use crate::domain::assistant::{
    AssistantEvent, ChatSession, ChatSessionSummary, CrashIncident, HarnessInfo, SkillDescriptor,
};
use crate::infrastructure::assistant_harness::hermes_harness::HermesHarness;
use crate::infrastructure::assistant_harness::pi_harness::PiHarness;
use crate::infrastructure::assistant_harness::runtime_provisioner::RuntimeProvisioner;
use crate::infrastructure::assistant_harness::HarnessBackend;
use crate::infrastructure::crash_monitor::CrashMonitor;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::mpsc;

pub struct AssistantService {
    pi: Arc<PiHarness>,
    hermes: Arc<HermesHarness>,
    sessions_dir: Option<PathBuf>,
}

impl Default for AssistantService {
    fn default() -> Self {
        Self::new()
    }
}

impl AssistantService {
    pub fn new() -> Self {
        Self {
            pi: Arc::new(PiHarness::new()),
            hermes: Arc::new(HermesHarness::new()),
            sessions_dir: None,
        }
    }

    pub fn with_sessions_dir(dir: PathBuf) -> Self {
        Self {
            pi: Arc::new(PiHarness::new()),
            hermes: Arc::new(HermesHarness::new()),
            sessions_dir: Some(dir),
        }
    }

    /// Returns list of available harnesses and their status
    pub fn list_harnesses(&self) -> Vec<HarnessInfo> {
        vec![self.pi.harness_info(), self.hermes.harness_info()]
    }

    /// Returns the active harness according to preference
    pub fn get_harness(&self, preference: Option<&str>) -> HarnessBackend {
        let pref = preference.unwrap_or("pi").to_lowercase();
        if pref == "hermes" && self.hermes.is_available() {
            HarnessBackend::Hermes((*self.hermes).clone())
        } else {
            HarnessBackend::Pi((*self.pi).clone())
        }
    }

    /// Discovers all available skills
    pub fn list_skills(&self) -> Vec<SkillDescriptor> {
        PiHarness::scan_skills()
    }

    /// Reads configured default provider and model from harness
    pub fn get_defaults(&self) -> (Option<String>, Option<String>) {
        PiHarness::read_pi_defaults()
    }

    /// Persists default provider and model to harness settings
    pub fn set_defaults(&self, provider: &str, model: &str) -> Result<(), String> {
        PiHarness::set_pi_defaults(provider, model)
    }

    /// Lists supported/discovered providers and their available models
    pub fn list_providers(&self) -> Vec<crate::infrastructure::assistant_harness::pi_harness::ProviderDescriptor> {
        PiHarness::list_providers_and_models()
    }

    /// Syncs built-in skills to ~/.agents/skills
    pub fn sync_skills_to_user_agents(&self) -> Result<usize, String> {
        let home = std::env::var("HOME").map_err(|_| "HOME not set".to_string())?;
        let target_dir = Path::new(&home).join(".agents/skills");
        std::fs::create_dir_all(&target_dir).map_err(|e| format!("Failed to create ~/.agents/skills: {}", e))?;

        let skills_src = Path::new("/mnt/data/workspace/astral-plasma/skills");
        if !skills_src.is_dir() {
            return Ok(0);
        }

        let mut linked = 0;
        if let Ok(entries) = std::fs::read_dir(skills_src) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.is_dir() && p.join("SKILL.md").exists() {
                    let name = p.file_name().unwrap_or_default();
                    let link_path = target_dir.join(name);
                    let _ = std::fs::remove_file(&link_path);
                    let _ = std::fs::remove_dir_all(&link_path);
                    #[cfg(unix)]
                    if std::os::unix::fs::symlink(&p, &link_path).is_ok() {
                        linked += 1;
                    }
                }
            }
        }

        Ok(linked)
    }

    /// Executes an approved command with optional sudo / pkexec elevation
    pub async fn execute_command(&self, command: &str, run_with_sudo: bool) -> Result<(String, String, i32), String> {
        let mut parts = vec!["-c".to_string()];
        let full_cmd = if run_with_sudo && !command.trim().starts_with("pkexec") && !command.trim().starts_with("sudo") {
            format!("pkexec {}", command)
        } else {
            command.to_string()
        };
        parts.push(full_cmd);

        let output = tokio::process::Command::new("bash")
            .args(&parts)
            .output()
            .await
            .map_err(|e| format!("Failed to execute command: {}", e))?;

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        let code = output.status.code().unwrap_or(-1);

        Ok((stdout, stderr, code))
    }

    /// Scans recent crashes
    pub fn get_recent_crashes(&self, limit: usize) -> Vec<CrashIncident> {
        CrashMonitor::scan_recent_crashes(limit)
    }

    /// Streams assistant response for a prompt
    pub async fn stream_turn(
        &self,
        prompt: &str,
        harness_pref: Option<&str>,
        provider: Option<&str>,
        model: Option<&str>,
        sender: mpsc::Sender<AssistantEvent>,
    ) -> Result<(), String> {
        let harness = self.get_harness(harness_pref);
        harness.run_turn(prompt, provider, model, sender).await
    }

    /// Ensures runtime provisioning and package installation
    pub fn ensure_provisioning(&self) -> Result<(), String> {
        if let Some(pi_bin) = RuntimeProvisioner::locate_pi() {
            RuntimeProvisioner::ensure_critical_packages(&pi_bin)?;
        }
        let _ = self.sync_skills_to_user_agents();
        Ok(())
    }

    pub fn sanitize_id(id: &str) -> Result<String, String> {
        let trimmed = id.trim();
        if trimmed.is_empty() {
            return Err("Session id cannot be empty".to_string());
        }
        if trimmed.contains("..") || trimmed.contains('/') || trimmed.contains('\\') {
            return Err("Invalid characters in session id".to_string());
        }
        if !trimmed.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-') {
            return Err("Session id must contain only alphanumeric characters, underscores, or hyphens".to_string());
        }
        Ok(trimmed.to_string())
    }

    pub fn sessions_path(&self) -> PathBuf {
        if let Some(ref dir) = self.sessions_dir {
            dir.clone()
        } else {
            crate::domain::branding::data_dir().join("assistant/sessions")
        }
    }

    pub fn active_session_path(&self) -> PathBuf {
        if let Some(ref dir) = self.sessions_dir {
            dir.join("active_session.json")
        } else {
            crate::domain::branding::data_dir().join("assistant/active_session.json")
        }
    }

    pub fn list_sessions(&self) -> Result<Vec<ChatSessionSummary>, String> {
        let dir = self.sessions_path();
        if !dir.exists() {
            return Ok(Vec::new());
        }

        let mut summaries = Vec::new();
        let entries = std::fs::read_dir(&dir).map_err(|e| format!("Failed to read sessions dir: {}", e))?;

        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() && path.extension().and_then(|ext| ext.to_str()) == Some("json") {
                let file_name = path.file_stem().and_then(|s| s.to_str()).unwrap_or_default();
                if file_name == "active_session" {
                    continue;
                }
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(session) = serde_json::from_str::<ChatSession>(&content) {
                        let last_preview = session.messages.iter().rev()
                            .find(|m| !m.content.trim().is_empty())
                            .map(|m| {
                                let c = m.content.trim();
                                if c.len() > 80 {
                                    format!("{}...", &c[..80])
                                } else {
                                    c.to_string()
                                }
                            })
                            .unwrap_or_default();

                        summaries.push(ChatSessionSummary {
                            id: session.id,
                            title: session.title,
                            created_at: session.created_at,
                            updated_at: session.updated_at,
                            message_count: session.messages.len(),
                            last_preview,
                        });
                    }
                }
            }
        }

        summaries.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
        Ok(summaries)
    }

    pub fn get_session(&self, id: &str) -> Result<ChatSession, String> {
        let clean_id = Self::sanitize_id(id)?;
        let path = self.sessions_path().join(format!("{}.json", clean_id));
        if !path.exists() {
            return Err(format!("Session '{}' not found", clean_id));
        }
        let content = std::fs::read_to_string(&path).map_err(|e| format!("Failed to read session file: {}", e))?;
        let session = serde_json::from_str::<ChatSession>(&content).map_err(|e| format!("Failed to parse session json: {}", e))?;
        Ok(session)
    }

    pub fn save_session(&self, session: &ChatSession) -> Result<(), String> {
        let clean_id = Self::sanitize_id(&session.id)?;
        let dir = self.sessions_path();
        std::fs::create_dir_all(&dir).map_err(|e| format!("Failed to create sessions directory: {}", e))?;

        let target_path = dir.join(format!("{}.json", clean_id));
        let tmp_path = dir.join(format!("{}.json.tmp.{}", clean_id, std::process::id()));

        let json = serde_json::to_string_pretty(session).map_err(|e| format!("Serialization error: {}", e))?;
        std::fs::write(&tmp_path, json).map_err(|e| format!("Failed to write tmp session file: {}", e))?;
        std::fs::rename(&tmp_path, &target_path).map_err(|e| format!("Failed to rename session file: {}", e))?;

        let _ = self.set_active_session_id(&clean_id);
        Ok(())
    }

    pub fn delete_session(&self, id: &str) -> Result<bool, String> {
        let clean_id = Self::sanitize_id(id)?;
        let path = self.sessions_path().join(format!("{}.json", clean_id));
        if !path.exists() {
            return Ok(false);
        }
        std::fs::remove_file(&path).map_err(|e| format!("Failed to delete session file: {}", e))?;

        if let Some(active) = self.get_active_session_id() {
            if active == clean_id {
                let _ = self.clear_active_session();
            }
        }
        Ok(true)
    }

    pub fn get_active_session_id(&self) -> Option<String> {
        let path = self.active_session_path();
        if !path.exists() {
            return None;
        }
        let content = std::fs::read_to_string(&path).ok()?;
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
            val.get("active_session_id").and_then(|v| v.as_str()).map(|s| s.to_string())
        } else {
            let trimmed = content.trim();
            if !trimmed.is_empty() {
                Some(trimmed.to_string())
            } else {
                None
            }
        }
    }

    pub fn set_active_session_id(&self, id: &str) -> Result<(), String> {
        let clean_id = Self::sanitize_id(id)?;
        let path = self.active_session_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("Failed to create directory for active session: {}", e))?;
        }
        let val = serde_json::json!({ "active_session_id": clean_id });
        let tmp = path.with_extension(format!("json.tmp.{}", std::process::id()));
        std::fs::write(&tmp, serde_json::to_string(&val).unwrap()).map_err(|e| format!("Failed to write active session: {}", e))?;
        std::fs::rename(&tmp, &path).map_err(|e| format!("Failed to update active session: {}", e))?;
        Ok(())
    }

    pub fn clear_active_session(&self) -> Result<(), String> {
        let path = self.active_session_path();
        if path.exists() {
            let _ = std::fs::remove_file(path);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_list_harnesses() {
        let svc = AssistantService::new();
        let harnesses = svc.list_harnesses();
        assert_eq!(harnesses.len(), 2);
        assert!(harnesses.iter().any(|h| h.id == "pi"));
        assert!(harnesses.iter().any(|h| h.id == "hermes"));
    }

    #[test]
    fn test_sync_skills() {
        let svc = AssistantService::new();
        let res = svc.sync_skills_to_user_agents();
        assert!(res.is_ok());
    }

    #[tokio::test]
    async fn test_execute_safe_command() {
        let svc = AssistantService::new();
        let (stdout, _stderr, code) = svc.execute_command("echo 'Astral Plasma AI Assistant'", false).await.unwrap();
        assert_eq!(code, 0);
        assert!(stdout.contains("Astral Plasma AI Assistant"));
    }
}
