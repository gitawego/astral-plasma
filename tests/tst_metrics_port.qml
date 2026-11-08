import QtQuick
import "../modules/Astral/Kernel/Host"

// ============================================================================
// MetricsPort
// ============================================================================
// Telemetry for a performance surface. The two lifecycle calls are the reason this is
// a port and not a bag of numbers: a surface that forgets `unregisterClient` leaves
// the shell sampling forever.
Item {
    id: testRoot
    width: 400
    height: 300

    property var failures: []

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function run() {
        const port = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/Host"; MetricsPort { }',
            testRoot, "metrics");
        port.operationFailed.connect(function (operation, reason) {
            failures.push({ operation: operation, reason: reason });
        });

        // ---- defaults are zero, not invented --------------------------------
        assert(port.cpuUsage === 0 && port.ramUsage === 0, "no telemetry until the shell samples");
        assert(port.gpus.length === 0, "no GPUs until the shell reports them");
        assert(port.gpuHistory(0).length === 0, "no history without a sampler");
        assert(failures.some(function (item) { return item.operation === "gpuHistory"; }),
            "asking for history without a sampler is reported");

        // ---- data ------------------------------------------------------------
        port.cpuUsage = 0.42;
        port.cpuTemp = 61;
        port.ramUsage = 0.55;
        port.ramTotalBytes = 34359738368;
        port.gpus = [{ name: "RX 7900 XT", usage: 0.31, temp: 58, used: 4096, total: 20480 }];
        port.selectedGpuIndex = 0;
        port.batteryPercentage = 77;
        port.powerProfile = "performance";
        assert(port.cpuUsage === 0.42 && port.cpuTemp === 61, "CPU telemetry reaches the surface");
        assert(port.gpus.length === 1 && port.gpus[0].name === "RX 7900 XT", "GPU entries arrive");
        assert(port.powerProfile === "performance", "the power profile arrives");

        // ---- lifecycle -------------------------------------------------------
        let registered = null;
        let unregistered = null;
        port.registerClientImpl = function (client, active) { registered = { client: client, active: active }; };
        port.unregisterClientImpl = function (client) { unregistered = client; };
        assert(port.canRegister, "registration is advertised");
        assert(port.registerClient("perf-tab", true), "a surface can register");
        assert(registered.client === "perf-tab" && registered.active === true,
            "both registration arguments arrive");
        assert(port.unregisterClient("perf-tab"), "and unregister");
        assert(unregistered === "perf-tab", "the client id arrives on unregister");

        // ---- history and GPU selection ---------------------------------------
        port.gpuHistoryImpl = function (index) { return [{ t: 1, value: 0.2 + index }]; };
        port.selectGpuImpl = function (index) { port.selectedGpuIndex = index; };
        const history = port.gpuHistory(1);
        assert(history.length === 1 && history[0].value === 1.2, "history is sampled per GPU");
        assert(port.selectGpu(0), "a GPU can be selected");

        // ---- containment -----------------------------------------------------
        port.registerClientImpl = function () { throw new Error("sampler gone"); };
        assert(port.registerClient("x", true) === false, "a throwing sampler returns false");
        assert(failures.some(function (item) { return item.operation === "registerClient"; }),
            "and is reported");

        port.destroy();
        console.log("PASS: All metrics port tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
