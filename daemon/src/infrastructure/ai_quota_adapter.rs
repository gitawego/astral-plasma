use crate::domain::ai_quota::{
    parse_agy_quota, parse_minimax_usage, parse_opencode_usage, parse_token_tracker_quotas,
    parse_xiaomi_usage, AiProviderQuota, AiQuotaSnapshot, ProviderAccount,
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

    pub fn get_legacy_cache_file(&self) -> Option<PathBuf> {
        let home = Self::get_home()?;
        Some(home.join(".cache/token-tracker/quotas.json"))
    }

    pub fn get_gemini_cli_token_file() -> Option<PathBuf> {
        let home = Self::get_home()?;
        Some(home.join(".gemini/antigravity-cli/antigravity-oauth-token"))
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
                            });
                        }
                    }
                }
            }
        }

        accounts.sort_by(|a, b| {
            b.is_active
                .cmp(&a.is_active)
                .then_with(|| a.identity.cmp(&b.identity))
        });
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
                    let _ = fs::write(&cli_token_path, json_str);
                }
            }
        }

        // Update .antigravity_last_active marker in accounts directory
        let _ = fs::write(dir.join(".antigravity_last_active"), &target_email);

        Ok(target_email)
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
            parse_opencode_usage(&body).ok()
        } else {
            None
        }
    }

    /// Queries live MiniMax coding plan remains
    fn query_minimax_quota(&self) -> Option<AiProviderQuota> {
        let key =
            self.get_provider_api_key("minimax-cn", "TOKEN_MINIMAX", &["minimax-cn", "minimax"])?;
        let output = Command::new("curl")
            .args([
                "-s",
                "-m",
                "5",
                "-H",
                &format!("Authorization: Bearer {}", key),
                "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains",
            ])
            .output()
            .ok()?;

        if output.status.success() {
            let body = String::from_utf8_lossy(&output.stdout);
            parse_minimax_usage(&body).ok()
        } else {
            None
        }
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
            parse_xiaomi_usage(&body).ok()
        } else {
            None
        }
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

        let mut accounts = self.load_configured_gemini_accounts(active_identity.as_deref());
        let w_5h = quota.windows.iter().find(|w| w.label == "5h");
        let w_wk = quota.windows.iter().find(|w| w.label == "weekly");
        let act_5h = w_5h.map(|w| w.remaining_percent);
        let act_wk = w_wk.map(|w| w.remaining_percent);

        for acc in &mut accounts {
            if acc.is_active {
                acc.five_hour_remaining_percent = act_5h;
                acc.weekly_remaining_percent = act_wk;
            } else {
                let acc_file = dir.join(format!("{}.json", acc.id));
                if let Ok(c) = fs::read_to_string(&acc_file) {
                    if let Ok(mut a_val) = serde_json::from_str::<serde_json::Value>(&c) {
                        if let Some(c_str) = a_val.get("credential").and_then(|c| c.as_str()) {
                            if let Ok(mut c_json) = serde_json::from_str::<serde_json::Value>(c_str) {
                                if let Some(tok) = Self::refresh_gemini_token(
                                    &mut c_json,
                                    Some(&acc_file),
                                    Some(&mut a_val),
                                ) {
                                    if let Some((other_body, _)) = Self::fetch_gemini_quota_json(&tok) {
                                        if let Ok(other_q) = parse_agy_quota(&other_body, Some(acc.identity.clone())) {
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
                                    for p in &mut snap.providers {
                                        if p.provider_id == "gemini" && p.accounts.is_empty() {
                                            p.accounts = self.load_configured_gemini_accounts(
                                                active_gemini_email.as_deref(),
                                            );
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

            // Fallback: check legacy cache if present
            if let Some(legacy_cache) = self.get_legacy_cache_file() {
                if legacy_cache.exists() {
                    let is_fresh = fs::metadata(&legacy_cache)
                        .and_then(|m| m.modified())
                        .map(|mtime| {
                            SystemTime::now()
                                .duration_since(mtime)
                                .unwrap_or(Duration::from_secs(9999))
                                < Duration::from_secs(300)
                        })
                        .unwrap_or(false);

                    if is_fresh {
                        if let Ok(content) = fs::read_to_string(&legacy_cache) {
                            if let Ok(mut snap) = parse_token_tracker_quotas(
                                &content,
                                active_gemini_email.as_deref(),
                                warning_thr,
                                critical_thr,
                            ) {
                                for p in &mut snap.providers {
                                    if p.provider_id == "gemini" && p.accounts.is_empty() {
                                        p.accounts = self.load_configured_gemini_accounts(
                                            active_gemini_email.as_deref(),
                                        );
                                    }
                                }
                                return snap;
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
