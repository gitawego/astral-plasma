import QtQuick
import Quickshell
import "../theme"
import "../config"
import "../menus"
import "../services"

Item {
    id: root
    anchors.fill: parent
    z: 9998
    visible: menuCard.visible

    property real dockW: Config.dockWidth + 6
    property real screenH: parent.height

    property var menuItems: []
    property var targetItem: null
    property bool isLoading: false

    function show(item, globalY) {
        root.targetItem = item;
        menuCard.targetGlobalY = globalY;
        menuCard.visible = true;
        root.isLoading = true;
        root.menuItems = [];

        if (item && item.menuPath) {
            WindowService.fetchTrayMenu(item.service, item.menuPath, (items) => {
                root.isLoading = false;
                root.menuItems = items;
            });
        } else {
            root.isLoading = false;
            root.menuItems = [];
        }
    }

    function hide() {
        menuCard.visible = false;
        root.targetItem = null;
        root.menuItems = [];
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.hide()
    }

    MenuCard {
        id: menuCard
        visible: false
        z: 9999

        property real targetGlobalY: 0

        x: root.dockW + 10
        y: Math.max(12, Math.min(root.screenH - height - 12, targetGlobalY - 10))
        implicitWidth: 240

        Behavior on y {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        MenuHeader {
            title: root.targetItem ? (root.targetItem.title || root.targetItem.id) : ""
            subtitle: (root.targetItem && root.targetItem.service) ? root.targetItem.service : "System Tray"
            iconSource: {
                if (!root.targetItem || !root.targetItem.rawIcon) return "";
                if (root.targetItem.rawIcon.indexOf("/") !== -1) {
                    return root.targetItem.rawIcon.startsWith("file://") ? root.targetItem.rawIcon : ("file://" + root.targetItem.rawIcon);
                }
                return Quickshell.iconPath(root.targetItem.rawIcon);
            }
            materialIcon: root.targetItem ? (root.targetItem.materialIcon || "widgets") : "widgets"
        }

        MenuDivider {}

        Item {
            width: parent ? parent.width : 220
            height: 30
            visible: root.isLoading

            Text {
                anchors.centerIn: parent
                text: "Loading menu..."
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Colors.textMuted
            }
        }

        Item {
            width: parent ? parent.width : 220
            height: 30
            visible: !root.isLoading && root.menuItems.length === 0

            Text {
                anchors.centerIn: parent
                text: "No menu actions"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Colors.textMuted
            }
        }

        Repeater {
            model: root.menuItems

            Item {
                id: delegateItem
                width: parent ? parent.width : 220
                visible: modelData.isSeparator || (modelData.label !== undefined && modelData.label.trim() !== "")
                height: visible ? (modelData.isSeparator ? 9 : 38) : 0

                MenuDivider {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: modelData.isSeparator
                }

                MenuItem {
                    anchors.fill: parent
                    visible: !modelData.isSeparator
                    text: modelData.label || ""
                    enabled: modelData.enabled !== false
                    iconSource: {
                        if (!modelData.icon) return "";
                        if (modelData.icon.indexOf("/") !== -1) {
                            return modelData.icon.startsWith("file://") ? modelData.icon : ("file://" + modelData.icon);
                        }
                        return Quickshell.iconPath(modelData.icon);
                    }
                    isDangerous: (modelData.label && modelData.label.toLowerCase().indexOf("quit") !== -1)
                    onClicked: {
                        if (root.targetItem && root.targetItem.menuPath) {
                            WindowService.triggerTrayMenuItem(root.targetItem.service, root.targetItem.menuPath, modelData.id);
                        }
                        root.hide();
                    }
                }
            }
        }
    }
}
