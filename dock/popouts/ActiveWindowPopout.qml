import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Card {
    id: root

    width: 320
    height: 180
    radius: Theme.radiusLarge

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: Theme.spaceMedium

        // Header: App icon + title + app ID
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceMedium

            Rectangle {
                width: 40
                height: 40
                radius: Theme.radiusSmall
                color: Colors.primaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: WindowService.appId
                    text: "desktop"
                    size: 24
                    color: Colors.primary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: WindowService.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    text: WindowService.appId ? WindowService.appId : "Desktop"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                }
            }
        }

        // Window Details / Controls Card
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusMedium
            color: Colors.surfaceContainer

            RowLayout {
                anchors.centerIn: parent
                spacing: Theme.spaceLarge

                PillButton {
                    label: "Focus"
                    iconText: "search"
                    onClicked: {
                        if (WindowService.activeWindow) WindowService.activeWindow.activate();
                    }
                }

                PillButton {
                    label: "Maximize"
                    iconText: "dashboard"
                    onClicked: {
                        if (WindowService.activeWindow) {
                            WindowService.activeWindow.maximized = !WindowService.activeWindow.maximized;
                        }
                    }
                }

                PillButton {
                    label: "Close"
                    iconText: "close"
                    activeColor: Qt.rgba(0.9, 0.2, 0.2, 0.15)
                    onClicked: {
                        if (WindowService.activeWindow) WindowService.activeWindow.close();
                    }
                }
            }
        }
    }
}
