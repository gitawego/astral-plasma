import QtQuick
import "../theme"

Rectangle {
    id: root

    property var tabs: [] // Array of { id, label, icon }
    property string activeTab: "dashboard"
    signal tabSelected(string tabId)

    radius: Theme.radiusLarge
    color: "transparent"
    implicitHeight: 52

    Row {
        anchors.centerIn: parent
        spacing: Theme.spaceLarge

        Repeater {
            model: root.tabs

            delegate: Item {
                id: tabItem
                implicitWidth: contentRow.implicitWidth + Theme.padLarge * 2
                implicitHeight: 44

                readonly property bool isSelected: root.activeTab === modelData.id

                Row {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: Theme.spaceSmall

                    MaterialIcon {
                        text: modelData.icon || modelData.id
                        size: 18
                        color: tabItem.isSelected ? Colors.primary : Colors.m3onSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        font.weight: tabItem.isSelected ? Font.DemiBold : Font.Normal
                        color: tabItem.isSelected ? Colors.primary : Colors.m3onSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Bottom active indicator line
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: tabItem.isSelected ? parent.width : 0
                    height: 3
                    radius: Theme.radiusFull
                    color: Colors.primary
                    opacity: tabItem.isSelected ? 1.0 : 0.0

                    Behavior on width {
                        NumberAnimation { duration: Theme.animDurationNormal; easing.type: Theme.animEasing }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.animDurationNormal }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.activeTab = modelData.id;
                        root.tabSelected(modelData.id);
                    }
                }
            }
        }
    }
}
