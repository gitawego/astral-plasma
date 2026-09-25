pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property string distroName: "CachyOS Linux"
    property string compositor: "KDE Plasma 6 (KWin)"
    property string uptime: "up 1 hour, 20 minutes"

    // Legacy compatibility property
    property real ramUsage: 0.40

    // CPU Metrics
    property real cpuUsage: 0.15
    property real cpuTemp: 0.0
    property real cpuFreqGhz: 0.0
    property string cpuModel: "Processor"
    property int cpuProcesses: 0
    property int cpuThreads: 0
    property real cpuLoad1m: 0.0
    property var cpuHistory: []

    // Memory Metrics
    property real ramTotalBytes: 0
    property real ramUsedBytes: 0
    property real ramAvailableBytes: 0
    property real ramCachedBytes: 0
    property real swapUsage: 0.0
    property real swapTotalBytes: 0
    property real swapUsedBytes: 0
    property var ramHistory: []

    // GPU Metrics
    property real gpuUsage: 0.0
    property real gpuTemp: 0.0
    property string gpuModel: "Graphics"
    property real gpuMemoryUsedBytes: 0
    property real gpuMemoryTotalBytes: 0
    property real gpuClockGhz: 0.0
    property var gpuHistory: []
    property var gpus: []
    property int selectedGpuIndex: 0
    property var gpuHistories: ({})

    function getGpuHistory(index) {
        const key = "gpu_" + index;
        if (root.gpuHistories && root.gpuHistories[key] && root.gpuHistories[key].length > 0) {
            return root.gpuHistories[key];
        }
        return root.gpuHistory;
    }

    onSelectedGpuIndexChanged: {
        if (root.gpus && root.gpus.length > root.selectedGpuIndex && root.selectedGpuIndex >= 0) {
            const curGpu = root.gpus[root.selectedGpuIndex];
            if (curGpu) {
                root.gpuUsage = curGpu.usage !== undefined ? curGpu.usage : 0.0;
                root.gpuTemp = curGpu.temperature !== undefined ? curGpu.temperature : 0.0;
                root.gpuModel = curGpu.model || "Graphics";
                root.gpuMemoryUsedBytes = curGpu.memory_used_bytes || 0;
                root.gpuMemoryTotalBytes = curGpu.memory_total_bytes || 0;
                root.gpuClockGhz = curGpu.clock_ghz || 0.0;
                root.gpuHistory = root.getGpuHistory(root.selectedGpuIndex);
            }
        }
    }

    // Battery / Power Metrics
    property int batteryPercentage: 100
    property bool batteryCharging: false
    property real batteryWatts: 0.0
    property real batteryVoltage: 0.0
    property int batteryHealth: 100
    property string powerProfile: "balanced"
    property string batteryState: "Discharging"
    property var batteryHistory: []

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        const p = Math.min(Math.max(0, i), units.length - 1);
        const val = bytes / Math.pow(1024, p);
        return val.toFixed(1) + " " + units[p];
    }

    function pushHistory(arr, val, maxLen) {
        const len = maxLen || 60;
        let next = (arr && arr.length > 0) ? arr.slice() : [];
        next.push(val);
        while (next.length > len) {
            next.shift();
        }
        return next;
    }

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    Process {
        id: sysInfoProc
        command: [root.daemonBin, "metrics"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text.trim());
                    if (d.uptime) root.uptime = d.uptime;
                    if (d.ram !== undefined) root.ramUsage = d.ram;

                    // CPU
                    if (d.cpu) {
                        if (d.cpu.usage !== undefined) {
                            root.cpuUsage = d.cpu.usage;
                            root.cpuHistory = root.pushHistory(root.cpuHistory, d.cpu.usage);
                        }
                        if (d.cpu.temperature !== undefined) root.cpuTemp = d.cpu.temperature;
                        if (d.cpu.frequency_ghz !== undefined) root.cpuFreqGhz = d.cpu.frequency_ghz;
                        if (d.cpu.model) root.cpuModel = d.cpu.model;
                        if (d.cpu.processes !== undefined) root.cpuProcesses = d.cpu.processes;
                        if (d.cpu.threads !== undefined) root.cpuThreads = d.cpu.threads;
                        if (d.cpu.load_1m !== undefined) root.cpuLoad1m = d.cpu.load_1m;
                    }

                    // Memory
                    if (d.memory) {
                        if (d.memory.usage !== undefined) {
                            root.ramUsage = d.memory.usage;
                            root.ramHistory = root.pushHistory(root.ramHistory, d.memory.usage);
                        }
                        if (d.memory.total_bytes !== undefined) root.ramTotalBytes = d.memory.total_bytes;
                        if (d.memory.used_bytes !== undefined) root.ramUsedBytes = d.memory.used_bytes;
                        if (d.memory.available_bytes !== undefined) root.ramAvailableBytes = d.memory.available_bytes;
                        if (d.memory.cached_bytes !== undefined) root.ramCachedBytes = d.memory.cached_bytes;
                        if (d.memory.swap_usage !== undefined) root.swapUsage = d.memory.swap_usage;
                        if (d.memory.swap_total_bytes !== undefined) root.swapTotalBytes = d.memory.swap_total_bytes;
                        if (d.memory.swap_used_bytes !== undefined) root.swapUsedBytes = d.memory.swap_used_bytes;
                    }

                    // GPU(s)
                    if (d.gpus && Array.isArray(d.gpus) && d.gpus.length > 0) {
                        root.gpus = d.gpus;
                        const newHistories = Object.assign({}, root.gpuHistories);
                        for (let i = 0; i < d.gpus.length; ++i) {
                            const g = d.gpus[i];
                            const key = "gpu_" + i;
                            const prevHist = newHistories[key] || [];
                            newHistories[key] = root.pushHistory(prevHist, (g && g.usage !== undefined) ? g.usage : 0.0);
                        }
                        root.gpuHistories = newHistories;

                        if (root.selectedGpuIndex >= d.gpus.length) {
                            root.selectedGpuIndex = 0;
                        }
                        const curGpu = d.gpus[root.selectedGpuIndex];
                        if (curGpu) {
                            root.gpuUsage = curGpu.usage !== undefined ? curGpu.usage : 0.0;
                            root.gpuTemp = curGpu.temperature !== undefined ? curGpu.temperature : 0.0;
                            root.gpuModel = curGpu.model || "Graphics";
                            root.gpuMemoryUsedBytes = curGpu.memory_used_bytes || 0;
                            root.gpuMemoryTotalBytes = curGpu.memory_total_bytes || 0;
                            root.gpuClockGhz = curGpu.clock_ghz || 0.0;
                        }
                        root.gpuHistory = root.getGpuHistory(root.selectedGpuIndex);
                    } else if (d.gpu) {
                        root.gpus = [d.gpu];
                        if (d.gpu.usage !== undefined) {
                            root.gpuUsage = d.gpu.usage;
                            root.gpuHistory = root.pushHistory(root.gpuHistory, d.gpu.usage);
                        }
                        if (d.gpu.temperature !== undefined) root.gpuTemp = d.gpu.temperature;
                        if (d.gpu.model) root.gpuModel = d.gpu.model;
                        if (d.gpu.memory_used_bytes !== undefined) root.gpuMemoryUsedBytes = d.gpu.memory_used_bytes;
                        if (d.gpu.memory_total_bytes !== undefined) root.gpuMemoryTotalBytes = d.gpu.memory_total_bytes;
                        if (d.gpu.clock_ghz !== undefined) root.gpuClockGhz = d.gpu.clock_ghz;
                    }

                    // Battery
                    if (d.battery) {
                        if (d.battery.percentage !== undefined) {
                            root.batteryPercentage = d.battery.percentage;
                            root.batteryHistory = root.pushHistory(root.batteryHistory, d.battery.percentage / 100.0);
                        }
                        if (d.battery.is_charging !== undefined) root.batteryCharging = d.battery.is_charging;
                        if (d.battery.power_watts !== undefined) root.batteryWatts = d.battery.power_watts;
                        if (d.battery.voltage_volts !== undefined) root.batteryVoltage = d.battery.voltage_volts;
                        if (d.battery.health_percent !== undefined) root.batteryHealth = d.battery.health_percent;
                        if (d.battery.profile) root.powerProfile = d.battery.profile;
                        if (d.battery.state) root.batteryState = d.battery.state;
                    }
                } catch (e) {}
            }
        }
    }

    // =========================================================================
    // High-Performance Telemetry Monitoring Lifecycle State Machine
    // Zero background polling when closed / invisible.
    // 400ms Hysteresis against rapid tab switches and mouse hover flickers.
    // 1000ms Throttling lock against rapid process thrashing.
    // =========================================================================
    property bool manualMonitoringOverride: false
    property var activeClients: []

    function registerClient(client, isActive) {
        let list = (root.activeClients || []).filter(c => c !== client);
        if (isActive) {
            list.push(client);
        }
        root.activeClients = list;
    }

    function unregisterClient(client) {
        root.activeClients = (root.activeClients || []).filter(c => c !== client);
    }

    readonly property bool hasActiveClients: Boolean(root.activeClients && root.activeClients.length > 0)

    readonly property bool isPerfTabVisibleInConfig: (typeof Config !== "undefined" && Config)
        ? (Boolean(Config.dashboardVisible) && Config.activeDashboardTab === "performance")
        : false

    readonly property bool rawMonitoringTarget: Boolean(
        root.manualMonitoringOverride ||
        root.hasActiveClients ||
        root.isPerfTabVisibleInConfig
    )

    property bool isMonitoringActive: false
    property double lastFetchTime: 0

    // Anti-thrashing exit grace timer: waits 400ms before tearing down monitoring
    // when switching tabs or moving mouse across drawer boundary
    Timer {
        id: deactivationGraceTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (!root.rawMonitoringTarget) {
                root.isMonitoringActive = false;
                if (sysInfoProc.running) {
                    sysInfoProc.running = false;
                }
            }
        }
    }

    function requestImmediateFetch() {
        const now = Date.now();
        // Strict 1000ms rate limit and single in-flight process lock
        if (now - root.lastFetchTime >= 1000 && !sysInfoProc.running) {
            root.lastFetchTime = now;
            sysInfoProc.running = true;
        }
    }

    onRawMonitoringTargetChanged: {
        if (rawMonitoringTarget) {
            deactivationGraceTimer.stop();
            root.isMonitoringActive = true;
            root.requestImmediateFetch();
        } else {
            deactivationGraceTimer.restart();
        }
    }

    // 1-second cadence timer: active ONLY while isMonitoringActive is true
    Timer {
        id: monitoringTimer
        interval: 1000
        running: root.isMonitoringActive
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            if (root.isMonitoringActive && !sysInfoProc.running) {
                root.lastFetchTime = Date.now();
                sysInfoProc.running = true;
            }
        }
    }

    Component.onCompleted: {
        let initArray = [];
        for (let i = 0; i < 60; ++i) initArray.push(0.0);
        root.cpuHistory = initArray.slice();
        root.ramHistory = initArray.slice();
        root.gpuHistory = initArray.slice();
        root.batteryHistory = initArray.slice();

        // Boot state: only start if monitoring is already explicitly requested
        if (root.isMonitoringActive && !sysInfoProc.running) {
            root.lastFetchTime = Date.now();
            sysInfoProc.running = true;
        }
    }
}
