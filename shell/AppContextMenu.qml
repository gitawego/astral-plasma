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

    function show(app, globalY) {
        menuCard.targetApp = app;
        menuCard.targetGlobalY = globalY;
        menuCard.visible = true;
    }

    function hide() {
        menuCard.visible = false;
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

        property var targetApp: null
        property real targetGlobalY: 0

        x: root.dockW + 10
        y: Math.max(12, Math.min(root.screenH - height - 12, targetGlobalY - 10))
        width: 220

        Behavior on y {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        MenuHeader {
            title: menuCard.targetApp ? menuCard.targetApp.appName : ""
            subtitle: {
                if (!menuCard.targetApp) return "";
                if (menuCard.targetApp.isPinned && menuCard.targetApp.isRunning) return "Pinned • Running";
                if (menuCard.targetApp.isPinned) return "Pinned";
                return "Running (Unpinned)";
            }
            iconSource: {
                if (!menuCard.targetApp || !menuCard.targetApp.iconName) return "";
                if (menuCard.targetApp.iconName.indexOf("/") !== -1) {
                    return menuCard.targetApp.iconName.startsWith("file://") ? menuCard.targetApp.iconName : ("file://" + menuCard.targetApp.iconName);
                }
                return Quickshell.iconPath(menuCard.targetApp.iconName);
            }
            materialIcon: menuCard.targetApp ? (menuCard.targetApp.materialIcon || "apps") : "apps"
        }

        MenuDivider {}

        MenuItem {
            text: (menuCard.targetApp && menuCard.targetApp.isPinned) ? "Unpin from dock" : "Pin to dock"
            materialIcon: (menuCard.targetApp && menuCard.targetApp.isPinned) ? "keep_off" : "push_pin"
            checked: menuCard.targetApp && menuCard.targetApp.isPinned
            onClicked: {
                if (!menuCard.targetApp) return;
                if (menuCard.targetApp.isPinned) {
                    Config.unpinApp(menuCard.targetApp.appId, menuCard.targetApp.desktopFile, menuCard.targetApp.appName);
                } else {
                    Config.pinApp(menuCard.targetApp);
                }
                root.hide();
            }
        }

        MenuItem {
            visible: menuCard.targetApp && menuCard.targetApp.isRunning
            text: "Close window"
            materialIcon: "close"
            isDangerous: true
            onClicked: {
                if (menuCard.targetApp && menuCard.targetApp.id) {
                    WindowService.closeWindow(menuCard.targetApp.id);
                }
                root.hide();
            }
        }

        MenuItem {
            visible: menuCard.targetApp && !menuCard.targetApp.isRunning
            text: "Launch application"
            materialIcon: "play_arrow"
            onClicked: {
                if (menuCard.targetApp) {
                    WindowService.launchApp(menuCard.targetApp.desktopFile || menuCard.targetApp.appId);
                }
                root.hide();
            }
        }
    }
}
