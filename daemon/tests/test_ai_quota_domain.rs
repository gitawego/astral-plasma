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

#[test]
fn test_parse_minimax_usage_success() {
    let json_data = r#"{
        "base_resp": {
            "status_code": 0,
            "status_msg": "success"
        },
        "model_remains": [
            {
                "model_name": "general",
                "end_time": 1727103728000,
                "current_interval_remaining_percent": 85.0,
                "current_weekly_remaining_percent": 92.5,
                "weekly_end_time": 1727654400000,
                "current_weekly_status": 1
            }
        ]
    }"#;

    let res = parse_minimax_usage(json_data);
    assert!(res.is_ok(), "Expected parse_minimax_usage to succeed");
    let provider = res.unwrap();
    assert_eq!(provider.provider_id, "minimax-cn");
    assert_eq!(provider.display_name, "MiniMax");
    assert_eq!(provider.windows.len(), 2);

    let w_5h = provider.windows.iter().find(|w| w.label == "5h").unwrap();
    assert_eq!(w_5h.remaining_percent, 85.0);
    assert_eq!(w_5h.used_percent, 15.0);
    assert!(w_5h.reset_at.is_some());

    let w_weekly = provider.windows.iter().find(|w| w.label == "weekly").unwrap();
    assert_eq!(w_weekly.remaining_percent, 92.5);
    assert_eq!(w_weekly.used_percent, 7.5);
    assert!(w_weekly.reset_at.is_some());
}

#[test]
fn test_parse_xiaomi_usage_success() {
    let json_data = r#"{
        "base_resp": {
            "status_code": 0
        },
        "model_remains": [
            {
                "model_name": "general",
                "end_time": 1727103728000,
                "current_interval_remaining_percent": 60.0,
                "current_weekly_remaining_percent": 75.0,
                "weekly_end_time": 1727654400000
            }
        ]
    }"#;

    let res = parse_xiaomi_usage(json_data);
    assert!(res.is_ok(), "Expected parse_xiaomi_usage to succeed");
    let provider = res.unwrap();
    assert_eq!(provider.provider_id, "xiaomi-mimo-cn");
    assert_eq!(provider.display_name, "Xiaomi Mimo");
    assert_eq!(provider.windows.len(), 2);

    let w_5h = provider.windows.iter().find(|w| w.label == "5h").unwrap();
    assert_eq!(w_5h.remaining_percent, 60.0);
    assert_eq!(w_5h.used_percent, 40.0);

    let w_weekly = provider.windows.iter().find(|w| w.label == "weekly").unwrap();
    assert_eq!(w_weekly.remaining_percent, 75.0);
    assert_eq!(w_weekly.used_percent, 25.0);
}

#[test]
fn test_epoch_millis_to_rfc3339() {
    // 1727103728000 is 2024-09-23T15:02:08Z
    let ts = epoch_millis_to_rfc3339(1727103728000);
    assert_eq!(ts, "2024-09-23T15:02:08Z");
}

#[test]
fn test_parse_google_retrieve_user_quota_summary_direct() {
    let google_json = r#"{
      "groups": [
        {
          "buckets": [
            {
              "bucketId": "gemini-weekly",
              "displayName": "Weekly Limit Remaining",
              "window": "weekly",
              "resetTime": "2026-09-30T06:22:36Z",
              "description": "You have used some of your weekly limit.",
              "remainingFraction": 0.8197143
            },
            {
              "bucketId": "gemini-5h",
              "displayName": "Five Hour Limit Remaining",
              "window": "5h",
              "resetTime": "2026-09-23T17:42:08Z",
              "description": "You have used some of your 5-hour limit.",
              "remainingFraction": 0.5200421
            }
          ],
          "displayName": "Gemini Models",
          "description": "Models within this group: Gemini Flash, Gemini Pro"
        },
        {
          "buckets": [
            {
              "bucketId": "3p-weekly",
              "displayName": "Weekly Limit Remaining",
              "window": "weekly",
              "resetTime": "2026-09-30T14:07:08Z",
              "remainingFraction": 1
            },
            {
              "bucketId": "3p-5h",
              "displayName": "Five Hour Limit Remaining",
              "window": "5h",
              "resetTime": "2026-09-23T19:07:08Z",
              "remainingFraction": 1
            }
          ],
          "displayName": "Claude and GPT models",
          "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS"
        }
      ]
    }"#;

    let res = parse_agy_quota(google_json, Some("gitawego@gmail.com".to_string()));
    assert!(res.is_ok(), "Expected parse_agy_quota to succeed on Google retrieveUserQuotaSummary payload");
    let provider = res.unwrap();
    assert_eq!(provider.provider_id, "gemini");
    assert_eq!(provider.account_email.as_deref(), Some("gitawego@gmail.com"));
    assert_eq!(provider.windows.len(), 2);

    let w_5h = provider.windows.iter().find(|w| w.label == "5h").unwrap();
    assert_eq!(w_5h.remaining_percent, 52.0);
    assert_eq!(w_5h.used_percent, 48.0);
    assert_eq!(w_5h.reset_at.as_deref(), Some("2026-09-23T17:42:08Z"));

    let w_weekly = provider.windows.iter().find(|w| w.label == "weekly").unwrap();
    assert_eq!(w_weekly.remaining_percent, 82.0);
    assert_eq!(w_weekly.used_percent, 18.0);
    assert_eq!(w_weekly.reset_at.as_deref(), Some("2026-09-30T06:22:36Z"));
}


