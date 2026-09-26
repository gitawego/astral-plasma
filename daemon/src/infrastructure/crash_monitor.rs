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
    })
}

impl CrashMonitor {
    /// Queries the system for the most recent application or service crashes.
    pub fn scan_recent_crashes(limit: usize) -> Vec<CrashIncident> {
        let mut incidents = Vec::new();

        // 1. Check coredumpctl
        if let Ok(output) = Command::new("coredumpctl").args(["list", "-n", &limit.to_string(), "--no-legend", "--no-pager"]).output() {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines() {
                    if let Some(incident) = parse_coredumpctl_line(line) {
                        incidents.push(incident);
                    }
                }
            }
        }

        // 2. If no coredumps found, check high severity systemd journal errors
        if incidents.is_empty() {
            if let Ok(output) = Command::new("journalctl").args(["-p", "3", "-xb", "-n", &limit.to_string(), "--no-pager"]).output() {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    for (idx, line) in stdout.lines().enumerate() {
                        let trimmed = line.trim();
                        if trimmed.is_empty() {
                            continue;
                        }
                        // Check if line indicates segfault or trap
                        if trimmed.contains("segfault") || trimmed.contains("traps") || trimmed.contains("failed") || trimmed.contains("error") {
                            let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                            let proc_guess = trimmed.split(':').next().unwrap_or("system").trim().to_string();

                            incidents.push(CrashIncident {
                                id: format!("jrn_{}_{}", now, idx),
                                process_name: proc_guess,
                                pid: None,
                                signal: None,
                                timestamp_ms: now,
                                summary: trimmed.chars().take(120).collect(),
                                log_snippet: trimmed.to_string(),
                            });

                            if incidents.len() >= limit {
                                break;
                            }
                        }
                    }
                }
            }
        }

        incidents
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
    }

    #[test]
    fn test_parse_coredump_line_without_trailing_size_column() {
        // Older rows without the SIZE column must still parse.
        let row = "Sat 2026-09-26 13:12:03 CEST 3102965 1000 1000 SIGQUIT present /usr/bin/some-app";
        let inc = parse_coredumpctl_line(row).expect("row must parse");
        assert_eq!(inc.process_name, "some-app");
        assert_eq!(inc.signal.as_deref(), Some("SIGQUIT"));
    }

    #[test]
    fn test_parse_coredump_line_rejects_malformed_rows() {
        assert!(parse_coredumpctl_line("garbage").is_none());
        assert!(parse_coredumpctl_line("").is_none());
        // SIG token without executable column after corefile status -> skip.
        assert!(parse_coredumpctl_line("Sat 2026-09-26 13:12:03 CEST 1 1 1 SIGQUIT present").is_none());
    }

    #[test]
    fn test_scan_recent_crashes_does_not_panic() {
        let crashes = CrashMonitor::scan_recent_crashes(5);
        // On clean test runners crashes might be empty or contain journal lines, but must not panic
        println!("Found {} crash incidents", crashes.len());
    }
}
