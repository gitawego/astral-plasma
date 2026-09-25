use crate::domain::tool_scanner::{DiscoveredCredential, ToolConfigScanner};
use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;

/// Deterministic configuration scanner for ZCode (`~/.zcode`).
#[derive(Debug, Clone)]
pub struct ZCodeScanner {
    base_dir: Option<PathBuf>,
}

impl Default for ZCodeScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl ZCodeScanner {
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
        std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".zcode"))
    }
}

impl ToolConfigScanner for ZCodeScanner {
    fn tool_name(&self) -> &'static str {
        "zcode"
    }

    fn scan(&self) -> Vec<DiscoveredCredential> {
        let mut results = Vec::new();
        let mut seen = HashSet::new();

        let base_dir = match self.get_base_dir() {
            Some(d) => d,
            None => return results,
        };

        // 1. Scan ~/.zcode/v2/provider_config.json
        let prov_config_path = base_dir.join("v2/provider_config.json");
        if prov_config_path.exists() {
            if let Ok(content) = fs::read_to_string(&prov_config_path) {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(rules) = val
                        .get("config")
                        .and_then(|c| c.get("providerConfigRules"))
                        .and_then(|r| r.get("providerRules"))
                        .and_then(|p| p.as_array())
                    {
                        for rule in rules {
                            let prov_name = rule
                                .get("providerName")
                                .or_else(|| rule.get("templateId"))
                                .and_then(|n| n.as_str())
                                .unwrap_or("");

                            let config_obj = rule.get("config");
                            let api_key = config_obj
                                .and_then(|c| c.get("access"))
                                .and_then(|a| a.get("apiKey"))
                                .or_else(|| config_obj.and_then(|c| c.get("apiKey")))
                                .and_then(|k| k.as_str());

                            let base_url = config_obj
                                .and_then(|c| c.get("api"))
                                .and_then(|a| a.get("baseUrl"))
                                .or_else(|| config_obj.and_then(|c| c.get("baseURL")))
                                .and_then(|u| u.as_str())
                                .map(|s| s.to_string());

                            if let Some(key) = api_key {
                                let trimmed = key.trim();
                                if !trimmed.is_empty() && !trimmed.starts_with("enc:") {
                                    let provider_id = normalize_zcode_provider_id(prov_name);
                                    let key_id = (provider_id.clone(), trimmed.to_string());
                                    if !seen.contains(&key_id) {
                                        seen.insert(key_id);
                                        results.push(DiscoveredCredential {
                                            provider_id,
                                            tool_source: "zcode".to_string(),
                                            credential: trimmed.to_string(),
                                            base_url,
                                            identity: None,
                                            label: Some(format!("ZCode ({})", prov_name)),
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Scan ~/.zcode/v2/config.json
        let config_json_path = base_dir.join("v2/config.json");
        if config_json_path.exists() {
            if let Ok(content) = fs::read_to_string(&config_json_path) {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(providers_obj) = val.get("provider").and_then(|p| p.as_object()) {
                        for (raw_id, prov_val) in providers_obj {
                            let name = prov_val
                                .get("name")
                                .and_then(|n| n.as_str())
                                .unwrap_or(raw_id);

                            let options = prov_val.get("options");
                            let api_key = options
                                .and_then(|o| o.get("apiKey"))
                                .or_else(|| options.and_then(|o| o.get("api_key")))
                                .and_then(|k| k.as_str());

                            let base_url = options
                                .and_then(|o| o.get("baseURL"))
                                .or_else(|| options.and_then(|o| o.get("baseUrl")))
                                .and_then(|u| u.as_str())
                                .map(|s| s.to_string());

                            if let Some(key) = api_key {
                                let trimmed = key.trim();
                                if !trimmed.is_empty() && !trimmed.starts_with("enc:") {
                                    let provider_id = normalize_zcode_provider_id(name);
                                    let key_id = (provider_id.clone(), trimmed.to_string());
                                    if !seen.contains(&key_id) {
                                        seen.insert(key_id);
                                        results.push(DiscoveredCredential {
                                            provider_id,
                                            tool_source: "zcode".to_string(),
                                            credential: trimmed.to_string(),
                                            base_url,
                                            identity: None,
                                            label: Some(format!("ZCode ({})", name)),
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. Scan root ~/.zcode/provider_config.json if present
        let root_prov_path = base_dir.join("provider_config.json");
        if root_prov_path.exists() {
            if let Ok(content) = fs::read_to_string(&root_prov_path) {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(rules) = val
                        .get("config")
                        .and_then(|c| c.get("providerConfigRules"))
                        .and_then(|r| r.get("providerRules"))
                        .and_then(|p| p.as_array())
                    {
                        for rule in rules {
                            let prov_name = rule
                                .get("providerName")
                                .or_else(|| rule.get("templateId"))
                                .and_then(|n| n.as_str())
                                .unwrap_or("");

                            let config_obj = rule.get("config");
                            let api_key = config_obj
                                .and_then(|c| c.get("access"))
                                .and_then(|a| a.get("apiKey"))
                                .or_else(|| config_obj.and_then(|c| c.get("apiKey")))
                                .and_then(|k| k.as_str());

                            let base_url = config_obj
                                .and_then(|c| c.get("api"))
                                .and_then(|a| a.get("baseUrl"))
                                .or_else(|| config_obj.and_then(|c| c.get("baseURL")))
                                .and_then(|u| u.as_str())
                                .map(|s| s.to_string());

                            if let Some(key) = api_key {
                                let trimmed = key.trim();
                                if !trimmed.is_empty() && !trimmed.starts_with("enc:") {
                                    let provider_id = normalize_zcode_provider_id(prov_name);
                                    let key_id = (provider_id.clone(), trimmed.to_string());
                                    if !seen.contains(&key_id) {
                                        seen.insert(key_id);
                                        results.push(DiscoveredCredential {
                                            provider_id,
                                            tool_source: "zcode".to_string(),
                                            credential: trimmed.to_string(),
                                            base_url,
                                            identity: None,
                                            label: Some(format!("ZCode ({})", prov_name)),
                                        });
                                    }
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

/// Normalizes ZCode provider names into canonical Astral Plasma provider identifiers.
pub fn normalize_zcode_provider_id(raw_name: &str) -> String {
    let lower = raw_name.to_lowercase();
    if lower.contains("minimax") {
        "minimax-cn".to_string()
    } else if lower.contains("deepseek") {
        "deepseek".to_string()
    } else if lower.contains("ollama") {
        "ollama".to_string()
    } else if lower.contains("opencode") {
        "opencode-go".to_string()
    } else if lower.contains("火山") || lower.contains("volces") || lower.contains("ark") {
        "ark-code".to_string()
    } else if lower.contains("讯飞") || lower.contains("spark") || lower.contains("xfyun") {
        "spark-cn".to_string()
    } else if lower.contains("bigmodel") || lower.contains("glm") || lower.contains("zhipu") || lower.contains("zai") {
        "glm".to_string()
    } else if lower.contains("claude") || lower.contains("anthropic") {
        "claude".to_string()
    } else if lower.contains("openai") || lower.contains("gpt") {
        "openai".to_string()
    } else if lower.contains("xiaomi") || lower.contains("mimo") {
        "xiaomi-mimo-cn".to_string()
    } else {
        lower.trim().replace(' ', "-")
    }
}
