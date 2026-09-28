import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"
import "../config"
import "../services"
import "components"

// The AI Copilot's content. It is the body of a real toplevel window
// (AssistantWindow), so it fills its host and never positions itself: moving,
// resizing and stacking belong to the compositor (docs/LESSONS.md §8.9).
Item {
    id: root

    property bool testMode: false
    // The Quickshell window hosting this drawer. Handed down so the card
    // background, the header and the file picker can start compositor-native
    // move/resize operations.
    property var windowHandle: null
    readonly property alias cardItem: card
    readonly property alias chatInputItem: chatInput
    readonly property alias headerItem: headerItem
    readonly property alias sessionDrawerItem: sessionDrawer
    readonly property alias chatContentColumnItem: chatContentColumn
    readonly property alias chatViewItem: chatView
    readonly property alias scrollIndicatorItem: chatScrollIndicator
    readonly property alias crashBannerItem: crashBanner

    // Sizing.
    //
    // A Wayland toplevel cannot resize itself while it is mapped, so the shell
    // publishes the size the window should take *before* the surface is shown
    // (AssistantWindow binds its implicit size to preferredWidth/Height) and the
    // compositor owns the geometry from then on.
    readonly property int referenceWidth: (windowHandle && windowHandle.screen && windowHandle.screen.width > 0)
        ? windowHandle.screen.width
        : ((typeof Window !== "undefined" && Window.window && Window.window.width > 0) ? Window.window.width : 1920)
    readonly property int referenceHeight: (windowHandle && windowHandle.screen && windowHandle.screen.height > 0)
        ? windowHandle.screen.height
        : ((typeof Window !== "undefined" && Window.window && Window.window.height > 0) ? Window.window.height : 1080)
    readonly property int minWidth: 480
    readonly property int minHeight: 520
    readonly property int baseDefaultWidth: Math.min(740, Math.max(480, Math.round(referenceWidth * 0.48)))
    readonly property int sidebarExtraWidth: sessionsVisible ? 280 : 0
    readonly property int defaultWidth: baseDefaultWidth + sidebarExtraWidth
    readonly property int defaultHeight: Math.min(840, Math.max(540, Math.round(referenceHeight * 0.76)))
    readonly property int maxWidth: Math.max(minWidth, referenceWidth - 32)
    readonly property int maxHeight: Math.max(minHeight, referenceHeight - 32)
    readonly property int preferredWidth: Math.min(maxWidth, Math.max(minWidth, defaultWidth))
    readonly property int preferredHeight: Math.min(maxHeight, Math.max(minHeight, defaultHeight))

    property bool isOpen: (typeof Config !== "undefined") ? Config.assistantVisible : false
    property bool addProviderVisible: false
    property bool imagePickerVisible: false
    property bool sessionsVisible: false

    onIsOpenChanged: {
        if (isOpen) {
            if (typeof AssistantService !== "undefined" && typeof AssistantService.refreshStatus === "function") {
                AssistantService.refreshStatus();
            }
            // Re-probe voice readiness on every open. The engine or model can be
            // installed from Settings while the shell is running, so a probe
            // taken only at startup would leave a stale, wrong mic-button state.
            if (typeof AssistantService !== "undefined" && typeof AssistantService.refreshVoiceStatus === "function") {
                AssistantService.refreshVoiceStatus();
            }
            Qt.callLater(function() {
                if (typeof chatInput !== "undefined" && chatInput.focusInput) {
                    chatInput.focusInput();
                }
            });
        }
    }

    // Motion: the compositor animates window show/minimize; the content only
    // settles in and out.
    scale: isOpen ? 1.0 : 0.95

    Behavior on scale {
        NumberAnimation {
            duration: Theme.animExpressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
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
    //
    // The card fills the toplevel exactly. Its ambient drop shadow is disabled:
    // it would be drawn outside the card, i.e. outside the surface, and a
    // Wayland toplevel cannot mask those pixels away from input - so an inset
    // card would silently swallow clicks on the desktop behind it. The specular
    // rim and the compositor blur carry the glass edge instead (LESSONS 9.1).
    LiquidGlassCard {
        id: card
        anchors.fill: parent
        radius: (typeof Theme !== "undefined") ? Theme.radiusGlassModal : 24
        elevation: 24
        showShadow: false

        // Readable glass substrate, shared with the settings content pane: the
        // card must stay legible over a bright wallpaper, not dissolve into it.
        color: (typeof Colors !== "undefined") ? Colors.glassPanelSubstrate : "#1e1e2e"

        focus: root.isOpen
        Keys.onEscapePressed: Config.closeAssistant()

        // Empty card surfaces start a compositor-native window move, so dragging
        // the card drags the window exactly like a titlebar would.
        MouseArea {
            id: dialogDragArea
            anchors.fill: parent
            z: 0
            cursorShape: containsMouse ? Qt.OpenHandCursor : Qt.ArrowCursor

            onPressed: {
                if (root.windowHandle && typeof root.windowHandle.startSystemMove === "function") {
                    root.windowHandle.startSystemMove();
                }
            }
            onClicked: {}
        }

        // Edge & Corner Resize Handles.
        //
        // Each handle starts a compositor-native resize: the shell hands the
        // edges to the compositor and the window (with the card inside it)
        // follows. The drawer's limits travel as the window's size hints.
        MouseArea {
            id: rightResizeHandle
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            // Narrow enough to stay out of the scroll strip's lane (12px).
            width: 8
            z: 30
            cursorShape: Qt.SizeHorCursor

            onPressed: {
                if (root.windowHandle) root.windowHandle.startSystemResize(Qt.RightEdge);
            }
        }

        MouseArea {
            id: bottomResizeHandle
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 10
            z: 30
            cursorShape: Qt.SizeVerCursor

            onPressed: {
                if (root.windowHandle) root.windowHandle.startSystemResize(Qt.BottomEdge);
            }
        }

        MouseArea {
            id: leftResizeHandle
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 10
            z: 30
            cursorShape: Qt.SizeHorCursor

            onPressed: {
                if (root.windowHandle) root.windowHandle.startSystemResize(Qt.LeftEdge);
            }
        }

        MouseArea {
            id: cornerResizeHandle
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // Kept inside the scroll strip's lane boundary so the bar stays
            // grabbable right down to its bottom end.
            width: 12
            height: 12
            z: 40
            cursorShape: Qt.SizeFDiagCursor

            onPressed: {
                if (root.windowHandle) root.windowHandle.startSystemResize(Qt.RightEdge | Qt.BottomEdge);
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
                    ctx.moveTo(width - 2, height - 6);
                    ctx.lineTo(width - 6, height - 2);

                    ctx.moveTo(width - 2, height - 9);
                    ctx.lineTo(width - 9, height - 2);

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
                windowHandle: root.windowHandle
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

                    // 3. Proactive Crash Banner (Multi-Crash Carousel & Dismissible Alert)
                    Rectangle {
                        id: crashBanner
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.padLarge
                        Layout.rightMargin: Theme.padLarge
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        radius: 10

                        readonly property var crashesList: (typeof AssistantService !== "undefined" && AssistantService.activeCrashes) ? AssistantService.activeCrashes : []
                        readonly property int crashCount: crashesList ? crashesList.length : 0
                        readonly property bool hasCrashes: crashCount > 0

                        property int currentCrashIndex: 0
                        readonly property int safeIndex: crashCount > 0 ? Math.max(0, Math.min(currentCrashIndex, crashCount - 1)) : 0
                        readonly property var currentCrash: hasCrashes ? crashesList[safeIndex] : null

                        property alias prevMouseItem: prevMouse
                        property alias nextMouseItem: nextMouse
                        property alias debugMouseItem: dbgMouse
                        property alias dismissMouseItem: dismissMouse

                        implicitHeight: hasCrashes ? 42 : 0
                        visible: implicitHeight > 0
                        clip: true
                        color: Qt.rgba(1.0, 0.22, 0.22, 0.12)
                        border.width: 1
                        border.color: Qt.rgba(1.0, 0.22, 0.22, 0.28)

                        Behavior on implicitHeight {
                            enabled: !root.testMode
                            NumberAnimation {
                                duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastSpatial) ? Theme.animExpressiveFastSpatial : 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padLarge
                            anchors.rightMargin: Theme.padLarge
                            spacing: 8

                            // Error icon
                            MaterialIcon {
                                iconName: "error_outline"
                                size: 16
                                color: Colors.m3error
                            }

                            // Process name & details
                            RowLayout {
                                spacing: 6
                                Layout.fillWidth: true

                                Text {
                                    text: "Crash detected:"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Normal
                                    color: Colors.m3onSurface
                                }

                                Text {
                                    text: crashBanner.currentCrash ? crashBanner.currentCrash.process_name : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: Colors.m3error
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 140
                                }

                                // Signal badge if available (e.g. SIGABRT, SIGSEGV)
                                Rectangle {
                                    implicitHeight: 18
                                    implicitWidth: sigTxt.implicitWidth + 8
                                    radius: 4
                                    color: Qt.rgba(1.0, 0.22, 0.22, 0.18)
                                    border.width: 1
                                    border.color: Qt.rgba(1.0, 0.22, 0.22, 0.35)
                                    visible: crashBanner.currentCrash && crashBanner.currentCrash.signal ? true : false

                                    Text {
                                        id: sigTxt
                                        anchors.centerIn: parent
                                        text: (crashBanner.currentCrash && crashBanner.currentCrash.signal) ? crashBanner.currentCrash.signal : ""
                                        font.family: Theme.fontMonospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: Colors.m3error
                                    }
                                }

                                // Multiplier badge if crash occurred multiple times (e.g. 2x)
                                Rectangle {
                                    id: countBadge
                                    implicitHeight: 18
                                    implicitWidth: countTxt.implicitWidth + 8
                                    radius: 4
                                    color: Qt.rgba(1.0, 0.22, 0.22, 0.18)
                                    border.width: 1
                                    border.color: Qt.rgba(1.0, 0.22, 0.22, 0.35)
                                    visible: crashBanner.currentCrash && crashBanner.currentCrash.count && crashBanner.currentCrash.count > 1 ? true : false

                                    Text {
                                        id: countTxt
                                        anchors.centerIn: parent
                                        text: (crashBanner.currentCrash && crashBanner.currentCrash.count && crashBanner.currentCrash.count > 1) ? (crashBanner.currentCrash.count + "x") : ""
                                        font.family: Theme.fontMonospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: Colors.m3error
                                    }
                                }

                                // Carousel pagination buttons when multiple crashes exist
                                RowLayout {
                                    spacing: 2
                                    visible: crashBanner.crashCount > 1

                                    Rectangle {
                                        width: 20
                                        height: 20
                                        radius: 6
                                        scale: prevMouse.pressed ? 0.90 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                        color: prevMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                        border.width: 1
                                        border.color: Colors.glassBorderSpecular

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            iconName: "chevron_left"
                                            size: 14
                                            color: Colors.m3onSurface
                                        }

                                        MouseArea {
                                            id: prevMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (crashBanner.crashCount > 0) {
                                                    crashBanner.currentCrashIndex = (crashBanner.safeIndex - 1 + crashBanner.crashCount) % crashBanner.crashCount;
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: (crashBanner.safeIndex + 1) + " of " + crashBanner.crashCount
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        color: Colors.m3onSurfaceVariant
                                        Layout.leftMargin: 2
                                        Layout.rightMargin: 2
                                    }

                                    Rectangle {
                                        width: 20
                                        height: 20
                                        radius: 6
                                        scale: nextMouse.pressed ? 0.90 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                        color: nextMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                        border.width: 1
                                        border.color: Colors.glassBorderSpecular

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            iconName: "chevron_right"
                                            size: 14
                                            color: Colors.m3onSurface
                                        }

                                        MouseArea {
                                            id: nextMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (crashBanner.crashCount > 0) {
                                                    crashBanner.currentCrashIndex = (crashBanner.safeIndex + 1) % crashBanner.crashCount;
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Action buttons: Debug + Dismiss (X)
                            RowLayout {
                                spacing: 6

                                // Debug button (Liquid Glass error pill)
                                Rectangle {
                                    implicitHeight: 24
                                    implicitWidth: dbgTxt.implicitWidth + 16
                                    radius: 12
                                    scale: dbgMouse.pressed ? 0.94 : (dbgMouse.containsMouse ? 1.04 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                    color: dbgMouse.containsMouse ? Qt.alpha(Colors.m3error, 0.32) : Qt.alpha(Colors.m3error, 0.20)
                                    border.width: 1
                                    border.color: dbgMouse.containsMouse ? Qt.lighter(Colors.m3error, 1.2) : Colors.m3error

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    Text {
                                        id: dbgTxt
                                        anchors.centerIn: parent
                                        text: "Debug"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: Colors.m3error
                                    }

                                    MouseArea {
                                        id: dbgMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (crashBanner.currentCrash && typeof AssistantService !== "undefined") {
                                                AssistantService.diagnoseCrash(crashBanner.currentCrash);
                                            }
                                        }
                                    }
                                }

                                // Dismiss (Close) button
                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: 12
                                    scale: dismissMouse.pressed ? 0.90 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                                    color: dismissMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                    border.width: dismissMouse.containsMouse ? 1 : 0
                                    border.color: Colors.glassBorderSpecular

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        iconName: "close"
                                        size: 14
                                        color: dismissMouse.containsMouse ? Colors.m3onSurface : Colors.m3onSurfaceVariant
                                    }

                                    MouseArea {
                                        id: dismissMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (crashBanner.currentCrash && typeof AssistantService !== "undefined") {
                                                AssistantService.dismissCrash(crashBanner.currentCrash.id);
                                            }
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
                    //
                    // The stream is wrapped so the scroll indicator can live
                    // *outside* the flickable: a Flickable's children scroll with
                    // its content, and an affordance that scrolls away is no
                    // affordance at all.
                    Item {
                        id: chatHost
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.topMargin: 4
                        Layout.bottomMargin: 8
                        // Reserve the scroll strip's lane: it has to sit clear of
                        // the window resize handles on the card's edge, and the
                        // bar belongs on the content's edge, not the card's.
                        Layout.rightMargin: 14

                        ChatView {
                            id: chatView
                            anchors.fill: parent
                        }

                        GlassScrollIndicator {
                            id: chatScrollIndicator
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.rightMargin: 0
                            flickable: chatView
                            // A stream keeps its bar visible at rest: the whole
                            // point is that the reader can see there is more.
                            restingOpacity: 0.45
                            barWidth: 4
                        }
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
            windowHandle: root.windowHandle
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
