use super::{extract_model_from_json_line, extract_tokens_from_tail, scan_dirs_recursive, scan_jsonl_recursive};
use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::path::{Path, PathBuf};

pub struct ZCodeAdapter;

impl Default for ZCodeAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl ZCodeAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AgentSessionAdapter for ZCodeAdapter {
    fn tool_id(&self) -> &'static str {
        "zcode"
    }

    fn watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        let mut dirs = vec![
            home.join(".zcode/cli/rollout"),
            home.join(".zcode/cli/agents"),
            home.join(".zcode/cli/db"),
            home.join(".zcode/v2"),
        ];

        let agents_dir = home.join(".zcode/cli/agents");
        if agents_dir.exists() && agents_dir.is_dir() {
            scan_dirs_recursive(&agents_dir, 3, &mut |p| dirs.push(p.to_path_buf()));
        }

        dirs
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy();
        s.contains("zcode")
            && (s.ends_with(".jsonl") || s.ends_with(".sqlite") || s.ends_with(".sqlite-wal"))
    }

    fn parse_session_file(&self, path: &Path, tail: Option<&str>, head: Option<&str>) -> Option<SessionParseResult> {
        let s = path.to_string_lossy();
        if s.contains("/cli/log/") || s.contains("/cli/log") {
            return None;
        }

        let mut model_prov = None;

        if let Some(tail_str) = tail {
            for line in tail_str.lines().rev() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    model_prov = Some((m, if prov.is_empty() { "zcode".to_string() } else { prov }));
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
                        model_prov = Some((m, if prov.is_empty() { "zcode".to_string() } else { prov }));
                        break;
                    }
                }
            }
        }

        let home = std::env::var("HOME").ok().map(PathBuf::from);
        let (model, prov) = model_prov
            .or_else(|| home.as_deref().and_then(|h| self.read_default_settings(h)))
            .unwrap_or_else(|| ("MiniMax-M3".to_string(), "zcode".to_string()));

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

        let zcode_rollout = home.join(".zcode/cli/rollout");
        if zcode_rollout.exists() {
            if let Ok(files) = std::fs::read_dir(&zcode_rollout) {
                for f in files.flatten() {
                    let fp = f.path();
                    if fp.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                        check_file(&fp);
                    }
                }
            }
        }

        let zcode_agents = home.join(".zcode/cli/agents");
        if zcode_agents.exists() {
            scan_jsonl_recursive(&zcode_agents, 3, &mut |p| {
                if p.ends_with("transcript.jsonl") {
                    check_file(p);
                }
            });
        }
    }

    fn find_candidate_session_files(&self, home: &Path, sink: &mut Vec<PathBuf>) {
        let zcode_rollout = home.join(".zcode/cli/rollout");
        if zcode_rollout.exists() {
            if let Ok(files) = std::fs::read_dir(&zcode_rollout) {
                for f in files.flatten() {
                    let fp = f.path();
                    if fp.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                        sink.push(fp);
                    }
                }
            }
        }

        let zcode_agents = home.join(".zcode/cli/agents");
        if zcode_agents.exists() {
            scan_jsonl_recursive(&zcode_agents, 3, &mut |p| {
                if p.ends_with("transcript.jsonl") {
                    sink.push(p.to_path_buf());
                }
            });
        }
    }

    fn query_external_store(&self, home: &Path) -> Option<SessionParseResult> {
        let db_path = home.join(".zcode/cli/db/db.sqlite");
        if !db_path.exists() {
            return None;
        }

        let uri = format!("file:{}?mode=ro", db_path.to_string_lossy());
        let output = std::process::Command::new("sqlite3")
            .arg(&uri)
            .arg("SELECT model_id, status, started_at, coalesce(completed_at, started_at), output_tokens, finish_reason FROM model_usage ORDER BY started_at DESC LIMIT 1;")
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let trimmed = stdout.trim();
        if trimmed.is_empty() {
            return None;
        }

        let parts: Vec<&str> = trimmed.split('|').collect();
        if parts.len() < 5 {
            return None;
        }

        let raw_model = parts[0].trim();
        let status = parts[1].trim();
        let time_updated: u64 = parts[3].trim().parse().unwrap_or(0);
        let tokens: u64 = parts[4].trim().parse().unwrap_or(0);
        let finish_reason = parts.get(5).map(|s| s.trim()).unwrap_or("");

        let model_id = if let Some(slash_pos) = raw_model.rfind('/') {
            raw_model[slash_pos + 1..].to_string()
        } else {
            raw_model.to_string()
        };

        let is_completed = (status == "completed" && (finish_reason == "stop" || finish_reason.is_empty()))
            || status == "error"
            || status == "cancelled";

        Some(SessionParseResult {
            model_id,
            tool_source: "zcode".to_string(),
            tokens: Some(tokens),
            is_turn_completed: is_completed,
            timestamp_ms: Some(time_updated),
        })
    }

    fn read_default_settings(&self, home: &Path) -> Option<(String, String)> {
        let bot_state_path = home.join(".zcode/v2/bot-state.v3.json");
        if let Ok(content) = std::fs::read_to_string(&bot_state_path) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(bots) = v.get("bots").and_then(|b| b.as_object()) {
                    let mut best_model: Option<(String, u64)> = None;
                    for (_, bot) in bots {
                        let updated = bot.get("updatedAt").and_then(|u| u.as_u64()).unwrap_or(0);
                        if let Some(model) = bot.get("draftOptions")
                            .and_then(|d| d.get("modelSelection"))
                            .and_then(|m| m.get("modelId"))
                            .and_then(|s| s.as_str())
                        {
                            if best_model.as_ref().map(|(_, t)| updated > *t).unwrap_or(true) {
                                best_model = Some((model.to_string(), updated));
                            }
                        }
                    }
                    if let Some((m, _)) = best_model {
                        return Some((m, "zcode".to_string()));
                    }
                }
            }
        }

        let config_path = home.join(".zcode/v2/config.json");
        if let Ok(content) = std::fs::read_to_string(&config_path) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(providers) = v.get("provider").or_else(|| v.get("providers")).and_then(|p| p.as_object()) {
                    for (_, p) in providers {
                        if let Some(models) = p.get("models").and_then(|m| m.as_object()) {
                            for (model_name, _) in models {
                                if !model_name.is_empty() {
                                    return Some((model_name.clone(), "zcode".to_string()));
                                }
                            }
                        }
                    }
                }
            }
        }

        Some(("MiniMax-M3".to_string(), "zcode".to_string()))
    }

    fn check_turn_completed(&self, tail: &str, _path: &Path) -> bool {
        for line in tail.lines().rev() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
                if let Some(resp) = v.get("response") {
                    if let Some(finish_reason) = resp.get("finishReason").and_then(|f| f.as_str()) {
                        if finish_reason == "stop" {
                            return true;
                        } else if finish_reason == "tool-calls" {
                            return false;
                        }
                    }
                }
                let event = v.get("event").and_then(|e| e.as_str()).unwrap_or("");
                if event == "turn.completed" || event == "turn.failed" {
                    return true;
                }
                if event == "turn.started" || event == "model.request.started" || event == "tool.call.started" {
                    return false;
                }
                if let Some(ctx) = v.get("context") {
                    if let Some(finish_reason) = ctx.get("finishReason").and_then(|f| f.as_str()) {
                        if finish_reason == "stop" {
                            return true;
                        } else if finish_reason == "tool-calls" {
                            return false;
                        }
                    }
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
