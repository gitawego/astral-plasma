import QtQuick
import "../theme"
import "../components"

Rectangle {
    id: root

    property string text: ""
    property string subtext: ""
    property string materialIcon: ""
    property string iconSource: ""
    property bool checked: false
    property bool isDangerous: false
    property bool enabled: true

    signal clicked()

    width: parent ? parent.width : 200
    height: 38
    radius: 8

    color: {
        if (!enabled) return "transparent";
        if (hoverArea.containsMouse) {
            return isDangerous ? Qt.rgba(0.85, 0.2, 0.15, 0.16) : ((typeof Colors !== "undefined" && Colors.surfaceContainerHighest) ? Colors.surfaceContainerHighest : "#36343b");
        }
        return "transparent";
    }

    Behavior on color {
        ColorAnimation {
            duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastEffects) ? Theme.animExpressiveFastEffects : 150
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastEffects) ? Theme.curveExpressiveFastEffects : [0.31, 0.94, 0.34, 1.0, 1.0, 1.0]
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Item {
            width: 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.fill: parent
                source: root.iconSource
                fillMode: Image.PreserveAspectFit
                visible: root.iconSource !== "" && status === Image.Ready
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: root.materialIcon
                size: 18
                visible: root.materialIcon !== "" && (!parent.children[0] || !parent.children[0].visible)
                color: {
                    if (root.isDangerous && hoverArea.containsMouse) return "#ffb4ab";
                    if (root.checked) return (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#d0bcff";
                    if (hoverArea.containsMouse) return (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#d0bcff";
                    return (typeof Colors !== "undefined" && Colors.textOnSurfaceVariant) ? Colors.textOnSurfaceVariant : "#cac4d0";
                }
            }
        }

        Column {
            width: parent.width - 30
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                text: root.text
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: 13
                font.weight: hoverArea.containsMouse ? Font.Medium : Font.Normal
                color: {
                    if (!root.enabled) return (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#7a757f";
                    if (root.isDangerous && hoverArea.containsMouse) return "#ffb4ab";
                    if (hoverArea.containsMouse || root.checked) return (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#d0bcff";
                    return (typeof Colors !== "undefined" && Colors.textOnSurface) ? Colors.textOnSurface : "#e6e1e6";
                }
                elide: Text.ElideRight
                width: parent.width
            }

            Text {
                text: root.subtext
                visible: root.subtext !== ""
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: 10
                color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#948f99"
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled) {
                root.clicked();
            }
        }
    }
}
