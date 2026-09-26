use super::{extract_model_from_json_line, extract_tokens_from_tail};
use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::path::{Path, PathBuf};

pub struct IdeAdapter;

impl Default for IdeAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl IdeAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AgentSessionAdapter for IdeAdapter {
    fn tool_id(&self) -> &'static str {
        "ide"
    }

    fn watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        vec![
            home.join(".config/Cursor"),
            home.join(".config/Windsurf"),
        ]
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy().to_lowercase();
        s.contains("cursor") || s.contains("windsurf")
    }

    fn parse_session_file(&self, path: &Path, tail: Option<&str>, _head: Option<&str>) -> Option<SessionParseResult> {
        let s = path.to_string_lossy().to_lowercase();
        let default_tool = if s.contains("cursor") { "cursor" } else { "windsurf" };

        let mut model_prov = None;
        if let Some(tail_str) = tail {
            for line in tail_str.lines().rev() {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                if let Some((m, prov)) = extract_model_from_json_line(trimmed) {
                    model_prov = Some((m, if prov.is_empty() { default_tool.to_string() } else { prov }));
                    break;
                }
            }
        }

        let (model, prov) = model_prov.unwrap_or_else(|| {
            if default_tool == "cursor" {
                ("cursor".to_string(), "cursor".to_string())
            } else {
                ("windsurf".to_string(), "windsurf".to_string())
            }
        });

        let tokens = tail.and_then(extract_tokens_from_tail);

        Some(SessionParseResult {
            model_id: model,
            tool_source: prov,
            tokens,
            is_turn_completed: true,
            timestamp_ms: None,
        })
    }

    fn scan_active_files(&self, _home: &Path, _max_age_ms: u64, _sink: &mut Vec<ActiveSessionDescriptor>) {
        // Cursor & Windsurf do not emit standardized rolling JSONL streams
    }

    fn find_candidate_session_files(&self, _home: &Path, _sink: &mut Vec<PathBuf>) {
        // Cursor & Windsurf do not emit standardized rolling JSONL streams
    }
}
