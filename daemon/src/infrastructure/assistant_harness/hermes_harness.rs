use super::pi_harness::PiHarness;
use super::runtime_provisioner::RuntimeProvisioner;
use crate::domain::assistant::{AssistantEvent, HarnessInfo, SkillDescriptor};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;

#[derive(Clone)]
pub struct HermesHarness {
    executable: Option<PathBuf>,
}

impl Default for HermesHarness {
    fn default() -> Self {
        Self::new()
    }
}

impl HermesHarness {
    pub fn new() -> Self {
        let exe = RuntimeProvisioner::locate_hermes();
        Self { executable: exe }
    }

    pub fn harness_id(&self) -> &'static str {
        "hermes"
    }

    pub fn display_name(&self) -> &'static str {
        "Hermes Autonomous Agent (Nous Research)"
    }

    pub fn is_available(&self) -> bool {
        self.executable.is_some()
    }

    pub fn harness_info(&self) -> HarnessInfo {
        let path_str = self.executable.as_ref().map(|p| p.to_string_lossy().to_string());
        HarnessInfo {
            id: "hermes".to_string(),
            name: "Hermes Agent".to_string(),
            is_available: self.executable.is_some(),
            version: if self.executable.is_some() { Some("0.4.0".to_string()) } else { None },
            is_default: false,
            path: path_str,
        }
    }

    pub fn list_skills(&self) -> Vec<SkillDescriptor> {
        PiHarness::scan_skills()
    }

    pub async fn run_turn(
        &self,
        prompt: &str,
        _provider: Option<&str>,
        _model: Option<&str>,
        event_sender: mpsc::Sender<AssistantEvent>,
    ) -> Result<(), String> {
        let exe = match &self.executable {
            Some(e) => e,
            None => {
                let msg = "Hermes Agent is not installed. You can install it via: pipx install hermes-agent".to_string();
                let _ = event_sender.send(AssistantEvent::Error(msg.clone())).await;
                return Err(msg);
            }
        };

        let mut cmd = Command::new(exe);
        cmd.arg("-p").arg(prompt);
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());

        let mut child = cmd.spawn().map_err(|e| format!("Failed to spawn Hermes: {}", e))?;
        let stdout = child.stdout.take().ok_or("Failed to capture Hermes stdout")?;

        let sender = event_sender.clone();
        tokio::spawn(async move {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let _ = sender.send(AssistantEvent::TextChunk(format!("{}\n", line))).await;
            }
        });

        let status = child.wait().await.map_err(|e| format!("Hermes execution error: {}", e))?;
        if status.success() {
            let _ = event_sender.send(AssistantEvent::TurnCompleted { total_tokens: None }).await;
            Ok(())
        } else {
            let err_msg = format!("Hermes exited with code: {}", status);
            let _ = event_sender.send(AssistantEvent::Error(err_msg.clone())).await;
            Err(err_msg)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hermes_harness_info() {
        let harness = HermesHarness::new();
        let info = harness.harness_info();
        assert_eq!(info.id, "hermes");
        assert!(!info.is_default);
    }
}
