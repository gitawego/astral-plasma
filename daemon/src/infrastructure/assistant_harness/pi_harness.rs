use super::runtime_provisioner::RuntimeProvisioner;
use crate::domain::assistant::{AssistantEvent, HarnessInfo, SkillDescriptor, ToolCallProposal};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ProviderDescriptor {
    pub id: String,
    pub name: String,
    pub models: Vec<String>,
}

#[derive(Clone)]
pub struct PiHarness {
    executable: Option<PathBuf>,
}

impl Default for PiHarness {
    fn default() -> Self {
        Self::new()
    }
}

impl PiHarness {
    pub fn new() -> Self {
        let exe = RuntimeProvisioner::locate_pi();
        Self { executable: exe }
    }

    /// Discovers all skills from astral-plasma skills directory and ~/.agents/skills
    pub fn scan_skills() -> Vec<SkillDescriptor> {
        let mut skills = Vec::new();
        let mut seen = std::collections::HashSet::new();

        // 1. Built-in astral skills
        let current_dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let mut builtin_paths = vec![
            current_dir.join("skills"),
            current_dir.join("../skills"),
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../skills"),
            PathBuf::from("/usr/share/astral-plasma/skills"),
            PathBuf::from("/mnt/data/workspace/astral-plasma/skills"),
        ];

        if let Ok(exe) = std::env::current_exe() {
            if let Some(bin_dir) = exe.parent() {
                builtin_paths.push(bin_dir.join("../skills"));
                builtin_paths.push(bin_dir.join("../../skills"));
                builtin_paths.push(bin_dir.join("../share/astral-plasma/skills"));
            }
        }

        for bdir in builtin_paths {
            if bdir.is_dir() {
                if let Ok(entries) = std::fs::read_dir(&bdir) {
                    for entry in entries.flatten() {
                        let path = entry.path();
                        if path.is_dir() {
                            let skill_file = path.join("SKILL.md");
                            if skill_file.exists() {
                                let name = path.file_name().unwrap_or_default().to_string_lossy().to_string();
                                if seen.insert(name.clone()) {
                                    let desc = Self::extract_description(&skill_file).unwrap_or_else(|| {
                                        format!("Linux system skill: {}", name)
                                    });
                                    skills.push(SkillDescriptor {
                                        name,
                                        description: desc,
                                        path: path.to_string_lossy().to_string(),
                                        source: "astral-builtin".to_string(),
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. User ~/.agents/skills
        let home = std::env::var("HOME").unwrap_or_default();
        if !home.is_empty() {
            let agents_skills = Path::new(&home).join(".agents/skills");
            if agents_skills.is_dir() {
                if let Ok(entries) = std::fs::read_dir(&agents_skills) {
                    for entry in entries.flatten() {
                        let path = entry.path();
                        if path.is_dir() {
                            let skill_file = path.join("SKILL.md");
                            if skill_file.exists() {
                                let name = path.file_name().unwrap_or_default().to_string_lossy().to_string();
                                if seen.insert(name.clone()) {
                                    let desc = Self::extract_description(&skill_file).unwrap_or_else(|| {
                                        format!("Agent skill: {}", name)
                                    });
                                    skills.push(SkillDescriptor {
                                        name,
                                        description: desc,
                                        path: path.to_string_lossy().to_string(),
                                        source: "user-agent".to_string(),
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        skills
    }

    fn extract_description(skill_file: &Path) -> Option<String> {
        let content = std::fs::read_to_string(skill_file).ok()?;
        let mut in_frontmatter = false;

        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed == "---" {
                if in_frontmatter {
                    break;
                } else {
                    in_frontmatter = true;
                    continue;
                }
            }
            if in_frontmatter && trimmed.starts_with("description:") {
                let desc = trimmed.trim_start_matches("description:").trim().trim_matches('"');
                return Some(desc.to_string());
            }
        }

        None
    }
}

impl PiHarness {
    pub fn harness_id(&self) -> &'static str {
        "pi"
    }

    pub fn display_name(&self) -> &'static str {
        "Pi Coding & System Agent"
    }

    pub fn is_available(&self) -> bool {
        self.executable.is_some()
    }

    pub fn harness_info(&self) -> HarnessInfo {
        let path_str = self.executable.as_ref().map(|p| p.to_string_lossy().to_string());
        HarnessInfo {
            id: "pi".to_string(),
            name: "Pi Agent".to_string(),
            is_available: self.executable.is_some(),
            version: Some("0.87.1".to_string()),
            is_default: true,
            path: path_str,
        }
    }

    pub fn list_skills(&self) -> Vec<SkillDescriptor> {
        Self::scan_skills()
    }

    pub fn read_pi_defaults() -> (Option<String>, Option<String>) {
        let home = std::env::var("HOME").unwrap_or_default();
        if home.is_empty() {
            return (None, None);
        }
        let settings_path = Path::new(&home).join(".pi/agent/settings.json");
        if let Ok(content) = std::fs::read_to_string(&settings_path) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                let p = v.get("defaultProvider").and_then(|x| x.as_str()).map(|s| s.to_string());
                let m = v.get("defaultModel").and_then(|x| x.as_str()).map(|s| s.to_string());
                return (p, m);
            }
        }
        (None, None)
    }

    pub fn set_pi_defaults(provider: &str, model: &str) -> Result<(), String> {
        let home = std::env::var("HOME").map_err(|_| "HOME not set".to_string())?;
        let dir = Path::new(&home).join(".pi/agent");
        std::fs::create_dir_all(&dir).map_err(|e| format!("Failed to create ~/.pi/agent: {}", e))?;
        let settings_path = dir.join("settings.json");

        let mut v: serde_json::Value = if settings_path.exists() {
            let content = std::fs::read_to_string(&settings_path).unwrap_or_else(|_| "{}".to_string());
            serde_json::from_str(&content).unwrap_or_else(|_| serde_json::json!({}))
        } else {
            serde_json::json!({})
        };

        if let Some(map) = v.as_object_mut() {
            map.insert("defaultProvider".to_string(), serde_json::Value::String(provider.to_string()));
            map.insert("defaultModel".to_string(), serde_json::Value::String(model.to_string()));
        }

        let formatted = serde_json::to_string_pretty(&v).map_err(|e| format!("JSON serialize error: {}", e))?;
        std::fs::write(&settings_path, formatted).map_err(|e| format!("Failed to write settings.json: {}", e))?;
        Ok(())
    }

    pub fn list_providers_and_models() -> Vec<ProviderDescriptor> {
        let mut known_models: std::collections::BTreeMap<&str, Vec<String>> = std::collections::BTreeMap::new();
        known_models.insert("opencode-go", vec![]);
        known_models.insert("minimax", vec![]);
        known_models.insert("minimax-cn", vec![]);
        known_models.insert("gemini", vec![
            "gemini-2.5-flash".to_string(),
            "gemini-2.5-pro".to_string(),
            "gemini-2.0-flash".to_string(),
            "gemini-1.5-pro".to_string(),
        ]);
        known_models.insert("claude", vec![
            "claude-3-7-sonnet".to_string(),
            "claude-3-5-sonnet".to_string(),
            "claude-3-5-haiku".to_string(),
        ]);
        known_models.insert("deepseek", vec![
            "deepseek-chat".to_string(),
            "deepseek-reasoner".to_string(),
        ]);
        known_models.insert("openai", vec![
            "gpt-4o".to_string(),
            "gpt-4o-mini".to_string(),
            "o3-mini".to_string(),
            "o1".to_string(),
        ]);
        known_models.insert("ollama", vec![
            "llama3.2".to_string(),
            "mistral".to_string(),
            "deepseek-r1".to_string(),
            "qwen2.5-coder".to_string(),
        ]);

        let home = std::env::var("HOME").unwrap_or_default();
        if !home.is_empty() {
            let ms_path = Path::new(&home).join(".pi/agent/models-store.json");
            if let Ok(content) = std::fs::read_to_string(&ms_path) {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(obj) = val.as_object() {
                        for (k, v) in obj {
                            if let Some(models_arr) = v.get("models").and_then(|m| m.as_array()) {
                                let ids: Vec<String> = models_arr
                                    .iter()
                                    .filter_map(|m| m.get("id").and_then(|id| id.as_str()).map(|s| s.to_string()))
                                    .collect();
                                if !ids.is_empty() {
                                    if let Some(existing) = known_models.get_mut(k.as_str()) {
                                        *existing = ids;
                                    } else {
                                        known_models.insert(Box::leak(k.clone().into_boxed_str()), ids);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        let display_name = |id: &str| -> String {
            match id {
                "opencode-go" => "OpenCode Go".to_string(),
                "gemini" => "Google Gemini".to_string(),
                "claude" => "Anthropic Claude".to_string(),
                "deepseek" => "DeepSeek".to_string(),
                "openai" => "OpenAI".to_string(),
                "minimax" => "MiniMax".to_string(),
                "minimax-cn" => "MiniMax CN".to_string(),
                "ollama" => "Local Ollama".to_string(),
                other => other.to_string(),
            }
        };

        let priority = ["opencode-go", "gemini", "claude", "deepseek", "openai", "minimax", "minimax-cn", "ollama"];
        let mut result = Vec::new();
        for &pid in &priority {
            if let Some(models) = known_models.remove(pid) {
                result.push(ProviderDescriptor {
                    id: pid.to_string(),
                    name: display_name(pid),
                    models,
                });
            }
        }
        for (pid, models) in known_models {
            result.push(ProviderDescriptor {
                id: pid.to_string(),
                name: display_name(pid),
                models,
            });
        }

        result
    }

    pub fn parse_pi_json_event(line: &str) -> Option<Vec<AssistantEvent>> {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with("[pi-") {
            return None;
        }

        if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
            let event_type = v.get("type").and_then(|t| t.as_str()).unwrap_or("");
            match event_type {
                "message_update" => {
                    if let Some(ame) = v.get("assistantMessageEvent") {
                        let ame_type = ame.get("type").and_then(|t| t.as_str()).unwrap_or("");
                        if ame_type == "text_delta" {
                            if let Some(delta) = ame.get("delta").and_then(|d| d.as_str()) {
                                return Some(vec![AssistantEvent::TextChunk(delta.to_string())]);
                            }
                        } else if ame_type == "toolcall_end" {
                            if let Some(tc) = ame.get("toolCall") {
                                let name = tc.get("name").and_then(|n| n.as_str()).unwrap_or("");
                                if name == "bash" {
                                    if let Some(cmd_str) = tc.get("arguments").and_then(|a| a.get("command")).and_then(|c| c.as_str()) {
                                        let (dangerous, sudo) = ToolCallProposal::assess_safety(cmd_str);
                                        if dangerous || sudo {
                                            let prop = ToolCallProposal {
                                                id: tc.get("id").and_then(|i| i.as_str()).unwrap_or("tool_call").to_string(),
                                                tool_name: "bash".to_string(),
                                                command: cmd_str.to_string(),
                                                args: vec![],
                                                is_dangerous: dangerous,
                                                requires_sudo: sudo,
                                            };
                                            return Some(vec![AssistantEvent::ToolProposal(prop)]);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                "tool_execution_start" => {
                    let tool_name = v.get("toolName").and_then(|n| n.as_str()).unwrap_or("tool");
                    if let Some(cmd) = v.get("args").and_then(|a| a.get("command")).and_then(|c| c.as_str()) {
                        return Some(vec![AssistantEvent::TextChunk(format!("*Inspecting: `{}`...*\n\n", cmd))]);
                    } else {
                        return Some(vec![AssistantEvent::TextChunk(format!("*Running {}...*\n\n", tool_name))]);
                    }
                }
                "auto_retry_end" => {
                    let success = v.get("success").and_then(|s| s.as_bool()).unwrap_or(true);
                    if !success {
                        let err = v.get("finalError").and_then(|e| e.as_str()).unwrap_or("Model request failed");
                        return Some(vec![AssistantEvent::Error(format!("Request failed: {}", err))]);
                    }
                }
                "agent_end" => {
                    if let Some(msgs) = v.get("messages").and_then(|m| m.as_array()) {
                        for msg in msgs {
                            if let Some(err) = msg.get("errorMessage").and_then(|e| e.as_str()) {
                                return Some(vec![AssistantEvent::Error(err.to_string())]);
                            }
                        }
                    }
                }
                _ => {}
            }
            return None;
        }

        // Fallback for non-JSON lines (e.g. error line or plain output)
        if !trimmed.starts_with('{') {
            Some(vec![AssistantEvent::TextChunk(format!("{}\n", trimmed))])
        } else {
            None
        }
    }

    pub async fn run_turn(
        &self,
        prompt: &str,
        provider: Option<&str>,
        model: Option<&str>,
        event_sender: mpsc::Sender<AssistantEvent>,
    ) -> Result<(), String> {
        let exe = match &self.executable {
            Some(e) => e,
            None => {
                let _ = event_sender.send(AssistantEvent::Error("Pi binary is not available".to_string())).await;
                return Err("Pi binary is not available".to_string());
            }
        };

        let mut cmd = Command::new(exe);
        cmd.arg("-p");
        cmd.arg(prompt);
        cmd.arg("--mode").arg("json");

        if let Some(p) = provider {
            if !p.is_empty() {
                cmd.arg("--provider").arg(p);
            }
        }
        if let Some(m) = model {
            if !m.is_empty() {
                cmd.arg("--model").arg(m);
            }
        }

        // Add built-in skills directory
        let home = std::env::var("HOME").unwrap_or_default();
        if !home.is_empty() {
            let user_skills = format!("{}/.agents/skills", home);
            if Path::new(&user_skills).is_dir() {
                cmd.arg("--skill").arg(user_skills);
            }
        }

        // Explicitly disconnect stdin to prevent Node.js / Pi readline hanging on open pipes
        cmd.stdin(Stdio::null());
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());

        let mut child = cmd.spawn().map_err(|e| format!("Failed to spawn Pi: {}", e))?;

        let stdout = child.stdout.take().ok_or("Failed to capture Pi stdout")?;
        let stderr = child.stderr.take().ok_or("Failed to capture Pi stderr")?;

        let sender_clone = event_sender.clone();
        let stdout_handle = tokio::spawn(async move {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                if let Some(events) = Self::parse_pi_json_event(&line) {
                    for ev in events {
                        let _ = sender_clone.send(ev).await;
                    }
                }
            }
        });

        let err_sender = event_sender.clone();
        let stderr_handle = tokio::spawn(async move {
            let mut reader = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let trimmed = line.trim();
                // Filter out extension/plugin debug notices
                if !trimmed.is_empty() && !trimmed.starts_with("[pi-") && (trimmed.contains("error") || trimmed.contains("Error") || trimmed.contains("fatal") || trimmed.contains("Fatal")) {
                    let _ = err_sender.send(AssistantEvent::TextChunk(format!("⚠️ {}\n", trimmed))).await;
                }
            }
        });

        let status = child.wait().await.map_err(|e| format!("Pi execution error: {}", e))?;
        let _ = stdout_handle.await;
        let _ = stderr_handle.await;

        if status.success() {
            let _ = event_sender.send(AssistantEvent::TurnCompleted { total_tokens: None }).await;
            Ok(())
        } else {
            let err_msg = format!("Pi exited with status: {}", status);
            let _ = event_sender.send(AssistantEvent::Error(err_msg.clone())).await;
            Err(err_msg)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pi_harness_scan_skills() {
        let skills = PiHarness::scan_skills();
        assert!(!skills.is_empty(), "Should discover skills from repository or ~/.agents/skills");
        let has_diag = skills.iter().any(|s| s.name == "system-diagnostics");
        assert!(has_diag, "Should discover system-diagnostics skill");
    }

    #[test]
    fn test_pi_harness_info() {
        let harness = PiHarness::new();
        let info = harness.harness_info();
        assert_eq!(info.id, "pi");
        assert!(info.is_default);
    }

    #[test]
    fn test_parse_pi_json_text_delta() {
        let line = r#"{"type":"message_update","usage":{"inputTokens":10},"assistantMessageEvent":{"type":"text_delta","contentIndex":1,"delta":"Hello world!"}}"#;
        let events = PiHarness::parse_pi_json_event(line).expect("Should parse event");
        assert_eq!(events.len(), 1);
        match &events[0] {
            AssistantEvent::TextChunk(text) => assert_eq!(text, "Hello world!"),
            _ => panic!("Expected TextChunk"),
        }
    }

    #[test]
    fn test_parse_pi_json_tool_execution() {
        let line = r#"{"type":"tool_execution_start","toolCallId":"call_123","toolName":"bash","args":{"command":"df -h"}}"#;
        let events = PiHarness::parse_pi_json_event(line).expect("Should parse event");
        assert_eq!(events.len(), 1);
        match &events[0] {
            AssistantEvent::TextChunk(text) => assert!(text.contains("df -h")),
            _ => panic!("Expected TextChunk with command"),
        }
    }

    #[test]
    fn test_parse_pi_json_error() {
        let line = r#"{"type":"auto_retry_end","success":false,"attempt":3,"finalError":"Model unavailable"}"#;
        let events = PiHarness::parse_pi_json_event(line).expect("Should parse event");
        assert_eq!(events.len(), 1);
        match &events[0] {
            AssistantEvent::Error(err) => assert!(err.contains("Model unavailable")),
            _ => panic!("Expected Error"),
        }
    }

    #[test]
    fn test_parse_pi_json_tool_proposal_dangerous() {
        let line = r#"{"type":"message_update","assistantMessageEvent":{"type":"toolcall_end","toolCall":{"id":"call_danger","name":"bash","arguments":{"command":"sudo systemctl restart NetworkManager"}}}}"#;
        let events = PiHarness::parse_pi_json_event(line).expect("Should parse event");
        assert_eq!(events.len(), 1);
        match &events[0] {
            AssistantEvent::ToolProposal(prop) => {
                assert!(prop.is_dangerous);
                assert!(prop.requires_sudo);
                assert_eq!(prop.command, "sudo systemctl restart NetworkManager");
            }
            _ => panic!("Expected ToolProposal"),
        }
    }
}
