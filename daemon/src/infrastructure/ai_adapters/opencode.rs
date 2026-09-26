use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::path::{Path, PathBuf};

pub struct OpenCodeAdapter;

impl Default for OpenCodeAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl OpenCodeAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AgentSessionAdapter for OpenCodeAdapter {
    fn tool_id(&self) -> &'static str {
        "opencode"
    }

    fn watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        vec![
            home.join(".local/share/opencode"),
            home.join(".config/ai.opencode.desktop"),
        ]
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy();
        s.contains("opencode.db")
    }

    fn parse_session_file(&self, _path: &Path, _tail: Option<&str>, _head: Option<&str>) -> Option<SessionParseResult> {
        let home = std::env::var("HOME").ok().map(PathBuf::from)?;
        self.query_external_store(&home)
    }

    fn scan_active_files(&self, home: &Path, max_age_ms: u64, sink: &mut Vec<ActiveSessionDescriptor>) {
        let now = current_epoch_ms();
        let db_path = home.join(".local/share/opencode/opencode.db");
        if let Ok(meta) = db_path.metadata() {
            if let Ok(mtime) = meta.modified() {
                let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                if now.saturating_sub(epoch) < max_age_ms {
                    sink.push(ActiveSessionDescriptor {
                        path: db_path,
                        mtime: epoch,
                        size: meta.len(),
                    });
                }
            }
        }
    }

    fn find_candidate_session_files(&self, _home: &Path, _sink: &mut Vec<PathBuf>) {
        // OpenCode tracks session state via its internal SQLite database
    }

    fn query_external_store(&self, home: &Path) -> Option<SessionParseResult> {
        let db_path = home.join(".local/share/opencode/opencode.db");
        if !db_path.exists() {
            return None;
        }

        let uri = format!("file:{}?mode=ro", db_path.to_string_lossy());
        let output = std::process::Command::new("sqlite3")
            .arg(&uri)
            .arg("SELECT model, tokens_input, tokens_output, time_updated FROM session_v2 ORDER BY time_updated DESC LIMIT 1;")
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
        if parts.len() < 4 {
            return None;
        }

        let raw_model = parts[0].trim();
        let tokens_in: u64 = parts[1].trim().parse().unwrap_or(0);
        let tokens_out: u64 = parts[2].trim().parse().unwrap_or(0);
        let time_updated: u64 = parts[3].trim().parse().unwrap_or(0);

        let model_id = if raw_model.starts_with('{') {
            serde_json::from_str::<serde_json::Value>(raw_model)
                .ok()
                .and_then(|v| v.get("id").and_then(|id| id.as_str().map(|s| s.to_string())))
                .unwrap_or_else(|| raw_model.to_string())
        } else {
            raw_model.to_string()
        };

        let now_epoch = current_epoch_ms();
        let is_completed = now_epoch.saturating_sub(time_updated) >= 3_000;

        Some(SessionParseResult {
            model_id,
            tool_source: "opencode".to_string(),
            tokens: Some(tokens_in + tokens_out),
            is_turn_completed: is_completed,
            timestamp_ms: Some(time_updated),
        })
    }
}

fn current_epoch_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
