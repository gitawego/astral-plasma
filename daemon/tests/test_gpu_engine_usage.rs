//! GPU utilisation must be measured, not inferred from clock frequency.
//!
//! The dashboard used to derive an Intel GPU's "usage" from `gt_act_freq_mhz`,
//! i.e. the fraction of the way between the minimum and maximum clock. On a
//! 240 Hz panel the governor parks near the maximum clock almost continuously,
//! so an idle GPU reported 60–100 % while its render engine was ~5 % busy. The
//! number was a frequency ratio wearing a utilisation label.
//!
//! Real engine time is available unprivileged: every DRM client's
//! `/proc/<pid>/fdinfo/<fd>` carries `drm-pdev` (which GPU) and
//! `drm-engine-<name>: <ns>` (busy nanoseconds). These tests pin the parser and
//! the delta accounting that turn those counters into a percentage.

use astral_plasma::domain::gpu_engine::{
    EngineSample, PdevKey, aggregate_engine_busy, encode_engine_state, gpu_usage_percent,
    parse_engine_state, parse_fdinfo_engine_busy, pdev_matches_pci_slot, rates_from_state,
};
use std::collections::HashMap;

#[test]
fn parses_engine_busy_nanoseconds_and_device() {
    let fdinfo = "\
pos:\t0
flags:\t02100002
mnt_id:\t25
ino:\t1234
drm-client-id:\t207
drm-pdev:\t0000:00:02.0
drm-engine-render:\t123456789 ns
drm-engine-copy:\t0 ns
drm-engine-video:\t42 ns
";
    let sample = parse_fdinfo_engine_busy(fdinfo).expect("a DRM client must parse");
    assert_eq!(sample.pdev, "0000:00:02.0");
    assert_eq!(sample.render_ns, 123_456_789);
    assert_eq!(sample.copy_ns, 0);
    assert_eq!(sample.video_ns, 42);
}

#[test]
fn non_drm_fdinfo_is_ignored() {
    // A plain pipe/eventfd must not be mistaken for a GPU client.
    assert!(parse_fdinfo_engine_busy("pos:\t0\nflags:\t02\nmnt_id:\t25\n").is_none());
    // Engines present but no device: not attributable, so not a usable sample.
    assert!(parse_fdinfo_engine_busy("drm-engine-render:\t5 ns\n").is_none());
}

#[test]
fn malformed_engine_lines_do_not_panic_or_flip_sign() {
    let fdinfo = "\
drm-pdev:\t0000:00:02.0
drm-engine-render:\tgarbage ns
drm-engine-copy:\t-9 ns
";
    let sample = parse_fdinfo_engine_busy(fdinfo).expect("device line is enough to be a GPU client");
    assert_eq!(sample.render_ns, 0, "unparseable counters read as zero, never as a bogus value");
    assert_eq!(sample.copy_ns, 0, "a negative counter is nonsense and must not survive");
}

#[test]
fn busy_total_is_the_busiest_engine() {
    // /proc/<pid>/fdinfo carries several fds per DRM client that all report the
    // same client-wide engine totals. Summing them would multiply the load by
    // the fd count; the engine busy time of a client is the max across its fds.
    let s1 = EngineSample { pdev: PdevKey::from("0000:00:02.0"), render_ns: 1000, copy_ns: 20, video_ns: 0 };
    let s2 = EngineSample { pdev: PdevKey::from("0000:00:02.0"), render_ns: 1000, copy_ns: 20, video_ns: 0 };
    let s3 = EngineSample { pdev: PdevKey::from("0000:00:02.0"), render_ns: 400, copy_ns: 900, video_ns: 0 };
    assert_eq!(s1.busy_total_ns(), 1000);
    assert_eq!(s3.busy_total_ns(), 900, "the busiest engine is what saturates first");
    let (render, busy) = aggregate_engine_busy(&[s1, s2, s3]);
    assert_eq!(render, 1000);
    assert_eq!(busy, 1000);
}

#[test]
fn percentage_is_clamped_and_wall_time_bounded() {
    // 1 s of GPU work over a 2 s window is 50 %.
    assert!((gpu_usage_percent(1_000_000_000, 2_000_000_000) - 0.5).abs() < 1e-9);
    // A counter that wraps or restarts must not produce a negative or >100 %.
    assert_eq!(gpu_usage_percent(0, 0), 0.0);
    assert_eq!(gpu_usage_percent(5_000_000_000, 1_000_000_000), 1.0);
    assert_eq!(gpu_usage_percent(u64::MAX, 1_000_000), 1.0);
}

#[test]
fn pci_slot_matching_tolerates_domain_prefix_forms() {
    // uevent gives "0000:00:02.0"; fdinfo and lspci may drop the domain.
    assert!(pdev_matches_pci_slot("0000:00:02.0", "0000:00:02.0"));
    assert!(pdev_matches_pci_slot("0000:00:02.0", "00:02.0"));
    assert!(pdev_matches_pci_slot("00:02.0", "0000:00:02.0"));
    // Case-insensitive hex, and the neighbouring function is a different device.
    assert!(pdev_matches_pci_slot("0000:00:02.0", "0000:00:02.0".to_uppercase().as_str()));
    assert!(!pdev_matches_pci_slot("0000:00:02.0", "0000:01:00.0"));
    assert!(!pdev_matches_pci_slot("0000:00:02.0", "0000:00:02.1"));
    // An empty slot must never match everything.
    assert!(!pdev_matches_pci_slot("0000:00:02.0", ""));
    assert!(!pdev_matches_pci_slot("", ""));
}

#[test]
fn engine_surfaces_win_over_the_frequency_ratio() {
    // The integration rule the adapter follows: measured busy time wins; the
    // clock ratio is only a last resort when no DRM client could be read.
    use astral_plasma::domain::gpu_engine::resolve_usage;
    assert!((resolve_usage(Some(0.04), 1.0) - 0.04).abs() < 1e-9,
        "a measured 4 % must not be replaced by the 100 % clock ratio");
    assert_eq!(resolve_usage(None, 1.0), 1.0, "no measurable client falls back to the clock");
    assert_eq!(resolve_usage(None, 0.0), 0.0);
}

// ---------------------------------------------------------------------------
// Persisted state: the shell runs `astral-plasma metrics` as a fresh process
// every tick, so the previous counters must outlive the process (the same
// reason the CPU sampler keeps /dev/shm/astral_cpu_stat).
// ---------------------------------------------------------------------------

fn counters(pairs: &[(&str, u64)]) -> HashMap<PdevKey, u64> {
    pairs
        .iter()
        .map(|(pdev, ns)| (PdevKey::from(*pdev), *ns))
        .collect()
}

#[test]
fn state_round_trips_through_the_cache_file() {
    let map = counters(&[("0000:00:02.0", 1_234_567_890), ("0000:01:00.0", 42)]);
    let encoded = encode_engine_state(1_700_000_000_000, &map);
    let (ts, decoded) = parse_engine_state(&encoded).expect("our own format must parse");
    assert_eq!(ts, 1_700_000_000_000);
    assert_eq!(decoded, map);
}

#[test]
fn corrupt_or_truncated_state_is_ignored_not_trusted() {
    assert!(parse_engine_state("").is_none());
    assert!(parse_engine_state("not-a-number 0000:00:02.0 5").is_none());
    // A half-written line loses only that device; the rest of the cache is still
    // usable, which keeps a crashed writer from blinding the probe for a tick.
    let (ts, map) = parse_engine_state("1700000000000\n0000:00:02.0 100\n0000:01:00.0 garbage\n").unwrap();
    assert_eq!(ts, 1_700_000_000_000);
    assert_eq!(map.get(&PdevKey::from("0000:00:02.0")), Some(&100));
    assert!(map.get(&PdevKey::from("0000:01:00.0")).is_none());
}

#[test]
fn rates_compare_only_devices_present_in_both_samples() {
    let prev = counters(&[("0000:00:02.0", 1_000_000_000), ("0000:01:00.0", 5)]);
    let now = counters(&[("0000:00:02.0", 1_500_000_000), ("0000:02:00.0", 9)]);
    // 500 ms of extra work over a 1 s window for the iGPU.
    let rates = rates_from_state(1_000, &prev, 2_000, &now);
    let igpu = rates.get(&PdevKey::from("0000:00:02.0")).copied().unwrap();
    assert!((igpu - 0.5).abs() < 1e-9);
    // A device that only appears now has no rate yet (not 0 %, not 100 %).
    assert!(!rates.contains_key(&PdevKey::from("0000:02:00.0")));
    // A device that vanished is simply absent.
    assert!(!rates.contains_key(&PdevKey::from("0000:01:00.0")));
}

#[test]
fn counter_restart_reads_as_no_measurement() {
    // Process re-exec resets fdinfo counters; that is not a negative load.
    let prev = counters(&[("0000:00:02.0", 5_000_000_000)]);
    let now = counters(&[("0000:00:02.0", 1)]);
    let rates = rates_from_state(1_000, &prev, 2_000, &now);
    assert!(!rates.contains_key(&PdevKey::from("0000:00:02.0")));
}

#[test]
fn non_monotonic_timestamps_yield_nothing() {
    let prev = counters(&[("0000:00:02.0", 10)]);
    let now = counters(&[("0000:00:02.0", 20)]);
    // Clock went backwards or the samples are the same instant: no rate.
    assert!(rates_from_state(2_000, &prev, 2_000, &now).is_empty());
    assert!(rates_from_state(2_000, &prev, 1_000, &now).is_empty());
}
