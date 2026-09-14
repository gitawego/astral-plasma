import QtQuick
import "../theme"
import "../components"

Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property string iconSource: ""
    property string materialIcon: "apps"

    width: parent ? parent.width : 200
    implicitHeight: 36

    Row {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 10

        Item {
            width: 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.fill: parent
                source: root.iconSource
                fillMode: Image.PreserveAspectFit
                visible: root.iconSource !== "" && status === Image.Ready
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: root.materialIcon
                size: 18
                visible: root.materialIcon !== "" && (!parent.children[0] || !parent.children[0].visible)
                color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#d0bcff"
            }
        }

        Column {
            width: parent.width - 30
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                text: root.title
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: (typeof Colors !== "undefined" && Colors.textOnSurface) ? Colors.textOnSurface : "#e6e1e6"
                elide: Text.ElideRight
                width: parent.width
            }

            Text {
                text: root.subtitle
                visible: root.subtitle !== ""
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: 10
                color: (typeof Colors !== "undefined" && Colors.textMuted) ? Colors.textMuted : "#948f99"
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }
}
