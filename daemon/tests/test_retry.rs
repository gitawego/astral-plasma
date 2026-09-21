//! Session bus names are singletons and are requested without queueing, so a
//! shell reload can lose a name to the outgoing daemon. These tests pin the
//! retry policy that makes that race harmless.

use astral_plasma::application::retry::retry_async;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Duration;

#[tokio::test]
async fn succeeds_after_transient_failures() {
    let attempts = AtomicU32::new(0);
    let result: Result<&str, String> = retry_async(5, Duration::from_millis(1), || {
        let this_attempt = attempts.fetch_add(1, Ordering::SeqCst) + 1;
        async move {
            if this_attempt < 3 {
                Err(format!("attempt {this_attempt} failed"))
            } else {
                Ok("acquired")
            }
        }
    })
    .await;

    assert_eq!(result.unwrap(), "acquired");
    assert_eq!(attempts.load(Ordering::SeqCst), 3, "stops retrying once it succeeds");
}

#[tokio::test]
async fn reports_the_last_error_after_exhausting_the_attempts() {
    let attempts = AtomicU32::new(0);
    let result: Result<(), String> = retry_async(3, Duration::from_millis(1), || {
        let this_attempt = attempts.fetch_add(1, Ordering::SeqCst) + 1;
        async move { Err(format!("failure {this_attempt}")) }
    })
    .await;

    assert_eq!(result.unwrap_err(), "failure 3", "the last error is reported");
    assert_eq!(attempts.load(Ordering::SeqCst), 3, "attempts are bounded");
}
