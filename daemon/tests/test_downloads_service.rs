//! TDD: downloads application service — snapshot grouping, add fan-out, verbs.
//!
//! Uses a fake [`DownloadsPort`]: no aria2c, no sockets. Verifies the D2/D3/D5
//! contract: normalised snapshot grouping, one task per URL line, pause/resume/
//! cancel/delete-partial/remove/retry verb mapping, defaults filled from settings.

use astral_plasma::application::download_service::{DownloadsPort, DownloadsSnapshot, DownloadsUseCase};
use astral_plasma::domain::downloads::{DownloadStatus, DownloadTask, NewDownloadOptions};
use astral_plasma::domain::ports::DynResult;
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct FakePort {
    raw: Mutex<Vec<serde_json::Value>>,
    calls: Mutex<Vec<(String, String)>>,
    added: Mutex<Vec<(String, NewDownloadOptions)>>,
    retry_gid: Mutex<Option<String>>,
}

impl FakePort {
    fn with_raw(raw: Vec<serde_json::Value>) -> Self {
        Self { raw: Mutex::new(raw), ..Default::default() }
    }
}

impl DownloadsPort for FakePort {
    fn ensure_running(&self, _default_dir: &str) -> DynResult<bool> {
        Ok(false)
    }
    fn fetch_raw(&self) -> DynResult<Vec<serde_json::Value>> {
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
    };
    assert!((t.progress() - 1.0).abs() < 1e-9, "clamped at 1.0");
    assert_eq!(t.remaining(), 0);
}
