import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"

Item {
    id: root

    property string summary: ""
    property string body: ""
    property string appName: ""
    property string timeStr: "now"
    property string materialIcon: "info"
    property string iconSource: ""
    property var actions: []
    property bool expanded: false
    property int timeoutMs: 5000

    property real borderThickness: (typeof Config !== "undefined" && Config.borderThickness) ? Config.borderThickness : 14
    property real borderRounding: (typeof Config !== "undefined" && Config.borderRounding) ? Config.borderRounding : 24

    readonly property alias fusedPanel: panel

    signal closed()
    signal actionInvoked(string actionId)

    function toggleExpanded() {
        expanded = !expanded;
    }

    width: 380
    height: panel.panelHeight
    implicitWidth: width
    implicitHeight: height

    Timer {
        id: autoCloseTimer
        interval: root.timeoutMs
        running: root.visible && !hoverHandler.hovered && root.timeoutMs > 0
        repeat: false
        onTriggered: root.closed()
    }

    onSummaryChanged: {
        if (root.visible) {
            autoCloseTimer.restart();
        }
    }

    FusedPanel {
        id: panel
        anchors.fill: parent
        attachEdge: "topRight"
        panelWidth: root.width
        panelHeight: root.expanded ? (expandedContent.implicitHeight + 36) : 74
        borderThickness: root.borderThickness
        borderRounding: root.borderRounding
        fillColor: (typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : "#1c1b20"
        isOpen: root.visible

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

            // Left Icon Badge
            Rectangle {
                id: iconBadge
                anchors.left: parent.left
                anchors.top: parent.top
                width: 38
                height: 38
                radius: 19
                color: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : "#2b2930"

                Image {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    source: root.iconSource
                    fillMode: Image.PreserveAspectFit
                    visible: root.iconSource !== "" && status === Image.Ready
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.materialIcon
                    size: 20
                    color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#d0bcff"
                    visible: !parent.children[0].visible
                }
            }

            // Right Content Area
            Item {
                anchors.left: iconBadge.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                // Row 1: Summary + Time + Expand Button
                Row {
                    id: headerRow
                    anchors.left: parent.left
                    anchors.right: expandBtn.left
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

                // Expand Chevron Button
                Rectangle {
                    id: expandBtn
                    anchors.right: parent.right
                    anchors.top: parent.top
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
                                onClicked: root.closed()
                            }
                        }
                    }
                }
            }
        }
    }
}
