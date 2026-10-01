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
                    let p = e.path();
                    if p.is_dir() {
                        let sys = p.join(".system_generated");
                        if sys.is_dir() {
                            dirs.push(sys.clone());
                        }
                        let logs = p.join(".system_generated/logs");
                        if logs.exists() && logs.is_dir() {
                            dirs.push(logs);
                        }
                        let tasks = p.join(".system_generated/tasks");
                        if tasks.exists() && tasks.is_dir() {
                            dirs.push(tasks);
                        }
                        let steps = p.join(".system_generated/steps");
                        if steps.exists() && steps.is_dir() {
                            dirs.push(steps);
                        }
                        let msgs = p.join(".system_generated/messages");
                        if msgs.exists() && msgs.is_dir() {
                            dirs.push(msgs);
                        }
                    }
                }
            }
        }
        dirs
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy();
        s.contains("antigravity")
            && (s.ends_with("transcript.jsonl")
                || s.contains(".system_generated/tasks")
                || s.contains(".system_generated/steps")
                || s.contains(".system_generated/messages"))
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
                    if !log_p.exists() {
                        continue;
                    }

                    let mut latest_mtime = 0u64;
                    let mut latest_size = 0u64;

                    if let Ok(meta) = log_p.metadata() {
                        if let Ok(mtime) = meta.modified() {
                            let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                            latest_mtime = epoch;
                            latest_size = meta.len();
                        }
                    }

                    // Check if tasks in .system_generated/tasks were modified more recently
                    let tasks_dir = p.join(".system_generated/tasks");
                    if let Ok(entries) = std::fs::read_dir(&tasks_dir) {
                        for entry in entries.flatten() {
                            let ep = entry.path();
                            if ep.extension().map(|e| e == "log").unwrap_or(false) {
                                if let Ok(meta) = ep.metadata() {
                                    if let Ok(mtime) = meta.modified() {
                                        let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                                        if epoch > latest_mtime {
                                            latest_mtime = epoch;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if latest_mtime > 0 && now.saturating_sub(latest_mtime) < max_age_ms {
                        sink.push(ActiveSessionDescriptor {
                            path: log_p,
                            mtime: latest_mtime,
                            size: latest_size,
                        });
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

    fn check_turn_completed(&self, tail: &str, path: &Path) -> bool {
        let mut completed_tasks: std::collections::HashSet<String> = std::collections::HashSet::new();
        let mut pending_tasks: std::collections::HashSet<String> = std::collections::HashSet::new();
        let mut completed_subagents: std::collections::HashSet<String> = std::collections::HashSet::new();
        let mut pending_subagents: std::collections::HashSet<String> = std::collections::HashSet::new();

        // 1. Scan the tail forward to identify launched background tasks and subagents vs completions
        for line in tail.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
                let typ = v.get("type").and_then(|t| t.as_str()).unwrap_or("");
                let status = v.get("status").and_then(|s| s.as_str()).unwrap_or("");
                let content = v.get("content").and_then(|c| c.as_str()).unwrap_or("");

                // Task completion messages
                if let Some(pos) = content.find("Task id \"") {
                    let rem = &content[pos + 9..];
                    if let Some(end_quote) = rem.find('"') {
                        let task_id = &rem[..end_quote];
                        if content[pos..].contains("finished")
                            || content[pos..].contains("canceled")
                            || content[pos..].contains("cancelled")
                            || content[pos..].contains("failed")
                        {
                            completed_tasks.insert(task_id.to_string());
                        }
                    }
                }

                // Subagent completion messages (e.g. sender=<uuid>)
                if let Some(sender_pos) = content.find("sender=") {
                    let rem = &content[sender_pos + 7..];
                    let sender_id = rem.split_whitespace().next().unwrap_or("").trim_matches('"');
                    if !sender_id.contains("/task-") && !sender_id.is_empty() {
                        completed_subagents.insert(sender_id.to_string());
                    }
                }

                // Background task launched
                if status == "RUNNING" || status == "IN_PROGRESS" || content.contains("Tool is running as a background task with task id: ") {
                    if let Some(pos) = content.find("task id: ") {
                        let rem = &content[pos + 9..];
                        let task_id = rem.lines().next().unwrap_or("").trim();
                        if !task_id.is_empty() {
                            pending_tasks.insert(task_id.to_string());
                        }
                    }
                }

                // Subagent launched in PLANNER_RESPONSE tool_calls
                if typ == "PLANNER_RESPONSE" {
                    if let Some(tool_calls) = v.get("tool_calls").and_then(|tc| tc.as_array()) {
                        for tc in tool_calls {
                            if tc.get("name").and_then(|n| n.as_str()) == Some("invoke_subagent") {
                                if let Some(args) = tc.get("args") {
                                    if let Some(subs) = args.get("Subagents").and_then(|s| s.as_array()) {
                                        for sub in subs {
                                            if let Some(role) = sub.get("Role").and_then(|r| r.as_str()) {
                                                pending_subagents.insert(role.to_string());
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // If any launched background task has not completed, turn is in-flight!
        for task in &pending_tasks {
            if !completed_tasks.contains(task) {
                return false;
            }
        }

        // If subagents were invoked and no subagent response has arrived, turn is in-flight!
        if !pending_subagents.is_empty() && completed_subagents.is_empty() {
            return false;
        }

        // 2. Also check file system for recent task activity in .system_generated/tasks
        if let Some(conv) = find_conversation_dir(path) {
            let tasks_dir = conv.join(".system_generated/tasks");
            if tasks_dir.is_dir() {
                if let Ok(entries) = std::fs::read_dir(&tasks_dir) {
                    let now = current_epoch_ms();
                    for entry in entries.flatten() {
                        let p = entry.path();
                        if p.extension().map(|e| e == "log").unwrap_or(false) {
                            if let Ok(meta) = p.metadata() {
                                if let Ok(mtime) = meta.modified() {
                                    let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                                    // If a task log was written to in the last 20 seconds, a background task is actively running!
                                    if now.saturating_sub(epoch) < 20_000 {
                                        return false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. Scan the tail in reverse to evaluate the latest step
        for line in tail.lines().rev() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
                let typ = v.get("type").and_then(|t| t.as_str()).unwrap_or("");
                let src = v.get("source").and_then(|s| s.as_str()).unwrap_or("");
                let status = v.get("status").and_then(|s| s.as_str()).unwrap_or("");

                // Actively running or in-progress steps are definitely in-flight
                if status == "IN_PROGRESS" || status == "RUNNING" {
                    return false;
                }

                // If user just input, or a tool produced output (GENERIC / TOOL_RESULT), or system notification arrived, turn is in-flight
                if typ == "USER_INPUT" || typ == "GENERIC" || typ == "TOOL_RESULT" || typ == "SYSTEM_MESSAGE" || src == "TOOL_CALL" || src == "SYSTEM" {
                    return false;
                }

                if typ == "PLANNER_RESPONSE" {
                    let has_tools = v.get("tool_calls")
                        .and_then(|tc| tc.as_array())
                        .map(|a| !a.is_empty())
                        .unwrap_or(false);
                    if has_tools {
                        return false; // Tool call in progress
                    }
                    // A PLANNER_RESPONSE with no tool calls and no pending tasks indicates completion
                    return true;
                }
            }
        }
        true
    }
}

pub fn find_conversation_dir(path: &Path) -> Option<PathBuf> {
    let mut curr = path;
    while let Some(parent) = curr.parent() {
        if curr.file_name().map(|f| f == ".system_generated").unwrap_or(false) {
            return parent.to_path_buf().into();
        }
        curr = parent;
    }
    None
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
