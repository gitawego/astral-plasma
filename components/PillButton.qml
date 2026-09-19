import QtQuick
import "../theme"

Rectangle {
    id: root

    signal clicked()

    property string iconText: ""
    property string iconName: ""
    property string label: ""
    property bool active: false
    property color activeColor: (typeof Colors !== 'undefined' && Colors.primaryContainer) ? Colors.primaryContainer : "#FFDBD1"
    property color activeTextColor: (typeof Colors !== 'undefined' && Colors.m3onPrimaryContainer) ? Colors.m3onPrimaryContainer : "#3B0900"
    property color inactiveColor: "transparent"
    property color inactiveTextColor: (typeof Colors !== 'undefined' && Colors.m3onSurface) ? Colors.m3onSurface : "#231917"
    property int iconSize: 18

    // Liquid Glass elevation & optics
    property bool showShadow: true
    property real elevation: 5

    // Sizing & Geometry
    radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : Math.round(height / 2)
    implicitWidth: label 
        ? labelText.implicitWidth + (iconText ? icon.width + ((typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 6) : 0) + ((typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16) * 2 
        : 40
    implicitHeight: 40

    // Component exposure aliases
    readonly property alias contactShadowItem: contactShadow
    readonly property alias topGlareItem: topGlare
    readonly property alias bottomRimItem: bottomRim
    readonly property alias labelItem: labelText
    readonly property alias textShadowItem: labelShadow
    readonly property alias iconItem: icon

    // Base Translucent Substrate Fill
    color: active 
        ? activeColor 
        : (mouseArea.containsPress 
            ? ((typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.60)) 
            : (mouseArea.containsMouse 
                ? ((typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.50)) 
                : (inactiveColor !== "transparent" 
                    ? inactiveColor 
                    : ((typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.35)))))

    border.color: active 
        ? ((typeof Colors !== "undefined" && Colors.primary) ? Qt.alpha(Colors.primary, 0.5) : "#9bcbfb") 
        : (mouseArea.containsMouse 
            ? ((typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.65)) 
            : ((typeof Colors !== "undefined" && Colors.glassBorderSubtle) ? Colors.glassBorderSubtle : Qt.rgba(1, 1, 1, 0.14)))
    border.width: active ? 1.2 : 1.0

    // Tactile Spring Micro-Physics
    scale: mouseArea.containsPress ? 0.95 : (mouseArea.containsMouse ? 1.02 : 1.0)

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }
    Behavior on scale { 
        NumberAnimation { 
            duration: mouseArea.containsPress ? 100 : 200 
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveGlassElastic) ? Theme.curveGlassElastic : [0.34, 1.56, 0.64, 1]
        } 
    }

    // 0. Ambient Contact Drop Shadow (Physical surface separation)
    Rectangle {
        id: contactShadow
        visible: root.showShadow
        z: -1
        anchors.fill: parent
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

    // 1. Refractive Optical Gradient
    Rectangle {
        id: refractionGradient
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        gradient: Gradient {
            GradientStop { 
                position: 0.0 
                color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.40) 
            }
            GradientStop { position: 0.50; color: "transparent" }
            GradientStop { 
                position: 1.0 
                color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.15) 
            }
        }
    }

    // 2. Dual Specular Hairline Glare (Horizontal light catch along flat top edge)
    // Anti-overhang: only visible when parent has flat top edge (width > radius * 2 + 8)
    Rectangle {
        id: topGlare
        visible: parent.width > (root.radius * 2 + 8)
        anchors.top: parent.top
        anchors.topMargin: 0.5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(root.radius + 2, 14)
        anchors.rightMargin: Math.max(root.radius + 2, 14)
        height: 1
        opacity: mouseArea.containsMouse ? 1.0 : ((typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.70 : 0.85)

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.20; color: Qt.rgba(1, 1, 1, 0.5) }
            GradientStop { position: 0.50; color: "#FFFFFF" }
            GradientStop { position: 0.80; color: Qt.rgba(1, 1, 1, 0.5) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // 3. Bottom Caustic Reflection Rim
    Rectangle {
        id: bottomRim
        visible: parent.width > (root.radius * 2 + 8)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0.5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Math.max(root.radius + 2, 14)
        anchors.rightMargin: Math.max(root.radius + 2, 14)
        height: 1
        opacity: (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.25 : 0.40

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0.45) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // 4. Floating Content with 3D Depth Shadow
    Row {
        id: shadowRow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 2.0
        spacing: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 6
        opacity: 0.70

        MaterialIcon {
            visible: root.iconText !== "" || root.iconName !== ""
            text: root.iconText
            iconName: root.iconName
            size: root.iconSize
            color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(0, 0, 0, 0.2)
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: labelShadow
            visible: root.label !== ""
            text: root.label
            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
            font.weight: root.active ? Font.DemiBold : Font.Normal
            color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(0, 0, 0, 0.2)
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 6

        MaterialIcon {
            id: icon
            visible: root.iconText !== "" || root.iconName !== ""
            text: root.iconText
            iconName: root.iconName
            size: root.iconSize
            color: root.active ? root.activeTextColor : root.inactiveTextColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: labelText
            visible: root.label !== ""
            text: root.label
            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
            font.weight: root.active ? Font.DemiBold : Font.Normal
            color: root.active ? root.activeTextColor : root.inactiveTextColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // 5. Interactive MouseArea
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
