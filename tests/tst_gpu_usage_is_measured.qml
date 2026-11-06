import QtQuick

/// The GPU percentage is utilisation, not a clock ratio.
///
/// On a 240 Hz panel the Intel RPS governor parks near `gt_max_freq_mhz` while
/// the render engine is ~5 % busy, so the old "usage" (a normalised clock) read
/// 60–100 % on an idle GPU. The daemon measures engine time in this order:
///
/// 1. the GT-wide i915 perf counter (every client, including the compositor,
///    which is non-dumpable and therefore unreadable through fdinfo),
/// 2. the `/proc/<pid>/fdinfo` sum for hosts without `CAP_PERFMON`,
/// 3. the clock ratio only when neither produced a number.
///
/// This suite pins the daemon side of that contract at the source level; the
/// accounting itself is unit-tested in Rust
/// (`daemon/tests/test_gpu_engine_usage.rs`, `daemon/tests/test_gpu_pmu_usage.rs`).
Item {
    id: testRoot
    width: 600
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: {
            console.log("RUNNING: GPU Usage Is Measured, Not A Clock Ratio");

            const metrics = readLocalFile("../daemon/src/infrastructure/proc_metrics.rs");
            const domain = readLocalFile("../daemon/src/domain/gpu_engine.rs");
            const probe = readLocalFile("../daemon/src/infrastructure/gpu_engine_probe.rs");
            const pmu = readLocalFile("../daemon/src/infrastructure/gpu_pmu_probe.rs");

            assert(metrics.length > 5000, "proc_metrics.rs must be readable");
            assert(domain.length > 1000, "the gpu_engine domain module must exist");
            assert(probe.length > 1000, "the fdinfo probe must exist");
            assert(pmu.length > 1000, "the GT perf-counter probe must exist");

            // 1. Engine samples exist and are attributed to a device.
            assert(domain.indexOf("drm-engine-render") >= 0,
                "the domain parser must read drm-engine-render from fdinfo");
            assert(domain.indexOf("drm-pdev") >= 0,
                "engine counters must be attributed to a PCI device (drm-pdev)");
            assert(probe.indexOf("fdinfo") >= 0,
                "the probe must scan /proc/<pid>/fdinfo");

            // 1b. The complete source is consulted first. fdinfo cannot read a
            // non-dumpable compositor, so it must not be the headline number.
            assert(pmu.indexOf("perf_event_open") >= 0 && pmu.indexOf("SYS_perf_event_open") >= 0,
                "the GT counters must be read through the perf PMU");
            assert(pmu.indexOf("-busy") >= 0 && pmu.indexOf("PMU_ROOT") >= 0,
                "the engine busy events must come from sysfs, not a hardcoded engine table");
            assert(metrics.indexOf("measure_pmu_usage") >= 0,
                "the metrics adapter must ask for the GT-wide counters");
            assert(/fn engine_usage_sources\(/.test(metrics)
                   && metrics.indexOf("engine_usage_sources(&pmu_rates") >= 0,
                "every DRM card must resolve through the staged source helper");

            // 2. Measured usage wins; the clock ratio is only a fallback.
            assert(domain.indexOf("pub fn resolve_usage") >= 0,
                "resolve_usage must decide between measurement and fallback");
            assert(domain.indexOf("pub fn resolve_usage_staged") >= 0,
                "the GT counter, the fdinfo sum and the fallback must be ranked");
            assert(/resolve_usage_staged\(gt, per_client, clock_ratio\)/.test(metrics),
                "the Intel branch must rank the GT counter above fdinfo, and both above the clock ratio");
            assert(metrics.indexOf("measured_usage_for_pci_slot") >= 0,
                "every DRM card branch must consult a measured engine usage");
            assert(/resolve_usage_staged\(\s*gt,\s*per_client,\s*amd_metric\.usage,?\s*\)/.test(metrics),
                "the AMD branch must prefer measured engine time over gpu_busy_percent");

            // 3. No measurement must never be reported as an idle GPU.
            assert(/if \*busy_now < \*busy_prev \{\s*continue;/.test(domain),
                "a restarted counter must yield no rate instead of a negative or zero load");
            assert(domain.indexOf("now_epoch_ms <= prev_epoch_ms") >= 0,
                "a non-advancing clock must yield no rate");
            assert(pmu.indexOf("if busy.is_empty()") >= 0,
                "an unreadable PMU must report no measurement, never an idle GPU");

            // 4. The rate survives between CLI invocations (tmpfs cache), and the
            // two sources never share one cache: their counters are unrelated.
            assert(probe.indexOf("/dev/shm/astral_gpu_engine") >= 0,
                "the previous counters must be cached in /dev/shm like the CPU sampler");
            assert(pmu.indexOf("/dev/shm/astral_gpu_pmu") >= 0,
                "the GT counters need their own cache, separate from the fdinfo one");
            assert(domain.indexOf("pub fn encode_engine_state") >= 0
                   && domain.indexOf("pub fn parse_engine_state") >= 0,
                "the cache format must be encoded and parsed by the domain, not ad hoc");

            console.log("PASS: GPU Usage Is Measured, Not A Clock Ratio");
            Qt.exit(0);
        }
    }
}
