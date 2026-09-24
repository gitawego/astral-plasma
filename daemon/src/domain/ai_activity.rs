use serde::{Deserialize, Serialize};

/// Clean domain model representing the resolved identity and branding for an active AI model.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AiAgentIdentity {
    pub tool_source: String,
    pub model_id: String,
    pub display_name: String,
    pub brand_color: String,
    pub brand_icon: String,
}

/// Instantaneous activity state emitted by the monitoring engine.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AiActivityState {
    pub identity: AiAgentIdentity,
    pub is_active: bool,
    pub intensity: f64,        // 0.0 to 1.0 (smooth decay)
    pub request_rate_rpm: f64, // Rolling requests per minute
    pub last_event_epoch_ms: u64,
}

impl Default for AiActivityState {
    fn default() -> Self {
        Self {
            identity: AiAgentIdentity {
                tool_source: "idle".to_string(),
                model_id: String::new(),
                display_name: "AI Agent".to_string(),
                brand_color: "#9bcbfb".to_string(),
                brand_icon: "auto_awesome".to_string(),
            },
            is_active: false,
            intensity: 0.0,
            request_rate_rpm: 0.0,
            last_event_epoch_ms: 0,
        }
    }
}

/// Resolves raw model name and agent tool source into a standardized identity with brand aesthetics.
pub fn resolve_model_metadata(raw_model: &str, tool_source: &str) -> AiAgentIdentity {
    let lower_model = raw_model.trim().to_lowercase();
    let lower_tool = tool_source.trim().to_lowercase();

    // 1. Claude / Anthropic
    if lower_model.contains("claude") || lower_tool.contains("claude") {
        let display = if lower_model.contains("3-7") || lower_model.contains("3.7") {
            "Claude 3.7 Sonnet".to_string()
        } else if lower_model.contains("3-5-haiku") || lower_model.contains("3.5-haiku") {
            "Claude 3.5 Haiku".to_string()
        } else if lower_model.contains("3-5") || lower_model.contains("3.5") {
            "Claude 3.5 Sonnet".to_string()
        } else if lower_model.contains("opus") {
            "Claude Opus".to_string()
        } else if !raw_model.is_empty() {
            format_clean_model_name(raw_model)
        } else {
            "Claude Code".to_string()
        };
        return AiAgentIdentity {
            tool_source: "claude".to_string(),
            model_id: if raw_model.is_empty() { "claude".to_string() } else { raw_model.to_string() },
            display_name: display,
            brand_color: "#D97706".to_string(), // Warm Amber
            brand_icon: "psychology".to_string(),
        };
    }

    // 2. Google Gemini / Antigravity
    if lower_model.contains("gemini") || lower_tool.contains("gemini") || lower_tool.contains("antigravity") {
        let display = if lower_model.contains("2.5-pro") || lower_model.contains("2-5-pro") {
            "Gemini 2.5 Pro".to_string()
        } else if lower_model.contains("2.5-flash") || lower_model.contains("2-5-flash") {
            "Gemini 2.5 Flash".to_string()
        } else if lower_model.contains("flash") {
            "Gemini Flash".to_string()
        } else if lower_model.contains("pro") {
            "Gemini Pro".to_string()
        } else if !raw_model.is_empty() {
            format_clean_model_name(raw_model)
        } else {
            "Google Gemini".to_string()
        };
        return AiAgentIdentity {
            tool_source: "gemini".to_string(),
            model_id: if raw_model.is_empty() { "gemini".to_string() } else { raw_model.to_string() },
            display_name: display,
            brand_color: "#818CF8".to_string(), // Stellar Violet
            brand_icon: "auto_awesome".to_string(),
        };
    }

    // 3. OpenAI / Codex / GPT
    if lower_model.contains("gpt") || lower_model.contains("o1") || lower_model.contains("o3") || lower_model.contains("codex") || lower_tool.contains("codex") {
        let display = if lower_model.contains("o3-mini") {
            "OpenAI o3-mini".to_string()
        } else if lower_model.contains("o1") {
            "OpenAI o1".to_string()
        } else if lower_model.contains("gpt-4o") {
            "GPT-4o".to_string()
        } else if !raw_model.is_empty() {
            format_clean_model_name(raw_model)
        } else {
            "OpenAI Codex".to_string()
        };
        return AiAgentIdentity {
            tool_source: "openai".to_string(),
            model_id: if raw_model.is_empty() { "codex".to_string() } else { raw_model.to_string() },
            display_name: display,
            brand_color: "#10A37F".to_string(), // OpenAI Emerald
            brand_icon: "terminal".to_string(),
        };
    }

    // 4. MiMo (Xiaomi)
    if lower_model.contains("mimo") || lower_model.contains("xiaomi") {
        let display = if lower_model.contains("v2.6-flash") || lower_model.contains("v2-6-flash") {
            "MiMo 2.6 Flash".to_string()
        } else if lower_model.contains("v2.5-pro") || lower_model.contains("v2-5-pro") {
            "MiMo 2.5 Pro".to_string()
        } else if !raw_model.is_empty() {
            format_clean_model_name(raw_model)
        } else {
            "MiMo (Xiaomi)".to_string()
        };
        return AiAgentIdentity {
            tool_source: "mimo".to_string(),
            model_id: raw_model.to_string(),
            display_name: display,
            brand_color: "#FF6900".to_string(), // Xiaomi Orange
            brand_icon: "devices".to_string(),
        };
    }

    // 5. Muse Spark (Meta)
    if lower_model.contains("muse") || lower_model.contains("spark") {
        let display = if lower_model.contains("1.3") {
            "Muse Spark 1.3".to_string()
        } else if lower_model.contains("1.2") {
            "Muse Spark 1.2".to_string()
        } else if !raw_model.is_empty() {
            format_clean_model_name(raw_model)
        } else {
            "Muse Spark (Meta)".to_string()
        };
        return AiAgentIdentity {
            tool_source: "meta".to_string(),
            model_id: raw_model.to_string(),
            display_name: display,
            brand_color: "#0081FB".to_string(), // Meta Electric Blue
            brand_icon: "flare".to_string(),
        };
    }

    // 6. Grok (x.com / xAI)
    if lower_model.contains("grok") || lower_tool.contains("grok") || lower_model.contains("xai") {
        let display = if lower_model.contains("3") {
            "Grok 3 (x.com)".to_string()
        } else if lower_model.contains("2") {
            "Grok 2 (x.com)".to_string()
        } else if !raw_model.is_empty() {
            format_clean_model_name(raw_model)
        } else {
            "Grok (x.com)".to_string()
        };
        return AiAgentIdentity {
            tool_source: "grok".to_string(),
            model_id: raw_model.to_string(),
            display_name: display,
            brand_color: "#EF4444".to_string(), // Grok Crimson
            brand_icon: "rocket_launch".to_string(),
        };
    }

    // 7. Ollama Cloud
    if lower_model.contains("ollama-cloud") || lower_model.starts_with("ollama/") || lower_tool.contains("ollama") {
        let clean = raw_model.replace("ollama-cloud/", "").replace("ollama/", "");
        return AiAgentIdentity {
            tool_source: "ollama".to_string(),
            model_id: raw_model.to_string(),
            display_name: format!("Ollama ({})", format_clean_model_name(&clean)),
            brand_color: "#F59E0B".to_string(), // Ollama Warm Amber
            brand_icon: "cloud".to_string(),
        };
    }

    // 8. DeepSeek
    if lower_model.contains("deepseek") {
        let display = if lower_model.contains("v4.1") || lower_model.contains("v4-1") {
            "DeepSeek V4.1".to_string()
        } else if lower_model.contains("v4") {
            "DeepSeek V4".to_string()
        } else if lower_model.contains("coder") {
            "DeepSeek Coder".to_string()
        } else {
            format_clean_model_name(raw_model)
        };
        return AiAgentIdentity {
            tool_source: "deepseek".to_string(),
            model_id: raw_model.to_string(),
            display_name: display,
            brand_color: "#2563EB".to_string(), // Cobalt Azure
            brand_icon: "smart_toy".to_string(),
        };
    }

    // 9. MiniMax
    if lower_model.contains("minimax") {
        let display = if lower_model.contains("m3") {
            "MiniMax M3".to_string()
        } else if lower_model.contains("m2.7") {
            "MiniMax M2.7".to_string()
        } else {
            "MiniMax".to_string()
        };
        return AiAgentIdentity {
            tool_source: "minimax".to_string(),
            model_id: raw_model.to_string(),
            display_name: display,
            brand_color: "#06B6D4".to_string(), // Electric Mint
            brand_icon: "bolt".to_string(),
        };
    }

    // 10. OMP / GLM / Qwen / Omen
    if lower_model.contains("glm") || lower_model.contains("qwen") || lower_model.contains("omen") || lower_tool.contains("omp") {
        return AiAgentIdentity {
            tool_source: "omp".to_string(),
            model_id: raw_model.to_string(),
            display_name: format_clean_model_name(raw_model),
            brand_color: "#EC4899".to_string(), // Vibrant Rose
            brand_icon: "memory".to_string(),
        };
    }

    // 11. Fallback / Generic
    AiAgentIdentity {
        tool_source: tool_source.to_string(),
        model_id: raw_model.to_string(),
        display_name: if raw_model.is_empty() { "AI Agent".to_string() } else { format_clean_model_name(raw_model) },
        brand_color: "#9bcbfb".to_string(),
        brand_icon: "token".to_string(),
    }
}

fn format_clean_model_name(raw: &str) -> String {
    let stripped = raw.split('/').last().unwrap_or(raw);
    let parts: Vec<String> = stripped
        .split(['-', '_', ':'])
        .filter(|s| !s.is_empty())
        .map(|s| {
            let mut c = s.chars();
            match c.next() {
                None => String::new(),
                Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
            }
        })
        .collect();
    if parts.is_empty() {
        return raw.to_string();
    }
    parts.join(" ")
}
