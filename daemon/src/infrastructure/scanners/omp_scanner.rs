use crate::domain::tool_scanner::{DiscoveredCredential, ToolConfigScanner};
use std::fs;
use std::path::PathBuf;

/// Deterministic configuration scanner for the OMP coding agent (`~/.omp/agent`).
#[derive(Debug, Clone)]
pub struct OmpScanner {
    base_dir: Option<PathBuf>,
}

impl Default for OmpScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl OmpScanner {
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
        std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".omp/agent"))
    }
}

impl ToolConfigScanner for OmpScanner {
    fn tool_name(&self) -> &'static str {
        "omp"
    }

    fn scan(&self) -> Vec<DiscoveredCredential> {
        let mut results = Vec::new();
        let base_dir = match self.get_base_dir() {
            Some(d) => d,
            None => return results,
        };

        let models_path = base_dir.join("models.yml");
        if !models_path.exists() {
            return results;
        }

        let content = match fs::read_to_string(&models_path) {
            Ok(c) => c,
            Err(_) => return results,
        };

        parse_omp_models_yaml(&content, &mut results);
        results
    }
}

/// Deterministically parses OMP `models.yml` providers section without external YAML dependencies.
pub fn parse_omp_models_yaml(content: &str, results: &mut Vec<DiscoveredCredential>) {
    let mut in_providers = false;
    let mut current_provider_id: Option<String> = None;
    let mut current_api_key_spec: Option<String> = None;
    let mut current_base_url: Option<String> = None;

    let flush_current = |id_opt: &Option<String>,
                         key_spec_opt: &Option<String>,
                         url_opt: &Option<String>,
                         out: &mut Vec<DiscoveredCredential>| {
        if let (Some(raw_id), Some(key_spec)) = (id_opt, key_spec_opt) {
            let trimmed_spec = key_spec.trim().trim_matches('"').trim_matches('\'');
            if !trimmed_spec.is_empty() {
                // If it's an environment variable name (e.g. MINIMAX_CODE_CN_API_KEY)
                let resolved_cred = if let Ok(val) = std::env::var(trimmed_spec) {
                    if !val.trim().is_empty() {
                        val.trim().to_string()
                    } else {
                        trimmed_spec.to_string()
                    }
                } else {
                    trimmed_spec.to_string()
                };

                // Only record if we resolved to a non-empty credential that isn't an unresolved env var name
                let looks_like_env_var = resolved_cred.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_')
                    && resolved_cred.chars().any(|c| c.is_ascii_uppercase());
                let is_unresolved_env = looks_like_env_var && std::env::var(&resolved_cred).is_err();
                if !is_unresolved_env && !resolved_cred.is_empty() {
                    let provider_id = normalize_omp_provider_id(raw_id);
                    out.push(DiscoveredCredential {
                        provider_id,
                        tool_source: "omp".to_string(),
                        credential: resolved_cred,
                        base_url: url_opt.clone(),
                        identity: None,
                        label: Some(format!("OMP ({})", raw_id)),
                    });
                }
            }
        }
    };

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('#') || trimmed.is_empty() {
            continue;
        }

        // Section header
        if !line.starts_with(' ') && !line.starts_with('\t') {
            if trimmed.starts_with("providers:") {
                in_providers = true;
                continue;
            } else if in_providers {
                // Leaving providers block
                flush_current(&current_provider_id, &current_api_key_spec, &current_base_url, results);
                in_providers = false;
                current_provider_id = None;
                current_api_key_spec = None;
                current_base_url = None;
            }
        }

        if !in_providers {
            continue;
        }

        // Provider entry under providers: (typically 2 spaces indentation)
        let indent = line.chars().take_while(|c| *c == ' ').count();
        if indent == 2 && trimmed.ends_with(':') {
            flush_current(&current_provider_id, &current_api_key_spec, &current_base_url, results);
            let prov_name = trimmed.trim_end_matches(':').trim();
            current_provider_id = Some(prov_name.to_string());
            current_api_key_spec = None;
            current_base_url = None;
        } else if indent >= 4 && current_provider_id.is_some() {
            if let Some(pos) = trimmed.find(':') {
                let key = trimmed[..pos].trim();
                let val = trimmed[pos + 1..].trim();
                if key == "apiKey" || key == "api_key" {
                    current_api_key_spec = Some(val.to_string());
                } else if key == "baseUrl" || key == "base_url" {
                    current_base_url = Some(val.trim_matches('"').trim_matches('\'').to_string());
                }
            }
        }
    }

    if in_providers {
        flush_current(&current_provider_id, &current_api_key_spec, &current_base_url, results);
    }
}

fn normalize_omp_provider_id(raw: &str) -> String {
    let lower = raw.to_lowercase();
    if lower == "minimax" || lower == "minimax-cn" || lower == "minimax-code-cn" {
        "minimax-cn".to_string()
    } else if lower == "mimo" || lower == "mimo-cn" || lower.contains("xiaomi") {
        "xiaomi-mimo-cn".to_string()
    } else if lower.contains("opencode") {
        "opencode-go".to_string()
    } else if lower == "gemini" || lower == "google" {
        "gemini".to_string()
    } else {
        raw.to_string()
    }
}
