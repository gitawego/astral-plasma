//! Regression coverage for resolving the active Gemini identity.
//!
//! `agy` (Antigravity CLI) authenticates through the desktop keyring. Astral used to
//! consult a cached third-party snapshot before the keyring, which could name an
//! account the user had since switched away from. The result was a dock that called
//! one account "Active in CLI" while `agy` was authenticated as another. Live
//! credential stores must win, and the cached source has been removed entirely.

use astral_plasma::infrastructure::ai_quota_adapter::{AiQuotaAdapter, GeminiIdentitySources};
use serde_json::json;

fn live_keyring(email: &str) -> serde_json::Value {
    json!({
        "auth_method": "consumer",
        "id_token_email": email,
        "token": {
            "access_token": "test-access-token",
            "refresh_token": "test-refresh-token",
            "token_type": "Bearer",
            "expiry": "2030-01-01T00:00:00Z"
        }
    })
}

#[test]
fn live_keyring_wins_over_stale_stored_state() {
    let keyring = live_keyring("live-account@example.com");
    let records = vec![
        json!({
            "id": "acc_live",
            "identity": "live-account@example.com",
            "credential": "{\"refresh_token\":\"test-refresh-token\"}",
            "is_active": false
        }),
        json!({
            "id": "acc_stale",
            "identity": "stale-account@example.com",
            "credential": "{\"refresh_token\":\"stale-refresh-token\"}",
            "is_active": true
        }),
    ];

    let resolved = AiQuotaAdapter::resolve_active_gemini_email(GeminiIdentitySources {
        keyring_payload: Some(&keyring),
        marker: Some("stale-account@example.com"),
        account_records: &records,
        ..Default::default()
    });

    assert_eq!(
        resolved.as_deref(),
        Some("live-account@example.com"),
        "the keyring that agy authenticates with must outrank stale stored state"
    );
}

#[test]
fn keyring_refresh_token_matches_the_live_account_record() {
    let keyring = json!({
        "token": {
            "access_token": "test-access-token",
            "refresh_token": "live-refresh-token"
        }
    });
    let records = vec![
        json!({
            "id": "acc_stale",
            "identity": "stale-account@example.com",
            "credential": "{\"refresh_token\":\"stale-refresh-token\"}",
            "is_active": true
        }),
        json!({
            "id": "acc_live",
            "identity": "live-account@example.com",
            "credential": "{\"refresh_token\":\"live-refresh-token\"}",
            "is_active": false
        }),
    ];

    let resolved = AiQuotaAdapter::resolve_active_gemini_email(GeminiIdentitySources {
        keyring_payload: Some(&keyring),
        marker: Some("stale-account@example.com"),
        account_records: &records,
        ..Default::default()
    });

    assert_eq!(resolved.as_deref(), Some("live-account@example.com"));
}

#[test]
fn marker_is_used_when_no_live_credentials_exist() {
    let records = vec![json!({
        "id": "acc_cached",
        "identity": "cached-account@example.com",
        "credential": "{}",
        "is_active": true
    })];

    let resolved = AiQuotaAdapter::resolve_active_gemini_email(GeminiIdentitySources {
        marker: Some("marker-account@example.com"),
        account_records: &records,
        ..Default::default()
    });

    assert_eq!(resolved.as_deref(), Some("marker-account@example.com"));
}
