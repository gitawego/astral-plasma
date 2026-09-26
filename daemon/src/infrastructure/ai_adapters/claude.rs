use super::{extract_model_from_json_line, extract_tokens_from_tail, scan_dirs_recursive, scan_jsonl_recursive};
use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::path::{Path, PathBuf};

pub struct ClaudeAdapter;

impl Default for ClaudeAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl ClaudeAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AgentSessionAdapter for ClaudeAdapter {
    fn tool_id(&self) -> &'static str {
        "claude"
    }

    fn watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        let mut dirs = vec![
            home.join(".claude"),
            home.join(".claude/sessions"),
            home.join(".claude/projects"),
        ];

        for root in &[home.join(".claude/sessions"), home.join(".claude/projects")] {
            if root.exists() && root.is_dir() {
                scan_dirs_recursive(root, 3, &mut |p| dirs.push(p.to_path_buf()));
            }
        }

        dirs
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy().to_lowercase();
        s.contains("claude")
            && (s.ends_with(".jsonl") || s.ends_with(".log"))
            && !s.contains("/cli/log/")
            && !s.contains("/cli/log")
    }

    fn parse_session_file(&self, path: &Path, tail: Option<&str>, head: Option<&str>) -> Option<SessionParseResult> {
        let mut model_prov = None;

        // 1. Scan tail lines in reverse
        if let Some(tail_str) = tail {
            for line in tail_str.lines().rev() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    model_prov = Some((m, if prov.is_empty() { "claude".to_string() } else { prov }));
                    break;
                }
            }
        }

        // 2. Scan head lines
        if model_prov.is_none() {
            if let Some(head_str) = head {
                for line in head_str.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() {
                        continue;
                    }
                    if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                        model_prov = Some((m, if prov.is_empty() { "claude".to_string() } else { prov }));
                        break;
                    }
                }
            }
        }

        let (model, prov) = model_prov.unwrap_or_else(|| ("claude-3-7-sonnet".to_string(), "claude".to_string()));
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

        let claude_projects = home.join(".claude/projects");
        if claude_projects.exists() {
            scan_jsonl_recursive(&claude_projects, 3, &mut check_file);
        }
        let claude_sessions = home.join(".claude/sessions");
        if claude_sessions.exists() {
            scan_jsonl_recursive(&claude_sessions, 2, &mut check_file);
        }
        let claude_history = home.join(".claude/history.jsonl");
        if claude_history.exists() {
            check_file(&claude_history);
        }
    }

    fn find_candidate_session_files(&self, home: &Path, sink: &mut Vec<PathBuf>) {
        let mut add_file = |p: &Path| sink.push(p.to_path_buf());

        let claude_projects = home.join(".claude/projects");
        if claude_projects.exists() {
            scan_jsonl_recursive(&claude_projects, 3, &mut add_file);
        }
        let claude_sessions = home.join(".claude/sessions");
        if claude_sessions.exists() {
            scan_jsonl_recursive(&claude_sessions, 2, &mut add_file);
        }
        let claude_history = home.join(".claude/history.jsonl");
        if claude_history.exists() {
            sink.push(claude_history);
        }
    }

    fn read_default_settings(&self, _home: &Path) -> Option<(String, String)> {
        Some(("claude-3-7-sonnet".to_string(), "claude".to_string()))
    }

    fn check_turn_completed(&self, tail: &str, _path: &Path) -> bool {
        for line in tail.lines().rev() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
                let msg = v.get("message");
                let stop_reason = v.get("stop_reason")
                    .or_else(|| msg.and_then(|m| m.get("stop_reason")))
                    .and_then(|s| s.as_str());
                if let Some(reason) = stop_reason {
                    if reason == "end_turn" || reason == "stop" {
                        return true;
                    } else if reason == "tool_use" {
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
