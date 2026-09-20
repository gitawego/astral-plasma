import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"

Item {
    id: root

    implicitWidth: 680
    implicitHeight: 320

    readonly property bool usesLiquidGlassCards: true

    Item {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: (typeof Theme !== "undefined" && Theme.padExtraLarge) ? Theme.padExtraLarge : 20
            spacing: (typeof Theme !== "undefined" && Theme.spaceLarge) ? Theme.spaceLarge : 16

            Text {
                text: "Virtual Desktops (KWin)"
                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 16
                font.weight: Font.DemiBold
                color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
            }

            GridView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                cellWidth: 150
                cellHeight: 100
                clip: true

                model: (typeof KWinWorkspaces !== "undefined" && KWinWorkspaces.desktops) ? KWinWorkspaces.desktops : []

                delegate: LiquidGlassCard {
                    width: 140
                    height: 90
                    radius: (typeof Theme !== "undefined" && Theme.radiusLarge) ? Theme.radiusLarge : 14
                    interactive: true
                    selected: Boolean(modelData.active)
                    hovered: wsMouse.containsMouse
                    elevation: modelData.active ? 8 : 4

                    Column {
                        anchors.centerIn: parent
                        spacing: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 6

                        MaterialIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "workspaces"
                            size: 26
                            color: modelData.active 
                                ? ((typeof Colors !== "undefined" && Colors.m3onPrimaryContainer) ? Colors.m3onPrimaryContainer : Colors.primary)
                                : ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.name || ("Desktop " + (modelData.index + 1))
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 13
                            font.weight: modelData.active ? Font.Bold : Font.Normal
                            color: modelData.active 
                            style: Text.Outline
                            styleColor: Colors.glassTextHalo
                                ? ((typeof Colors !== "undefined" && Colors.m3onPrimaryContainer) ? Colors.m3onPrimaryContainer : "#FFFFFF")
                                : ((typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF")
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
