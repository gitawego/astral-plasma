use crate::domain::tool_scanner::{DiscoveredCredential, ToolConfigScanner};
use std::fs;
use std::path::PathBuf;

/// Deterministic configuration scanner for OpenCode (`~/.config/opencode`).
#[derive(Debug, Clone)]
pub struct OpenCodeScanner {
    base_dir: Option<PathBuf>,
}

impl Default for OpenCodeScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl OpenCodeScanner {
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
        std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".config/opencode"))
    }
}

impl ToolConfigScanner for OpenCodeScanner {
    fn tool_name(&self) -> &'static str {
        "opencode"
    }

    fn scan(&self) -> Vec<DiscoveredCredential> {
        let mut results = Vec::new();
        let base_dir = match self.get_base_dir() {
            Some(d) => d,
            None => return results,
        };

        // 1. Scan opencode.json
        let opencode_json_path = base_dir.join("opencode.json");
        if opencode_json_path.exists() {
            if let Ok(content) = fs::read_to_string(&opencode_json_path) {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(providers_obj) = val.get("provider").and_then(|p| p.as_object()) {
                        for (raw_name, prov_val) in providers_obj {
                            let options = prov_val.get("options");
                            let api_key_raw = options
                                .and_then(|o| o.get("apiKey"))
                                .or_else(|| options.and_then(|o| o.get("api_key")))
                                .and_then(|k| k.as_str());

                            let base_url = options
                                .and_then(|o| o.get("baseURL"))
                                .or_else(|| options.and_then(|o| o.get("baseUrl")))
                                .and_then(|u| u.as_str())
                                .map(|s| s.to_string());

                            if let Some(raw_key) = api_key_raw {
                                let resolved_key = resolve_opencode_key(raw_key);
                                if !resolved_key.is_empty() {
                                    let provider_id = normalize_opencode_provider_id(raw_name);
                                    results.push(DiscoveredCredential {
                                        provider_id,
                                        tool_source: "opencode".to_string(),
                                        credential: resolved_key,
                                        base_url,
                                        identity: None,
                                        label: Some(format!("OpenCode ({})", raw_name)),
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Scan credentials.json in opencode config dir if present
        let creds_path = base_dir.join("credentials.json");
        if creds_path.exists() {
            if let Ok(c) = fs::read_to_string(&creds_path) {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&c) {
                    if let Some(obj) = v.as_object() {
                        for (k, val) in obj {
                            if let Some(secret) = val.as_str() {
                                if !secret.trim().is_empty() {
                                    results.push(DiscoveredCredential {
                                        provider_id: normalize_opencode_provider_id(k),
                                        tool_source: "opencode".to_string(),
                                        credential: secret.trim().to_string(),
                                        base_url: None,
                                        identity: None,
                                        label: Some(format!("OpenCode Credentials ({})", k)),
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

fn resolve_opencode_key(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.starts_with("{file://") && trimmed.ends_with('}') {
        let path_str = &trimmed[8..trimmed.len() - 1];
        if let Ok(content) = fs::read_to_string(path_str) {
            return content.trim().to_string();
        }
    } else if trimmed.starts_with("{file:") && trimmed.ends_with('}') {
        let path_str = &trimmed[6..trimmed.len() - 1];
        if let Ok(content) = fs::read_to_string(path_str) {
            return content.trim().to_string();
        }
    }
    trimmed.to_string()
}

fn normalize_opencode_provider_id(raw: &str) -> String {
    let lower = raw.to_lowercase();
    if lower.contains("minimax") {
        "minimax-cn".to_string()
    } else if lower.contains("mimo") || lower.contains("xiaomi") {
        "xiaomi-mimo-cn".to_string()
    } else if lower == "opencode" || lower == "opencode-go" {
        "opencode-go".to_string()
    } else if lower == "gemini" || lower == "google" {
        "gemini".to_string()
    } else {
        raw.to_string()
    }
}
