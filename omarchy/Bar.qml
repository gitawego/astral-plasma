import QtQuick
import QtQuick.Layouts
import Quickshell
import "../theme"
import "../config"
import "../services"
import "../dock/components"

Item {
    id: root

    implicitWidth: 48
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
    }
}
