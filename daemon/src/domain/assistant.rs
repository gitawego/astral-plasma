use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum MessageRole {
    User,
    Assistant,
    System,
    Tool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AssistantMessage {
    pub id: String,
    pub role: MessageRole,
    pub content: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_calls: Option<Vec<ToolCallProposal>>,
    pub timestamp_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChatMessage {
    pub id: String,
    pub role: String,
    pub content: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub images: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub files: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tool_calls: Vec<ToolCallProposal>,
    pub timestamp: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChatSession {
    pub id: String,
    pub title: String,
    pub created_at: u64,
    pub updated_at: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub harness: Option<String>,
    #[serde(default)]
    pub messages: Vec<ChatMessage>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChatSessionSummary {
    pub id: String,
    pub title: String,
    pub created_at: u64,
    pub updated_at: u64,
    pub message_count: usize,
    pub last_preview: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ToolCallProposal {
    pub id: String,
    pub tool_name: String,
    pub command: String,
    pub args: Vec<String>,
    pub is_dangerous: bool,
    pub requires_sudo: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SkillDescriptor {
    pub name: String,
    pub description: String,
    pub path: String,
    pub source: String, // "astral-builtin" | "user-agent" | "omarchy"
}

fn default_crash_count() -> u32 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CrashIncident {
    pub id: String,
    pub process_name: String,
    pub pid: Option<u32>,
    pub signal: Option<String>,
    pub timestamp_ms: u64,
    pub summary: String,
    pub log_snippet: String,
    #[serde(default = "default_crash_count")]
    pub count: u32,
}

impl CrashIncident {
    pub fn build_diagnostic_prompt(&self, detailed_info: Option<&str>) -> String {
        let mut prompt = format!(
            "Please diagnose the following crash of '{}':\n\n- Process: {}\n",
            self.process_name, self.process_name
        );
        if let Some(pid) = self.pid {
            prompt.push_str(&format!("- PID: {}\n", pid));
        }
        if let Some(ref sig) = self.signal {
            prompt.push_str(&format!("- Signal: {}\n", sig));
        }
        prompt.push_str(&format!("- Summary: {}\n", self.summary));

        let logs = detailed_info.unwrap_or(&self.log_snippet);
        if !logs.trim().is_empty() {
            prompt.push_str("\nStack Trace / System Diagnostic Logs:\n```\n");
            prompt.push_str(logs.trim());
            prompt.push_str("\n```\n");
        }
        prompt.push_str("\nPlease analyze the root cause of this crash, explain why it happened, and suggest potential solutions or bug fixes.");
        prompt
    }
}


#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HarnessInfo {
    pub id: String,
    pub name: String,
    pub is_available: bool,
    pub version: Option<String>,
    pub is_default: bool,
    pub path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", content = "payload")]
pub enum AssistantEvent {
    TextChunk(String),
    ToolProposal(ToolCallProposal),
    ToolExecuted { id: String, stdout: String, stderr: String, exit_code: i32 },
    CrashDetected(CrashIncident),
    TurnCompleted { total_tokens: Option<u64> },
    Error(String),
}

impl ToolCallProposal {
    pub fn assess_safety(command: &str) -> (bool, bool) {
        let trimmed = command.trim();
        let lower = trimmed.to_lowercase();

        let requires_sudo = lower.starts_with("sudo ")
            || lower.contains(" sudo ")
            || lower.starts_with("pkexec ")
            || lower.starts_with("kdesu ");

        let is_dangerous = requires_sudo
            || lower.contains("rm -rf")
            || lower.contains("rm -r")
            || lower.contains("dd if=")
            || lower.contains("mkfs")
            || lower.contains("kill -9")
            || lower.contains("killall -9")
            || lower.starts_with("systemctl restart")
            || lower.starts_with("systemctl stop")
            || lower.starts_with("pacman -r")
            || lower.starts_with("pacman -s")
            || lower.starts_with("pkill");

        (is_dangerous, requires_sudo)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_assess_safety_read_only() {
        let (dangerous, sudo) = ToolCallProposal::assess_safety("journalctl -p 3 -xb -n 50");
        assert!(!dangerous);
        assert!(!sudo);

        let (dangerous2, sudo2) = ToolCallProposal::assess_safety("ps -eo pid,%cpu,%mem,comm");
        assert!(!dangerous2);
        assert!(!sudo2);
    }

    #[test]
    fn test_assess_safety_dangerous_and_sudo() {
        let (dangerous, sudo) = ToolCallProposal::assess_safety("sudo systemctl restart NetworkManager");
        assert!(dangerous);
        assert!(sudo);

        let (dangerous2, sudo2) = ToolCallProposal::assess_safety("rm -rf /tmp/cache/*");
        assert!(dangerous2);
        assert!(!sudo2);

        let (dangerous3, sudo3) = ToolCallProposal::assess_safety("kill -9 1234");
        assert!(dangerous3);
        assert!(!sudo3);
    }

    #[test]
    fn test_event_serialization() {
        let ev = AssistantEvent::TextChunk("Analyzing system logs...".to_string());
        let json = serde_json::to_string(&ev).unwrap();
        assert!(json.contains("TextChunk"));
        assert!(json.contains("Analyzing system logs..."));
    }
}
