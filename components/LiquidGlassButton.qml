import QtQuick
import "../theme"

Item {
    id: root

    signal clicked()

    // Content properties
    property string text: ""
    property string iconName: ""
    property string iconText: ""
    property int iconSize: 18

    // Styling & Theme properties
    property bool isPrimary: false
    property bool interactive: true
    property bool active: false
    property bool hovered: false
    property bool pressed: false

    property color accentColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
    property color textColor: (typeof Colors !== "undefined" && Colors.isDarkMode) ? "#FFFFFF" : "#2A2A2E"
    property color textShadowColor: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.18)
    property real elevation: 6
    property int paddingHorizontal: 22
    property int paddingVertical: 10

    // Stadium Pill Geometry
    readonly property int radius: Math.round(height / 2)
    implicitHeight: 42
    implicitWidth: Math.max(100, contentRow.implicitWidth + paddingHorizontal * 2)

    // Absolute vertical position helpers for 3D depth assertion
    readonly property real labelY: contentRow.y + labelText.y
    readonly property real shadowY: shadowRow.y + labelShadow.y

    // Component aliases for testing & styling
    readonly property alias topGlareItem: topGlare
    readonly property alias bottomRimItem: bottomRim
    readonly property alias labelItem: labelText
    readonly property alias textShadowItem: labelShadow
    readonly property alias shadowRowItem: shadowRow
    readonly property alias contactShadowItem: contactShadow
    readonly property alias iconItem: buttonIcon
    readonly property alias contentRowItem: contentRow

    // Spring Micro-Physics & Target Scale
    readonly property real targetScale: root.interactive ? (root.pressed ? 0.96 : (root.hovered ? 1.02 : 1.0)) : 1.0
    scale: targetScale

    Behavior on scale {
        NumberAnimation {
            duration: root.pressed ? 120 : 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveGlassElastic) ? Theme.curveGlassElastic : [0.34, 1.56, 0.64, 1]
        }
    }

    // 0. Ambient Contact Drop Shadow (Physical surface separation)
    Rectangle {
        id: contactShadow
        visible: true
        z: -1
        anchors.fill: glassBody
        anchors.topMargin: Math.max(2, Math.round(root.elevation * 0.4))
        anchors.bottomMargin: -Math.max(2, Math.round(root.elevation * 0.5))
        anchors.leftMargin: -Math.max(1, Math.round(root.elevation * 0.15))
        anchors.rightMargin: -Math.max(1, Math.round(root.elevation * 0.15))
        radius: root.radius
        color: "transparent"
        border.color: (typeof Colors !== "undefined" && Colors.isDarkMode)
            ? Qt.rgba(0.0, 0.0, 0.0, 0.35)
            : Qt.rgba(0.0, 0.0, 0.0, 0.14)
        border.width: Math.max(2, Math.round(root.elevation * 0.5))
        opacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.40 : 0.25
    }

    // 1. Translucent Frosted Glass Body Capsule
    Rectangle {
        id: glassBody
        anchors.fill: parent
        radius: root.radius
        color: root.isPrimary
            ? Qt.tint((typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1.0, 1.0, 1.0, 0.15) : Qt.rgba(1.0, 1.0, 1.0, 0.55), Qt.alpha(root.accentColor, 0.25))
            : ((typeof Colors !== "undefined" && Colors.isDarkMode)
                ? (root.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.12) : Qt.rgba(1.0, 1.0, 1.0, 0.07))
                : (root.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.55) : Qt.rgba(1.0, 1.0, 1.0, 0.42)))

        border.color: (typeof Colors !== "undefined" && Colors.isDarkMode)
            ? (root.hovered ? Colors.glassBorderSpecular : Qt.rgba(1.0, 1.0, 1.0, 0.16))
            : (root.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.90) : Qt.rgba(1.0, 1.0, 1.0, 0.70))
        border.width: 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    // 2. Fresnel Refraction Cushion
    Rectangle {
        id: refractionCushion
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.12), Qt.alpha(root.accentColor, 0.08))
                    : Qt.rgba(1.0, 1.0, 1.0, 0.45)
            }
            GradientStop { position: 0.45; color: "transparent" }
            GradientStop { position: 0.85; color: "transparent" }
            GradientStop {
                position: 1.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.rgba(0.0, 0.0, 0.0, 0.08)
                    : Qt.rgba(1.0, 1.0, 1.0, 0.18)
            }
        }
    }

    // 3. Dual-Layer Specular Hairline Glare (Horizontal light catch along flat top edge)
    // NOTE: Must strictly stay within [radius, width - radius] to eliminate detached overhang lines!
    Rectangle {
        id: topGlare
        visible: parent.width > (root.radius * 2 + 8)
        anchors.top: parent.top
        anchors.topMargin: 0.5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(root.radius + 2, 16)
        anchors.rightMargin: Math.max(root.radius + 2, 16)
        height: 1
        opacity: root.hovered ? 1.0 : ((typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.75 : 0.88)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.20; color: Qt.rgba(1.0, 1.0, 1.0, 0.60) }
            GradientStop { position: 0.50; color: "#FFFFFF" }
            GradientStop { position: 0.80; color: Qt.rgba(1.0, 1.0, 1.0, 0.60) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // 4. Bottom Caustic Reflection Rim
    Rectangle {
        id: bottomRim
        visible: parent.width > (root.radius * 2 + 8)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0.5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(root.radius + 2, 16)
        anchors.rightMargin: Math.max(root.radius + 2, 16)
        height: 1
        opacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.30 : 0.45

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.50; color: Qt.rgba(1.0, 1.0, 1.0, 0.50) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // 5. Floating Content with 3D Depth Shadow
    Row {
        id: shadowRow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 2.5
        spacing: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 6
        opacity: 0.80

        MaterialIcon {
            visible: root.iconText !== "" || root.iconName !== ""
            text: root.iconText
            iconName: root.iconName
            size: root.iconSize
            color: root.textShadowColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: labelShadow
            visible: root.text !== ""
            text: root.text
            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyLarge) ? Theme.fontBodyLarge : 14
            font.weight: Font.DemiBold
            color: root.textShadowColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 6

        MaterialIcon {
            id: buttonIcon
            visible: root.iconText !== "" || root.iconName !== ""
            text: root.iconText
            iconName: root.iconName
            size: root.iconSize
            color: root.isPrimary ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : root.accentColor) : root.textColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: labelText
            visible: root.text !== ""
            text: root.text
            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyLarge) ? Theme.fontBodyLarge : 14
            font.weight: Font.DemiBold
            color: root.isPrimary ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : root.accentColor) : root.textColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // 6. Interactive MouseArea
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered = true
        onExited: {
            root.hovered = false
            root.pressed = false
        }
        onPressed: root.pressed = true
        onReleased: root.pressed = false
        onCanceled: {
            root.hovered = false
            root.pressed = false
        }
        onClicked: root.clicked()
    }
}
