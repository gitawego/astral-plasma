import QtQuick
import "../theme"

Rectangle {
    id: root

    // Content
    property string text: ""
    property string icon: ""
    property string iconName: ""
    property int iconSize: 11
    property int fontPixelSize: 9
    property int fontWeight: Font.DemiBold
    property string fontFamily: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"

    // Behavior & Interaction
    property bool interactive: true
    signal clicked()

    // Variants: "primary", "secondary", "active", "info", "danger", "ghost"
    property string variant: "secondary"

    // Geometry & Sizing
    property real fixedWidth: 0
    property real fixedHeight: 20
    property int paddingHorizontal: 8
    property int spacing: 4
    property bool pill: false // If true, radius = height / 2

    radius: pill ? Math.round(height / 2) : 4
    height: fixedHeight
    implicitHeight: fixedHeight
    implicitWidth: fixedWidth > 0 ? fixedWidth : Math.max(16, contentRow.implicitWidth + paddingHorizontal * 2)

    readonly property bool isHovered: interactive && mouseArea.containsMouse
    readonly property bool isPressed: interactive && mouseArea.pressed

    // Effective Colors based on variant & state
    readonly property color effectiveBgColor: {
        switch (root.variant) {
            case "primary":
                return isHovered ? Qt.lighter(Colors.primary, 1.1) : Colors.primary;
            case "active":
                return isHovered ? Qt.alpha(Colors.primary, 0.25) : Qt.alpha(Colors.primary, 0.15);
            case "info":
                return isHovered ? Qt.alpha("#3B82F6", 0.25) : Qt.alpha("#3B82F6", 0.12);
            case "danger":
                return isHovered ? Qt.alpha("#EF4444", 0.25) : Qt.alpha("#EF4444", 0.12);
            case "ghost":
                return isHovered ? Qt.alpha(Colors.primary, 0.12) : "transparent";
            case "secondary":
            default:
                return isHovered ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh;
        }
    }

    readonly property color effectiveBorderColor: {
        switch (root.variant) {
            case "primary":
                return Colors.primary;
            case "active":
                return isHovered ? Colors.primary : Qt.alpha(Colors.primary, 0.35);
            case "info":
                return isHovered ? "#3B82F6" : Qt.alpha("#3B82F6", 0.35);
            case "danger":
                return isHovered ? "#EF4444" : Qt.alpha("#EF4444", 0.35);
            case "ghost":
                return isHovered ? Colors.primary : "transparent";
            case "secondary":
            default:
                return isHovered ? Colors.primary : Theme.borderSubtle;
        }
    }

    readonly property color effectiveTextColor: {
        switch (root.variant) {
            case "primary":
                return Colors.textOnPrimary;
            case "active":
                return Colors.primary;
            case "info":
                return "#3B82F6";
            case "danger":
                return "#EF4444";
            case "ghost":
                return isHovered ? Colors.primary : Colors.m3onSurfaceVariant;
            case "secondary":
            default:
                return isHovered ? Colors.primary : Colors.m3onSurface;
        }
    }

    color: effectiveBgColor
    border.color: effectiveBorderColor
    border.width: 1

    scale: isPressed ? 0.95 : 1.0

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
    Behavior on scale {
        NumberAnimation {
            duration: 120
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveGlassElastic) ? Theme.curveGlassElastic : [0.34, 1.56, 0.64, 1]
        }
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: (iconItem.visible && labelItem.visible) ? root.spacing : 0

        MaterialIcon {
            id: iconItem
            visible: (root.icon !== "" || root.iconName !== "")
            text: root.icon
            iconName: root.iconName
            size: root.iconSize
            color: root.effectiveTextColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: labelItem
            visible: root.text !== ""
            text: root.text
            font.family: root.fontFamily
            font.pixelSize: root.fontPixelSize
            font.weight: root.fontWeight
            color: root.effectiveTextColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: (mouse) => {
            mouse.accepted = true;
            root.clicked();
        }
    }
}
