use super::{extract_model_from_json_line, extract_tokens_from_tail, scan_dirs_recursive, scan_jsonl_recursive};
use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::path::{Path, PathBuf};

pub struct CodexAdapter;

impl Default for CodexAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl CodexAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AgentSessionAdapter for CodexAdapter {
    fn tool_id(&self) -> &'static str {
        "codex"
    }

    fn watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        let mut dirs = vec![
            home.join(".codex"),
            home.join(".codex/sessions"),
        ];

        let sroot = home.join(".codex/sessions");
        if sroot.exists() && sroot.is_dir() {
            scan_dirs_recursive(&sroot, 4, &mut |p| dirs.push(p.to_path_buf()));
        }

        dirs
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy().to_lowercase();
        s.contains(".codex") && s.ends_with(".jsonl")
    }

    fn parse_session_file(&self, path: &Path, tail: Option<&str>, head: Option<&str>) -> Option<SessionParseResult> {
        let mut model_prov = None;

        // 1. Tail parse
        if let Some(tail_str) = tail {
            for line in tail_str.lines().rev() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    model_prov = Some((m, if prov.is_empty() { "openai".to_string() } else { prov }));
                    break;
                }
            }
        }

        // 2. Head parse
        if model_prov.is_none() {
            if let Some(head_str) = head {
                for line in head_str.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() {
                        continue;
                    }
                    if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                        model_prov = Some((m, if prov.is_empty() { "openai".to_string() } else { prov }));
                        break;
                    }
                }
            }
        }

        // 3. Config fallback
        let home = std::env::var("HOME").ok().map(PathBuf::from);
        let (model, prov) = model_prov.or_else(|| home.as_deref().and_then(|h| self.read_default_settings(h)))
            .unwrap_or_else(|| ("gpt-5.5".to_string(), "openai".to_string()));

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
        let mut check_file = |p: &Path| {
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
        };

        let codex_sessions = home.join(".codex/sessions");
        if codex_sessions.exists() {
            scan_jsonl_recursive(&codex_sessions, 4, &mut check_file);
        }
        let codex_history = home.join(".codex/history.jsonl");
        if codex_history.exists() {
            check_file(&codex_history);
        }
    }

    fn find_candidate_session_files(&self, home: &Path, sink: &mut Vec<PathBuf>) {
        let mut add_file = |p: &Path| sink.push(p.to_path_buf());

        let codex_sessions = home.join(".codex/sessions");
        if codex_sessions.exists() {
            scan_jsonl_recursive(&codex_sessions, 4, &mut add_file);
        }
        let codex_history = home.join(".codex/history.jsonl");
        if codex_history.exists() {
            sink.push(codex_history);
        }
    }

    fn read_default_settings(&self, home: &Path) -> Option<(String, String)> {
        let config_path = home.join(".codex/config.toml");
        if let Ok(content) = std::fs::read_to_string(&config_path) {
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with("model ") || trimmed.starts_with("model=") {
                    if let Some(val) = trimmed.split('=').nth(1) {
                        let clean = val.trim().trim_matches('"').trim_matches('\'').trim();
                        if !clean.is_empty() {
                            return Some((clean.to_string(), "openai".to_string()));
                        }
                    }
                }
            }
        }
        Some(("gpt-5.5".to_string(), "openai".to_string()))
    }

    fn check_turn_completed(&self, tail: &str, _path: &Path) -> bool {
        for line in tail.lines().rev() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
                let typ = v.get("type").and_then(|t| t.as_str()).unwrap_or("");
                if typ == "task_complete" || typ == "turn_complete" {
                    return true;
                }
                if let Some(payload) = v.get("payload") {
                    let p_type = payload.get("type").and_then(|t| t.as_str()).unwrap_or("");
                    if p_type == "task_complete" || p_type == "turn_complete" {
                        return true;
                    }
                }
                let finish_reason = v.get("finish_reason")
                    .or_else(|| v.get("payload").and_then(|p| p.get("finish_reason")))
                    .and_then(|f| f.as_str());
                if finish_reason == Some("stop") {
                    return true;
                } else if finish_reason == Some("tool_calls") {
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
