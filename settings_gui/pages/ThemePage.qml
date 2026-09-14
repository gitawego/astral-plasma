import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"

ColumnLayout {
    id: root

    spacing: Theme.spaceMedium

    Text {
        text: "Theming & Appearance"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTitleMedium
        font.weight: Font.Bold
        color: Colors.m3onSurface
    }

    SettingToggle {
        Layout.fillWidth: true
        title: "Dynamic Material You Colors"
        description: "Extract soft pastel color palettes dynamically from your current wallpaper using matugen"
        checked: Config.settings.theme && Config.settings.theme.mode === "dynamic"
        onToggled: val => {
            if (!Config.settings.theme) Config.settings.theme = {};
            Config.settings.theme.mode = val ? "dynamic" : "preset";
            Config.saveSettings();
        }
    }

    SettingSlider {
        Layout.fillWidth: true
        title: "Corner Radius"
        min: 12
        max: 32
        suffix: "px"
        value: Config.settings.theme ? Config.settings.theme.cornerRadius : 20
        onValueModified: val => {
            Config.settings.theme.cornerRadius = Math.round(val);
            Config.saveSettings();
        }
    }

    // Colors Preview Pill
    Rectangle {
        Layout.fillWidth: true
        height: 60
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.padMedium

            Text {
                text: "Current Palette:"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                color: Colors.m3onSurface
                Layout.fillWidth: true
            }

            Rectangle { width: 32; height: 32; radius: 16; color: Colors.primary }
            Rectangle { width: 32; height: 32; radius: 16; color: Colors.primaryContainer }
            Rectangle { width: 32; height: 32; radius: 16; color: Colors.secondary }
            Rectangle { width: 32; height: 32; radius: 16; color: Colors.surfaceContainerHigh }
        }
    }
}
