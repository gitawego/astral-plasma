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
        ? Colors.glassPillActive
        : Colors.glassPill

    property color hoverColor: root.isPrimary
        ? Colors.glassPillHover
        : Colors.glassPillHover

    property color activeColor: Colors.glassPillActive

    property color fillColor: root.active
        ? root.activeColor
        : (root.hovered ? root.hoverColor : root.baseColor)

    property color textColor: "#FFFFFF"

    property color borderColor: root.active 
        ? Colors.glassBorderSpecular 
        : (root.hovered ? Colors.glassBorderSpecular : Colors.glassBorderSubtle)

    property real borderWidth: root.active ? 1.2 : 1.0
    property int paddingHorizontal: 16
    property int paddingVertical: 8
    property int radius: height / 2

    default property alias content: contentContainer.data
    readonly property alias pillRectangle: pillRect

    implicitWidth: 100
    implicitHeight: 36

    scale: root.interactive
        ? (root.pressed ? Theme.glassScaleBounce : (root.hovered ? 1.02 : 1.0))
        : 1.0

    Behavior on scale {
        enabled: root.interactive
        NumberAnimation {
            duration: root.pressed ? Theme.animGlassPress : Theme.animGlassRelease
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveGlassElastic
        }
    }

    Rectangle {
        id: pillRect
        anchors.fill: parent
        radius: root.radius
        color: root.fillColor
        border.color: root.borderColor
        border.width: root.borderWidth

        Behavior on color {
            ColorAnimation { duration: Theme.animExpressiveFastEffects }
        }

        Behavior on border.color {
            ColorAnimation { duration: Theme.animExpressiveFastEffects }
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
