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

    radius: Theme.radiusFull
    implicitWidth: label ? labelText.implicitWidth + (iconText ? icon.width + Theme.spaceMedium : 0) + Theme.padLarge * 2 : 40
    implicitHeight: 40

    color: active ? activeColor : (mouseArea.containsPress ? Colors.pillPress : (mouseArea.containsMouse ? Colors.pillHover : inactiveColor))

    border.color: active ? Qt.alpha(Colors.primary, 0.3) : "transparent"
    border.width: active ? 1 : 0

    scale: mouseArea.containsPress ? 0.95 : 1.0

    Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }
    Behavior on scale { NumberAnimation { duration: Theme.animDurationFast; easing.type: Theme.animEasing } }

    Row {
        anchors.centerIn: parent
        spacing: Theme.spaceSmall

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
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBodyMedium
            font.weight: root.active ? Font.DemiBold : Font.Normal
            color: root.active ? root.activeTextColor : root.inactiveTextColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
