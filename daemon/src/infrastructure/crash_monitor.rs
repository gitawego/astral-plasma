use crate::domain::assistant::CrashIncident;
use std::process::Command;

pub struct CrashMonitor;

/// Parses a single `coredumpctl list --no-legend` row into a [`CrashIncident`].
///
/// Row layout (systemd 262):
/// `TIME(4 tokens) PID UID GID SIG COREFILE EXE [SIZE]`
///
/// Newer systemd builds append a trailing `SIZE` column (e.g. `48K`), so the
/// executable must be located relative to the `SIG`/`COREFILE` columns — never
/// assumed to be the last token. Returns `None` for rows that don't match the
/// coredump layout.
fn parse_coredumpctl_line(line: &str) -> Option<CrashIncident> {
    let parts: Vec<&str> = line.split_whitespace().collect();

    // Locate the signal column (first SIG-prefixed token after TIME/PID/UID/GID).
    let sig_idx = parts.iter().skip(4).position(|p| p.starts_with("SIG"))? + 4;
    // PID sits exactly three columns before SIG (PID UID GID SIG).
    let pid = parts.get(sig_idx.checked_sub(3)?).and_then(|p| p.parse::<u32>().ok())?;
    // EXE sits two columns after SIG (SIG COREFILE EXE), with SIZE trailing (if any).
    let exe_path = parts.get(sig_idx + 2)?;
    let signal = parts[sig_idx].to_string();
    let proc_name = std::path::Path::new(exe_path)
        .file_name()?
        .to_string_lossy()
        .to_string();

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;

    Some(CrashIncident {
        id: format!("core_{}", pid),
        process_name: proc_name.clone(),
        pid: Some(pid),
        signal: Some(signal.clone()),
        timestamp_ms: now,
        summary: format!("Application '{}' terminated due to {}", proc_name, signal),
        log_snippet: line.trim().to_string(),
        count: 1,
    })
}

/// Deduplicates crash incidents by process name, aggregating occurrences into `count`
/// and keeping the newest incident's metadata.
pub fn deduplicate_incidents(raw: Vec<CrashIncident>, limit: usize) -> Vec<CrashIncident> {
    let mut deduped: Vec<CrashIncident> = Vec::new();

    for inc in raw {
        let is_system_or_empty = inc.process_name.is_empty() || inc.process_name == "system";

        if let Some(existing) = deduped.iter_mut().find(|item| {
            if is_system_or_empty {
                item.summary == inc.summary
            } else {
                item.process_name == inc.process_name
            }
        }) {
            existing.count += inc.count.max(1);
            if let Some(ref sig) = existing.signal {
                existing.summary = format!(
                    "Application '{}' terminated due to {} ({} crashes)",
                    existing.process_name, sig, existing.count
                );
            } else {
                existing.summary = format!(
                    "Application '{}' crashed ({} times)",
                    existing.process_name, existing.count
                );
            }
        } else if deduped.len() < limit {
            let mut new_entry = inc;
            if new_entry.count == 0 {
                new_entry.count = 1;
            }
            deduped.push(new_entry);
        }
    }

    deduped
}

impl CrashMonitor {
    /// Queries the system for the most recent application or service crashes,
    /// deduplicated by process name with repeat crash counts aggregated.
    pub fn scan_recent_crashes(limit: usize) -> Vec<CrashIncident> {
        let mut raw_incidents = Vec::new();
        let scan_limit = (limit * 10).max(50);

        // 1. Check coredumpctl (-r: newest first)
        let coredump_output = Command::new("coredumpctl")
            .args(["list", "-r", "-n", &scan_limit.to_string(), "--no-legend", "--no-pager"])
            .output();

        let (coredump_success, coredump_stdout, is_reversed) = match coredump_output {
            Ok(ref out) if out.status.success() => (true, String::from_utf8_lossy(&out.stdout).to_string(), true),
            _ => {
                // Fallback: try without -r (older systemd)
                if let Ok(fallback_out) = Command::new("coredumpctl")
                    .args(["list", "-n", &scan_limit.to_string(), "--no-legend", "--no-pager"])
                    .output()
                {
                    if fallback_out.status.success() {
                        (true, String::from_utf8_lossy(&fallback_out.stdout).to_string(), false)
                    } else {
                        (false, String::new(), false)
                    }
                } else {
                    (false, String::new(), false)
                }
            }
        };

        if coredump_success {
            let lines: Vec<&str> = if is_reversed {
                coredump_stdout.lines().collect()
            } else {
                coredump_stdout.lines().rev().collect()
            };

            for line in lines {
                if let Some(incident) = parse_coredumpctl_line(line) {
                    raw_incidents.push(incident);
                }
            }
        }

        // 2. If no coredumps found, check high severity systemd journal errors
        if raw_incidents.is_empty() {
            if let Ok(output) = Command::new("journalctl")
                .args(["-p", "3", "-xb", "-r", "-n", &scan_limit.to_string(), "--no-pager"])
                .output()
            {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    for (idx, line) in stdout.lines().enumerate() {
                        let trimmed = line.trim();
                        if trimmed.is_empty() {
                            continue;
                        }
                        if trimmed.contains("segfault") || trimmed.contains("traps") || trimmed.contains("failed") || trimmed.contains("error") {
                            let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                            let proc_guess = trimmed.split(':').next().unwrap_or("system").trim().to_string();

                            raw_incidents.push(CrashIncident {
                                id: format!("jrn_{}_{}", now, idx),
                                process_name: proc_guess,
                                pid: None,
                                signal: None,
                                timestamp_ms: now,
                                summary: trimmed.chars().take(120).collect(),
                                log_snippet: trimmed.to_string(),
                                count: 1,
                            });
                        }
                    }
                }
            }
        }

        deduplicate_incidents(raw_incidents, limit)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Real row captured from `coredumpctl list` (systemd 262, Arch):
    // TIME(4 tokens) PID UID GID SIG COREFILE EXE SIZE
    const REAL_ROW_WITH_SIZE: &str = "Sat 2026-09-26 13:12:03 CEST 3102965 1000 1000 SIGQUIT present /home/hlu/.local/share/Steam/compatibilitytools.d/GE-Proton10-34/files/bin/wine64-preloader 48K";

    #[test]
    fn test_parse_coredump_line_finds_exe_before_trailing_size_column() {
        let inc = parse_coredumpctl_line(REAL_ROW_WITH_SIZE)
            .expect("row must parse");
        assert_eq!(inc.process_name, "wine64-preloader");
        assert_eq!(inc.pid, Some(3102965));
        assert_eq!(inc.signal.as_deref(), Some("SIGQUIT"));
        assert!(inc.summary.contains("wine64-preloader"), "summary: {}", inc.summary);
        assert!(inc.summary.contains("SIGQUIT"), "summary: {}", inc.summary);
        assert!(!inc.summary.contains("48K"), "summary leaked SIZE column: {}", inc.summary);
        assert_eq!(inc.count, 1);
    }

    #[test]
    fn test_parse_coredump_line_without_trailing_size_column() {
        // Older rows without the SIZE column must still parse.
        let row = "Sat 2026-09-26 13:12:03 CEST 3102965 1000 1000 SIGQUIT present /usr/bin/some-app";
        let inc = parse_coredumpctl_line(row).expect("row must parse");
        assert_eq!(inc.process_name, "some-app");
        assert_eq!(inc.signal.as_deref(), Some("SIGQUIT"));
        assert_eq!(inc.count, 1);
    }

    #[test]
    fn test_parse_coredump_line_rejects_malformed_rows() {
        assert!(parse_coredumpctl_line("garbage").is_none());
        assert!(parse_coredumpctl_line("").is_none());
        // SIG token without executable column after corefile status -> skip.
        assert!(parse_coredumpctl_line("Sat 2026-09-26 13:12:03 CEST 1 1 1 SIGQUIT present").is_none());
    }

    #[test]
    fn test_deduplicate_incidents_aggregates_same_process() {
        let incidents = vec![
            CrashIncident {
                id: "core_3885547".to_string(),
                process_name: "python3.14".to_string(),
                pid: Some(3885547),
                signal: Some("SIGSEGV".to_string()),
                timestamp_ms: 2000,
                summary: "Application 'python3.14' terminated due to SIGSEGV".to_string(),
                log_snippet: "snippet 2".to_string(),
                count: 1,
            },
            CrashIncident {
                id: "core_3114727".to_string(),
                process_name: "python3.14".to_string(),
                pid: Some(3114727),
                signal: Some("SIGSEGV".to_string()),
                timestamp_ms: 1000,
                summary: "Application 'python3.14' terminated due to SIGSEGV".to_string(),
                log_snippet: "snippet 1".to_string(),
                count: 1,
            },
        ];

        let deduped = deduplicate_incidents(incidents, 5);
        assert_eq!(deduped.len(), 1, "Duplicate process crashes must be merged into 1 incident");
        assert_eq!(deduped[0].process_name, "python3.14");
        assert_eq!(deduped[0].pid, Some(3885547), "Latest PID must be retained");
        assert_eq!(deduped[0].count, 2, "Crash count must be aggregated");
        assert!(deduped[0].summary.contains("2 crashes"), "Summary must reflect repeat crashes: {}", deduped[0].summary);
    }

    #[test]
    fn test_deduplicate_incidents_keeps_different_processes_separate() {
        let incidents = vec![
            CrashIncident {
                id: "core_3885547".to_string(),
                process_name: "python3.14".to_string(),
                pid: Some(3885547),
                signal: Some("SIGSEGV".to_string()),
                timestamp_ms: 2000,
                summary: "Application 'python3.14' terminated due to SIGSEGV".to_string(),
                log_snippet: "snippet py".to_string(),
                count: 1,
            },
            CrashIncident {
                id: "core_3102965".to_string(),
                process_name: "wine64-preloader".to_string(),
                pid: Some(3102965),
                signal: Some("SIGQUIT".to_string()),
                timestamp_ms: 1500,
                summary: "Application 'wine64-preloader' terminated due to SIGQUIT".to_string(),
                log_snippet: "snippet wine".to_string(),
                count: 1,
            },
            CrashIncident {
                id: "core_2561885".to_string(),
                process_name: "python3.14".to_string(),
                pid: Some(2561885),
                signal: Some("SIGABRT".to_string()),
                timestamp_ms: 1000,
                summary: "Application 'python3.14' terminated due to SIGABRT".to_string(),
                log_snippet: "snippet py old".to_string(),
                count: 1,
            },
        ];

        let deduped = deduplicate_incidents(incidents, 5);
        assert_eq!(deduped.len(), 2, "Distinct processes must be kept separate");
        assert_eq!(deduped[0].process_name, "python3.14");
        assert_eq!(deduped[0].count, 2, "Python crash count must be 2");
        assert_eq!(deduped[1].process_name, "wine64-preloader");
        assert_eq!(deduped[1].count, 1, "Wine crash count must be 1");
    }

    #[test]
    fn test_deduplicate_incidents_respects_limit() {
        let incidents = vec![
            CrashIncident {
                id: "1".into(),
                process_name: "app1".into(),
                pid: Some(1),
                signal: None,
                timestamp_ms: 10,
                summary: "crash 1".into(),
                log_snippet: "".into(),
                count: 1,
            },
            CrashIncident {
                id: "2".into(),
                process_name: "app2".into(),
                pid: Some(2),
                signal: None,
                timestamp_ms: 20,
                summary: "crash 2".into(),
                log_snippet: "".into(),
                count: 1,
            },
            CrashIncident {
                id: "3".into(),
                process_name: "app3".into(),
                pid: Some(3),
                signal: None,
                timestamp_ms: 30,
                summary: "crash 3".into(),
                log_snippet: "".into(),
                count: 1,
            },
        ];

        let deduped = deduplicate_incidents(incidents, 2);
        assert_eq!(deduped.len(), 2, "Deduplication must respect requested limit");
    }

    #[test]
    fn test_scan_recent_crashes_does_not_panic() {
        let crashes = CrashMonitor::scan_recent_crashes(5);
        // On clean test runners crashes might be empty or contain journal lines, but must not panic
        println!("Found {} crash incidents", crashes.len());
    }
}
