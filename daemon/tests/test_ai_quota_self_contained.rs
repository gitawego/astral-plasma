use astral_plasma::infrastructure::ai_quota_adapter::AiQuotaAdapter;
use std::fs;
use tempfile::TempDir;

#[test]
fn test_one_time_migration_from_token_tracker() {
    let temp_root = TempDir::new().unwrap();
    let legacy_dir = temp_root.path().join("token-tracker");
    let legacy_gemini = legacy_dir.join("accounts/gemini");
    fs::create_dir_all(&legacy_gemini).unwrap();

    let acc1_json = serde_json::json!({
        "id": "gemini_acc_1",
        "provider_id": "gemini",
        "label": "Work Account",
        "identity": "hongbo@work.com",
        "credential": "{\"access_token\":\"xyz\",\"refresh_token\":\"abc\"}",
        "is_active": true
    });
    fs::write(legacy_gemini.join("acc1.json"), acc1_json.to_string()).unwrap();

    let creds_json = serde_json::json!({
        "minimax-cn": "minimax_test_secret",
        "opencode-go": "opencode_test_secret"
    });
    fs::write(legacy_dir.join("credentials.json"), creds_json.to_string()).unwrap();

    let config_dir = temp_root.path().join("astral-plasma");
    let cache_dir = temp_root.path().join("cache");

    // Initialize adapter with isolated test directories
    let adapter = AiQuotaAdapter::with_dirs(cache_dir, config_dir.clone(), Some(legacy_dir));
    adapter.ensure_storage_migrated();

    // 1. Verify accounts were copied into astral-plasma directory
    let migrated_acc = config_dir.join("accounts/gemini/acc1.json");
    assert!(migrated_acc.exists(), "Expected acc1.json to be migrated to astral-plasma/accounts/gemini");

    let migrated_content = fs::read_to_string(&migrated_acc).unwrap();
    assert!(migrated_content.contains("hongbo@work.com"));

    // 2. Verify credentials were copied
    let migrated_creds = config_dir.join("credentials.json");
    assert!(migrated_creds.exists(), "Expected credentials.json to be migrated");

    // 3. Verify loading configured accounts reads from astral-plasma
    let accounts = adapter.load_configured_gemini_accounts(None);
    assert_eq!(accounts.len(), 1);
    assert_eq!(accounts[0].identity, "hongbo@work.com");
    assert!(accounts[0].is_active);
}

#[test]
fn test_switch_gemini_account_in_self_contained_dir() {
    let temp_root = TempDir::new().unwrap();
    let config_dir = temp_root.path().join("astral-plasma");
    let gemini_dir = config_dir.join("accounts/gemini");
    fs::create_dir_all(&gemini_dir).unwrap();

    let acc1 = serde_json::json!({
        "id": "acc_1",
        "provider_id": "gemini",
        "label": "Account 1",
        "identity": "user1@gmail.com",
        "credential": "{\"access_token\":\"tok1\",\"refresh_token\":\"ref1\"}",
        "is_active": true
    });
    fs::write(gemini_dir.join("acc1.json"), serde_json::to_string_pretty(&acc1).unwrap()).unwrap();

    let acc2 = serde_json::json!({
        "id": "acc_2",
        "provider_id": "gemini",
        "label": "Account 2",
        "identity": "user2@gmail.com",
        "credential": "{\"access_token\":\"tok2\",\"refresh_token\":\"ref2\"}",
        "is_active": false
    });
    fs::write(gemini_dir.join("acc2.json"), serde_json::to_string_pretty(&acc2).unwrap()).unwrap();

    let cache_dir = temp_root.path().join("cache");
    let adapter = AiQuotaAdapter::with_dirs(cache_dir, config_dir.clone(), None);

    // Switch to user2@gmail.com
    let switched = adapter.switch_gemini_account("user2@gmail.com");
    assert!(switched.is_ok(), "Expected switch to succeed");
    assert_eq!(switched.unwrap(), "user2@gmail.com");

    // Verify acc1 is now inactive
    let c1: serde_json::Value = serde_json::from_str(&fs::read_to_string(gemini_dir.join("acc1.json")).unwrap()).unwrap();
    assert_eq!(c1.get("is_active").and_then(|a| a.as_bool()), Some(false));

    // Verify acc2 is now active
    let c2: serde_json::Value = serde_json::from_str(&fs::read_to_string(gemini_dir.join("acc2.json")).unwrap()).unwrap();
    assert_eq!(c2.get("is_active").and_then(|a| a.as_bool()), Some(true));

    // Verify marker
    let marker = fs::read_to_string(gemini_dir.join(".antigravity_last_active")).unwrap();
    assert_eq!(marker.trim(), "user2@gmail.com");
}

#[test]
fn test_get_provider_api_key_resolution() {
    let temp_root = TempDir::new().unwrap();
    let config_dir = temp_root.path().join("astral-plasma");
    fs::create_dir_all(&config_dir).unwrap();

    let creds = serde_json::json!({
        "minimax-cn": "minimax_secret_123",
        "xiaomi-mimo-cn": "mimo_secret_456"
    });
    fs::write(config_dir.join("credentials.json"), serde_json::to_string_pretty(&creds).unwrap()).unwrap();

    let cache_dir = temp_root.path().join("cache");
    let adapter = AiQuotaAdapter::with_dirs(cache_dir, config_dir, None);

    let k1 = adapter.get_provider_api_key("minimax-cn", "NON_EXISTENT_VAR_123", &["minimax-cn", "minimax"]);
    assert_eq!(k1.as_deref(), Some("minimax_secret_123"));

    let k2 = adapter.get_provider_api_key("xiaomi-mimo-cn", "NON_EXISTENT_VAR_123", &["xiaomi-mimo-cn"]);
    assert_eq!(k2.as_deref(), Some("mimo_secret_456"));
}

#[test]
fn test_stable_gemini_accounts_order_never_changes() {
    let temp_root = TempDir::new().unwrap();
    let config_dir = temp_root.path().join("astral-plasma");
    let gemini_dir = config_dir.join("accounts/gemini");
    fs::create_dir_all(&gemini_dir).unwrap();

    let a1 = serde_json::json!({
        "id": "acc_z",
        "identity": "z_user@gmail.com",
        "label": "Z",
        "credential": "{}",
        "is_active": true
    });
    fs::write(gemini_dir.join("acc_z.json"), a1.to_string()).unwrap();

    let a2 = serde_json::json!({
        "id": "acc_a",
        "identity": "a_user@gmail.com",
        "label": "A",
        "credential": "{}",
        "is_active": false
    });
    fs::write(gemini_dir.join("acc_a.json"), a2.to_string()).unwrap();

    let cache_dir = temp_root.path().join("cache");
    let adapter = AiQuotaAdapter::with_dirs(cache_dir, config_dir, None);

    // Initial load: a_user must come before z_user alphabetically, regardless of is_active
    let accs1 = adapter.load_configured_gemini_accounts(Some("z_user@gmail.com"));
    assert_eq!(accs1[0].identity, "a_user@gmail.com");
    assert!(!accs1[0].is_active);
    assert_eq!(accs1[1].identity, "z_user@gmail.com");
    assert!(accs1[1].is_active);

    // After switching active to a_user: order MUST REMAIN IDENTICAL
    let accs2 = adapter.load_configured_gemini_accounts(Some("a_user@gmail.com"));
    assert_eq!(accs2[0].identity, "a_user@gmail.com");
    assert!(accs2[0].is_active);
    assert_eq!(accs2[1].identity, "z_user@gmail.com");
    assert!(!accs2[1].is_active);
}

#[test]
fn test_parse_minimax_status_2062_pay_as_you_go() {
    use astral_plasma::domain::ai_quota::parse_minimax_usage;
    let json_2062 = r#"{"model_remains":null,"base_resp":{"status_code":2062,"status_msg":"no active token plan subscription"}}"#;
    let res = parse_minimax_usage(json_2062);
    assert!(res.is_ok(), "Expected status 2062 to produce valid pay-as-you-go quota");
    let quota = res.unwrap();
    assert_eq!(quota.provider_id, "minimax-cn");
    assert_eq!(quota.display_name, "MiniMax");
    assert_eq!(quota.plan_type.as_deref(), Some("Pay-as-you-go"));
    assert!(quota.is_available);
    assert!(quota.windows.is_empty());
}
