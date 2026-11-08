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
        const prim = (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb";
        const isDark = (typeof Colors !== "undefined" && Colors.isDarkMode !== undefined) ? Colors.isDarkMode : true;
        switch (root.variant) {
            case "primary":
                return isHovered ? Qt.lighter(prim, 1.1) : prim;
            case "active":
                return isDark
                    ? Qt.tint(Qt.rgba(0, 0, 0, 0.35), Qt.alpha(prim, isHovered ? 0.30 : 0.20))
                    : (isHovered ? Qt.alpha(prim, 0.25) : Qt.alpha(prim, 0.15));
            case "info":
                return isDark
                    ? Qt.tint(Qt.rgba(0, 0, 0, 0.35), Qt.alpha("#3B82F6", isHovered ? 0.30 : 0.20))
                    : (isHovered ? Qt.alpha("#3B82F6", 0.25) : Qt.alpha("#3B82F6", 0.12));
            case "danger":
                return isHovered ? Qt.alpha("#EF4444", 0.25) : Qt.alpha("#EF4444", 0.12);
            case "ghost":
                return isHovered ? Qt.alpha(prim, 0.12) : "transparent";
            case "secondary":
            default:
                if (typeof Colors !== "undefined") {
                    return isHovered ? (Colors.surfaceContainerHighest || Qt.rgba(1, 1, 1, 0.12)) : (Colors.surfaceContainerHigh || Qt.rgba(1, 1, 1, 0.08));
                }
                return isHovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.08);
        }
    }

    readonly property color effectiveBorderColor: {
        const prim = (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb";
        switch (root.variant) {
            case "primary":
                return prim;
            case "active":
                return isHovered ? prim : Qt.alpha(prim, 0.35);
            case "info":
                return isHovered ? "#3B82F6" : Qt.alpha("#3B82F6", 0.35);
            case "danger":
                return isHovered ? "#EF4444" : Qt.alpha("#EF4444", 0.35);
            case "ghost":
                return isHovered ? prim : "transparent";
            case "secondary":
            default:
                return isHovered ? prim : ((typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : Qt.rgba(1, 1, 1, 0.1));
        }
    }

    readonly property color effectiveTextColor: {
        const prim = (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb";
        switch (root.variant) {
            case "primary":
                return (typeof Colors !== "undefined" && Colors.textOnPrimary) ? Colors.textOnPrimary : "#000000";
            case "active":
                return prim;
            case "info":
                return "#3B82F6";
            case "danger":
                return "#EF4444";
            case "ghost":
                return isHovered ? prim : ((typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0");
            case "secondary":
            default:
                return isHovered ? prim : ((typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF");
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
            style: (root.variant !== "primary") ? Text.Outline : Text.Normal
            styleColor: (typeof Colors !== "undefined" && Colors.glassTextHalo) ? Colors.glassTextHalo : Qt.rgba(0, 0, 0, 0.62)
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
