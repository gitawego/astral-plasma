import QtQuick
import "../theme"

Item {
    id: root

    property int radius: Theme.radiusGlassCard
    property int padding: Theme.padMedium

    property bool interactive: false
    property bool hovered: false
    property bool pressed: false
    property bool selected: false

    property color baseColor: Colors.glassCard
    property color hoverColor: Colors.glassCardHover
    property color activeColor: Colors.glassCardActive

    property color fillColor: root.selected
        ? root.activeColor
        : (root.hovered ? root.hoverColor : root.baseColor)

    property color specularColor: Colors.glassBorderSpecular
    property color subtleBorderColor: Colors.glassBorderSubtle
    property color borderColor: root.selected
        ? Colors.primary
        : (root.hovered ? root.specularColor : root.subtleBorderColor)

    property real borderWidth: root.selected ? 1.5 : 1.0
    property bool showTopSpecular: false

    default property alias content: contentContainer.data
    readonly property alias cardRectangle: baseRect

    implicitWidth: 200
    implicitHeight: 60

    scale: root.interactive
        ? (root.pressed ? Theme.glassScaleBounce : (root.hovered ? 1.01 : 1.0))
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
        id: baseRect
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

        Behavior on border.width {
            NumberAnimation { duration: Theme.animExpressiveFastEffects }
        }



        Item {
            id: contentContainer
            anchors.fill: parent
            anchors.margins: root.padding
        }
    }
}
