import QtQuick
import QtQuick.Layouts
import "../dashboard/tabs"
import "../theme"

Item {
    id: testRoot
    width: 680
    height: 360

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    PerformanceTab {
        id: perfTab
        anchors.fill: parent
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: {
            console.log("Starting PerformanceTab Telemetry Unit Tests...");

            function assert(condition, message) {
                if (!condition) {
                    console.error("FAIL: " + message);
                    Qt.exit(1);
                }
            }

            // 1. Basic instantiation & sizing
            assert(perfTab !== null, "PerformanceTab must instantiate");
            assert(perfTab.width >= 600, "PerformanceTab width must be >= 600px");
            assert(perfTab.height >= 320, "PerformanceTab height must be >= 320px");

            // 2. Removal of volume and brightness cards (User requirement)
            assert(perfTab.volumeCardItem === undefined, "Volume card must not exist in PerformanceTab");
            assert(perfTab.brightnessCardItem === undefined, "Brightness card must not exist in PerformanceTab");
            assert(perfTab.isTargetVisible !== undefined, "PerformanceTab must expose isTargetVisible");
            assert(perfTab.isTargetVisible === true, "perfTab.isTargetVisible must be true when visible");

            // 3. Backward compatibility & Liquid Glass contracts
            assert(perfTab.ramCardItem !== undefined && perfTab.ramCardItem !== null, "PerformanceTab must expose ramCardItem for tst_dashboard_cards");
            assert(perfTab.ramCardItem.showShadow === true, "ramCardItem must have showShadow enabled");

            // 4. Master-Detail Device Selection
            assert(perfTab.selectedDevice !== undefined, "PerformanceTab must expose selectedDevice");
            assert(perfTab.selectedDevice === "cpu", "Default selectedDevice must be 'cpu'");

            // Test selecting memory
            perfTab.selectedDevice = "memory";
            assert(perfTab.selectedDevice === "memory", "selectedDevice must switch to 'memory'");

            // Test selecting gpu
            perfTab.selectedDevice = "gpu";
            assert(perfTab.selectedDevice === "gpu", "selectedDevice must switch to 'gpu'");

            // Test selecting battery
            perfTab.selectedDevice = "battery";
            assert(perfTab.selectedDevice === "battery", "selectedDevice must switch to 'battery'");

            // Reset to cpu
            perfTab.selectedDevice = "cpu";

            // 5. Telemetry Real-time Chart
            assert(perfTab.chartCanvas !== undefined && perfTab.chartCanvas !== null, "PerformanceTab must expose chartCanvas");
            assert(perfTab.chartCanvas.visible === true, "chartCanvas must be active and visible");
            assert(Array.isArray(perfTab.activeHistory), "perfTab.activeHistory must be an array");
            assert(perfTab.activeHistory.length >= 60, "perfTab.activeHistory must have at least 60 data points");

            // 6. Format bytes helper
            let formatted = perfTab.formatBytes(1073741824);
            assert(formatted === "1.0 GiB", "perfTab.formatBytes(1073741824) must return '1.0 GiB', got: " + formatted);

            let formattedMb = perfTab.formatBytes(104857600);
            assert(formattedMb === "100.0 MiB", "perfTab.formatBytes(104857600) must return '100.0 MiB', got: " + formattedMb);

            // 7. Verify SystemService.qml static contract & ground-truth telemetry properties
            let serviceContent = readLocalFile("../services/SystemService.qml");
            assert(serviceContent.indexOf("property real cpuUsage") !== -1, "SystemService must declare cpuUsage");
            assert(serviceContent.indexOf("property var cpuHistory") !== -1, "SystemService must declare cpuHistory");
            assert(serviceContent.indexOf("property real ramTotalBytes") !== -1, "SystemService must declare ramTotalBytes");
            assert(serviceContent.indexOf("property var ramHistory") !== -1, "SystemService must declare ramHistory");
            assert(serviceContent.indexOf("property real gpuUsage") !== -1, "SystemService must declare gpuUsage");
            assert(serviceContent.indexOf("property var gpuHistory") !== -1, "SystemService must declare gpuHistory");
            assert(serviceContent.indexOf("property var gpus") !== -1, "SystemService must declare gpus array");
            assert(serviceContent.indexOf("property int selectedGpuIndex") !== -1, "SystemService must declare selectedGpuIndex");
            assert(serviceContent.indexOf("function getGpuHistory") !== -1, "SystemService must declare getGpuHistory");
            assert(serviceContent.indexOf("property int batteryPercentage") !== -1, "SystemService must declare batteryPercentage");
            assert(serviceContent.indexOf("property var batteryHistory") !== -1, "SystemService must declare batteryHistory");

            // 8. Chromatic Tokens for Vibrant Domain-Specific Charts
            assert(perfTab.cpuColor !== undefined, "perfTab must declare cpuColor");
            assert(perfTab.memoryColor !== undefined, "perfTab must declare memoryColor");
            assert(perfTab.gpuColor !== undefined, "perfTab must declare gpuColor");
            assert(perfTab.batteryColor !== undefined, "perfTab must declare batteryColor");
            assert(perfTab.activeDeviceColor !== undefined, "perfTab must declare activeDeviceColor");
            assert(Qt.colorEqual(perfTab.activeDeviceColor, perfTab.cpuColor), "activeDeviceColor must match cpuColor when selectedDevice is cpu");
            perfTab.selectedDevice = "gpu";
            assert(Qt.colorEqual(perfTab.activeDeviceColor, perfTab.gpuColor), "activeDeviceColor must match gpuColor when selectedDevice is gpu");
            perfTab.selectedDevice = "memory";
            assert(Qt.colorEqual(perfTab.activeDeviceColor, perfTab.memoryColor), "activeDeviceColor must match memoryColor when selectedDevice is memory");
            perfTab.selectedDevice = "battery";
            assert(Qt.colorEqual(perfTab.activeDeviceColor, perfTab.batteryColor), "activeDeviceColor must match batteryColor when selectedDevice is battery");
            // Verify green battery (g > r to avoid warning yellow impression)
            assert(perfTab.batteryColor.g > perfTab.batteryColor.r, "batteryColor must be green (g > r), avoiding yellow warning impression");
            assert(Qt.colorEqual(perfTab.batteryColor, "#34d399"), "batteryColor must be emerald green #34d399");
            assert(Qt.colorEqual(perfTab.gpuColor, "#fb7185"), "gpuColor must be coral rose #fb7185");

            // 9. Multi-GPU Device Selection & Reactivity
            perfTab.selectedDevice = "gpu:0";
            assert(perfTab.selectedDevice === "gpu:0", "selectedDevice must switch to 'gpu:0'");
            assert(perfTab.selectedGpuIndex === 0, "selectedGpuIndex must be 0 for 'gpu:0'");
            assert(Qt.colorEqual(perfTab.activeDeviceColor, perfTab.gpuColor), "activeDeviceColor must match gpuColor for 'gpu:0'");

            perfTab.selectedDevice = "gpu:1";
            assert(perfTab.selectedDevice === "gpu:1", "selectedDevice must switch to 'gpu:1'");
            assert(perfTab.selectedGpuIndex === 1, "selectedGpuIndex must be 1 for 'gpu:1'");
            assert(Qt.colorEqual(perfTab.activeDeviceColor, perfTab.gpuColor), "activeDeviceColor must match gpuColor for 'gpu:1'");

            perfTab.selectedDevice = "gpu";
            assert(perfTab.selectedDevice === "gpu", "selectedDevice must switch to backward-compatible 'gpu'");
            assert(Qt.colorEqual(perfTab.activeDeviceColor, perfTab.gpuColor), "activeDeviceColor must match gpuColor for 'gpu'");

            perfTab.selectedDevice = "cpu";

            // 10. Smooth Telemetry Transitions & Stable Delegate Lifecycle (Zero Cursor Flashing)
            assert(perfTab.gpuCount !== undefined && perfTab.gpuCount >= 1, "perfTab must expose integer gpuCount >= 1");
            assert(perfTab.animatedMainUsage !== undefined && perfTab.animatedMainUsage >= 0.0, "perfTab must expose animatedMainUsage");
            assert(perfTab.waveMorph !== undefined && perfTab.waveMorph >= 0.0 && perfTab.waveMorph <= 1.0, "perfTab must expose waveMorph in [0.0, 1.0]");

            let perfContent = readLocalFile("../dashboard/tabs/PerformanceTab.qml");
            assert(perfContent.indexOf("model: root.gpuCount") !== -1, "gpuRepeater must use integer model: root.gpuCount to prevent delegate teardown & mouse flash");
            assert(perfContent.indexOf("waveMorph") !== -1, "PerformanceTab must use waveMorph interpolation for smooth charts");
            assert(perfContent.indexOf("animatedMainUsage") !== -1, "PerformanceTab must animate main usage headline number");
            assert(perfContent.indexOf("Behavior on width") !== -1, "PerformanceTab must animate card load bars with Behavior on width");

            console.log("PASS: PerformanceTab Telemetry Unit Tests");
            Qt.exit(0);
        }
    }
}
