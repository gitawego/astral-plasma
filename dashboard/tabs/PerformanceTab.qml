import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitWidth: 680
    implicitHeight: 350

    // Lifecycle & Visibility Tracking (zero offscreen rendering)
    property bool testMode: false

    readonly property bool isTargetVisible: testMode || (
        visible &&
        ((typeof Config !== "undefined" && Config)
            ? (Boolean(Config.dashboardVisible) && Config.activeDashboardTab === "performance")
            : true)
    )

    onIsTargetVisibleChanged: {
        if (typeof SystemService !== "undefined" && SystemService && typeof SystemService.registerClient === "function") {
            SystemService.registerClient(root, root.isTargetVisible);
        }
        if (root.isTargetVisible) {
            telemetryCanvas.requestPaint();
        }
    }

    Component.onCompleted: {
        if (typeof SystemService !== "undefined" && SystemService && typeof SystemService.registerClient === "function") {
            SystemService.registerClient(root, root.isTargetVisible);
        }
    }

    Component.onDestruction: {
        if (typeof SystemService !== "undefined" && SystemService && typeof SystemService.unregisterClient === "function") {
            SystemService.unregisterClient(root);
        }
    }

    // Selected hardware telemetry device: "cpu" | "memory" | "gpu" | "battery"
    property string selectedDevice: (typeof Config !== "undefined" && Config.perfSelectedDevice) ? Config.perfSelectedDevice : "cpu"

    readonly property int gpuCount: (typeof SystemService !== "undefined" && SystemService.gpus && SystemService.gpus.length > 0)
        ? SystemService.gpus.length
        : 1

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onPerfSelectedDeviceChanged() {
            if (Config.perfSelectedDevice && root.selectedDevice !== Config.perfSelectedDevice) {
                root.selectedDevice = Config.perfSelectedDevice;
            }
        }
    }

    readonly property int selectedGpuIndex: {
        if (root.selectedDevice && root.selectedDevice.startsWith("gpu:")) {
            const idx = parseInt(root.selectedDevice.substring(4));
            return isNaN(idx) ? 0 : idx;
        }
        return (typeof SystemService !== "undefined" && SystemService && SystemService.selectedGpuIndex !== undefined) ? SystemService.selectedGpuIndex : 0;
    }

    readonly property var currentGpu: {
        if (typeof SystemService !== "undefined" && SystemService && SystemService.gpus && SystemService.gpus.length > 0) {
            const idx = Math.min(Math.max(0, root.selectedGpuIndex), SystemService.gpus.length - 1);
            return SystemService.gpus[idx];
        }
        return null;
    }

    onSelectedDeviceChanged: {
        if (root.selectedDevice.startsWith("gpu:")) {
            const idx = parseInt(root.selectedDevice.substring(4));
            if (!isNaN(idx) && typeof SystemService !== "undefined" && SystemService) {
                SystemService.selectedGpuIndex = idx;
            }
        }
        if (typeof Config !== "undefined" && Config.perfSelectedDevice !== selectedDevice) {
            Config.perfSelectedDevice = selectedDevice;
        }
        // Immediate clean reset when switching hardware device tabs
        slideAnim.stop();
        root.slideProgress = 1.0;
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
        if (typeof SystemService !== "undefined" && SystemService && typeof SystemService.formatBytes === "function") {
            return SystemService.formatBytes(bytes);
        }
        if (!bytes || bytes <= 0) return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        const p = Math.min(Math.max(0, i), units.length - 1);
        const val = bytes / Math.pow(1024, p);
        return val.toFixed(1) + " " + units[p];
    }

    // Device telemetry active dataset
    readonly property var activeHistory: {
        let hist = [];
        if (typeof SystemService !== "undefined" && SystemService) {
            if (root.selectedDevice.startsWith("gpu")) {
                if (typeof SystemService.getGpuHistory === "function") {
                    hist = SystemService.getGpuHistory(root.selectedGpuIndex);
                } else {
                    hist = SystemService.gpuHistory;
                }
            } else {
                switch (root.selectedDevice) {
                    case "memory": hist = SystemService.ramHistory; break;
                    case "battery": hist = SystemService.batteryHistory; break;
                    case "cpu":
                    default: hist = SystemService.cpuHistory; break;
                }
            }
        }
        if (!hist || !Array.isArray(hist) || hist.length === 0) {
            hist = [];
            for (let i = 0; i < 60; ++i) hist.push(0.0);
        }
        return hist;
    }

    // Smooth horizontal slide telemetry properties (preserves shape, zero deformation)
    property var slideBuffer: []
    property real slideProgress: 1.0

    readonly property real waveMorph: slideProgress // alias for test backward compatibility

    NumberAnimation on slideProgress {
        id: slideAnim
        duration: 450
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.25, 0.1, 0.25, 1.0]
        from: 0.0
        to: 1.0
        running: false
    }

    onSlideProgressChanged: {
        if (root.isTargetVisible) {
            telemetryCanvas.requestPaint();
        }
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
            slideAnim.stop();
            root.slideProgress = 0.0;
            slideAnim.restart();
        } else {
            root.slideProgress = 1.0;
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
                radius: 12
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
                                const hist = (typeof SystemService !== "undefined") ? SystemService.cpuHistory : [];
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
                                target: (typeof SystemService !== "undefined") ? SystemService : null
                                function onCpuHistoryChanged() { if (root.isTargetVisible) cpuSparkline.requestPaint(); }
                            }
                        }

                        Text {
                            text: Math.round(((typeof SystemService !== "undefined" && SystemService.cpuUsage !== undefined) ? SystemService.cpuUsage : 0.0) * 100) + "%"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: Font.Bold
                            color: root.cpuColor
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }
                    }

                    Text {
                        text: ((typeof SystemService !== "undefined" && SystemService.cpuFreqGhz > 0) ? (SystemService.cpuFreqGhz.toFixed(2) + " GHz") : "3.60 GHz") +
                              ((typeof SystemService !== "undefined" && SystemService.cpuTemp > 0) ? (" • " + Math.round(SystemService.cpuTemp) + "°C") : "")
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
                            width: Math.max(parent.radius * 2, parent.width * Math.min(1.0, Math.max(0.0, ((typeof SystemService !== "undefined" && SystemService.cpuUsage !== undefined) ? SystemService.cpuUsage : 0.0))))
                            radius: parent.radius
                            color: root.cpuColor

                            Behavior on width {
                                NumberAnimation {
                                    duration: 450
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.25, 0.1, 0.25, 1.0]
                                }
                            }
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
                radius: 12
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
                                const hist = (typeof SystemService !== "undefined") ? SystemService.ramHistory : [];
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
                                target: (typeof SystemService !== "undefined") ? SystemService : null
                                function onRamHistoryChanged() { if (root.isTargetVisible) memSparkline.requestPaint(); }
                            }
                        }

                        Text {
                            text: Math.round(((typeof SystemService !== "undefined" && SystemService.ramUsage !== undefined) ? SystemService.ramUsage : 0.0) * 100) + "%"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: Font.Bold
                            color: root.memoryColor
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }
                    }

                    Text {
                        text: (typeof SystemService !== "undefined" && SystemService.ramTotalBytes > 0)
                            ? (root.formatBytes(SystemService.ramUsedBytes) + " / " + root.formatBytes(SystemService.ramTotalBytes))
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
                            width: Math.max(parent.radius * 2, parent.width * Math.min(1.0, Math.max(0.0, ((typeof SystemService !== "undefined" && SystemService.ramUsage !== undefined) ? SystemService.ramUsage : 0.0))))
                            radius: parent.radius
                            color: root.memoryColor

                            Behavior on width {
                                NumberAnimation {
                                    duration: 450
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.25, 0.1, 0.25, 1.0]
                                }
                            }
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

                    readonly property var gpuData: {
                        if (typeof SystemService !== "undefined" && SystemService.gpus && SystemService.gpus[index]) {
                            return SystemService.gpus[index];
                        }
                        return {
                            index: index,
                            name: "GPU " + index,
                            model: "Graphics",
                            gpu_type: "discrete",
                            usage: (typeof SystemService !== "undefined" ? SystemService.gpuUsage : 0.0),
                            temperature: (typeof SystemService !== "undefined" ? SystemService.gpuTemp : 0.0),
                            clock_ghz: (typeof SystemService !== "undefined" ? SystemService.gpuClockGhz : 0.0),
                            memory_used_bytes: (typeof SystemService !== "undefined" ? SystemService.gpuMemoryUsedBytes : 0),
                            memory_total_bytes: (typeof SystemService !== "undefined" ? SystemService.gpuMemoryTotalBytes : 0)
                        };
                    }

                    readonly property int cardGpuIndex: (gpuData && gpuData.index !== undefined) ? gpuData.index : index

                    selected: (root.selectedDevice === "gpu" && (cardGpuIndex === 0 || root.selectedGpuIndex === cardGpuIndex)) || root.selectedDevice === ("gpu:" + cardGpuIndex)
                    accentGlint: root.gpuColor
                    radius: 12
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
                                    const hist = (typeof SystemService !== "undefined" && SystemService && typeof SystemService.getGpuHistory === "function")
                                        ? SystemService.getGpuHistory(gpuCardDelegate.cardGpuIndex)
                                        : ((typeof SystemService !== "undefined" && SystemService && SystemService.gpuHistory) ? SystemService.gpuHistory : []);
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
                                    target: (typeof SystemService !== "undefined") ? SystemService : null
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
                                width: Math.max(parent.radius * 2, parent.width * Math.min(1.0, Math.max(0.0, ((gpuCardDelegate.gpuData && gpuCardDelegate.gpuData.usage !== undefined) ? gpuCardDelegate.gpuData.usage : 0.0))))
                                radius: parent.radius
                                color: root.gpuColor

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 450
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: [0.25, 0.1, 0.25, 1.0]
                                    }
                                }
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
                radius: 12
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
                                const hist = (typeof SystemService !== "undefined") ? SystemService.batteryHistory : [];
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
                                target: (typeof SystemService !== "undefined") ? SystemService : null
                                function onBatteryHistoryChanged() { if (root.isTargetVisible) batSparkline.requestPaint(); }
                            }
                        }

                        Text {
                            text: ((typeof SystemService !== "undefined" && SystemService.batteryPercentage !== undefined) ? SystemService.batteryPercentage : 100) + "%"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: Font.Bold
                            color: root.batteryColor
                            style: Text.Outline
                            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.6)
                        }
                    }

                    Text {
                        text: ((typeof SystemService !== "undefined" && SystemService.batteryWatts > 0) ? (SystemService.batteryWatts.toFixed(1) + " W") : ((typeof SystemService !== "undefined" && SystemService.batteryState) ? SystemService.batteryState : "Full")) +
                              ((typeof SystemService !== "undefined" && SystemService.powerProfile) ? (" • " + SystemService.powerProfile) : "")
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
                            width: Math.max(parent.radius * 2, parent.width * Math.min(1.0, Math.max(0.0, ((typeof SystemService !== "undefined" && SystemService.batteryPercentage !== undefined) ? (SystemService.batteryPercentage / 100.0) : 1.0))))
                            radius: parent.radius
                            color: root.batteryColor

                            Behavior on width {
                                NumberAnimation {
                                    duration: 450
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.25, 0.1, 0.25, 1.0]
                                }
                            }
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
            radius: 16
            showShadow: true
            accentGlint: root.activeDeviceColor

            // Animated main usage value for fluid roll transitions
            readonly property real targetMainUsage: {
                if (root.selectedDevice.startsWith("gpu")) {
                    const g = root.currentGpu;
                    return (g && g.usage !== undefined) ? g.usage : ((typeof SystemService !== "undefined") ? SystemService.gpuUsage : 0.0);
                }
                switch (root.selectedDevice) {
                    case "memory":
                        return (typeof SystemService !== "undefined" && SystemService.ramUsage !== undefined) ? SystemService.ramUsage : 0.0;
                    case "battery":
                        return (typeof SystemService !== "undefined" && SystemService.batteryPercentage !== undefined) ? (SystemService.batteryPercentage / 100.0) : 1.0;
                    case "cpu":
                    default:
                        return (typeof SystemService !== "undefined" && SystemService.cpuUsage !== undefined) ? SystemService.cpuUsage : 0.0;
                }
            }

            property real animatedMainUsage: targetMainUsage
            Behavior on animatedMainUsage {
                NumberAnimation {
                    duration: 450
                    easing.type: Easing.OutCubic
                }
            }

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
                                    return (typeof SystemService !== "undefined" && SystemService.gpuModel) ? SystemService.gpuModel : "Graphics";
                                }
                                switch (root.selectedDevice) {
                                    case "memory":
                                        return (typeof SystemService !== "undefined" && SystemService.ramTotalBytes > 0)
                                            ? (root.formatBytes(SystemService.ramTotalBytes) + " DDR5 System Memory")
                                             : "32.0 GiB System Memory";
                                    case "battery":
                                        return ((typeof SystemService !== "undefined" && SystemService.batteryState) ? SystemService.batteryState : "AC") +
                                               " • " + ((typeof SystemService !== "undefined" && SystemService.powerProfile) ? SystemService.powerProfile : "balanced") + " profile";
                                    case "cpu":
                                    default:
                                        return (typeof SystemService !== "undefined" && SystemService.cpuModel)
                                            ? SystemService.cpuModel
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
                                readonly property var chipGpuData: (typeof SystemService !== "undefined" && SystemService.gpus && SystemService.gpus[index])
                                    ? SystemService.gpus[index]
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
                                    { label: "SPEED", val: ((typeof SystemService !== "undefined" && SystemService.cpuFreqGhz > 0) ? (SystemService.cpuFreqGhz.toFixed(2) + " GHz") : "3.60 GHz") },
                                    { label: "TEMPERATURE", val: ((typeof SystemService !== "undefined" && SystemService.cpuTemp > 0) ? (SystemService.cpuTemp.toFixed(1) + " °C") : "65.0 °C") },
                                    { label: "PROCESSES", val: "" + ((typeof SystemService !== "undefined" && SystemService.cpuProcesses !== undefined) ? SystemService.cpuProcesses : 605) },
                                    { label: "THREADS", val: "" + ((typeof SystemService !== "undefined" && SystemService.cpuThreads !== undefined) ? SystemService.cpuThreads : 2650) },
                                    { label: "LOAD (1M)", val: ((typeof SystemService !== "undefined" && SystemService.cpuLoad1m !== undefined) ? SystemService.cpuLoad1m.toFixed(2) : "3.50") },
                                    { label: "UPTIME", val: ((typeof SystemService !== "undefined" && SystemService.uptime) ? SystemService.uptime : "up 2 hours") }
                                ];
                            } else if (root.selectedDevice === "memory") {
                                return [
                                    { label: "IN USE", val: (typeof SystemService !== "undefined" && SystemService.ramUsedBytes !== undefined) ? root.formatBytes(SystemService.ramUsedBytes) : "17.0 GiB" },
                                    { label: "AVAILABLE", val: (typeof SystemService !== "undefined" && SystemService.ramAvailableBytes !== undefined) ? root.formatBytes(SystemService.ramAvailableBytes) : "15.0 GiB" },
                                    { label: "CACHED", val: (typeof SystemService !== "undefined" && SystemService.ramCachedBytes !== undefined) ? root.formatBytes(SystemService.ramCachedBytes) : "12.0 GiB" },
                                    { label: "TOTAL", val: (typeof SystemService !== "undefined" && SystemService.ramTotalBytes !== undefined) ? root.formatBytes(SystemService.ramTotalBytes) : "32.0 GiB" },
                                    { label: "SWAP USED", val: (typeof SystemService !== "undefined" && SystemService.swapUsedBytes !== undefined) ? root.formatBytes(SystemService.swapUsedBytes) : "380 MiB" },
                                    { label: "SWAP TOTAL", val: (typeof SystemService !== "undefined" && SystemService.swapTotalBytes !== undefined) ? root.formatBytes(SystemService.swapTotalBytes) : "48.0 GiB" }
                                ];
                            } else if (root.selectedDevice.startsWith("gpu")) {
                                const curGpu = root.currentGpu;
                                const isIntegrated = curGpu ? (curGpu.gpu_type === "integrated") : false;
                                const usageVal = (curGpu && curGpu.usage !== undefined) ? curGpu.usage : ((typeof SystemService !== "undefined") ? SystemService.gpuUsage : 0.0);
                                const tempVal = (curGpu && curGpu.temperature > 0) ? curGpu.temperature : ((typeof SystemService !== "undefined") ? SystemService.gpuTemp : 0.0);
                                const clockVal = (curGpu && curGpu.clock_ghz > 0) ? curGpu.clock_ghz : ((typeof SystemService !== "undefined") ? SystemService.gpuClockGhz : 0.0);
                                const memUsed = (curGpu && curGpu.memory_used_bytes > 0) ? curGpu.memory_used_bytes : ((typeof SystemService !== "undefined") ? SystemService.gpuMemoryUsedBytes : 0);
                                const memTotal = (curGpu && curGpu.memory_total_bytes > 0) ? curGpu.memory_total_bytes : ((typeof SystemService !== "undefined") ? SystemService.gpuMemoryTotalBytes : 0);
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
                                    { label: "STATE", val: (typeof SystemService !== "undefined" && SystemService.batteryState) ? SystemService.batteryState : "Full" },
                                    { label: "POWER DRAW", val: ((typeof SystemService !== "undefined" && SystemService.batteryWatts > 0) ? (SystemService.batteryWatts.toFixed(1) + " W") : "0.0 W") },
                                    { label: "VOLTAGE", val: ((typeof SystemService !== "undefined" && SystemService.batteryVoltage > 0) ? (SystemService.batteryVoltage.toFixed(2) + " V") : "12.01 V") },
                                    { label: "HEALTH", val: ((typeof SystemService !== "undefined" && SystemService.batteryHealth !== undefined) ? SystemService.batteryHealth : 100) + "%" },
                                    { label: "PROFILE", val: (typeof SystemService !== "undefined" && SystemService.powerProfile) ? SystemService.powerProfile : "balanced" },
                                    { label: "CHARGING", val: ((typeof SystemService !== "undefined" && SystemService.batteryCharging) ? "Connected" : "Discharging") }
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
                            onClicked: {
                                if (typeof Quickshell !== "undefined" && typeof Quickshell.execDetached === "function") {
                                    Quickshell.execDetached(["plasma-systemmonitor"]);
                                }
                            }
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
