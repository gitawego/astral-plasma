//! Download manager domain: pure models, aria2 payload parsing, and total-progress math.
//!
//! Everything here is side-effect free and fully unit-tested. aria2 speaks
//! JSON-RPC with all byte counts as *strings*; [`parse_task`] normalises one
//! raw task object into a [`DownloadTask`]. [`aggregate_total`] folds the
//! counted tasks (active + waiting + paused) into a single [`DownloadsTotal`]
//! that drives the top-right border HUD: fill fraction = progress, packet
//! motion = speed.

use serde::{Deserialize, Serialize};

/// Default per-file split connections (`-s` / `--split`).
pub const DEFAULT_SPLIT: u32 = 4;
/// Hard clamp for user-supplied split values (aria2 supports 1..*).
pub const MAX_SPLIT: u32 = 16;
/// aria2 default RPC port.
pub const ARIA2_RPC_PORT: u16 = 6800;

/// Lifecycle of one download, mapped from aria2 `status` strings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DownloadStatus {
    Active,
    Waiting,
    Paused,
    Complete,
    Error,
    Removed,
    Unknown,
}

impl DownloadStatus {
    /// Maps an aria2 status string; unknown strings degrade to [`DownloadStatus::Unknown`].
    pub fn from_aria2(s: &str) -> Self {
        match s {
            "active" => Self::Active,
            "waiting" => Self::Waiting,
            "paused" => Self::Paused,
            "complete" => Self::Complete,
            "error" => Self::Error,
            "removed" => Self::Removed,
            _ => Self::Unknown,
        }
    }

    /// Whether this task counts toward the aggregate total bar.
    ///
    /// Active + waiting + paused contribute bytes (paused/waiting add 0
    /// speed, so the bar freezes honestly). Complete/error/removed are
    /// excluded: a finished file must not pin the bar at 100%.
    pub fn counts_in_total(&self) -> bool {
        matches!(self, Self::Active | Self::Waiting | Self::Paused)
    }

    /// Terminal states that can leave the aggregate.
    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Complete | Self::Error | Self::Removed)
    }
}

/// One download row, in shell-native numeric types.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DownloadTask {
    pub gid: String,
    pub name: String,
    pub status: DownloadStatus,
    pub total_length: u64,
    pub completed_length: u64,
    pub download_speed: u64,
    #[serde(default)]
    pub dir: String,
    #[serde(default)]
    pub error_code: Option<String>,
}

impl DownloadTask {
    /// 0.0..=1.0 fraction; indeterminate (unknown total) reports 0.0.
    pub fn progress(&self) -> f64 {
        if self.total_length == 0 {
            0.0
        } else {
            (self.completed_length.min(self.total_length) as f64) / (self.total_length as f64)
        }
    }

    /// Remaining bytes, saturating.
    pub fn remaining(&self) -> u64 {
        self.total_length.saturating_sub(self.completed_length)
    }
}

/// Aggregate folded over every counted task; the single source of truth for
/// the top-right border HUD (`totalProgress = Σ completed / Σ total`).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct DownloadsTotal {
    pub completed_length: u64,
    pub total_length: u64,
    pub download_speed: u64,
    /// Σ completed / Σ total over counted tasks with known length.
    pub progress: f64,
    /// Counted tasks (active + waiting + paused).
    pub active_count: usize,
    /// True when at least one counted task has unknown length: the HUD must
    /// loop (AI-style) instead of filling.
    pub indeterminate: bool,
}

/// ETA in whole seconds; `None` when nothing is moving.
pub fn eta_seconds(remaining: u64, speed: u64) -> Option<u64> {
    if speed == 0 || remaining == 0 {
        None
    } else {
        Some(remaining / speed)
    }
}

/// Folds counted tasks into [`DownloadsTotal`].
pub fn aggregate_total(tasks: &[DownloadTask]) -> DownloadsTotal {
    let mut total = DownloadsTotal::default();
    let mut known_bytes = false;
    for t in tasks.iter().filter(|t| t.status.counts_in_total()) {
        total.active_count += 1;
        total.download_speed = total.download_speed.saturating_add(t.download_speed);
        if t.total_length > 0 {
            known_bytes = true;
            total.completed_length = total
                .completed_length
                .saturating_add(t.completed_length.min(t.total_length));
            total.total_length = total.total_length.saturating_add(t.total_length);
        }
    }
    total.indeterminate = total.active_count > 0 && !known_bytes;
    total.progress = if total.total_length > 0 {
        (total.completed_length as f64) / (total.total_length as f64)
    } else {
        0.0
    };
    total
}

/// Parses one multi-line URL input into tasks (one per line), mirroring
/// AriaNg's `parseUrlsFromOriginInput`: trim, drop empties.
pub fn parse_urls(input: &str) -> Vec<String> {
    input
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(ToString::to_string)
        .collect()
}

/// Clamps a user-supplied split value into 1..=[`MAX_SPLIT`].
pub fn clamp_split(n: i64) -> u32 {
    (n.max(1).min(MAX_SPLIT as i64)) as u32
}

/// Derives a display filename from an aria2 file path or URI: basename,
/// query string stripped, percent-decoded.
pub fn derive_filename(path_or_uri: &str) -> String {
    let no_query = path_or_uri.split(['?', '#']).next().unwrap_or("");
    let base = no_query.rsplit('/').next().unwrap_or(no_query);
    let decoded = percent_decode(base);
    if decoded.is_empty() {
        no_query.to_string()
    } else {
        decoded
    }
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(h), Some(l)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2])) {
                out.push(h * 16 + l);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out).unwrap_or_else(|_| s.to_string())
}

fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

/// Reads a u64 that aria2 encodes as either a JSON string or number.
fn num_from_value(v: &serde_json::Value) -> u64 {
    match v {
        serde_json::Value::String(s) => s.parse::<u64>().unwrap_or(0),
        serde_json::Value::Number(n) => n.as_u64().unwrap_or(0),
        _ => 0,
    }
}

/// Normalises one raw aria2 `tell*` task object. Returns `None` when the
/// object carries no usable `gid`.
pub fn parse_task(v: &serde_json::Value) -> Option<DownloadTask> {
    let gid = v.get("gid")?.as_str()?.to_string();
    if gid.is_empty() {
        return None;
    }
    let status = DownloadStatus::from_aria2(v.get("status").and_then(|s| s.as_str()).unwrap_or(""));
    let total_length = v.get("totalLength").map(num_from_value).unwrap_or(0);
    let completed_length = v.get("completedLength").map(num_from_value).unwrap_or(0);
    let download_speed = v.get("downloadSpeed").map(num_from_value).unwrap_or(0);
    let dir = v
        .get("dir")
        .and_then(|s| s.as_str())
        .unwrap_or_default()
        .to_string();
    let error_code = v
        .get("errorCode")
        .and_then(|s| s.as_str())
        .filter(|s| !s.is_empty() && *s != "0")
        .map(ToString::to_string);

    // Name: first file path wins, else first URI, else the gid.
    let mut name = String::new();
    if let Some(files) = v.get("files").and_then(|f| f.as_array()) {
        if let Some(path) = files.first().and_then(|f| f.get("path")).and_then(|p| p.as_str()) {
            if !path.is_empty() {
                name = derive_filename(path);
            }
        }
        if name.is_empty() {
            if let Some(uri) = files
                .first()
                .and_then(|f| f.get("uris"))
                .and_then(|u| u.as_array())
                .and_then(|a| a.first())
                .and_then(|e| e.get("uri"))
                .and_then(|u| u.as_str())
            {
                name = derive_filename(uri);
            }
        }
    }
    if name.is_empty() {
        name = gid.clone();
    }

    Some(DownloadTask {
        gid,
        name,
        status,
        total_length,
        completed_length,
        download_speed,
        dir,
        error_code,
    })
}

/// Per-add options; serialises to the aria2 `addUri` options map.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct NewDownloadOptions {
    pub dir: Option<String>,
    pub out: Option<String>,
    pub split: Option<u32>,
    pub max_connection_per_server: Option<u32>,
    pub pause_on_added: bool,
}

impl NewDownloadOptions {
    /// Builds the aria2 options object. `split` also sets the per-server
    /// cap so connections are not throttled below the requested parts.
    pub fn to_rpc_map(&self) -> serde_json::Map<String, serde_json::Value> {
        let mut m = serde_json::Map::new();
        if let Some(d) = &self.dir {
            if !d.trim().is_empty() {
                m.insert("dir".into(), serde_json::Value::String(d.clone()));
            }
        }
        if let Some(o) = &self.out {
            if !o.trim().is_empty() {
                m.insert("out".into(), serde_json::Value::String(o.clone()));
            }
        }
        if let Some(s) = self.split {
            let s = clamp_split(s as i64).to_string();
            m.insert("split".into(), serde_json::Value::String(s.clone()));
            m.insert("max-connection-per-server".into(), serde_json::Value::String(s));
        }
        if let Some(c) = self.max_connection_per_server {
            m.insert(
                "max-connection-per-server".into(),
                serde_json::Value::String(clamp_split(c as i64).to_string()),
            );
        }
        if self.pause_on_added {
            m.insert("pause".into(), serde_json::Value::String("true".into()));
        }
        // Resume partial files by default so a reboot continues cleanly.
        m.insert("continue".into(), serde_json::Value::String("true".into()));
        m
    }
}
