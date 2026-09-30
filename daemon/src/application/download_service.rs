//! Application use cases for the download manager.
//!
//! DDD: pure domain types in, infrastructure port calls out. The use case
//! owns no threads and no timers — QML consumes download events, never polls.

use crate::domain::downloads::{
    aggregate_total, clamp_split, parse_task, parse_urls, DownloadStatus, DownloadTask, DownloadsTotal,
    NewDownloadOptions, DEFAULT_SPLIT,
};
use crate::domain::ports::DynResult;
use crate::infrastructure::aria2_adapter;
use std::sync::Arc;

fn default_download_dir() -> String {
    let home = crate::domain::branding::home_dir();
    home.join("Downloads").to_string_lossy().to_string()
}

/// Snapshot the shell renders: rows grouped by segment + the aggregate total.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct DownloadsSnapshot {
    pub active: Vec<DownloadTask>,
    pub waiting: Vec<DownloadTask>,
    pub stopped: Vec<DownloadTask>,
    pub total: DownloadsTotal,
}

/// Thin port over the aria2 adapter so tests can fake RPC without aria2c.
pub trait DownloadsPort: Send + Sync {
    fn ensure_running(&self, default_dir: &str) -> DynResult<bool>;
    fn fetch_raw(&self) -> DynResult<Vec<serde_json::Value>>;
    fn add_uri(&self, url: &str, opts: &NewDownloadOptions) -> DynResult<String>;
    fn control(&self, verb: &str, gid: &str) -> DynResult<()>;
    fn retry(&self, gid: &str, opts: &NewDownloadOptions) -> DynResult<String>;
    fn purge(&self) -> DynResult<()>;
    fn secret(&self) -> DynResult<String>;
}

pub struct Aria2DownloadsPort;

impl DownloadsPort for Aria2DownloadsPort {
    fn ensure_running(&self, default_dir: &str) -> DynResult<bool> {
        aria2_adapter::ensure_running(default_dir)
    }
    fn fetch_raw(&self) -> DynResult<Vec<serde_json::Value>> {
        let secret = aria2_adapter::load_or_create_secret()?;
        aria2_adapter::fetch_all(&secret)
    }
    fn add_uri(&self, url: &str, opts: &NewDownloadOptions) -> DynResult<String> {
        let secret = aria2_adapter::load_or_create_secret()?;
        aria2_adapter::add_uri(&secret, url, opts, None)
    }
    fn control(&self, verb: &str, gid: &str) -> DynResult<()> {
        let secret = aria2_adapter::load_or_create_secret()?;
        aria2_adapter::control(&secret, verb, gid)?;
        Ok(())
    }
    fn retry(&self, gid: &str, opts: &NewDownloadOptions) -> DynResult<String> {
        let secret = aria2_adapter::load_or_create_secret()?;
        aria2_adapter::retry(&secret, gid, opts)
    }
    fn purge(&self) -> DynResult<()> {
        let secret = aria2_adapter::load_or_create_secret()?;
        aria2_adapter::rpc_call(&secret, "purgeDownloadResult", serde_json::json!([]))?;
        Ok(())
    }
    fn secret(&self) -> DynResult<String> {
        aria2_adapter::load_or_create_secret()
    }
}

pub struct DownloadsUseCase {
    port: Arc<dyn DownloadsPort>,
    default_dir: String,
    default_split: u32,
}

impl DownloadsUseCase {
    pub fn new(port: Arc<dyn DownloadsPort>) -> Self {
        Self {
            port,
            default_dir: default_download_dir(),
            default_split: DEFAULT_SPLIT,
        }
    }

    pub fn with_defaults(port: Arc<dyn DownloadsPort>, default_dir: String, default_split: u32) -> Self {
        Self {
            port,
            default_dir,
            default_split: clamp_split(default_split as i64),
        }
    }

    pub fn ensure_running(&self) -> DynResult<bool> {
        self.port.ensure_running(&self.default_dir)
    }

    /// One-shot snapshot: fetch raw RPC tasks, normalise, group, aggregate.
    /// Change events (see `run_downloads_watch`) tell QML *when* to re-run
    /// this; QML holds no polling timer of its own.
    pub fn snapshot(&self) -> DynResult<DownloadsSnapshot> {
        let raw = self.port.fetch_raw()?;
        Ok(Self::build_snapshot(raw))
    }

    pub fn build_snapshot(raw: Vec<serde_json::Value>) -> DownloadsSnapshot {
        let mut snap = DownloadsSnapshot::default();
        let mut counted: Vec<DownloadTask> = Vec::new();
        for v in &raw {
            if let Some(t) = parse_task(v) {
                match t.status {
                    DownloadStatus::Active => snap.active.push(t.clone()),
                    DownloadStatus::Waiting | DownloadStatus::Paused => snap.waiting.push(t.clone()),
                    _ => snap.stopped.push(t.clone()),
                }
                if t.status.counts_in_total() {
                    counted.push(t);
                }
            }
        }
        snap.total = aggregate_total(&counted);
        snap
    }

    /// Adds each non-empty line as its own task (AriaNg multi-URL pattern).
    pub fn add_urls(&self, input: &str, opts: NewDownloadOptions) -> DynResult<Vec<String>> {
        let urls = parse_urls(input);
        if urls.is_empty() {
            return Err("no URLs provided".into());
        }
        let mut gids = Vec::with_capacity(urls.len());
        for u in &urls {
            let mut o = opts.clone();
            if o.split.is_none() {
                o.split = Some(self.default_split);
            }
            if o.dir.is_none() {
                o.dir = Some(self.default_dir.clone());
            }
            gids.push(self.port.add_uri(u, &o)?);
        }
        Ok(gids)
    }

    pub fn pause(&self, gid: &str) -> DynResult<()> {
        self.port.control("pause", gid)
    }

    pub fn resume(&self, gid: &str) -> DynResult<()> {
        self.port.control("unpause", gid)
    }

    /// Cancel: `remove` keeps the partial file, `forceRemove` drops it.
    /// `delete_partial=true` maps to forceRemove.
    pub fn cancel(&self, gid: &str, delete_partial: bool) -> DynResult<()> {
        self.port
            .control(if delete_partial { "forceRemove" } else { "remove" }, gid)
    }

    pub fn remove_result(&self, gid: &str) -> DynResult<()> {
        self.port.control("removeDownloadResult", gid)
    }

    pub fn purge_results(&self) -> DynResult<()> {
        self.port.purge()
    }

    pub fn retry(&self, gid: &str) -> DynResult<String> {
        let opts = NewDownloadOptions {
            dir: Some(self.default_dir.clone()),
            split: Some(self.default_split),
            ..Default::default()
        };
        self.port.retry(gid, &opts)
    }
}

/// Progress quantum: re-emit only when a task's progress crosses a 0.5%
/// bucket. Coarse buckets mean the UI repaints on human-visible change, not
/// on every byte tick.
pub const PROGRESS_QUANTUM: f64 = 0.005;

/// Change signature of one snapshot: gid set, per-gid (status, progress
/// bucket, error), and the aggregate. Pure: unit-tested.
#[derive(Debug, Clone, PartialEq)]
pub struct SnapshotSig {
    pub tasks: Vec<(String, String, u64, bool)>,
    pub total_progress_bucket: u64,
    pub total_speed_bucket: u64,
}

/// Speed bucket: exact bytes below 64 KiB/s (stall detection needs it),
/// 64 KiB steps above (no repaint churn on jitter).
pub fn speed_bucket(speed: u64) -> u64 {
    if speed < 65536 { speed } else { speed / 65536 }
}

pub fn snapshot_sig(snap: &DownloadsSnapshot) -> SnapshotSig {
    let mut tasks: Vec<(String, String, u64, bool)> = Vec::new();
    for t in snap.active.iter().chain(snap.waiting.iter()).chain(snap.stopped.iter()) {
        let status = format!("{:?}", t.status);
        let bucket = (t.progress() / PROGRESS_QUANTUM).floor() as u64;
        tasks.push((t.gid.clone(), status, bucket, t.error_code.is_some()));
    }
    tasks.sort();
    SnapshotSig {
        tasks,
        total_progress_bucket: (snap.total.progress / PROGRESS_QUANTUM).floor() as u64,
        total_speed_bucket: speed_bucket(snap.total.download_speed),
    }
}

/// Emits one JSON line per change on stdout: the full snapshot plus
/// `msg_type`/`type` routing keys (the WindowService event convention).
pub fn emit_snapshot_line(snap: &DownloadsSnapshot) {
    if let Ok(mut v) = serde_json::to_value(snap) {
        if let Some(o) = v.as_object_mut() {
            o.insert("msg_type".into(), serde_json::Value::String("downloads".into()));
            o.insert("type".into(), serde_json::Value::String("downloads".into()));
        }
        if let Ok(line) = serde_json::to_string(&v) {
            println!("{}", line);
            use std::io::Write;
            let _ = std::io::stdout().flush();
        }
    }
}

/// Event loop for `downloads watch`: full snapshot on start, then re-emit
/// only on change. 1s cadence while any counted task exists, 5s idle.
/// Bounded blocking RPC calls run via `watch_events::blocking` so no tokio
/// worker parks (the documented daemon failure mode).
pub async fn run_downloads_watch(use_case: DownloadsUseCase) -> DynResult<()> {
    use crate::application::watch_events::blocking;
    let _ = blocking({
        let dir = use_case.default_dir.clone();
        let port = Arc::clone(&use_case.port);
        move || {
            let uc = DownloadsUseCase::with_defaults(port, dir, DEFAULT_SPLIT);
            let _ = uc.ensure_running();
        }
    })
    .await;
    let mut last: Option<SnapshotSig> = None;
    loop {
        let port = Arc::clone(&use_case.port);
        let dir = use_case.default_dir.clone();
        let split = use_case.default_split;
        let snap: DynResult<DownloadsSnapshot> = blocking(move || {
            let uc = DownloadsUseCase::with_defaults(port, dir, split);
            uc.snapshot()
        })
        .await;
        match snap {
            Ok(s) => {
                let sig = snapshot_sig(&s);
                if last.as_ref() != Some(&sig) {
                    last = Some(sig);
                    emit_snapshot_line(&s);
                }
                let idle = s.total.active_count == 0;
                tokio::time::sleep(if idle {
                    std::time::Duration::from_secs(5)
                } else {
                    std::time::Duration::from_secs(1)
                })
                .await;
            }
            Err(e) => {
                eprintln!("[downloads watch] snapshot failed: {}", e);
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
            }
        }
    }
}
