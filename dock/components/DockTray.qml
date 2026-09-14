import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"
import "../../components"
import "../../config"

Item {
    id: root

    readonly property bool enabledInConfig: Config.settings.dock && Config.settings.dock.tray ? Config.settings.dock.tray.enabled : true
    readonly property var trayItems: SystemTray.items.values

    visible: enabledInConfig && trayItems.length > 0
    implicitWidth: 40
    implicitHeight: columnLayout.implicitHeight

    Column {
        id: columnLayout
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.spaceSmall

        Repeater {
            model: root.trayItems

            delegate: Item {
                implicitWidth: 32
                implicitHeight: 32

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSmall
                    color: trayMouseArea.containsMouse ? Colors.pillHover : "transparent"

                    Image {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        source: modelData.icon || ""
                        fillMode: Image.PreserveAspectFit
                    }

                    MouseArea {
                        id: trayMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (modelData.hasMenu) {
                                    modelData.openMenu();
                                }
                            } else {
                                modelData.activate();
                            }
                        }
                    }
                }
            }
        }
    }
}
