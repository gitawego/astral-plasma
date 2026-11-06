//! GT-wide GPU busy time from the driver's perf PMU.
//!
//! `/proc/<pid>/fdinfo` measures *visible* DRM clients (see
//! [`crate::infrastructure::gpu_engine_probe`]). It cannot see the compositor:
//! `kwin_wayland` is installed with `cap_sys_nice=ep` file capabilities, the
//! kernel therefore marks it non-dumpable, and every `/proc/<kwin_pid>/fdinfo`
//! read answers `EACCES` to anyone below `CAP_SYS_PTRACE`. On a
//! 2560x1600@240Hz panel that missing client was half the load - a saturated
//! iGPU read as 46 % while `rc6_residency_ms` never advanced.
//!
//! The i915 perf PMU counts engine busy nanoseconds for the whole GT, whoever
//! submits the work. Reading it needs `CAP_PERFMON` (not root, not debugfs);
//! that is the same source `intel_gpu_top` and KDE's `ksystemstats_intel_helper`
//! report from.
//!
//! Two ways to get the counter, in this order:
//!
//! 1. **In process** - when the binary itself carries `CAP_PERFMON`.
//! 2. **A privileged helper** - file capabilities are ignored on a `nosuid`
//!    mount, so a copy installed outside one
//!    (`/usr/local/libexec/astral-plasma/astral-plasma`, set up by
//!    `make gpu-pmu-perms`) answers `gpu-pmu-counters` over stdout in the very
//!    same format as the state cache.
//!
//! When neither is available the caller keeps the fdinfo reading: a lower
//! bound is better than a fabricated number, and nothing here ever guesses.
//!
//! The `xe` driver publishes engine ticks rather than nanoseconds, and
//! converting them needs the tick period. Until that is measured, `xe` cards
//! stay on fdinfo: [`parse_pmu_event_config`] rejects descriptors whose unit is
//! not `ns`, so they contribute nothing instead of a wrong value.

use crate::domain::gpu_engine::{
    bind_single_card, encode_engine_state, fold_engine_rates_by_slot, parse_engine_state,
    parse_pmu_event_config, pci_slot_from_device_path, pmu_state_key, rates_from_state,
    state_is_fresh, PdevKey,
};
use crate::infrastructure::gpu_engine_probe::MAX_SAMPLE_AGE_MS;
use std::collections::HashMap;
use std::io;
use std::os::unix::io::RawFd;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Where the kernel advertises perf PMUs.
pub const PMU_ROOT: &str = "/sys/bus/event_source/devices";
/// Where the kernel advertises DRM cards.
pub const DRM_ROOT: &str = "/sys/class/drm";
/// The privileged helper `make gpu-pmu-perms` installs outside the checkout.
pub const HELPER_PATH: &str = "/usr/local/libexec/astral-plasma/astral-plasma";

/// One perf event of one PMU: an engine class and its perf `config` value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PmuEngineEvent {
    pub engine: String,
    pub config: u64,
}

/// A perf PMU that exposes engine busy counters, as sysfs describes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PmuDevice {
    /// sysfs name, e.g. `i915`.
    pub pmu: String,
    /// The perf event type to pass to `perf_event_open`.
    pub counter_type: u32,
    /// Engine busy events only, sorted by engine name.
    pub events: Vec<PmuEngineEvent>,
}

/// How the GT counters will be read this tick.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CounterSource {
    /// `perf_event_open` succeeded in this process.
    InProcess,
    /// A pre-installed binary that carries `CAP_PERFMON` itself.
    Helper(PathBuf),
    /// Nothing privileged: the caller falls back to fdinfo.
    Unavailable,
}

impl CounterSource {
    pub fn label(&self) -> String {
        match self {
            Self::InProcess => "i915 PMU (CAP_PERFMON)".to_string(),
            Self::Helper(path) => format!("i915 PMU via {}", path.display()),
            Self::Unavailable => "DRM fdinfo".to_string(),
        }
    }
}

// ---------------------------------------------------------------------------
// sysfs discovery (pure: takes the root, so tests use a fake tree)
// ---------------------------------------------------------------------------

/// Discover every perf PMU whose descriptors we understand.
///
/// Intel candidates only (`i915`, plus `xe` whose numeric events we filter
/// out): opening other devices' events would be meaningless.
pub fn read_pmu_devices(root: &Path) -> Vec<PmuDevice> {
    read_pmu_devices_from(root)
}

/// [`read_pmu_devices`] against an injected sysfs root.
pub fn read_pmu_devices_from(root: &Path) -> Vec<PmuDevice> {
    let Ok(entries) = std::fs::read_dir(root) else {
        return Vec::new();
    };
    let mut devices: Vec<PmuDevice> = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !(name == "i915" || name.starts_with("i915_") || name.starts_with("xe")) {
            continue;
        }
        if let Some(device) = read_pmu_device(root, &name) {
            devices.push(device);
        }
    }
    devices.sort_by(|a, b| a.pmu.cmp(&b.pmu));
    devices
}

fn read_pmu_device(root: &Path, name: &str) -> Option<PmuDevice> {
    let dir = root.join(name);
    let counter_type = std::fs::read_to_string(dir.join("type"))
        .ok()?
        .trim()
        .parse::<u32>()
        .ok()?;
    if counter_type == 0 {
        return None;
    }

    let mut events: Vec<PmuEngineEvent> = Vec::new();
    for entry in std::fs::read_dir(dir.join("events")).ok()?.flatten() {
        let file = entry.file_name().to_string_lossy().to_string();
        let Some(engine) = file.strip_suffix("-busy") else { continue };
        // Only nanosecond counters are engine busy time. A residency counter or
        // an interrupt count shares the `-busy` naming nowhere, but the unit
        // check is what actually keeps the numbers honest.
        let unit = std::fs::read_to_string(dir.join("events").join(format!("{file}.unit")))
            .unwrap_or_default();
        if unit.trim() != "ns" {
            continue;
        }
        let content = std::fs::read_to_string(entry.path()).unwrap_or_default();
        let Some(config) = parse_pmu_event_config(&content) else { continue };
        events.push(PmuEngineEvent { engine: engine.to_string(), config });
    }
    if events.is_empty() {
        return None;
    }
    events.sort_by(|a, b| a.engine.cmp(&b.engine));
    Some(PmuDevice { pmu: name.to_string(), counter_type, events })
}

/// PCI slots of the cards driven by i915, in sysfs order.
pub fn i915_card_slots() -> Vec<String> {
    i915_card_slots_from(Path::new(DRM_ROOT))
}

/// [`i915_card_slots`] against an injected `/sys/class/drm`.
pub fn i915_card_slots_from(drm_root: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(drm_root) else {
        return Vec::new();
    };
    let mut slots: Vec<String> = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        // `card0` is a card; `card0-DP-1` is a connector on it.
        if !name.starts_with("card") || name.contains('-') {
            continue;
        }
        let uevent = std::fs::read_to_string(entry.path().join("device").join("uevent"))
            .unwrap_or_default();
        let (mut driver, mut slot) = (String::new(), String::new());
        for line in uevent.lines() {
            if let Some((key, value)) = line.split_once('=') {
                match key.trim() {
                    "DRIVER" => driver = value.trim().to_string(),
                    "PCI_SLOT_NAME" => slot = value.trim().to_ascii_lowercase(),
                    _ => {}
                }
            }
        }
        // `xe` exposes ticks, not nanoseconds, so its cards keep the fdinfo path.
        if driver == "i915" && !slot.is_empty() && !slots.contains(&slot) {
            slots.push(slot);
        }
    }
    slots.sort();
    slots
}

/// Which card a PMU belongs to, or `None` when sysfs cannot say.
///
/// The slot in the PMU's own path is authoritative. Otherwise a single i915
/// card is implied; several of them are not guessed between.
pub fn resolve_pmu_card(pmu_path: &str, i915_slots: &[String]) -> Option<String> {
    if let Some(slot) = pci_slot_from_device_path(pmu_path) {
        return if i915_slots.iter().any(|s| s == &slot) { Some(slot) } else { None };
    }
    bind_single_card(i915_slots)
}

// ---------------------------------------------------------------------------
// perf_event_open
// ---------------------------------------------------------------------------

/// `struct perf_event_attr` up to `PERF_ATTR_SIZE_VER0` (64 bytes).
///
/// Only the prefix every perf-capable kernel understands is passed, so the
/// call does not depend on the `libc` crate's struct being the same width as
/// this kernel's ABI (a too-large `size` is rejected with `E2BIG`).
#[repr(C)]
#[derive(Default)]
struct PerfEventAttr {
    type_: u32,
    size: u32,
    config: u64,
    sample_period: u64,
    sample_type: u64,
    read_format: u64,
    flags: u64,
    wakeup: u32,
    bp_type: u32,
    config1: u64,
}

const PERF_ATTR_SIZE_VER0: u32 = 64;
const PERF_FLAG_FD_CLOEXEC: libc::c_ulong = 1 << 3;

/// Open one PMU counter system-wide (`pid = -1, cpu = 0`).
///
/// The i915 events are uncore counters, not per-task sampling, so any CPU
/// serves. `CAP_PERFMON` (or root) is required by `perf_event_paranoid`; a
/// refusal surfaces as `PermissionDenied` and the caller falls back.
pub fn perf_event_open(counter_type: u32, config: u64) -> io::Result<RawFd> {
    let mut attr = PerfEventAttr {
        type_: counter_type,
        size: PERF_ATTR_SIZE_VER0,
        config,
        // Counting, not sampling: a read returns the accumulated value.
        read_format: 0,
        flags: 0,
        ..Default::default()
    };

    let fd = unsafe {
        libc::syscall(
            libc::SYS_perf_event_open,
            &mut attr as *mut PerfEventAttr,
            -1i32,
            0i32,
            -1i32,
            PERF_FLAG_FD_CLOEXEC,
        )
    };
    if fd < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(fd as RawFd)
    }
}

fn read_counter(fd: RawFd) -> io::Result<u64> {
    let mut buf = [0u8; std::mem::size_of::<u64>()];
    let n = unsafe { libc::read(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len()) };
    if n != buf.len() as isize {
        return Err(io::Error::last_os_error());
    }
    Ok(u64::from_ne_bytes(buf))
}

/// Read every engine counter of every bound PMU.
///
/// `None` means "nothing could be read" (no PMU, no permission, no card), and
/// the caller must not present that as an idle GPU.
fn in_process_sample() -> Option<(u64, HashMap<PdevKey, u64>)> {
    let devices = read_pmu_devices(Path::new(PMU_ROOT));
    if devices.is_empty() {
        return None;
    }
    let slots = i915_card_slots();
    let mut busy: HashMap<PdevKey, u64> = HashMap::new();

    for device in &devices {
        let pmu_dir = Path::new(PMU_ROOT).join(&device.pmu);
        let pmu_path = std::fs::canonicalize(&pmu_dir)
            .unwrap_or(pmu_dir)
            .to_string_lossy()
            .to_string();
        let Some(slot) = resolve_pmu_card(&pmu_path, &slots) else { continue };

        for event in &device.events {
            let Ok(fd) = perf_event_open(device.counter_type, event.config) else {
                // Denied (no CAP_PERFMON) or the event vanished: try the next
                // one; a partial engine list is still a real measurement.
                continue;
            };
            let value = read_counter(fd).ok();
            unsafe { libc::close(fd) };
            if let Some(value) = value {
                busy.insert(pmu_state_key(&slot, &event.engine), value);
            }
        }
    }

    if busy.is_empty() {
        return None;
    }
    Some((now_ms(), busy))
}

/// One counter sample formatted exactly like the state cache.
///
/// `astral-plasma gpu-pmu-counters` prints this; the probe feeds the same text
/// through the same parser, so the helper needs no protocol of its own.
pub fn counters_state_line() -> Option<String> {
    in_process_sample().map(|(epoch_ms, busy)| encode_engine_state(epoch_ms, &busy))
}

// ---------------------------------------------------------------------------
// state cache + rates
// ---------------------------------------------------------------------------

/// Where the previous PMU counters are kept.
///
/// Separate from the fdinfo cache: the two sources count different things, and
/// mixing their values in one file would produce nonsense deltas.
pub fn pmu_state_path() -> PathBuf {
    if Path::new("/dev/shm").exists() {
        PathBuf::from("/dev/shm/astral_gpu_pmu")
    } else {
        std::env::temp_dir().join("astral_gpu_pmu")
    }
}

/// The privileged helper, if one is installed.
pub fn helper_binary() -> Option<PathBuf> {
    if let Ok(configured) = std::env::var("ASTRAL_GPU_COUNTERS_BIN") {
        let path = PathBuf::from(configured);
        if path.is_file() {
            return Some(path);
        }
    }
    let installed = PathBuf::from(HELPER_PATH);
    installed.is_file().then_some(installed)
}

/// Pick how to read the counters, given what this tick already knows.
pub fn choose_counter_source(in_process_available: bool, helper: Option<PathBuf>) -> CounterSource {
    if in_process_available {
        CounterSource::InProcess
    } else if let Some(path) = helper {
        CounterSource::Helper(path)
    } else {
        CounterSource::Unavailable
    }
}

/// Which source a measurement would use right now, without taking one.
///
/// Used by `doctor`, where the point is to answer "why does my GPU number look
/// wrong" without running a full metrics tick.
pub fn active_counter_source() -> CounterSource {
    let devices = read_pmu_devices(Path::new(PMU_ROOT));
    let can_open = devices.iter().any(|device| {
        device.events.iter().any(|event| {
            match perf_event_open(device.counter_type, event.config) {
                Ok(fd) => {
                    unsafe { libc::close(fd) };
                    true
                }
                Err(_) => false,
            }
        })
    });
    choose_counter_source(can_open, helper_binary())
}

/// Run the privileged helper and parse its counters.
pub fn counters_from_helper(path: &Path) -> Option<(u64, HashMap<PdevKey, u64>)> {
    let output = Command::new(path).arg("gpu-pmu-counters").output().ok()?;
    if !output.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let (epoch_ms, busy) = parse_engine_state(&stdout)?;
    if busy.is_empty() {
        return None;
    }
    Some((epoch_ms, busy))
}

/// GT-wide utilisation per card for this invocation, folded to the busiest
/// engine. Empty means "nothing measurable yet"; the caller then keeps its
/// previous value or falls back to fdinfo.
pub fn measure_pmu_usage(state_path: &Path) -> HashMap<PdevKey, f64> {
    let direct = in_process_sample();
    let source = choose_counter_source(direct.is_some(), helper_binary());
    let sample = match source {
        CounterSource::InProcess => direct,
        CounterSource::Helper(path) => counters_from_helper(&path),
        CounterSource::Unavailable => None,
    };
    let Some((now_epoch_ms, busy)) = sample else {
        return HashMap::new();
    };

    let previous = std::fs::read_to_string(state_path)
        .ok()
        .and_then(|content| parse_engine_state(&content));

    let temp = state_path.with_extension("tmp");
    if std::fs::write(&temp, encode_engine_state(now_epoch_ms, &busy)).is_ok() {
        let _ = std::fs::rename(&temp, state_path);
    }

    let Some((prev_epoch_ms, prev)) = previous else { return HashMap::new() };
    if !state_is_fresh(prev_epoch_ms, now_epoch_ms, MAX_SAMPLE_AGE_MS) {
        return HashMap::new();
    }
    fold_engine_rates_by_slot(&rates_from_state(prev_epoch_ms, &prev, now_epoch_ms, &busy))
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
