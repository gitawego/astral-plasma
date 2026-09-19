import QtQuick
import "../theme"

Item {
    id: root

    property bool isPrimary: false
    property bool interactive: true
    property bool active: false
    property bool hovered: false
    property bool pressed: false

    signal clicked()

    property color baseColor: root.isPrimary
        ? ((typeof Colors !== "undefined" && Colors.glassPillActive) ? Colors.glassPillActive : Qt.rgba(1, 1, 1, 0.15))
        : ((typeof Colors !== "undefined" && Colors.glassPill) ? Colors.glassPill : Qt.rgba(1, 1, 1, 0.08))

    property color hoverColor: root.isPrimary
        ? ((typeof Colors !== "undefined" && Colors.glassPillHover) ? Colors.glassPillHover : Qt.rgba(1, 1, 1, 0.22))
        : ((typeof Colors !== "undefined" && Colors.glassPillHover) ? Colors.glassPillHover : Qt.rgba(1, 1, 1, 0.15))

    property color activeColor: (typeof Colors !== "undefined" && Colors.glassPillActive) ? Colors.glassPillActive : Qt.rgba(1, 1, 1, 0.20)

    property color fillColor: root.active
        ? root.activeColor
        : (root.hovered ? root.hoverColor : root.baseColor)

    property color textColor: "#FFFFFF"

    property color borderColor: root.active 
        ? ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.6))
        : (root.hovered ? ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.6)) : ((typeof Colors !== "undefined" && Colors.glassBorderSubtle) ? Colors.glassBorderSubtle : Qt.rgba(1, 1, 1, 0.12)))

    property real borderWidth: root.active ? 1.2 : 1.0
    property int paddingHorizontal: 16
    property int paddingVertical: 8
    property int radius: height / 2

    // Liquid Glass Elevation
    property bool showShadow: true
    property real elevation: 5

    default property alias content: contentContainer.data
    readonly property alias pillRectangle: pillRect
    readonly property alias contactShadowItem: contactShadow

    implicitWidth: 100
    implicitHeight: 36

    scale: root.interactive
        ? (root.pressed ? ((typeof Theme !== "undefined" && Theme.glassScaleBounce) ? Theme.glassScaleBounce : 0.96) : (root.hovered ? 1.02 : 1.0))
        : 1.0

    Behavior on scale {
        enabled: root.interactive
        NumberAnimation {
            duration: root.pressed ? 120 : 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveGlassElastic) ? Theme.curveGlassElastic : [0.34, 1.56, 0.64, 1]
        }
    }

    // 0. Ambient Contact Drop Shadow
    Rectangle {
        id: contactShadow
        visible: root.showShadow
        z: -1
        anchors.fill: pillRect
        anchors.topMargin: Math.max(2, Math.round(root.elevation * 0.4))
        anchors.bottomMargin: -Math.max(2, Math.round(root.elevation * 0.45))
        anchors.leftMargin: -Math.max(1, Math.round(root.elevation * 0.12))
        anchors.rightMargin: -Math.max(1, Math.round(root.elevation * 0.12))
        radius: root.radius
        color: "transparent"
        border.color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0, 0, 0, 0.32) : Qt.rgba(0, 0, 0, 0.12)
        border.width: Math.max(2, Math.round(root.elevation * 0.45))
        opacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.35 : 0.20
    }

    Rectangle {
        id: pillRect
        anchors.fill: parent
        radius: root.radius
        color: root.fillColor
        border.color: root.borderColor
        border.width: root.borderWidth

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        Behavior on border.color {
            ColorAnimation { duration: 150 }
        }

        Item {
            id: contentContainer
            anchors.fill: parent
            anchors.leftMargin: root.paddingHorizontal
            anchors.rightMargin: root.paddingHorizontal
            anchors.topMargin: root.paddingVertical
            anchors.bottomMargin: root.paddingVertical
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered = true
        onExited: {
            root.hovered = false;
            root.pressed = false;
        }
        onPressed: root.pressed = true
        onReleased: root.pressed = false
        onCanceled: {
            root.hovered = false;
            root.pressed = false;
        }
        onClicked: root.clicked()
    }
}
