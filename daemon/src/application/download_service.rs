//! Application use cases for the download manager.
//!
//! DDD: pure domain types in, infrastructure port calls out. The use case
//! owns no threads and no timers — QML consumes download events, never polls.

use crate::domain::downloads::{
    aggregate_total, clamp_split, parse_task, parse_urls, DownloadHistory, DownloadStatus,
    DownloadTask, DownloadsTotal, EngineSettings, NewDownloadOptions, DEFAULT_SPLIT,
};
use crate::domain::ports::DynResult;
use crate::infrastructure::aria2_adapter;
use std::sync::Arc;

fn default_download_dir() -> String {
    let home = crate::domain::branding::home_dir();
    home.join("Downloads").to_string_lossy().to_string()
}

fn default_true() -> bool {
    true
}

/// Snapshot the shell renders: rows grouped by segment + the aggregate total.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct DownloadsSnapshot {
    pub active: Vec<DownloadTask>,
    pub waiting: Vec<DownloadTask>,
    pub stopped: Vec<DownloadTask>,
    pub total: DownloadsTotal,
    #[serde(default = "default_true")]
    pub aria_available: bool,
    #[serde(default)]
    pub aria_install_command: Option<String>,
    /// Version of the installed engine, when it answers its own probe.
    #[serde(default)]
    pub aria_version: Option<String>,
    /// Whether the native (polkit) install path is usable here. `false` means
    /// the shell guides with the manual command instead of prompting.
    #[serde(default)]
    pub aria_installable: bool,
}

impl Default for DownloadsSnapshot {
    fn default() -> Self {
        Self {
            active: Vec::new(),
            waiting: Vec::new(),
            stopped: Vec::new(),
            total: DownloadsTotal::default(),
            aria_available: true,
            aria_install_command: None,
            aria_version: None,
            aria_installable: false,
        }
    }
}

/// What the engine is, and how it could be installed.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct EngineStatus {
    pub installed: bool,
    pub version: Option<String>,
    /// The one-liner shown to the user (copy-paste fallback).
    pub install_command: String,
    /// `pkexec` present: the shell can raise the native password dialog.
    pub installable: bool,
}

/// Outcome of one native install attempt.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct EngineInstallReport {
    pub outcome: String,
    pub message: String,
    pub installed: bool,
}

/// Whether a live reconfiguration reached the engine.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct EngineApplyReport {
    pub applied: bool,
    #[serde(default)]
    pub reason: Option<String>,
}

/// Thin port over the aria2 adapter so tests can fake RPC without aria2c.
pub trait DownloadsPort: Send + Sync {
    fn ensure_running(&self, settings: &EngineSettings) -> DynResult<bool>;
    fn fetch_raw(&self) -> DynResult<Vec<serde_json::Value>>;
    fn add_uri(&self, url: &str, opts: &NewDownloadOptions) -> DynResult<String>;
    fn control(&self, verb: &str, gid: &str) -> DynResult<()>;
    fn retry(&self, gid: &str, opts: &NewDownloadOptions) -> DynResult<String>;
    fn purge(&self) -> DynResult<()>;
    fn secret(&self) -> DynResult<String>;
    fn load_history(&self) -> DynResult<DownloadHistory> {
        Ok(DownloadHistory::default())
    }
    fn save_history(&self, _history: &DownloadHistory) -> DynResult<()> {
        Ok(())
    }
    fn scan_directory(&self, _dir: &str) -> DynResult<Vec<DownloadTask>> {
        Ok(Vec::new())
    }
    fn is_aria2_installed(&self) -> bool {
        true
    }
    fn aria2_install_command(&self) -> Option<String> {
        None
    }
    /// The engine's own version string, when it is installed and answers.
    fn engine_version(&self) -> Option<String> {
        None
    }
    /// Whether the native authentication dialog can be raised here.
    fn pkexec_available(&self) -> bool {
        false
    }
    /// Contents of `/etc/os-release`, which decides the package manager.
    fn os_release(&self) -> String {
        std::fs::read_to_string("/etc/os-release").unwrap_or_default()
    }
    /// Run the distribution's install step through the privilege helper; the
    /// return value is the helper's exit code.
    fn run_privileged_install(&self, _argv: &[String]) -> DynResult<i32> {
        Err("no privilege helper available".into())
    }
    /// Reconfigure the running engine in place.
    fn apply_global_options(&self, _settings: &EngineSettings) -> DynResult<()> {
        Ok(())
    }
}

pub struct Aria2DownloadsPort;

impl DownloadsPort for Aria2DownloadsPort {
    fn ensure_running(&self, settings: &EngineSettings) -> DynResult<bool> {
        aria2_adapter::ensure_running(settings)
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
    fn load_history(&self) -> DynResult<DownloadHistory> {
        aria2_adapter::load_history()
    }
    fn save_history(&self, history: &DownloadHistory) -> DynResult<()> {
        aria2_adapter::save_history(history)
    }
    fn scan_directory(&self, dir: &str) -> DynResult<Vec<DownloadTask>> {
        Ok(aria2_adapter::scan_download_directory(std::path::Path::new(dir)))
    }
    fn is_aria2_installed(&self) -> bool {
        aria2_adapter::is_aria2_installed()
    }
    fn aria2_install_command(&self) -> Option<String> {
        Some(aria2_adapter::aria2_install_command())
    }
    fn engine_version(&self) -> Option<String> {
        aria2_adapter::engine_version()
    }
    fn pkexec_available(&self) -> bool {
        aria2_adapter::pkexec_available()
    }
    fn run_privileged_install(&self, argv: &[String]) -> DynResult<i32> {
        aria2_adapter::run_privileged_install(argv)
    }
    fn apply_global_options(&self, settings: &EngineSettings) -> DynResult<()> {
        let secret = aria2_adapter::load_or_create_secret()?;
        aria2_adapter::apply_global_options(&secret, settings)
    }
}

pub struct DownloadsUseCase {
    port: Arc<dyn DownloadsPort>,
    default_dir: String,
    default_split: u32,
    /// Engine-wide settings (parallelism, speed cap, destination): the argv
    /// aria2c is spawned with, and the payload a running engine is reconfigured
    /// with. One value, so the two can never disagree.
    engine: EngineSettings,
}

impl DownloadsUseCase {
    pub fn new(port: Arc<dyn DownloadsPort>) -> Self {
        let default_dir = default_download_dir();
        let engine = EngineSettings::clamped(
            crate::domain::downloads::DEFAULT_CONCURRENT_DOWNLOADS,
            0,
            &default_dir,
        );
        Self {
            port,
            default_dir,
            default_split: DEFAULT_SPLIT,
            engine,
        }
    }

    pub fn with_defaults(port: Arc<dyn DownloadsPort>, default_dir: String, default_split: u32) -> Self {
        let engine = EngineSettings::clamped(
            crate::domain::downloads::DEFAULT_CONCURRENT_DOWNLOADS,
            0,
            &default_dir,
        );
        Self::with_engine(port, default_dir, default_split, engine)
    }

    /// Full constructor: destination + parts for new downloads, plus the
    /// engine-wide settings the aria2c process is started (and reconfigured)
    /// with.
    pub fn with_engine(
        port: Arc<dyn DownloadsPort>,
        default_dir: String,
        default_split: u32,
        engine: EngineSettings,
    ) -> Self {
        Self {
            port,
            default_dir,
            default_split: clamp_split(default_split as i64),
            engine,
        }
    }

    /// The engine-wide settings this session runs with.
    pub fn engine_settings(&self) -> &EngineSettings {
        &self.engine
    }

    /// Start the engine if it is installed and not already answering.
    ///
    /// The settings are the user's own (parallelism, speed cap, destination):
    /// they are passed at spawn time because that is the only moment aria2 reads
    /// them from argv. A missing engine is not an error - there is simply
    /// nothing to run.
    pub fn ensure_running(&self) -> DynResult<bool> {
        if !self.port.is_aria2_installed() {
            return Ok(false);
        }
        self.port.ensure_running(&self.engine)
    }

    /// What the engine is, plus how it could be installed.
    pub fn engine_status(&self) -> DynResult<EngineStatus> {
        let installed = self.port.is_aria2_installed();
        Ok(EngineStatus {
            installed,
            version: if installed { self.port.engine_version() } else { None },
            install_command: self
                .port
                .aria2_install_command()
                .unwrap_or_else(|| "https://aria2.github.io/".to_string()),
            installable: self.port.pkexec_available(),
        })
    }

    /// Install the engine with the desktop's own authentication dialog.
    ///
    /// Returns a report rather than an error: "you dismissed the prompt" and "no
    /// prompt can be shown here" are outcomes the user has to see, and both carry
    /// the command they can run themselves.
    pub fn install_engine(&self) -> DynResult<EngineInstallReport> {
        use crate::domain::downloads::{aria2_install_argv, aria2_install_command, InstallOutcome};
        use crate::domain::voice::package_manager_for_os_release;

        let package_manager = package_manager_for_os_release(&self.port.os_release());
        let command = aria2_install_command(package_manager).unwrap_or("https://aria2.github.io/");

        let Some(argv) = aria2_install_argv(package_manager) else {
            return Ok(Self::install_report(InstallOutcome::NoKnownPackage, command));
        };
        if !self.port.pkexec_available() {
            return Ok(Self::install_report(InstallOutcome::NoAuthenticationAgent, command));
        }

        let outcome = crate::domain::downloads::install_outcome(
            self.port.run_privileged_install(&argv)?,
        );
        Ok(Self::install_report(outcome, command))
    }

    fn install_report(
        outcome: crate::domain::downloads::InstallOutcome,
        install_command: &str,
    ) -> EngineInstallReport {
        EngineInstallReport {
            outcome: outcome.code().to_string(),
            message: outcome.message(install_command),
            installed: outcome.succeeded(),
        }
    }

    /// Reconfigure the engine that is already running.
    ///
    /// Settings changed in the UI have to reach the live process, or the new
    /// values only apply after the next restart. A missing engine is a skip, not
    /// a failure: the settings are read again at the next spawn.
    pub fn apply_engine_settings(&self, settings: &EngineSettings) -> DynResult<EngineApplyReport> {
        if !self.port.is_aria2_installed() {
            return Ok(EngineApplyReport {
                applied: false,
                reason: Some("aria2c is not installed; the settings apply when it is".to_string()),
            });
        }
        self.port.apply_global_options(settings)?;
        Ok(EngineApplyReport { applied: true, reason: None })
    }

    /// One-shot snapshot: fetch raw RPC tasks, normalise, group, aggregate,
    /// and reconcile with persistent history + download directory.
    pub fn snapshot(&self) -> DynResult<DownloadsSnapshot> {
        let is_installed = self.port.is_aria2_installed();
        let raw = if is_installed {
            self.port.fetch_raw().unwrap_or_default()
        } else {
            Vec::new()
        };
        let mut snap = Self::build_snapshot(raw);
        snap.aria_available = is_installed;
        snap.aria_install_command = self.port.aria2_install_command();
        snap.aria_version = if is_installed { self.port.engine_version() } else { None };
        snap.aria_installable = self.port.pkexec_available();
        self.reconcile_history(&mut snap)?;
        Ok(snap)
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

    /// Reconciles live stopped tasks with persistent history and discovers
    /// completed files in the target download directory.
    pub fn reconcile_history(&self, snap: &mut DownloadsSnapshot) -> DynResult<()> {
        let mut history = self.port.load_history().unwrap_or_default();
        let now_secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        // 1. Live stopped tasks from aria2 RPC (complete, error, removed)
        for stopped_task in &mut snap.stopped {
            history.dismissed.retain(|d| d != &stopped_task.gid && d != &stopped_task.name);
            if stopped_task.completed_at.is_none() {
                stopped_task.completed_at = Some(now_secs);
            }
            history.add_or_update(stopped_task.clone());
        }

        // 2. Ensure no active/waiting download remains in stopped history
        history.items.retain(|item| {
            !snap.active.iter().any(|a| a.gid == item.gid || a.name == item.name)
                && !snap.waiting.iter().any(|w| w.gid == item.gid || w.name == item.name)
        });

        // 4. Sort newest first
        history.items.sort_by(|a, b| {
            b.completed_at
                .unwrap_or(0)
                .cmp(&a.completed_at.unwrap_or(0))
                .then_with(|| a.name.cmp(&b.name))
        });

        // 5. Bound to 100 items
        if history.items.len() > 100 {
            history.items.truncate(100);
        }

        // 6. Save persistent state
        let _ = self.port.save_history(&history);

        // 7. Update snap.stopped with the complete history
        snap.stopped = history.items;
        Ok(())
    }

    /// Adds each non-empty line as its own task (AriaNg multi-URL pattern).
    pub fn add_urls(&self, input: &str, opts: NewDownloadOptions) -> DynResult<Vec<String>> {
        let urls = parse_urls(input);
        if urls.is_empty() {
            return Err("no URLs provided".into());
        }
        // The engine is optional, so this is the one place a user can learn *why*
        // their download did not start. Without the check the RPC call would
        // reach a closed port and report `Connection refused` instead.
        if !self.port.is_aria2_installed() {
            return Err(crate::domain::downloads::engine_missing_message(
                self.port.aria2_install_command().as_deref(),
            )
            .into());
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
        let _ = self.port.control("removeDownloadResult", gid);
        if let Ok(mut history) = self.port.load_history() {
            history.dismiss(gid);
            let _ = self.port.save_history(&history);
        }
        Ok(())
    }

    pub fn purge_results(&self) -> DynResult<()> {
        let _ = self.port.purge();
        if let Ok(mut history) = self.port.load_history() {
            history.clear();
            let _ = self.port.save_history(&history);
        }
        Ok(())
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
    /// Engine state belongs to the signature: it decides whether the Downloads
    /// tab exists and what the settings page reports, so an install (or a lost
    /// engine) must reach the UI even when no task changed.
    pub aria_available: bool,
    pub aria_version: Option<String>,
    pub aria_installable: bool,
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
        aria_available: snap.aria_available,
        aria_version: snap.aria_version.clone(),
        aria_installable: snap.aria_installable,
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

/// Should this tick start the engine?
///
/// The watch loop starts the engine once at startup. If the engine is installed
/// *while the shell runs* - the settings page's install flow, or a package
/// manager - that one attempt is long past, and the tab would appear with a list
/// that can never fill. Exactly the false→true transition triggers a start; a
/// failing start is not retried every tick (the next `add`/`ensure` tries again,
/// and the loop keeps reporting the state).
pub fn should_start_engine(previous_available: Option<bool>, current_available: bool) -> bool {
    previous_available == Some(false) && current_available
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
    let mut engine_present: Option<bool> = None;
    loop {
        let port = Arc::clone(&use_case.port);
        let dir = use_case.default_dir.clone();
        let split = use_case.default_split;
        let engine = use_case.engine.clone();
        let snap: DynResult<DownloadsSnapshot> = blocking(move || {
            let uc = DownloadsUseCase::with_engine(port, dir, split, engine);
            uc.snapshot()
        })
        .await;
        match snap {
            Ok(s) => {
                if should_start_engine(engine_present.take(), s.aria_available) {
                    // The engine appeared: start it before reporting, so the very
                    // next snapshot has real tasks instead of an empty list.
                    engine_present = Some(true);
                    let port = Arc::clone(&use_case.port);
                    let dir = use_case.default_dir.clone();
                    let split = use_case.default_split;
                    let engine = use_case.engine.clone();
                    let _ = blocking(move || {
                        let uc = DownloadsUseCase::with_engine(port, dir, split, engine);
                        uc.ensure_running()
                    })
                    .await;
                    continue;
                }
                engine_present = Some(s.aria_available);
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
