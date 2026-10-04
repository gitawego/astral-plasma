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
    property int fontSize: 0
    property int minWidth: 100
    property bool showSpecular: (typeof Theme !== "undefined" && Theme.material) ? Theme.material.specularEnabled : true
    property bool showCaustic: (typeof Theme !== "undefined" && Theme.material) ? Theme.material.causticEnabled : true

    // Stadium Pill Geometry
    property int customRadius: -1
    readonly property int radius: customRadius >= 0 
        ? customRadius 
        : ((typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber")
            ? 0
            : (root.isCircular 
                ? Math.round(height / 2) 
                : ((typeof Theme !== "undefined" && Theme.radiusGlassPill !== undefined) 
                    ? Math.min(Theme.radiusGlassPill, Math.round(height / 2)) 
                    : Math.round(height / 2))))
    readonly property bool isCircular: root.text === "" && (Math.abs(root.width - root.height) <= 6)
    implicitHeight: 42
    implicitWidth: Math.max(minWidth, contentRow.implicitWidth + paddingHorizontal * 2)

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
    readonly property real targetScale: root.interactive ? (root.pressed ? (root.isCircular ? 0.92 : 0.96) : (root.hovered ? (root.isCircular ? 1.08 : 1.02) : 1.0)) : 1.0
    scale: targetScale

    Behavior on scale {
        NumberAnimation {
            duration: root.pressed ? 120 : 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveGlassElastic) ? Theme.curveGlassElastic : [0.34, 1.56, 0.64, 1]
        }
    }

    // 0. Ambient Contact Drop Shadow (Physical surface separation, fully translucent contour)
    Rectangle {
        id: contactShadow
        visible: (typeof Theme !== "undefined" && Theme.material) ? Theme.material.shadowsEnabled : true
        z: -1
        anchors.fill: glassBody
        anchors.topMargin: Math.max(2, Math.round(root.elevation * 0.35))
        anchors.bottomMargin: -Math.max(2, Math.round(root.elevation * 0.40))
        anchors.leftMargin: -Math.max(1, Math.round(root.elevation * 0.12))
        anchors.rightMargin: -Math.max(1, Math.round(root.elevation * 0.12))
        radius: root.radius
        color: "transparent"
        border.color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.0, 0.0, 0.0, 0.30) : Qt.rgba(0.0, 0.0, 0.0, 0.12)
        border.width: Math.max(1, Math.round(root.elevation * 0.25))
        opacity: root.hovered ? 0.45 : 0.25
    }

    // 1. Translucent Frosted Glass Body Capsule (Smooth, unified substrate)
    Rectangle {
        id: glassBody
        anchors.fill: parent
        radius: root.radius
        color: root.isPrimary
            ? (root.pressed 
                ? Qt.alpha(root.accentColor, 0.45) 
                : (root.hovered ? Qt.alpha(root.accentColor, 0.35) : Qt.alpha(root.accentColor, 0.24)))
            : ((typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber")
                ? (root.pressed ? Qt.alpha(Colors.primary, 0.30) : (root.hovered ? Qt.alpha(Colors.primary, 0.18) : Qt.rgba(0.04, 0.05, 0.08, 0.90)))
                : ((typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? (root.pressed ? Qt.rgba(1.0, 1.0, 1.0, 0.18) : (root.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.12) : Qt.rgba(1.0, 1.0, 1.0, 0.06)))
                    : (root.pressed ? Qt.rgba(1.0, 1.0, 1.0, 0.70) : (root.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.60) : Qt.rgba(1.0, 1.0, 1.0, 0.42)))))

        border.color: root.isPrimary
            ? (root.hovered ? Qt.alpha(root.accentColor, 0.90) : Qt.alpha(root.accentColor, 0.55))
            : ((typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber")
                ? (root.hovered ? Colors.primary : Qt.alpha(Colors.primary, 0.60))
                : ((typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? (root.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.32) : Qt.rgba(1.0, 1.0, 1.0, 0.12))
                    : (root.hovered ? Qt.rgba(1.0, 1.0, 1.0, 0.85) : Qt.rgba(1.0, 1.0, 1.0, 0.55))))
        border.width: (typeof Theme !== "undefined" && Theme.glassBorderWidth) ? Theme.glassBorderWidth : 1

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    // 2. Fresnel Refraction Cushion (Soft continuous vertical depth sheen)
    Rectangle {
        id: refractionCushion
        visible: (typeof Theme !== "undefined" && Theme.material) ? Theme.material.specularEnabled : true
        anchors.fill: parent
        radius: root.radius
        color: "transparent"

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.rgba(1.0, 1.0, 1.0, root.hovered ? 0.14 : 0.08)
                    : Qt.rgba(1.0, 1.0, 1.0, 0.35)
            }
            GradientStop { position: 0.50; color: "transparent" }
            GradientStop {
                position: 1.0
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.rgba(0.0, 0.0, 0.0, 0.06)
                    : Qt.rgba(0.0, 0.0, 0.0, 0.04)
            }
        }
    }

    // 3. Specular Hairline Glare (Horizontal light catch along flat top edge for pills)
    Rectangle {
        id: topGlare
        visible: root.showSpecular && !root.isCircular && (parent.width > (root.radius * 2 + 8))
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

    // 4. Bottom Reflection Rim (For stadium pills)
    Rectangle {
        id: bottomRim
        visible: root.showSpecular && !root.isCircular && (parent.width > (root.radius * 2 + 8))
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
        anchors.verticalCenterOffset: 1.5
        spacing: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 6
        opacity: (root.isCircular || root.text === "") ? 0.0 : 0.60

        MaterialIcon {
            visible: !root.isCircular && (root.iconText !== "" || root.iconName !== "")
            text: root.iconText
            iconName: root.iconName
            size: root.iconSize
            color: root.textShadowColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: labelShadow
            visible: root.text !== "" && ((typeof Theme !== "undefined" && Theme.material) ? Theme.material.shadowsEnabled : true)
            text: root.text
            font.family: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber" && Theme.fontMonospace)
                ? Theme.fontMonospace
                : ((typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif")
            font.pixelSize: root.fontSize > 0 ? root.fontSize : ((typeof Theme !== "undefined" && Theme.fontBodyLarge) ? Theme.fontBodyLarge : 14)
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
            color: root.isPrimary 
                ? "#FFFFFF" 
                : (root.hovered ? "#FFFFFF" : ((typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : root.textColor))
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: labelText
            visible: root.text !== ""
            text: root.text
            font.family: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber" && Theme.fontMonospace)
                ? Theme.fontMonospace
                : ((typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif")
            font.pixelSize: root.fontSize > 0 ? root.fontSize : ((typeof Theme !== "undefined" && Theme.fontBodyLarge) ? Theme.fontBodyLarge : 14)
            font.weight: Font.DemiBold
            color: root.isPrimary ? "#FFFFFF" : root.textColor
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
