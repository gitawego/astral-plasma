import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"
import "../config"
import "../services"
import "../dock/components"

Item {
    id: root

    // "widget" = compact capsule widget embedded in existing Omarchy bar
    // "complete" = full desktop bar providing launcher, active window, clock, and status
    property string mode: (Config.settings.omarchy && Config.settings.omarchy.barMode)
        ? Config.settings.omarchy.barMode
        : ((parent && parent.width > 300) ? "complete" : "widget")

    implicitWidth: mode === "complete" ? (parent ? parent.width : 400) : 180
    implicitHeight: parent ? parent.height : 48

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacingSmall

        DockLauncher {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            Layout.alignment: Qt.AlignVCenter
        }

        ActiveWindow {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.alignment: Qt.AlignVCenter
        }

        DockClock {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 36
            Layout.alignment: Qt.AlignVCenter
        }

        DockStatusIcons {
            visible: root.mode === "complete"
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
