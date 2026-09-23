use crate::domain::tool_scanner::{DiscoveredCredential, ToolConfigScanner};
use std::fs;
use std::path::PathBuf;
use std::process::Command;

/// Deterministic configuration scanner for Google Antigravity / Gemini CLI (`~/.antigravity_cockpit`, Keyring, and token files).
#[derive(Debug, Clone)]
pub struct AntigravityScanner {
    cockpit_dir: Option<PathBuf>,
}

impl Default for AntigravityScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl AntigravityScanner {
    pub fn new() -> Self {
        Self { cockpit_dir: None }
    }

    pub fn with_cockpit_dir(dir: PathBuf) -> Self {
        Self {
            cockpit_dir: Some(dir),
        }
    }

    fn get_cockpit_dir(&self) -> Option<PathBuf> {
        if let Some(ref d) = self.cockpit_dir {
            return Some(d.clone());
        }
        std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".antigravity_cockpit"))
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

        // 2. Read ~/.antigravity_cockpit/accounts.json
        if let Some(cockpit) = self.get_cockpit_dir() {
            let accounts_json = cockpit.join("accounts.json");
            if accounts_json.exists() {
                if let Ok(c) = fs::read_to_string(&accounts_json) {
                    if let Ok(val) = serde_json::from_str::<serde_json::Value>(&c) {
                        if let Some(accs) = val.get("accounts").and_then(|a| a.as_array()) {
                            for acc in accs {
                                if let Some(email) = acc.get("email").and_then(|e| e.as_str()) {
                                    let id = acc.get("id").and_then(|i| i.as_str());
                                    let label = acc.get("name").and_then(|n| n.as_str());
                                    results.push(DiscoveredCredential {
                                        provider_id: "gemini".to_string(),
                                        tool_source: "antigravity".to_string(),
                                        credential: id.unwrap_or(email).to_string(),
                                        base_url: None,
                                        identity: Some(email.to_string()),
                                        label: label.map(|l| format!("Antigravity ({})", l)),
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        results
    }
}
