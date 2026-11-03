import QtQuick

/// The GPU percentage is utilisation, not a clock ratio.
///
/// On a 240 Hz panel the Intel RPS governor parks near `gt_max_freq_mhz` while
/// the render engine is ~5 % busy, so the old "usage" (a normalised clock) read
/// 60–100 % on an idle GPU. The daemon now measures DRM engine time from
/// `/proc/<pid>/fdinfo` and only falls back to the clock when no client is
/// readable. This suite pins the daemon side of that contract at the source
/// level; the accounting itself is unit-tested in Rust
/// (`daemon/tests/test_gpu_engine_usage.rs`).
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

            assert(metrics.length > 5000, "proc_metrics.rs must be readable");
            assert(domain.length > 1000, "the gpu_engine domain module must exist");
            assert(probe.length > 1000, "the fdinfo probe must exist");

            // 1. Engine samples exist and are attributed to a device.
            assert(domain.indexOf("drm-engine-render") >= 0,
                "the domain parser must read drm-engine-render from fdinfo");
            assert(domain.indexOf("drm-pdev") >= 0,
                "engine counters must be attributed to a PCI device (drm-pdev)");
            assert(probe.indexOf("fdinfo") >= 0,
                "the probe must scan /proc/<pid>/fdinfo");

            // 2. Measured usage wins; the clock ratio is only a fallback.
            assert(domain.indexOf("pub fn resolve_usage") >= 0,
                "resolve_usage must decide between measurement and fallback");
            assert(/resolve_usage\(measured, clock_ratio\)/.test(metrics),
                "the Intel branch must feed the measured value, with the clock ratio only as fallback");
            assert(/let measured = crate::infrastructure::gpu_engine_probe::measured_usage_for_pci_slot/.test(metrics),
                "every DRM card branch must consult the measured engine usage");
            assert(metrics.indexOf("resolve_usage(measured, amd_metric.usage)") >= 0,
                "the AMD branch must prefer measured engine time over gpu_busy_percent");

            // 3. No measurement must never be reported as an idle GPU.
            assert(/if \*busy_now < \*busy_prev \{\s*continue;/.test(domain),
                "a restarted counter must yield no rate instead of a negative or zero load");
            assert(domain.indexOf("now_epoch_ms <= prev_epoch_ms") >= 0,
                "a non-advancing clock must yield no rate");

            // 4. The rate survives between CLI invocations (tmpfs cache).
            assert(probe.indexOf("/dev/shm/astral_gpu_engine") >= 0,
                "the previous counters must be cached in /dev/shm like the CPU sampler");
            assert(domain.indexOf("pub fn encode_engine_state") >= 0
                   && domain.indexOf("pub fn parse_engine_state") >= 0,
                "the cache format must be encoded and parsed by the domain, not ad hoc");

            console.log("PASS: GPU Usage Is Measured, Not A Clock Ratio");
            Qt.exit(0);
        }
    }
}
