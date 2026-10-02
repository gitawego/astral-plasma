import QtQuick
import QtQuick.Layouts
import "../theme"

Rectangle {
    id: toggleItemRoot

    property string icon: ""
    property string iconSource: ""
    property color iconColor: Colors.textOnSurface
    property string label: ""
    property bool checked: false
    property bool enabled: true
    signal toggled()

    /// Test / introspection surface: the rendered glyph, whose colour follows
    /// `iconColor` (the offscreen harness cannot load the theme singletons, so the
    /// plumbing is asserted through this item and the token binding in the
    /// popout's own source).
    property alias iconItem: toggleIcon

    Layout.fillWidth: true
    implicitHeight: 30
    radius: Theme.radiusSmall
    color: "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.padSmall
        anchors.rightMargin: Theme.padSmall
        spacing: Theme.spaceSmall

        ThemedIcon {
            id: toggleIcon
            Layout.preferredWidth: (toggleItemRoot.iconSource !== "" || toggleItemRoot.icon !== "") ? 18 : 0
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignVCenter
            visible: toggleItemRoot.iconSource !== "" || toggleItemRoot.icon !== ""
            source: toggleItemRoot.iconSource
            materialIcon: toggleItemRoot.icon
            color: toggleItemRoot.iconColor
            size: 16
        }

        Text {
            id: labelText
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: toggleItemRoot.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSmall
            color: toggleItemRoot.enabled ? Colors.textOnSurface : Colors.textOnSurfaceVariant
            elide: Text.ElideRight
        }

        // Material 3 Switch Pill
        Rectangle {
            id: switchTrack
            Layout.preferredWidth: 36
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            radius: 10
            color: toggleItemRoot.checked 
                ? (switchMouse.containsMouse ? Qt.lighter(Colors.primary, 1.1) : Colors.primary)
                : (switchMouse.containsMouse ? (Colors.surfaceContainerHigh || Qt.rgba(1, 1, 1, 0.18)) : (Colors.surfaceContainerHighest || Qt.rgba(1, 1, 1, 0.12)))
            border.color: toggleItemRoot.checked ? Colors.primary : (Theme.borderSubtle || Qt.rgba(1, 1, 1, 0.2))
            border.width: 1

            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            Behavior on border.color {
                ColorAnimation { duration: 150 }
            }

            Rectangle {
                id: switchThumb
                anchors.verticalCenter: parent.verticalCenter
                x: toggleItemRoot.checked ? parent.width - width - 3 : 3
                width: 14
                height: 14
                radius: 7
                color: toggleItemRoot.checked 
                    ? (Colors.onPrimary || Colors.textOnPrimary || "#000000") 
                    : (Colors.outline || Colors.textOnSurfaceVariant)

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.animDurationFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }
                }
            }

            MouseArea {
                id: switchMouse
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: toggleItemRoot.enabled
                cursorShape: toggleItemRoot.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: {
                    if (typeof Config !== "undefined" && Config.keepBottomPopout) {
                        Config.keepBottomPopout();
                    }
                }
                onClicked: {
                    if (toggleItemRoot.enabled) {
                        toggleItemRoot.toggled();
                    }
                }
            }
        }
    }
}
