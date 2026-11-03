//! Walks `/proc/*/fdinfo/*` to measure real GPU engine utilisation.
//!
//! Utilisation is a *rate*, so a single scan cannot produce it: this keeps the
//! previous scan and its timestamp, and each call returns the busy fraction over
//! the interval since last time. The first call of a process therefore reports
//! nothing measurable (`None`), and the caller keeps showing its last known
//! value instead of a fabricated zero.

use crate::domain::gpu_engine::{
    aggregate_engine_busy, encode_engine_state, parse_engine_state, parse_fdinfo_engine_busy,
    rates_from_state, EngineSample, PdevKey,
};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// One scan of every readable DRM client, keyed by device.
#[derive(Debug, Default, Clone)]
pub struct EngineSnapshot {
    /// Per device: the max render-engine busy counter among its clients.
    pub render_ns: HashMap<PdevKey, u64>,
    /// Per device: the max of each client's busiest engine.
    pub busy_ns: HashMap<PdevKey, u64>,
}

impl EngineSnapshot {
    /// Fold every readable `/proc/<pid>/fdinfo/<fd>` into per-device totals.
    ///
    /// Unreadable fds (other users' processes, kwin when hardened, races with
    /// exits) are skipped: measurement is best-effort, and a partial scan is
    /// still a lower bound on real usage rather than an error.
    pub fn scan() -> Self {
        let mut snapshot = Self::default();
        let Ok(procs) = std::fs::read_dir("/proc") else {
            return snapshot;
        };

        for proc_entry in procs.flatten() {
            let name = proc_entry.file_name();
            let Some(pid) = name.to_str() else { continue };
            if !pid.chars().all(|c| c.is_ascii_digit()) {
                continue;
            }
            let Ok(fds) = std::fs::read_dir(proc_entry.path().join("fdinfo")) else {
                continue;
            };
            let mut samples: Vec<EngineSample> = Vec::new();
            for fd in fds.flatten() {
                let Ok(content) = std::fs::read_to_string(fd.path()) else {
                    continue;
                };
                if let Some(sample) = parse_fdinfo_engine_busy(&content) {
                    samples.push(sample);
                }
            }
            if samples.is_empty() {
                continue;
            }
            // Several fds of one client repeat the same totals; aggregate per
            // device so a client is counted once.
            let mut by_device: HashMap<PdevKey, Vec<EngineSample>> = HashMap::new();
            for sample in samples {
                by_device.entry(sample.pdev.clone()).or_default().push(sample);
            }
            for (pdev, client_samples) in by_device {
                let (render, busy) = aggregate_engine_busy(&client_samples);
                // Cross-process totals add up: the engines are shared.
                *snapshot.render_ns.entry(pdev.clone()).or_insert(0) += render;
                *snapshot.busy_ns.entry(pdev).or_insert(0) += busy;
            }
        }
        snapshot
    }
}

/// Where the previous counters are kept between CLI invocations.
///
/// `/dev/shm` is preferred: it is tmpfs, so writing it a few times per second
/// never touches the disk, and it disappears on reboot (which is right - the
/// counters do too).
pub fn engine_state_path() -> PathBuf {
    if Path::new("/dev/shm").exists() {
        PathBuf::from("/dev/shm/astral_gpu_engine")
    } else {
        std::env::temp_dir().join("astral_gpu_engine")
    }
}

/// Compute per-device usage for this CLI invocation and persist the sample.
///
/// Returns only *measured* devices. An empty map means "nothing measurable yet"
/// (first run, or the cache is unreadable), and the caller must then keep its
/// previous value or fall back - never present the absence of a measurement as
/// an idle GPU.
pub fn measure_engine_usage(state_path: &Path) -> HashMap<PdevKey, f64> {
    let snapshot = EngineSnapshot::scan();
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);

    let rates = std::fs::read_to_string(state_path)
        .ok()
        .and_then(|content| parse_engine_state(&content))
        .map(|(prev_ms, prev)| rates_from_state(prev_ms, &prev, now_ms, &snapshot.busy_ns))
        .unwrap_or_default();

    let encoded = encode_engine_state(now_ms, &snapshot.busy_ns);
    // A failed write only costs one tick of rate; never fail the whole metrics
    // read because a tmpfs file could not be replaced.
    let tmp = state_path.with_extension("tmp");
    if std::fs::write(&tmp, encoded).is_ok() {
        let _ = std::fs::rename(&tmp, state_path);
    }

    rates
}

/// How long a cached sample may be reused before a measurement is stale.
///
/// The shell polls every ~400 ms; a cache older than this means the previous
/// write failed, and the delta would be spread over an unknown interval.
pub const MAX_SAMPLE_AGE_MS: u64 = 5_000;

/// The measured usage for one card, or `None` when nothing was measurable.
///
/// Matching is by PCI slot because the two sources name the same device
/// differently (`drm-pdev` may omit the `0000:` domain).
pub fn measured_usage_for_pci_slot(
    rates: &HashMap<PdevKey, f64>,
    pci_slot: &str,
) -> Option<f64> {
    rates.iter().find_map(|(pdev, usage)| {
        if crate::domain::gpu_engine::pdev_matches_pci_slot(pdev.as_str(), pci_slot) {
            Some(*usage)
        } else {
            None
        }
    })
}
