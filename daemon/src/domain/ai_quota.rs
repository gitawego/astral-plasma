use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct QuotaWindow {
    pub label: String,
    pub used_percent: f64,
    pub remaining_percent: f64,
    pub reset_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProviderAccount {
    pub id: String,
    pub label: String,
    pub identity: String,
    pub is_active: bool,
    pub plan_type: Option<String>,
    pub five_hour_remaining_percent: Option<f64>,
    pub weekly_remaining_percent: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AiProviderQuota {
    pub provider_id: String,
    pub display_name: String,
    pub icon: String,
    pub plan_type: Option<String>,
    pub account_email: Option<String>,
    pub account_name: Option<String>,
    pub is_available: bool,
    pub windows: Vec<QuotaWindow>,
    pub accounts: Vec<ProviderAccount>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AiQuotaSnapshot {
    pub providers: Vec<AiProviderQuota>,
    pub highest_used_percent: f64,
    pub lowest_remaining_percent: f64,
    pub warning_level: String, // "normal", "warning", "critical"
    pub fetched_at: String,
    pub active_gemini_email: Option<String>,
}

impl AiQuotaSnapshot {
    pub fn compute_metrics(&mut self, warning_thr: f64, critical_thr: f64) {
        let mut highest_used = 0.0f64;
        let mut lowest_rem = 100.0f64;

        for p in &self.providers {
            if !p.is_available {
                continue;
            }
            for w in &p.windows {
                if w.used_percent > highest_used {
                    highest_used = w.used_percent;
                }
                if w.remaining_percent < lowest_rem {
                    lowest_rem = w.remaining_percent;
                }
            }
        }

        self.highest_used_percent = (highest_used * 10.0).round() / 10.0;
        self.lowest_remaining_percent = (lowest_rem * 10.0).round() / 10.0;

        self.warning_level = if highest_used >= critical_thr {
            "critical".to_string()
        } else if highest_used >= warning_thr {
            "warning".to_string()
        } else {
            "normal".to_string()
        };
    }
}

pub fn provider_display_name(slug: &str) -> &'static str {
    match slug {
        "gemini" => "Google Gemini",
        "opencode-go" => "OpenCode Go",
        "xiaomi-mimo-cn" => "Xiaomi Mimo",
        "minimax-cn" => "MiniMax",
        "anthropic" => "Anthropic Claude",
        "openai" => "OpenAI",
        "deepseek" => "DeepSeek",
        "ollama" => "Ollama (Local)",
        _ => "AI Provider",
    }
}

pub fn provider_icon(slug: &str) -> &'static str {
    match slug {
        "gemini" => "spark",
        "opencode-go" => "terminal",
        "xiaomi-mimo-cn" => "smartphone",
        "minimax-cn" => "bolt",
        "anthropic" => "neurology",
        "openai" => "smart_toy",
        "deepseek" => "explore",
        _ => "auto_awesome",
    }
}

/// Parses the output of `agy --output-format json -p='/quota'` into an `AiProviderQuota`.
pub fn parse_agy_quota(json_str: &str, active_email: Option<String>) -> Result<AiProviderQuota, String> {
    let root: serde_json::Value = serde_json::from_str(json_str)
        .map_err(|e| format!("Invalid JSON from agy: {}", e))?;

    let groups = root
        .pointer("/command/data/groups")
        .or_else(|| root.get("groups"))
        .and_then(|g| g.as_array())
        .ok_or_else(|| "Missing groups array in agy quota response".to_string())?;

    let mut windows = Vec::new();

    // Prefer "Gemini Models" group
    let gemini_group = groups.iter().find(|g| {
        g.get("name")
            .and_then(|n| n.as_str())
            .map(|s| s.to_lowercase().contains("gemini"))
            .unwrap_or(false)
    }).or_else(|| groups.first());

    if let Some(group) = gemini_group {
        if let Some(buckets) = group.get("buckets").and_then(|b| b.as_array()) {
            for b in buckets {
                let win_label = match b.get("window").and_then(|w| w.as_str()) {
                    Some("5h") | Some("5-hour") => "5h".to_string(),
                    Some("weekly") | Some("week") => "weekly".to_string(),
                    Some("monthly") | Some("month") => "monthly".to_string(),
                    _ => {
                        let id = b.get("id").and_then(|i| i.as_str()).unwrap_or("");
                        if id.contains("5h") {
                            "5h".to_string()
                        } else if id.contains("week") {
                            "weekly".to_string()
                        } else {
                            "quota".to_string()
                        }
                    }
                };

                let remaining_fraction = b
                    .get("remaining_fraction")
                    .or_else(|| b.get("remainingFraction"))
                    .and_then(|f| f.as_f64())
                    .unwrap_or(1.0);

                let remaining_pct = (remaining_fraction * 100.0).clamp(0.0, 100.0);
                let used_pct = (100.0 - remaining_pct).clamp(0.0, 100.0);
                let reset_at = b
                    .get("reset_time")
                    .or_else(|| b.get("resetTime"))
                    .and_then(|r| r.as_str())
                    .map(|s| s.to_string());

                windows.push(QuotaWindow {
                    label: win_label,
                    used_percent: (used_pct * 10.0).round() / 10.0,
                    remaining_percent: (remaining_pct * 10.0).round() / 10.0,
                    reset_at,
                });
            }
        }
    }

    // Sort windows: 5h first, then weekly, then monthly
    windows.sort_by_key(|w| match w.label.as_str() {
        "5h" => 1,
        "weekly" => 2,
        "monthly" => 3,
        _ => 4,
    });

    Ok(AiProviderQuota {
        provider_id: "gemini".to_string(),
        display_name: "Google Gemini (Antigravity)".to_string(),
        icon: "spark".to_string(),
        plan_type: Some("Google AI Pro".to_string()),
        account_email: active_email.clone(),
        account_name: active_email,
        is_available: !windows.is_empty(),
        windows,
        accounts: Vec::new(),
        error_message: None,
    })
}

/// Parses the official OpenCode Go quota endpoint response (`https://opencode.ai/zen/go/v1/usage`).
pub fn parse_opencode_usage(json_str: &str) -> Result<AiProviderQuota, String> {
    let root: serde_json::Value = serde_json::from_str(json_str)
        .map_err(|e| format!("Invalid JSON from opencode usage: {}", e))?;

    let usage = root
        .get("usage")
        .and_then(|u| u.as_object())
        .ok_or_else(|| "Missing usage object in OpenCode Go response".to_string())?;

    let mut windows = Vec::new();

    for (key, label) in [("rolling", "5h"), ("weekly", "weekly"), ("monthly", "monthly")] {
        if let Some(entry) = usage.get(key) {
            let pct = entry
                .get("percent")
                .or_else(|| entry.get("usagePercent"))
                .and_then(|p| p.as_f64().or_else(|| p.as_str().and_then(|s| s.parse().ok())));

            if let Some(used) = pct {
                let used_clamped = used.clamp(0.0, 100.0);
                let remaining_clamped = (100.0 - used_clamped).clamp(0.0, 100.0);
                let reset_at = entry
                    .get("resetsAt")
                    .and_then(|r| r.as_str())
                    .map(|s| s.to_string());

                windows.push(QuotaWindow {
                    label: label.to_string(),
                    used_percent: (used_clamped * 10.0).round() / 10.0,
                    remaining_percent: (remaining_clamped * 10.0).round() / 10.0,
                    reset_at,
                });
            }
        }
    }

    Ok(AiProviderQuota {
        provider_id: "opencode-go".to_string(),
        display_name: "OpenCode Go".to_string(),
        icon: "terminal".to_string(),
        plan_type: Some("Go Plan".to_string()),
        account_email: None,
        account_name: None,
        is_available: !windows.is_empty(),
        windows,
        accounts: Vec::new(),
        error_message: None,
    })
}

/// Parses `quotas.json` from token-tracker cache.
/// Verifies the active Gemini account against `active_gemini_email`.
/// If `active_gemini_email` is provided and does not match the active account in `quotas.json`,
/// returns an Err("stale_gemini_account") so the caller can refresh Gemini with SSOT.
pub fn parse_token_tracker_quotas(
    json_str: &str,
    active_gemini_email: Option<&str>,
    warning_thr: f64,
    critical_thr: f64,
) -> Result<AiQuotaSnapshot, String> {
    let root: serde_json::Value = serde_json::from_str(json_str)
        .map_err(|e| format!("Failed to parse quotas.json: {}", e))?;

    let providers_arr = root
        .get("providers")
        .and_then(|p| p.as_array())
        .ok_or_else(|| "Missing providers array in quotas.json".to_string())?;

    let mut out_providers = Vec::new();

    for p in providers_arr {
        let provider_id = p
            .get("provider_id")
            .and_then(|id| id.as_str())
            .unwrap_or("");

        // Only include recognized coding / plan providers
        if !["gemini", "opencode-go", "xiaomi-mimo-cn", "minimax-cn"].contains(&provider_id) {
            continue;
        }

        let is_available = p.get("is_available").and_then(|b| b.as_bool()).unwrap_or(true);
        let error_msg = if p.get("type").and_then(|t| t.as_str()) == Some("failure") {
            p.get("message").and_then(|m| m.as_str()).map(|s| s.to_string())
        } else {
            None
        };

        let mut windows = Vec::new();
        if let Some(win_arr) = p.get("windows").and_then(|w| w.as_array()) {
            for w in win_arr {
                let label = w.get("window_label").and_then(|l| l.as_str()).unwrap_or("window");
                let used = w.get("used").and_then(|u| u.as_f64()).unwrap_or(0.0);
                let total = w.get("total").and_then(|t| t.as_f64()).unwrap_or(100.0);
                let used_pct = if total > 0.0 { (used / total) * 100.0 } else { 0.0 };
                let rem_pct = (100.0 - used_pct).clamp(0.0, 100.0);
                let reset_at = w.get("reset_at").and_then(|r| r.as_str()).map(|s| s.to_string());

                windows.push(QuotaWindow {
                    label: label.to_string(),
                    used_percent: (used_pct * 10.0).round() / 10.0,
                    remaining_percent: (rem_pct * 10.0).round() / 10.0,
                    reset_at,
                });
            }
        }

        let mut accounts = Vec::new();
        let mut active_acc_email = p.get("account_email").and_then(|e| e.as_str()).map(|s| s.to_string());
        let active_acc_name = p.get("account_name").and_then(|n| n.as_str()).map(|s| s.to_string());
        let plan_type = p.get("plan_type").and_then(|pt| pt.as_str()).map(|s| s.to_string());

        if let Some(acc_arr) = p.get("accounts").and_then(|a| a.as_array()) {
            for a in acc_arr {
                let id = a.get("id").and_then(|i| i.as_str()).unwrap_or("").to_string();
                let label = a.get("label").and_then(|l| l.as_str()).unwrap_or("").to_string();
                let identity = a.get("identity").and_then(|id| id.as_str()).unwrap_or("").to_string();
                let is_act = a.get("is_active").and_then(|act| act.as_bool()).unwrap_or(false);
                let is_agy = a.get("is_antigravity_active").and_then(|act| act.as_bool()).unwrap_or(false);
                let five_hr = a.get("five_hour_remaining_percent").and_then(|f| f.as_f64());
                let weekly = a.get("weekly_remaining_percent").and_then(|w| w.as_f64());

                if (is_act || is_agy) && active_acc_email.is_none() && !identity.is_empty() {
                    active_acc_email = Some(identity.clone());
                }

                accounts.push(ProviderAccount {
                    id,
                    label,
                    identity,
                    is_active: is_act || is_agy,
                    plan_type: a.get("plan_type").and_then(|pt| pt.as_str()).map(|s| s.to_string()),
                    five_hour_remaining_percent: five_hr,
                    weekly_remaining_percent: weekly,
                });
            }
        }

        // Gemini Single Source of Truth validation:
        if provider_id == "gemini" {
            if let Some(target_email) = active_gemini_email {
                let current_email = active_acc_email.as_deref().unwrap_or("");
                if !current_email.is_empty() && !current_email.eq_ignore_ascii_case(target_email) {
                    return Err(format!(
                        "stale_gemini_account: cache has '{}', but keyring SSOT has '{}'",
                        current_email, target_email
                    ));
                }
            }
        }

        out_providers.push(AiProviderQuota {
            provider_id: provider_id.to_string(),
            display_name: provider_display_name(provider_id).to_string(),
            icon: provider_icon(provider_id).to_string(),
            plan_type,
            account_email: active_acc_email,
            account_name: active_acc_name,
            is_available: is_available && error_msg.is_none(),
            windows,
            accounts,
            error_message: error_msg,
        });
    }

    let mut snapshot = AiQuotaSnapshot {
        providers: out_providers,
        highest_used_percent: 0.0,
        lowest_remaining_percent: 100.0,
        warning_level: "normal".to_string(),
        fetched_at: root.get("fetched_at").and_then(|f| f.as_str()).unwrap_or("").to_string(),
        active_gemini_email: active_gemini_email.map(|s| s.to_string()),
    };

    snapshot.compute_metrics(warning_thr, critical_thr);
    Ok(snapshot)
}
