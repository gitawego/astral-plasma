use super::{extract_model_from_json_line, extract_tokens_from_tail};
use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::path::{Path, PathBuf};

pub struct AntigravityAdapter;

impl Default for AntigravityAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl AntigravityAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AgentSessionAdapter for AntigravityAdapter {
    fn tool_id(&self) -> &'static str {
        "antigravity"
    }

    fn watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        let mut dirs = Vec::new();
        let brain = home.join(".gemini/antigravity/brain");
        if brain.exists() && brain.is_dir() {
            dirs.push(brain.clone());
            if let Ok(entries) = std::fs::read_dir(&brain) {
                for e in entries.flatten() {
                    let logs = e.path().join(".system_generated/logs");
                    if logs.exists() && logs.is_dir() {
                        dirs.push(logs);
                    }
                }
            }
        }
        dirs
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy();
        s.contains("antigravity") && s.ends_with("transcript.jsonl")
    }

    fn parse_session_file(&self, path: &Path, tail: Option<&str>, _head: Option<&str>) -> Option<SessionParseResult> {
        let tail_str = tail?;
        let mut resolved_model = None;

        // 1. Scan JSON lines in reverse
        for line in tail_str.lines().rev() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Some((m, _)) = extract_model_from_json_line(trimmed) {
                resolved_model = Some(m);
                break;
            }
        }

        // 2. Scan for Model Selection text in planner steps
        if resolved_model.is_none() {
            for line in tail_str.lines().rev() {
                if let Some(pos) = line.find("Model Selection` from None to ") {
                    let rem = &line[pos + 30..];
                    let candidate = rem.split(['`', '\n', '\r']).next().unwrap_or("Gemini Flash 3.8").trim();
                    let clean = candidate.trim_end_matches('.').split('(').next().unwrap_or(candidate).trim();
                    if !clean.is_empty() && clean.len() < 30 && !clean.contains('\\') && !clean.contains('{') && !clean.contains("let ") {
                        let final_name = if clean == "Gemini Flash" {
                            "Gemini Flash 3.8".to_string()
                        } else if clean == "Gemini Pro" {
                            "Gemini Pro 3.8".to_string()
                        } else {
                            clean.to_string()
                        };
                        resolved_model = Some(final_name);
                        break;
                    }
                }
            }
        }

        // 3. Fallback to state pbtxt or default
        if resolved_model.is_none() {
            resolved_model = read_antigravity_state_model().or_else(|| Some("Gemini Flash 3.8".to_string()));
        }

        let model = resolved_model?;
        let tokens = extract_tokens_from_tail(tail_str);
        let is_completed = self.check_turn_completed(tail_str, path);

        Some(SessionParseResult {
            model_id: model,
            tool_source: "gemini".to_string(),
            tokens,
            is_turn_completed: is_completed,
            timestamp_ms: None,
        })
    }

    fn scan_active_files(&self, home: &Path, max_age_ms: u64, sink: &mut Vec<ActiveSessionDescriptor>) {
        let now = current_epoch_ms();
        let brain = home.join(".gemini/antigravity/brain");
        if let Ok(dirs) = std::fs::read_dir(&brain) {
            for d in dirs.flatten() {
                let p = d.path();
                if p.is_dir() {
                    let log_p = p.join(".system_generated/logs/transcript.jsonl");
                    if let Ok(meta) = log_p.metadata() {
                        if let Ok(mtime) = meta.modified() {
                            let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                            if now.saturating_sub(epoch) < max_age_ms {
                                sink.push(ActiveSessionDescriptor {
                                    path: log_p,
                                    mtime: epoch,
                                    size: meta.len(),
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    fn find_candidate_session_files(&self, home: &Path, sink: &mut Vec<PathBuf>) {
        let brain = home.join(".gemini/antigravity/brain");
        if let Ok(dirs) = std::fs::read_dir(&brain) {
            for d in dirs.flatten() {
                let p = d.path();
                if p.is_dir() {
                    let log_p = p.join(".system_generated/logs/transcript.jsonl");
                    if log_p.exists() {
                        sink.push(log_p);
                    }
                }
            }
        }
    }

    fn read_default_settings(&self, _home: &Path) -> Option<(String, String)> {
        let model = read_antigravity_state_model().unwrap_or_else(|| "Gemini Flash 3.8".to_string());
        Some((model, "gemini".to_string()))
    }

    fn check_turn_completed(&self, tail: &str, _path: &Path) -> bool {
        for line in tail.lines().rev() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
                let typ = v.get("type").and_then(|t| t.as_str()).unwrap_or("");
                let src = v.get("source").and_then(|s| s.as_str()).unwrap_or("");
                if typ == "USER_INPUT" {
                    return false; // User just asked, agent is in-flight
                }
                if typ == "PLANNER_RESPONSE" || (src == "MODEL" && typ == "GENERIC") {
                    let has_tools = v.get("tool_calls")
                        .and_then(|tc| tc.as_array())
                        .map(|a| !a.is_empty())
                        .unwrap_or(false);
                    if has_tools {
                        return false; // Tool call in progress
                    }
                    if typ == "PLANNER_RESPONSE" {
                        return true; // Final response with no tool calls -> turn complete!
                    }
                }
            }
        }
        true
    }
}

pub fn read_antigravity_state_model() -> Option<String> {
    let home = std::env::var("HOME").ok()?;
    let pbtxt_path = PathBuf::from(home).join(".gemini/antigravity/antigravity_state.pbtxt");
    if let Ok(content) = std::fs::read_to_string(&pbtxt_path) {
        for line in content.lines() {
            if line.contains("last_selected_agent_model:") {
                if let Some(val) = line.split(':').nth(1) {
                    let trimmed = val.trim();
                    if trimmed.contains("M318") {
                        return Some("Gemini Flash 3.8".to_string());
                    } else if trimmed.contains("PRO") {
                        return Some("Gemini Pro 3.8".to_string());
                    } else if trimmed.contains("25") || trimmed.contains("2_5") {
                        return Some("Gemini Flash 2.5".to_string());
                    }
                }
            }
        }
    }
    None
}

fn current_epoch_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
