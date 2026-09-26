use crate::domain::ports::{ActiveSessionDescriptor, AgentSessionAdapter, SessionParseResult};
use std::path::{Path, PathBuf};

pub struct DshAdapter;

impl Default for DshAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl DshAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl AgentSessionAdapter for DshAdapter {
    fn tool_id(&self) -> &'static str {
        "dsh"
    }

    fn watch_directories(&self, home: &Path) -> Vec<PathBuf> {
        vec![
            home.join(".dsh"),
            home.join(".dsh/sessions"),
        ]
    }

    fn can_handle_file(&self, path: &Path) -> bool {
        let s = path.to_string_lossy();
        s.contains(".dsh") && (s.ends_with("session.lock") || s.ends_with(".jsonl"))
    }

    fn parse_session_file(&self, _path: &Path, _tail: Option<&str>, _head: Option<&str>) -> Option<SessionParseResult> {
        let home = std::env::var("HOME").ok().map(PathBuf::from);
        let (model, prov) = home.as_deref().and_then(|h| self.read_default_settings(h))
            .unwrap_or_else(|| ("DSH Agent".to_string(), "dsh".to_string()));

        Some(SessionParseResult {
            model_id: model,
            tool_source: prov,
            tokens: None,
            is_turn_completed: true,
            timestamp_ms: None,
        })
    }

    fn scan_active_files(&self, home: &Path, max_age_ms: u64, sink: &mut Vec<ActiveSessionDescriptor>) {
        let now = current_epoch_ms();
        let dsh_sessions = home.join(".dsh/sessions");
        if dsh_sessions.exists() {
            if let Ok(dirs) = std::fs::read_dir(&dsh_sessions) {
                for d in dirs.flatten() {
                    let p = d.path();
                    if p.is_dir() {
                        if let Ok(sub) = std::fs::read_dir(&p) {
                            for s in sub.flatten() {
                                let sp = s.path();
                                if sp.is_dir() {
                                    let lock = sp.join("session.lock");
                                    if let Ok(meta) = lock.metadata() {
                                        if let Ok(mtime) = meta.modified() {
                                            let epoch = mtime.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis() as u64;
                                            if now.saturating_sub(epoch) < max_age_ms {
                                                sink.push(ActiveSessionDescriptor {
                                                    path: lock,
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
                }
            }
        }
    }

    fn find_candidate_session_files(&self, home: &Path, sink: &mut Vec<PathBuf>) {
        let dsh_sessions = home.join(".dsh/sessions");
        if dsh_sessions.exists() {
            if let Ok(dirs) = std::fs::read_dir(&dsh_sessions) {
                for d in dirs.flatten() {
                    let p = d.path();
                    if p.is_dir() {
                        if let Ok(sub) = std::fs::read_dir(&p) {
                            for s in sub.flatten() {
                                let sp = s.path();
                                if sp.is_dir() {
                                    let lock = sp.join("session.lock");
                                    if lock.exists() {
                                        sink.push(lock);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    fn read_default_settings(&self, home: &Path) -> Option<(String, String)> {
        let settings_path = home.join(".dsh/settings.yaml");
        if let Ok(content) = std::fs::read_to_string(&settings_path) {
            let mut in_agent_default = false;
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with("agent-default-model:") {
                    in_agent_default = true;
                    continue;
                }
                if in_agent_default {
                    if !line.starts_with(' ') && !line.starts_with('\t') {
                        break;
                    }
                    if let Some(m) = trimmed.strip_prefix("model:") {
                        let m_clean = m.trim().trim_matches('"').trim_matches('\'');
                        if !m_clean.is_empty() {
                            return Some((m_clean.to_string(), "dsh".to_string()));
                        }
                    }
                }
            }
        }
        None
    }
}

fn current_epoch_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
