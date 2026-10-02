//! TDD: change-gated watch signatures — the perf contract.
//!
//! The UI must repaint on human-visible change, not on byte ticks: progress
//! quanta (0.5%), speed buckets, status flips, gid set changes. These tests
//! pin that contract.

use astral_plasma::application::download_service::{
    snapshot_sig, speed_bucket, DownloadsSnapshot, PROGRESS_QUANTUM,
};
use astral_plasma::domain::downloads::{DownloadStatus, DownloadTask, DownloadsTotal};

fn task(gid: &str, done: u64, total: u64, speed: u64) -> DownloadTask {
    DownloadTask {
        gid: gid.into(),
        name: gid.into(),
        status: DownloadStatus::Active,
        total_length: total,
        completed_length: done,
        download_speed: speed,
        dir: String::new(),
        error_code: None,
        completed_at: None,
    }
}

fn snap_with(tasks: Vec<DownloadTask>, speed: u64) -> DownloadsSnapshot {
    let total = DownloadsTotal {
        completed_length: tasks.iter().map(|t| t.completed_length).sum(),
        total_length: tasks.iter().map(|t| t.total_length).sum(),
        download_speed: speed,
        progress: 0.5,
        active_count: tasks.len(),
        indeterminate: false,
    };
    DownloadsSnapshot {
        active: tasks,
        waiting: vec![],
        stopped: vec![],
        total,
        aria_available: true,
        aria_install_command: None,
        aria_version: None,
        aria_installable: false,
    }
}

#[test]
fn test_quantum_is_half_percent() {
    assert!((PROGRESS_QUANTUM - 0.005).abs() < 1e-12);
}

#[test]
fn test_sub_quantum_byte_ticks_do_not_change_sig() {
    // 10000-byte file: +10 bytes stays in the same 0.5% bucket.
    let a = snap_with(vec![task("g", 5000, 10000, 100)], 100);
    let b = snap_with(vec![task("g", 5010, 10000, 100)], 100);
    assert_eq!(snapshot_sig(&a), snapshot_sig(&b));
}

#[test]
fn test_quantum_crossing_changes_sig() {
    let a = snap_with(vec![task("g", 5000, 10000, 100)], 100);
    let b = snap_with(vec![task("g", 5200, 10000, 100)], 100);
    assert_ne!(snapshot_sig(&a), snapshot_sig(&b));
}

#[test]
fn test_status_flip_changes_sig() {
    let mut tasks = vec![task("g", 5000, 10000, 100)];
    let a = snap_with(tasks.clone(), 100);
    tasks[0].status = DownloadStatus::Paused;
    let paused_snap = DownloadsSnapshot {
        active: vec![],
        waiting: tasks,
        stopped: vec![],
        total: DownloadsTotal::default(),
        aria_available: true,
        aria_install_command: None,
        aria_version: None,
        aria_installable: false,
    };
    assert_ne!(snapshot_sig(&a), snapshot_sig(&paused_snap));
}

#[test]
fn test_new_and_removed_gid_change_sig() {
    let a = snap_with(vec![task("g1", 5, 10, 1)], 1);
    let b = snap_with(vec![task("g1", 5, 10, 1), task("g2", 0, 10, 0)], 1);
    assert_ne!(snapshot_sig(&a), snapshot_sig(&b));
}

#[test]
fn test_small_speed_changes_are_exact_stall_visible() {
    assert_ne!(speed_bucket(0), speed_bucket(1024));
    assert_eq!(snapshot_sig(&snap_with(vec![task("g", 5, 10, 0)], 0)),
               snapshot_sig(&snap_with(vec![task("g", 5, 10, 1024)], 0)));
}

#[test]
fn test_large_speed_jitter_is_bucketed() {
    // 1 MiB/s vs 1 MiB/s + 1 KiB: same bucket, no repaint.
    assert_eq!(speed_bucket(1_048_576), speed_bucket(1_049_600));
    // 1 MiB/s vs 2 MiB/s: different bucket.
    assert_ne!(speed_bucket(1_048_576), speed_bucket(2_097_152));
}

#[test]
fn engine_state_changes_the_snapshot_signature() {
    // The stream is change-only: state that is not part of the signature never
    // reaches the UI. Engine availability decides whether the Downloads tab
    // exists, so installing aria2 while the shell runs (or losing it) has to
    // re-emit - otherwise the tab stays hidden until some unrelated download
    // changes, and the settings page keeps saying "not installed".
    let mut absent = snap_with(vec![], 0);
    let mut present = snap_with(vec![], 0);
    absent.aria_available = false;
    present.aria_available = true;
    assert_ne!(
        snapshot_sig(&absent),
        snapshot_sig(&present),
        "engine availability must be part of the signature"
    );

    let mut old = snap_with(vec![], 0);
    old.aria_version = Some("1.36.0".to_string());
    let mut new = snap_with(vec![], 0);
    new.aria_version = Some("1.37.0".to_string());
    assert_ne!(
        snapshot_sig(&old),
        snapshot_sig(&new),
        "a version change is a change"
    );

    let mut installable = snap_with(vec![], 0);
    installable.aria_installable = true;
    let mut guided = snap_with(vec![], 0);
    guided.aria_installable = false;
    assert_ne!(
        snapshot_sig(&installable),
        snapshot_sig(&guided),
        "the native install path appearing or going away is a change"
    );
}

#[test]
fn the_engine_is_started_the_moment_it_appears() {
    use astral_plasma::application::download_service::should_start_engine;

    // First observation: the watch loop starts the engine itself, so this is not
    // a transition.
    assert!(!should_start_engine(None, true));
    assert!(!should_start_engine(None, false));

    // Still missing, still missing with the engine: nothing to do.
    assert!(!should_start_engine(Some(false), false));
    assert!(!should_start_engine(Some(true), true));

    // Installed while the shell was running (the settings page's install flow, or
    // a package manager): the engine has to be started, or the tab is present and
    // its list can never fill.
    assert!(should_start_engine(Some(false), true), "the engine appearing must start it");

    // The other direction needs no action: a vanished engine is reported, and a
    // failed start is not retried on every tick (the next `add`/`ensure` tries).
    assert!(!should_start_engine(Some(true), false));
}
