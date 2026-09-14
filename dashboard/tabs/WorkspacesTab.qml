import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    implicitWidth: 680
    implicitHeight: 320

    Item {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padExtraLarge
            spacing: Theme.spaceLarge

            Text {
                text: "Virtual Desktops (KWin)"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleMedium
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
            }

            GridView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                cellWidth: 150
                cellHeight: 100
                clip: true

                model: (typeof KWinWorkspaces !== "undefined" && KWinWorkspaces.desktops) ? KWinWorkspaces.desktops : []

                delegate: Rectangle {
                    width: 140
                    height: 90
                    radius: Theme.radiusLarge
                    color: modelData.active ? Colors.primaryContainer : (wsMouse.containsMouse ? Colors.pillHover : Colors.surfaceContainer)
                    border.color: modelData.active ? Colors.primary : Theme.borderSubtle
                    border.width: modelData.active ? 2 : 1

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spaceSmall

                        MaterialIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "workspaces"
                            size: 26
                            color: modelData.active ? Colors.m3onPrimaryContainer : Colors.primary
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.name || ("Desktop " + (modelData.index + 1))
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBodyMedium
                            font.weight: modelData.active ? Font.Bold : Font.Normal
                            color: modelData.active ? Colors.m3onPrimaryContainer : Colors.m3onSurface
                        }
                    }

                    MouseArea {
                        id: wsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof KWinWorkspaces !== "undefined") {
                                KWinWorkspaces.switchTo(modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        if (typeof KWinWorkspaces !== "undefined") {
            KWinWorkspaces.refresh();
        }
    }
}
