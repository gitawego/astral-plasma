//! TDD: downloads application service — snapshot grouping, add fan-out, verbs.
//!
//! Uses a fake [`DownloadsPort`]: no aria2c, no sockets. Verifies the D2/D3/D5
//! contract: normalised snapshot grouping, one task per URL line, pause/resume/
//! cancel/delete-partial/remove/retry verb mapping, defaults filled from settings.

use astral_plasma::application::download_service::{DownloadsPort, DownloadsSnapshot, DownloadsUseCase};
use astral_plasma::domain::downloads::{DownloadStatus, DownloadTask, EngineSettings, NewDownloadOptions};
use astral_plasma::domain::ports::DynResult;
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct FakePort {
    raw: Mutex<Vec<serde_json::Value>>,
    calls: Mutex<Vec<(String, String)>>,
    added: Mutex<Vec<(String, NewDownloadOptions)>>,
    retry_gid: Mutex<Option<String>>,
    /// `true` simulates a machine without aria2c: every RPC path must stay
    /// untouched and the user must be told what to install.
    engine_missing: bool,
    install_command: Option<String>,
    spawn_calls: Mutex<Vec<String>>,
    fetch_calls: Mutex<usize>,
    history: Mutex<astral_plasma::domain::downloads::DownloadHistory>,
    /// Engine probe answers (version + whether the native prompt is available).
    engine_version: Option<String>,
    pkexec_available: bool,
    os_release: Mutex<String>,
    install_exit_code: Mutex<i32>,
    privileged: Mutex<Vec<Vec<String>>>,
    applied: Mutex<Vec<EngineSettings>>,
    spawn_settings: Mutex<Vec<EngineSettings>>,
}

impl FakePort {
    fn with_raw(raw: Vec<serde_json::Value>) -> Self {
        Self { raw: Mutex::new(raw), ..Default::default() }
    }

    /// A machine the download manager cannot start anything on.
    fn without_engine() -> Self {
        Self {
            engine_missing: true,
            install_command: Some("sudo pacman -S aria2".to_string()),
            ..Default::default()
        }
    }

    fn fetch_calls(&self) -> usize {
        *self.fetch_calls.lock().unwrap()
    }

    fn spawn_calls(&self) -> Vec<String> {
        self.spawn_calls.lock().unwrap().clone()
    }

    fn set_os_release(&self, text: &str) {
        *self.os_release.lock().unwrap() = text.to_string();
    }

    fn set_install_exit_code(&self, code: i32) {
        *self.install_exit_code.lock().unwrap() = code;
    }

    fn privileged_calls(&self) -> Vec<Vec<String>> {
        self.privileged.lock().unwrap().clone()
    }

    fn applied_settings(&self) -> Vec<EngineSettings> {
        self.applied.lock().unwrap().clone()
    }

    fn spawn_settings(&self) -> Vec<EngineSettings> {
        self.spawn_settings.lock().unwrap().clone()
    }
}

impl DownloadsPort for FakePort {
    fn ensure_running(&self, settings: &EngineSettings) -> DynResult<bool> {
        self.spawn_calls.lock().unwrap().push(settings.dir.clone());
        self.spawn_settings.lock().unwrap().push(settings.clone());
        Ok(false)
    }
    fn fetch_raw(&self) -> DynResult<Vec<serde_json::Value>> {
        *self.fetch_calls.lock().unwrap() += 1;
        Ok(self.raw.lock().unwrap().clone())
    }
    fn add_uri(&self, url: &str, opts: &NewDownloadOptions) -> DynResult<String> {
        self.added.lock().unwrap().push((url.to_string(), opts.clone()));
        Ok(format!("gid-{}", url.len()))
    }
    fn control(&self, verb: &str, gid: &str) -> DynResult<()> {
        self.calls.lock().unwrap().push((verb.to_string(), gid.to_string()));
        Ok(())
    }
    fn retry(&self, gid: &str, _opts: &NewDownloadOptions) -> DynResult<String> {
        *self.retry_gid.lock().unwrap() = Some(gid.to_string());
        Ok("gid-new".to_string())
    }
    fn purge(&self) -> DynResult<()> {
        self.calls.lock().unwrap().push(("purgeDownloadResult".to_string(), String::new()));
        Ok(())
    }
    fn secret(&self) -> DynResult<String> {
        Ok("s".to_string())
    }
    fn load_history(&self) -> DynResult<astral_plasma::domain::downloads::DownloadHistory> {
        Ok(self.history.lock().unwrap().clone())
    }
    fn is_aria2_installed(&self) -> bool {
        !self.engine_missing
    }
    fn aria2_install_command(&self) -> Option<String> {
        self.install_command.clone()
    }
    fn engine_version(&self) -> Option<String> {
        self.engine_version.clone()
    }
    fn pkexec_available(&self) -> bool {
        self.pkexec_available
    }
    fn os_release(&self) -> String {
        self.os_release.lock().unwrap().clone()
    }
    fn run_privileged_install(&self, argv: &[String]) -> DynResult<i32> {
        self.privileged.lock().unwrap().push(argv.to_vec());
        Ok(*self.install_exit_code.lock().unwrap())
    }
    fn apply_global_options(&self, settings: &EngineSettings) -> DynResult<()> {
        self.applied.lock().unwrap().push(settings.clone());
        Ok(())
    }
}

fn raw_task(gid: &str, status: &str, total: &str, done: &str, speed: &str) -> serde_json::Value {
    serde_json::json!({
        "gid": gid,
        "status": status,
        "totalLength": total,
        "completedLength": done,
        "downloadSpeed": speed,
        "dir": "/dl",
        "files": [{"path": format!("/dl/{}.iso", gid)}]
    })
}

fn use_case(raw: Vec<serde_json::Value>) -> (DownloadsUseCase, Arc<FakePort>) {
    let port = Arc::new(FakePort::with_raw(raw));
    let uc = DownloadsUseCase::with_defaults(port.clone(), "/dl".into(), 4);
    (uc, port)
}

#[test]
fn test_snapshot_groups_and_aggregates() {
    let (uc, _) = use_case(vec![
        raw_task("a1", "active", "100", "40", "10"),
        raw_task("w1", "waiting", "200", "0", "0"),
        raw_task("p1", "paused", "200", "100", "0"),
        raw_task("c1", "complete", "50", "50", "0"),
        raw_task("e1", "error", "50", "10", "0"),
    ]);
    let snap: DownloadsSnapshot = uc.snapshot().expect("snapshot");
    assert_eq!(snap.active.len(), 1);
    assert_eq!(snap.waiting.len(), 2, "waiting + paused share the queued segment");
    assert_eq!(snap.stopped.len(), 2, "complete + error share the stopped segment");
    assert_eq!(snap.total.active_count, 3);
    assert_eq!(snap.total.total_length, 500);
    assert_eq!(snap.total.completed_length, 140);
    assert_eq!(snap.total.download_speed, 10);
}

#[test]
fn test_add_urls_fans_out_one_task_per_line_with_defaults() {
    let (uc, port) = use_case(vec![]);
    let gids = uc
        .add_urls("https://h/a.iso\n\nhttps://h/b.iso\n", NewDownloadOptions::default())
        .expect("add");
    assert_eq!(gids.len(), 2);
    let added = port.added.lock().unwrap();
    assert_eq!(added.len(), 2);
    assert_eq!(added[0].0, "https://h/a.iso");
    // Defaults filled: dir + split from settings (D6/D7).
    assert_eq!(added[0].1.dir.as_deref(), Some("/dl"));
    assert_eq!(added[0].1.split, Some(4));
}

#[test]
fn test_add_urls_rejects_empty_input() {
    let (uc, _) = use_case(vec![]);
    assert!(uc.add_urls("  \n ", NewDownloadOptions::default()).is_err());
}

#[test]
fn test_add_urls_respects_per_add_override() {
    let (uc, port) = use_case(vec![]);
    uc.add_urls(
        "https://h/a.iso",
        NewDownloadOptions { dir: Some("/tmp/x".into()), split: Some(9), ..Default::default() },
    )
    .expect("add");
    let added = port.added.lock().unwrap();
    assert_eq!(added[0].1.dir.as_deref(), Some("/tmp/x"));
    assert_eq!(added[0].1.split, Some(9));
}

#[test]
fn test_verbs_map_to_aria2_methods() {
    let (uc, port) = use_case(vec![]);
    uc.pause("g1").unwrap();
    uc.resume("g1").unwrap();
    uc.cancel("g1", false).unwrap();
    uc.cancel("g2", true).unwrap();
    uc.remove_result("g3").unwrap();
    uc.purge_results().unwrap();
    let calls = port.calls.lock().unwrap().clone();
    assert!(calls.contains(&("pause".into(), "g1".into())));
    assert!(calls.contains(&("unpause".into(), "g1".into())));
    assert!(calls.contains(&("remove".into(), "g1".into())), "cancel keeps partial (D5)");
    assert!(calls.contains(&("forceRemove".into(), "g2".into())), "cancel-delete drops partial (D5)");
    assert!(calls.contains(&("removeDownloadResult".into(), "g3".into())));
    assert!(calls.iter().any(|(v, _)| v == "purgeDownloadResult"));
}

#[test]
fn test_retry_returns_new_gid() {
    let (uc, port) = use_case(vec![]);
    let gid = uc.retry("old").expect("retry");
    assert_eq!(gid, "gid-new");
    assert_eq!(*port.retry_gid.lock().unwrap(), Some("old".to_string()));
}

#[test]
fn test_build_snapshot_skips_unparseable_rows() {
    let raw = vec![
        serde_json::json!({"status": "active"}),
        raw_task("ok", "active", "10", "5", "1"),
    ];
    let snap = DownloadsUseCase::build_snapshot(raw);
    assert_eq!(snap.active.len(), 1);
    assert_eq!(snap.active[0].gid, "ok");
}

#[test]
fn test_task_progress_and_remaining_helpers() {
    let t = DownloadTask {
        gid: "g".into(),
        name: "n".into(),
        status: DownloadStatus::Active,
        total_length: 100,
        completed_length: 150,
        download_speed: 0,
        dir: String::new(),
        error_code: None,
        completed_at: None,
    };
    assert!((t.progress() - 1.0).abs() < 1e-9, "clamped at 1.0");
    assert_eq!(t.remaining(), 0);
}

#[test]
fn test_reconcile_history_persists_stopped_and_purges() {
    use astral_plasma::domain::downloads::DownloadHistory;

    #[derive(Default)]
    struct MockHistoryPort {
        history: Mutex<DownloadHistory>,
        raw: Mutex<Vec<serde_json::Value>>,
    }

    impl DownloadsPort for MockHistoryPort {
        fn ensure_running(&self, _settings: &EngineSettings) -> DynResult<bool> { Ok(false) }
        fn fetch_raw(&self) -> DynResult<Vec<serde_json::Value>> {
            Ok(self.raw.lock().unwrap().clone())
        }
        fn add_uri(&self, _url: &str, _opts: &NewDownloadOptions) -> DynResult<String> { Ok("g".into()) }
        fn control(&self, _verb: &str, _gid: &str) -> DynResult<()> { Ok(()) }
        fn retry(&self, _gid: &str, _opts: &NewDownloadOptions) -> DynResult<String> { Ok("g".into()) }
        fn purge(&self) -> DynResult<()> { Ok(()) }
        fn secret(&self) -> DynResult<String> { Ok("s".into()) }
        fn load_history(&self) -> DynResult<DownloadHistory> {
            Ok(self.history.lock().unwrap().clone())
        }
        fn save_history(&self, hist: &DownloadHistory) -> DynResult<()> {
            *self.history.lock().unwrap() = hist.clone();
            Ok(())
        }
        fn scan_directory(&self, _dir: &str) -> DynResult<Vec<DownloadTask>> {
            Ok(vec![])
        }
    }

    let port = Arc::new(MockHistoryPort::default());
    // Aria2 reports completed download
    *port.raw.lock().unwrap() = vec![serde_json::json!({
        "gid": "aria-1",
        "status": "complete",
        "totalLength": "1000000",
        "completedLength": "1000000",
        "downloadSpeed": "0",
        "dir": "/home/user/Downloads",
        "files": [{"path": "/home/user/Downloads/omarchy-4.0.4.iso"}]
    })];

    let uc = DownloadsUseCase::with_defaults(port.clone(), "/home/user/Downloads".into(), 4);
    let snap = uc.snapshot().expect("snapshot");

    assert_eq!(snap.stopped.len(), 1, "Completed aria2 task appears in stopped tasks");
    assert_eq!(snap.stopped[0].name, "omarchy-4.0.4.iso");
    assert_eq!(snap.stopped[0].status, DownloadStatus::Complete);

    // Verify it was persisted to history
    let saved = port.history.lock().unwrap().clone();
    assert_eq!(saved.items.len(), 1);
    assert_eq!(saved.items[0].name, "omarchy-4.0.4.iso");

    // Aria2 restarts, so raw is now empty, but history restores the finished download
    *port.raw.lock().unwrap() = vec![];
    let snap2 = uc.snapshot().expect("snapshot after aria2 restart");
    assert_eq!(snap2.stopped.len(), 1, "Persistent history restores the finished download");
    assert_eq!(snap2.stopped[0].name, "omarchy-4.0.4.iso");

    // Dismiss via remove_result
    uc.remove_result("aria-1").expect("remove");
    let after_remove = uc.snapshot().expect("snapshot after remove");
    assert_eq!(after_remove.stopped.len(), 0, "Dismissed task is no longer in stopped tasks");

    // Re-add to history and test purge
    *port.raw.lock().unwrap() = vec![serde_json::json!({
        "gid": "aria-2",
        "status": "complete",
        "totalLength": "2000000",
        "completedLength": "2000000",
        "downloadSpeed": "0",
        "dir": "/home/user/Downloads",
        "files": [{"path": "/home/user/Downloads/file2.zip"}]
    })];
    let _ = uc.snapshot();
    assert_eq!(port.history.lock().unwrap().items.len(), 1);
    uc.purge_results().expect("purge");
    assert_eq!(port.history.lock().unwrap().items.len(), 0, "purge clears history completely");
}


// ============================================================================
// No engine installed
// ============================================================================
// aria2c is an optional dependency. A machine that does not have it must never
// see a raw socket error: the snapshot has to say the engine is missing, name
// the install command, and keep working in history-only mode, and starting a
// download has to explain what is missing instead of reporting that a
// connection to port 6800 was refused.

fn engine_less_use_case() -> (DownloadsUseCase, Arc<FakePort>) {
    let port = Arc::new(FakePort::without_engine());
    let uc = DownloadsUseCase::with_defaults(port.clone(), "/dl".into(), 4);
    (uc, port)
}

#[test]
fn test_snapshot_without_the_engine_is_history_only_and_names_the_install() {
    let (uc, port) = engine_less_use_case();
    // A finished download from an earlier, engine-equipped session.
    {
        let mut history = port.history.lock().unwrap();
        history.add_or_update(DownloadTask {
            gid: "done-1".into(),
            name: "old.iso".into(),
            status: DownloadStatus::Complete,
            total_length: 100,
            completed_length: 100,
            download_speed: 0,
            dir: "/dl".into(),
            error_code: None,
            completed_at: Some(1700000000),
        });
    }

    let snap = uc.snapshot().expect("a missing engine is not an error");

    assert!(!snap.aria_available, "the shell must learn the engine is missing");
    assert_eq!(
        snap.aria_install_command.as_deref(),
        Some("sudo pacman -S aria2"),
        "the install command is what the banner and the button copy"
    );
    assert_eq!(port.fetch_calls(), 0, "a missing engine must not be talked to");
    assert!(snap.active.is_empty() && snap.waiting.is_empty());
    assert_eq!(
        snap.stopped.iter().filter(|t| t.gid == "done-1").count(),
        1,
        "finished downloads stay visible while the engine is missing"
    );
}

#[test]
fn test_ensure_running_without_the_engine_never_tries_to_spawn_it() {
    let (uc, port) = engine_less_use_case();

    assert_eq!(uc.ensure_running().expect("checked, not failed"), false);
    assert!(
        port.spawn_calls().is_empty(),
        "spawning a binary that does not exist would log a spawn error on every poll"
    );
}

#[test]
fn test_adding_a_url_without_the_engine_says_what_to_install() {
    let (uc, port) = engine_less_use_case();

    let error = uc
        .add_urls("https://h/a.iso", NewDownloadOptions::default())
        .expect_err("a download cannot start without an engine");
    let message = error.to_string();

    assert!(
        message.contains("aria2c is not installed"),
        "the error must name the missing engine, got: {message}"
    );
    assert!(
        message.contains("sudo pacman -S aria2"),
        "the error must carry the install command, got: {message}"
    );
    assert!(
        port.added.lock().unwrap().is_empty(),
        "nothing may be sent to an engine that is not there"
    );
}

// ============================================================================
// Engine status and the native install flow
// ============================================================================
// The settings page shows what the engine is, offers to install it with the
// desktop's own authentication dialog, and falls back to the manual command
// whenever that dialog is unavailable or dismissed.

impl FakePort {
    fn with_engine_status(installed: bool, version: Option<&str>, pkexec: bool) -> Self {
        Self {
            engine_missing: !installed,
            install_command: Some("sudo pacman -S aria2".to_string()),
            pkexec_available: pkexec,
            engine_version: version.map(str::to_string),
            ..Default::default()
        }
    }
}

#[test]
fn test_engine_status_reports_version_and_whether_installing_is_possible() {
    let port = Arc::new(FakePort::with_engine_status(true, Some("1.37.0"), true));
    let uc = DownloadsUseCase::with_defaults(port.clone(), "/dl".into(), 4);

    let status = uc.engine_status().expect("status");
    assert!(status.installed);
    assert_eq!(status.version.as_deref(), Some("1.37.0"));
    assert_eq!(status.install_command, "sudo pacman -S aria2");
    assert!(status.installable, "polkit is the native install path");

    // The snapshot carries the same facts, so the tab needs no second call.
    let snap = uc.snapshot().expect("snapshot");
    assert_eq!(snap.aria_version.as_deref(), Some("1.37.0"));
    assert!(snap.aria_installable);

    let absent = Arc::new(FakePort::with_engine_status(false, None, false));
    let absent_uc = DownloadsUseCase::with_defaults(absent, "/dl".into(), 4);
    let absent_status = absent_uc.engine_status().expect("status");
    assert!(!absent_status.installed && absent_status.version.is_none());
    assert!(!absent_status.installable, "no polkit = guide instead of prompt");
    let snap = absent_uc.snapshot().expect("snapshot");
    assert!(!snap.aria_available && !snap.aria_installable);
}

#[test]
fn test_install_engine_runs_the_distribution_install_through_polkit() {
    let port = Arc::new(FakePort::with_engine_status(false, None, true));
    port.set_os_release("ID=cachyos\nID_LIKE=arch\n");
    port.set_install_exit_code(0);
    let uc = DownloadsUseCase::with_defaults(port.clone(), "/dl".into(), 4);

    let report = uc.install_engine().expect("install runs");

    assert_eq!(report.outcome, "installed");
    assert!(report.installed);
    assert_eq!(
        port.privileged_calls(),
        vec![vec!["pacman".to_string(), "-S".to_string(), "--noconfirm".to_string(), "aria2".to_string()]],
        "searched in the fake os-release, package manager and flags included"
    );
    assert!(!report.message.is_empty());
}

#[test]
fn test_install_engine_without_polkit_guides_instead_of_prompting() {
    let port = Arc::new(FakePort::with_engine_status(false, None, false));
    port.set_os_release("ID=arch\n");
    let uc = DownloadsUseCase::with_defaults(port.clone(), "/dl".into(), 4);

    let report = uc.install_engine().expect("install reports, never fails hard");

    assert_eq!(report.outcome, "no_agent");
    assert!(
        report.message.contains("sudo pacman -S aria2"),
        "the manual command has to be in the message: {}",
        report.message
    );
    assert!(port.privileged_calls().is_empty(), "nothing may be spawned without a prompt");
}

#[test]
fn test_install_engine_maps_a_dismissed_prompt_to_guidance() {
    let port = Arc::new(FakePort::with_engine_status(false, None, true));
    port.set_os_release("ID=debian\n");
    port.set_install_exit_code(126);
    let uc = DownloadsUseCase::with_defaults(port.clone(), "/dl".into(), 4);

    let report = uc.install_engine().expect("install reports");

    assert_eq!(report.outcome, "dismissed");
    assert!(report.message.contains("sudo apt install aria2"), "{}", report.message);
}

#[test]
fn test_install_engine_on_an_unknown_distribution_points_at_upstream() {
    let port = Arc::new(FakePort::with_engine_status(false, None, true));
    port.set_os_release("ID=some-new-distro\n");
    let uc = DownloadsUseCase::with_defaults(port.clone(), "/dl".into(), 4);

    let report = uc.install_engine().expect("install reports");

    assert!(report.message.contains("aria2.github.io"), "{}", report.message);
    assert!(port.privileged_calls().is_empty(), "no invented package manager");
}

#[test]
fn test_engine_settings_reach_the_running_engine_and_are_clamped() {
    use astral_plasma::domain::downloads::EngineSettings;

    let port = Arc::new(FakePort::with_engine_status(true, Some("1.37.0"), true));
    let uc = DownloadsUseCase::with_defaults(port.clone(), "/dl".into(), 4);

    uc.apply_engine_settings(&EngineSettings::clamped(99, 42, "/dl"))
        .expect("applied");
    let applied = port.applied_settings();
    assert_eq!(applied.len(), 1);
    assert_eq!(applied[0].max_concurrent_downloads, 16, "clamped on the way out");
    assert_eq!(applied[0].speed_limit_kbps, 42);

    // A missing engine is not an error: there is nothing to reconfigure, and the
    // settings are picked up at the next spawn.
    let absent = Arc::new(FakePort::with_engine_status(false, None, true));
    let absent_uc = DownloadsUseCase::with_defaults(absent.clone(), "/dl".into(), 4);
    let report = absent_uc.apply_engine_settings(&EngineSettings::default()).expect("no-op");
    assert!(!report.applied);
    assert!(report.reason.is_some());
    assert!(absent.applied_settings().is_empty());
}

#[test]
fn test_ensure_running_passes_the_configured_engine_settings() {
    use astral_plasma::domain::downloads::EngineSettings;

    let port = Arc::new(FakePort::with_engine_status(true, Some("1.37.0"), true));
    let uc = DownloadsUseCase::with_engine(
        port.clone(),
        "/dl".into(),
        4,
        EngineSettings::clamped(7, 900, "/dl"),
    );

    uc.ensure_running().expect("ensure");
    assert_eq!(port.spawn_settings().len(), 1);
    assert_eq!(port.spawn_settings()[0].max_concurrent_downloads, 7);
    assert_eq!(port.spawn_settings()[0].speed_limit_kbps, 900);
}
