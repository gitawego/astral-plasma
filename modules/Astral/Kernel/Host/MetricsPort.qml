import QtQuick

// ============================================================================
// MetricsPort — the machine's telemetry a surface may render
// ============================================================================
// A performance surface shows CPU, memory, GPU, battery and power mode. Those live in
// the shell's `SystemService`; a Loader-loaded surface that imported it would get its
// own instance with no sampling (spec C.9/C.10), so the shell injects this.
//
// It exists in two shapes, and the shell picks per surface: a narrow facade (the
// properties below) when the surface needs a handful of numbers, or **the live service
// object itself** for a surface whose needs are wide (telemetry plus helpers like byte
// formatting, the system-monitor action and the sampling lifecycle). What matters in
// both shapes is that the object is the shell's instance, injected — never a singleton
// an app imports for itself.
//
// Two lifecycle calls matter and are easy to get wrong: `registerClient(client)` keeps
// the service sampling while a surface is visible, and `unregisterClient(client)`
// stops it. A port that forgot them would leave the CPU polling in the background
// forever, so they are first-class here rather than left to the surface.
QtObject {
    id: root

    // ---- data ---------------------------------------------------------------
    property real cpuUsage: 0
    property real cpuTemp: 0
    property real cpuFreqGhz: 0
    property real ramUsage: 0
    property real ramTotalBytes: 0

    /// `[{ name, usage, temp, vramUsed, vramTotal, ... }]`
    property var gpus: []
    property int selectedGpuIndex: 0

    property int batteryPercentage: 0
    property real batteryWatts: 0
    property string batteryState: ""
    property string powerProfile: "balanced"

    // ---- operations (supplied by the shell) ---------------------------------

    property var gpuHistoryImpl: null
    property var registerClientImpl: null
    property var unregisterClientImpl: null
    property var selectGpuImpl: null

    readonly property bool canSampleGpuHistory: gpuHistoryImpl !== null
    readonly property bool canRegister: registerClientImpl !== null

    signal operationFailed(string operation, string reason)

    function call(operation, impl, args) {
        if (typeof impl !== "function") {
            root.operationFailed(operation, "not supported by this shell");
            return false;
        }
        try {
            const result = impl.apply(null, args || []);
            return result === undefined ? true : !!result;
        } catch (error) {
            root.operationFailed(operation, String(error));
            return false;
        }
    }

    /// Samples for one GPU, as `[{ t, value }]` (empty when the shell keeps none).
    function gpuHistory(index) {
        if (typeof gpuHistoryImpl !== "function") {
            root.operationFailed("gpuHistory", "not supported by this shell");
            return [];
        }
        try {
            return gpuHistoryImpl(Number(index) || 0) || [];
        } catch (error) {
            root.operationFailed("gpuHistory", String(error));
            return [];
        }
    }

    function registerClient(client, active) {
        return call("registerClient", registerClientImpl, [client, !!active]);
    }

    function unregisterClient(client) {
        return call("unregisterClient", unregisterClientImpl, [client]);
    }

    function selectGpu(index) {
        return call("selectGpu", selectGpuImpl, [Number(index) || 0]);
    }
}
