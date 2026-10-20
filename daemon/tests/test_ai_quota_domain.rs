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
fn test_parse_agy_quota_with_monthly_bucket() {
    let agy_json = r#"{
        "groups": [
            {
                "displayName": "Gemini Models",
                "buckets": [
                    {
                        "bucketId": "gemini-pro-5h",
                        "remainingFraction": 0.40,
                        "resetTime": "2026-09-23T18:00:00Z"
                    },
                    {
                        "bucketId": "gemini-pro-weekly",
                        "remainingFraction": 0.85,
                        "resetTime": "2026-09-30T00:00:00Z"
                    },
                    {
                        "bucketId": "gemini-pro-monthly",
                        "remainingFraction": 0.95,
                        "resetTime": "2026-10-01T00:00:00Z"
                    }
                ]
            }
        ]
    }"#;

    let res = parse_agy_quota(agy_json, Some("monthly_user@gmail.com".to_string()));
    assert!(res.is_ok());
    let p = res.unwrap();
    assert_eq!(p.windows.len(), 3);
    assert_eq!(p.windows[0].label, "5h");
    assert_eq!(p.windows[1].label, "weekly");
    assert_eq!(p.windows[2].label, "monthly");
    assert_eq!(p.windows[2].remaining_percent, 95.0);
    assert_eq!(p.windows[2].used_percent, 5.0);
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
                cache_stats: None,
            }
        ],
        highest_used_percent: 0.0,
        lowest_remaining_percent: 100.0,
        warning_level: "normal".to_string(),
        fetched_at: "now".to_string(),
        active_gemini_email: None,
        global_cache_stats: None,
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

#[test]
fn test_compute_next_monthly_reset_iso() {
    // 1727103728000 is 2024-09-23T15:02:08Z
    let now_ms = 1727103728000;
    // Current day is 23. If reset day is 1, next reset is 2024-10-01T00:00:00Z
    assert_eq!(compute_next_monthly_reset_iso(now_ms, 1), "2024-10-01T00:00:00Z");
    // If reset day is 25, current day 23 < 25, next reset is 2024-09-25T00:00:00Z
    assert_eq!(compute_next_monthly_reset_iso(now_ms, 25), "2024-09-25T00:00:00Z");
    // Clamp to 28 (today 23 < 28, so still this month)
    assert_eq!(compute_next_monthly_reset_iso(now_ms, 31), "2024-09-28T00:00:00Z");
    // If reset day was 20 (today 23 >= 20, so next month)
    assert_eq!(compute_next_monthly_reset_iso(now_ms, 20), "2024-10-20T00:00:00Z");
}

#[test]
fn test_token_cache_stats_hit_rate() {
    use astral_plasma::domain::ai_quota::TokenCacheStats;

    let stats = TokenCacheStats {
        cached_tokens: 9000,
        uncached_input_tokens: 1000,
        output_tokens: 500,
        total_prompt_tokens: 10000,
        cache_hit_rate_percent: 90.0,
    };

    assert_eq!(stats.total_prompt_tokens, 10000);
    assert_eq!(stats.cache_hit_rate_percent, 90.0);
    assert_eq!(stats.cached_tokens, 9000);
    assert_eq!(stats.uncached_input_tokens, 1000);
}

// --- Passive `agy` quota probe: fail-closed guard ---------------------------
//
// Regression guard: the shell polled `agy -p='/quota'` every few minutes. When the
// stored token had expired, `agy` escalated its failed silent auth into an
// interactive OAuth window in the user's browser, so the desktop was hit by a
// recurring Google sign-in popup. The probe must refuse to run unless the stored
// token can be used without any human interaction.

#[test]
fn test_agy_probe_timeout_outlives_cli_silent_auth_budget() {
    assert!(
        AGY_PROBE_TIMEOUT_SECS > AGY_SILENT_AUTH_BUDGET_SECS,
        "probe timeout ({}s) must exceed agy's silent-auth budget ({}s); otherwise the CLI is \
         killed mid-refresh and escalates to interactive OAuth",
        AGY_PROBE_TIMEOUT_SECS,
        AGY_SILENT_AUTH_BUDGET_SECS
    );
}

#[test]
fn test_agy_token_allows_probe_for_valid_token() {
    let json = r#"{"auth_method":"consumer","token":{"access_token":"ya29.abc","expiry":"2026-10-20T18:55:33Z","refresh_token":"1//rt","token_type":"Bearer"}}"#;
    let now = parse_rfc3339_utc_secs("2026-10-20T18:00:00Z").unwrap();
    assert!(
        agy_token_allows_probe(json, now),
        "a token that expires in the future must allow the probe"
    );
}

#[test]
fn test_agy_token_allows_probe_rejects_expired_token() {
    let json = r#"{"token":{"access_token":"ya29.abc","expiry":"2026-10-19T21:53:30Z","refresh_token":"1//rt"}}"#;
    let now = parse_rfc3339_utc_secs("2026-10-20T13:43:43Z").unwrap();
    assert!(
        !agy_token_allows_probe(json, now),
        "an expired token must fail closed instead of letting the CLI open a browser"
    );
}

#[test]
fn test_agy_token_allows_probe_rejects_expiry_equal_to_now() {
    let json = r#"{"token":{"access_token":"ya29.abc","expiry":"2026-10-20T13:43:43Z"}}"#;
    let now = parse_rfc3339_utc_secs("2026-10-20T13:43:43Z").unwrap();
    assert!(!agy_token_allows_probe(json, now), "a token expiring now is already unusable");
}

#[test]
fn test_agy_token_allows_probe_rejects_unusable_documents() {
    let now = parse_rfc3339_utc_secs("2026-10-20T13:43:43Z").unwrap();

    assert!(!agy_token_allows_probe("", now), "empty file must fail closed");
    assert!(!agy_token_allows_probe("not json", now), "garbage must fail closed");
    assert!(
        !agy_token_allows_probe(r#"{"auth_method":"consumer"}"#, now),
        "a document without token/expiry must fail closed"
    );
    assert!(
        !agy_token_allows_probe(r#"{"token":{"expiry":"2026-10-20T18:55:33Z"}}"#, now),
        "a token without an access_token must fail closed"
    );
    assert!(
        !agy_token_allows_probe(r#"{"token":{"access_token":"ya29.abc"}}"#, now),
        "a token without an expiry must fail closed"
    );
    assert!(
        !agy_token_allows_probe(
            r#"{"token":{"access_token":"ya29.abc","expiry":"2026-10-20T18:55:33Z"}}"#,
            parse_rfc3339_utc_secs("2026-10-21T00:00:00Z").unwrap()
        ),
        "expiry must be re-evaluated against the supplied clock"
    );
}

#[test]
fn test_parse_rfc3339_utc_secs_accepts_z_fraction_and_offsets() {
    let base = parse_rfc3339_utc_secs("2026-10-20T18:00:00Z").expect("Z form must parse");
    assert_eq!(
        parse_rfc3339_utc_secs("2026-10-20T18:00:00.123456789Z").expect("fractional form must parse"),
        base,
        "fractional seconds must not shift the timestamp"
    );
    assert_eq!(
        parse_rfc3339_utc_secs("2026-10-20T20:00:00+02:00").expect("positive offset must parse"),
        base,
        "+02:00 must normalise to UTC"
    );
    assert_eq!(
        parse_rfc3339_utc_secs("2026-10-20T13:00:00-05:00").expect("negative offset must parse"),
        base,
        "-05:00 must normalise to UTC"
    );
    assert_eq!(
        parse_rfc3339_utc_secs("1970-01-01T00:00:00Z"),
        Some(0),
        "the epoch itself must parse to 0"
    );
    assert_eq!(parse_rfc3339_utc_secs("2026-10-13T17:55:33Z").map(|s| s > 0), Some(true));
}

// --- Provider failure surfacing --------------------------------------------
//
// Regression: a provider whose stored session was rejected returned `None`, so the
// panel showed a completely blank provider with nothing telling the user to sign in.

#[test]
fn test_provider_failure_message_detects_opencode_auth_error() {
    let body = r#"{"type":"error","error":{"type":"AuthError","message":"Unauthorized"}}"#;
    assert_eq!(
        provider_failure_message(body).as_deref(),
        Some("Session expired — sign in again"),
        "OpenCode answers 401 with an error envelope, not a quota payload"
    );
}

#[test]
fn test_provider_failure_message_detects_minimax_cookie_error() {
    let body = r#"{"base_resp":{"status_code":1004,"status_msg":"cookie is missing, log in again"}}"#;
    assert_eq!(
        provider_failure_message(body).as_deref(),
        Some("Session expired — sign in again"),
        "MiniMax answers 200 with a base_resp error, which must not read as a healthy payload"
    );
}

#[test]
fn test_minimax_error_envelope_parses_to_empty_quota() {
    let body = r#"{"base_resp":{"status_code":1004,"status_msg":"cookie is missing, log in again"}}"#;
    let parsed = parse_minimax_usage(body);
    assert!(
        parsed.map(|q| q.windows.is_empty()).unwrap_or(true),
        "the lenient coding-plan parser yields no windows for an error envelope, \
         which is exactly why the failure envelope must be inspected first"
    );
    assert!(provider_failure_message(body).is_some());
}

#[test]
fn test_provider_failure_message_ignores_healthy_bodies() {
    for healthy in [
        "",
        "not json",
        r#"{"groups":[{"buckets":[]}]}"#,
        r#"{"base_resp":{"status_code":0}}"#,
        r#"{"error":{}}"#,
    ] {
        assert_eq!(
            provider_failure_message(healthy),
            None,
            "{healthy:?} must not be reported as a failure"
        );
    }
}

#[test]
fn test_provider_failure_message_reports_non_auth_errors_verbatim() {
    let body = r#"{"base_resp":{"status_code":2062,"status_msg":"plan not found"}}"#;
    assert_eq!(
        provider_failure_message(body).as_deref(),
        Some("Provider error: plan not found"),
        "non-auth failures must keep the provider's own wording"
    );
}

#[test]
fn test_parse_rfc3339_utc_secs_rejects_malformed_input() {
    for bad in ["", "not-a-date", "2026-10-20", "2026-10-20T18:00:00", "2026-13-20T18:00:00Z", "2026-10-20T25:00:00Z"] {
        assert_eq!(parse_rfc3339_utc_secs(bad), None, "{bad:?} must be rejected");
    }
}



