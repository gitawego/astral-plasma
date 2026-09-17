import QtQuick
import QtQuick.Effects
import "../theme"

Item {
    id: root

    property int radius: Theme.radiusGlassModal
    property color glassColor: Colors.glassSurface
    property color specularColor: Colors.glassBorderSpecular
    property color subtleBorderColor: Colors.glassBorderSubtle
    property color causticColor: Colors.glassCausticGlow

    property bool showSpecular: true
    property bool showCaustic: true
    property bool showShadow: true
    property bool enableCursorGlint: true
    property bool clipContent: false

    // Interactive state (optional, for clickable glass surfaces)
    property bool interactive: false
    property bool pressed: false
    property bool hovered: false
    property real cursorX: -1
    property real cursorY: -1

    // Content alias
    default property alias content: contentContainer.data
    readonly property alias surfaceRectangle: baseGlass

    implicitWidth: 300
    implicitHeight: 200

    scale: root.interactive
        ? (root.pressed ? Theme.glassScaleBounce : (root.hovered ? 1.008 : 1.0))
        : 1.0

    Behavior on scale {
        enabled: root.interactive
        NumberAnimation {
            duration: root.pressed ? Theme.animGlassPress : Theme.animGlassRelease
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveGlassElastic
        }
    }

    // Soft ambient drop shadow layer
    layer.enabled: root.showShadow
    layer.effect: MultiEffect {
        shadowEnabled: root.showShadow
        blurMax: 36
        shadowBlur: 0.85
        shadowVerticalOffset: 6
        shadowColor: Colors.glassShadowColor
    }

    // Base Translucent Glass Slab
    Rectangle {
        id: baseGlass
        anchors.fill: parent
        radius: root.radius
        color: root.glassColor
        clip: root.clipContent

        border.width: Theme.glassBorderWidth
        border.color: root.subtleBorderColor

        Behavior on color {
            ColorAnimation { duration: Theme.animExpressiveFastEffects }
        }

        Behavior on border.color {
            ColorAnimation { duration: Theme.animExpressiveFastEffects }
        }

        // Inner Optical Refraction Caustic Glow (Light entering top edge)
        Rectangle {
            id: causticGlow
            visible: root.showCaustic
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.min(parent.height * 0.20, 32)
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.causticColor }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Dynamic Specular Cursor Glint (Follows pointer across glass surface)
        Rectangle {
            id: cursorGlint
            visible: root.enableCursorGlint && root.cursorX >= 0 && root.cursorY >= 0
            x: root.cursorX - width / 2
            y: root.cursorY - height / 2
            width: Math.min(root.width, 240)
            height: Math.min(root.height, 240)
            radius: width / 2
            color: Colors.isDarkMode ? "#FFFFFF" : Colors.accentPrimary
            opacity: root.hovered ? (Colors.isDarkMode ? 0.06 : 0.10) : 0.0

            Behavior on opacity {
                NumberAnimation { duration: Theme.animExpressiveFastEffects }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 48
            }
        }

        // Directional Top Specular Rim Glare (ultra-fine hairline catch)
        Rectangle {
            id: specularRimTop
            visible: root.showSpecular
            anchors.top: parent.top
            anchors.topMargin: 0.5
            anchors.left: parent.left
            anchors.leftMargin: parent.radius * 0.35
            anchors.right: parent.right
            anchors.rightMargin: parent.radius * 0.35
            height: Theme.glassSpecularWidth
            color: root.specularColor
            radius: 1
            opacity: root.hovered ? 0.45 : 0.30

            Behavior on opacity {
                NumberAnimation { duration: Theme.animExpressiveFastEffects }
            }
        }

        // Content Area
        Item {
            id: contentContainer
            anchors.fill: parent
        }
    }
}
