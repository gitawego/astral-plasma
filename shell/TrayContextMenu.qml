import QtQuick
import Quickshell
import "../theme"
import "../config"
import "../components"
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
    property var submenuStack: []
    readonly property var currentItems: (submenuStack && submenuStack.length > 0) ? (submenuStack[submenuStack.length - 1].items || []) : root.menuItems
    readonly property string currentSubmenuTitle: (submenuStack && submenuStack.length > 0) ? (submenuStack[submenuStack.length - 1].title || "") : ""
    property var targetItem: null
    property bool isLoading: false

    function show(item, globalY) {
        console.log("TrayContextMenu.show() called! item=" + JSON.stringify(item) + " globalY=" + globalY);
        root.targetItem = item;
        root.submenuStack = [];
        menuCard.targetGlobalY = globalY;
        menuCard.visible = true;
        root.isLoading = true;
        root.menuItems = [];

        if (item && item.menuPath) {
            console.log("Fetching tray menu for " + item.service + " " + item.menuPath);
            WindowService.fetchTrayMenu(item.service, item.menuPath, (items) => {
                console.log("Tray menu received " + items.length + " items: " + JSON.stringify(items));
                root.isLoading = false;
                root.menuItems = items;
            });
        } else {
            console.log("Tray item has no menuPath!");
            root.isLoading = false;
            root.menuItems = [];
        }
    }

    function hide() {
        menuCard.visible = false;
        root.targetItem = null;
        root.menuItems = [];
        root.submenuStack = [];
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
        implicitWidth: 260

        Behavior on y {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        // Top-Level Header
        MenuHeader {
            visible: root.submenuStack.length === 0
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

        // Submenu Header
        Item {
            width: parent.width
            height: 36
            visible: root.submenuStack.length > 0

            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: backRow.implicitWidth + 12
                    height: 28
                    radius: Theme.radiusSmall
                    color: backHover.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh

                    Row {
                        id: backRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "arrow_back"
                            size: 16
                            color: Colors.primary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Back"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: Colors.textOnSurface
                        }
                    }

                    MouseArea {
                        id: backHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let s = root.submenuStack.slice(0);
                            s.pop();
                            root.submenuStack = s;
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - backRow.implicitWidth - 30
                    text: root.currentSubmenuTitle
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Colors.textOnSurface
                    elide: Text.ElideRight
                }
            }
        }

        MenuDivider {}

        Item {
            width: parent ? parent.width : 220
            height: 30
            visible: root.isLoading && root.submenuStack.length === 0

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
            visible: (!root.isLoading || root.submenuStack.length > 0) && root.currentItems.length === 0

            Text {
                anchors.centerIn: parent
                text: "No menu actions"
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Colors.textMuted
            }
        }

        Item {
            width: parent.width
            implicitHeight: Math.min(460, menuCol.implicitHeight)
            visible: root.currentItems.length > 0
            clip: true

            Flickable {
                id: menuFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: menuCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                interactive: contentHeight > height

                Column {
                    id: menuCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.currentItems

                        Item {
                            id: delegateItem
                            width: parent ? parent.width : 220
                            visible: modelData.isSeparator || (modelData.label !== undefined && modelData.label.trim() !== "")
                            height: visible ? (modelData.isSeparator ? 9 : 36) : 0

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
                                hasSubmenu: Boolean(modelData.hasSubmenu) || (Boolean(modelData.children) && modelData.children.length > 0)
                                toggleType: modelData.toggleType || ""
                                toggleState: (modelData.toggleState !== undefined) ? modelData.toggleState : 0
                                iconSource: {
                                    if (!modelData.icon) return "";
                                    if (modelData.icon.indexOf("/") !== -1) {
                                        return modelData.icon.startsWith("file://") ? modelData.icon : ("file://" + modelData.icon);
                                    }
                                    return Quickshell.iconPath(modelData.icon);
                                }
                                isDangerous: (modelData.label && modelData.label.toLowerCase().indexOf("quit") !== -1)
                                onClicked: {
                                    if (hasSubmenu && modelData.children && modelData.children.length > 0) {
                                        let s = root.submenuStack.slice(0);
                                        s.push({
                                            title: modelData.label || "Submenu",
                                            items: modelData.children
                                        });
                                        root.submenuStack = s;
                                        menuFlickable.contentY = 0;
                                    } else if (modelData.enabled !== false) {
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

                WheelHandler {
                    target: menuFlickable
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        menuFlickable.contentY = Math.max(0, Math.min(menuFlickable.contentHeight - menuFlickable.height, menuFlickable.contentY - event.angleDelta.y));
                    }
                }
            }
        }
    }
}
