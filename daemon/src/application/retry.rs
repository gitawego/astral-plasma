//! Bounded retry for operations that can lose a race.
//!
//! Both the watcher daemon and its Wine MPRIS bridge own session bus names,
//! which are singletons requested without queueing. During a shell reload the
//! incoming daemon starts before the outgoing one has necessarily released its
//! name, and failing once would cost the whole session its window events (or
//! its Wine player). Retrying for a bounded window turns that race into a short
//! start-up delay.

use std::future::Future;
use std::time::Duration;

/// Run `operation` until it succeeds, up to `attempts` times, sleeping `delay`
/// between attempts. The last error is returned when the attempts run out.
pub async fn retry_async<T, E, F, Fut>(attempts: u32, delay: Duration, mut operation: F) -> Result<T, E>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, E>>,
{
    let attempts = attempts.max(1);
    let mut last_error = None;
    for attempt in 1..=attempts {
        match operation().await {
            Ok(value) => return Ok(value),
            Err(error) => {
                last_error = Some(error);
                if attempt < attempts {
                    tokio::time::sleep(delay).await;
                }
            }
        }
    }
    // `attempts` is at least one, so an error was recorded.
    Err(last_error.expect("at least one attempt runs"))
}

/// Retry until it succeeds, at a fixed cadence.
///
/// Used for session singletons that must eventually exist: a shell restart can
/// make the previous owner hold the name for longer than any fixed budget, and
/// giving up permanently would cost the session that service.
pub async fn retry_forever<T, F, Fut>(delay: std::time::Duration, mut operation: F) -> T
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = crate::domain::ports::DynResult<T>>,
{
    let mut attempt: u64 = 0;
    loop {
        match operation().await {
            Ok(value) => return value,
            Err(error) => {
                attempt += 1;
                if attempt % 15 == 1 {
                    eprintln!("[retry] still failing after {attempt} attempts: {error}");
                }
                tokio::time::sleep(delay).await;
            }
        }
    }
}
