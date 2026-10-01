//! Infrastructure adapter owning the persistent aria2c RPC child.
//!
//! The daemon (not QML) owns exactly one `aria2c --enable-rpc` process, so a
//! shell/QML reload re-attaches instead of killing downloads. Ownership:
//!
//! * state dir `$XDG_STATE_HOME/astral-plasma` (branding): session file,
//!   RPC secret (0600).
//! * `ensure_running()` spawns aria2c detached (`--daemon=true`) when no
//!   healthy instance answers; the session file + `--continue` resume partial
//!   files across reboot/logout.
//! * JSON-RPC over HTTP on 127.0.0.1:6800 (blocking `std` HTTP client on a
//!   short timeout). Change events reach QML via `downloads watch`
//!   (see `application::download_service`): full snapshot on start, then
//!   change-only lines at 1s active / 5s idle cadence. No polling anywhere.

use crate::domain::branding;
use crate::domain::downloads::{
    DownloadHistory, DownloadStatus, DownloadTask, NewDownloadOptions, ARIA2_RPC_PORT,
};
use crate::domain::ports::DynResult;
use std::fs;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

const RPC_TIMEOUT: Duration = Duration::from_secs(4);
pub const RPC_SECRET_BYTES: usize = 32;

fn state_dir() -> PathBuf {
    branding::state_home().join(branding::STATE_DIR)
}

pub fn downloads_state_dir() -> PathBuf {
    state_dir().join("downloads")
}

pub fn session_file() -> PathBuf {
    downloads_state_dir().join("aria2.session")
}

pub fn secret_file() -> PathBuf {
    downloads_state_dir().join("rpc.secret")
}

pub fn history_file() -> PathBuf {
    downloads_state_dir().join("history.json")
}

fn lock_file() -> PathBuf {
    downloads_state_dir().join("aria2.lock")
}

/// Reads (or creates, 0600) the persistent RPC secret token.
pub fn load_or_create_secret() -> DynResult<String> {
    let dir = downloads_state_dir();
    fs::create_dir_all(&dir)?;
    let path = secret_file();
    if let Ok(raw) = fs::read_to_string(&path) {
        let s = raw.trim().to_string();
        if s.len() >= 16 {
            return Ok(s);
        }
    }
    let secret = random_token(RPC_SECRET_BYTES);
    fs::write(&path, format!("{}\n", secret))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
    }
    Ok(secret)
}

fn random_token(n: usize) -> String {
    // No rand dependency: fold /dev/urandom (fallback: time+pid) into hex.
    let mut bytes = vec![0u8; n];
    let mut filled = false;
    if let Ok(mut f) = fs::File::open("/dev/urandom") {
        if f.read_exact(&mut bytes).is_ok() {
            filled = true;
        }
    }
    if !filled {
        let mut x: u64 = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0x9e3779b97f4a7c15)
            ^ (std::process::id() as u64).wrapping_mul(0xbf58476d1ce4e5b9);
        for b in bytes.iter_mut() {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            *b = (x & 0xff) as u8;
        }
    }
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

/// Builds the aria2c argument vector. Pure: unit-tested without spawning.
///
/// Completion is observed by the `downloads watch` loop diffing snapshots
/// (change-only emission, 1s active / 5s idle): aria2 `--on-*` hooks would
/// print into the detached daemon's /dev/null stdout, so they are
/// deliberately not used.
pub fn aria2_args(
    secret: &str,
    session: &PathBuf,
    log: &PathBuf,
    _daemon_bin: &PathBuf,
    default_dir: &str,
) -> Vec<String> {
    let args = vec![
        "--enable-rpc=true".into(),
        "--rpc-listen-port".into(),
        ARIA2_RPC_PORT.to_string(),
        "--rpc-listen-all=false".into(),
        format!("--rpc-secret={}", secret),
        "--daemon=true".into(),
        "--continue=true".into(),
        "--max-concurrent-downloads=5".into(),
        format!("--dir={}", default_dir),
        format!("--input-file={}", session.display()),
        format!("--save-session={}", session.display()),
        "--save-session-interval=30".into(),
        format!("--log={}", log.display()),
        "--log-level=warn".into(),
    ];
    // aria2 requires the session file to exist for --input-file.
    let _ = fs::OpenOptions::new().create(true).write(true).open(session);
    args
}

/// Spawns aria2c detached when no healthy instance answers. Idempotent:
/// returns Ok(false) when already running, Ok(true) when (re)started.
pub fn ensure_running(default_dir: &str) -> DynResult<bool> {
    let dir = downloads_state_dir();
    fs::create_dir_all(&dir)?;
    let session = session_file();
    if !session.exists() {
        fs::write(&session, "")?;
    }
    let secret = load_or_create_secret()?;

    if rpc_ping(&secret).is_ok() {
        return Ok(false);
    }

    // Stale lock: try once to clear a dead pid file.
    let _ = fs::remove_file(lock_file());

    let log = dir.join("aria2.log");
    let home_dl = default_dir.to_string();
    let args = aria2_args(&secret, &session, &log, &PathBuf::new(), &home_dl);

    let mut cmd = Command::new("aria2c");
    cmd.args(&args);
    // Fully detached: the daemon CLI returns immediately; QML never waits.
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        unsafe {
            cmd.pre_exec(|| {
                libc::setsid();
                Ok(())
            });
        }
        cmd.stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
    }
    cmd.spawn()?;

    // Wait briefly for the RPC port to answer (bounded, off the async runtime).
    for _ in 0..20 {
        std::thread::sleep(Duration::from_millis(150));
        if rpc_ping(&secret).is_ok() {
            return Ok(true);
        }
    }
    Err("aria2c did not answer JSON-RPC after start".into())
}

/// Minimal blocking JSON-RPC client (no new deps): POST + Content-Length framing.
pub fn rpc_call(secret: &str, method: &str, params: serde_json::Value) -> DynResult<serde_json::Value> {
    let mut full_params = vec![serde_json::Value::String(format!("token:{}", secret))];
    match params {
        serde_json::Value::Array(mut a) => full_params.append(&mut a),
        other => full_params.push(other),
    }
    let body = serde_json::to_string(&serde_json::json!({
        "jsonrpc": "2.0",
        "id": "astral",
        "method": format!("aria2.{}", method),
        "params": full_params,
    }))?;
    let req = format!(
        "POST /jsonrpc HTTP/1.0\r\nHost: 127.0.0.1:{}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        ARIA2_RPC_PORT,
        body.len(),
        body
    );
    let mut stream = TcpStream::connect_timeout(
        &format!("127.0.0.1:{}", ARIA2_RPC_PORT).parse()?,
        RPC_TIMEOUT,
    )?;
    stream.set_read_timeout(Some(RPC_TIMEOUT))?;
    stream.set_write_timeout(Some(RPC_TIMEOUT))?;
    stream.write_all(req.as_bytes())?;
    let mut resp = String::new();
    stream.read_to_string(&mut resp)?;
    let json_start = resp.find('{').ok_or("no JSON in aria2 response")?;
    let val: serde_json::Value = serde_json::from_str(&resp[json_start..])?;
    if let Some(err) = val.get("error") {
        return Err(format!("aria2 rpc {} failed: {}", method, err).into());
    }
    Ok(val.get("result").cloned().unwrap_or(serde_json::Value::Null))
}

fn rpc_ping(secret: &str) -> DynResult<()> {
    rpc_call(secret, "getVersion", serde_json::Value::Array(vec![]))?;
    Ok(())
}

/// Fetches active + waiting + stopped tasks with the fields the QML rows need.
pub fn fetch_all(secret: &str) -> DynResult<Vec<serde_json::Value>> {
    let keys = serde_json::json!([
        "gid", "status", "totalLength", "completedLength", "downloadSpeed",
        "dir", "files", "errorCode"
    ]);
    let mut out = Vec::new();
    for method in ["tellActive", "tellWaiting", "tellStopped"] {
        let params = if method == "tellActive" {
            serde_json::json!([keys])
        } else {
            serde_json::json!([0, 1000, keys])
        };
        let res = rpc_call(secret, method, params)?;
        if let Some(arr) = res.as_array() {
            out.extend(arr.iter().cloned());
        }
    }
    Ok(out)
}

/// Adds one URL with per-add options; returns the new gid.
pub fn add_uri(secret: &str, url: &str, opts: &NewDownloadOptions, position: Option<u32>) -> DynResult<String> {
    let mut params = vec![
        serde_json::Value::Array(vec![serde_json::Value::String(url.to_string())]),
        serde_json::Value::Object(opts.to_rpc_map()),
    ];
    if let Some(p) = position {
        params.push(serde_json::Value::Number(p.into()));
    }
    let res = rpc_call(secret, "addUri", serde_json::Value::Array(params))?;
    res.as_str()
        .map(ToString::to_string)
        .ok_or_else(|| "aria2 addUri returned no gid".into())
}

/// Single-gid control verbs.
pub fn control(secret: &str, verb: &str, gid: &str) -> DynResult<serde_json::Value> {
    rpc_call(
        secret,
        verb,
        serde_json::json!([gid]),
    )
}

/// Retry a failed download: re-add the first URI, then drop the old result
/// (AriaNg `retryTask` pattern).
pub fn retry(secret: &str, gid: &str, opts: &NewDownloadOptions) -> DynResult<String> {
    let status = rpc_call(secret, "tellStatus", serde_json::json!([gid, ["files", "dir"]]))?;
    let uri = status
        .get("files")
        .and_then(|f| f.as_array())
        .and_then(|a| a.first())
        .and_then(|f| f.get("uris"))
        .and_then(|u| u.as_array())
        .and_then(|a| a.first())
        .and_then(|e| e.get("uri"))
        .and_then(|u| u.as_str())
        .ok_or("no URI to retry")?
        .to_string();
    let mut o = opts.clone();
    if o.dir.is_none() {
        o.dir = status
            .get("dir")
            .and_then(|d| d.as_str())
            .map(ToString::to_string);
    }
    let new_gid = add_uri(secret, &uri, &o, None)?;
    let _ = rpc_call(secret, "removeDownloadResult", serde_json::json!([gid]));
    Ok(new_gid)
}

/// Loads persistent download history from disk.
pub fn load_history() -> DynResult<DownloadHistory> {
    let path = history_file();
    if !path.exists() {
        return Ok(DownloadHistory::default());
    }
    let content = fs::read_to_string(&path)?;
    if let Ok(hist) = serde_json::from_str::<DownloadHistory>(&content) {
        return Ok(hist);
    }
    if let Ok(tasks) = serde_json::from_str::<Vec<DownloadTask>>(&content) {
        return Ok(DownloadHistory {
            items: tasks,
            dismissed: Vec::new(),
        });
    }
    Ok(DownloadHistory::default())
}

/// Saves persistent download history to disk.
pub fn save_history(history: &DownloadHistory) -> DynResult<()> {
    let dir = downloads_state_dir();
    fs::create_dir_all(&dir)?;
    let path = history_file();
    let json = serde_json::to_string_pretty(history)?;
    fs::write(&path, json)?;
    Ok(())
}

/// 64-bit FNV-1a hash for deriving stable file GIDs without external dependencies.
fn fnv1a_hash(s: &str) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for b in s.as_bytes() {
        hash ^= *b as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

/// Scans the target download directory (e.g. ~/Downloads) for existing downloaded files.
/// Ignores hidden files and temporary/control files (.aria2, .crdownload, .part, .tmp).
pub fn scan_download_directory(dir: &std::path::Path) -> Vec<DownloadTask> {
    let mut tasks = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return tasks,
    };

    let dir_str = dir.to_string_lossy().to_string();

    for entry in entries.flatten() {
        let file_type = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if !file_type.is_file() {
            continue;
        }

        let file_name = entry.file_name().to_string_lossy().to_string();
        if file_name.starts_with('.') {
            continue;
        }

        let lower = file_name.to_lowercase();
        if lower.ends_with(".aria2")
            || lower.ends_with(".crdownload")
            || lower.ends_with(".part")
            || lower.ends_with(".tmp")
            || lower.ends_with(".download")
        {
            continue;
        }

        let metadata = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };

        let file_len = metadata.len();
        let mtime = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs());

        let gid = format!("file-{:016x}", fnv1a_hash(&format!("{}/{}", dir_str, file_name)));

        tasks.push(DownloadTask {
            gid,
            name: file_name,
            status: DownloadStatus::Complete,
            total_length: file_len,
            completed_length: file_len,
            download_speed: 0,
            dir: dir_str.clone(),
            error_code: None,
            completed_at: mtime,
        });
    }

    // Sort newest first
    tasks.sort_by(|a, b| {
        b.completed_at
            .unwrap_or(0)
            .cmp(&a.completed_at.unwrap_or(0))
            .then_with(|| a.name.cmp(&b.name))
    });

    // Bound to top 100 recent files
    if tasks.len() > 100 {
        tasks.truncate(100);
    }

    tasks
}

/// Checks whether the aria2c binary is present in PATH and executable.
pub fn is_aria2_installed() -> bool {
    Command::new("aria2c")
        .arg("--version")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Derives the tailored installation command for the current distribution.
pub fn aria2_install_command() -> String {
    let os_release = std::fs::read_to_string("/etc/os-release").unwrap_or_default();
    match crate::domain::voice::package_manager_for_os_release(&os_release) {
        crate::domain::voice::PackageManager::Pacman => "sudo pacman -S aria2".to_string(),
        crate::domain::voice::PackageManager::Apt => "sudo apt install aria2".to_string(),
        crate::domain::voice::PackageManager::Dnf => "sudo dnf install aria2".to_string(),
        crate::domain::voice::PackageManager::Zypper => "sudo zypper install aria2".to_string(),
        crate::domain::voice::PackageManager::Nix => "nix-env -iA nixpkgs.aria2".to_string(),
        crate::domain::voice::PackageManager::Unknown => "https://aria2.github.io/".to_string(),
    }
}


