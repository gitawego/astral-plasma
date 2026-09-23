use astral_plasma::infrastructure::ai_quota_adapter::AiQuotaAdapter;
use std::fs;
use tempfile::TempDir;

#[test]
fn test_remove_active_account_promotes_next() {
    let temp_root = TempDir::new().unwrap();
    let config_dir = temp_root.path().join("astral-plasma");
    let gemini_dir = config_dir.join("accounts/gemini");
    fs::create_dir_all(&gemini_dir).unwrap();

    let acc1 = serde_json::json!({
        "id": "gemini_1",
        "provider_id": "gemini",
        "label": "Account 1",
        "identity": "primary@gmail.com",
        "credential": "{\"access_token\":\"tok1\",\"refresh_token\":\"ref1\"}",
        "is_active": true
    });
    fs::write(gemini_dir.join("gemini_1.json"), serde_json::to_string_pretty(&acc1).unwrap()).unwrap();

    let acc2 = serde_json::json!({
        "id": "gemini_2",
        "provider_id": "gemini",
        "label": "Account 2",
        "identity": "secondary@gmail.com",
        "credential": "{\"access_token\":\"tok2\",\"refresh_token\":\"ref2\"}",
        "is_active": false
    });
    fs::write(gemini_dir.join("gemini_2.json"), serde_json::to_string_pretty(&acc2).unwrap()).unwrap();
    fs::write(gemini_dir.join(".antigravity_last_active"), "primary@gmail.com").unwrap();

    let cache_dir = temp_root.path().join("cache");
    let adapter = AiQuotaAdapter::with_dirs(cache_dir, config_dir.clone(), None);

    // Remove active account gemini_1
    let result = adapter.remove_account("gemini", "gemini_1");
    assert!(result.is_ok(), "remove_account failed: {:?}", result.err());

    // File gemini_1.json must no longer exist
    assert!(!gemini_dir.join("gemini_1.json").exists());

    // File gemini_2.json must exist and be promoted to is_active: true
    let content2 = fs::read_to_string(gemini_dir.join("gemini_2.json")).unwrap();
    let val2: serde_json::Value = serde_json::from_str(&content2).unwrap();
    assert_eq!(val2.get("is_active").and_then(|b| b.as_bool()), Some(true));

    // Marker must be updated to secondary@gmail.com
    let marker = fs::read_to_string(gemini_dir.join(".antigravity_last_active")).unwrap();
    assert_eq!(marker.trim(), "secondary@gmail.com");
}

#[test]
fn test_remove_inactive_account_keeps_active() {
    let temp_root = TempDir::new().unwrap();
    let config_dir = temp_root.path().join("astral-plasma");
    let gemini_dir = config_dir.join("accounts/gemini");
    fs::create_dir_all(&gemini_dir).unwrap();

    let acc1 = serde_json::json!({
        "id": "gemini_1",
        "provider_id": "gemini",
        "label": "Account 1",
        "identity": "primary@gmail.com",
        "credential": "{\"access_token\":\"tok1\",\"refresh_token\":\"ref1\"}",
        "is_active": true
    });
    fs::write(gemini_dir.join("gemini_1.json"), serde_json::to_string_pretty(&acc1).unwrap()).unwrap();

    let acc2 = serde_json::json!({
        "id": "gemini_2",
        "provider_id": "gemini",
        "label": "Account 2",
        "identity": "secondary@gmail.com",
        "credential": "{\"access_token\":\"tok2\",\"refresh_token\":\"ref2\"}",
        "is_active": false
    });
    fs::write(gemini_dir.join("gemini_2.json"), serde_json::to_string_pretty(&acc2).unwrap()).unwrap();
    fs::write(gemini_dir.join(".antigravity_last_active"), "primary@gmail.com").unwrap();

    let cache_dir = temp_root.path().join("cache");
    let adapter = AiQuotaAdapter::with_dirs(cache_dir, config_dir.clone(), None);

    // Remove inactive account by email
    let result = adapter.remove_account("gemini", "secondary@gmail.com");
    assert!(result.is_ok());

    assert!(!gemini_dir.join("gemini_2.json").exists());
    assert!(gemini_dir.join("gemini_1.json").exists());

    let marker = fs::read_to_string(gemini_dir.join(".antigravity_last_active")).unwrap();
    assert_eq!(marker.trim(), "primary@gmail.com");
}

#[test]
fn test_add_account_for_provider() {
    let temp_root = TempDir::new().unwrap();
    let config_dir = temp_root.path().join("astral-plasma");
    let cache_dir = temp_root.path().join("cache");
    let adapter = AiQuotaAdapter::with_dirs(cache_dir, config_dir.clone(), None);

    let result = adapter.add_account("minimax-cn", "test_minimax_jwt_123", Some("MiniMax Work"), false);
    assert!(result.is_ok(), "add_account failed: {:?}", result.err());

    let acc_dir = config_dir.join("accounts/minimax-cn");
    assert!(acc_dir.exists());

    let files: Vec<_> = fs::read_dir(&acc_dir).unwrap().map(|e| e.unwrap().path()).collect();
    assert_eq!(files.len(), 1);

    let c = fs::read_to_string(&files[0]).unwrap();
    let v: serde_json::Value = serde_json::from_str(&c).unwrap();
    assert_eq!(v.get("provider_id").and_then(|s| s.as_str()), Some("minimax-cn"));
    assert_eq!(v.get("label").and_then(|s| s.as_str()), Some("MiniMax Work"));
    assert_eq!(v.get("credential").and_then(|s| s.as_str()), Some("test_minimax_jwt_123"));

    // Verify credentials.json was updated
    let creds_file = config_dir.join("credentials.json");
    assert!(creds_file.exists());
    let creds: serde_json::Value = serde_json::from_str(&fs::read_to_string(creds_file).unwrap()).unwrap();
    assert_eq!(creds.get("minimax-cn").and_then(|s| s.as_str()), Some("test_minimax_jwt_123"));
}

#[test]
fn test_reauth_in_place_preserves_account_id() {
    let temp_root = TempDir::new().unwrap();
    let config_dir = temp_root.path().join("astral-plasma");
    let gemini_dir = config_dir.join("accounts/gemini");
    fs::create_dir_all(&gemini_dir).unwrap();

    let acc1 = serde_json::json!({
        "id": "gemini_original_id",
        "provider_id": "gemini",
        "label": "Original Label",
        "identity": "existing@gmail.com",
        "credential": "{\"access_token\":\"old_tok\",\"refresh_token\":\"old_ref\"}",
        "is_active": false
    });
    fs::write(gemini_dir.join("gemini_original_id.json"), serde_json::to_string_pretty(&acc1).unwrap()).unwrap();

    let cache_dir = temp_root.path().join("cache");
    let adapter = AiQuotaAdapter::with_dirs(cache_dir, config_dir.clone(), None);

    let token_resp = serde_json::json!({
        "access_token": "new_access_token_123",
        "refresh_token": "new_refresh_token_456",
        "expires_in": 3600
    }).to_string();

    let userinfo_resp = serde_json::json!({
        "email": "existing@gmail.com",
        "name": "Updated Name"
    }).to_string();

    let res = adapter.save_gemini_oauth_account(&token_resp, &userinfo_resp).unwrap();
    assert_eq!(res.get("reauthenticated").and_then(|b| b.as_bool()), Some(true));
    assert_eq!(res.get("account_id").and_then(|s| s.as_str()), Some("gemini_original_id"));

    // Verify file content has updated tokens and preserves the original account file
    let c = fs::read_to_string(gemini_dir.join("gemini_original_id.json")).unwrap();
    assert!(c.contains("new_access_token_123"));
    assert!(c.contains("new_refresh_token_456"));
    let v: serde_json::Value = serde_json::from_str(&c).unwrap();
    assert_eq!(v.get("is_active").and_then(|b| b.as_bool()), Some(true));
}

#[test]
fn test_list_accounts_returns_all_configured() {
    let temp_root = TempDir::new().unwrap();
    let config_dir = temp_root.path().join("astral-plasma");
    let gemini_dir = config_dir.join("accounts/gemini");
    fs::create_dir_all(&gemini_dir).unwrap();

    let acc1 = serde_json::json!({
        "id": "acc_1",
        "provider_id": "gemini",
        "label": "Work",
        "identity": "work@example.com",
        "credential": "{}",
        "is_active": true
    });
    fs::write(gemini_dir.join("acc_1.json"), acc1.to_string()).unwrap();

    let cache_dir = temp_root.path().join("cache");
    let adapter = AiQuotaAdapter::with_dirs(cache_dir, config_dir.clone(), None);

    let list = adapter.list_accounts(Some("gemini")).unwrap();
    let arr = list.as_array().unwrap();
    assert_eq!(arr.len(), 1);
    assert_eq!(arr[0].get("id").and_then(|s| s.as_str()), Some("acc_1"));
    assert_eq!(arr[0].get("identity").and_then(|s| s.as_str()), Some("work@example.com"));
    assert_eq!(arr[0].get("is_active").and_then(|b| b.as_bool()), Some(true));
}
