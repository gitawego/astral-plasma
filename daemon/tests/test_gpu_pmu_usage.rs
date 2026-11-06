//! GPU utilisation from the i915 GT perf counter, with fdinfo as the fallback.
//!
//! `/proc/<pid>/fdinfo` measures *visible clients*. KWin is started with
//! `cap_sys_nice=ep` file capabilities, which makes the kernel mark it
//! non-dumpable, so `/proc/<kwin_pid>/fdinfo` answers EACCES to every reader
//! below `CAP_SYS_PTRACE`. The compositor is therefore invisible to every
//! fdinfo scanner - Astral and Mission Center both missed ~half of a saturated
//! iGPU on a 2560x1600@240Hz panel while `rc6_residency_ms` never left zero.
//!
//! The GT-wide counter the kernel publishes through the i915 perf PMU
//! (`rcs0-busy` etc.) counts *all* clients, needs only `CAP_PERFMON`, and is
//! what `intel_gpu_top` and KDE's ksystemstats report. These tests pin the
//! descriptor parsing, device binding, delta accounting, and the precedence
//! rule (GT counter > per-client fdinfo > driver fallback) without touching a
//! live perf fd, so the suite runs unprivileged.

use astral_plasma::domain::gpu_engine::{
    PdevKey, bind_single_card, fold_engine_rates_by_slot, parse_pmu_event_config,
    pci_slot_from_device_path, pmu_state_key, rates_from_state, resolve_usage,
    resolve_usage_staged, state_is_fresh,
};
use astral_plasma::infrastructure::gpu_pmu_probe::{
    CounterSource, choose_counter_source, counters_from_helper, i915_card_slots_from,
    perf_event_open, read_pmu_devices, read_pmu_devices_from,
};
use std::collections::HashMap;
use std::io::Write;
use std::path::Path;

// ---------------------------------------------------------------------------
// sysfs descriptors
// ---------------------------------------------------------------------------

#[test]
fn i915_event_descriptor_is_parsed() {
    // `/sys/bus/event_source/devices/i915/events/rcs0-busy` is a file holding
    // one `config=` line; the engine busy events are the ones whose sibling
    // `.unit` says `ns`.
    assert_eq!(parse_pmu_event_config("config=0x0\n"), Some(0x0));
    assert_eq!(parse_pmu_event_config("config=0x1000"), Some(0x1000));
    assert_eq!(parse_pmu_event_config("config=0x100004\n"), Some(0x100004));
    // Surrounding whitespace/trailing junk must not shift the value.
    assert_eq!(parse_pmu_event_config("  config = 0x2010 \n"), Some(0x2010));
}

#[test]
fn unknown_event_descriptor_shapes_are_not_guessed() {
    // A driver whose ABI we do not understand must fall through to fdinfo
    // rather than contribute an invented counter value.
    assert_eq!(parse_pmu_event_config(""), None);
    assert_eq!(parse_pmu_event_config("config="), None);
    assert_eq!(parse_pmu_event_config("config=0xZZ"), None);
    assert_eq!(parse_pmu_event_config("foo=1"), None);
    assert_eq!(parse_pmu_event_config("event=0x0,instance=0x0"), None);
}

#[test]
fn discovery_reads_only_nanosecond_engine_busy_events() {
    let dir = tempfile::tempdir().unwrap();
    write_pmu_tree(dir.path());

    let devices = read_pmu_devices_from(dir.path());
    assert_eq!(devices.len(), 1, "one i915 PMU");
    let i915 = &devices[0];
    assert_eq!(i915.pmu, "i915");
    assert_eq!(i915.counter_type, 14);

    let engines: Vec<&str> = i915.events.iter().map(|e| e.engine.as_str()).collect();
    assert_eq!(engines, vec!["bcs0", "rcs0"], "engine busy counters only, sorted");
    // rc6-residency/interrupts are ns/file-descriptors too, but not engine busy
    // time; actual-frequency is not nanoseconds. Counting them would inflate or
    // corrupt the utilisation.
    assert_eq!(i915.events[1].config, 0x0);
    assert_eq!(i915.events[0].config, 0x1000);
}

#[test]
fn a_pmu_without_a_usable_type_is_skipped() {
    let dir = tempfile::tempdir().unwrap();
    write_pmu_tree(dir.path());
    std::fs::write(dir.path().join("i915").join("type"), "not-a-number\n").unwrap();
    assert!(read_pmu_devices_from(dir.path()).is_empty(),
        "an unreadable perf type cannot open a counter, so the device is skipped");
}

#[test]
fn live_sysfs_exposes_the_i915_busy_events() {
    // Runs on the developer's machine: if an i915 PMU exists here, discovery
    // must find its render engine with a real perf type. Absent (AMD, NVIDIA
    // only, CI) is not a failure - the fdinfo path covers those.
    let root = Path::new("/sys/bus/event_source/devices");
    if !root.join("i915").exists() {
        return;
    }
    let devices = read_pmu_devices(root);
    let i915 = devices.iter().find(|d| d.pmu == "i915");
    let i915 = i915.expect("i915 PMU present on this machine must be discovered");
    assert!(i915.counter_type > 0);
    assert!(i915.events.iter().any(|e| e.engine == "rcs0"),
        "the render engine class must be among the discovered busy counters");
}

// ---------------------------------------------------------------------------
// device binding
// ---------------------------------------------------------------------------

#[test]
fn pci_slot_is_extracted_from_sysfs_paths() {
    assert_eq!(pci_slot_from_device_path("/sys/devices/pci0000:00/0000:00:02.0").as_deref(),
        Some("0000:00:02.0"));
    // Some DRM platform devices spell the slot with underscores instead of
    // colons (xe names its PMU after the device).
    assert_eq!(pci_slot_from_device_path("/sys/bus/event_source/devices/xe_0000_00_02.0").as_deref(),
        Some("0000:00:02.0"));
    // The i915 PMU lives on a slotless platform device: nothing to derive.
    assert_eq!(pci_slot_from_device_path("/sys/devices/i915"), None);
    assert_eq!(pci_slot_from_device_path(""), None);
}

#[test]
fn pmu_binds_to_the_only_i915_card_or_not_at_all() {
    // Ambiguous bindings would attribute one GPU's busy time to another, so a
    // multi-GPU machine without a slot in the PMU path gets no PMU reading and
    // keeps the (safe, partial) fdinfo one.
    assert_eq!(bind_single_card(&["0000:00:02.0".to_string()]).as_deref(), Some("0000:00:02.0"));
    assert_eq!(bind_single_card(&[]), None);
    assert_eq!(bind_single_card(&["0000:00:02.0".to_string(), "0000:03:00.0".to_string()]), None);
}

#[test]
fn i915_card_slots_come_from_the_driver_uevent() {
    let dir = tempfile::tempdir().unwrap();
    write_drm_tree(dir.path());
    // NVIDIA and connector entries are not i915 cards; a slotless device is
    // dropped instead of being reported as an empty slot.
    assert_eq!(i915_card_slots_from(dir.path()), vec!["0000:00:02.0".to_string()]);
}

// ---------------------------------------------------------------------------
// delta accounting
// ---------------------------------------------------------------------------

#[test]
fn state_keys_name_slot_and_engine_and_fold_to_the_busiest() {
    // The GT counter is per engine; a card's utilisation is its busiest engine
    // (render and copy run in parallel, so summing can exceed wall time).
    let mut rates = HashMap::new();
    rates.insert(pmu_state_key("0000:00:02.0", "rcs0"), 0.30);
    rates.insert(pmu_state_key("0000:00:02.0", "vcs0"), 0.05);
    rates.insert(pmu_state_key("0000:00:02.0", "bcs0"), 0.72);
    rates.insert(pmu_state_key("0000:01:00.0", "rcs0"), 0.10);

    let folded = fold_engine_rates_by_slot(&rates);
    assert!((folded[&PdevKey::from("0000:00:02.0")] - 0.72).abs() < 1e-9);
    assert!((folded[&PdevKey::from("0000:01:00.0")] - 0.10).abs() < 1e-9);
    // The folded keys are bare slots, so the existing slot matcher works.
    assert!(folded.contains_key(&PdevKey::from("0000:00:02.0")));
}

#[test]
fn a_stale_sample_is_dropped_instead_of_diluted() {
    // A minute-old sample divided by a minute of wall time would report ~0 %
    // for a busy GPU; the documented rule is "no measurement" instead.
    assert!(state_is_fresh(1_000, 3_000, 5_000));
    assert!(state_is_fresh(1_000, 1_000, 5_000));
    assert!(!state_is_fresh(1_000, 9_000, 5_000));
    // Timestamps that went backwards are not a measurement either.
    assert!(!state_is_fresh(9_000, 1_000, 5_000));
}

#[test]
fn pmu_state_key_round_trips_through_the_state_file_format() {
    // Reuse of encode/parse keeps one cache format; the key must survive it.
    let mut busy = HashMap::new();
    busy.insert(pmu_state_key("0000:00:02.0", "rcs0"), 1_000);
    busy.insert(pmu_state_key("0000:00:02.0", "bcs0"), 4_000);
    let encoded = astral_plasma::domain::gpu_engine::encode_engine_state(1_700_000_000_000, &busy);
    let (ts, decoded) =
        astral_plasma::domain::gpu_engine::parse_engine_state(&encoded).unwrap();
    assert_eq!(ts, 1_700_000_000_000);
    assert_eq!(decoded, busy);
    let rates = rates_from_state(1_700_000_000_000, &decoded, 1_700_000_001_000, &busy);
    // A key that survives the cache file must also come back out of the rate
    // calculation: unchanged counters are a measured 0 %, not a missing entry.
    assert_eq!(rates[&pmu_state_key("0000:00:02.0", "rcs0")], 0.0);
    assert_eq!(rates[&pmu_state_key("0000:00:02.0", "bcs0")], 0.0);
}

#[test]
fn staged_resolution_prefers_the_complete_gt_counter() {
    // 1. GT counter (all clients, incl. the non-dumpable compositor)
    // 2. per-client fdinfo (visible clients only)
    // 3. driver fallback (Intel clock ratio - a clock, never a measurement)
    assert!((resolve_usage_staged(Some(1.0), Some(0.51), 1.0) - 1.0).abs() < 1e-9,
        "the GT counter must win over an under-counting fdinfo sum");
    assert!((resolve_usage_staged(None, Some(0.51), 1.0) - 0.51).abs() < 1e-9,
        "without CAP_PERFMON the fdinfo sum is still much better than a clock ratio");
    assert_eq!(resolve_usage_staged(None, None, 1.0), 1.0);
    // The single-source rule is unchanged for callers that predate staging.
    assert_eq!(resolve_usage(None, 0.25), 0.25);
}

// ---------------------------------------------------------------------------
// counter sources
// ---------------------------------------------------------------------------

#[test]
fn in_process_counters_win_over_the_helper_binary() {
    // With CAP_PERFMON on the daemon itself (or full root) the perf fd is
    // opened directly: no subprocess per tick.
    let helper_path = std::path::PathBuf::from("/usr/local/libexec/x");
    assert!(matches!(choose_counter_source(true, Some(helper_path.clone())), CounterSource::InProcess));
    // File capabilities cannot be honoured on a nosuid mount (this checkout
    // lives on one), so a pre-installed privileged copy steps in.
    let helper = choose_counter_source(false, Some(helper_path));
    assert!(matches!(helper, CounterSource::Helper(ref p) if p == Path::new("/usr/local/libexec/x")));
    // Nothing privileged available: the caller falls back to fdinfo.
    assert!(matches!(choose_counter_source(false, None), CounterSource::Unavailable));
}

#[test]
fn helper_output_reuses_the_state_file_format() {
    // The helper prints exactly what the state cache holds - one timestamp line
    // then `<slot>#<engine> <ns>` - so no new protocol exists to drift.
    let dir = tempfile::tempdir().unwrap();
    let script = dir.path().join("fake-helper");
    let mut f = std::fs::File::create(&script).unwrap();
    writeln!(f, "#!/bin/sh").unwrap();
    writeln!(f, "printf '1700000000000\\n0000:00:02.0#rcs0 500\\n0000:00:02.0#bcs0 900\\n'").unwrap();
    drop(f);
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();

    let (ts, busy) = counters_from_helper(&script).expect("helper output must parse");
    assert_eq!(ts, 1_700_000_000_000);
    assert_eq!(busy[&pmu_state_key("0000:00:02.0", "bcs0")], 900);
    // A helper that cannot run (missing, not executable, garbage) is "no
    // measurement", never a fabricated zero.
    assert!(counters_from_helper(&dir.path().join("missing")).is_none());
    std::fs::write(&script, "#!/bin/sh\nprintf 'garbage\\n'\n").unwrap();
    assert!(counters_from_helper(&script).is_none());
}

#[test]
fn perf_event_open_plumbing_reads_a_software_counter() {
    // Proves the perf_event_attr layout and the raw syscall are right without
    // CAP_PERFMON: a task-clock software event on our own process is allowed at
    // perf_event_paranoid<=2. Where even that is denied the test skips rather
    // than failing on a hardened host.
    const PERF_TYPE_SOFTWARE: u32 = 1;
    const PERF_COUNT_SW_TASK_CLOCK: u64 = 1;
    let fd = match perf_event_open(PERF_TYPE_SOFTWARE, PERF_COUNT_SW_TASK_CLOCK) {
        Ok(fd) => fd,
        Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => return,
        Err(e) => panic!("perf_event_open must only fail by permission here: {e}"),
    };
    let first = read_counter(fd);
    std::thread::sleep(std::time::Duration::from_millis(60));
    let second = read_counter(fd);
    unsafe { libc::close(fd) };
    assert!(second > first, "a running task clock must advance ({first} -> {second})");
}

#[test]
fn live_i915_counter_is_either_readable_or_blocked_by_capability_alone() {
    // A wrong `type`/`config`/struct size reaches the kernel as EINVAL, E2BIG or
    // ENOENT. Seeing only a permission error proves the descriptor parsing is
    // right and that the sole missing piece is CAP_PERFMON - which is what
    // `make gpu-pmu-perms` grants. Skips on hosts without an i915 PMU.
    let devices = read_pmu_devices(std::path::Path::new("/sys/bus/event_source/devices"));
    let Some(i915) = devices.iter().find(|d| d.pmu == "i915") else { return };
    let event = i915.events.iter().find(|e| e.engine == "rcs0").expect("render engine event");
    match perf_event_open(i915.counter_type, event.config) {
        Ok(fd) => {
            unsafe { libc::close(fd) };
        }
        Err(e) => assert_eq!(
            e.kind(),
            std::io::ErrorKind::PermissionDenied,
            "only a capability may block a correctly described counter, got {e:?}"
        ),
    }
}

fn read_counter(fd: std::os::unix::io::RawFd) -> u64 {
    let mut buf = [0u8; 8];
    let n = unsafe { libc::read(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len()) };
    assert_eq!(n, 8, "a counting perf event reads back one u64");
    u64::from_ne_bytes(buf)
}

// ---------------------------------------------------------------------------
// fake sysfs trees
// ---------------------------------------------------------------------------

fn write_pmu_tree(root: &Path) {
    let pmu = root.join("i915");
    std::fs::create_dir_all(pmu.join("events")).unwrap();
    std::fs::write(pmu.join("type"), "14\n").unwrap();
    for (event, config) in [
        ("rcs0-busy", "config=0x0\n"),
        ("bcs0-busy", "config=0x1000\n"),
        // Not engine busy time: residency, IRQ count, and a clock in MHz.
        ("rc6-residency", "config=0x100003\n"),
        ("rc6-residency.unit", "ns\n"),
        ("interrupts", "config=0x100002\n"),
        ("actual-frequency", "config=0x100000\n"),
        ("actual-frequency.unit", "M\n"),
        ("software-gt-awake-time", "config=0x100004\n"),
        ("software-gt-awake-time.unit", "ns\n"),
    ] {
        std::fs::write(pmu.join("events").join(event), config).unwrap();
    }
    for engine in ["rcs0", "bcs0"] {
        std::fs::write(pmu.join("events").join(format!("{engine}-busy.unit")), "ns\n").unwrap();
    }
    // A second PMU that is not Intel: discovery must not open its events.
    let other = root.join("cpu_thermal");
    std::fs::create_dir_all(other.join("events")).unwrap();
    std::fs::write(other.join("type"), "11\n").unwrap();
}

fn write_drm_tree(root: &Path) {
    // card0: NVIDIA, card1: Intel i915, card2: xe, card1-DP-1: a connector.
    for (card, driver, slot) in [
        ("card0", "nvidia", "0000:01:00.0"),
        ("card1", "i915", "0000:00:02.0"),
        ("card2", "xe", "0000:03:00.0"),
    ] {
        let dev = root.join(card).join("device");
        std::fs::create_dir_all(&dev).unwrap();
        std::fs::write(dev.join("uevent"), format!("DRIVER={driver}\nPCI_SLOT_NAME={slot}\n")).unwrap();
    }
    std::fs::create_dir_all(root.join("card1-DP-1").join("device")).unwrap();
    std::fs::write(
        root.join("card1-DP-1").join("device").join("uevent"),
        "DRIVER=i915\n",
    )
    .unwrap();
}
