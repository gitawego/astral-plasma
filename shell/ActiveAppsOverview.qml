import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"
import "../services"

// Active-apps overview: a fullscreen liquid-glass surface listing every
// running window with a live thumbnail; click a card to switch to that
// window. Toggled by the bare Meta key:
//   KWin registerShortcut -> daemon ShellIpc whitelist -> `overview` IPC ->
//   Config.overviewVisible -> this surface drives WindowService's capture
//   cycle while open.
PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    readonly property bool openRequested: Config.overviewVisible

    // A pick already handed activation to its window; dismissing WITHOUT a
    // pick must hand compositor activation back (`focus restore`), because
    // KWin does not reassign it when our Exclusive focus request is withdrawn
    // - which would freeze the dock's active-app display (the power modal and
    // UnifiedShell close over the exact same loop).
    property string pickedWindowId: ""

    // Entrance/exit progress. The window stays mapped while the close
    // animation still has frames (CentralDropdown's proven pattern), driven
    // by the M3 slow-spatial token - DESIGN.md assigns that token to large
    // overlays such as this one.
    property real offsetProgress: openRequested ? 1.0 : 0.0
    Behavior on offsetProgress {
        NumberAnimation {
            duration: Theme.animExpressiveSlowSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveSlowSpatial
        }
    }

    visible: offsetProgress > 0.001

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Dim scrim, fading with the entrance (never an opaque slab).
    color: Qt.rgba(0, 0, 0, 0.55 * root.offsetProgress)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: openRequested ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Compositor backdrop blur across the whole surface. ONE boolean gates
    // every dimension, so the region is always a valid positive-area rect or
    // fully empty - never a degenerate sliver KWin would keep painting. It
    // clears the moment closing starts, while 650ms of animation frames
    // remain to flush the clear (docs/LESSONS.md blur-region teardown rules).
    readonly property bool blurWanted: openRequested
    BackgroundEffect.blurRegion: Region {
        x: 0
        y: 0
        width: root.blurWanted ? root.width : 0
        height: root.blurWanted ? root.height : 0
    }

    // Escape closes. The scrim handles pointer dismissal; Meta toggles from
    // anywhere through IPC and needs no focus of its own.
    Item {
        id: keySink
        anchors.fill: parent
        focus: root.openRequested
        Keys.onEscapePressed: Config.closeOverview()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Config.closeOverview()
    }

    Process {
        id: focusRestoreProc
    }

    Connections {
        target: Config
        function onOverviewVisibleChanged() {
            if (Config.overviewVisible) {
                root.pickedWindowId = "";
                WindowService.startOverviewThumbnails();
            } else {
                WindowService.stopOverviewThumbnails();
                if (root.pickedWindowId === "") {
                    focusRestoreProc.command = [Config.daemonBin, "focus", "restore"];
                    focusRestoreProc.running = true;
                }
                root.pickedWindowId = "";
            }
        }
    }

    // Windows opening/closing while the overview is visible re-target the
    // rotation without restarting it (PreviewCycle re-reads items at wrap).
    Connections {
        target: WindowService
        function onWindowsChanged() {
            if (Config.overviewVisible) {
                WindowService.refreshOverviewThumbnails();
            }
        }
    }

    OverviewLayout {
        id: layout
    }

    readonly property int gridMargin: Theme.spaceExtraLarge * 2
    readonly property int gridGap: Theme.spaceLarge
    readonly property real availW: Math.max(0, root.width - 2 * root.gridMargin)
    readonly property real availH: Math.max(0, root.height - 2 * root.gridMargin)
    readonly property var grid: layout.compute(
        root.availW,
        root.availH,
        WindowService.windows ? WindowService.windows.length : 0,
        { gap: root.gridGap })
    readonly property bool gridOverflow: root.grid.gridH > root.availH

    // Zoom-settle entrance: one animated driver (offsetProgress) moves the
    // whole board, so no per-card timing is invented.
    Item {
        id: content
        anchors.fill: parent
        opacity: root.offsetProgress
        scale: 0.94 + 0.06 * root.offsetProgress
        transformOrigin: Item.Center

        GridView {
            id: gridV
            visible: root.grid.cols > 0
            clip: true
            width: root.grid.cols > 0 ? root.grid.gridW + root.gridGap : 0
            height: root.gridOverflow ? root.availH : root.grid.gridH + root.gridGap
            x: (root.width - width) / 2 + root.gridGap / 2
            y: root.gridOverflow ? root.gridMargin : (root.height - height) / 2 + root.gridGap / 2
            cellWidth: root.grid.cellW + root.gridGap
            cellHeight: root.grid.cellH + root.gridGap
            interactive: contentHeight > height
            model: WindowService.windows

            delegate: LiquidGlassCard {
                id: card
                width: root.grid.cellW
                height: root.grid.cellH
                radius: Theme.radiusGlassCard
                interactive: true
                hovered: cardMouse.containsMouse
                selected: Boolean(modelData.isActive)
                elevation: modelData.isActive ? 8 : 4
                showShadow: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.padSmall
                    spacing: Theme.spaceSmall

                    // Thumbnail well: concentric inner radius
                    // R_inner = R_outer - padding (AGENTS.md glass rule).
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusGlassCard - Theme.padSmall
                            color: Colors.surfaceContainerLowest
                            clip: true

                            LiveWindowThumbnail {
                                id: thumb
                                anchors.fill: parent
                                source: (WindowService.overviewThumbnails || {})[String(modelData.id)] || ""
                                identity: modelData.id
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "wallpaper"
                                size: 28
                                color: Colors.textOnSurfaceVariant
                                visible: !thumb.hasImage
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spaceSmall

                        Item {
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16

                            Image {
                                anchors.fill: parent
                                source: Config.iconUrl(modelData.iconName)
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: modelData.materialIcon ? modelData.materialIcon : "window"
                                size: 14
                                color: Colors.primary
                                visible: !parent.children[0].visible
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: (modelData.title && modelData.title.trim() !== "")
                                ? modelData.title
                                : (modelData.appName || "")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontLabelSmall
                            font.weight: Font.Medium
                            color: Colors.textOnSurface
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.pickedWindowId = String(modelData.id);
                        WindowService.activateWindow(modelData.id);
                        Config.closeOverview();
                    }
                }
            }
        }

        // Empty state: an empty overview is an invitation, not a void.
        Column {
            anchors.centerIn: parent
            spacing: Theme.spaceMedium
            visible: WindowService.windows.length === 0

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "space_dashboard"
                size: 44
                color: Colors.textOnSurfaceVariant
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No open windows"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.Medium
                color: Colors.textOnSurfaceVariant
            }
        }
    }
}
