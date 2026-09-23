use crate::domain::ai_quota::{
    parse_agy_quota, parse_opencode_usage, parse_token_tracker_quotas,
    AiProviderQuota, AiQuotaSnapshot, ProviderAccount,
};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime};

pub struct AiQuotaAdapter {
    custom_cache_dir: Option<PathBuf>,
}

impl Default for AiQuotaAdapter {
    fn default() -> Self {
        Self { custom_cache_dir: None }
    }
}

impl AiQuotaAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_cache_dir(dir: PathBuf) -> Self {
        Self { custom_cache_dir: Some(dir) }
    }

    fn get_home() -> Option<PathBuf> {
        std::env::var("HOME").ok().map(PathBuf::from)
    }

    fn get_token_tracker_cache_file(&self) -> Option<PathBuf> {
        if let Some(ref d) = self.custom_cache_dir {
            return Some(d.join("quotas.json"));
        }
        let home = Self::get_home()?;
        Some(home.join(".cache/token-tracker/quotas.json"))
    }

    fn get_gemini_cli_token_file() -> Option<PathBuf> {
        let home = Self::get_home()?;
        Some(home.join(".gemini/antigravity-cli/antigravity-oauth-token"))
    }

    fn get_gemini_accounts_dir() -> Option<PathBuf> {
        let home = Self::get_home()?;
        Some(home.join(".config/token-tracker/accounts/gemini"))
    }

    /// Single Source of Truth (SSOT): Resolves the currently active Gemini account identity.
    /// Checks Desktop Keyring (service: gemini, username: antigravity) first.
    /// Extracts email from the id_token JWT payload if available.
    /// If not in id_token, extracts refresh_token and matches against ~/.config/token-tracker/accounts/gemini/*.json.
    /// Fallback: checks ~/.gemini/antigravity-cli/antigravity-oauth-token refresh_token.
    pub fn get_active_gemini_email(&self) -> Option<String> {
        // 1. Check Desktop Keyring via secret-tool
        if let Ok(output) = Command::new("secret-tool")
            .args(["lookup", "service", "gemini", "username", "antigravity"])
            .output()
        {
            if output.status.success() && !output.stdout.is_empty() {
                let raw = String::from_utf8_lossy(&output.stdout);
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) {
                    // Try decoding email from id_token JWT
                    if let Some(id_token) = v.get("id_token").and_then(|t| t.as_str()) {
                        if let Some(email) = Self::decode_email_from_jwt(id_token) {
                            if !email.is_empty() {
                                return Some(email);
                            }
                        }
                    }

                    // Try matching refresh_token against stored accounts
                    let refresh_token = v
                        .pointer("/token/refresh_token")
                        .or_else(|| v.get("refresh_token"))
                        .and_then(|t| t.as_str())
                        .unwrap_or("");

                    if !refresh_token.is_empty() {
                        if let Some(email) = Self::find_account_email_by_token(refresh_token) {
                            return Some(email);
                        }
                    }
                }
            }
        }

        // 2. Check ~/.gemini/antigravity-cli/antigravity-oauth-token
        if let Some(token_path) = Self::get_gemini_cli_token_file() {
            if let Ok(content) = fs::read_to_string(token_path) {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(refresh_token) = v.pointer("/token/refresh_token").and_then(|t| t.as_str()) {
                        if !refresh_token.is_empty() {
                            if let Some(email) = Self::find_account_email_by_token(refresh_token) {
                                return Some(email);
                            }
                        }
                    }
                }
            }
        }

        None
    }

    /// Decodes the email claim from an unencrypted JWT id_token without external dependencies.
    fn decode_email_from_jwt(jwt: &str) -> Option<String> {
        let parts: Vec<&str> = jwt.split('.').collect();
        if parts.len() < 2 {
            return None;
        }

        let payload_b64 = parts[1];
        // Standard / URL-safe base64 decoding with padding
        let mut padded = payload_b64.replace('-', "+").replace('_', "/");
        while padded.len() % 4 != 0 {
            padded.push('=');
        }

        // Simple manual or byte decode via serde_json after base64 decode
        let decoded_bytes = Self::base64_decode(&padded)?;
        let json_str = String::from_utf8(decoded_bytes).ok()?;
        let v: serde_json::Value = serde_json::from_str(&json_str).ok()?;
        v.get("email").and_then(|e| e.as_str()).map(|s| s.to_string())
    }

    fn base64_decode(input: &str) -> Option<Vec<u8>> {
        const B64_CHARS: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut result = Vec::new();
        let mut buf = 0u32;
        let mut bits = 0;

        for &byte in input.as_bytes() {
            if byte == b'=' {
                break;
            }
            let val = match B64_CHARS.iter().position(|&c| c == byte) {
                Some(idx) => idx as u32,
                None => continue,
            };
            buf = (buf << 6) | val;
            bits += 6;
            if bits >= 8 {
                bits -= 8;
                result.push((buf >> bits) as u8);
                buf &= (1 << bits) - 1;
            }
        }

        if result.is_empty() { None } else { Some(result) }
    }

    /// Matches a refresh_token or access_token against accounts in ~/.config/token-tracker/accounts/gemini/*.json
    fn find_account_email_by_token(token_str: &str) -> Option<String> {
        let dir = Self::get_gemini_accounts_dir()?;
        if !dir.exists() {
            return None;
        }

        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) == Some("json") {
                    if let Ok(content) = fs::read_to_string(&path) {
                        if content.contains(token_str) {
                            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                                if let Some(identity) = v.get("identity").and_then(|i| i.as_str()) {
                                    if !identity.is_empty() {
                                        return Some(identity.to_string());
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        None
    }

    /// Loads all configured Gemini accounts from ~/.config/token-tracker/accounts/gemini/*.json
    pub fn load_configured_gemini_accounts(&self, active_email: Option<&str>) -> Vec<ProviderAccount> {
        let mut accounts = Vec::new();
        let dir = match Self::get_gemini_accounts_dir() {
            Some(d) => d,
            None => return accounts,
        };

        if !dir.exists() {
            return accounts;
        }

        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) == Some("json") {
                    if let Ok(content) = fs::read_to_string(&path) {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                            let id = v.get("id").and_then(|i| i.as_str()).unwrap_or("").to_string();
                            let label = v.get("label").and_then(|l| l.as_str()).unwrap_or("").to_string();
                            let identity = v.get("identity").and_then(|id| id.as_str()).unwrap_or("").to_string();
                            let is_act = match active_email {
                                Some(ae) => identity.eq_ignore_ascii_case(ae),
                                None => v.get("is_active").and_then(|a| a.as_bool()).unwrap_or(false),
                            };

                            accounts.push(ProviderAccount {
                                id,
                                label,
                                identity,
                                is_active: is_act,
                                plan_type: Some("Google AI Pro".to_string()),
                                five_hour_remaining_percent: None,
                                weekly_remaining_percent: None,
                            });
                        }
                    }
                }
            }
        }

        accounts.sort_by(|a, b| b.is_active.cmp(&a.is_active).then_with(|| a.identity.cmp(&b.identity)));
        accounts
    }

    /// Switches the active Gemini account directly in the Desktop Keyring and Antigravity CLI token file.
    pub fn switch_gemini_account(&self, target_id_or_email: &str) -> Result<String, String> {
        let dir = Self::get_gemini_accounts_dir()
            .ok_or_else(|| "Cannot find gemini accounts directory".to_string())?;

        let mut target_account: Option<(String, String, serde_json::Value)> = None;

        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) == Some("json") {
                    if let Ok(content) = fs::read_to_string(&path) {
                        if let Ok(mut v) = serde_json::from_str::<serde_json::Value>(&content) {
                            let id = v.get("id").and_then(|i| i.as_str()).unwrap_or("").to_string();
                            let identity = v.get("identity").and_then(|i| i.as_str()).unwrap_or("").to_string();

                            let is_target = id == target_id_or_email || identity.eq_ignore_ascii_case(target_id_or_email);
                            if is_target {
                                target_account = Some((id.clone(), identity.clone(), v.clone()));
                                if let Some(obj) = v.as_object_mut() {
                                    obj.insert("is_active".to_string(), serde_json::Value::Bool(true));
                                }
                            } else if let Some(obj) = v.as_object_mut() {
                                obj.insert("is_active".to_string(), serde_json::Value::Bool(false));
                            }

                            // Write back is_active status
                            if let Ok(updated_json) = serde_json::to_string_pretty(&v) {
                                let _ = fs::write(&path, updated_json);
                            }
                        }
                    }
                }
            }
        }

        let (_target_id, target_email, target_json) = target_account
            .ok_or_else(|| format!("Account '{}' not found", target_id_or_email))?;

        let raw_cred = target_json.get("credential").and_then(|c| c.as_str()).unwrap_or("");
        if raw_cred.is_empty() {
            return Err("Account has no credential stored".to_string());
        }

        // Update Desktop Keyring via secret-tool
        let mut child = Command::new("secret-tool")
            .args(["store", "--label=gemini", "service", "gemini", "username", "antigravity"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to spawn secret-tool: {}", e))?;

        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(raw_cred.as_bytes());
        }
        let _ = child.wait();

        // Update ~/.gemini/antigravity-cli/antigravity-oauth-token
        if let Some(cli_token_path) = Self::get_gemini_cli_token_file() {
            if let Some(parent) = cli_token_path.parent() {
                let _ = fs::create_dir_all(parent);
            }

            let cred_obj: serde_json::Value = serde_json::from_str(raw_cred).unwrap_or_else(|_| serde_json::json!({}));
            let access_tok = cred_obj.get("access_token").and_then(|t| t.as_str()).unwrap_or("");
            let refresh_tok = cred_obj.get("refresh_token").and_then(|t| t.as_str()).unwrap_or("");

            let token_payload = serde_json::json!({
                "token": {
                    "access_token": access_tok,
                    "token_type": "Bearer",
                    "refresh_token": refresh_tok,
                    "expiry": "2030-01-01T00:00:00Z"
                },
                "auth_method": "consumer"
            });

            if let Ok(json_str) = serde_json::to_string_pretty(&token_payload) {
                let _ = fs::write(&cli_token_path, json_str);
            }
        }

        // Update .antigravity_last_active marker in accounts directory
        if let Some(dir) = Self::get_gemini_accounts_dir() {
            let _ = fs::write(dir.join(".antigravity_last_active"), &target_email);
        }

        Ok(target_email)
    }

    /// Queries live OpenCode Go usage using local credentials
    fn query_opencode_usage(&self) -> Option<AiProviderQuota> {
        let home = Self::get_home()?;

        // Discover API key
        let mut api_key = std::env::var("TOKEN_OPENCODE_GO").ok();

        if api_key.is_none() {
            let cred_file = home.join(".config/token-tracker/credentials.json");
            if let Ok(content) = fs::read_to_string(cred_file) {
                if let Ok(creds) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(k) = creds.get("opencode-go").and_then(|k| k.as_str()) {
                        api_key = Some(k.to_string());
                    }
                }
            }
        }

        if api_key.is_none() {
            let opencode_dir = home.join(".config/token-tracker/accounts/opencode-go");
            if let Ok(entries) = fs::read_dir(opencode_dir) {
                for entry in entries.flatten() {
                    if let Ok(c) = fs::read_to_string(entry.path()) {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&c) {
                            if let Some(k) = v.get("credential").and_then(|k| k.as_str()) {
                                if !k.is_empty() {
                                    api_key = Some(k.to_string());
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        let key = api_key?;
        let output = Command::new("curl")
            .args([
                "-s",
                "-m", "5",
                "-H", &format!("Authorization: Bearer {}", key),
                "https://opencode.ai/zen/go/v1/usage",
            ])
            .output()
            .ok()?;

        if output.status.success() {
            let body = String::from_utf8_lossy(&output.stdout);
            parse_opencode_usage(&body).ok()
        } else {
            None
        }
    }

    /// Queries live Gemini quota using `agy --output-format json -p='/quota'`
    fn query_agy_quota(&self, active_email: Option<String>) -> Option<AiProviderQuota> {
        let output = Command::new("agy")
            .args(["--output-format", "json", "-p=/quota"])
            .output()
            .ok()?;

        if output.status.success() {
            let body = String::from_utf8_lossy(&output.stdout);
            let mut quota = parse_agy_quota(&body, active_email.clone()).ok()?;
            quota.accounts = self.load_configured_gemini_accounts(active_email.as_deref());
            Some(quota)
        } else {
            None
        }
    }

    /// Aggregated snapshot fetcher:
    /// 1. Resolves active Gemini identity from Desktop Keyring SSOT.
    /// 2. If fresh cache exists (< 5 min) and matches active identity, returns it.
    /// 3. Otherwise, autonomously polls `agy` and OpenCode Go.
    pub fn get_snapshot(&self, warning_thr: f64, critical_thr: f64, force_refresh: bool) -> AiQuotaSnapshot {
        let active_gemini_email = self.get_active_gemini_email();

        // 1. Try reading token-tracker cache if not forcing refresh
        if !force_refresh {
            if let Some(cache_path) = self.get_token_tracker_cache_file() {
                if cache_path.exists() {
                    let is_fresh = fs::metadata(&cache_path)
                        .and_then(|m| m.modified())
                        .map(|mtime| {
                            SystemTime::now()
                                .duration_since(mtime)
                                .unwrap_or(Duration::from_secs(9999))
                                < Duration::from_secs(300)
                        })
                        .unwrap_or(false);

                    if is_fresh {
                        if let Ok(content) = fs::read_to_string(&cache_path) {
                            if let Ok(mut snap) = parse_token_tracker_quotas(
                                &content,
                                active_gemini_email.as_deref(),
                                warning_thr,
                                critical_thr,
                            ) {
                                // Enrich gemini accounts with all configured identities
                                for p in &mut snap.providers {
                                    if p.provider_id == "gemini" && p.accounts.is_empty() {
                                        p.accounts = self.load_configured_gemini_accounts(active_gemini_email.as_deref());
                                    }
                                }
                                return snap;
                            }
                        }
                    }
                }
            }
        }

        // 2. Autonomous fallback: query agy and OpenCode directly
        let mut providers = Vec::new();

        if let Some(gemini) = self.query_agy_quota(active_gemini_email.clone()) {
            providers.push(gemini);
        }

        if let Some(opencode) = self.query_opencode_usage() {
            providers.push(opencode);
        }

        let now_rfc3339 = chrono_lite_rfc3339();

        let mut snapshot = AiQuotaSnapshot {
            providers,
            highest_used_percent: 0.0,
            lowest_remaining_percent: 100.0,
            warning_level: "normal".to_string(),
            fetched_at: now_rfc3339,
            active_gemini_email,
        };

        snapshot.compute_metrics(warning_thr, critical_thr);
        snapshot
    }
}

fn chrono_lite_rfc3339() -> String {
    // Generate ISO timestamp without requiring chrono crate if system time is sufficient
    use std::time::UNIX_EPOCH;
    let dur = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    format!("{}.{:03}Z", dur.as_secs(), dur.subsec_millis())
}
