import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../components"
import "../theme"
import "../config"
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
        let isMprisMatch = (typeof MprisMedia !== "undefined" && Boolean(MprisMedia.identity)) ? app.includes(MprisMedia.identity.toLowerCase()) : false;
        return Boolean(app.includes("strawberry") || 
                       app.includes("elisa") || 
                       app.includes("cloudmusic") || 
                       app.includes("netease") || 
                       app.includes("music") || 
                       app.includes("player") || 
                       app.includes("spotify") ||
                       isMprisMatch);
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
    property real borderRounding: (typeof Config !== "undefined" && Config.borderRounding) ? Config.borderRounding : 20

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
        panelHeight: root.expanded ? (expandedContent.implicitHeight + 52) : (root.hasImageCover ? 84 : 78)
        borderThickness: root.borderThickness
        borderRounding: root.borderRounding
        fillColor: (typeof Colors !== "undefined" && Colors.glassSurface) ? Colors.glassSurface : Qt.rgba(0.08, 0.07, 0.10, 1.0)
        borderColor: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.12)
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
            anchors.topMargin: root.borderThickness + 4
            anchors.bottomMargin: 10

            // Top specular highlight line
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.4)
                opacity: 0.6
            }

            // Left Icon Badge / Album Art Cover
            Item {
                id: iconBadge
                anchors.left: parent.left
                anchors.top: root.expanded ? parent.top : undefined
                anchors.topMargin: root.expanded ? 4 : 0
                anchors.verticalCenter: root.expanded ? undefined : parent.verticalCenter
                width: root.hasImageCover ? 42 : 36
                height: width

                // Round / squircle mask geometry
                Rectangle {
                    id: badgeCircleMask
                    anchors.fill: parent
                    radius: root.hasImageCover ? (width / 2) : 10
                    color: "white"
                    visible: false
                    layer.enabled: true
                }

                // Frosted glass icon plate
                Rectangle {
                    anchors.fill: parent
                    radius: root.hasImageCover ? (width / 2) : 10
                    color: (typeof Colors !== "undefined" && Colors.glassCard) ? Colors.glassCard : Qt.rgba(1, 1, 1, 0.12)
                    border.color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.25)
                    border.width: 1

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: (root.isMediaNotification || root.hasImageCover) ? "music_note" : root.materialIcon
                        size: root.hasImageCover ? 22 : 19
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#d0bcff"
                        visible: !(root.hasImageCover && coverImg.status === Image.Ready)
                    }
                }

                // Cover image masked to shape
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

                // Specular border ring
                Rectangle {
                    anchors.fill: parent
                    radius: root.hasImageCover ? (width / 2) : 10
                    color: "transparent"
                    border.color: root.hasImageCover ? ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.4)) : Qt.rgba(1, 1, 1, 0.2)
                    border.width: root.hasImageCover ? 1.5 : 1
                }
            }

            // Right Content Area
            Item {
                anchors.left: iconBadge.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.bottom: parent.bottom

                // Row 1: App Name + Time + Controls
                Row {
                    id: appHeaderRow
                    anchors.left: parent.left
                    anchors.right: headerControls.left
                    anchors.rightMargin: 6
                    anchors.top: parent.top
                    spacing: 6

                    Text {
                        text: (root.appName && root.appName.length > 0) ? root.appName : "System"
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        renderType: Text.QtRendering
                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "•"
                        font.pixelSize: 10
                        renderType: Text.QtRendering
                        color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#8F9099"
                    }

                    Text {
                        id: timeText
                        text: root.timeStr
                        font.pixelSize: 11
                        renderType: Text.QtRendering
                        color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#8F9099"
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
                        width: 22
                        height: 22
                        radius: 11
                        color: expandHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.glassCardHover) ? Colors.glassCardHover : Qt.rgba(1, 1, 1, 0.18)) : "transparent"

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "expand_more"
                            size: 16
                            color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF"
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
                        width: 22
                        height: 22
                        radius: 11
                        color: closeBtnHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.glassCardHover) ? Colors.glassCardHover : Qt.rgba(1, 1, 1, 0.18)) : "transparent"

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "close"
                            size: 15
                            color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF"
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

                // Row 2: Summary / Title
                Text {
                    id: summaryText
                    anchors.left: parent.left
                    anchors.right: headerControls.left
                    anchors.rightMargin: 6
                    anchors.top: appHeaderRow.bottom
                    anchors.topMargin: 2
                    text: root.summary
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    renderType: Text.QtRendering
                    color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF"
                    elide: Text.ElideRight
                }

                // Row 3: Collapsed Body Preview
                Text {
                    id: bodyPreview
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: summaryText.bottom
                    anchors.topMargin: 2
                    visible: !root.expanded && root.body.length > 0
                    text: root.body
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: 12
                    renderType: Text.QtRendering
                    color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#c7c6ca"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Expanded Content (Full body + Action Buttons)
                Column {
                    id: expandedContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: summaryText.bottom
                    anchors.topMargin: 4
                    visible: root.expanded
                    spacing: 8

                    Text {
                        width: parent.width
                        text: root.body
                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                        font.pixelSize: 12
                        renderType: Text.QtRendering
                        color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#c7c6ca"
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    // Action Buttons Row
                    Row {
                        spacing: 8

                        Rectangle {
                            height: 26
                            width: 62
                            radius: 13
                            color: closeHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.glassCardHover) ? Colors.glassCardHover : Qt.rgba(1, 1, 1, 0.22)) : ((typeof Colors !== "undefined" && Colors.glassCard) ? Colors.glassCard : Qt.rgba(1, 1, 1, 0.12))
                            border.color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.3)
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialIcon { text: "close"; size: 13; color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF" }
                                Text { text: "Close"; font.pixelSize: 11; renderType: Text.QtRendering; color: (typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#FFFFFF" }
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
