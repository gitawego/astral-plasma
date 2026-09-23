use astral_plasma::domain::ai_quota::*;

#[test]
fn test_parse_agy_quota_success() {
    let agy_json = r#"{
        "status": "SUCCESS",
        "command": {
            "name": "usage",
            "data": {
                "groups": [
                    {
                        "name": "Gemini Models",
                        "buckets": [
                            {
                                "id": "gemini-5h",
                                "name": "Five Hour Limit Remaining",
                                "window": "5h",
                                "remaining_fraction": 0.45,
                                "reset_time": "2026-09-23T12:42:08Z"
                            },
                            {
                                "id": "gemini-weekly",
                                "name": "Weekly Limit Remaining",
                                "window": "weekly",
                                "remaining_fraction": 0.91,
                                "reset_time": "2026-09-30T06:22:36Z"
                            }
                        ]
                    }
                ]
            }
        }
    }"#;

    let res = parse_agy_quota(agy_json, Some("test@example.com".to_string()));
    assert!(res.is_ok(), "Expected parse_agy_quota to succeed");
    let provider = res.unwrap();
    assert_eq!(provider.provider_id, "gemini");
    assert_eq!(provider.account_email.as_deref(), Some("test@example.com"));
    assert_eq!(provider.windows.len(), 2);

    let win_5h = &provider.windows[0];
    assert_eq!(win_5h.label, "5h");
    assert_eq!(win_5h.used_percent, 55.0);
    assert_eq!(win_5h.remaining_percent, 45.0);

    let win_week = &provider.windows[1];
    assert_eq!(win_week.label, "weekly");
    assert_eq!(win_week.used_percent, 9.0);
    assert_eq!(win_week.remaining_percent, 91.0);
}

#[test]
fn test_parse_opencode_usage_success() {
    let opencode_json = r#"{
        "usage": {
            "rolling": {
                "status": "ok",
                "percent": 15,
                "resetsAt": "2026-09-23T18:00:00Z"
            },
            "weekly": {
                "status": "ok",
                "percent": 82,
                "resetsAt": "2026-09-28T00:00:00Z"
            },
            "monthly": {
                "status": "ok",
                "percent": 45,
                "resetsAt": "2026-10-01T00:00:00Z"
            }
        }
    }"#;

    let res = parse_opencode_usage(opencode_json);
    assert!(res.is_ok());
    let provider = res.unwrap();
    assert_eq!(provider.provider_id, "opencode-go");
    assert_eq!(provider.windows.len(), 3);

    let w_5h = provider.windows.iter().find(|w| w.label == "5h").unwrap();
    assert_eq!(w_5h.used_percent, 15.0);
    assert_eq!(w_5h.remaining_percent, 85.0);

    let w_week = provider.windows.iter().find(|w| w.label == "weekly").unwrap();
    assert_eq!(w_week.used_percent, 82.0);
    assert_eq!(w_week.remaining_percent, 18.0);
}

#[test]
fn test_parse_token_tracker_quotas_stale_gemini_detection() {
    let cache_json = r#"{
        "fetched_at": "2026-09-23T12:00:00Z",
        "providers": [
            {
                "provider_id": "gemini",
                "account_email": "old_account@gmail.com",
                "windows": [
                    { "window_label": "5h", "used": 20, "total": 100 }
                ],
                "accounts": [
                    { "id": "1", "identity": "old_account@gmail.com", "is_active": true },
                    { "id": "2", "identity": "active_keyring@gmail.com", "is_active": false }
                ]
            }
        ]
    }"#;

    // When the Keyring SSOT says the active email is "active_keyring@gmail.com",
    // parse_token_tracker_quotas must detect that the cache is stale!
    let res = parse_token_tracker_quotas(cache_json, Some("active_keyring@gmail.com"), 80.0, 95.0);
    assert!(res.is_err(), "Expected stale cache error when active email differs");
    let err = res.err().unwrap();
    assert!(err.contains("stale_gemini_account"));

    // When active email matches, it succeeds:
    let res_match = parse_token_tracker_quotas(cache_json, Some("old_account@gmail.com"), 80.0, 95.0);
    assert!(res_match.is_ok());
}

#[test]
fn test_warning_level_escalation() {
    let mut snap = AiQuotaSnapshot {
        providers: vec![
            AiProviderQuota {
                provider_id: "opencode-go".to_string(),
                display_name: "OpenCode Go".to_string(),
                icon: "terminal".to_string(),
                plan_type: None,
                account_email: None,
                account_name: None,
                is_available: true,
                windows: vec![
                    QuotaWindow {
                        label: "5h".to_string(),
                        used_percent: 85.0, // >= 80% warning
                        remaining_percent: 15.0,
                        reset_at: None,
                    }
                ],
                accounts: vec![],
                error_message: None,
            }
        ],
        highest_used_percent: 0.0,
        lowest_remaining_percent: 100.0,
        warning_level: "normal".to_string(),
        fetched_at: "now".to_string(),
        active_gemini_email: None,
    };

    snap.compute_metrics(80.0, 95.0);
    assert_eq!(snap.warning_level, "warning");
    assert_eq!(snap.highest_used_percent, 85.0);
    assert_eq!(snap.lowest_remaining_percent, 15.0);

    // Now push it to critical (>= 95%)
    snap.providers[0].windows[0].used_percent = 96.5;
    snap.providers[0].windows[0].remaining_percent = 3.5;
    snap.compute_metrics(80.0, 95.0);
    assert_eq!(snap.warning_level, "critical");
    assert_eq!(snap.highest_used_percent, 96.5);
    assert_eq!(snap.lowest_remaining_percent, 3.5);
}
