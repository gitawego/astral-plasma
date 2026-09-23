use crate::domain::tool_scanner::{DiscoveredCredential, ToolConfigScanner};
use std::fs;
use std::path::PathBuf;

/// Deterministic configuration scanner for the Pi coding agent (`~/.pi/agent`).
#[derive(Debug, Clone)]
pub struct PiScanner {
    base_dir: Option<PathBuf>,
}

impl Default for PiScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl PiScanner {
    pub fn new() -> Self {
        Self { base_dir: None }
    }

    pub fn with_base_dir(dir: PathBuf) -> Self {
        Self {
            base_dir: Some(dir),
        }
    }

    fn get_base_dir(&self) -> Option<PathBuf> {
        if let Some(ref d) = self.base_dir {
            return Some(d.clone());
        }
        std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".pi/agent"))
    }
}

impl ToolConfigScanner for PiScanner {
    fn tool_name(&self) -> &'static str {
        "pi"
    }

    fn scan(&self) -> Vec<DiscoveredCredential> {
        let mut results = Vec::new();
        let base_dir = match self.get_base_dir() {
            Some(d) => d,
            None => return results,
        };

        let auth_path = base_dir.join("auth.json");
        if !auth_path.exists() {
            return results;
        }

        let content = match fs::read_to_string(&auth_path) {
            Ok(c) => c,
            Err(_) => return results,
        };

        let val: serde_json::Value = match serde_json::from_str(&content) {
            Ok(v) => v,
            Err(_) => return results,
        };

        if let Some(obj) = val.as_object() {
            for (provider_raw, cred_val) in obj {
                let key = cred_val
                    .get("key")
                    .and_then(|k| k.as_str())
                    .or_else(|| cred_val.as_str());

                if let Some(api_key) = key {
                    let trimmed = api_key.trim();
                    if !trimmed.is_empty() {
                        let provider_id = normalize_provider_id(provider_raw);
                        results.push(DiscoveredCredential {
                            provider_id,
                            tool_source: "pi".to_string(),
                            credential: trimmed.to_string(),
                            base_url: None,
                            identity: None,
                            label: Some(format!("Pi Agent ({})", provider_raw)),
                        });
                    }
                }
            }
        }

        results
    }
}

fn normalize_provider_id(raw: &str) -> String {
    let lower = raw.to_lowercase();
    if lower == "minimax" || lower == "minimax-cn" || lower == "minimax_cn" {
        "minimax-cn".to_string()
    } else if lower == "opencode" || lower == "opencode-go" || lower == "opencode_go" {
        "opencode-go".to_string()
    } else if lower.contains("mimo") || lower.contains("xiaomi") {
        "xiaomi-mimo-cn".to_string()
    } else if lower == "gemini" || lower == "google" {
        "gemini".to_string()
    } else {
        raw.to_string()
    }
}
