import QtQuick
import qs.theme
import qs.config
import qs.components

Item {
    id: root

    implicitWidth: 44
    implicitHeight: layout.implicitHeight + Theme.padSmall * 2

    property string hour: "12"
    property string minute: "00"
    property string day: "Sat"
    property string dateNum: "1"

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date();
            root.hour = Qt.formatDateTime(now, "HH");
            root.minute = Qt.formatDateTime(now, "mm");
            root.day = Qt.formatDateTime(now, "ddd");
            root.dateNum = Qt.formatDateTime(now, "d");
        }
    }

    Column {
        id: layout
        anchors.centerIn: parent
        spacing: 2

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "calendar_month"
            size: 16
            color: Colors.m3onSurfaceVariant
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.hour
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontTitleSmall
            font.weight: Font.DemiBold
            color: Colors.m3onSurface
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "•••"
            font.family: Theme.fontFamily
            font.pixelSize: 8
            color: Colors.primary
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.minute
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontTitleSmall
            font.weight: Font.DemiBold
            color: Colors.m3onSurface
        }

        Item { width: 1; height: 4 }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.day + ", " + root.dateNum
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontLabelSmall
            color: Colors.m3onSurfaceVariant
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Config.toggleDashboard()
    }
}
