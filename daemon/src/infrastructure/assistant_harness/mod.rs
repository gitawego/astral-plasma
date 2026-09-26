pub mod pi_harness;
pub mod hermes_harness;
pub mod runtime_provisioner;

use crate::domain::assistant::{AssistantEvent, HarnessInfo, SkillDescriptor};
use hermes_harness::HermesHarness;
use pi_harness::PiHarness;
use tokio::sync::mpsc;

#[derive(Clone)]
pub enum HarnessBackend {
    Pi(PiHarness),
    Hermes(HermesHarness),
}

impl HarnessBackend {
    pub fn harness_id(&self) -> &'static str {
        match self {
            Self::Pi(_) => "pi",
            Self::Hermes(_) => "hermes",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            Self::Pi(_) => "Pi Coding & System Agent",
            Self::Hermes(_) => "Hermes Autonomous Agent (Nous Research)",
        }
    }

    pub fn is_available(&self) -> bool {
        match self {
            Self::Pi(p) => p.is_available(),
            Self::Hermes(h) => h.is_available(),
        }
    }

    pub fn harness_info(&self) -> HarnessInfo {
        match self {
            Self::Pi(p) => p.harness_info(),
            Self::Hermes(h) => h.harness_info(),
        }
    }

    pub async fn run_turn(
        &self,
        prompt: &str,
        provider: Option<&str>,
        model: Option<&str>,
        event_sender: mpsc::Sender<AssistantEvent>,
    ) -> Result<(), String> {
        match self {
            Self::Pi(p) => p.run_turn(prompt, provider, model, event_sender).await,
            Self::Hermes(h) => h.run_turn(prompt, provider, model, event_sender).await,
        }
    }

    pub fn list_skills(&self) -> Vec<SkillDescriptor> {
        PiHarness::scan_skills()
    }
}
