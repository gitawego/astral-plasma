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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub monthly_remaining_percent: Option<f64>,
    #[serde(default)]
    pub windows: Vec<QuotaWindow>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct TokenCacheStats {
    pub cached_tokens: u64,
    pub uncached_input_tokens: u64,
    pub output_tokens: u64,
    pub total_prompt_tokens: u64,
    pub cache_hit_rate_percent: f64,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_stats: Option<TokenCacheStats>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AiQuotaSnapshot {
    pub providers: Vec<AiProviderQuota>,
    pub highest_used_percent: f64,
    pub lowest_remaining_percent: f64,
    pub warning_level: String, // "normal", "warning", "critical"
    pub fetched_at: String,
    pub active_gemini_email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub global_cache_stats: Option<TokenCacheStats>,
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

/// Extracts an actionable failure message from a provider's quota response body.
///
/// Several providers answer HTTP 200 with an error envelope, so a body that parses
/// but carries no quota windows is indistinguishable from a healthy empty payload
/// unless the envelope is read. The panel would otherwise render a blank provider
/// with no explanation. `None` means "this body reports nothing wrong".
pub fn provider_failure_message(body: &str) -> Option<String> {
    let root: serde_json::Value = serde_json::from_str(body).ok()?;

    if let Some(message) = root.pointer("/error/message").and_then(|m| m.as_str()) {
        let message = message.trim();
        if !message.is_empty() {
            return Some(actionable_provider_message(message));
        }
    }

    if let Some(code) = root
        .pointer("/base_resp/status_code")
        .and_then(|c| c.as_i64())
    {
        if code != 0 {
            let message = root
                .pointer("/base_resp/status_msg")
                .and_then(|m| m.as_str())
                .unwrap_or("provider rejected the stored credentials");
            return Some(actionable_provider_message(message));
        }
    }

    None
}

/// Collapses a provider's raw error text into one sentence a user can act on.
fn actionable_provider_message(server_message: &str) -> String {
    const AUTH_HINTS: [&str; 6] = [
        "unauthorized",
        "cookie",
        "login",
        "auth",
        "expired",
        "credential",
    ];
    let lowered = server_message.to_lowercase();
    if AUTH_HINTS.iter().any(|hint| lowered.contains(hint)) {
        "Session expired — sign in again".to_string()
    } else {
        format!("Provider error: {}", server_message)
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

    // Iterate through groups (Gemini group first, then others for any additional windows like monthly)
    let mut ordered_groups: Vec<&serde_json::Value> = Vec::new();
    if let Some(g_idx) = groups.iter().position(|g| {
        g.get("name")
            .or_else(|| g.get("displayName"))
            .and_then(|n| n.as_str())
            .map(|s| s.to_lowercase().contains("gemini"))
            .unwrap_or(false)
    }) {
        ordered_groups.push(&groups[g_idx]);
        for (i, g) in groups.iter().enumerate() {
            if i != g_idx {
                ordered_groups.push(g);
            }
        }
    } else {
        ordered_groups.extend(groups.iter());
    }

    for group in ordered_groups {
        if let Some(buckets) = group.get("buckets").and_then(|b| b.as_array()) {
            for b in buckets {
                let win_label = match b.get("window").and_then(|w| w.as_str()) {
                    Some("5h") | Some("5-hour") => "5h".to_string(),
                    Some("weekly") | Some("week") => "weekly".to_string(),
                    Some("monthly") | Some("month") => "monthly".to_string(),
                    _ => {
                        let id = b
                            .get("id")
                            .or_else(|| b.get("bucketId"))
                            .or_else(|| b.get("displayName"))
                            .or_else(|| b.get("name"))
                            .and_then(|i| i.as_str())
                            .unwrap_or("")
                            .to_lowercase();
                        if id.contains("5h") || id.contains("5-hour") || id.contains("rolling") {
                            "5h".to_string()
                        } else if id.contains("week") {
                            "weekly".to_string()
                        } else if id.contains("month") {
                            "monthly".to_string()
                        } else {
                            "quota".to_string()
                        }
                    }
                };

                if windows.iter().any(|w: &QuotaWindow| w.label == win_label) {
                    continue;
                }

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
        cache_stats: None,
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
        cache_stats: None,
    })
}

/// Wall-clock budget `agy` gives its own silent (non-interactive) auth path.
///
/// Observed in `~/.gemini/antigravity-cli/log/cli-*.log` as
/// `keyringAuth: timed out after 10s, skipping keyring auth`. Once this budget is
/// exhausted the CLI abandons silent auth and, in print mode, escalates to an
/// interactive OAuth window in the user's browser.
pub const AGY_SILENT_AUTH_BUDGET_SECS: u64 = 10;

/// Hard bound for the passive `agy` quota probe.
///
/// Must stay strictly above [`AGY_SILENT_AUTH_BUDGET_SECS`]: a probe bounded at or
/// below the CLI's own auth budget is killed before it can answer, and the
/// orphaned OAuth escalation still opens a browser window afterwards.
pub const AGY_PROBE_TIMEOUT_SECS: u64 = 20;

/// Wall-clock budget for the Antigravity token endpoint (`oauth2.googleapis.com/token`).
///
/// Measured on this desktop: a cold TLS handshake alone reaches 9.6s and a refresh
/// POST has taken 60s on a congested link, while a 5s bound failed five consecutive
/// attempts. A timeout that short is not a hint — it silently leaves every stored
/// Gemini account holding a dead access token, so the quota panel goes blank for
/// every account except whichever one happens to refresh during a lucky window.
pub const GEMINI_HTTP_TIMEOUT_SECS: u64 = 30;

/// Wall-clock budget for the Cloud Code quota calls (`loadCodeAssist` and
/// `retrieveUserQuotaSummary`). Healthy responses measure 0.6-2.4s; this keeps
/// roughly 4x headroom without letting one degraded account stall a whole poll.
pub const GEMINI_QUOTA_TIMEOUT_SECS: u64 = 10;

/// Number of days in a proleptic Gregorian month.
fn agy_days_in_month(year: i64, month: i64) -> i64 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 => 29,
        2 => 28,
        _ => 0,
    }
}

/// Days since the Unix epoch for a proleptic Gregorian date (Howard Hinnant's civil algorithm).
fn agy_days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = if month > 2 { month - 3 } else { month + 9 };
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// Parses an RFC3339 / ISO-8601 timestamp into epoch seconds (UTC).
///
/// Accepts `YYYY-MM-DDTHH:MM:SS` followed by `Z`, a `+HH:MM` / `-HH:MM` offset, and
/// an optional fractional-second part. Returns `None` for anything malformed, so a
/// corrupt credential file can never be mistaken for a usable one.
pub fn parse_rfc3339_utc_secs(value: &str) -> Option<i64> {
    let bytes = value.as_bytes();
    if bytes.len() < 20 {
        return None;
    }
    let byte_at = |i: usize| -> Option<u8> { bytes.get(i).copied() };
    let digits = |from: usize, len: usize| -> Option<i64> {
        let part = value.get(from..from + len)?;
        if !part.bytes().all(|c| c.is_ascii_digit()) {
            return None;
        }
        part.parse::<i64>().ok()
    };

    if byte_at(4) != Some(b'-')
        || byte_at(7) != Some(b'-')
        || !matches!(byte_at(10), Some(b'T') | Some(b't'))
        || byte_at(13) != Some(b':')
        || byte_at(16) != Some(b':')
    {
        return None;
    }

    let year = digits(0, 4)?;
    let month = digits(5, 2)?;
    let day = digits(8, 2)?;
    let hour = digits(11, 2)?;
    let minute = digits(14, 2)?;
    let second = digits(17, 2)?;

    if !(1..=12).contains(&month)
        || day < 1
        || day > agy_days_in_month(year, month)
        || hour > 23
        || minute > 59
        || second > 60
    {
        return None;
    }
    // A leap second (60) still belongs to the second that just elapsed.
    let second = second.min(59);

    let mut idx = 19;
    if byte_at(idx) == Some(b'.') {
        idx += 1;
        let frac_start = idx;
        while matches!(byte_at(idx), Some(c) if c.is_ascii_digit()) {
            idx += 1;
        }
        if idx == frac_start {
            return None;
        }
    }

    let offset_secs = match byte_at(idx) {
        Some(b'Z') | Some(b'z') => {
            idx += 1;
            0
        }
        Some(sign @ (b'+' | b'-')) => {
            let hours = digits(idx + 1, 2)?;
            if byte_at(idx + 3) != Some(b':') {
                return None;
            }
            let minutes = digits(idx + 4, 2)?;
            if hours > 23 || minutes > 59 {
                return None;
            }
            idx += 6;
            let magnitude = hours * 3600 + minutes * 60;
            if sign == b'-' {
                -magnitude
            } else {
                magnitude
            }
        }
        _ => return None,
    };

    if idx != bytes.len() {
        return None;
    }

    Some(
        agy_days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second
            - offset_secs,
    )
}

/// Decides whether the passive `agy` quota probe may run.
///
/// `agy` answers `-p='/quota'` non-interactively only while its stored credential is
/// usable; an expired or missing token makes it escalate to an interactive OAuth
/// window in the user's browser. A background quota refresh must never hijack the
/// desktop like that, so anything other than a present, unexpired access token
/// fails closed.
pub fn agy_token_allows_probe(token_json: &str, now_secs: i64) -> bool {
    let root: serde_json::Value = match serde_json::from_str(token_json) {
        Ok(v) => v,
        Err(_) => return false,
    };

    let access_token = root
        .pointer("/token/access_token")
        .or_else(|| root.get("access_token"))
        .and_then(|t| t.as_str())
        .unwrap_or("");
    if access_token.trim().is_empty() {
        return false;
    }

    let expiry = root
        .pointer("/token/expiry")
        .or_else(|| root.get("expiry"))
        .and_then(|t| t.as_str())
        .unwrap_or("");

    match parse_rfc3339_utc_secs(expiry) {
        Some(expires_at) => expires_at > now_secs,
        None => false,
    }
}

/// Converts epoch milliseconds to an RFC3339 / ISO-8601 UTC timestamp string without external dependencies.
pub fn epoch_millis_to_rfc3339(ms: i64) -> String {
    let secs = ms / 1000;
    let mut days = secs / 86400;
    let mut rem_secs = (secs % 86400) as i32;
    if rem_secs < 0 {
        rem_secs += 86400;
        days -= 1;
    }
    let hours = rem_secs / 3600;
    let mins = (rem_secs % 3600) / 60;
    let s = rem_secs % 60;

    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };

    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", y, m, d, hours, mins, s)
}

/// Computes the next monthly reset timestamp in ISO-8601 UTC string format given epoch milliseconds and reset day of the month (1-28).
pub fn compute_next_monthly_reset_iso(now_ms: i64, reset_day: u32) -> String {
    let day_clamped = reset_day.clamp(1, 28);
    let secs = now_ms / 1000;
    let days = secs / 86400;
    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let cur_d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let cur_m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let cur_y = if cur_m <= 2 { y + 1 } else { y };

    let (next_y, next_m) = if cur_d < day_clamped {
        (cur_y, cur_m)
    } else if cur_m == 12 {
        (cur_y + 1, 1)
    } else {
        (cur_y, cur_m + 1)
    };

    format!("{:04}-{:02}-{:02}T00:00:00Z", next_y, next_m, day_clamped)
}

/// Generic parser for coding_plan/remains endpoints (MiniMax, Xiaomi MiMo).
pub fn parse_coding_plan_remains(
    provider_id: &str,
    display_name: &str,
    icon: &str,
    json_str: &str,
) -> Result<AiProviderQuota, String> {
    let v: serde_json::Value = serde_json::from_str(json_str)
        .map_err(|e| format!("Invalid JSON from {}: {}", display_name, e))?;

    if let Some(code) = v.pointer("/base_resp/status_code").and_then(|c| c.as_i64()) {
        if code == 2062 {
            return Ok(AiProviderQuota {
                provider_id: provider_id.to_string(),
                display_name: display_name.to_string(),
                icon: icon.to_string(),
                plan_type: Some("Pay-as-you-go".to_string()),
                account_email: None,
                account_name: None,
                is_available: true,
                windows: Vec::new(),
                accounts: Vec::new(),
                error_message: None,
                cache_stats: None,
            });
        }
        if code != 0 {
            let msg = v.pointer("/base_resp/status_msg")
                .and_then(|m| m.as_str())
                .unwrap_or("error");
            return Err(format!("{} error (status {}): {}", display_name, code, msg));
        }
    }

    let remains = v.get("model_remains")
        .and_then(|m| m.as_array())
        .ok_or_else(|| format!("Missing model_remains in {} response", display_name))?;

    let primary = remains.iter().find(|m| {
        m.get("model_name").and_then(|n| n.as_str()) == Some("general")
            && m.get("current_interval_remaining_percent").is_some()
    }).or_else(|| {
        remains.iter().find(|m| m.get("current_interval_remaining_percent").is_some())
    }).or_else(|| remains.first())
      .ok_or_else(|| format!("No models in {} remains", display_name))?;

    let mut windows = Vec::new();

    if let Some(rem) = primary.get("current_interval_remaining_percent").and_then(|r| r.as_f64()) {
        let rem_pct = rem.clamp(0.0, 100.0);
        let used_pct = (100.0 - rem_pct).clamp(0.0, 100.0);
        let reset_at = primary.get("end_time")
            .and_then(|ms| ms.as_i64())
            .map(epoch_millis_to_rfc3339);

        windows.push(QuotaWindow {
            label: "5h".to_string(),
            used_percent: (used_pct * 10.0).round() / 10.0,
            remaining_percent: (rem_pct * 10.0).round() / 10.0,
            reset_at,
        });
    }

    if let Some(rem) = primary.get("current_weekly_remaining_percent").and_then(|r| r.as_f64()) {
        let rem_pct = rem.clamp(0.0, 100.0);
        let used_pct = (100.0 - rem_pct).clamp(0.0, 100.0);
        let reset_at = primary.get("weekly_end_time")
            .and_then(|ms| ms.as_i64())
            .map(epoch_millis_to_rfc3339);

        windows.push(QuotaWindow {
            label: "weekly".to_string(),
            used_percent: (used_pct * 10.0).round() / 10.0,
            remaining_percent: (rem_pct * 10.0).round() / 10.0,
            reset_at,
        });
    }

    if let Some(rem) = primary.get("current_monthly_remaining_percent").and_then(|r| r.as_f64()) {
        let rem_pct = rem.clamp(0.0, 100.0);
        let used_pct = (100.0 - rem_pct).clamp(0.0, 100.0);
        let reset_at = primary.get("monthly_end_time")
            .and_then(|ms| ms.as_i64())
            .map(epoch_millis_to_rfc3339);

        windows.push(QuotaWindow {
            label: "monthly".to_string(),
            used_percent: (used_pct * 10.0).round() / 10.0,
            remaining_percent: (rem_pct * 10.0).round() / 10.0,
            reset_at,
        });
    }

    Ok(AiProviderQuota {
        provider_id: provider_id.to_string(),
        display_name: display_name.to_string(),
        icon: icon.to_string(),
        plan_type: Some("Coding Plan".to_string()),
        account_email: None,
        account_name: None,
        is_available: true,
        windows,
        accounts: Vec::new(),
        error_message: None,
        cache_stats: None,
    })
}

pub fn parse_minimax_usage(json_str: &str) -> Result<AiProviderQuota, String> {
    parse_coding_plan_remains("minimax-cn", "MiniMax", "bolt", json_str)
}

pub fn parse_xiaomi_usage(json_str: &str) -> Result<AiProviderQuota, String> {
    parse_coding_plan_remains("xiaomi-mimo-cn", "Xiaomi Mimo", "smartphone", json_str)
}

/// Parses `quotas.json` from cache if present.
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

                let is_current = if provider_id == "gemini" {
                    if let Some(target) = active_gemini_email {
                        identity.eq_ignore_ascii_case(target)
                    } else {
                        is_act || is_agy
                    }
                } else {
                    is_act || is_agy
                };

                if is_current && active_acc_email.is_none() && !identity.is_empty() {
                    active_acc_email = Some(identity.clone());
                }

                let mut acc_windows = Vec::new();
                if let Some(w_arr) = a.get("windows").and_then(|w| w.as_array()) {
                    for win in w_arr {
                        let label = win.get("label").and_then(|l| l.as_str()).unwrap_or("").to_string();
                        let used_pct = win.get("used_percent").and_then(|u| u.as_f64()).unwrap_or(0.0);
                        let rem_pct = win.get("remaining_percent").and_then(|r| r.as_f64()).unwrap_or(100.0);
                        let reset_at = win.get("reset_at").and_then(|r| r.as_str()).map(|s| s.to_string());
                        acc_windows.push(QuotaWindow {
                            label,
                            used_percent: used_pct,
                            remaining_percent: rem_pct,
                            reset_at,
                        });
                    }
                } else if is_current && !windows.is_empty() {
                    acc_windows = windows.clone();
                }

                accounts.push(ProviderAccount {
                    id,
                    label,
                    identity,
                    is_active: is_current,
                    plan_type: a.get("plan_type").and_then(|pt| pt.as_str()).map(|s| s.to_string()),
                    five_hour_remaining_percent: five_hr,
                    weekly_remaining_percent: weekly,
                    monthly_remaining_percent: None,
                    windows: acc_windows,
                });
            }
            accounts.sort_by(|a, b| a.identity.cmp(&b.identity));
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
            cache_stats: None,
        });
    }

    let mut snapshot = AiQuotaSnapshot {
        providers: out_providers,
        highest_used_percent: 0.0,
        lowest_remaining_percent: 100.0,
        warning_level: "normal".to_string(),
        fetched_at: root.get("fetched_at").and_then(|f| f.as_str()).unwrap_or("").to_string(),
        active_gemini_email: active_gemini_email.map(|s| s.to_string()),
        global_cache_stats: None,
    };

    snapshot.compute_metrics(warning_thr, critical_thr);
    Ok(snapshot)
}
