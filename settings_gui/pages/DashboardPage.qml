import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"

ColumnLayout {
    id: root

    spacing: Theme.spaceMedium

    Text {
        text: "Dashboard & Widgets"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTitleMedium
        font.weight: Font.Bold
        color: Colors.m3onSurface
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "Central Popout Dashboard"
        description: "Enable the top-center modal overlay (toggled via dock clock or shortcut)"
        checked: Config.settings.dashboard ? (Config.settings.dashboard.enabled ?? true) : true
        onToggled: val => Config.setDashboardEnabled(val)
    }

    Repeater {
        model: Config.settings.dashboard && Config.settings.dashboard.tabs ? Config.settings.dashboard.tabs : []

        delegate: SettingToggle {
            Layout.fillWidth: true
            title: modelData.label + " Tab"
            description: "Show " + modelData.label + " tab inside the Central Dashboard"
            checked: modelData.enabled
            onToggled: val => Config.setDashboardTabEnabled(modelData.id, val)
        }
    }

    // Media Tab Avatar setting card
    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        implicitHeight: avatarCol.implicitHeight + Theme.padLarge * 2

        ColumnLayout {
            id: avatarCol
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                Column {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Media Tab Avatar"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        font.weight: Font.DemiBold
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: "Custom avatar file path (supports GIF, SVG, PNG, JPG, and video formats)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                Rectangle {
                    width: 70
                    height: 28
                    radius: Theme.radiusSmall
                    color: Colors.surfaceContainerHigh
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Reset"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.primary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            avatarInput.text = "";
                            Config.setMediaAvatar("");
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 34
                radius: Theme.radiusSmall
                color: Colors.surfaceContainerLowest
                border.color: avatarInput.activeFocus ? Colors.primary : Theme.borderSubtle
                border.width: 1

                TextInput {
                    id: avatarInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.m3onSurface
                    text: Config.mediaAvatar
                    clip: true

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Default (Boba Cat)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Colors.m3onSurfaceVariant
                        opacity: 0.5
                        visible: !avatarInput.text && !avatarInput.activeFocus
                    }

                    onAccepted: {
                        Config.setMediaAvatar(text.trim());
                    }
                    onEditingFinished: {
                        Config.setMediaAvatar(text.trim());
                    }
                }
            }
        }
    }
}
