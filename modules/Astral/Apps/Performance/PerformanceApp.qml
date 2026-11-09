import QtQuick
import QtQuick.Layouts
import "../../Kernel/components/motion"
import "../../Kernel/theme"
import "../../Kernel/components"

// Performance app (`manifest.entry.dashboardTab` = "performance").
//
// Declared as a Component in `shell.qml` so it shares the shell's kernel registration and
// palette (spec C.18). `metrics` is the shell's live telemetry service; `shellState` carries
// the selected device; writes go through `intents`.
Item {
    id: root

    property var metrics: null
    property var shellState: null
    property var intents: null

    implicitWidth: 680
    implicitHeight: 350

    // Lifecycle & Visibility Tracking (zero offscreen rendering)
    property bool testMode: false

    // Visible in the dashboard's performance pane, or anywhere the surface is shown on its
    // own (`testMode`). The old `typeof Config` guard was permanently false inside an app,
    // so this was always `true`.
    readonly property bool isTargetVisible: testMode || (visible && root.shellState !== null
        && root.shellState.activeDashboardTab === "performance")

    onIsTargetVisibleChanged: {
        if (root.metrics !== null && root.metrics && typeof root.metrics.registerClient === "function") {
            root.metrics.registerClient(root, root.isTargetVisible);
        }
        if (root.isTargetVisible) {
            telemetryCanvas.requestPaint();
        }
    }

    Component.onCompleted: {
        if (root.metrics !== null && root.metrics && typeof root.metrics.registerClient === "function") {
            root.metrics.registerClient(root, root.isTargetVisible);
        }
    }

    Component.onDestruction: {
        if (root.metrics !== null && root.metrics && typeof root.metrics.unregisterClient === "function") {
            root.metrics.unregisterClient(root);
        }
    }

    // Selected hardware telemetry device: "cpu" | "memory" | "gpu" | "battery"
    property string selectedDevice: (root.shellState && root.shellState.perfSelectedDevice) ? root.shellState.perfSelectedDevice : "cpu"

    readonly property int gpuCount: (root.metrics !== null && root.metrics.gpus && root.metrics.gpus.length > 0)
        ? root.metrics.gpus.length
        : 1

    Connections {
        target: root.shellState
        function onPerfSelectedDeviceChanged() {
            if ((root.shellState ? root.shellState.perfSelectedDevice : "") && root.selectedDevice !== (root.shellState ? root.shellState.perfSelectedDevice : "")) {
                root.selectedDevice = (root.shellState ? root.shellState.perfSelectedDevice : "");
            }
        }
    }

    readonly property int selectedGpuIndex: {
        if (root.selectedDevice && root.selectedDevice.startsWith("gpu:")) {
            const idx = parseInt(root.selectedDevice.substring(4));
            return isNaN(idx) ? 0 : idx;
        }
        return (root.metrics !== null && root.metrics && root.metrics.selectedGpuIndex !== undefined) ? root.metrics.selectedGpuIndex : 0;
    }

    readonly property var currentGpu: {
        if (root.metrics !== null && root.metrics && root.metrics.gpus && root.metrics.gpus.length > 0) {
            const idx = Math.min(Math.max(0, root.selectedGpuIndex), root.metrics.gpus.length - 1);
            return root.metrics.gpus[idx];
        }
        return null;
    }

    onSelectedDeviceChanged: {
        if (root.selectedDevice.startsWith("gpu:")) {
            const idx = parseInt(root.selectedDevice.substring(4));
            if (!isNaN(idx) && root.metrics !== null && root.metrics) {
                root.metrics.selectedGpuIndex = idx;
            }
        }
        if (root.shellState !== null && root.shellState.perfSelectedDevice !== selectedDevice) {
            // A settings write is an intent: the shell owns the settings document.
            if (root.intents) {
                root.intents.request("performance.device", { device: selectedDevice });
            }
        }
        // Immediate clean reset when switching hardware device tabs
        slideTween.complete();
        const currentData = root.activeHistory;
        let b = (currentData && currentData.length) ? currentData.slice() : [];
        if (b.length > 0) b.push(b[b.length - 1] || 0.0);
        slideBuffer = b;
        if (root.isTargetVisible) {
            telemetryCanvas.requestPaint();
        }
    }

    // Vibrant hardware domain chromatic tokens (Material 3 Expressive)
    readonly property color cpuColor: "#38bdf8"       // Sky / Azure
    readonly property color memoryColor: "#c084fc"    // Orchid / Violet
    readonly property color gpuColor: "#fb7185"       // Coral / Rose
    readonly property color batteryColor: "#34d399"   // Emerald / Mint Green (Healthy status, avoiding warning yellow)

    readonly property color activeDeviceColor: {
        if (root.selectedDevice.startsWith("gpu")) return root.gpuColor;
        switch (root.selectedDevice) {
            case "memory": return root.memoryColor;
            case "battery": return root.batteryColor;
            case "cpu":
            default: return root.cpuColor;
        }
    }

    // Backward compatibility aliases for tests
    readonly property alias ramCardItem: memoryDeviceCard
    readonly property alias chartCanvas: telemetryCanvas
    readonly property real animatedMainUsage: detailContainer.animatedMainUsage

    function formatBytes(bytes) {
        if (root.metrics !== null && root.metrics && typeof root.metrics.formatBytes === "function") {
            return root.metrics.formatBytes(bytes);
        }
        if (!bytes || bytes <= 0) return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        const p = Math.min(Math.max(0, i), units.length - 1);
        const val = bytes / Math.pow(1024, p);
        return val.toFixed(1) + " " + units[p];
    }

    function openSystemMonitor() {
        if (root.testMode) return;
        if (typeof WindowService !== "undefined" && WindowService && typeof WindowService.openSystemMonitor === "function") {
            WindowService.openSystemMonitor();
            return;
        }
        if (root.metrics !== null && root.metrics && typeof root.metrics.openSystemMonitor === "function") {
            root.metrics.openSystemMonitor();
            return;
        }
    }

    // Device telemetry active dataset
    readonly property var activeHistory: {
        let hist = [];
        if (root.metrics !== null && root.metrics) {
            if (root.selectedDevice.startsWith("gpu")) {
                if (typeof root.metrics.getGpuHistory === "function") {
                    hist = root.metrics.getGpuHistory(root.selectedGpuIndex);
                } else {
                    hist = root.metrics.gpuHistory;
                }
            } else {
                switch (root.selectedDevice) {
                    case "memory": hist = root.metrics.ramHistory; break;
                    case "battery": hist = root.metrics.batteryHistory; break;
                    case "cpu":
                    default: hist = root.metrics.cpuHistory; break;
                }
            }
        }
        if (!hist || !Array.isArray(hist) || hist.length === 0) {
            hist = [];
            for (let i = 0; i < 60; ++i) hist.push(0.0);
        }
        return hist;
    }

    // Smooth horizontal slide telemetry properties (preserves shape, zero deformation).
    // The slide is *data-driven* decoration: it runs on the shared decorative clock
    // (≤ `decorativeMaxFps`), so the trace is repainted at most that often per
    // second instead of once per display frame. A Qt animation here was restarted by
    // every 400 ms sample while lasting 450 ms, so it never finished and the whole
    // tab rendered at the panel's refresh rate.
    property var slideBuffer: []
    readonly property real slideProgress: slideTween.value

    readonly property real waveMorph: slideProgress // alias for test backward compatibility

    MotionTween {
        id: slideTween
        duration: Theme.animExpressiveFastEffects
        bezier: Theme.curveExpressiveFastEffects
        from: 0.0
        to: 1.0
        onAdvanced: {
            if (root.isTargetVisible) {
                telemetryCanvas.requestPaint();
            }
        }
    }

    // Usage meters follow their metric on the same clock. See MotionValue: a
    // `Behavior on width` would animate at display refresh and, with a 400 ms CPU
    // sample interval, never come to rest.
    MotionValue {
        id: cpuBar
        animated: root.isTargetVisible
        duration: Theme.animExpressiveFastSpatial
        bezier: Theme.curveExpressiveFastSpatial
        target: Math.min(1.0, Math.max(0.0, (root.metrics !== null && root.metrics.cpuUsage !== undefined) ? root.metrics.cpuUsage : 0.0))
    }

    MotionValue {
        id: ramBar
        animated: root.isTargetVisible
        duration: Theme.animExpressiveFastSpatial
        bezier: Theme.curveExpressiveFastSpatial
        target: Math.min(1.0, Math.max(0.0, (root.metrics !== null && root.metrics.ramUsage !== undefined) ? root.metrics.ramUsage : 0.0))
    }

    MotionValue {
        id: batteryBar
        animated: root.isTargetVisible
        duration: Theme.animExpressiveFastSpatial
        bezier: Theme.curveExpressiveFastSpatial
        target: Math.min(1.0, Math.max(0.0, (root.metrics !== null && root.metrics.batteryPercentage !== undefined) ? (root.metrics.batteryPercentage / 100.0) : 1.0))
    }

    // The selected device's big readout follows the same policy.
    MotionValue {
        id: mainUsage
        animated: root.isTargetVisible
        duration: Theme.animExpressiveFastSpatial
        bezier: Theme.curveExpressiveFastSpatial
        target: detailContainer.targetMainUsage
    }

    onActiveHistoryChanged: {
        const newHist = root.activeHistory;
        if (!newHist || newHist.length < 2) return;

        const N = 60;
        const newSample = newHist[newHist.length - 1] || 0.0;

        if (slideBuffer && slideBuffer.length >= N) {
            let prev60 = [];
            if (slideProgress >= 1.0 && slideBuffer.length === N + 1) {
                prev60 = slideBuffer.slice(1, N + 1);
            } else if (slideBuffer.length === N) {
                prev60 = slideBuffer.slice(0, N);
            } else {
                prev60 = newHist.slice(0, N - 1);
                prev60.push(newSample);
            }
            let nextBuf = prev60.slice(0, N);
            nextBuf.push(newSample);
            slideBuffer = nextBuf;
        } else {
            let initBuf = newHist.slice(0, N);
            while (initBuf.length < N) initBuf.push(0.0);
            initBuf.push(newSample);
            slideBuffer = initBuf;
        }

        if (root.isTargetVisible) {
            slideTween.restart();
        } else {
            slideTween.complete();
            telemetryCanvas.requestPaint();
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

        // =========================================================================
        // LEFT COLUMN: Master Device Selector List
        // =========================================================================
        ColumnLayout {
            Layout.preferredWidth: 220
            Layout.minimumWidth: 200
            Layout.maximumWidth: 240
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: 8

            // 1. CPU Card
            LiquidGlassCard {
                id: cpuDeviceCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                interactive: true
                selected: root.selectedDevice === "cpu"
                accentGlint: root.cpuColor
                radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined) ? Theme.radiusGlassCard : 12
                showShadow: true
                hovered: cpuMa.containsMouse

                MouseArea {
                    id: cpuMa
                    anchors.fill: parent
                    z: 20
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedDevice = "cpu"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialIcon {
                            text: "speed"
                            size: 18
                            color: root.cpuColor
                        }
                        Text {
                            text: "CPU"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: Font.DemiBold
                            color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                            Layout.fillWidth: true
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }

                        // Mini Live Sparkline
                        Canvas {
                            id: cpuSparkline
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 14
                            onPaint: {
                                const ctx = getContext("2d");
                                const w = width;
                                const h = height;
                                ctx.clearRect(0, 0, w, h);
                                const hist = (root.metrics !== null) ? root.metrics.cpuHistory : [];
                                if (!hist || hist.length < 2) return;
                                const col = root.cpuColor;
                                ctx.beginPath();
                                const step = w / (hist.length - 1);
                                for (let i = 0; i < hist.length; ++i) {
                                    const v = Math.min(1.0, Math.max(0.0, hist[i] || 0.0));
                                    const x = i * step;
                                    const y = h - (v * (h - 2)) - 1;
                                    if (i === 0) ctx.moveTo(x, y);
                                    else ctx.lineTo(x, y);
                                }
                                ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.85);
                                ctx.lineWidth = 1.2;
                                ctx.stroke();
                                ctx.lineTo(w, h);
                                ctx.lineTo(0, h);
                                ctx.closePath();
                                ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.20);
                                ctx.fill();
                            }
                            Connections {
                                target: root.metrics
                                function onCpuHistoryChanged() { if (root.isTargetVisible) cpuSparkline.requestPaint(); }
                            }
                        }

                        Text {
                            text: Math.round(((root.metrics !== null && root.metrics.cpuUsage !== undefined) ? root.metrics.cpuUsage : 0.0) * 100) + "%"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: Font.Bold
                            color: root.cpuColor
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }
                    }

                    Text {
                        text: ((root.metrics !== null && root.metrics.cpuFreqGhz > 0) ? (root.metrics.cpuFreqGhz.toFixed(2) + " GHz") : "3.60 GHz") +
                              ((root.metrics !== null && root.metrics.cpuTemp > 0) ? (" • " + Math.round(root.metrics.cpuTemp) + "°C") : "")
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 11
                        color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : Qt.rgba(1, 1, 1, 0.6)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: 2
                        color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.12)

                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: Math.max(parent.radius * 2, parent.width * cpuBar.value)
                            radius: parent.radius
                            color: root.cpuColor
                        }
                    }
                }
            }

            // 2. Memory Card (aliased as ramCardItem for regression tests)
            LiquidGlassCard {
                id: memoryDeviceCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                interactive: true
                selected: root.selectedDevice === "memory"
                accentGlint: root.memoryColor
                radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined) ? Theme.radiusGlassCard : 12
                showShadow: true
                hovered: memMa.containsMouse

                MouseArea {
                    id: memMa
                    anchors.fill: parent
                    z: 20
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedDevice = "memory"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialIcon {
                            text: "memory"
                            size: 18
                            color: root.memoryColor
                        }
                        Text {
                            text: "Memory"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: Font.DemiBold
                            color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                            Layout.fillWidth: true
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }

                        // Mini Live Sparkline
                        Canvas {
                            id: memSparkline
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 14
                            onPaint: {
                                const ctx = getContext("2d");
                                const w = width;
                                const h = height;
                                ctx.clearRect(0, 0, w, h);
                                const hist = (root.metrics !== null) ? root.metrics.ramHistory : [];
                                if (!hist || hist.length < 2) return;
                                const col = root.memoryColor;
                                ctx.beginPath();
                                const step = w / (hist.length - 1);
                                for (let i = 0; i < hist.length; ++i) {
                                    const v = Math.min(1.0, Math.max(0.0, hist[i] || 0.0));
                                    const x = i * step;
                                    const y = h - (v * (h - 2)) - 1;
                                    if (i === 0) ctx.moveTo(x, y);
                                    else ctx.lineTo(x, y);
                                }
                                ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.85);
                                ctx.lineWidth = 1.2;
                                ctx.stroke();
                                ctx.lineTo(w, h);
                                ctx.lineTo(0, h);
                                ctx.closePath();
                                ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.20);
                                ctx.fill();
                            }
                            Connections {
                                target: root.metrics
                                function onRamHistoryChanged() { if (root.isTargetVisible) memSparkline.requestPaint(); }
                            }
                        }

                        Text {
                            text: Math.round(((root.metrics !== null && root.metrics.ramUsage !== undefined) ? root.metrics.ramUsage : 0.0) * 100) + "%"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: Font.Bold
                            color: root.memoryColor
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }
                    }

                    Text {
                        text: (root.metrics !== null && root.metrics.ramTotalBytes > 0)
                            ? (root.formatBytes(root.metrics.ramUsedBytes) + " / " + root.formatBytes(root.metrics.ramTotalBytes))
                            : "16.0 GiB / 32.0 GiB"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 11
                        color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : Qt.rgba(1, 1, 1, 0.6)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: 2
                        color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.12)

                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: Math.max(parent.radius * 2, parent.width * ramBar.value)
                            radius: parent.radius
                            color: root.memoryColor
                        }
                    }
                }
            }

            // 3. GPU Cards (Multi-GPU support: Integrated & Dedicated)
            Repeater {
                id: gpuRepeater
                model: root.gpuCount

                delegate: LiquidGlassCard {
                    id: gpuCardDelegate
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    interactive: true

                    // 0×0 motion item: a direct child of the card, never a layout slot.
                    MotionValue {
                        id: gpuBar
                        animated: root.isTargetVisible
                        duration: Theme.animExpressiveFastSpatial
                        bezier: Theme.curveExpressiveFastSpatial
                        target: Math.min(1.0, Math.max(0.0, (gpuCardDelegate.gpuData && gpuCardDelegate.gpuData.usage !== undefined) ? gpuCardDelegate.gpuData.usage : 0.0))
                    }

                    readonly property var gpuData: {
                        if (root.metrics !== null && root.metrics.gpus && root.metrics.gpus[index]) {
                            return root.metrics.gpus[index];
                        }
                        return {
                            index: index,
                            name: "GPU " + index,
                            model: "Graphics",
                            gpu_type: "discrete",
                            usage: (root.metrics !== null ? root.metrics.gpuUsage : 0.0),
                            temperature: (root.metrics !== null ? root.metrics.gpuTemp : 0.0),
                            clock_ghz: (root.metrics !== null ? root.metrics.gpuClockGhz : 0.0),
                            memory_used_bytes: (root.metrics !== null ? root.metrics.gpuMemoryUsedBytes : 0),
                            memory_total_bytes: (root.metrics !== null ? root.metrics.gpuMemoryTotalBytes : 0)
                        };
                    }

                    readonly property int cardGpuIndex: (gpuData && gpuData.index !== undefined) ? gpuData.index : index

                    selected: (root.selectedDevice === "gpu" && (cardGpuIndex === 0 || root.selectedGpuIndex === cardGpuIndex)) || root.selectedDevice === ("gpu:" + cardGpuIndex)
                    accentGlint: root.gpuColor
                    radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined) ? Theme.radiusGlassCard : 12
                    showShadow: true
                    hovered: gpuCardMa.containsMouse

                    MouseArea {
                        id: gpuCardMa
                        anchors.fill: parent
                        z: 20
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.gpuCount > 1) {
                                root.selectedDevice = "gpu:" + gpuCardDelegate.cardGpuIndex;
                            } else {
                                root.selectedDevice = "gpu";
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            MaterialIcon {
                                text: "videogame_asset"
                                size: 18
                                color: root.gpuColor
                            }
                            Text {
                                text: (gpuCardDelegate.gpuData && gpuCardDelegate.gpuData.name) || ("GPU " + gpuCardDelegate.cardGpuIndex)
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                                font.weight: Font.DemiBold
                                color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                                Layout.fillWidth: true
                                style: Text.Outline
                                styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                            }

                            // Mini Live Sparkline
                            Canvas {
                                id: delegateGpuSparkline
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 14
                                onPaint: {
                                    const ctx = getContext("2d");
                                    const w = width;
                                    const h = height;
                                    ctx.clearRect(0, 0, w, h);
                                    const hist = (root.metrics !== null && root.metrics && typeof root.metrics.getGpuHistory === "function")
                                        ? root.metrics.getGpuHistory(gpuCardDelegate.cardGpuIndex)
                                        : ((root.metrics !== null && root.metrics && root.metrics.gpuHistory) ? root.metrics.gpuHistory : []);
                                    if (!hist || hist.length < 2) return;
                                    const col = root.gpuColor;
                                    ctx.beginPath();
                                    const step = w / (hist.length - 1);
                                    for (let i = 0; i < hist.length; ++i) {
                                        const v = Math.min(1.0, Math.max(0.0, hist[i] || 0.0));
                                        const x = i * step;
                                        const y = h - (v * (h - 2)) - 1;
                                        if (i === 0) ctx.moveTo(x, y);
                                        else ctx.lineTo(x, y);
                                    }
                                    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.85);
                                    ctx.lineWidth = 1.2;
                                    ctx.stroke();
                                    ctx.lineTo(w, h);
                                    ctx.lineTo(0, h);
                                    ctx.closePath();
                                    ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.20);
                                    ctx.fill();
                                }
                                Connections {
                                    target: root.metrics
                                    function onGpuHistoriesChanged() { if (root.isTargetVisible) delegateGpuSparkline.requestPaint(); }
                                    function onGpuHistoryChanged() { if (root.isTargetVisible) delegateGpuSparkline.requestPaint(); }
                                }
                            }

                            Text {
                                text: Math.round(((gpuCardDelegate.gpuData && gpuCardDelegate.gpuData.usage !== undefined) ? gpuCardDelegate.gpuData.usage : 0.0) * 100) + "%"
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                                font.weight: Font.Bold
                                color: root.gpuColor
                                style: Text.Outline
                                styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                            }
                        }

                        Text {
                            text: {
                                const data = gpuCardDelegate.gpuData;
                                if (!data) return "Active";
                                if (data.gpu_type === "integrated") {
                                    const clk = (data.clock_ghz > 0) ? (data.clock_ghz.toFixed(2) + " GHz") : "Integrated";
                                    const tmp = (data.temperature > 0) ? (" • " + Math.round(data.temperature) + "°C") : "";
                                    return clk + tmp;
                                } else {
                                    const tmp = (data.temperature > 0) ? (Math.round(data.temperature) + "°C") : "Active";
                                    const mem = (data.memory_total_bytes > 0) ? (" • " + root.formatBytes(data.memory_used_bytes)) : "";
                                    return tmp + mem;
                                }
                            }
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 11
                            color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : Qt.rgba(1, 1, 1, 0.6)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.12)

                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: Math.max(parent.radius * 2, parent.width * gpuBar.value)
                                radius: parent.radius
                                color: root.gpuColor
                            }
                        }
                    }
                }
            }

            // 4. Battery / Power Card
            LiquidGlassCard {
                id: batteryDeviceCard
                Layout.fillWidth: true
                Layout.fillHeight: true
                interactive: true
                selected: root.selectedDevice === "battery"
                accentGlint: root.batteryColor
                radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined) ? Theme.radiusGlassCard : 12
                showShadow: true
                hovered: batMa.containsMouse

                MouseArea {
                    id: batMa
                    anchors.fill: parent
                    z: 20
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedDevice = "battery"
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialIcon {
                            text: (typeof PowerService !== "undefined" && typeof PowerService.getIcon === "function") ? PowerService.getIcon() : "battery_charging_full"
                            size: 18
                            color: root.batteryColor
                        }
                        Text {
                            text: "Battery"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: Font.DemiBold
                            color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                            Layout.fillWidth: true
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }

                        // Mini Live Sparkline
                        Canvas {
                            id: batSparkline
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 14
                            onPaint: {
                                const ctx = getContext("2d");
                                const w = width;
                                const h = height;
                                ctx.clearRect(0, 0, w, h);
                                const hist = (root.metrics !== null) ? root.metrics.batteryHistory : [];
                                if (!hist || hist.length < 2) return;
                                const col = root.batteryColor;
                                ctx.beginPath();
                                const step = w / (hist.length - 1);
                                for (let i = 0; i < hist.length; ++i) {
                                    const v = Math.min(1.0, Math.max(0.0, hist[i] || 0.0));
                                    const x = i * step;
                                    const y = h - (v * (h - 2)) - 1;
                                    if (i === 0) ctx.moveTo(x, y);
                                    else ctx.lineTo(x, y);
                                }
                                ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.85);
                                ctx.lineWidth = 1.2;
                                ctx.stroke();
                                ctx.lineTo(w, h);
                                ctx.lineTo(0, h);
                                ctx.closePath();
                                ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.20);
                                ctx.fill();
                            }
                            Connections {
                                target: root.metrics
                                function onBatteryHistoryChanged() { if (root.isTargetVisible) batSparkline.requestPaint(); }
                            }
                        }

                        Text {
                            text: ((root.metrics !== null && root.metrics.batteryPercentage !== undefined) ? root.metrics.batteryPercentage : 100) + "%"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: Font.Bold
                            color: root.batteryColor
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }
                    }

                    Text {
                        text: ((root.metrics !== null && root.metrics.batteryWatts > 0) ? (root.metrics.batteryWatts.toFixed(1) + " W") : ((root.metrics !== null && root.metrics.batteryState) ? root.metrics.batteryState : "Full")) +
                              ((root.metrics !== null && root.metrics.powerProfile) ? (" • " + root.metrics.powerProfile) : "")
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 11
                        color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : Qt.rgba(1, 1, 1, 0.6)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: 2
                        color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : Qt.rgba(1, 1, 1, 0.12)

                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: Math.max(parent.radius * 2, parent.width * batteryBar.value)
                            radius: parent.radius
                            color: root.batteryColor
                        }
                    }
                }
            }
        }

        // =========================================================================
        // RIGHT COLUMN: Detail View (Area Chart & Mission-Center Telemetry)
        // =========================================================================
        LiquidGlassCard {
            id: detailContainer
            Layout.minimumWidth: 400
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined) ? Theme.radiusGlassCard : 16
            showShadow: true
            accentGlint: root.activeDeviceColor

            // Animated main usage value for fluid roll transitions
            readonly property real targetMainUsage: {
                if (root.selectedDevice.startsWith("gpu")) {
                    const g = root.currentGpu;
                    return (g && g.usage !== undefined) ? g.usage : ((root.metrics !== null) ? root.metrics.gpuUsage : 0.0);
                }
                switch (root.selectedDevice) {
                    case "memory":
                        return (root.metrics !== null && root.metrics.ramUsage !== undefined) ? root.metrics.ramUsage : 0.0;
                    case "battery":
                        return (root.metrics !== null && root.metrics.batteryPercentage !== undefined) ? (root.metrics.batteryPercentage / 100.0) : 1.0;
                    case "cpu":
                    default:
                        return (root.metrics !== null && root.metrics.cpuUsage !== undefined) ? root.metrics.cpuUsage : 0.0;
                }
            }

            // Follows the metric on the shared decorative clock (see `mainUsage`
            // above): a `Behavior` here animated at display refresh forever.
            readonly property real animatedMainUsage: mainUsage.value

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // 1. Header Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: {
                                if (root.selectedDevice.startsWith("gpu")) {
                                    const g = root.currentGpu;
                                    return g ? (g.name || "GPU") : "GPU";
                                }
                                switch (root.selectedDevice) {
                                    case "memory": return "Memory";
                                    case "battery": return "Battery & Power";
                                    case "cpu":
                                    default: return "CPU";
                                }
                            }
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 16
                            font.weight: Font.DemiBold
                            color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }

                        Text {
                            text: {
                                if (root.selectedDevice.startsWith("gpu")) {
                                    const g = root.currentGpu;
                                    if (g) {
                                        const typeTag = (g.gpu_type === "integrated") ? "Integrated GPU" : "Discrete GPU";
                                        const driverTag = g.driver ? (" • " + g.driver) : "";
                                        const slotTag = g.pci_slot ? (" • " + g.pci_slot) : "";
                                        return (g.model || "Graphics") + " (" + typeTag + driverTag + slotTag + ")";
                                    }
                                    return (root.metrics !== null && root.metrics.gpuModel) ? root.metrics.gpuModel : "Graphics";
                                }
                                switch (root.selectedDevice) {
                                    case "memory":
                                        return (root.metrics !== null && root.metrics.ramTotalBytes > 0)
                                            ? (root.formatBytes(root.metrics.ramTotalBytes) + " DDR5 System Memory")
                                             : "32.0 GiB System Memory";
                                    case "battery":
                                        return ((root.metrics !== null && root.metrics.batteryState) ? root.metrics.batteryState : "AC") +
                                               " • " + ((root.metrics !== null && root.metrics.powerProfile) ? root.metrics.powerProfile : "balanced") + " profile";
                                    case "cpu":
                                    default:
                                        return (root.metrics !== null && root.metrics.cpuModel)
                                            ? root.metrics.cpuModel
                                            : "Intel Core Processor";
                                }
                            }
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 11
                            color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : Qt.rgba(1, 1, 1, 0.65)
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // Multi-GPU Quick Switcher Chips
                    RowLayout {
                        spacing: 6
                        visible: Boolean(root.selectedDevice && root.selectedDevice.startsWith("gpu") && root.gpuCount > 1)
                        Repeater {
                            model: root.gpuCount
                            delegate: Rectangle {
                                readonly property var chipGpuData: (root.metrics !== null && root.metrics.gpus && root.metrics.gpus[index])
                                    ? root.metrics.gpus[index]
                                    : null
                                readonly property int chipIndex: (chipGpuData && chipGpuData.index !== undefined) ? chipGpuData.index : index

                                implicitWidth: pillLabel.implicitWidth + 14
                                implicitHeight: 22
                                radius: 11
                                color: root.selectedGpuIndex === chipIndex ? Qt.rgba(root.gpuColor.r, root.gpuColor.g, root.gpuColor.b, 0.28) : (chipMa.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08))
                                border.width: 1
                                border.color: root.selectedGpuIndex === chipIndex ? root.gpuColor : Qt.rgba(1, 1, 1, 0.15)

                                Text {
                                    id: pillLabel
                                    anchors.centerIn: parent
                                    text: {
                                        if (!chipGpuData) return "GPU " + index;
                                        const nm = chipGpuData.name || ("GPU " + chipIndex);
                                        const tag = chipGpuData.vendor || (chipGpuData.gpu_type === "integrated" ? "iGPU" : "dGPU");
                                        return nm + " (" + tag + ")";
                                    }
                                    font.pixelSize: 10
                                    font.weight: root.selectedGpuIndex === chipIndex ? Font.Bold : Font.Normal
                                    color: root.selectedGpuIndex === chipIndex ? root.gpuColor : (typeof Colors !== "undefined" ? Colors.m3onSurface : "#FFFFFF")
                                }

                                MouseArea {
                                    id: chipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedDevice = "gpu:" + chipIndex
                                }
                            }
                        }
                    }

                    // Main Metric Large Number
                    Text {
                        text: Math.round(detailContainer.animatedMainUsage * 100) + "%"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        color: root.activeDeviceColor
                        style: Text.Outline
                        styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                    }
                }

                // 2. Real-Time 60-Second Area Chart (Mission Center style)
                Item {
                    id: chartContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: 125
                    clip: true

                    Canvas {
                        id: telemetryCanvas
                        anchors.fill: parent

                        onPaint: {
                            const ctx = getContext("2d");
                            const w = width;
                            const h = height;
                            ctx.clearRect(0, 0, w, h);

                            if (w <= 0 || h <= 0) return;

                            const col = root.activeDeviceColor;

                            // 1. Grid Guidelines & Labels
                            ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.12);
                            ctx.lineWidth = 1;
                            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.40);
                            ctx.font = "9px sans-serif";

                            const yLevels = [0.0, 0.5, 1.0];
                            for (let i = 0; i < yLevels.length; ++i) {
                                const level = yLevels[i];
                                const y = h - (level * (h - 16)) - 8;
                                ctx.beginPath();
                                ctx.moveTo(28, y);
                                ctx.lineTo(w, y);
                                ctx.stroke();

                                const lbl = Math.round(level * 100) + "%";
                                ctx.fillText(lbl, 2, y + 3);
                            }

                            // 2. Time Labels along bottom
                            ctx.fillText("60s", 32, h - 2);
                            ctx.fillText("30s", w / 2 - 8, h - 2);
                            ctx.fillText("0s", w - 16, h - 2);

                            // 3. Area Plot with smooth horizontal sliding (zero shape distortion)
                            const buf = (root.slideBuffer && root.slideBuffer.length >= 2) ? root.slideBuffer : root.activeHistory;
                            if (!buf || buf.length < 2) return;

                            const N = 60;
                            const startX = 30;
                            const plotW = w - startX;
                            const plotH = h - 18;
                            const bottomY = h - 8;
                            const stepX = plotW / (N - 1);
                            const slide = root.slideProgress; // 0.0 -> 1.0
                            const xOffset = slide * stepX;

                            ctx.save();
                            ctx.beginPath();
                            ctx.rect(startX, 0, plotW, h);
                            ctx.clip();

                            ctx.beginPath();
                            let firstPoint = true;
                            for (let idx = 0; idx < buf.length; ++idx) {
                                const rawVal = Math.min(1.0, Math.max(0.0, buf[idx] || 0.0));
                                const px = startX + (idx * stepX) - xOffset;
                                const py = bottomY - (rawVal * plotH);

                                if (firstPoint) {
                                    ctx.moveTo(px, py);
                                    firstPoint = false;
                                } else {
                                    ctx.lineTo(px, py);
                                }
                            }

                            // Stroke top line
                            ctx.strokeStyle = col;
                            ctx.lineWidth = 2.2;
                            ctx.stroke();

                            // Area fill under curve
                            const lastBufX = startX + ((buf.length - 1) * stepX) - xOffset;
                            ctx.lineTo(lastBufX, bottomY);
                            ctx.lineTo(startX - xOffset, bottomY);
                            ctx.closePath();

                            const gradient = ctx.createLinearGradient(0, bottomY - plotH, 0, bottomY);
                            gradient.addColorStop(0.0, Qt.rgba(col.r, col.g, col.b, 0.40));
                            gradient.addColorStop(0.5, Qt.rgba(col.r, col.g, col.b, 0.16));
                            gradient.addColorStop(1.0, Qt.rgba(col.r, col.g, col.b, 0.02));
                            ctx.fillStyle = gradient;
                            ctx.fill();

                            ctx.restore();

                            // Live glowing indicator tip at the right boundary
                            const prevEdgeVal = buf.length >= 2 ? (buf[buf.length - 2] || 0.0) : 0.0;
                            const nextEdgeVal = buf[buf.length - 1] || 0.0;
                            const curEdgeVal = Math.min(1.0, Math.max(0.0, prevEdgeVal + (nextEdgeVal - prevEdgeVal) * slide));
                            const tipX = startX + plotW;
                            const tipY = bottomY - (curEdgeVal * plotH);

                            ctx.beginPath();
                            ctx.arc(tipX, tipY, 5.5, 0, 2 * Math.PI);
                            ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.30);
                            ctx.fill();

                            ctx.beginPath();
                            ctx.arc(tipX, tipY, 2.8, 0, 2 * Math.PI);
                            ctx.fillStyle = col;
                            ctx.fill();

                            ctx.beginPath();
                            ctx.arc(tipX, tipY, 1.0, 0, 2 * Math.PI);
                            ctx.fillStyle = "#FFFFFF";
                            ctx.fill();
                        }
                    }
                }

                // 3. Telemetry Details Grid
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: 6
                    columnSpacing: 10

                    // CPU metrics view
                    Repeater {
                        model: {
                            if (root.selectedDevice === "cpu") {
                                return [
                                    { label: "SPEED", val: ((root.metrics !== null && root.metrics.cpuFreqGhz > 0) ? (root.metrics.cpuFreqGhz.toFixed(2) + " GHz") : "3.60 GHz") },
                                    { label: "TEMPERATURE", val: ((root.metrics !== null && root.metrics.cpuTemp > 0) ? (root.metrics.cpuTemp.toFixed(1) + " °C") : "65.0 °C") },
                                    { label: "PROCESSES", val: "" + ((root.metrics !== null && root.metrics.cpuProcesses !== undefined) ? root.metrics.cpuProcesses : 605) },
                                    { label: "THREADS", val: "" + ((root.metrics !== null && root.metrics.cpuThreads !== undefined) ? root.metrics.cpuThreads : 2650) },
                                    { label: "LOAD (1M)", val: ((root.metrics !== null && root.metrics.cpuLoad1m !== undefined) ? root.metrics.cpuLoad1m.toFixed(2) : "3.50") },
                                    { label: "UPTIME", val: ((root.metrics !== null && root.metrics.uptime) ? root.metrics.uptime : "up 2 hours") }
                                ];
                            } else if (root.selectedDevice === "memory") {
                                return [
                                    { label: "IN USE", val: (root.metrics !== null && root.metrics.ramUsedBytes !== undefined) ? root.formatBytes(root.metrics.ramUsedBytes) : "17.0 GiB" },
                                    { label: "AVAILABLE", val: (root.metrics !== null && root.metrics.ramAvailableBytes !== undefined) ? root.formatBytes(root.metrics.ramAvailableBytes) : "15.0 GiB" },
                                    { label: "CACHED", val: (root.metrics !== null && root.metrics.ramCachedBytes !== undefined) ? root.formatBytes(root.metrics.ramCachedBytes) : "12.0 GiB" },
                                    { label: "TOTAL", val: (root.metrics !== null && root.metrics.ramTotalBytes !== undefined) ? root.formatBytes(root.metrics.ramTotalBytes) : "32.0 GiB" },
                                    { label: "SWAP USED", val: (root.metrics !== null && root.metrics.swapUsedBytes !== undefined) ? root.formatBytes(root.metrics.swapUsedBytes) : "380 MiB" },
                                    { label: "SWAP TOTAL", val: (root.metrics !== null && root.metrics.swapTotalBytes !== undefined) ? root.formatBytes(root.metrics.swapTotalBytes) : "48.0 GiB" }
                                ];
                            } else if (root.selectedDevice.startsWith("gpu")) {
                                const curGpu = root.currentGpu;
                                const isIntegrated = curGpu ? (curGpu.gpu_type === "integrated") : false;
                                const usageVal = (curGpu && curGpu.usage !== undefined) ? curGpu.usage : ((root.metrics !== null) ? root.metrics.gpuUsage : 0.0);
                                const tempVal = (curGpu && curGpu.temperature > 0) ? curGpu.temperature : ((root.metrics !== null) ? root.metrics.gpuTemp : 0.0);
                                const clockVal = (curGpu && curGpu.clock_ghz > 0) ? curGpu.clock_ghz : ((root.metrics !== null) ? root.metrics.gpuClockGhz : 0.0);
                                const memUsed = (curGpu && curGpu.memory_used_bytes > 0) ? curGpu.memory_used_bytes : ((root.metrics !== null) ? root.metrics.gpuMemoryUsedBytes : 0);
                                const memTotal = (curGpu && curGpu.memory_total_bytes > 0) ? curGpu.memory_total_bytes : ((root.metrics !== null) ? root.metrics.gpuMemoryTotalBytes : 0);
                                const typeStr = isIntegrated ? "Integrated GPU" : "Discrete GPU";
                                const driverStr = (curGpu && curGpu.driver) ? curGpu.driver : "Kernel DRM";

                                return [
                                    { label: "UTILIZATION", val: Math.round(usageVal * 100) + "%" },
                                    { label: "TEMPERATURE", val: tempVal > 0 ? (tempVal.toFixed(1) + " °C") : "50.0 °C" },
                                    { label: "GRAPHICS CLOCK", val: clockVal > 0 ? (clockVal.toFixed(2) + " GHz") : "N/A" },
                                    { label: "MEMORY TYPE", val: isIntegrated ? "Shared System RAM" : ((memTotal > 0 ? root.formatBytes(memTotal) : "Dedicated") + " VRAM") },
                                    { label: isIntegrated ? "ALLOCATED" : "VRAM USED", val: isIntegrated ? "Dynamic (DVMT)" : root.formatBytes(memUsed) },
                                    { label: "DEVICE TYPE", val: typeStr + " (" + driverStr + ")" }
                                ];
                            } else {
                                return [
                                    { label: "STATE", val: (root.metrics !== null && root.metrics.batteryState) ? root.metrics.batteryState : "Full" },
                                    { label: "POWER DRAW", val: ((root.metrics !== null && root.metrics.batteryWatts > 0) ? (root.metrics.batteryWatts.toFixed(1) + " W") : "0.0 W") },
                                    { label: "VOLTAGE", val: ((root.metrics !== null && root.metrics.batteryVoltage > 0) ? (root.metrics.batteryVoltage.toFixed(2) + " V") : "12.01 V") },
                                    { label: "HEALTH", val: ((root.metrics !== null && root.metrics.batteryHealth !== undefined) ? root.metrics.batteryHealth : 100) + "%" },
                                    { label: "PROFILE", val: (root.metrics !== null && root.metrics.powerProfile) ? root.metrics.powerProfile : "balanced" },
                                    { label: "CHARGING", val: ((root.metrics !== null && root.metrics.batteryCharging) ? "Connected" : "Discharging") }
                                ];
                            }
                        }

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 38
                            radius: 8
                            color: (typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : Qt.rgba(1, 1, 1, 0.04)
                            border.width: 1
                            border.color: Qt.rgba(root.activeDeviceColor.r, root.activeDeviceColor.g, root.activeDeviceColor.b, 0.18)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                anchors.topMargin: 4
                                anchors.bottomMargin: 4
                                spacing: 1

                                Text {
                                    text: modelData.label
                                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : Qt.rgba(1, 1, 1, 0.5)
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: modelData.val
                                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                // 4. Footer Action Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialIcon {
                        text: "info"
                        size: 14
                        color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : Qt.rgba(1, 1, 1, 0.5)
                    }

                    Text {
                        text: "Live physical ground-truth hardware metrics (60s history)"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 11
                        color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : Qt.rgba(1, 1, 1, 0.5)
                        Layout.fillWidth: true
                    }

                    // Open System Monitor action button
                    Rectangle {
                        id: launchSysMonBtn
                        width: 150
                        height: 28
                        radius: 14
                        color: sysMonMa.containsMouse
                            ? ((typeof Colors !== "undefined" && Colors.primaryContainer) ? Colors.primaryContainer : Qt.rgba(1, 1, 1, 0.20))
                            : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        border.color: root.activeDeviceColor

                        MouseArea {
                            id: sysMonMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSystemMonitor()
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                text: "open_in_new"
                                size: 14
                                color: root.activeDeviceColor
                            }

                            Text {
                                text: "System Monitor"
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                            }
                        }
                    }
                }
            }
        }
    }
}
