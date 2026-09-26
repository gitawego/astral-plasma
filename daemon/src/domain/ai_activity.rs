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

/// Clean domain model representing an individual active agent slot when multiple agents run concurrently.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ActiveAgentSlot {
    pub tool_source: String,
    pub model_id: String,
    pub display_name: String,
    pub brand_color: String,
    pub brand_icon: String,
    #[serde(default)]
    pub request_rate_rpm: f64,
    #[serde(default)]
    pub token_rate_tpm: f64,
    #[serde(default)]
    pub recent_tokens: u64,
    #[serde(default)]
    pub last_event_epoch_ms: u64,
}

/// Instantaneous activity state emitted by the monitoring engine.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AiActivityState {
    pub identity: AiAgentIdentity,
    pub is_active: bool,
    pub intensity: f64,        // 0.0 to 1.0 (smooth decay)
    pub request_rate_rpm: f64, // Rolling requests per minute
    #[serde(default)]
    pub token_rate_tpm: f64,   // Rolling tokens per minute
    #[serde(default)]
    pub recent_tokens: u64,    // Total tokens in rolling window
    pub last_event_epoch_ms: u64,
    #[serde(default)]
    pub active_agents: Vec<ActiveAgentSlot>,
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
            token_rate_tpm: 0.0,
            recent_tokens: 0,
            last_event_epoch_ms: 0,
            active_agents: Vec::new(),
        }
    }
}

/// User-configurable agent brand override loaded from settings.json.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomAgentRule {
    pub tool_id: String,
    #[serde(default)]
    pub model_keywords: Vec<String>,
    #[serde(default)]
    pub tool_keywords: Vec<String>,
    #[serde(default)]
    pub display_name: Option<String>,
    pub brand_color: String,
    pub brand_icon: String,
}

/// Declarative pattern matching rule for model display naming.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct ModelPatternRule {
    pub any_of: &'static [&'static str],
    pub all_of: &'static [&'static str],
    pub display: &'static str,
}

impl ModelPatternRule {
    pub fn matches(&self, lower_model: &str) -> bool {
        let all_pass = self.all_of.is_empty() || self.all_of.iter().all(|kw| lower_model.contains(kw));
        let any_pass = self.any_of.is_empty() || self.any_of.iter().any(|kw| lower_model.contains(kw));
        all_pass && any_pass && (!self.all_of.is_empty() || !self.any_of.is_empty())
    }
}

/// Declarative brand styling rule for an AI agent tool or model family.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct ModelBrandRule {
    pub tool_id: &'static str,
    pub model_keywords: &'static [&'static str],
    pub tool_keywords: &'static [&'static str],
    pub default_model_id: &'static str,
    pub default_display_name: &'static str,
    pub brand_color: &'static str,
    pub brand_icon: &'static str,
    pub patterns: &'static [ModelPatternRule],
    pub strip_prefixes: &'static [&'static str],
    pub prefix_format: Option<&'static str>,
    pub resolve_inner: bool,
    pub adopt_inner_style: bool,
}

/// Master catalog of static brand configurations and display formatting rules.
pub static STATIC_BRAND_RULES: &[ModelBrandRule] = &[
    ModelBrandRule {
        tool_id: "cursor",
        model_keywords: &[],
        tool_keywords: &["cursor"],
        default_model_id: "cursor",
        default_display_name: "Cursor",
        brand_color: "#6366F1", // Indigo
        brand_icon: "smart_toy",
        patterns: &[],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: true,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "windsurf",
        model_keywords: &[],
        tool_keywords: &["windsurf"],
        default_model_id: "windsurf",
        default_display_name: "Windsurf Cascade",
        brand_color: "#0EA5E9", // Sky Blue
        brand_icon: "waves",
        patterns: &[],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: true,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "dsh",
        model_keywords: &[],
        tool_keywords: &["dsh"],
        default_model_id: "dsh",
        default_display_name: "DSH Agent",
        brand_color: "#06B6D4", // Electric Mint / Cyan
        brand_icon: "bolt",
        patterns: &[
            ModelPatternRule { any_of: &["muse", "spark"], all_of: &["1.3"], display: "Muse Spark 1.3" },
            ModelPatternRule { any_of: &["muse", "spark"], all_of: &["1.2"], display: "Muse Spark 1.2" },
            ModelPatternRule { any_of: &["muse", "spark"], all_of: &[], display: "Muse Spark" },
        ],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "zcode",
        model_keywords: &[],
        tool_keywords: &["zcode"],
        default_model_id: "zcode",
        default_display_name: "ZCode Agent",
        brand_color: "#3B82F6", // Electric Blue
        brand_icon: "code",
        patterns: &[],
        strip_prefixes: &[],
        prefix_format: Some("ZCode · {}"),
        resolve_inner: true,
        adopt_inner_style: true,
    },
    ModelBrandRule {
        tool_id: "claude",
        model_keywords: &["claude"],
        tool_keywords: &["claude"],
        default_model_id: "claude-3-7-sonnet",
        default_display_name: "Claude Code",
        brand_color: "#D97706", // Warm Amber
        brand_icon: "psychology",
        patterns: &[
            ModelPatternRule { any_of: &["3-7", "3.7"], all_of: &[], display: "Claude 3.7 Sonnet" },
            ModelPatternRule { any_of: &["3-5-haiku", "3.5-haiku"], all_of: &[], display: "Claude 3.5 Haiku" },
            ModelPatternRule { any_of: &["3-5", "3.5"], all_of: &[], display: "Claude 3.5 Sonnet" },
            ModelPatternRule { any_of: &["opus"], all_of: &[], display: "Claude Opus" },
        ],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "gemini",
        model_keywords: &["gemini"],
        tool_keywords: &["gemini", "antigravity"],
        default_model_id: "gemini-flash-3.8",
        default_display_name: "Gemini Flash 3.8",
        brand_color: "#818CF8", // Stellar Violet
        brand_icon: "auto_awesome",
        patterns: &[
            ModelPatternRule { any_of: &["3.8", "3-8", "m318"], all_of: &["pro"], display: "Gemini Pro 3.8" },
            ModelPatternRule { any_of: &["3.8", "3-8", "m318"], all_of: &[], display: "Gemini Flash 3.8" },
            ModelPatternRule { any_of: &["2.5", "2-5"], all_of: &["pro"], display: "Gemini 2.5 Pro" },
            ModelPatternRule { any_of: &["2.5", "2-5"], all_of: &[], display: "Gemini 2.5 Flash" },
            ModelPatternRule { any_of: &["2.0", "2-0"], all_of: &["pro"], display: "Gemini 2.0 Pro" },
            ModelPatternRule { any_of: &["2.0", "2-0"], all_of: &[], display: "Gemini 2.0 Flash" },
            ModelPatternRule { any_of: &["pro"], all_of: &[], display: "Gemini Pro 3.8" },
            ModelPatternRule { any_of: &["flash"], all_of: &[], display: "Gemini Flash 3.8" },
        ],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "openai",
        model_keywords: &["gpt", "o1", "o3", "codex"],
        tool_keywords: &["codex"],
        default_model_id: "codex",
        default_display_name: "OpenAI Codex",
        brand_color: "#10A37F", // OpenAI Emerald
        brand_icon: "terminal",
        patterns: &[
            ModelPatternRule { any_of: &["5.5", "5-5"], all_of: &[], display: "GPT-5.5" },
            ModelPatternRule { any_of: &["o3-mini"], all_of: &[], display: "OpenAI o3-mini" },
            ModelPatternRule { any_of: &["o1"], all_of: &[], display: "OpenAI o1" },
            ModelPatternRule { any_of: &["gpt-4o"], all_of: &[], display: "GPT-4o" },
        ],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "mimo",
        model_keywords: &["mimo", "xiaomi"],
        tool_keywords: &[],
        default_model_id: "mimo",
        default_display_name: "MiMo (Xiaomi)",
        brand_color: "#FF6900", // Xiaomi Orange
        brand_icon: "token",
        patterns: &[
            ModelPatternRule { any_of: &["v2.6-flash", "v2-6-flash"], all_of: &[], display: "MiMo 2.6 Flash" },
            ModelPatternRule { any_of: &["v2.5-pro", "v2-5-pro"], all_of: &[], display: "MiMo 2.5 Pro" },
        ],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "meta",
        model_keywords: &["muse", "spark"],
        tool_keywords: &[],
        default_model_id: "muse-spark",
        default_display_name: "Muse Spark (Meta)",
        brand_color: "#0081FB", // Meta Electric Blue
        brand_icon: "flare",
        patterns: &[
            ModelPatternRule { any_of: &["1.3"], all_of: &[], display: "Muse Spark 1.3" },
            ModelPatternRule { any_of: &["1.2"], all_of: &[], display: "Muse Spark 1.2" },
        ],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "grok",
        model_keywords: &["grok", "xai"],
        tool_keywords: &["grok"],
        default_model_id: "grok",
        default_display_name: "Grok (x.com)",
        brand_color: "#EF4444", // Grok Crimson
        brand_icon: "rocket_launch",
        patterns: &[
            ModelPatternRule { any_of: &["3"], all_of: &[], display: "Grok 3 (x.com)" },
            ModelPatternRule { any_of: &["2"], all_of: &[], display: "Grok 2 (x.com)" },
        ],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "ollama",
        model_keywords: &["ollama-cloud", "ollama/"],
        tool_keywords: &["ollama"],
        default_model_id: "ollama",
        default_display_name: "Ollama",
        brand_color: "#F59E0B", // Ollama Warm Amber
        brand_icon: "cloud",
        patterns: &[],
        strip_prefixes: &["ollama-cloud/", "ollama/"],
        prefix_format: Some("Ollama ({})"),
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "deepseek",
        model_keywords: &["deepseek"],
        tool_keywords: &[],
        default_model_id: "deepseek",
        default_display_name: "DeepSeek",
        brand_color: "#2563EB", // Cobalt Azure
        brand_icon: "smart_toy",
        patterns: &[
            ModelPatternRule { any_of: &["v4.1", "v4-1"], all_of: &[], display: "DeepSeek V4.1" },
            ModelPatternRule { any_of: &["v4"], all_of: &[], display: "DeepSeek V4" },
            ModelPatternRule { any_of: &["coder"], all_of: &[], display: "DeepSeek Coder" },
        ],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "minimax",
        model_keywords: &["minimax"],
        tool_keywords: &[],
        default_model_id: "minimax",
        default_display_name: "MiniMax",
        brand_color: "#06B6D4", // Electric Mint
        brand_icon: "bolt",
        patterns: &[
            ModelPatternRule { any_of: &["m3"], all_of: &[], display: "MiniMax M3" },
            ModelPatternRule { any_of: &["m2.7"], all_of: &[], display: "MiniMax M2.7" },
        ],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "omp",
        model_keywords: &["glm", "qwen", "omen"],
        tool_keywords: &["omp"],
        default_model_id: "omp",
        default_display_name: "OMP Agent",
        brand_color: "#EC4899", // Vibrant Rose
        brand_icon: "memory",
        patterns: &[],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
    ModelBrandRule {
        tool_id: "opencode",
        model_keywords: &["opencode"],
        tool_keywords: &["opencode"],
        default_model_id: "opencode",
        default_display_name: "OpenCode",
        brand_color: "#10B981", // OpenCode Emerald
        brand_icon: "terminal",
        patterns: &[],
        strip_prefixes: &[],
        prefix_format: None,
        resolve_inner: false,
        adopt_inner_style: false,
    },
];

fn load_custom_agent_rules() -> Vec<CustomAgentRule> {
    let candidate_paths = [
        crate::domain::branding::config_home().join("astral-plasma").join("settings.json"),
        std::path::PathBuf::from("config/settings.json"),
    ];
    for path in &candidate_paths {
        if let Ok(content) = std::fs::read_to_string(path) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(rules) = v.get("ai").and_then(|a| a.get("agents")).and_then(|ag| ag.get("custom_rules")) {
                    if let Ok(parsed) = serde_json::from_value::<Vec<CustomAgentRule>>(rules.clone()) {
                        return parsed;
                    }
                }
            }
        }
    }
    Vec::new()
}

/// Resolves raw model name and agent tool source into a standardized identity with brand aesthetics.
pub fn resolve_model_metadata(raw_model: &str, tool_source: &str) -> AiAgentIdentity {
    let unescaped_model = if raw_model.trim().starts_with('{') {
        serde_json::from_str::<serde_json::Value>(raw_model)
            .ok()
            .and_then(|v| v.get("id").and_then(|id| id.as_str().map(|s| s.to_string())))
            .unwrap_or_else(|| raw_model.to_string())
    } else {
        raw_model.to_string()
    };
    let raw_model = unescaped_model.as_str();
    let lower_model = raw_model.trim().to_lowercase();
    let lower_tool = tool_source.trim().to_lowercase();

    // 1. Check custom overrides configured by the user in settings.json
    let custom_rules = load_custom_agent_rules();
    for custom in &custom_rules {
        let matches_model = custom.model_keywords.iter().any(|kw| lower_model.contains(&kw.to_lowercase()));
        let matches_tool = custom.tool_keywords.iter().any(|kw| lower_tool.contains(&kw.to_lowercase()));
        if matches_model || matches_tool {
            let display = custom.display_name.clone().unwrap_or_else(|| {
                if raw_model.is_empty() {
                    custom.tool_id.clone()
                } else {
                    format_clean_model_name(raw_model)
                }
            });
            return AiAgentIdentity {
                tool_source: custom.tool_id.clone(),
                model_id: if raw_model.is_empty() { custom.tool_id.clone() } else { raw_model.to_string() },
                display_name: display,
                brand_color: custom.brand_color.clone(),
                brand_icon: custom.brand_icon.clone(),
            };
        }
    }

    // 2. Evaluate declarative static catalog rules
    for rule in STATIC_BRAND_RULES {
        let matches_tool = rule.tool_keywords.iter().any(|&kw| lower_tool.contains(kw));
        let matches_model = rule.model_keywords.iter().any(|&kw| {
            if kw.ends_with('/') {
                lower_model.starts_with(kw)
            } else {
                lower_model.contains(kw)
            }
        });

        if matches_tool || matches_model {
            let mut matched_display: Option<String> = None;

            for pat in rule.patterns {
                if pat.matches(&lower_model) {
                    matched_display = Some(pat.display.to_string());
                    break;
                }
            }

            let display = matched_display.unwrap_or_else(|| {
                if raw_model.is_empty() {
                    rule.default_display_name.to_string()
                } else if rule.resolve_inner {
                    let inner = resolve_model_metadata(raw_model, "");
                    let inner_name = if inner.display_name != "AI Agent" && !inner.display_name.is_empty() {
                        inner.display_name
                    } else {
                        format_clean_model_name(raw_model)
                    };
                    if let Some(fmt) = rule.prefix_format {
                        fmt.replace("{}", &inner_name)
                    } else {
                        inner_name
                    }
                } else if !rule.strip_prefixes.is_empty() {
                    let mut clean = raw_model.to_string();
                    for prefix in rule.strip_prefixes {
                        clean = clean.replace(prefix, "");
                    }
                    let cleaned_name = format_clean_model_name(&clean);
                    if let Some(fmt) = rule.prefix_format {
                        fmt.replace("{}", &cleaned_name)
                    } else {
                        cleaned_name
                    }
                } else if let Some(fmt) = rule.prefix_format {
                    fmt.replace("{}", &format_clean_model_name(raw_model))
                } else {
                    let clean = format_clean_model_name(raw_model);
                    if clean.eq_ignore_ascii_case("gemini flash") {
                        "Gemini Flash 3.8".to_string()
                    } else if clean.eq_ignore_ascii_case("gemini pro") {
                        "Gemini Pro 3.8".to_string()
                    } else {
                        clean
                    }
                }
            });

            let (color, icon) = if rule.adopt_inner_style && !raw_model.is_empty() {
                let inner = resolve_model_metadata(raw_model, "");
                let c = if inner.brand_color != "#10B981" && inner.brand_color != "#9bcbfb" {
                    inner.brand_color
                } else {
                    rule.brand_color.to_string()
                };
                let ic = if inner.brand_icon != "token" && inner.brand_icon != "code" {
                    inner.brand_icon
                } else {
                    rule.brand_icon.to_string()
                };
                (c, ic)
            } else {
                (rule.brand_color.to_string(), rule.brand_icon.to_string())
            };

            let model_id = if raw_model.is_empty() {
                rule.default_model_id.to_string()
            } else {
                raw_model.to_string()
            };

            return AiAgentIdentity {
                tool_source: rule.tool_id.to_string(),
                model_id,
                display_name: display,
                brand_color: color,
                brand_icon: icon,
            };
        }
    }

    // 3. Fallback generic identity
    AiAgentIdentity {
        tool_source: tool_source.to_string(),
        model_id: raw_model.to_string(),
        display_name: if raw_model.is_empty() { "AI Agent".to_string() } else { format_clean_model_name(raw_model) },
        brand_color: "#10B981".to_string(), // OpenCode / Terminal Emerald
        brand_icon: "token".to_string(),
    }
}

pub fn format_clean_model_name(raw: &str) -> String {
    let stripped = raw.split('/').last().unwrap_or(raw);
    let parts: Vec<String> = stripped
        .split(['-', '_', ':'])
        .filter(|s| !s.is_empty())
        .map(|s| {
            let lower = s.to_lowercase();
            match lower.as_str() {
                "gpt" => "GPT".to_string(),
                "r1" => "R1".to_string(),
                "ai" => "AI".to_string(),
                "glm" => "GLM".to_string(),
                "api" => "API".to_string(),
                "deepseek" => "DeepSeek".to_string(),
                "minimax" => "MiniMax".to_string(),
                _ => {
                    let mut c = s.chars();
                    match c.next() {
                        None => String::new(),
                        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
                    }
                }
            }
        })
        .collect();
    if parts.is_empty() {
        return raw.to_string();
    }
    parts.join(" ")
}
