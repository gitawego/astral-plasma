use crate::domain::tool_scanner::{DiscoveredCredential, ToolConfigScanner};
use std::process::Command;

/// Deterministic configuration scanner for Google Antigravity / Gemini CLI (desktop Keyring).
#[derive(Debug, Clone, Default)]
pub struct AntigravityScanner;

impl AntigravityScanner {
    pub fn new() -> Self {
        Self
    }
}

impl ToolConfigScanner for AntigravityScanner {
    fn tool_name(&self) -> &'static str {
        "antigravity"
    }

    fn scan(&self) -> Vec<DiscoveredCredential> {
        let mut results = Vec::new();

        // 1. Read desktop keyring (secret-tool)
        if let Ok(output) = Command::new("secret-tool")
            .args(["lookup", "service", "gemini", "username", "antigravity"])
            .output()
        {
            if output.status.success() {
                let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !text.is_empty() {
                    let mut identity = None;
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                        identity = v.get("identity")
                            .or_else(|| v.get("account"))
                            .or_else(|| v.get("email"))
                            .and_then(|s| s.as_str())
                            .map(|s| s.to_string());
                    }

                    results.push(DiscoveredCredential {
                        provider_id: "gemini".to_string(),
                        tool_source: "antigravity".to_string(),
                        credential: text,
                        base_url: None,
                        identity,
                        label: Some("Antigravity Keyring".to_string()),
                    });
                }
            }
        }

        results
    }
}
