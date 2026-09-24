import QtQuick
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    readonly property string displayTitle: WindowService.title
    readonly property bool hasWindow: WindowService.activeWindow !== null

    implicitWidth: 44
    implicitHeight: Math.min(220, Math.max(60, titleText.implicitWidth + 36))

    Column {
        anchors.centerIn: parent
        spacing: Theme.spaceSmall

        // App Icon
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 18
            height: 18

            Image {
                id: activeIconImg
                anchors.centerIn: parent
                width: 18
                height: 18
                source: Config.iconUrl(WindowService.appId)
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }

            MaterialIcon {
                anchors.centerIn: parent
                iconName: activeIconImg.visible ? "" : (WindowService.appId ? WindowService.appId : "")
                text: WindowService.materialIcon || "desktop_windows"
                size: 18
                color: Colors.primary
                visible: !activeIconImg.visible || activeIconImg.status !== Image.Ready
            }
        }

        // Rotated Vertical Title matching Screenshot 2 & 3
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 20
            height: titleText.implicitWidth

            Text {
                id: titleText
                anchors.centerIn: parent
                text: root.displayTitle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodySmall
                color: Colors.m3onSurfaceVariant
                rotation: 90
                elide: Text.ElideRight
                width: 160
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Config.togglePopout("activewindow")
    }
}
