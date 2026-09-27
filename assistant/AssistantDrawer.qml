import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"
import "../config"
import "../services"
import "components"

Item {
    id: root

    property bool testMode: false
    property bool isFloating: false
    property bool userMoved: false
    readonly property alias cardItem: card
    readonly property alias chatInputItem: chatInput
    readonly property alias headerItem: headerItem
    readonly property alias sessionDrawerItem: sessionDrawer
    readonly property alias chatContentColumnItem: chatContentColumn
    readonly property alias chatViewItem: chatView

    signal userDragged()
    signal resetRequested()

    function resetPosition() {
        userMoved = false;
        customWidth = 0;
        customHeight = 0;
        x = Qt.binding(() => Math.round((targetScreenWidth - width) / 2));
        y = Qt.binding(() => Math.round((targetScreenHeight - height) / 2));
    }

    // Sizing & Placement
    readonly property int drawerWidth: 460
    readonly property int targetScreenWidth: (parent && parent.width > 0) ? parent.width : ((typeof Window !== "undefined" && Window.window) ? Window.window.width : 1920)
    readonly property int targetScreenHeight: (parent && parent.height > 0) ? parent.height : ((typeof Window !== "undefined" && Window.window) ? Window.window.height : 1080)

    property int customWidth: 0
    property int customHeight: 0
    readonly property int minWidth: 480
    readonly property int minHeight: 520
    readonly property int baseDefaultWidth: Math.min(740, Math.max(480, Math.round(targetScreenWidth * 0.48)))
    readonly property int sidebarExtraWidth: sessionsVisible ? 280 : 0
    readonly property int defaultWidth: baseDefaultWidth + sidebarExtraWidth
    readonly property int defaultHeight: Math.min(840, Math.max(540, Math.round(targetScreenHeight * 0.76)))
    readonly property int maxWidth: Math.max(minWidth, targetScreenWidth - 32)
    readonly property int maxHeight: Math.max(minHeight, targetScreenHeight - 32)

    width: customWidth > 0 ? Math.max(minWidth, Math.min(maxWidth, customWidth + sidebarExtraWidth)) : (isFloating ? defaultWidth : drawerWidth)
    height: customHeight > 0 ? Math.max(minHeight, Math.min(maxHeight, customHeight)) : (isFloating ? defaultHeight : (parent ? parent.height : 800))

    Behavior on width {
        enabled: !root.testMode && (typeof Theme !== "undefined") && root.customWidth === 0
        NumberAnimation {
            duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastSpatial) ? Theme.animExpressiveFastSpatial : 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    anchors.top: !isFloating ? (parent ? parent.top : undefined) : undefined
    anchors.bottom: !isFloating ? (parent ? parent.bottom : undefined) : undefined

    property bool isOpen: (typeof Config !== "undefined") ? Config.assistantVisible : false
    property bool addProviderVisible: false
    property bool imagePickerVisible: false
    property bool sessionsVisible: false

    onIsOpenChanged: {
        if (isOpen) {
            if (typeof AssistantService !== "undefined" && typeof AssistantService.refreshStatus === "function") {
                AssistantService.refreshStatus();
            }
            Qt.callLater(function() {
                if (typeof chatInput !== "undefined" && chatInput.focusInput) {
                    chatInput.focusInput();
                }
            });
        }
    }

    // Motion & Positioning:
    // Floating mode centers in parent; drawer mode slides from right edge
    x: isFloating ? Math.round((targetScreenWidth - width) / 2) : (isOpen ? (targetScreenWidth - drawerWidth) : targetScreenWidth)
    y: isFloating ? Math.round((targetScreenHeight - height) / 2) : 0

    scale: isFloating ? (isOpen ? 1.0 : 0.95) : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: Theme.animExpressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
        }
    }

    Behavior on x {
        enabled: !root.isFloating
        NumberAnimation {
            duration: (typeof Theme !== "undefined") ? (root.isOpen ? Theme.animExpressiveDefaultSpatial : Theme.animExpressiveFastSpatial) : 350
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.isOpen
                ? ((typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0])
                : ((typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.42, 1.67, 0.21, 0.9, 1.0, 1.0])
        }
    }

    opacity: isOpen ? 1.0 : 0.0
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.animExpressiveFastEffects
            easing.type: Easing.OutQuad
        }
    }

    // Main Liquid Glass Container Card
    LiquidGlassCard {
        id: card
        anchors.fill: parent
        anchors.margins: root.isFloating ? 0 : Theme.padSmall
        radius: (typeof Theme !== "undefined") ? Theme.radiusGlassModal : 24
        elevation: root.isFloating ? 24 : 16
        showShadow: true

        // Rich, high-readability frosted liquid glass substrate:
        // 96% alpha in dark mode, 97% in light mode completely eliminates background text bleed-through
        // from windows underneath while preserving authentic liquid glass depth, specular borders, and compositor blur.
        color: {
            if (typeof Colors === "undefined") return "#1e1e2e";
            let base = Colors.isDarkMode ? Qt.rgba(0.08, 0.09, 0.13, 0.96) : Qt.rgba(0.96, 0.97, 1.0, 0.97);
            return Qt.tint(base, Qt.alpha(Colors.primary, Colors.isDarkMode ? 0.05 : 0.03));
        }

        focus: root.isOpen
        Keys.onEscapePressed: Config.closeAssistant()

        // Underlying Dialog Drag Area (consumes clicks and supports dragging empty surfaces)
        MouseArea {
            id: dialogDragArea
            enabled: root.isFloating
            anchors.fill: parent
            z: 0

            drag.target: root.isFloating ? root : null
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 16
            drag.maximumX: Math.max(16, (root.parent ? root.parent.width : 1920) - root.width - 16)
            drag.minimumY: 16
            drag.maximumY: Math.max(16, (root.parent ? root.parent.height : 1080) - root.height - 16)

            onPositionChanged: {
                if (drag.active) {
                    root.userMoved = true;
                    root.userDragged();
                }
            }

            onDoubleClicked: {
                root.resetPosition();
                root.resetRequested();
            }
            onClicked: {}
        }

        // Edge & Corner Resize Handles (Floating Mode)
        MouseArea {
            id: rightResizeHandle
            enabled: root.isFloating
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 10
            z: 30
            cursorShape: Qt.SizeHorCursor

            property real startX: 0
            property real startW: 0

            onPressed: mouse => {
                startX = mouse.x;
                startW = root.width;
            }
            onPositionChanged: mouse => {
                if (pressed) {
                    const deltaX = mouse.x - startX;
                    root.customWidth = Math.max(root.minWidth, Math.min(root.maxWidth, startW + deltaX));
                    root.userMoved = true;
                    root.userDragged();
                }
            }
        }

        MouseArea {
            id: bottomResizeHandle
            enabled: root.isFloating
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 10
            z: 30
            cursorShape: Qt.SizeVerCursor

            property real startY: 0
            property real startH: 0

            onPressed: mouse => {
                startY = mouse.y;
                startH = root.height;
            }
            onPositionChanged: mouse => {
                if (pressed) {
                    const deltaY = mouse.y - startY;
                    root.customHeight = Math.max(root.minHeight, Math.min(root.maxHeight, startH + deltaY));
                    root.userMoved = true;
                    root.userDragged();
                }
            }
        }

        MouseArea {
            id: leftResizeHandle
            enabled: root.isFloating
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 10
            z: 30
            cursorShape: Qt.SizeHorCursor

            property real startGlobalX: 0
            property real startX: 0
            property real startW: 0

            onPressed: mouse => {
                const pt = mapToItem(null, mouse.x, mouse.y);
                startGlobalX = pt.x;
                startX = root.x;
                startW = root.width;
            }
            onPositionChanged: mouse => {
                if (pressed) {
                    const pt = mapToItem(null, mouse.x, mouse.y);
                    const deltaX = pt.x - startGlobalX;
                    let targetW = startW - deltaX;
                    if (targetW < root.minWidth) targetW = root.minWidth;
                    if (targetW > root.maxWidth) targetW = root.maxWidth;
                    const actualDeltaX = startW - targetW;
                    root.customWidth = targetW;
                    root.x = Math.max(16, startX + actualDeltaX);
                    root.userMoved = true;
                    root.userDragged();
                }
            }
        }

        MouseArea {
            id: cornerResizeHandle
            enabled: root.isFloating
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 24
            height: 24
            z: 40
            cursorShape: Qt.SizeFDiagCursor

            property real startX: 0
            property real startY: 0
            property real startW: 0
            property real startH: 0

            onPressed: mouse => {
                startX = mouse.x;
                startY = mouse.y;
                startW = root.width;
                startH = root.height;
            }
            onPositionChanged: mouse => {
                if (pressed) {
                    const deltaX = mouse.x - startX;
                    const deltaY = mouse.y - startY;
                    root.customWidth = Math.max(root.minWidth, Math.min(root.maxWidth, startW + deltaX));
                    root.customHeight = Math.max(root.minHeight, Math.min(root.maxHeight, startH + deltaY));
                    root.userMoved = true;
                    root.userDragged();
                }
            }
            onDoubleClicked: {
                root.customWidth = 0;
                root.customHeight = 0;
                root.userMoved = true;
                root.userDragged();
            }

            Canvas {
                anchors.fill: parent
                anchors.margins: 4
                opacity: cornerResizeHandle.containsMouse ? 0.9 : 0.4
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.strokeStyle = (typeof Colors !== "undefined" && Colors.onSurfaceVariant) ? Colors.onSurfaceVariant : "#aaaaaa";
                    ctx.lineWidth = 1.5;
                    ctx.lineCap = "round";

                    ctx.beginPath();
                    ctx.moveTo(width - 3, height - 9);
                    ctx.lineTo(width - 9, height - 3);

                    ctx.moveTo(width - 3, height - 14);
                    ctx.lineTo(width - 14, height - 3);

                    ctx.stroke();
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            z: 5

            // 1. Header
            AssistantHeader {
                id: headerItem
                testMode: root.testMode
                dragTarget: root.isFloating ? root : null
                onUserDragged: {
                    root.userMoved = true;
                    root.userDragged();
                }
                onCloseRequested: Config.closeAssistant()
                onMinimizeRequested: Config.minimizeAssistant()
                onAddProviderRequested: root.addProviderVisible = true
                onSessionsRequested: root.sessionsVisible = !root.sessionsVisible
                onNewChatRequested: {
                    if (typeof AssistantService !== "undefined") {
                        AssistantService.createNewSession();
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Colors.glassBorderSpecular
            }

            // 2. Main Content Split View: [ Sessions Sidebar ] + [ Vertical Divider ] + [ Chat Content Area ]
            RowLayout {
                id: splitContentRow
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Sessions Sidebar Panel (Non-overlapping, dockable side panel)
                SessionListDrawer {
                    id: sessionDrawer
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.sessionsVisible ? 280 : 0
                    width: Layout.preferredWidth
                    visible: root.sessionsVisible || width > 0
                    clip: true

                    Behavior on Layout.preferredWidth {
                        enabled: !root.testMode
                        NumberAnimation {
                            duration: Theme.animExpressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                        }
                    }

                    onClosed: root.sessionsVisible = false
                    onSessionSelected: function(id) {
                        if (typeof AssistantService !== "undefined") {
                            AssistantService.loadSession(id);
                        }
                    }
                    onNewSessionRequested: {
                        if (typeof AssistantService !== "undefined") {
                            AssistantService.createNewSession();
                        }
                    }
                }

                // Vertical Divider between sidebar and chat
                Rectangle {
                    id: sidebarDivider
                    Layout.fillHeight: true
                    width: 1
                    color: Colors.glassBorderSpecular
                    visible: root.sessionsVisible && sessionDrawer.width > 20
                }

                // Main Chat Content Column
                ColumnLayout {
                    id: chatContentColumn
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // 2. Dedicated Model & Provider Selector Bar
                    ModelProviderBar {
                        Layout.topMargin: 8
                        Layout.bottomMargin: 4
                        onAddProviderRequested: root.addProviderVisible = true
                    }

                    // 3. Proactive Crash Banner (if a critical crash is detected)
                    Rectangle {
                        id: crashBanner
                        Layout.fillWidth: true
                        readonly property bool hasCrashes: typeof AssistantService !== "undefined" && AssistantService.recentCrashes && AssistantService.recentCrashes.length > 0
                        implicitHeight: hasCrashes ? 38 : 0
                        visible: hasCrashes
                        color: Qt.rgba(1, 0.2, 0.2, 0.12)
                        border.width: 1
                        border.color: Qt.rgba(1, 0.2, 0.2, 0.3)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padLarge
                            anchors.rightMargin: Theme.padLarge
                            spacing: 8

                            MaterialIcon {
                                iconName: "error_outline"
                                size: 16
                                color: Colors.m3error
                            }

                            Text {
                                text: crashBanner.hasCrashes ? ("Crash detected: " + AssistantService.recentCrashes[0].process_name) : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: Colors.m3error
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                implicitHeight: 24
                                implicitWidth: 60
                                radius: 6
                                color: Colors.m3error

                                Text {
                                    anchors.centerIn: parent
                                    text: "Debug"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: Colors.m3onError
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (crashBanner.hasCrashes) {
                                            AssistantService.diagnoseCrash(AssistantService.recentCrashes[0]);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 3. Quick Action Chips
                    QuickActionChips {
                        Layout.topMargin: 8
                        Layout.bottomMargin: 4
                    }

                    // 4. Scrollable Chat Stream View
                    ChatView {
                        id: chatView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.topMargin: 4
                        Layout.bottomMargin: 8
                    }

                    // 5. Input Bar
                    ChatInputBar {
                        id: chatInput
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.padLarge
                        Layout.rightMargin: Theme.padLarge
                        Layout.bottomMargin: Theme.padLarge

                        onRequestOpenImagePicker: root.imagePickerVisible = true

                        onSubmitMessage: function(text, images) {
                            if (typeof AssistantService !== "undefined") {
                                AssistantService.sendMessage(text, images);
                            }
                        }
                    }
                }
            }
        }

        // 6. Custom Provider Dialog Modal
        AddProviderDialog {
            visible: root.addProviderVisible
            onClosed: root.addProviderVisible = false
        }

        // 7. Liquid Glass File Picker Modal
        LiquidGlassFilePicker {
            visible: root.imagePickerVisible
            dragTarget: root.isFloating ? root : null
            onUserDragged: {
                root.userMoved = true;
                root.userDragged();
            }
            onAccepted: function(files) {
                for (let i = 0; i < files.length; i++) {
                    chatInput.stageImage(files[i]);
                }
                root.imagePickerVisible = false;
            }
            onCanceled: root.imagePickerVisible = false
        }
    }
}
