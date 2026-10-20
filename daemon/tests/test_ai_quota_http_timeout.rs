use astral_plasma::domain::ai_quota::{GEMINI_HTTP_TIMEOUT_SECS, GEMINI_QUOTA_TIMEOUT_SECS};
use astral_plasma::infrastructure::ai_quota_adapter::AiQuotaAdapter;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;
use std::time::{Duration, Instant};

/// Serves `requests` connections, answering each only after `delay`.
fn slow_server(requests: usize, delay: Duration) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
    let addr = listener.local_addr().expect("local addr");
    thread::spawn(move || {
        for _ in 0..requests {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut buf = [0u8; 2048];
                let _ = stream.read(&mut buf);
                thread::sleep(delay);
                let body = "{\"ok\":true}";
                let _ = write!(
                    stream,
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                let _ = stream.flush();
            }
        }
    });
    format!("http://{}/token", addr)
}

// Regression guard: the token refresh used a 5s bound. On this desktop a cold TLS
// handshake to oauth2.googleapis.com reaches 9.6s and a refresh POST has taken 60s,
// so five consecutive refreshes timed out — leaving every stored Gemini account with
// a dead access token and blanking every account row except the active one.
#[test]
fn test_slow_token_endpoint_survives_real_world_latency() {
    let url = slow_server(2, Duration::from_secs(6));
    let form = [("grant_type", "refresh_token")];

    let started = Instant::now();
    let refreshed =
        AiQuotaAdapter::gemini_http_post_form(&url, &form, GEMINI_HTTP_TIMEOUT_SECS);
    let elapsed = started.elapsed();

    assert!(
        refreshed.is_some(),
        "a 6s token round trip must succeed inside the configured budget"
    );
    assert!(
        elapsed >= Duration::from_secs(6),
        "the server must genuinely have taken 6s, else this proves nothing"
    );
    assert!(refreshed.unwrap().contains("ok"));

    let previous_bound = AiQuotaAdapter::gemini_http_post_form(&url, &form, 5);
    assert!(
        previous_bound.is_none(),
        "the old 5s bound must fail a 6s round trip; if this passes the test stopped guarding the bug"
    );
}

/// Accepts `drops` connections that are closed without a response, then answers.
fn flaky_server(drops: usize, delay: Duration) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
    let addr = listener.local_addr().expect("local addr");
    thread::spawn(move || {
        for index in 0..=drops {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut buf = [0u8; 2048];
                let _ = stream.read(&mut buf);
                if index < drops {
                    continue; // drop the connection without answering
                }
                thread::sleep(delay);
                let body = "{\"ok\":true}";
                let _ = write!(
                    stream,
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                let _ = stream.flush();
            }
        }
    });
    format!("http://{}/token", addr)
}

// Regression guard: a single dropped connection used to blank an account for a whole
// poll cycle, because a failed refresh is indistinguishable from a revoked credential.
#[test]
fn test_transient_drop_is_retried() {
    let url = flaky_server(1, Duration::from_millis(50));
    let form = [("grant_type", "refresh_token")];

    let single = AiQuotaAdapter::gemini_http_post_form(&url, &form, 10);
    assert!(single.is_none(), "the first attempt is dropped, so one attempt must fail");

    let url = flaky_server(1, Duration::from_millis(50));
    let retried =
        AiQuotaAdapter::gemini_http_post_form_retrying(&url, &form, 10, 2);
    assert!(
        retried.is_some(),
        "a retry must recover from a single dropped connection"
    );
}

#[test]
fn test_gemini_timeouts_are_not_optimistic() {
    assert!(
        GEMINI_HTTP_TIMEOUT_SECS > 5,
        "the token endpoint budget must exceed the 5s value that failed every refresh"
    );
    assert!(
        GEMINI_QUOTA_TIMEOUT_SECS > 2,
        "quota calls measure 0.6-2.4s when healthy; the bound needs headroom above that"
    );
    assert!(
        GEMINI_HTTP_TIMEOUT_SECS >= GEMINI_QUOTA_TIMEOUT_SECS,
        "the token endpoint is the slower exchange and must not get the tighter budget"
    );
}
