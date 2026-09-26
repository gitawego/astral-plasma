use super::{extract_model_from_json_line, extract_tokens_from_tail, scan_dirs_recursive, scan_jsonl_recursive};
use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::path::{Path, PathBuf};

pub struct OmpAdapter;

impl Default for OmpAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl OmpAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AgentSessionAdapter for OmpAdapter {
    fn tool_id(&self) -> &'static str {
        "omp"
    }

    fn watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        let mut dirs = vec![home.join(".omp/agent/sessions")];
        let sroot = home.join(".omp/agent/sessions");
        if sroot.exists() && sroot.is_dir() {
            scan_dirs_recursive(&sroot, 3, &mut |p| dirs.push(p.to_path_buf()));
        }
        dirs
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy().to_lowercase();
        (s.contains(".omp") || s.contains("/omp/")) && s.ends_with(".jsonl")
    }

    fn parse_session_file(&self, path: &Path, tail: Option<&str>, head: Option<&str>) -> Option<SessionParseResult> {
        let mut model_prov = None;

        if let Some(tail_str) = tail {
            for line in tail_str.lines().rev() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    model_prov = Some((m, if prov.is_empty() { "omp".to_string() } else { prov }));
                    break;
                }
            }
        }

        if model_prov.is_none() {
            if let Some(head_str) = head {
                for line in head_str.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() {
                        continue;
                    }
                    if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                        model_prov = Some((m, if prov.is_empty() { "omp".to_string() } else { prov }));
                        break;
                    }
                }
            }
        }

        let (model, prov) = model_prov.unwrap_or_else(|| ("omp-agent".to_string(), "omp".to_string()));
        let tokens = tail.and_then(extract_tokens_from_tail);
        let is_completed = tail.map(|t| self.check_turn_completed(t, path)).unwrap_or(true);

        Some(SessionParseResult {
            model_id: model,
            tool_source: prov,
            tokens,
            is_turn_completed: is_completed,
            timestamp_ms: None,
        })
    }

    fn scan_active_files(&self, home: &Path, max_age_ms: u64, sink: &mut Vec<ActiveSessionDescriptor>) {
        let now = current_epoch_ms();
        let omp_sessions = home.join(".omp/agent/sessions");
        if omp_sessions.exists() {
            scan_jsonl_recursive(&omp_sessions, 3, &mut |p| {
                if let Ok(meta) = p.metadata() {
                    if let Ok(mtime) = meta.modified() {
                        let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                        if now.saturating_sub(epoch) < max_age_ms {
                            sink.push(ActiveSessionDescriptor {
                                path: p.to_path_buf(),
                                mtime: epoch,
                                size: meta.len(),
                            });
                        }
                    }
                }
            });
        }
    }

    fn find_candidate_session_files(&self, home: &Path, sink: &mut Vec<PathBuf>) {
        let omp_sessions = home.join(".omp/agent/sessions");
        if let Ok(dirs) = std::fs::read_dir(&omp_sessions) {
            for d in dirs.flatten() {
                let p = d.path();
                if p.is_dir() {
                    if let Ok(files) = std::fs::read_dir(&p) {
                        for f in files.flatten() {
                            let fp = f.path();
                            if fp.extension().and_then(|ext| ext.to_str()) == Some("jsonl") {
                                sink.push(fp);
                            }
                        }
                    }
                } else if p.extension().and_then(|ext| ext.to_str()) == Some("jsonl") {
                    sink.push(p);
                }
            }
        }
    }

    fn check_turn_completed(&self, tail: &str, _path: &Path) -> bool {
        for line in tail.lines().rev() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
                let msg = v.get("message");
                let stop_reason = v.get("stopReason")
                    .or_else(|| v.get("stop_reason"))
                    .or_else(|| msg.and_then(|m| m.get("stopReason").or_else(|| m.get("stop_reason"))))
                    .and_then(|s| s.as_str());
                if let Some(reason) = stop_reason {
                    if reason == "stop" || reason == "end_turn" {
                        return true;
                    } else if reason == "toolUse" || reason == "tool_use" {
                        return false;
                    }
                }
                let role = v.get("role")
                    .or_else(|| msg.and_then(|m| m.get("role")))
                    .and_then(|r| r.as_str());
                if role == Some("user") {
                    return false;
                }
            }
        }
        true
    }
}

fn current_epoch_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
