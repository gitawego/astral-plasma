import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../components"
import "../theme"
import "../services"

Item {
    id: root

    property string summary: ""
    property string body: ""
    property string appName: ""
    property string timeStr: "now"
    property string materialIcon: "info"
    property string iconSource: ""
    property string imageSource: ""
    property var actions: []
    property bool expanded: false
    property int timeoutMs: 5000

    readonly property bool isMediaNotification: {
        let app = (root.appName || "").toLowerCase();
        return app.includes("strawberry") || 
               app.includes("elisa") || 
               app.includes("cloudmusic") || 
               app.includes("netease") || 
               app.includes("music") || 
               app.includes("player") || 
               app.includes("spotify") ||
               (typeof MprisMedia !== "undefined" && MprisMedia.identity && app.includes(MprisMedia.identity.toLowerCase()));
    }

    readonly property string effectiveCover: {
        let src = (root.imageSource && root.imageSource.length > 0) ? root.imageSource : root.iconSource;
        if (src && src.length > 0) {
            if (src.startsWith("/")) return "file://" + src;
            if (src.startsWith("file://") || src.startsWith("http://") || src.startsWith("https://")) return src;
        }
        // Fallback: If this is a media player notification or matches active track, use MprisMedia.artUrl
        if (typeof MprisMedia !== "undefined" && MprisMedia.artUrl && MprisMedia.artUrl.length > 0) {
            if (isMediaNotification || 
                (root.summary && MprisMedia.title && root.summary.toLowerCase().includes(MprisMedia.title.toLowerCase())) ||
                (root.body && MprisMedia.artist && root.body.toLowerCase().includes(MprisMedia.artist.toLowerCase()))) {
                let art = MprisMedia.artUrl;
                if (art.startsWith("/")) return "file://" + art;
                return art;
            }
        }
        return "";
    }
    readonly property bool hasImageCover: effectiveCover.length > 0

    property real borderThickness: (typeof Config !== "undefined" && Config.borderThickness) ? Config.borderThickness : 14
    property real borderRounding: (typeof Config !== "undefined" && Config.borderRounding) ? Config.borderRounding : 24

    property bool isDismissed: false

    readonly property alias fusedPanel: panel
    readonly property alias autoCloseTimer: autoCloseTimer

    signal closed()
    signal actionInvoked(string actionId)

    function toggleExpanded() {
        expanded = !expanded;
    }

    function close() {
        autoCloseTimer.stop();
        root.isDismissed = true;
        root.closed();
    }

    width: 380
    height: panel.panelHeight
    implicitWidth: width
    implicitHeight: height

    Timer {
        id: autoCloseTimer
        interval: root.timeoutMs
        running: root.visible && !root.isDismissed && !hoverHandler.hovered && root.timeoutMs > 0
        repeat: false
        onTriggered: root.close()
    }

    onVisibleChanged: {
        if (root.visible) {
            root.isDismissed = false;
            autoCloseTimer.restart();
        } else {
            autoCloseTimer.stop();
        }
    }

    onSummaryChanged: {
        if (root.visible) {
            root.isDismissed = false;
            autoCloseTimer.restart();
        }
    }

    FusedPanel {
        id: panel
        anchors.fill: parent
        attachEdge: "topRight"
        panelWidth: root.width
        panelHeight: root.expanded ? (expandedContent.implicitHeight + 36) : (root.hasImageCover ? 78 : 74)
        borderThickness: root.borderThickness
        borderRounding: root.borderRounding
        fillColor: (typeof Colors !== "undefined" && Colors.surface) ? Colors.surface : "#141318"
        isOpen: root.visible && !root.isDismissed

        Behavior on panelHeight {
            NumberAnimation {
                duration: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial) ? Theme.animExpressiveDefaultSpatial : 500
                easing.type: Easing.BezierSpline
                easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
            }
        }

        HoverHandler {
            id: hoverHandler
        }

        Item {
            id: contentContainer
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16 + root.borderThickness
            anchors.topMargin: 14
            anchors.bottomMargin: 14

            // Left Icon Badge / Album Art Cover (Circular like on Dashboard)
            Item {
                id: iconBadge
                anchors.left: parent.left
                anchors.top: root.expanded ? parent.top : undefined
                anchors.topMargin: root.expanded ? 2 : 0
                anchors.verticalCenter: root.expanded ? undefined : parent.verticalCenter
                width: root.hasImageCover ? 46 : 38
                height: width

                // Round mask geometry (strictly circular mask like on dashboard)
                Rectangle {
                    id: badgeCircleMask
                    anchors.fill: parent
                    radius: width / 2
                    color: "white"
                    visible: false
                    layer.enabled: true
                }

                // Background / fallback circle
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : "#2b2930"

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: (root.isMediaNotification || root.hasImageCover) ? "music_note" : root.materialIcon
                        size: root.hasImageCover ? 22 : 20
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#d0bcff"
                        visible: !(root.hasImageCover && coverImg.status === Image.Ready)
                    }
                }

                // Cover image masked strictly to the circular boundary (like on dashboard)
                Item {
                    anchors.fill: parent
                    visible: root.hasImageCover && coverImg.status === Image.Ready

                    Image {
                        id: coverImg
                        anchors.fill: parent
                        source: root.effectiveCover
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: badgeCircleMask
                    }
                }

                // Circular border ring matching dashboard circle definition
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: root.hasImageCover ? (typeof Colors !== "undefined" ? Colors.outlineVariant : Qt.rgba(1, 1, 1, 0.15)) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: root.hasImageCover ? 1.5 : 1
                }
            }

            // Right Content Area
            Item {
                anchors.left: iconBadge.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                // Row 1: Summary + Time + Controls
                Row {
                    id: headerRow
                    anchors.left: parent.left
                    anchors.right: headerControls.left
                    anchors.rightMargin: 6
                    anchors.top: parent.top
                    spacing: 6

                    Text {
                        text: root.summary
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: (typeof Colors !== "undefined" && Colors.textOnSurface) ? Colors.textOnSurface : "#e6e1e6"
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, parent.width - timeText.implicitWidth - 20)
                    }

                    Text {
                        text: "•"
                        font.pixelSize: 11
                        color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#948f99"
                    }

                    Text {
                        id: timeText
                        text: root.timeStr
                        font.pixelSize: 11
                        color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#948f99"
                    }
                }

                // Header Controls (Expand + Close Buttons)
                Row {
                    id: headerControls
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 4

                    // Expand Chevron Button
                    Rectangle {
                        id: expandBtn
                        width: 24
                        height: 24
                        radius: 12
                        color: expandHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.surfaceContainerHighest) ? Colors.surfaceContainerHighest : "#36343b") : "transparent"

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "expand_more"
                            size: 18
                            color: (typeof Colors !== "undefined" && Colors.textOnSurfaceVariant) ? Colors.textOnSurfaceVariant : "#cac4d0"
                            rotation: root.expanded ? 180 : 0

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastSpatial) ? Theme.animExpressiveFastSpatial : 350
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
                                }
                            }
                        }

                        MouseArea {
                            id: expandHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleExpanded()
                        }
                    }

                    // Direct Close Button
                    Rectangle {
                        id: headerCloseBtn
                        width: 24
                        height: 24
                        radius: 12
                        color: closeBtnHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.surfaceContainerHighest) ? Colors.surfaceContainerHighest : "#36343b") : "transparent"

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "close"
                            size: 16
                            color: (typeof Colors !== "undefined" && Colors.textOnSurfaceVariant) ? Colors.textOnSurfaceVariant : "#cac4d0"
                        }

                        MouseArea {
                            id: closeBtnHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // Row 2: Collapsed Body Preview
                Text {
                    id: bodyPreview
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: headerRow.bottom
                    anchors.topMargin: 4
                    visible: !root.expanded
                    text: root.body
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: 12
                    color: (typeof Colors !== "undefined" && Colors.textOnSurfaceVariant) ? Colors.textOnSurfaceVariant : "#cac4d0"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Expanded Content (Full body + Action Buttons)
                Column {
                    id: expandedContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: headerRow.bottom
                    anchors.topMargin: 6
                    visible: root.expanded
                    spacing: 10

                    Text {
                        width: parent.width
                        text: root.body
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 12
                        color: (typeof Colors !== "undefined" && Colors.textOnSurfaceVariant) ? Colors.textOnSurfaceVariant : "#cac4d0"
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    // Action Buttons Row
                    Row {
                        spacing: 8

                        Rectangle {
                            height: 28
                            width: 60
                            radius: 14
                            color: closeHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.surfaceContainerHighest) ? Colors.surfaceContainerHighest : "#36343b") : Qt.alpha(Colors.surfaceContainerHigh, 0.6)

                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialIcon { text: "close"; size: 14; color: (typeof Colors !== "undefined" && Colors.textOnSurface) ? Colors.textOnSurface : "#e6e1e6" }
                                Text { text: "Close"; font.pixelSize: 11; color: (typeof Colors !== "undefined" && Colors.textOnSurface) ? Colors.textOnSurface : "#e6e1e6" }
                            }

                            MouseArea {
                                id: closeHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
