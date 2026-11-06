//! GPU utilisation from DRM engine counters.
//!
//! Every process holding a DRM device has `/proc/<pid>/fdinfo/<fd>` entries
//! that the kernel fills in: `drm-pdev` names the device (`0000:00:02.0`) and
//! `drm-engine-<name>: <ns>` reports how many nanoseconds that client has spent
//! on each engine. Two samples of the same counter give real utilisation:
//!
//! ```text
//! usage = (busy_ns(t1) - busy_ns(t0)) / (t1 - t0)
//! ```
//!
//! This is what `intel_gpu_top` shows, but it needs no `CAP_PERFMON` and no
//! `debugfs`: reading our own `/proc` is enough. The alternative used for Intel
//! before this module - the ratio between `gt_min_freq_mhz` and
//! `gt_max_freq_mhz` - is a *clock* ratio, not utilisation. On a 240 Hz panel
//! the RPS governor parks near the maximum clock while the engine is nearly
//! idle, so the clock ratio reported 60-100 % on a 5 %-busy GPU.
//!
//! It is however an **incomplete** source, and no longer the first one: it can
//! only read DRM clients this process may open, and `kwin_wayland` carries
//! `cap_sys_nice=ep` file capabilities, which makes the kernel mark it
//! non-dumpable. The compositor's `fdinfo` answers `EACCES` to every reader below
//! `CAP_SYS_PTRACE`, and on a 240 Hz panel it is the largest client of all - the
//! sum reported 46 % on a GPU whose `rc6_residency_ms` never advanced.
//! [`crate::infrastructure::gpu_pmu_probe`] reads the GT-wide i915 perf counters
//! instead (`CAP_PERFMON`, every client); this module remains the fallback for
//! every host that cannot grant it, and the only source on AMD/NVIDIA.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A DRM device key as it appears in `drm-pdev` (e.g. `0000:00:02.0`).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
pub struct PdevKey(pub String);

impl PdevKey {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<&str> for PdevKey {
    fn from(value: &str) -> Self {
        Self(value.trim().to_ascii_lowercase())
    }
}

// Comparing a device key to the literal slot written in a test or a log line
// should not require an `.into()` at every call site.
impl PartialEq<str> for PdevKey {
    fn eq(&self, other: &str) -> bool {
        self.0 == other
    }
}

impl PartialEq<&str> for PdevKey {
    fn eq(&self, other: &&str) -> bool {
        self.0 == *other
    }
}

impl From<String> for PdevKey {
    fn from(value: String) -> Self {
        Self(value.trim().to_ascii_lowercase())
    }
}

/// One DRM client's engine counters, isolated from its fdinfo text.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct EngineSample {
    pub pdev: PdevKey,
    pub render_ns: u64,
    pub copy_ns: u64,
    pub video_ns: u64,
}

impl EngineSample {
    /// The busiest engine of this client.
    ///
    /// A client is "using the GPU" as much as its most saturated engine, not as
    /// the sum of its engines: render and copy run in parallel, so adding them
    /// can exceed wall time.
    pub fn busy_total_ns(&self) -> u64 {
        self.render_ns.max(self.copy_ns).max(self.video_ns)
    }
}

fn parse_ns(value: &str) -> u64 {
    // Lines look like `drm-engine-render:\t123456789 ns`.
    let digits = value.split_whitespace().next().unwrap_or("");
    digits.parse::<u64>().unwrap_or(0)
}

/// Parse one `fdinfo` file into an engine sample.
///
/// Returns `None` for anything that is not a DRM client: a socket, a pipe, or an
/// engine line without a device is not attributable to a GPU and must not be
/// counted. Unparseable or negative counters degrade to `0` rather than
/// aborting the sample - a garbled line from one process must not blind the
/// whole reading.
pub fn parse_fdinfo_engine_busy(content: &str) -> Option<EngineSample> {
    let mut pdev: Option<&str> = None;
    let mut sample = EngineSample::default();

    for line in content.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        match key.trim() {
            "drm-pdev" => pdev = Some(value.trim()),
            "drm-engine-render" => sample.render_ns = parse_ns(value),
            "drm-engine-copy" => sample.copy_ns = parse_ns(value),
            "drm-engine-video" => sample.video_ns = parse_ns(value),
            _ => {}
        }
    }

    let pdev = pdev.filter(|p| !p.is_empty())?;
    sample.pdev = PdevKey::from(pdev);
    Some(sample)
}

/// Fold a process's fds into `(render_ns, busiest_engine_ns)`.
///
/// One DRM client exposes several fds, and each repeats the same client-wide
/// totals. Summing them would multiply the load by the fd count, so each metric
/// is the maximum across the samples instead.
pub fn aggregate_engine_busy(samples: &[EngineSample]) -> (u64, u64) {
    let mut render = 0;
    let mut busy = 0;
    for sample in samples {
        render = render.max(sample.render_ns);
        busy = busy.max(sample.busy_total_ns());
    }
    (render, busy)
}

/// Convert a busy-counter delta into a 0..=1 utilisation.
///
/// Clamped at both ends: a counter that restarts (process re-exec, driver
/// reset) reads as 0 %, and a busy time longer than the window - which happens
/// when two samples are taken back to back while other engines keep running -
/// reads as 100 % instead of an impossible 400 %.
pub fn gpu_usage_percent(delta_busy_ns: u64, delta_wall_ns: u64) -> f64 {
    if delta_wall_ns == 0 {
        return 0.0;
    }
    (delta_busy_ns as f64 / delta_wall_ns as f64).clamp(0.0, 1.0)
}

/// Compare a `drm-pdev` / uevent slot against an lspci slot.
///
/// The PCI domain prefix (`0000:`) is optional in all three sources, so
/// `00:02.0`, `0000:00:02.0` and `0000:00:02.0` in upper case all name the same
/// device. An empty slot on either side never matches: that would attribute
/// every GPU's busy time to whichever card happened to be scanned first.
pub fn pdev_matches_pci_slot(pdev: &str, pci_slot: &str) -> bool {
    fn norm(slot: &str) -> String {
        let low = slot.trim().to_ascii_lowercase();
        match low.split_once(':') {
            // Strip a leading domain when it is the canonical 4-hex-digit form.
            Some((domain, rest)) if domain.len() == 4 && domain.chars().all(|c| c.is_ascii_hexdigit()) => rest.to_string(),
            _ => low,
        }
    }
    let a = norm(pdev);
    let b = norm(pci_slot);
    !a.is_empty() && a == b
}

/// Which number to publish as `usage`.
///
/// Measured engine time wins whenever any DRM client could be read. The clock
/// ratio (`fallback`) is a last resort only for drivers that expose no engine
/// counters to us - never a silent substitute for a real measurement.
pub fn resolve_usage(measured: Option<f64>, fallback: f64) -> f64 {
    measured.unwrap_or(fallback).clamp(0.0, 1.0)
}

/// Utilisation for one card, in order of how much of the GPU each source sees.
///
/// `gt` is the driver's GT-wide counter (i915 perf PMU): every client counts,
/// including the compositor, which fdinfo cannot see because KWin runs with
/// `cap_sys_nice=ep` file capabilities and is therefore non-dumpable. `per_client`
/// is the sum of the `/proc/<pid>/fdinfo` engine counters: real, but a lower
/// bound that silently omits such clients. `fallback` is the driver's own
/// percentage, or the Intel clock ratio as a last resort.
pub fn resolve_usage_staged(gt: Option<f64>, per_client: Option<f64>, fallback: f64) -> f64 {
    resolve_usage(gt.or(per_client), fallback)
}

// ---------------------------------------------------------------------------
// GT-wide perf counters
// ---------------------------------------------------------------------------
//
// The i915 driver publishes one perf event per engine class
// (`rcs0-busy`, `bcs0-busy`, ...), each counting the nanoseconds that engine
// spent executing *any* client's work. Reading them needs `CAP_PERFMON` and
// nothing else, which is why `intel_gpu_top` and KDE's ksystemstats use them.
//
// The sysfs descriptors, not a hardcoded table, define what is available:
// `/sys/bus/event_source/devices/<pmu>/events/<engine>-busy` holds the perf
// `config` value and its sibling `.unit` file says `ns`. An event whose unit is
// not nanoseconds (a residency counter, an MHz clock, an interrupt count) is
// not engine time and must never be summed into utilisation.

/// Parse a perf event descriptor such as `config=0x1000`.
///
/// Only the documented i915 shape is accepted. An unknown ABI (a different
/// driver, a future format) yields `None` so the caller keeps the fdinfo
/// reading instead of inventing a counter value.
pub fn parse_pmu_event_config(content: &str) -> Option<u64> {
    let (key, value) = content.trim().split_once('=')?;
    if key.trim() != "config" {
        return None;
    }
    let value = value.trim();
    let hex = value.strip_prefix("0x").or_else(|| value.strip_prefix("0X"))?;
    if hex.is_empty() || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    u64::from_str_radix(hex, 16).ok()
}

/// Cache key for one engine of one card: `<pci-slot>#<engine>`.
///
/// The slot comes first so the key stays readable in the cache file and the
/// `#` cannot appear in either half.
pub fn pmu_state_key(pci_slot: &str, engine: &str) -> PdevKey {
    PdevKey(format!("{}#{}", pci_slot.trim().to_ascii_lowercase(), engine.trim()))
}

/// Fold per-engine rates into one rate per card: the busiest engine.
///
/// Render and copy execute in parallel, so their busy times can overlap and
/// must not be added (that would report 160 % on a fully loaded GPU). The
/// busiest engine is what actually saturates first.
pub fn fold_engine_rates_by_slot(rates: &HashMap<PdevKey, f64>) -> HashMap<PdevKey, f64> {
    let mut folded: HashMap<PdevKey, f64> = HashMap::new();
    for (key, usage) in rates {
        let slot = key.as_str().split('#').next().unwrap_or(key.as_str());
        let entry = folded.entry(PdevKey::from(slot)).or_insert(0.0);
        if *usage > *entry {
            *entry = *usage;
        }
    }
    folded
}

/// Extract the PCI slot (`dddd:bb:dd.f`) named by a sysfs path.
///
/// The i915 PMU usually sits on a slotless platform device, in which case there
/// is nothing to derive. Drivers that name their PMU after the device either
/// keep the colon form or replace them with underscores (`xe_0000_00_02.0`), so
/// both are accepted and normalised.
pub fn pci_slot_from_device_path(path: &str) -> Option<String> {
    path.split('/').find_map(pci_slot_in_segment)
}

fn pci_slot_in_segment(segment: &str) -> Option<String> {
    let bytes = segment.as_bytes();
    if bytes.len() < 12 {
        return None;
    }
    for start in 0..=(bytes.len() - 12) {
        let window = &segment[start..start + 12];
        let w = window.as_bytes();
        let separators_match =
            (w[4] == b':' || w[4] == b'_') && w[7] == w[4] && w[10] == b'.';
        if !separators_match {
            continue;
        }
        let digits_match = (0..12)
            .filter(|i| *i != 4 && *i != 7 && *i != 10)
            .all(|i| w[i].is_ascii_hexdigit());
        if !digits_match {
            continue;
        }
        let mut out = String::with_capacity(12);
        for (i, c) in window.bytes().enumerate() {
            out.push(match i {
                4 | 7 => ':',
                10 => '.',
                _ => (c as char).to_ascii_lowercase(),
            });
        }
        return Some(out);
    }
    None
}

/// Bind a single-instance PMU to a card, but only when that is unambiguous.
///
/// Picking one of several Intel GPUs arbitrarily would attribute one card's
/// busy time to another. With no usable identity sysfs the reading is dropped,
/// and the caller keeps the fdinfo one.
pub fn bind_single_card(cards: &[String]) -> Option<String> {
    match cards {
        [only] => Some(only.clone()),
        _ => None,
    }
}

/// Whether a cached counter sample is recent enough to turn into a rate.
///
/// `usage = busy_delta / wall_delta` assumes the caller polls at a steady
/// cadence. A cache an hour old would divide a busy GPU by an hour of wall time
/// and report ~0 %, so a stale sample is “no measurement”, not a rate.
pub fn state_is_fresh(prev_epoch_ms: u64, now_epoch_ms: u64, max_age_ms: u64) -> bool {
    now_epoch_ms >= prev_epoch_ms && now_epoch_ms - prev_epoch_ms <= max_age_ms
}

// ---------------------------------------------------------------------------
// Cross-process state
// ---------------------------------------------------------------------------
//
// `astral-plasma metrics` is executed fresh on every shell tick, so the previous
// counters cannot live in memory: they are written to a small cache file (the
// same reason the CPU sampler persists `/dev/shm/astral_cpu_stat`). The format is
// one timestamp line followed by `<pdev> <busy_ns>` lines - readable, diffable,
// and cheap enough to rewrite a few times per second.

/// Serialise counters as `<epoch_ms>\n<pdev> <busy_ns>\n...`.
pub fn encode_engine_state(epoch_ms: u64, busy: &HashMap<PdevKey, u64>) -> String {
    let mut keys: Vec<&PdevKey> = busy.keys().collect();
    keys.sort_by(|a, b| a.as_str().cmp(b.as_str()));
    let mut out = format!("{}\n", epoch_ms);
    for key in keys {
        out.push_str(&format!("{} {}\n", key.as_str(), busy[key]));
    }
    out
}

/// Parse a state file written by [`encode_engine_state`].
///
/// A corrupt timestamp invalidates the whole cache (deltas would be nonsense).
/// A corrupt *device* line is dropped on its own, so a half-flushed write costs
/// one device for one tick instead of every device.
pub fn parse_engine_state(content: &str) -> Option<(u64, HashMap<PdevKey, u64>)> {
    let mut lines = content.lines();
    let epoch_ms = lines.next()?.trim().parse::<u64>().ok()?;
    let mut busy = HashMap::new();
    for line in lines {
        let mut parts = line.split_whitespace();
        let (Some(pdev), Some(ns)) = (parts.next(), parts.next()) else { continue };
        let Ok(ns) = ns.parse::<u64>() else { continue };
        busy.insert(PdevKey::from(pdev), ns);
    }
    Some((epoch_ms, busy))
}

/// Utilisation of every device present in both samples.
///
/// Devices absent from either side get no entry: a GPU whose client just started
/// has no rate yet, and reporting `0.0` would look like "measured idle" when
/// nothing was measured at all.
pub fn rates_from_state(
    prev_epoch_ms: u64,
    prev: &HashMap<PdevKey, u64>,
    now_epoch_ms: u64,
    now: &HashMap<PdevKey, u64>,
) -> HashMap<PdevKey, f64> {
    let mut rates = HashMap::new();
    if now_epoch_ms <= prev_epoch_ms {
        return rates;
    }
    let wall_ns = (now_epoch_ms - prev_epoch_ms).saturating_mul(1_000_000);
    for (pdev, busy_now) in now {
        let Some(busy_prev) = prev.get(pdev) else { continue };
        if *busy_now < *busy_prev {
            continue;
        }
        rates.insert(pdev.clone(), gpu_usage_percent(busy_now - busy_prev, wall_ns));
    }
    rates
}
