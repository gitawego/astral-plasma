//! The runtime must never be parked by port work.
//!
//! The daemon's desktop ports shell out (`qdbus6`, `busctl`, `bash`, `sqlite3`)
//! and several of them take hundreds of milliseconds. A tokio worker parked in
//! such a call stops polling the runtime's I/O and timer drivers; when that
//! happens no D-Bus reply, `sleep` or `interval` in the process makes progress
//! again - the daemon stays alive, owns its bus name and answers nothing, so
//! every shortcut silently does nothing and the panels are never handed back.
//! This was measured on the live session: the wedged process had 4461 unread
//! bytes on its bus socket and its worker was parked inside `poll()` in
//! `AgentSessionAdapter::query_external_store`, while every other worker sat in
//! `park_condvar` and the heartbeat timer had stopped firing.
//!
//! These tests pin the two shapes that prevent it: blocking work goes through
//! `blocking` (the blocking pool) and the hand-over wait yields instead of
//! sleeping.

use astral_plasma::application::plasma_service::wait_for_restore_to_finish_async;
use astral_plasma::application::watch_events::blocking;
use astral_plasma::infrastructure::ai_adapters::AdapterRegistry;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("astral-nonblocking-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");
    dir
}

/// Spawns a timer that ticks every 5 ms and returns the tick counter.
///
/// On a single-threaded runtime this timer only runs while the runtime thread is
/// free: if the work under test parks that thread, the counter stops.
fn spawn_ticker(ticks: Arc<AtomicUsize>) {
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_millis(5)).await;
            ticks.fetch_add(1, Ordering::SeqCst);
        }
    });
}

#[tokio::test(flavor = "current_thread")]
async fn blocking_work_leaves_the_runtime_able_to_run_timers() {
    let ticks = Arc::new(AtomicUsize::new(0));
    spawn_ticker(Arc::clone(&ticks));
    // Let the ticker register its first timer.
    tokio::time::sleep(Duration::from_millis(20)).await;

    // Stand-in for a port call: a slow child-process wait.
    let started = Instant::now();
    let value = blocking(|| {
        std::thread::sleep(Duration::from_millis(150));
        7u32
    })
    .await;
    let elapsed = started.elapsed();

    assert_eq!(value, 7, "blocking work must return its value");
    assert!(elapsed >= Duration::from_millis(140), "work must actually run");
    let observed = ticks.load(Ordering::SeqCst);
    assert!(
        observed >= 10,
        "the runtime timer must keep firing while the port call runs, saw {observed} ticks"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn handover_wait_yields_instead_of_parking_the_thread() {
    let dir = temp_dir("handover");
    fs::write(dir.join(".restoring"), b"held").expect("lock file");

    let ticks = Arc::new(AtomicUsize::new(0));
    spawn_ticker(Arc::clone(&ticks));
    tokio::time::sleep(Duration::from_millis(20)).await;

    // The lock never clears: the wait must time out, and the runtime must have
    // kept running the ticker while it waited.
    let started = Instant::now();
    wait_for_restore_to_finish_async(&dir, Duration::from_millis(200)).await;
    let elapsed = started.elapsed();

    assert!(elapsed >= Duration::from_millis(190), "wait must run its timeout");
    let observed = ticks.load(Ordering::SeqCst);
    assert!(
        observed >= 10,
        "the wait must yield to the runtime, saw {observed} ticks"
    );

    // A cleared lock returns immediately.
    fs::remove_file(dir.join(".restoring")).expect("remove lock");
    let started = Instant::now();
    wait_for_restore_to_finish_async(&dir, Duration::from_secs(5)).await;
    assert!(
        started.elapsed() < Duration::from_millis(100),
        "an unlocked hand-over must not wait"
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn external_store_lookup_is_scoped_to_the_owning_adapter() {
    let registry = AdapterRegistry::new();
    let home = Path::new("/tmp");

    // No adapter claims an arbitrary path, so nothing is queried and no process
    // is spawned for it.
    assert!(registry
        .query_external_store_for_path(Path::new("/tmp/not-an-agent-session.txt"), home)
        .is_none());
}
