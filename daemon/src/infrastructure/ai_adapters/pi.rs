use super::{extract_model_from_json_line, extract_tokens_from_tail, scan_dirs_recursive, scan_jsonl_recursive};
use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::path::{Path, PathBuf};

pub struct PiAdapter;

impl Default for PiAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl PiAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AgentSessionAdapter for PiAdapter {
    fn tool_id(&self) -> &'static str {
        "pi"
    }

    fn watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        let mut dirs = vec![home.join(".pi/agent/sessions")];
        let sroot = home.join(".pi/agent/sessions");
        if sroot.exists() && sroot.is_dir() {
            scan_dirs_recursive(&sroot, 3, &mut |p| dirs.push(p.to_path_buf()));
        }
        dirs
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy().to_lowercase();
        (s.contains(".pi") || s.contains("/pi/"))
            && s.ends_with(".jsonl")
            && !s.contains("context-mode")
            && !s.contains("stats-pid")
    }

    fn parse_session_file(&self, path: &Path, tail: Option<&str>, head: Option<&str>) -> Option<SessionParseResult> {
        let mut model_prov = None;

        // 1. Scan tail
        if let Some(tail_str) = tail {
            for line in tail_str.lines().rev() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    model_prov = Some((m, if prov.is_empty() { "pi".to_string() } else { prov }));
                    break;
                }
            }
        }

        // 2. Scan head (line 2 often contains session model header)
        if model_prov.is_none() {
            if let Some(head_str) = head {
                for line in head_str.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() {
                        continue;
                    }
                    if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                        model_prov = Some((m, if prov.is_empty() { "pi".to_string() } else { prov }));
                        break;
                    }
                }
            }
        }

        // 3. Fallback to settings
        let home = std::env::var("HOME").ok().map(PathBuf::from);
        let (model, prov) = model_prov
            .or_else(|| home.as_deref().and_then(|h| self.read_default_settings(h)))
            .unwrap_or_else(|| ("pi-agent".to_string(), "pi".to_string()));

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
        let pi_sessions = home.join(".pi/agent/sessions");
        if pi_sessions.exists() {
            scan_jsonl_recursive(&pi_sessions, 3, &mut |p| {
                let s = p.to_string_lossy();
                if s.contains("context-mode") || s.contains("stats-pid") {
                    return;
                }
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
        let pi_sessions = home.join(".pi/agent/sessions");
        if let Ok(dirs) = std::fs::read_dir(&pi_sessions) {
            for d in dirs.flatten() {
                let p = d.path();
                if p.is_dir() {
                    if let Ok(files) = std::fs::read_dir(&p) {
                        for f in files.flatten() {
                            let fp = f.path();
                            let s = fp.to_string_lossy();
                            if fp.extension().and_then(|ext| ext.to_str()) == Some("jsonl")
                                && !s.contains("context-mode")
                                && !s.contains("stats-pid")
                            {
                                sink.push(fp);
                            }
                        }
                    }
                } else if p.extension().and_then(|ext| ext.to_str()) == Some("jsonl") {
                    let s = p.to_string_lossy();
                    if !s.contains("context-mode") && !s.contains("stats-pid") {
                        sink.push(p);
                    }
                }
            }
        }
    }

    fn read_default_settings(&self, home: &Path) -> Option<(String, String)> {
        let settings_path = home.join(".pi/agent/settings.json");
        if let Ok(content) = std::fs::read_to_string(&settings_path) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                let model = v.get("defaultModel").and_then(|s| s.as_str())?;
                let prov = v.get("defaultProvider").and_then(|s| s.as_str()).unwrap_or("opencode-go");
                return Some((model.to_string(), prov.to_string()));
            }
        }
        None
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
