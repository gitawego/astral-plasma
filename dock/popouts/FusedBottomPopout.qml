pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.theme
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property string mode: "default" // "default", "bluetooth", "network", "audio", "power", "clock"

    property var currentDate: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.currentDate = new Date()
    }

    readonly property real targetPopWidth: {
        switch (root.mode) {
            case "bluetooth": return 300;
            case "network": return 300;
            case "audio": return 280;
            case "power": return 260;
            case "clock":
            case "time": return 300;
            case "tray": return 380;
            case "app": return 350;
            default: return 280;
        }
    }
    property real popWidth: targetPopWidth
    Behavior on popWidth {
        NumberAnimation {
            duration: Theme.animExpressiveDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
        }
    }

    readonly property real targetContentHeight: {
        switch (root.mode) {
            case "bluetooth": return bluetoothSection.implicitHeight;
            case "network": return networkSection.implicitHeight;
            case "audio": return audioSection.implicitHeight;
            case "power": return powerSection.implicitHeight;
            case "clock":
            case "time": return clockSection.implicitHeight;
            case "tray": return traySection.implicitHeight;
            case "app": return appSection.implicitHeight;
            default: return defaultSection.implicitHeight;
        }
    }

    implicitWidth: popWidth
    implicitHeight: popCard.implicitHeight

    readonly property real appIconCenterY: 49.5
    readonly property real trayIconCenterY: 49.5

    function openTraySubmenu(indexOrTitle) {
        if (!traySection) return false;
        let items = traySection.currentTrayItems;
        for (let i = 0; i < items.length; i++) {
            let it = items[i];
            if (it && (it.label.indexOf(indexOrTitle) !== -1 || ("" + i) === indexOrTitle)) {
                if ((it.hasSubmenu || (it.children && it.children.length > 0)) && it.children && it.children.length > 0) {
                    traySection.pushSubmenu(it.label || "Submenu", it.children);
                    return true;
                }
            }
        }
        return false;
    }

    function popTraySubmenu() {
        if (!traySection || traySection.traySubmenuStack.length === 0) return false;
        traySection.popSubmenu();
        return true;
    }

    Item {
        id: popCard
        width: root.popWidth
        implicitHeight: root.targetContentHeight + Theme.padLarge * 2
        height: implicitHeight + Config.borderThickness

        HoverHandler {
            id: popCardHover
            onHoveredChanged: {
                if (hovered) {
                    Config.keepBottomPopout();
                } else {
                    Config.scheduleCloseBottomPopout();
                }
            }
        }

        Item {
            id: contentLoader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.padLarge
            height: root.targetContentHeight

            // ==========================================
            // 1. DEFAULT STATUS / BATTERY & POWER PROFILES (Screenshot 1)
            // ==========================================
            ColumnLayout {
                id: defaultSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Theme.spaceMedium
                readonly property bool isCurrent: root.mode === "default" || root.mode === "battery"
                visible: isCurrent
                opacity: isCurrent ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: PowerService.batteryString
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontMedium
                        font.weight: Font.DemiBold
                        color: Colors.textOnSurface
                    }

                    Text {
                        text: "Power profile: " + PowerService.currentProfile.charAt(0).toUpperCase() + PowerService.currentProfile.slice(1)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSmall
                        color: Colors.textOnSurfaceVariant
                    }
                }

                // Compact Power Profile Pill matching design
                Rectangle {
                    Layout.alignment: Qt.AlignLeft
                    implicitWidth: 124
                    implicitHeight: 32
                    radius: Theme.radiusFull
                    color: Colors.surfaceContainer
                    border.color: Theme.borderSubtle
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 2

                        Repeater {
                            model: [
                                { id: "power-saver", icon: "energy_savings_leaf" },
                                { id: "balanced", icon: "balance" },
                                { id: "performance", icon: "rocket_launch" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool isCurrent: PowerService.currentProfile === modelData.id

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Theme.radiusFull
                                color: isCurrent ? Colors.primary : (profileHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    size: 16
                                    color: isCurrent ? Colors.textOnPrimary : Colors.textOnSurfaceVariant
                                }

                                MouseArea {
                                    id: profileHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: PowerService.setProfile(modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // ==========================================
            // 2. BLUETOOTH ACTIONS LIST (Screenshot 2)
            // ==========================================
            ColumnLayout {
                id: bluetoothSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 2
                readonly property bool isCurrent: root.mode === "bluetooth"
                visible: isCurrent
                opacity: isCurrent ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }

                ActionItem {
                    icon: "bluetooth"
                    label: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled) ? "Turn Bluetooth Off" : "Turn Bluetooth On"
                    onClicked: {
                        if (Bluetooth.defaultAdapter) {
                            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
                        } else {
                            Quickshell.execDetached(["bluetoothctl", "power", "toggle"]);
                        }
                    }
                }

                ActionItem {
                    icon: "search"
                    label: "Make Discoverable"
                    onClicked: Quickshell.execDetached(["bluetoothctl", "discoverable", "on"])
                }

                ActionDivider {}

                ActionItem {
                    icon: "send"
                    label: "Send Files to Device..."
                    onClicked: Quickshell.execDetached(["blueman-sendto"])
                }

                ActionItem {
                    icon: "history"
                    label: "Reconnect to..."
                }

                // Connected / Paired devices
                Repeater {
                    model: Bluetooth.devices ? Bluetooth.devices.values.slice(0, 3) : []

                    delegate: ActionItem {
                        required property var modelData
                        icon: "headphones"
                        iconColor: modelData.connected ? "#388E3C" : Colors.textOnSurfaceVariant
                        label: (modelData.name || modelData.address || "Audio Device")
                        onClicked: {
                            if (modelData.connected) modelData.disconnect();
                            else modelData.connect();
                        }
                    }
                }

                ActionDivider {}

                ActionItem {
                    icon: "devices"
                    label: "Devices..."
                    onClicked: Quickshell.execDetached(["blueman-manager"])
                }

                ActionItem {
                    icon: "settings"
                    label: "Adaptors..."
                    onClicked: Quickshell.execDetached(["blueman-adapters"])
                }

                ActionItem {
                    icon: "lan"
                    label: "Local Services..."
                }

                ActionDivider {}

                ActionItem {
                    icon: "extension"
                    label: "Plugins"
                }

                ActionItem {
                    icon: "help"
                    label: "Help"
                }

                ActionItem {
                    icon: "close"
                    label: "Exit"
                    onClicked: Config.activePopout = ""
                }
            }

            // ==========================================
            // 3. NETWORK / WIFI ACTIONS LIST
            // ==========================================
            ColumnLayout {
                id: networkSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 2
                readonly property bool isCurrent: root.mode === "network"
                visible: isCurrent
                opacity: isCurrent ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }

                ActionItem {
                    icon: "wifi"
                    label: "Wi-Fi: " + (NetworkService.connected ? (NetworkService.activeSsid || NetworkService.ssid || "Connected") : "Disconnected")
                    onClicked: NetworkService.toggleWifi()
                }

                ActionDivider {}

                Repeater {
                    model: (NetworkService.wifiNetworks || NetworkService.scannedNetworks) ? (NetworkService.wifiNetworks || NetworkService.scannedNetworks).slice(0, 5) : []

                    delegate: ActionItem {
                        required property var modelData
                        icon: "wifi"
                        label: modelData.ssid || "Hidden Network"
                        detail: modelData.signal + "%"
                        onClicked: NetworkService.connectToNetwork(modelData.ssid)
                    }
                }

                ActionDivider {}

                ActionItem {
                    icon: "settings"
                    label: "Network Settings..."
                    onClicked: Quickshell.execDetached(["kcmshell6", "kcm_networkmanagement"])
                }
            }

            // ==========================================
            // 4. AUDIO / VOLUME ACTIONS LIST
            // ==========================================
            ColumnLayout {
                id: audioSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Theme.spaceMedium
                readonly property bool isCurrent: root.mode === "audio"
                visible: isCurrent
                opacity: isCurrent ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSmall

                    MaterialIcon {
                        text: PipewireAudio.getVolumeIcon()
                        size: 20
                        color: Colors.primary
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Volume: " + Math.round(PipewireAudio.volume * 100) + "%"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontMedium
                        font.weight: Font.Bold
                        color: Colors.textOnSurface
                    }

                    Rectangle {
                        implicitWidth: 32
                        implicitHeight: 26
                        radius: Theme.radiusFull
                        color: PipewireAudio.muted ? Colors.primary : Colors.surfaceContainerHigh

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: PipewireAudio.muted ? "volume_off" : "volume_up"
                            size: 14
                            color: PipewireAudio.muted ? Colors.textOnPrimary : Colors.textOnSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PipewireAudio.toggleMute()
                        }
                    }
                }

                // Volume Slider Track
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: Colors.surfaceContainerHigh

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.min(1.0, Math.max(0.0, PipewireAudio.volume))
                        radius: 4
                        color: Colors.primary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => PipewireAudio.setVolume(mouse.x / width)
                        onPositionChanged: mouse => {
                            if (pressed) PipewireAudio.setVolume(mouse.x / width);
                        }
                    }
                }

                ActionDivider {}

                ActionItem {
                    icon: "speaker"
                    label: PipewireAudio.sinkName
                }

                ActionItem {
                    icon: "settings"
                    label: "Audio Settings..."
                    onClicked: Quickshell.execDetached(["kcmshell6", "kcm_pulseaudio"])
                }
            }

            // ==========================================
            // 5. POWER ACTIONS LIST
            // ==========================================
            ColumnLayout {
                id: powerSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 2
                readonly property bool isCurrent: root.mode === "power"
                visible: isCurrent
                opacity: isCurrent ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }

                ActionItem {
                    icon: "lock"
                    label: "Lock Screen"
                    onClicked: PowerService.lock()
                }

                ActionItem {
                    icon: "bedtime"
                    label: "Sleep / Suspend"
                    onClicked: PowerService.suspend()
                }

                ActionDivider {}

                ActionItem {
                    icon: "logout"
                    label: "Log Out..."
                    onClicked: PowerService.requestLogout()
                }

                ActionItem {
                    icon: "exit_to_app"
                    label: "Exit Astral Plasma"
                    onClicked: {
                        if (typeof Config !== "undefined" && Config.exitShell) {
                            Config.exitShell();
                        }
                    }
                }

                ActionItem {
                    icon: "restart_alt"
                    label: "Restart..."
                    onClicked: PowerService.requestReboot()
                }

                ActionItem {
                    icon: "power_settings_new"
                    iconColor: (typeof Colors !== "undefined" && Colors.error) ? Colors.error : "#D32F2F"
                    label: "Shut Down..."
                    onClicked: PowerService.requestPoweroff()
                }
            }

            // ==========================================
            // 6. CLOCK / FULL TIME & DATE SECTION
            // ==========================================
            ColumnLayout {
                id: clockSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Theme.spaceMedium
                readonly property bool isCurrent: root.mode === "clock" || root.mode === "time"
                visible: isCurrent
                opacity: isCurrent ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }

                // Top: Large Digital Time with Live Seconds
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        spacing: 6
                        Layout.alignment: Qt.AlignLeft

                        Text {
                            text: Qt.formatDateTime(root.currentDate, "HH:mm")
                            font.family: Theme.fontFamily
                            font.pixelSize: 32
                            font.weight: Font.Bold
                            color: Colors.textOnSurface
                        }

                        Text {
                            text: ":" + Qt.formatDateTime(root.currentDate, "ss")
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            color: Colors.primary
                            Layout.alignment: Qt.AlignBaseline
                        }
                    }

                    Text {
                        text: Qt.formatDateTime(root.currentDate, "dddd, MMMM d, yyyy")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.Medium
                        color: Colors.textOnSurfaceVariant
                    }
                }

                ActionDivider {}

                // Details: Timezone & System Uptime
                ActionItem {
                    icon: "clock"
                    label: "Timezone"
                    detail: Qt.formatDateTime(root.currentDate, "t")
                }

                ActionItem {
                    icon: "history"
                    label: "System Uptime"
                    detail: SystemService.uptime || "up"
                }

                ActionDivider {}

                // Settings link matching Wi-Fi
                ActionItem {
                    icon: "settings"
                    label: "Date & Time Settings..."
                    onClicked: Quickshell.execDetached(["kcmshell6", "kcm_clock"])
                }
            }

            // ==========================================
            // 7. SYSTEM TRAY MENU POPUP
            // ==========================================
            ColumnLayout {
                id: traySection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 2
                readonly property bool isCurrent: root.mode === "tray"
                visible: isCurrent
                opacity: isCurrent ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }

                property var traySubmenuStack: []
                property int activeLayer: 0 // 0 = layerA, 1 = layerB
                property bool isTransitioning: false

                readonly property var currentTrayItems: (traySubmenuStack && traySubmenuStack.length > 0) ? (traySubmenuStack[traySubmenuStack.length - 1].items || []) : (WindowService.activeTrayMenuItems || [])
                readonly property string currentSubmenuTitle: (traySubmenuStack && traySubmenuStack.length > 0) ? (traySubmenuStack[traySubmenuStack.length - 1].title || "") : ""

                function resetToRoot() {
                    traySubmenuStack = [];
                    activeLayer = 0;
                    isTransitioning = false;
                    layerA.items = WindowService.activeTrayLoading ? [] : (WindowService.activeTrayMenuItems || []);
                    layerA.resetScroll();
                    layerA.x = 0;
                    layerA.opacity = 1.0;
                    layerA.visible = true;

                    layerB.items = [];
                    layerB.resetScroll();
                    layerB.x = 35;
                    layerB.opacity = 0.0;
                    layerB.visible = false;
                }

                function pushSubmenu(title, newItems) {
                    if (isTransitioning) return;

                    let stack = traySubmenuStack.slice(0);
                    stack.push({ title: title, items: newItems });
                    traySubmenuStack = stack;

                    const targetLayer = (activeLayer === 0) ? 1 : 0;
                    const outgoing = (activeLayer === 0) ? layerA : layerB;
                    const incoming = (activeLayer === 0) ? layerB : layerA;

                    incoming.items = newItems;
                    incoming.resetScroll();
                    incoming.x = 35;
                    incoming.opacity = 0.0;
                    incoming.visible = true;

                    isTransitioning = true;
                    pushOutX.target = outgoing;
                    pushOutOp.target = outgoing;
                    pushInX.target = incoming;
                    pushInOp.target = incoming;
                    slideAnimPush.outgoingRef = outgoing;
                    slideAnimPush.targetLayerIndex = targetLayer;
                    slideAnimPush.restart();
                }

                function popSubmenu() {
                    if (isTransitioning || traySubmenuStack.length === 0) return;

                    let stack = traySubmenuStack.slice(0);
                    stack.pop();
                    traySubmenuStack = stack;

                    const parentItems = (stack.length > 0) ? stack[stack.length - 1].items : (WindowService.activeTrayMenuItems || []);
                    const targetLayer = (activeLayer === 0) ? 1 : 0;
                    const outgoing = (activeLayer === 0) ? layerA : layerB;
                    const incoming = (activeLayer === 0) ? layerB : layerA;

                    incoming.items = parentItems;
                    incoming.resetScroll();
                    incoming.x = -35;
                    incoming.opacity = 0.0;
                    incoming.visible = true;

                    isTransitioning = true;
                    popOutX.target = outgoing;
                    popOutOp.target = outgoing;
                    popInX.target = incoming;
                    popInOp.target = incoming;
                    slideAnimPop.outgoingRef = outgoing;
                    slideAnimPop.targetLayerIndex = targetLayer;
                    slideAnimPop.restart();
                }

                function handleItemClick(modelData) {
                    if (isTransitioning) return;
                    const hasSubmenu = Boolean(modelData.hasSubmenu) || (Boolean(modelData.children) && modelData.children.length > 0);
                    if (hasSubmenu && modelData.children && modelData.children.length > 0) {
                        traySection.pushSubmenu(modelData.label || "Submenu", modelData.children);
                    } else if (modelData.enabled !== false) {
                        if (WindowService.activeTrayItem && WindowService.activeTrayItem.menuPath) {
                            WindowService.triggerTrayMenuItem(WindowService.activeTrayItem.service, WindowService.activeTrayItem.menuPath, modelData.id);
                        }
                        Config.closeBottomPopout();
                    }
                }

                Connections {
                    target: Config
                    function onBottomPopoutVisibleChanged() {
                        if (!Config.bottomPopoutVisible) {
                            traySection.resetToRoot();
                        }
                    }
                    function onRequestOpenTraySubmenu(indexOrTitle) {
                        root.openTraySubmenu(indexOrTitle);
                    }
                    function onRequestPopTraySubmenu() {
                        root.popTraySubmenu();
                    }
                }
                Connections {
                    target: WindowService
                    function onActiveTrayItemChanged() {
                        traySection.resetToRoot();
                    }
                    function onActiveTrayMenuItemsChanged() {
                        if (traySection.traySubmenuStack.length === 0 && !traySection.isTransitioning) {
                            if (traySection.activeLayer === 0) {
                                if (typeof layerA !== "undefined" && layerA) {
                                    layerA.items = WindowService.activeTrayMenuItems || [];
                                }
                            } else {
                                if (typeof layerB !== "undefined" && layerB) {
                                    layerB.items = WindowService.activeTrayMenuItems || [];
                                }
                            }
                        }
                    }
                }

                ParallelAnimation {
                    id: slideAnimPush
                    property var outgoingRef: null
                    property int targetLayerIndex: 0

                    NumberAnimation {
                        id: pushOutX
                        property: "x"
                        to: -35
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }
                    NumberAnimation {
                        id: pushOutOp
                        property: "opacity"
                        to: 0.0
                        duration: 180
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                    NumberAnimation {
                        id: pushInX
                        property: "x"
                        to: 0
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }
                    NumberAnimation {
                        id: pushInOp
                        property: "opacity"
                        to: 1.0
                        duration: 200
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }

                    onFinished: {
                        traySection.activeLayer = targetLayerIndex;
                        if (outgoingRef) {
                            outgoingRef.visible = false;
                        }
                        traySection.isTransitioning = false;
                    }
                }

                ParallelAnimation {
                    id: slideAnimPop
                    property var outgoingRef: null
                    property int targetLayerIndex: 0

                    NumberAnimation {
                        id: popOutX
                        property: "x"
                        to: 35
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }
                    NumberAnimation {
                        id: popOutOp
                        property: "opacity"
                        to: 0.0
                        duration: 180
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                    NumberAnimation {
                        id: popInX
                        property: "x"
                        to: 0
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }
                    NumberAnimation {
                        id: popInOp
                        property: "opacity"
                        to: 1.0
                        duration: 200
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }

                    onFinished: {
                        traySection.activeLayer = targetLayerIndex;
                        if (outgoingRef) {
                            outgoingRef.visible = false;
                        }
                        traySection.isTransitioning = false;
                    }
                }

                // Animated Header Container (cross-fades top-level app header & submenu navigation header)
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    clip: true

                    // 1. Top-Level App Header
                    Rectangle {
                        id: appHeaderRow
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        radius: Theme.radiusSmall
                        color: headerMouse.containsMouse ? Colors.surfaceContainerHigh : "transparent"
                        opacity: traySection.traySubmenuStack.length === 0 ? 1.0 : 0.0
                        x: traySection.traySubmenuStack.length === 0 ? 0 : -25
                        visible: opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                            }
                        }
                        Behavior on x {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: Theme.spaceSmall

                            Item {
                                id: trayHeaderIcon
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignVCenter

                                Image {
                                    anchors.fill: parent
                                    source: Config.iconUrl(WindowService.activeTrayItem ? WindowService.activeTrayItem.rawIcon : "")
                                    fillMode: Image.PreserveAspectFit
                                    visible: status === Image.Ready
                                }

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: (WindowService.activeTrayItem && WindowService.activeTrayItem.materialIcon) ? WindowService.activeTrayItem.materialIcon : "widgets"
                                    size: 22
                                    color: Colors.primary
                                    visible: !parent.children[0].visible
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: (WindowService.activeTrayItem && WindowService.activeTrayItem.title && !WindowService.activeTrayItem.title.startsWith("Error")) 
                                        ? WindowService.activeTrayItem.title 
                                        : ((WindowService.activeTrayItem && WindowService.activeTrayItem.id) ? WindowService.activeTrayItem.id : "Application")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontMedium
                                    font.weight: Font.DemiBold
                                    color: Colors.textOnSurface
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (WindowService.activeTrayItem && WindowService.activeTrayItem.menuPath === "/SyntheticMenu") ? "Wine Application" : ((WindowService.activeTrayItem && WindowService.activeTrayItem.service) ? WindowService.activeTrayItem.service : "System Tray")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontLabelSmall
                                    color: Colors.textOnSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: headerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (WindowService.activeTrayItem) {
                                    Config.closeBottomPopout();
                                    WindowService.activateTray(WindowService.activeTrayItem.service, WindowService.activeTrayItem.path);
                                }
                            }
                        }
                    }

                    // 2. Submenu Navigation Header
                    RowLayout {
                        id: submenuHeaderRow
                        anchors.fill: parent
                        spacing: Theme.spaceSmall
                        opacity: traySection.traySubmenuStack.length > 0 ? 1.0 : 0.0
                        x: traySection.traySubmenuStack.length > 0 ? 0 : 25
                        visible: opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                            }
                        }
                        Behavior on x {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                            }
                        }

                        Rectangle {
                            id: backBtn
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: backBtnRow.implicitWidth + 12
                            radius: Theme.radiusSmall
                            color: backMouse.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                            Layout.alignment: Qt.AlignVCenter

                            Row {
                                id: backBtnRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "arrow_back"
                                    size: 16
                                    color: Colors.primary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Back"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSmall
                                    font.weight: Font.Medium
                                    color: Colors.textOnSurface
                                }
                            }

                            MouseArea {
                                id: backMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: traySection.popSubmenu()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: traySection.currentSubmenuTitle
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontMedium
                            font.weight: Font.DemiBold
                            color: Colors.textOnSurface
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: countText.implicitWidth + 10
                            implicitHeight: 20
                            radius: 10
                            color: Colors.surfaceContainerHigh
                            visible: traySection.currentTrayItems.length > 0

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: traySection.currentTrayItems.length.toString()
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontLabelSmall
                                font.weight: Font.Medium
                                color: Colors.textOnSurfaceVariant
                            }
                        }
                    }
                }

                ActionDivider {}

                // Loading State
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    visible: WindowService.activeTrayLoading && traySection.traySubmenuStack.length === 0

                    Text {
                        anchors.centerIn: parent
                        text: "Loading menu..."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSmall
                        color: Colors.textOnSurfaceVariant
                    }
                }

                // Empty State
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    visible: (!WindowService.activeTrayLoading || traySection.traySubmenuStack.length > 0) && traySection.currentTrayItems.length === 0

                    Text {
                        anchors.centerIn: parent
                        text: "No actions available"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSmall
                        color: Colors.textOnSurfaceVariant
                    }
                }

                // Animated Viewport with Two-Layer Sliding Transition
                Item {
                    id: trayFlickableContainer
                    Layout.fillWidth: true
                    implicitHeight: Math.min(480, animatedHeight)
                    visible: traySection.currentTrayItems.length > 0
                    clip: true

                    readonly property real activeContentHeight: {
                        if (traySection.isTransitioning) {
                            const incoming = (traySection.activeLayer === 0) ? layerB : layerA;
                            return incoming ? incoming.contentHeight : 0;
                        }
                        const current = (traySection.activeLayer === 0) ? layerA : layerB;
                        return current ? current.contentHeight : 0;
                    }
                    property real animatedHeight: activeContentHeight > 0 ? activeContentHeight : 30
                    Behavior on animatedHeight {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                        }
                    }

                    TrayMenuPage {
                        id: layerA
                        anchors.fill: parent
                        items: WindowService.activeTrayMenuItems || []
                        x: 0
                        opacity: 1.0
                        visible: opacity > 0.001
                        onItemClicked: (modelData) => traySection.handleItemClick(modelData)
                    }

                    TrayMenuPage {
                        id: layerB
                        anchors.fill: parent
                        items: []
                        x: 35
                        opacity: 0.0
                        visible: opacity > 0.001
                        onItemClicked: (modelData) => traySection.handleItemClick(modelData)
                    }
                }
            }

            // ==========================================
            // 8. APPLICATION PREVIEW DRAWER
            // ==========================================
            ColumnLayout {
                id: appSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 8
                readonly property bool isCurrent: root.mode === "app"
                visible: isCurrent
                opacity: isCurrent ? 1.0 : 0.0

                readonly property var currentApp: WindowService.activePreviewApp
                readonly property bool isRunning: currentApp ? (Boolean(currentApp.isRunning) || Boolean(currentApp.id)) : false

                // Live preview auto-refresh while hovering over app or drawer
                Timer {
                    id: liveRefreshTimer
                    interval: 1000
                    repeat: true
                    running: appSection.isCurrent && appSection.isRunning && Config.bottomPopoutVisible
                    onTriggered: {
                        if (appSection.currentApp && appSection.currentApp.id) {
                            WindowService.refreshAppPreview(appSection.currentApp);
                        }
                    }
                }

                // 1. App Header: Icon, App Name & Status Pill
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSmall
                    Layout.bottomMargin: 2

                    Item {
                        id: appHeaderIcon
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter

                        Image {
                            anchors.fill: parent
                            source: Config.iconUrl(appSection.currentApp ? appSection.currentApp.iconName : "")
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: (appSection.currentApp && appSection.currentApp.materialIcon) ? appSection.currentApp.materialIcon : "desktop_windows"
                            size: 22
                            color: Colors.primary
                            visible: !parent.children[0].visible
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: (appSection.currentApp && appSection.currentApp.appName) ? appSection.currentApp.appName : "Application"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontMedium
                            font.weight: Font.DemiBold
                            color: Colors.textOnSurface
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                const app = appSection.currentApp;
                                if (!app) return "";
                                if (app.isActive) return "Active Window";
                                if (appSection.isRunning) return "Running";
                                if (app.isPinned) return "Pinned to Dock";
                                return "Ready to launch";
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontLabelSmall
                            color: (appSection.currentApp && appSection.currentApp.isActive) ? Colors.primary : Colors.textOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }

                ActionDivider {}

                // 2. Window / App Preview Card
                Rectangle {
                    id: appPreviewCard
                    Layout.fillWidth: true
                    implicitHeight: (appSection.currentApp && appSection.isRunning) ? 200 : 96
                    radius: Theme.radiusSmall
                    color: Colors.surfaceContainerLowest
                    border.color: (appSection.currentApp && appSection.currentApp.isActive) ? Colors.primary : Theme.borderSubtle
                    border.width: (appSection.currentApp && appSection.currentApp.isActive) ? 1.5 : 1
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: Config.keepBottomPopout()
                        onClicked: {
                            const app = appSection.currentApp;
                            if (!app) return;
                            if (appSection.isRunning && app.id) {
                                WindowService.activateWindow(app.id);
                            } else {
                                WindowService.launchApp(app.desktopFile || app.appId);
                            }
                            Config.closeBottomPopout();
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        // Mini Titlebar with macOS-style dots
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: "#ff5f56"
                            }
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: "#ffbd2e"
                            }
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: "#27c93f"
                            }

                            Item { Layout.preferredWidth: 4 }

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    const app = appSection.currentApp;
                                    if (app && app.title && app.title.trim() !== "") {
                                        return app.title;
                                    }
                                    return (app && app.appName) ? app.appName : "Window";
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontLabelSmall
                                font.weight: Font.Medium
                                color: Colors.textOnSurface
                                elide: Text.ElideRight
                            }

                            // Live badge indicator
                            RowLayout {
                                spacing: 4
                                visible: appSection.currentApp && appSection.isRunning

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: (appSection.currentApp && appSection.currentApp.isActive) ? "#27c93f" : Colors.primary
                                }

                                Text {
                                    text: (appSection.currentApp && appSection.currentApp.isActive) ? "ACTIVE" : "LIVE"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    color: (appSection.currentApp && appSection.currentApp.isActive) ? "#27c93f" : Colors.primary
                                }
                            }
                        }

                        // Live Window Content Preview
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 4
                            color: Colors.surfaceContainer
                            clip: true

                            // Double-buffered live thumbnail container to prevent flicker during updates
                            Item {
                                id: livePreviewBufContainer
                                anchors.fill: parent

                                readonly property string targetSource: (appSection.currentApp && appSection.isRunning) ? WindowService.activePreviewThumbnail : ""
                                property string activeBuffer: "A"
                                property var lastAppId: null
                                property bool hasLoadedPreview: false
                                readonly property bool hasImage: hasLoadedPreview || (bufA.status === Image.Ready && bufA.source !== "") || (bufB.status === Image.Ready && bufB.source !== "")

                                function onTargetChanged() {
                                    const curId = (appSection.currentApp && appSection.currentApp.id) ? appSection.currentApp.id : null;
                                    if (curId !== lastAppId) {
                                        lastAppId = curId;
                                        hasLoadedPreview = false;
                                        bufA.source = "";
                                        bufB.source = "";
                                        activeBuffer = "A";
                                    }

                                    if (targetSource === "") {
                                        hasLoadedPreview = false;
                                        bufA.source = "";
                                        bufB.source = "";
                                        return;
                                    }

                                    if (activeBuffer === "A") {
                                        bufB.source = targetSource;
                                    } else {
                                        bufA.source = targetSource;
                                    }
                                }

                                onTargetSourceChanged: onTargetChanged()

                                Image {
                                    id: bufA
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    z: livePreviewBufContainer.activeBuffer === "A" ? 2 : 1
                                    visible: livePreviewBufContainer.hasLoadedPreview ? (livePreviewBufContainer.activeBuffer === "A" || livePreviewBufContainer.activeBuffer === "B") : (status === Image.Ready)

                                    onStatusChanged: {
                                        if (status === Image.Ready) {
                                            livePreviewBufContainer.hasLoadedPreview = true;
                                            if (livePreviewBufContainer.activeBuffer === "B") {
                                                livePreviewBufContainer.activeBuffer = "A";
                                            }
                                        }
                                    }
                                }

                                Image {
                                    id: bufB
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    z: livePreviewBufContainer.activeBuffer === "B" ? 2 : 1
                                    visible: livePreviewBufContainer.hasLoadedPreview ? (livePreviewBufContainer.activeBuffer === "B" || livePreviewBufContainer.activeBuffer === "A") : (status === Image.Ready)

                                    onStatusChanged: {
                                        if (status === Image.Ready) {
                                            livePreviewBufContainer.hasLoadedPreview = true;
                                            if (livePreviewBufContainer.activeBuffer === "A") {
                                                livePreviewBufContainer.activeBuffer = "B";
                                            }
                                        }
                                    }
                                }
                            }

                            // Fallback placeholder / immediate skeleton preview card
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                visible: !livePreviewBufContainer.hasImage

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 44

                                    Image {
                                        anchors.fill: parent
                                        source: Config.iconUrl(appSection.currentApp ? appSection.currentApp.iconName : "")
                                        fillMode: Image.PreserveAspectFit
                                        opacity: 0.85
                                        visible: status === Image.Ready
                                    }

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: (appSection.currentApp && appSection.currentApp.materialIcon) ? appSection.currentApp.materialIcon : "desktop_windows"
                                        size: 36
                                        color: Colors.primary
                                        opacity: 0.85
                                        visible: !parent.children[0].visible
                                    }
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 6

                                    MaterialIcon {
                                        text: (appSection.currentApp && appSection.isRunning)
                                            ? (WindowService.activePreviewLoading ? "sync" : "picture_in_picture")
                                            : "play_circle"
                                        size: 15
                                        color: (appSection.currentApp && appSection.currentApp.isActive) ? Colors.primary : Colors.textOnSurfaceVariant
                                    }

                                    Text {
                                        text: {
                                            const app = appSection.currentApp;
                                            if (!app) return "";
                                            if (appSection.isRunning) {
                                                return WindowService.activePreviewLoading ? "Capturing live preview..." : (app.isActive ? "Currently in focus" : "Running in background");
                                            }
                                            return "Click to start";
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSmall
                                        color: Colors.textOnSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }

                ActionDivider {}

                // 3. Quick Actions
                ActionItem {
                    visible: appSection.currentApp && appSection.isRunning
                    label: "Bring to Front"
                    icon: "open_in_new"
                    onClicked: {
                        if (appSection.currentApp && appSection.currentApp.id) {
                            WindowService.activateWindow(appSection.currentApp.id);
                        }
                        Config.closeBottomPopout();
                    }
                }

                ActionItem {
                    visible: appSection.currentApp && !appSection.isRunning
                    label: "Launch Application"
                    icon: "play_arrow"
                    onClicked: {
                        if (appSection.currentApp) {
                            WindowService.launchApp(appSection.currentApp.desktopFile || appSection.currentApp.appId);
                        }
                        Config.closeBottomPopout();
                    }
                }

                ActionItem {
                    visible: appSection.currentApp !== null
                    label: (appSection.currentApp && appSection.currentApp.isPinned) ? "Unpin from Dock" : "Pin to Dock"
                    icon: (appSection.currentApp && appSection.currentApp.isPinned) ? "keep_off" : "push_pin"
                    onClicked: {
                        if (!appSection.currentApp) return;
                        if (appSection.currentApp.isPinned) {
                            Config.unpinApp(appSection.currentApp.appId, appSection.currentApp.desktopFile, appSection.currentApp.appName);
                        } else {
                            Config.pinApp(appSection.currentApp);
                        }
                        Config.closeBottomPopout();
                    }
                }

                ActionItem {
                    visible: appSection.currentApp && appSection.isRunning
                    label: "Close Window"
                    icon: "close"
                    iconColor: "#ffb4ab"
                    onClicked: {
                        if (appSection.currentApp && appSection.currentApp.id) {
                            WindowService.closeWindow(appSection.currentApp.id);
                        }
                        Config.closeBottomPopout();
                    }
                }
            }
        }
    }

    // ==========================================
    // ACTION ITEM HELPER COMPONENT
    // ==========================================
    component ActionItem: Rectangle {
        id: actionRoot
        property string icon: ""
        property string iconSource: ""
        property color iconColor: Colors.textOnSurface
        property string label: ""
        property string detail: ""
        property bool enabled: true
        property bool hasSubmenu: false
        property string toggleType: "" // "checkmark", "radio", ""
        property int toggleState: 0 // 0, 1
        signal clicked()

        Layout.fillWidth: true
        implicitHeight: 30
        radius: Theme.radiusSmall
        color: (actionRoot.enabled && actionMouse.containsMouse) ? Colors.surfaceContainerHigh : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padSmall
            anchors.rightMargin: Theme.padSmall
            spacing: Theme.spaceSmall

            // Toggle icon (checkmark or radio) if configured
            MaterialIcon {
                Layout.preferredWidth: (actionRoot.toggleType !== "") ? 16 : 0
                Layout.preferredHeight: 16
                Layout.alignment: Qt.AlignVCenter
                visible: actionRoot.toggleType !== ""
                text: {
                    if (actionRoot.toggleType === "checkmark") {
                        return actionRoot.toggleState === 1 ? "check" : "";
                    } else if (actionRoot.toggleType === "radio") {
                        return actionRoot.toggleState === 1 ? "radio_button_checked" : "radio_button_unchecked";
                    }
                    return "";
                }
                color: (actionRoot.toggleState === 1) ? Colors.primary : Colors.textOnSurfaceVariant
                size: 14
            }

            ThemedIcon {
                Layout.preferredWidth: (actionRoot.iconSource !== "" || actionRoot.icon !== "") ? 18 : 0
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                visible: actionRoot.iconSource !== "" || actionRoot.icon !== ""
                source: actionRoot.iconSource
                materialIcon: actionRoot.icon
                color: actionRoot.iconColor
                size: 16
            }

            Text {
                Layout.fillWidth: true
                text: actionRoot.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSmall
                color: actionRoot.enabled ? Colors.textOnSurface : Colors.textOnSurfaceVariant
                elide: Text.ElideRight
            }

            Text {
                visible: actionRoot.detail !== ""
                text: actionRoot.detail
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.textOnSurfaceVariant
            }

            // Submenu Chevron Indicator
            MaterialIcon {
                Layout.preferredWidth: actionRoot.hasSubmenu ? 16 : 0
                Layout.preferredHeight: 16
                Layout.alignment: Qt.AlignVCenter
                visible: actionRoot.hasSubmenu
                text: "chevron_right"
                size: 16
                color: (actionRoot.enabled && actionMouse.containsMouse) ? Colors.primary : Colors.textOnSurfaceVariant
            }
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: actionRoot.enabled
            cursorShape: actionRoot.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: {
                Config.keepBottomPopout();
            }
            onClicked: {
                if (actionRoot.enabled) actionRoot.clicked();
            }
        }
    }

    // ==========================================
    // ACTION DIVIDER COMPONENT
    // ==========================================
    component ActionDivider: Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.borderSubtle
        Layout.topMargin: 2
        Layout.bottomMargin: 2
    }

    // ==========================================
    // TRAY MENU PAGE COMPONENT (SMOOTH TRANSITIONS)
    // ==========================================
    component TrayMenuPage: Item {
        id: pageRoot
        property var items: []
        readonly property real contentHeight: pageCol.implicitHeight
        signal itemClicked(var modelData)

        Flickable {
            id: pageFlickable
            anchors.fill: parent
            contentWidth: width
            contentHeight: pageCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            interactive: contentHeight > height

            ColumnLayout {
                id: pageCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: pageRoot.items

                    Item {
                        required property var modelData
                        Layout.fillWidth: true
                        visible: modelData.isSeparator || (modelData.label !== undefined && modelData.label.trim() !== "")
                        implicitHeight: visible ? (modelData.isSeparator ? 9 : 30) : 0

                        ActionDivider {
                            anchors.centerIn: parent
                            width: parent.width
                            visible: modelData.isSeparator
                        }

                        ActionItem {
                            anchors.fill: parent
                            visible: !modelData.isSeparator
                            label: modelData.label || ""
                            enabled: modelData.enabled !== false
                            hasSubmenu: Boolean(modelData.hasSubmenu) || (Boolean(modelData.children) && modelData.children.length > 0)
                            toggleType: modelData.toggleType || ""
                            toggleState: (modelData.toggleState !== undefined) ? modelData.toggleState : 0
                            icon: (modelData.icon && !modelData.icon.includes("/") && !modelData.icon.includes("-")) ? modelData.icon : ""
                            iconSource: Config.iconUrl(modelData.icon)
                            iconColor: (modelData.label && (modelData.label.toLowerCase().includes("quit") || modelData.label.toLowerCase().includes("exit"))) ? "#ffb4ab" : Colors.textOnSurface
                            onClicked: pageRoot.itemClicked(modelData)
                        }
                    }
                }
            }

            WheelHandler {
                target: pageFlickable
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    pageFlickable.contentY = Math.max(0, Math.min(pageFlickable.contentHeight - pageFlickable.height, pageFlickable.contentY - event.angleDelta.y));
                }
            }
        }

        Rectangle {
            id: pageScrollBar
            anchors.right: parent.right
            anchors.rightMargin: 1
            width: 3
            radius: 1.5
            color: Colors.primary
            opacity: (pageFlickable.moving || pageFlickable.dragging) ? 0.8 : 0.0
            visible: pageFlickable.contentHeight > pageFlickable.height
            y: pageFlickable.contentHeight > 0 ? ((pageFlickable.contentY / pageFlickable.contentHeight) * pageFlickable.height) : 0
            height: pageFlickable.contentHeight > 0 ? Math.max(20, (pageFlickable.height / pageFlickable.contentHeight) * pageFlickable.height) : 0

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }

        function resetScroll() {
            pageFlickable.contentY = 0;
        }
    }
}
