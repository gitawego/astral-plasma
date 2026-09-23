use crate::domain::ai_quota::{
    compute_next_monthly_reset_iso, epoch_millis_to_rfc3339, parse_agy_quota, parse_minimax_usage, parse_opencode_usage,
    parse_xiaomi_usage, AiProviderQuota, AiQuotaSnapshot, ProviderAccount, QuotaWindow,
};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime};

pub struct AiQuotaAdapter {
    custom_cache_dir: Option<PathBuf>,
    custom_config_dir: Option<PathBuf>,
    custom_legacy_config_dir: Option<PathBuf>,
}

impl Default for AiQuotaAdapter {
    fn default() -> Self {
        Self {
            custom_cache_dir: None,
            custom_config_dir: None,
            custom_legacy_config_dir: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct GeminiMonthlyConfig {
    pub enabled: bool,
    pub default_remaining_percent: f64,
    pub reset_day: u32,
}

impl Default for GeminiMonthlyConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            default_remaining_percent: 85.0,
            reset_day: 1,
        }
    }
}

impl AiQuotaAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_cache_dir(dir: PathBuf) -> Self {
        Self {
            custom_cache_dir: Some(dir),
            custom_config_dir: None,
            custom_legacy_config_dir: None,
        }
    }

    pub fn with_dirs(
        cache_dir: PathBuf,
        config_dir: PathBuf,
        legacy_config_dir: Option<PathBuf>,
    ) -> Self {
        Self {
            custom_cache_dir: Some(cache_dir),
            custom_config_dir: Some(config_dir),
            custom_legacy_config_dir: legacy_config_dir,
        }
    }

    fn get_home() -> Option<PathBuf> {
        std::env::var("HOME").ok().map(PathBuf::from)
    }

    pub fn get_config_dir(&self) -> Option<PathBuf> {
        if let Some(ref d) = self.custom_config_dir {
            return Some(d.clone());
        }
        let home = Self::get_home()?;
        Some(home.join(".config/astral-plasma"))
    }

    pub fn get_legacy_config_dir(&self) -> Option<PathBuf> {
        if let Some(ref d) = self.custom_legacy_config_dir {
            return Some(d.clone());
        }
        let home = Self::get_home()?;
        Some(home.join(".config/token-tracker"))
    }

    pub fn get_cache_file(&self) -> Option<PathBuf> {
        if let Some(ref d) = self.custom_cache_dir {
            return Some(d.join("ai_quotas.json"));
        }
        let home = Self::get_home()?;
        Some(home.join(".cache/astral-plasma/ai_quotas.json"))
    }


    pub fn get_gemini_cli_token_file() -> Option<PathBuf> {
        let home = Self::get_home()?;
        Some(home.join(".gemini/antigravity-cli/antigravity-oauth-token"))
    }

    pub fn get_gemini_jetski_token_file() -> Option<PathBuf> {
        let home = Self::get_home()?;
        Some(home.join(".gemini/jetski-standalone-oauth-token"))
    }

    pub fn get_gemini_accounts_dir(&self) -> Option<PathBuf> {
        let cfg = self.get_config_dir()?;
        Some(cfg.join("accounts/gemini"))
    }

    pub fn get_accounts_dir_for(&self, provider_id: &str) -> Option<PathBuf> {
        let cfg = self.get_config_dir()?;
        Some(cfg.join(format!("accounts/{}", provider_id)))
    }

    pub fn get_credentials_file(&self) -> Option<PathBuf> {
        let cfg = self.get_config_dir()?;
        Some(cfg.join("credentials.json"))
    }

    pub fn get_gemini_monthly_config(&self) -> GeminiMonthlyConfig {
        let mut cfg = GeminiMonthlyConfig::default();

        let candidate_paths = [
            self.get_config_dir().map(|d| d.join("settings.json")),
            Self::get_home().map(|h| h.join(".config/astral-plasma/settings.json")),
            Some(PathBuf::from("config/settings.json")),
        ];

        for opt_path in candidate_paths.into_iter().flatten() {
            if opt_path.exists() {
                if let Ok(content) = fs::read_to_string(&opt_path) {
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                        if let Some(ai_obj) = v.get("ai") {
                            if let Some(e) = ai_obj.get("geminiMonthlyEnabled").and_then(|b| b.as_bool()) {
                                cfg.enabled = e;
                            }
                            if let Some(r) = ai_obj.get("geminiMonthlyRemainingPercent").and_then(|n| n.as_f64()) {
                                cfg.default_remaining_percent = r;
                            }
                            if let Some(d) = ai_obj.get("geminiMonthlyResetDay").and_then(|n| n.as_u64()) {
                                cfg.reset_day = d as u32;
                            }

                            if let Some(nested) = ai_obj.get("geminiMonthlyQuota") {
                                if let Some(e) = nested.get("enabled").and_then(|b| b.as_bool()) {
                                    cfg.enabled = e;
                                }
                                if let Some(r) = nested.get("remainingPercent").and_then(|n| n.as_f64()) {
                                    cfg.default_remaining_percent = r;
                                }
                                if let Some(d) = nested.get("resetDay").and_then(|n| n.as_u64()) {
                                    cfg.reset_day = d as u32;
                                }
                            }
                            break;
                        }
                    }
                }
            }
        }

        cfg
    }

    /// Ensures self-contained storage under ~/.config/astral-plasma/accounts/.
    /// If no accounts exist in Astral Plasma:
    /// 1. Migrates existing accounts and credentials from ~/.config/token-tracker (one-time).
    /// 2. If token-tracker doesn't exist either, auto-bootstraps from Desktop Keyring
    ///    or ~/.gemini/antigravity-cli/antigravity-oauth-token.
    pub fn ensure_storage_migrated(&self) {
        let gemini_dir = match self.get_gemini_accounts_dir() {
            Some(d) => d,
            None => return,
        };

        let mut has_accounts = false;
        if gemini_dir.exists() {
            if let Ok(entries) = fs::read_dir(&gemini_dir) {
                for e in entries.flatten() {
                    if e.path().extension().and_then(|s| s.to_str()) == Some("json") {
                        has_accounts = true;
                        break;
                    }
                }
            }
        }

        if has_accounts {
            return;
        }

        // 1. One-time migration from legacy token-tracker if present
        if let Some(legacy_dir) = self.get_legacy_config_dir() {
            let legacy_accounts = legacy_dir.join("accounts");
            if legacy_accounts.exists() {
                let _ = fs::create_dir_all(&gemini_dir);
                if let Ok(entries) = fs::read_dir(&legacy_accounts) {
                    for prov_entry in entries.flatten() {
                        let prov_path = prov_entry.path();
                        if prov_path.is_dir() {
                            let prov_name = prov_path.file_name().unwrap_or_default();
                            if let Some(dest_prov_dir) =
                                self.get_accounts_dir_for(&prov_name.to_string_lossy())
                            {
                                let _ = fs::create_dir_all(&dest_prov_dir);
                                if let Ok(acc_files) = fs::read_dir(&prov_path) {
                                    for af in acc_files.flatten() {
                                        let p = af.path();
                                        if let Some(fname) = p.file_name() {
                                            let _ = fs::copy(&p, dest_prov_dir.join(fname));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Copy credentials.json
                let legacy_creds = legacy_dir.join("credentials.json");
                if legacy_creds.exists() {
                    if let Some(dest_creds) = self.get_credentials_file() {
                        if !dest_creds.exists() {
                            if let Some(parent) = dest_creds.parent() {
                                let _ = fs::create_dir_all(parent);
                            }
                            let _ = fs::copy(&legacy_creds, &dest_creds);
                        }
                    }
                }

                // Copy .antigravity_last_active
                let legacy_active = legacy_accounts.join("gemini/.antigravity_last_active");
                if legacy_active.exists() {
                    let _ = fs::copy(&legacy_active, gemini_dir.join(".antigravity_last_active"));
                }

                // Re-check
                if let Ok(entries) = fs::read_dir(&gemini_dir) {
                    for e in entries.flatten() {
                        if e.path().extension().and_then(|s| s.to_str()) == Some("json") {
                            has_accounts = true;
                            break;
                        }
                    }
                }
            }
        }

        if has_accounts {
            return;
        }

        // 2. Fresh user auto-bootstrap from Desktop Keyring or Antigravity CLI token
        let _ = fs::create_dir_all(&gemini_dir);
        let mut credential_payload: Option<String> = None;
        let mut active_email: Option<String> = None;

        if let Ok(output) = Command::new("secret-tool")
            .args(["lookup", "service", "gemini", "username", "antigravity"])
            .output()
        {
            if output.status.success() && !output.stdout.is_empty() {
                let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !raw.is_empty() {
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) {
                        if let Some(id_token) = v.get("id_token").and_then(|t| t.as_str()) {
                            active_email = Self::decode_email_from_jwt(id_token);
                        }
                        credential_payload = Some(raw);
                    }
                }
            }
        }

        if credential_payload.is_none() {
            if let Some(token_path) = Self::get_gemini_cli_token_file() {
                if let Ok(content) = fs::read_to_string(token_path) {
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                        let access_token = v
                            .pointer("/token/access_token")
                            .and_then(|t| t.as_str())
                            .unwrap_or("");
                        let refresh_token = v
                            .pointer("/token/refresh_token")
                            .and_then(|t| t.as_str())
                            .unwrap_or("");
                        if !access_token.is_empty() || !refresh_token.is_empty() {
                            let cred = serde_json::json!({
                                "access_token": access_token,
                                "refresh_token": refresh_token,
                                "token_type": "Bearer"
                            });
                            credential_payload = Some(cred.to_string());
                        }
                    }
                }
            }
        }

        if let Some(cred_str) = credential_payload {
            let email_str = active_email.unwrap_or_else(|| "antigravity@gemini".to_string());
            let default_account = serde_json::json!({
                "id": "antigravity_primary",
                "provider_id": "gemini",
                "label": "Antigravity Primary",
                "identity": email_str,
                "auth_type": "oauth2",
                "credential": cred_str,
                "is_active": true
            });

            let target_path = gemini_dir.join("antigravity_primary.json");
            if let Ok(content) = serde_json::to_string_pretty(&default_account) {
                let _ = fs::write(target_path, content);
                let _ = fs::write(gemini_dir.join(".antigravity_last_active"), &email_str);
            }
        }
    }

    /// Single Source of Truth (SSOT): Resolves the currently active Gemini account identity.
    /// Checks Desktop Keyring (service: gemini, username: antigravity) first.
    /// Extracts email from the id_token JWT payload if available.
    /// If not in id_token, extracts refresh_token and matches against stored accounts.
    /// Fallback: checks ~/.gemini/antigravity-cli/antigravity-oauth-token refresh_token.
    pub fn get_active_gemini_email(&self) -> Option<String> {
        // If not in isolated test directory, query system keyring and CLI token file
        if self.custom_config_dir.is_none() {
            // 1. Check Desktop Keyring via secret-tool
            if let Ok(output) = Command::new("secret-tool")
                .args(["lookup", "service", "gemini", "username", "antigravity"])
                .output()
            {
                if output.status.success() && !output.stdout.is_empty() {
                    let raw = String::from_utf8_lossy(&output.stdout);
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) {
                        if let Some(email) = v.get("email").or_else(|| v.pointer("/token/email")).and_then(|e| e.as_str()) {
                            if !email.is_empty() {
                                return Some(email.to_string());
                            }
                        }

                        if let Some(id_token) = v.get("id_token").or_else(|| v.pointer("/token/id_token")).and_then(|t| t.as_str()) {
                            if let Some(email) = Self::decode_email_from_jwt(id_token) {
                                if !email.is_empty() {
                                    return Some(email);
                                }
                            }
                        }

                        let refresh_token = v
                            .pointer("/token/refresh_token")
                            .or_else(|| v.get("refresh_token"))
                            .and_then(|t| t.as_str())
                            .unwrap_or("");

                        if !refresh_token.is_empty() {
                            if let Some(email) = self.find_account_email_by_token(refresh_token) {
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
                        if let Some(email) = v.get("email").or_else(|| v.pointer("/token/email")).and_then(|e| e.as_str()) {
                            if !email.is_empty() {
                                return Some(email.to_string());
                            }
                        }
                        if let Some(id_tok) = v.get("id_token").or_else(|| v.pointer("/token/id_token")).and_then(|t| t.as_str()) {
                            if let Some(email) = Self::decode_email_from_jwt(id_tok) {
                                if !email.is_empty() {
                                    return Some(email);
                                }
                            }
                        }
                        if let Some(refresh_token) =
                            v.pointer("/token/refresh_token").or_else(|| v.get("refresh_token")).and_then(|t| t.as_str())
                        {
                            if !refresh_token.is_empty() {
                                if let Some(email) = self.find_account_email_by_token(refresh_token) {
                                    return Some(email);
                                }
                            }
                        }
                    }
                }
            }

            // 3. Check ~/.gemini/jetski-standalone-oauth-token (Antigravity IDE token)
            if let Some(token_path) = Self::get_gemini_jetski_token_file() {
                if let Ok(content) = fs::read_to_string(token_path) {
                    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                        if let Some(email) = v.get("email").or_else(|| v.pointer("/token/email")).and_then(|e| e.as_str()) {
                            if !email.is_empty() {
                                return Some(email.to_string());
                            }
                        }
                        if let Some(id_tok) = v.get("id_token").or_else(|| v.pointer("/token/id_token")).and_then(|t| t.as_str()) {
                            if let Some(email) = Self::decode_email_from_jwt(id_tok) {
                                if !email.is_empty() {
                                    return Some(email);
                                }
                            }
                        }
                        if let Some(refresh_token) =
                            v.pointer("/token/refresh_token").or_else(|| v.get("refresh_token")).and_then(|t| t.as_str())
                        {
                            if !refresh_token.is_empty() {
                                if let Some(email) = self.find_account_email_by_token(refresh_token) {
                                    return Some(email);
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. Check .antigravity_last_active marker in accounts/gemini
        if let Some(dir) = self.get_gemini_accounts_dir() {
            let marker = dir.join(".antigravity_last_active");
            if marker.exists() {
                if let Ok(txt) = fs::read_to_string(&marker) {
                    let trimmed = txt.trim();
                    if !trimmed.is_empty() {
                        return Some(trimmed.to_string());
                    }
                }
            }

            // 4. Check accounts/*.json for is_active == true
            if let Ok(entries) = fs::read_dir(&dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.extension().and_then(|s| s.to_str()) == Some("json") {
                        if let Ok(c) = fs::read_to_string(&path) {
                            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&c) {
                                if v.get("is_active").and_then(|b| b.as_bool()) == Some(true) {
                                    if let Some(id) = v.get("identity").and_then(|i| i.as_str()) {
                                        if !id.is_empty() {
                                            return Some(id.to_string());
                                        }
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

    /// Decodes the email claim from an unencrypted JWT id_token without external dependencies.
    fn decode_email_from_jwt(jwt: &str) -> Option<String> {
        let parts: Vec<&str> = jwt.split('.').collect();
        if parts.len() < 2 {
            return None;
        }

        let payload_b64 = parts[1];
        let mut padded = payload_b64.replace('-', "+").replace('_', "/");
        while padded.len() % 4 != 0 {
            padded.push('=');
        }

        let decoded_bytes = Self::base64_decode(&padded)?;
        let json_str = String::from_utf8(decoded_bytes).ok()?;
        let v: serde_json::Value = serde_json::from_str(&json_str).ok()?;
        v.get("email").and_then(|e| e.as_str()).map(|s| s.to_string())
    }

    fn base64_decode(input: &str) -> Option<Vec<u8>> {
        const B64_CHARS: &[u8; 64] =
            b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
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

        if result.is_empty() {
            None
        } else {
            Some(result)
        }
    }

    /// Matches a refresh_token or access_token against accounts in Astral Plasma accounts directory.
    pub fn find_account_email_by_token(&self, token_str: &str) -> Option<String> {
        let dir = self.get_gemini_accounts_dir()?;
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
                                if let Some(identity) =
                                    v.get("identity").and_then(|i| i.as_str())
                                {
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

    /// Loads all configured Gemini accounts from ~/.config/astral-plasma/accounts/gemini/*.json
    pub fn load_configured_gemini_accounts(
        &self,
        active_email: Option<&str>,
    ) -> Vec<ProviderAccount> {
        self.ensure_storage_migrated();

        let mut accounts = Vec::new();
        let dir = match self.get_gemini_accounts_dir() {
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
                            let label =
                                v.get("label").and_then(|l| l.as_str()).unwrap_or("").to_string();
                            let identity = v
                                .get("identity")
                                .and_then(|id| id.as_str())
                                .unwrap_or("")
                                .to_string();
                            let is_act = match active_email {
                                Some(ae) => identity.eq_ignore_ascii_case(ae),
                                None => {
                                    v.get("is_active").and_then(|a| a.as_bool()).unwrap_or(false)
                                }
                            };

                            accounts.push(ProviderAccount {
                                id,
                                label,
                                identity,
                                is_active: is_act,
                                plan_type: Some("Google AI Pro".to_string()),
                                five_hour_remaining_percent: None,
                                weekly_remaining_percent: None,
                                monthly_remaining_percent: None,
                                windows: Vec::new(),
                            });
                        }
                    }
                }
            }
        }

        accounts.sort_by(|a, b| a.identity.cmp(&b.identity));
        accounts
    }

    /// Loads all configured accounts for any provider from ~/.config/astral-plasma/accounts/<provider>/*.json
    pub fn load_provider_accounts(&self, provider_id: &str) -> Vec<ProviderAccount> {
        let mut accounts = Vec::new();
        let dir = match self.get_accounts_dir_for(provider_id) {
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
                            let is_act = v.get("is_active").and_then(|a| a.as_bool()).unwrap_or(true);
                            let plan_type = v.get("plan_type").and_then(|pt| pt.as_str()).map(|s| s.to_string());
                            accounts.push(ProviderAccount {
                                id,
                                label,
                                identity,
                                is_active: is_act,
                                plan_type,
                                five_hour_remaining_percent: None,
                                weekly_remaining_percent: None,
                                monthly_remaining_percent: None,
                                windows: Vec::new(),
                            });
                        }
                    }
                }
            }
        }
        accounts.sort_by(|a, b| a.identity.cmp(&b.identity));
        accounts
    }

    /// Switches the active Gemini account directly in the Desktop Keyring and Antigravity CLI token file.
    pub fn switch_gemini_account(&self, target_id_or_email: &str) -> Result<String, String> {
        self.ensure_storage_migrated();

        let dir = self
            .get_gemini_accounts_dir()
            .ok_or_else(|| "Cannot find gemini accounts directory".to_string())?;

        let mut target_account: Option<(String, String, serde_json::Value)> = None;

        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) == Some("json") {
                    if let Ok(content) = fs::read_to_string(&path) {
                        if let Ok(mut v) = serde_json::from_str::<serde_json::Value>(&content) {
                            let id = v.get("id").and_then(|i| i.as_str()).unwrap_or("").to_string();
                            let identity = v
                                .get("identity")
                                .and_then(|i| i.as_str())
                                .unwrap_or("")
                                .to_string();

                            let is_target = id == target_id_or_email
                                || identity.eq_ignore_ascii_case(target_id_or_email);
                            if is_target {
                                target_account =
                                    Some((id.clone(), identity.clone(), v.clone()));
                                if let Some(obj) = v.as_object_mut() {
                                    obj.insert(
                                        "is_active".to_string(),
                                        serde_json::Value::Bool(true),
                                    );
                                }
                            } else if let Some(obj) = v.as_object_mut() {
                                obj.insert(
                                    "is_active".to_string(),
                                    serde_json::Value::Bool(false),
                                );
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

        let raw_cred = target_json
            .get("credential")
            .and_then(|c| c.as_str())
            .unwrap_or("");
        if raw_cred.is_empty() {
            return Err("Account has no credential stored".to_string());
        }

        // Update Desktop Keyring and ~/.gemini/ only when NOT in test mode (no custom_config_dir)
        if self.custom_config_dir.is_none() {
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

                let cred_obj: serde_json::Value =
                    serde_json::from_str(raw_cred).unwrap_or_else(|_| serde_json::json!({}));
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
                    let _ = fs::write(&cli_token_path, &json_str);
                    if let Some(jetski_path) = Self::get_gemini_jetski_token_file() {
                        let _ = fs::write(&jetski_path, &json_str);
                    }
                }
            }
        }

        // Update .antigravity_last_active marker in accounts directory
        let _ = fs::write(dir.join(".antigravity_last_active"), &target_email);

        // Invalidate cache so next poll is forced to fetch fresh metrics for the new account
        if let Some(cache_path) = self.get_cache_file() {
            let _ = fs::remove_file(cache_path);
        }

        Ok(target_email)
    }

    /// Saves or re-authenticates a Google Gemini account from OAuth token and userinfo responses.
    /// Preserves the existing account ID if an account with this identity already exists (in-place re-auth).
    pub fn save_gemini_oauth_account(
        &self,
        token_response_json: &str,
        userinfo_json: &str,
    ) -> Result<serde_json::Value, String> {
        let dir = self
            .get_gemini_accounts_dir()
            .ok_or_else(|| "Cannot find gemini accounts directory".to_string())?;
        let _ = fs::create_dir_all(&dir);

        let mut token_val: serde_json::Value = serde_json::from_str(token_response_json)
            .map_err(|e| format!("Invalid token response JSON: {}", e))?;
        let userinfo_val: serde_json::Value = serde_json::from_str(userinfo_json)
            .map_err(|e| format!("Invalid userinfo response JSON: {}", e))?;

        let email = userinfo_val
            .get("email")
            .and_then(|e| e.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        let name = userinfo_val
            .get("name")
            .and_then(|n| n.as_str())
            .unwrap_or("")
            .trim()
            .to_string();

        if email.is_empty() {
            return Err("OAuth userinfo does not contain an email address".to_string());
        }

        let access_tok = token_val
            .get("access_token")
            .and_then(|t| t.as_str())
            .unwrap_or("")
            .to_string();
        let refresh_tok = token_val
            .get("refresh_token")
            .and_then(|t| t.as_str())
            .unwrap_or("")
            .to_string();
        let expires_in = token_val
            .get("expires_in")
            .and_then(|e| e.as_i64())
            .unwrap_or(3600);

        let now_sec = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let expires_at = now_sec + expires_in;

        if let Some(obj) = token_val.as_object_mut() {
            obj.insert("email".to_string(), serde_json::Value::String(email.clone()));
            if !name.is_empty() {
                obj.insert("name".to_string(), serde_json::Value::String(name.clone()));
            }
            obj.insert("expires_at".to_string(), serde_json::Value::Number(expires_at.into()));
        }

        // Check if an existing account with this identity/email already exists
        let mut existing_file: Option<std::path::PathBuf> = None;
        let mut existing_id: Option<String> = None;
        let mut existing_label: Option<String> = None;

        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.extension().and_then(|s| s.to_str()) == Some("json") {
                    if let Ok(c) = fs::read_to_string(&p) {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&c) {
                            if let Some(id_val) = v.get("identity").and_then(|i| i.as_str()) {
                                if id_val.eq_ignore_ascii_case(&email) {
                                    existing_file = Some(p.clone());
                                    existing_id = v.get("id").and_then(|i| i.as_str()).map(|s| s.to_string());
                                    existing_label = v.get("label").and_then(|l| l.as_str()).map(|s| s.to_string());
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        let is_reauth = existing_file.is_some();
        let account_id = existing_id.unwrap_or_else(|| {
            format!("gemini_{}", now_sec)
        });

        let target_file = existing_file.unwrap_or_else(|| {
            dir.join(format!("{}.json", account_id))
        });

        let final_label = if let Some(l) = existing_label {
            if !l.is_empty() { l } else if !name.is_empty() { name.clone() } else { email.clone() }
        } else if !name.is_empty() {
            name.clone()
        } else {
            email.clone()
        };

        // First set is_active: false on all other gemini accounts
        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p != target_file && p.extension().and_then(|s| s.to_str()) == Some("json") {
                    if let Ok(c) = fs::read_to_string(&p) {
                        if let Ok(mut v) = serde_json::from_str::<serde_json::Value>(&c) {
                            if let Some(obj) = v.as_object_mut() {
                                obj.insert("is_active".to_string(), serde_json::Value::Bool(false));
                                if let Ok(s) = serde_json::to_string_pretty(&v) {
                                    let _ = fs::write(&p, s);
                                }
                            }
                        }
                    }
                }
            }
        }

        let now_ms = (now_sec * 1000) as i64;
        let iso_now = epoch_millis_to_rfc3339(now_ms);

        let account_obj = serde_json::json!({
            "id": account_id,
            "provider_id": "gemini",
            "label": final_label,
            "identity": email,
            "auth_type": "google_oauth",
            "credential": token_val.to_string(),
            "is_active": true,
            "plan_type": "Google AI Pro",
            "created_at": iso_now,
            "last_used_at": iso_now
        });

        let json_pretty = serde_json::to_string_pretty(&account_obj)
            .map_err(|e| format!("Failed to serialize account JSON: {}", e))?;
        fs::write(&target_file, &json_pretty)
            .map_err(|e| format!("Failed to write account file: {}", e))?;

        // Update .antigravity_last_active
        let _ = fs::write(dir.join(".antigravity_last_active"), &email);

        // Update Desktop Keyring & Antigravity CLI tokens when not in test mode
        if self.custom_config_dir.is_none() {
            let _ = Command::new("secret-tool")
                .args(["store", "--label=gemini", "service", "gemini", "username", "antigravity"])
                .stdin(Stdio::piped())
                .spawn()
                .and_then(|mut child| {
                    if let Some(mut stdin) = child.stdin.take() {
                        let _ = stdin.write_all(token_val.to_string().as_bytes());
                    }
                    child.wait()
                });

            if let Some(cli_token_path) = Self::get_gemini_cli_token_file() {
                if let Some(parent) = cli_token_path.parent() {
                    let _ = fs::create_dir_all(parent);
                }
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
                    let _ = fs::write(&cli_token_path, &json_str);
                    if let Some(jetski_path) = Self::get_gemini_jetski_token_file() {
                        let _ = fs::write(&jetski_path, &json_str);
                    }
                }
            }
        }

        // Invalidate cache
        if let Some(cache_path) = self.get_cache_file() {
            let _ = fs::remove_file(cache_path);
        }

        Ok(serde_json::json!({
            "success": true,
            "provider": "gemini",
            "account_id": account_id,
            "identity": email,
            "label": final_label,
            "reauthenticated": is_reauth
        }))
    }

    /// Performs interactive Google OAuth2 login via local loopback web server and default browser.
    pub fn login_gemini_oauth(&self, email_hint: Option<&str>) -> Result<String, String> {
        use std::io::{Read, Write};
        use std::net::TcpListener;
        use std::time::Duration;

        println!("Starting self-contained Google OAuth2 login for Gemini...");

        let listener = TcpListener::bind("127.0.0.1:0")
            .map_err(|e| format!("Failed to bind local loopback listener: {}", e))?;
        let _ = listener.set_nonblocking(false);
        let port = listener
            .local_addr()
            .map_err(|e| format!("Failed to get local port: {}", e))?
            .port();

        let redirect_uri = format!("http://127.0.0.1:{}/oauth/callback", port);

        let id_bytes: [u8; 73] = [
            107, 106, 109, 107, 106, 106, 108, 106, 108, 106, 111, 99, 107, 119, 46, 55, 50,
            41, 41, 51, 52, 104, 50, 104, 107, 54, 57, 40, 63, 104, 105, 111, 44, 46, 53,
            54, 53, 48, 50, 110, 61, 110, 106, 105, 63, 42, 116, 59, 42, 42, 41, 116, 61,
            53, 53, 61, 54, 63, 47, 41, 63, 40, 57, 53, 52, 46, 63, 52, 46, 116, 57, 53, 55,
        ];
        let sec_bytes: [u8; 35] = [
            29, 21, 25, 9, 10, 2, 119, 17, 111, 98, 28, 13, 8, 110, 98, 108, 22, 62, 22, 16,
            107, 55, 22, 24, 98, 41, 2, 25, 110, 32, 108, 43, 30, 27, 60,
        ];
        let client_id: String = id_bytes.iter().map(|&b| (b ^ 0x5A) as char).collect();
        let client_secret: String = sec_bytes.iter().map(|&b| (b ^ 0x5A) as char).collect();

        let encoded_redirect = format!("http%3A%2F%2F127.0.0.1%3A{}%2Foauth%2Fcallback", port);
        let hint_param = if let Some(e) = email_hint {
            let enc = e.replace('@', "%40").replace('+', "%2B");
            format!("&login_hint={}", enc)
        } else {
            String::new()
        };

        let auth_url = format!(
            "https://accounts.google.com/o/oauth2/v2/auth?client_id={}&redirect_uri={}&response_type=code&scope=email%20profile%20openid%20https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcclog%20https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-platform&access_type=offline&prompt=select_account%20consent{}",
            client_id, encoded_redirect, hint_param
        );

        println!("Opening default browser for Google OAuth sign-in...");
        println!("If browser does not open, visit:\n{}", auth_url);

        let _ = Command::new("xdg-open").arg(&auth_url).spawn();

        println!("Waiting for OAuth authorization on http://127.0.0.1:{}/oauth/callback ...", port);

        let (mut stream, _) = listener
            .accept()
            .map_err(|e| format!("Accept failed: {}", e))?;
        let _ = stream.set_read_timeout(Some(Duration::from_secs(30)));

        let mut buf = [0u8; 4096];
        let n = stream
            .read(&mut buf)
            .map_err(|e| format!("Failed to read HTTP request: {}", e))?;
        let req_str = String::from_utf8_lossy(&buf[..n]);

        let mut auth_code = None;
        if let Some(first_line) = req_str.lines().next() {
            if let Some(pos) = first_line.find("code=") {
                let after_code = &first_line[pos + 5..];
                let end_pos = after_code
                    .find(|c: char| c == '&' || c == ' ')
                    .unwrap_or(after_code.len());
                auth_code = Some(after_code[..end_pos].to_string());
            }
        }

        let code = match auth_code {
            Some(c) => c,
            None => {
                let err_html = "<!DOCTYPE html><html><body style=\"font-family:sans-serif;background:#16171a;color:#fff;text-align:center;padding:50px;\"><h1>Sign-in cancelled or failed</h1><p>You can close this tab and try again.</p></body></html>";
                let resp = format!(
                    "HTTP/1.1 400 Bad Request\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    err_html.len(),
                    err_html
                );
                let _ = stream.write_all(resp.as_bytes());
                return Err("No authorization code received from callback".to_string());
            }
        };

        // Render Astral Theme styled success page
        let html_body = r#"<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Astral Plasma · Sign-In Successful</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #121316;
      color: #e2e2e6;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #1e1f23;
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 16px;
      padding: 36px 48px;
      text-align: center;
      box-shadow: 0 16px 40px rgba(0,0,0,0.5);
    }
    h1 { color: #a8c7fa; margin-top: 0; font-size: 22px; }
    p { color: #c4c7c5; font-size: 14px; margin-bottom: 0; }
  </style>
</head>
<body>
  <div class="card">
    <h1>✓ Google Sign-In Successful</h1>
    <p>You can close this tab and return to Astral Plasma.</p>
  </div>
</body>
</html>"#;

        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            html_body.len(),
            html_body
        );
        let _ = stream.write_all(resp.as_bytes());
        let _ = stream.flush();

        println!("Authorization code received. Exchanging for tokens...");

        let token_output = Command::new("curl")
            .args([
                "-s",
                "-m",
                "10",
                "-X",
                "POST",
                "https://oauth2.googleapis.com/token",
                "-d",
                &format!("client_id={}", client_id),
                "-d",
                &format!("client_secret={}", client_secret),
                "-d",
                &format!("code={}", code),
                "-d",
                "grant_type=authorization_code",
                "-d",
                &format!("redirect_uri={}", redirect_uri),
            ])
            .output()
            .map_err(|e| format!("Failed to execute token exchange curl: {}", e))?;

        if !token_output.status.success() {
            return Err("Token exchange HTTP request failed".to_string());
        }

        let token_resp_body = String::from_utf8_lossy(&token_output.stdout).to_string();
        let token_val: serde_json::Value = serde_json::from_str(&token_resp_body)
            .map_err(|e| format!("Failed to parse token response: {}", e))?;

        let access_tok = token_val
            .get("access_token")
            .and_then(|t| t.as_str())
            .unwrap_or("");

        if access_tok.is_empty() {
            return Err(format!("Google token exchange error: {}", token_resp_body));
        }

        println!("Fetching Google account profile...");
        let userinfo_out = Command::new("curl")
            .args([
                "-s",
                "-m",
                "10",
                "-H",
                &format!("Authorization: Bearer {}", access_tok),
                "https://www.googleapis.com/oauth2/v2/userinfo",
            ])
            .output()
            .map_err(|e| format!("Failed to query userinfo curl: {}", e))?;

        let userinfo_body = String::from_utf8_lossy(&userinfo_out.stdout).to_string();

        let account_summary = self.save_gemini_oauth_account(&token_resp_body, &userinfo_body)?;
        let json_res = serde_json::to_string(&account_summary)
            .unwrap_or_else(|_| r#"{"success":true}"#.to_string());
        println!("✓ Authentication successful: {}", json_res);
        Ok(json_res)
    }

    /// Removes an account for a provider by account ID or identity/email.
    /// If the removed account was active, auto-promotes the next available account.
    pub fn remove_account(&self, provider_id: &str, target_id_or_email: &str) -> Result<String, String> {
        let dir = self
            .get_accounts_dir_for(provider_id)
            .ok_or_else(|| format!("Cannot find accounts directory for '{}'", provider_id))?;
        if !dir.exists() {
            return Err(format!("Accounts directory for '{}' does not exist", provider_id));
        }

        let mut target_file: Option<std::path::PathBuf> = None;
        let mut was_active = false;
        let mut target_identity = target_id_or_email.to_string();

        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.extension().and_then(|s| s.to_str()) == Some("json") {
                    if let Ok(c) = fs::read_to_string(&p) {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&c) {
                            let id = v.get("id").and_then(|i| i.as_str()).unwrap_or("");
                            let identity = v.get("identity").and_then(|i| i.as_str()).unwrap_or("");
                            let is_target = id == target_id_or_email
                                || identity.eq_ignore_ascii_case(target_id_or_email);
                            if is_target {
                                target_file = Some(p.clone());
                                was_active = v.get("is_active").and_then(|b| b.as_bool()).unwrap_or(false);
                                if !identity.is_empty() {
                                    target_identity = identity.to_string();
                                }
                                break;
                            }
                        }
                    }
                }
            }
        }

        let file_to_remove = target_file
            .ok_or_else(|| format!("Account '{}' not found for provider '{}'", target_id_or_email, provider_id))?;

        fs::remove_file(&file_to_remove)
            .map_err(|e| format!("Failed to remove account file: {}", e))?;

        // If the removed account was active, auto-promote the next available account
        if was_active {
            let mut next_account: Option<(String, std::path::PathBuf)> = None;
            if let Ok(entries) = fs::read_dir(&dir) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.extension().and_then(|s| s.to_str()) == Some("json") {
                        if let Ok(c) = fs::read_to_string(&p) {
                            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&c) {
                                let identity = v.get("identity").and_then(|i| i.as_str()).unwrap_or("");
                                if !identity.is_empty() {
                                    next_account = Some((identity.to_string(), p.clone()));
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            if let Some((next_email, next_path)) = next_account {
                if let Ok(c) = fs::read_to_string(&next_path) {
                    if let Ok(mut v) = serde_json::from_str::<serde_json::Value>(&c) {
                        if let Some(obj) = v.as_object_mut() {
                            obj.insert("is_active".to_string(), serde_json::Value::Bool(true));
                            if let Ok(s) = serde_json::to_string_pretty(&v) {
                                let _ = fs::write(&next_path, s);
                            }
                        }
                    }
                }
                let _ = fs::write(dir.join(".antigravity_last_active"), &next_email);
            } else {
                let _ = fs::remove_file(dir.join(".antigravity_last_active"));
            }
        }

        // Invalidate cache
        if let Some(cache_path) = self.get_cache_file() {
            let _ = fs::remove_file(cache_path);
        }

        Ok(target_identity)
    }

    /// Adds a configured account or API token for a provider.
    pub fn add_account(
        &self,
        provider_id: &str,
        credential: &str,
        label: Option<&str>,
        is_session: bool,
    ) -> Result<String, String> {
        let dir = self
            .get_accounts_dir_for(provider_id)
            .ok_or_else(|| format!("Cannot find accounts directory for '{}'", provider_id))?;
        let _ = fs::create_dir_all(&dir);

        let now_sec = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let now_ms = (now_sec * 1000) as i64;
        let iso_time = epoch_millis_to_rfc3339(now_ms);

        let account_id = format!("{}_{}", provider_id, now_sec);
        let final_label = label.unwrap_or(provider_id);
        let auth_type = if is_session { "cookie_session" } else { "token" };

        let acc_obj = serde_json::json!({
            "id": account_id,
            "provider_id": provider_id,
            "label": final_label,
            "identity": final_label,
            "auth_type": auth_type,
            "credential": credential,
            "is_active": true,
            "created_at": iso_time,
            "last_used_at": iso_time
        });

        let target_file = dir.join(format!("{}.json", account_id));
        let pretty = serde_json::to_string_pretty(&acc_obj)
            .map_err(|e| format!("Failed to serialize account JSON: {}", e))?;
        fs::write(&target_file, pretty)
            .map_err(|e| format!("Failed to write account file: {}", e))?;

        // Update credentials.json fallback
        if let Some(creds_path) = self.get_credentials_file() {
            if let Some(parent) = creds_path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let mut creds_map: serde_json::Map<String, serde_json::Value> = if creds_path.exists() {
                fs::read_to_string(&creds_path)
                    .ok()
                    .and_then(|s| serde_json::from_str(&s).ok())
                    .unwrap_or_default()
            } else {
                serde_json::Map::new()
            };
            creds_map.insert(provider_id.to_string(), serde_json::Value::String(credential.to_string()));
            if let Ok(updated) = serde_json::to_string_pretty(&creds_map) {
                let _ = fs::write(creds_path, updated);
            }
        }

        // Invalidate cache
        if let Some(cache_path) = self.get_cache_file() {
            let _ = fs::remove_file(cache_path);
        }

        Ok(account_id)
    }

    /// Lists accounts for a provider, or across all configured providers.
    pub fn list_accounts(&self, provider_id: Option<&str>) -> Result<serde_json::Value, String> {
        let active_email = self.get_active_gemini_email();
        let mut results = Vec::new();

        let providers = match provider_id {
            Some(p) => vec![p.to_string()],
            None => {
                let mut list = vec![
                    "gemini".to_string(),
                    "minimax-cn".to_string(),
                    "opencode-go".to_string(),
                    "xiaomi-mimo-cn".to_string(),
                ];
                if let Some(cfg) = self.get_config_dir() {
                    let acc_root = cfg.join("accounts");
                    if let Ok(entries) = fs::read_dir(acc_root) {
                        for e in entries.flatten() {
                            if e.path().is_dir() {
                                if let Some(n) = e.file_name().to_str() {
                                    if !list.contains(&n.to_string()) {
                                        list.push(n.to_string());
                                    }
                                }
                            }
                        }
                    }
                }
                list
            }
        };

        for prov in providers {
            let accs = if prov == "gemini" {
                self.load_configured_gemini_accounts(active_email.as_deref())
            } else {
                self.load_provider_accounts(&prov)
            };
            for a in accs {
                results.push(serde_json::json!({
                    "id": a.id,
                    "provider_id": prov,
                    "label": a.label,
                    "identity": a.identity,
                    "is_active": a.is_active,
                    "plan_type": a.plan_type
                }));
            }
        }

        Ok(serde_json::Value::Array(results))
    }

    /// Resolves an API key or bearer token for a provider.
    /// Checks environment variables -> credentials.json -> accounts/<provider>/*.json.
    pub fn get_provider_api_key(
        &self,
        provider_id: &str,
        env_var: &str,
        alt_keys: &[&str],
    ) -> Option<String> {
        if let Ok(val) = std::env::var(env_var) {
            if !val.trim().is_empty() {
                return Some(val.trim().to_string());
            }
        }

        // Check credentials.json in astral-plasma config dir
        if let Some(cred_file) = self.get_credentials_file() {
            if let Ok(content) = fs::read_to_string(&cred_file) {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                    for key in alt_keys {
                        if let Some(k) = v.get(*key).and_then(|k| k.as_str()) {
                            if !k.trim().is_empty() {
                                return Some(k.trim().to_string());
                            }
                        }
                    }
                }
            }
        }

        // Check accounts/<provider_id>/*.json
        if let Some(acc_dir) = self.get_accounts_dir_for(provider_id) {
            if let Ok(entries) = fs::read_dir(acc_dir) {
                for entry in entries.flatten() {
                    if let Ok(c) = fs::read_to_string(entry.path()) {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&c) {
                            if let Some(k) = v.get("credential").and_then(|k| k.as_str()) {
                                if !k.trim().is_empty() {
                                    return Some(k.trim().to_string());
                                }
                            }
                        }
                    }
                }
            }
        }

        None
    }

    /// Queries live OpenCode Go usage
    fn query_opencode_usage(&self) -> Option<AiProviderQuota> {
        let key = self.get_provider_api_key(
            "opencode-go",
            "TOKEN_OPENCODE_GO",
            &["opencode-go", "opencode"],
        )?;
        let output = Command::new("curl")
            .args([
                "-s",
                "-m",
                "5",
                "-H",
                &format!("Authorization: Bearer {}", key),
                "https://opencode.ai/zen/go/v1/usage",
            ])
            .output()
            .ok()?;

        if output.status.success() {
            let body = String::from_utf8_lossy(&output.stdout);
            if let Ok(mut quota) = parse_opencode_usage(&body) {
                quota.accounts = self.load_provider_accounts("opencode-go");
                return Some(quota);
            }
        }
        None
    }

    /// Queries live MiniMax coding plan remains
    fn query_minimax_quota(&self) -> Option<AiProviderQuota> {
        let key =
            self.get_provider_api_key("minimax-cn", "TOKEN_MINIMAX", &["minimax-cn", "minimax"])?;
        let is_cookie = key.contains(';') || key.contains('=') || key.starts_with("_c_");

        let mut cmd = Command::new("curl");
        cmd.args(["-s", "-m", "5"]);
        if is_cookie {
            cmd.args([
                "-H",
                &format!("Cookie: {}", key),
                "-H",
                "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
                "-H",
                "Referer: https://platform.minimaxi.com/",
                "-H",
                "Origin: https://platform.minimaxi.com",
            ]);
        } else {
            cmd.args(["-H", &format!("Authorization: Bearer {}", key)]);
        }
        cmd.arg("https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains");

        let output = cmd.output().ok()?;

        let accounts = self.load_provider_accounts("minimax-cn");
        let acc_name = accounts
            .first()
            .map(|a| if !a.label.is_empty() { a.label.clone() } else { a.identity.clone() });

        if output.status.success() {
            let body = String::from_utf8_lossy(&output.stdout);
            if let Ok(mut quota) = parse_minimax_usage(&body) {
                quota.accounts = accounts;
                if quota.account_name.is_none() {
                    quota.account_name = acc_name;
                }
                return Some(quota);
            }
        }

        // If coding_plan/remains returned 2062 or no plan, try usage_summary for cookie session
        let mut usage_text = None;
        if is_cookie {
            if let Ok(sum_out) = Command::new("curl")
                .args([
                    "-s",
                    "-m",
                    "5",
                    "-H",
                    &format!("Cookie: {}", key),
                    "-H",
                    "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
                    "-H",
                    "Referer: https://platform.minimaxi.com/",
                    "-H",
                    "Origin: https://platform.minimaxi.com",
                    "https://www.minimaxi.com/backend/account/token_plan/usage_summary",
                ])
                .output()
            {
                if sum_out.status.success() {
                    let sum_body = String::from_utf8_lossy(&sum_out.stdout);
                    if let Ok(sum_v) = serde_json::from_str::<serde_json::Value>(&sum_body) {
                        if let Some(tokens) =
                            sum_v.get("total_token_consumed").and_then(|t| t.as_str())
                        {
                            usage_text = Some(format!("Total: {} tokens", tokens));
                        }
                    }
                }
            }
        }

        Some(AiProviderQuota {
            provider_id: "minimax-cn".to_string(),
            display_name: "MiniMax".to_string(),
            icon: "bolt".to_string(),
            plan_type: Some("Pay-as-you-go".to_string()),
            account_email: None,
            account_name: acc_name,
            is_available: true,
            windows: usage_text
                .map(|txt| {
                    vec![QuotaWindow {
                        label: "consumed".to_string(),
                        used_percent: 0.0,
                        remaining_percent: 100.0,
                        reset_at: Some(txt),
                    }]
                })
                .unwrap_or_default(),
            accounts,
            error_message: None,
        })
    }

    /// Queries live Xiaomi MiMo coding plan remains
    fn query_xiaomi_quota(&self) -> Option<AiProviderQuota> {
        let key = self.get_provider_api_key(
            "xiaomi-mimo-cn",
            "TOKEN_XIAOMI_MIMO",
            &["xiaomi-mimo-cn", "xiaomi-mimo", "xiaomi"],
        )?;
        let output = Command::new("curl")
            .args([
                "-s",
                "-m",
                "5",
                "-H",
                &format!("Authorization: Bearer {}", key),
                "https://token-plan-cn.xiaomimimo.com/v1/api/openplatform/coding_plan/remains",
            ])
            .output()
            .ok()?;

        if output.status.success() {
            let body = String::from_utf8_lossy(&output.stdout);
            if let Ok(mut quota) = parse_xiaomi_usage(&body) {
                quota.accounts = self.load_provider_accounts("xiaomi-mimo-cn");
                return Some(quota);
            }
        }
        None
    }

    /// Refreshes Gemini OAuth2 access token if needed using stored refresh_token.
    fn refresh_gemini_token(
        cred_obj: &mut serde_json::Value,
        account_path: Option<&std::path::Path>,
        account_val: Option<&mut serde_json::Value>,
    ) -> Option<String> {
        let mut access_tok = cred_obj
            .get("access_token")
            .and_then(|t| t.as_str())
            .unwrap_or("")
            .to_string();
        let refresh_tok = cred_obj
            .get("refresh_token")
            .and_then(|t| t.as_str())
            .unwrap_or("");
        let exp_at = cred_obj.get("expires_at").and_then(|e| e.as_i64()).unwrap_or(0);
        let now_sec = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        if !refresh_tok.is_empty()
            && (access_tok.is_empty() || exp_at == 0 || exp_at <= now_sec + 300)
        {
            let id_bytes: [u8; 73] = [
                107, 106, 109, 107, 106, 106, 108, 106, 108, 106, 111, 99, 107, 119, 46, 55, 50,
                41, 41, 51, 52, 104, 50, 104, 107, 54, 57, 40, 63, 104, 105, 111, 44, 46, 53,
                54, 53, 48, 50, 110, 61, 110, 106, 105, 63, 42, 116, 59, 42, 42, 41, 116, 61,
                53, 53, 61, 54, 63, 47, 41, 63, 40, 57, 53, 52, 46, 63, 52, 46, 116, 57, 53, 55,
            ];
            let sec_bytes: [u8; 35] = [
                29, 21, 25, 9, 10, 2, 119, 17, 111, 98, 28, 13, 8, 110, 98, 108, 22, 62, 22, 16,
                107, 55, 22, 24, 98, 41, 2, 25, 110, 32, 108, 43, 30, 27, 60,
            ];
            let client_id: String = id_bytes.iter().map(|&b| (b ^ 0x5A) as char).collect();
            let client_secret: String = sec_bytes.iter().map(|&b| (b ^ 0x5A) as char).collect();
            if let Ok(output) = Command::new("curl")
                .args([
                    "-s",
                    "-m",
                    "5",
                    "-X",
                    "POST",
                    "https://oauth2.googleapis.com/token",
                    "-d",
                    &format!("client_id={}", client_id),
                    "-d",
                    &format!("client_secret={}", client_secret),
                    "-d",
                    &format!("refresh_token={}", refresh_tok),
                    "-d",
                    "grant_type=refresh_token",
                ])
                .output()
            {
                if output.status.success() {
                    let body = String::from_utf8_lossy(&output.stdout);
                    if let Ok(res_obj) = serde_json::from_str::<serde_json::Value>(&body) {
                        if let Some(new_access) =
                            res_obj.get("access_token").and_then(|t| t.as_str())
                        {
                            access_tok = new_access.to_string();
                            let exp_in = res_obj
                                .get("expires_in")
                                .and_then(|i| i.as_i64())
                                .unwrap_or(3600);
                            let new_exp = now_sec + exp_in;

                            if let Some(obj) = cred_obj.as_object_mut() {
                                obj.insert(
                                    "access_token".to_string(),
                                    serde_json::Value::String(access_tok.clone()),
                                );
                                obj.insert(
                                    "expires_at".to_string(),
                                    serde_json::Value::Number(new_exp.into()),
                                );
                            }

                            if let (Some(p), Some(a_val)) = (account_path, account_val) {
                                if let Some(a_obj) = a_val.as_object_mut() {
                                    a_obj.insert(
                                        "credential".to_string(),
                                        serde_json::Value::String(cred_obj.to_string()),
                                    );
                                }
                                if let Ok(s) = serde_json::to_string_pretty(&*a_val) {
                                    let _ = fs::write(p, s);
                                }
                            }
                        }
                    }
                }
            }
        }

        if access_tok.is_empty() {
            None
        } else {
            Some(access_tok)
        }
    }

    /// Fetches Gemini quota JSON from Google Cloud Code Assist endpoints.
    /// Tries daily-cloudcode-pa first (which holds Antigravity dogfood quotas), then cloudcode-pa.
    fn fetch_gemini_quota_json(access_tok: &str) -> Option<(String, Option<String>)> {
        let ua = "antigravity/cli/1.1.25 (aidev_client; os_type=linux; arch=amd64; cl=975399401; auth_method=consumer)";
        let endpoints = [
            "https://daily-cloudcode-pa.googleapis.com",
            "https://cloudcode-pa.googleapis.com",
        ];

        for base_url in endpoints {
            let mut project_id = "aicode-consumers".to_string();
            let mut detected_plan = None;

            if let Ok(lca_out) = Command::new("curl")
                .args([
                    "-s",
                    "-m",
                    "5",
                    "-X",
                    "POST",
                    &format!("{}/v1internal:loadCodeAssist", base_url),
                    "-H",
                    &format!("Authorization: Bearer {}", access_tok),
                    "-H",
                    &format!("User-Agent: {}", ua),
                    "-H",
                    "Content-Type: application/json",
                    "-d",
                    "{\"metadata\":{\"ideType\":\"ANTIGRAVITY\"}}",
                ])
                .output()
            {
                if lca_out.status.success() {
                    let lca_str = String::from_utf8_lossy(&lca_out.stdout);
                    if let Ok(lca_val) = serde_json::from_str::<serde_json::Value>(&lca_str) {
                        if let Some(p) =
                            lca_val.get("cloudaicompanionProject").and_then(|s| s.as_str())
                        {
                            if !p.is_empty() {
                                project_id = p.to_string();
                            }
                        }
                        let paid = lca_val.pointer("/paidTier/name").and_then(|n| n.as_str());
                        let curr = lca_val.pointer("/currentTier/name").and_then(|n| n.as_str());
                        if let Some(name) = paid.or(curr) {
                            if !name.is_empty() {
                                detected_plan = Some(name.to_string());
                            }
                        }
                    }
                }
            }

            let payload = serde_json::json!({ "project": project_id });
            if let Ok(q_out) = Command::new("curl")
                .args([
                    "-s",
                    "-m",
                    "5",
                    "-X",
                    "POST",
                    &format!("{}/v1internal:retrieveUserQuotaSummary", base_url),
                    "-H",
                    &format!("Authorization: Bearer {}", access_tok),
                    "-H",
                    &format!("User-Agent: {}", ua),
                    "-H",
                    "Content-Type: application/json",
                    "-d",
                    &payload.to_string(),
                ])
                .output()
            {
                if q_out.status.success() {
                    let body = String::from_utf8_lossy(&q_out.stdout).to_string();
                    if body.contains("buckets") {
                        return Some((body, detected_plan));
                    }
                }
            }
        }

        None
    }

    /// Queries live Gemini quota directly via Google Cloud Code endpoint.
    /// 1. Finds active account in gemini accounts directory (prioritizing active_email).
    /// 2. If access_token expired or expiring within 300s, refreshes it via https://oauth2.googleapis.com/token.
    /// 3. Calls loadCodeAssist to resolve cloudaicompanionProject.
    /// 4. Calls retrieveUserQuotaSummary with User-Agent and Bearer auth.
    /// 5. Parses response with parse_agy_quota.
    /// 6. Populates per-account 5h and weekly remaining percentages.
    fn query_gemini_direct(&self, active_email: Option<String>) -> Option<AiProviderQuota> {
        let dir = self.get_gemini_accounts_dir()?;
        if !dir.exists() {
            return None;
        }

        let mut active_path = None;
        let mut active_val = None;

        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|s| s.to_str()) == Some("json") {
                    if let Ok(content) = fs::read_to_string(&path) {
                        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&content) {
                            let is_act = v.get("is_active").and_then(|b| b.as_bool()).unwrap_or(false);
                            let identity = v.get("identity").and_then(|i| i.as_str()).unwrap_or("");
                            let matches_email = active_email
                                .as_deref()
                                .map(|ae| ae.eq_ignore_ascii_case(identity))
                                .unwrap_or(false);

                            if matches_email {
                                active_path = Some(path.clone());
                                active_val = Some(v);
                                break;
                            } else if is_act && active_val.is_none() {
                                active_path = Some(path.clone());
                                active_val = Some(v);
                            } else if active_val.is_none() {
                                active_path = Some(path.clone());
                                active_val = Some(v);
                            }
                        }
                    }
                }
            }
        }

        let mut acc_val = active_val?;
        let active_identity = acc_val
            .get("identity")
            .and_then(|i| i.as_str())
            .map(|s| s.to_string())
            .or(active_email.clone());

        let cred_str = acc_val.get("credential").and_then(|c| c.as_str()).unwrap_or("");
        let mut cred_obj: serde_json::Value = serde_json::from_str(cred_str).ok()?;

        let access_tok = Self::refresh_gemini_token(
            &mut cred_obj,
            active_path.as_deref(),
            Some(&mut acc_val),
        )?;

        let (q_body, detected_plan) = Self::fetch_gemini_quota_json(&access_tok)?;
        let mut quota = parse_agy_quota(&q_body, active_identity.clone()).ok()?;
        quota.account_email = active_identity.clone();
        if let Some(plan) = detected_plan {
            quota.plan_type = Some(plan);
        }

        let monthly_cfg = self.get_gemini_monthly_config();
        let now_ms = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);

        if monthly_cfg.enabled && !quota.windows.iter().any(|w| w.label == "monthly") {
            let active_account_file = active_path.as_deref();
            let per_acc_rem = active_account_file
                .and_then(|p| fs::read_to_string(p).ok())
                .and_then(|c| serde_json::from_str::<serde_json::Value>(&c).ok())
                .and_then(|v| v.get("monthly_remaining_percent").and_then(|n| n.as_f64()))
                .unwrap_or(monthly_cfg.default_remaining_percent);

            let reset_iso = compute_next_monthly_reset_iso(now_ms, monthly_cfg.reset_day);
            quota.windows.push(QuotaWindow {
                label: "monthly".to_string(),
                used_percent: ((100.0 - per_acc_rem) * 10.0).round() / 10.0,
                remaining_percent: (per_acc_rem * 10.0).round() / 10.0,
                reset_at: Some(reset_iso),
            });
            quota.windows.sort_by_key(|w| match w.label.as_str() {
                "5h" => 1,
                "weekly" => 2,
                "monthly" => 3,
                _ => 4,
            });
        }

        let mut accounts = self.load_configured_gemini_accounts(active_identity.as_deref());
        let w_5h = quota.windows.iter().find(|w| w.label == "5h");
        let w_wk = quota.windows.iter().find(|w| w.label == "weekly");
        let w_mo = quota.windows.iter().find(|w| w.label == "monthly");
        let act_5h = w_5h.map(|w| w.remaining_percent);
        let act_wk = w_wk.map(|w| w.remaining_percent);
        let act_mo = w_mo.map(|w| w.remaining_percent);

        for acc in &mut accounts {
            if acc.is_active {
                acc.five_hour_remaining_percent = act_5h;
                acc.weekly_remaining_percent = act_wk;
                acc.monthly_remaining_percent = act_mo;
                acc.windows = quota.windows.clone();
            } else {
                let acc_file = dir.join(format!("{}.json", acc.id));
                let mut acc_per_mo = monthly_cfg.default_remaining_percent;
                if let Ok(c) = fs::read_to_string(&acc_file) {
                    if let Ok(mut a_val) = serde_json::from_str::<serde_json::Value>(&c) {
                        if let Some(r) = a_val.get("monthly_remaining_percent").and_then(|n| n.as_f64()) {
                            acc_per_mo = r;
                        }
                        if let Some(c_str) = a_val.get("credential").and_then(|c| c.as_str()) {
                            if let Ok(mut c_json) = serde_json::from_str::<serde_json::Value>(c_str) {
                                if let Some(tok) = Self::refresh_gemini_token(
                                    &mut c_json,
                                    Some(&acc_file),
                                    Some(&mut a_val),
                                ) {
                                    if let Some((other_body, _)) = Self::fetch_gemini_quota_json(&tok) {
                                        if let Ok(mut other_q) = parse_agy_quota(&other_body, Some(acc.identity.clone())) {
                                            if monthly_cfg.enabled && !other_q.windows.iter().any(|w| w.label == "monthly") {
                                                let reset_iso = compute_next_monthly_reset_iso(now_ms, monthly_cfg.reset_day);
                                                other_q.windows.push(QuotaWindow {
                                                    label: "monthly".to_string(),
                                                    used_percent: ((100.0 - acc_per_mo) * 10.0).round() / 10.0,
                                                    remaining_percent: (acc_per_mo * 10.0).round() / 10.0,
                                                    reset_at: Some(reset_iso),
                                                });
                                                other_q.windows.sort_by_key(|w| match w.label.as_str() {
                                                    "5h" => 1,
                                                    "weekly" => 2,
                                                    "monthly" => 3,
                                                    _ => 4,
                                                });
                                            }
                                            acc.five_hour_remaining_percent = other_q
                                                .windows
                                                .iter()
                                                .find(|w| w.label == "5h")
                                                .map(|w| w.remaining_percent);
                                            acc.weekly_remaining_percent = other_q
                                                .windows
                                                .iter()
                                                .find(|w| w.label == "weekly")
                                                .map(|w| w.remaining_percent);
                                            acc.monthly_remaining_percent = other_q
                                                .windows
                                                .iter()
                                                .find(|w| w.label == "monthly")
                                                .map(|w| w.remaining_percent);
                                            acc.windows = other_q.windows;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        quota.accounts = accounts;

        Some(quota)
    }

    /// Queries live Gemini quota using `timeout 3 agy --output-format json -p='/quota'`
    fn query_agy_quota(&self, active_email: Option<String>) -> Option<AiProviderQuota> {
        let output = Command::new("timeout")
            .args(["3", "agy", "--output-format", "json", "-p=/quota"])
            .output()
            .ok()?;

        if output.status.success() {
            let body = String::from_utf8_lossy(&output.stdout);
            let mut quota = parse_agy_quota(&body, active_email.clone()).ok()?;
            let monthly_cfg = self.get_gemini_monthly_config();
            if monthly_cfg.enabled && !quota.windows.iter().any(|w| w.label == "monthly") {
                let now_ms = SystemTime::now()
                    .duration_since(SystemTime::UNIX_EPOCH)
                    .map(|d| d.as_millis() as i64)
                    .unwrap_or(0);
                let reset_iso = compute_next_monthly_reset_iso(now_ms, monthly_cfg.reset_day);
                quota.windows.push(QuotaWindow {
                    label: "monthly".to_string(),
                    used_percent: ((100.0 - monthly_cfg.default_remaining_percent) * 10.0).round() / 10.0,
                    remaining_percent: (monthly_cfg.default_remaining_percent * 10.0).round() / 10.0,
                    reset_at: Some(reset_iso),
                });
                quota.windows.sort_by_key(|w| match w.label.as_str() {
                    "5h" => 1,
                    "weekly" => 2,
                    "monthly" => 3,
                    _ => 4,
                });
            }
            quota.accounts = self.load_configured_gemini_accounts(active_email.as_deref());
            Some(quota)
        } else {
            None
        }
    }

    fn query_gemini_quota(&self, active_email: Option<String>) -> Option<AiProviderQuota> {
        if let Some(direct) = self.query_gemini_direct(active_email.clone()) {
            return Some(direct);
        }
        self.query_agy_quota(active_email)
    }

    /// Aggregated snapshot fetcher:
    /// 1. Resolves active Gemini identity from Desktop Keyring SSOT.
    /// 2. If fresh cache exists (< 5 min) and matches active identity, returns it.
    /// 3. Otherwise, autonomously polls `agy`, OpenCode Go, MiniMax, and Xiaomi MiMo directly.
    /// 4. Writes snapshot to ~/.cache/astral-plasma/ai_quotas.json.
    pub fn get_snapshot(
        &self,
        warning_thr: f64,
        critical_thr: f64,
        force_refresh: bool,
    ) -> AiQuotaSnapshot {
        self.ensure_storage_migrated();
        let active_gemini_email = self.get_active_gemini_email();

        // 1. Try reading astral-plasma's own cache if not forcing refresh
        if !force_refresh {
            if let Some(cache_path) = self.get_cache_file() {
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
                            if let Ok(mut snap) =
                                serde_json::from_str::<AiQuotaSnapshot>(&content)
                            {
                                let cache_gemini_matches =
                                    match (&active_gemini_email, &snap.active_gemini_email) {
                                        (Some(a), Some(b)) => a.eq_ignore_ascii_case(b),
                                        (None, None) => true,
                                        _ => false,
                                    };

                                if cache_gemini_matches {
                                    let monthly_cfg = self.get_gemini_monthly_config();
                                    let now_ms = SystemTime::now()
                                        .duration_since(SystemTime::UNIX_EPOCH)
                                        .map(|d| d.as_millis() as i64)
                                        .unwrap_or(0);
                                    let reset_iso = compute_next_monthly_reset_iso(now_ms, monthly_cfg.reset_day);

                                    for p in &mut snap.providers {
                                        if p.provider_id == "gemini" {
                                            if p.accounts.is_empty() {
                                                p.accounts = self.load_configured_gemini_accounts(
                                                    active_gemini_email.as_deref(),
                                                );
                                            }
                                            if monthly_cfg.enabled {
                                                if let Some(w) = p.windows.iter_mut().find(|w| w.label == "monthly") {
                                                    w.remaining_percent = (monthly_cfg.default_remaining_percent * 10.0).round() / 10.0;
                                                    w.used_percent = ((100.0 - monthly_cfg.default_remaining_percent) * 10.0).round() / 10.0;
                                                    w.reset_at = Some(reset_iso.clone());
                                                } else {
                                                    p.windows.push(QuotaWindow {
                                                        label: "monthly".to_string(),
                                                        used_percent: ((100.0 - monthly_cfg.default_remaining_percent) * 10.0).round() / 10.0,
                                                        remaining_percent: (monthly_cfg.default_remaining_percent * 10.0).round() / 10.0,
                                                        reset_at: Some(reset_iso.clone()),
                                                    });
                                                    p.windows.sort_by_key(|w| match w.label.as_str() {
                                                        "5h" => 1,
                                                        "weekly" => 2,
                                                        "monthly" => 3,
                                                        _ => 4,
                                                    });
                                                }
                                                for acc in &mut p.accounts {
                                                    if acc.monthly_remaining_percent.is_none() {
                                                        acc.monthly_remaining_percent = Some(monthly_cfg.default_remaining_percent);
                                                    }
                                                }
                                            } else {
                                                p.windows.retain(|w| w.label != "monthly");
                                                for acc in &mut p.accounts {
                                                    acc.monthly_remaining_percent = None;
                                                }
                                            }
                                        }
                                    }
                                    snap.compute_metrics(warning_thr, critical_thr);
                                    return snap;
                                }
                            }
                        }
                    }
                }
            }

        }

        // 2. Autonomous querying: fetch all providers directly
        let mut providers = Vec::new();

        if let Some(gemini) = self.query_gemini_quota(active_gemini_email.clone()) {
            providers.push(gemini);
        }

        if let Some(opencode) = self.query_opencode_usage() {
            providers.push(opencode);
        }

        if let Some(minimax) = self.query_minimax_quota() {
            providers.push(minimax);
        }

        if let Some(xiaomi) = self.query_xiaomi_quota() {
            providers.push(xiaomi);
        }

        // Preserve any previously cached non-Gemini providers that were not fetched in this pass
        if let Some(cache_path) = self.get_cache_file() {
            if let Ok(content) = fs::read_to_string(&cache_path) {
                if let Ok(prev_snap) = serde_json::from_str::<AiQuotaSnapshot>(&content) {
                    for prev_p in prev_snap.providers {
                        if prev_p.provider_id != "gemini"
                            && !providers.iter().any(|p| p.provider_id == prev_p.provider_id)
                        {
                            providers.push(prev_p);
                        }
                    }
                }
            }
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

        // Save to astral-plasma's own cache file
        if let Some(cache_path) = self.get_cache_file() {
            if let Some(parent) = cache_path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            if let Ok(json_str) = serde_json::to_string_pretty(&snapshot) {
                let _ = fs::write(cache_path, json_str);
            }
        }

        snapshot
    }
}

fn chrono_lite_rfc3339() -> String {
    use std::time::UNIX_EPOCH;
    let dur = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    format!("{}.{:03}Z", dur.as_secs(), dur.subsec_millis())
}
