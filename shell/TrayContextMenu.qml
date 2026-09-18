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

    readonly property real menuCardX: menuCard.x
    readonly property real menuCardY: menuCard.y
    readonly property real menuCardW: menuCard.width
    readonly property real menuCardH: menuCard.height
    readonly property bool menuCardVisible: menuCard.visible

    property var menuItems: []
    property var submenuStack: []
    property int activeLayer: 0
    property bool isTransitioning: false

    readonly property var currentItems: (submenuStack && submenuStack.length > 0) ? (submenuStack[submenuStack.length - 1].items || []) : root.menuItems
    readonly property string currentSubmenuTitle: (submenuStack && submenuStack.length > 0) ? (submenuStack[submenuStack.length - 1].title || "") : ""
    property var targetItem: null
    property bool isLoading: false

    function resetToRoot() {
        submenuStack = [];
        activeLayer = 0;
        isTransitioning = false;
        layerA.items = root.menuItems || [];
        layerA.resetScroll();
        layerA.x = 0;
        layerA.opacity = 1.0;
        layerA.visible = true;

        layerB.items = [];
        layerB.resetScroll();
        layerB.x = 35;
        layerB.opacity = 0.0;
        layerB.visible = false;
    }

    onMenuItemsChanged: {
        if (submenuStack.length === 0 && !isTransitioning) {
            if (activeLayer === 0) {
                layerA.items = root.menuItems || [];
            } else {
                layerB.items = root.menuItems || [];
            }
        }
    }

    function pushSubmenu(title, newItems) {
        if (isTransitioning) return;

        let stack = submenuStack.slice(0);
        stack.push({ title: title, items: newItems });
        submenuStack = stack;

        const targetLayer = (activeLayer === 0) ? 1 : 0;
        const outgoing = (activeLayer === 0) ? layerA : layerB;
        const incoming = (activeLayer === 0) ? layerB : layerA;

        incoming.items = newItems;
        incoming.resetScroll();
        incoming.x = 35;
        incoming.opacity = 0.0;
        incoming.visible = true;

        isTransitioning = true;
        pushOutX.target = outgoing;
        pushOutOp.target = outgoing;
        pushInX.target = incoming;
        pushInOp.target = incoming;
        slideAnimPush.outgoingRef = outgoing;
        slideAnimPush.targetLayerIndex = targetLayer;
        slideAnimPush.restart();
    }

    function popSubmenu() {
        if (isTransitioning || submenuStack.length === 0) return;

        let stack = submenuStack.slice(0);
        stack.pop();
        submenuStack = stack;

        const parentItems = (stack.length > 0) ? stack[stack.length - 1].items : (root.menuItems || []);
        const targetLayer = (activeLayer === 0) ? 1 : 0;
        const outgoing = (activeLayer === 0) ? layerA : layerB;
        const incoming = (activeLayer === 0) ? layerB : layerA;

        incoming.items = parentItems;
        incoming.resetScroll();
        incoming.x = -35;
        incoming.opacity = 0.0;
        incoming.visible = true;

        isTransitioning = true;
        popOutX.target = outgoing;
        popOutOp.target = outgoing;
        popInX.target = incoming;
        popInOp.target = incoming;
        slideAnimPop.outgoingRef = outgoing;
        slideAnimPop.targetLayerIndex = targetLayer;
        slideAnimPop.restart();
    }

    function handleItemClick(modelData) {
        if (isTransitioning) return;
        const hasSubmenu = Boolean(modelData.hasSubmenu) || (Boolean(modelData.children) && modelData.children.length > 0);
        if (hasSubmenu && modelData.children && modelData.children.length > 0) {
            root.pushSubmenu(modelData.label || "Submenu", modelData.children);
        } else if (modelData.enabled !== false) {
            if (root.targetItem && root.targetItem.menuPath) {
                WindowService.triggerTrayMenuItem(root.targetItem.service, root.targetItem.menuPath, modelData.id);
            }
            root.hide();
        }
    }

    function show(item, globalY) {
        root.targetItem = item;
        root.resetToRoot();
        menuCard.targetGlobalY = globalY;
        menuCard.visible = true;
        root.isLoading = true;
        root.menuItems = [];

        if (item && item.menuPath) {
            WindowService.fetchTrayMenu(item.service, item.menuPath, (items) => {
                if (root.targetItem && root.targetItem.service === item.service) {
                    root.isLoading = false;
                    root.menuItems = items;
                    root.resetToRoot();
                }
            });
        } else {
            root.isLoading = false;
            root.menuItems = [];
            root.resetToRoot();
        }
    }

    function hide() {
        menuCard.visible = false;
        root.targetItem = null;
        root.menuItems = [];
        root.submenuStack = [];
        root.resetToRoot();
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.hide()
    }

    ParallelAnimation {
        id: slideAnimPush
        property var outgoingRef: null
        property int targetLayerIndex: 0

        NumberAnimation {
            id: pushOutX
            property: "x"
            to: -35
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
        }
        NumberAnimation {
            id: pushOutOp
            property: "opacity"
            to: 0.0
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultEffects
        }
        NumberAnimation {
            id: pushInX
            property: "x"
            to: 0
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
        }
        NumberAnimation {
            id: pushInOp
            property: "opacity"
            to: 1.0
            duration: 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultEffects
        }

        onFinished: {
            root.activeLayer = targetLayerIndex;
            if (outgoingRef) outgoingRef.visible = false;
            root.isTransitioning = false;
        }
    }

    ParallelAnimation {
        id: slideAnimPop
        property var outgoingRef: null
        property int targetLayerIndex: 0

        NumberAnimation {
            id: popOutX
            property: "x"
            to: 35
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
        }
        NumberAnimation {
            id: popOutOp
            property: "opacity"
            to: 0.0
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultEffects
        }
        NumberAnimation {
            id: popInX
            property: "x"
            to: 0
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
        }
        NumberAnimation {
            id: popInOp
            property: "opacity"
            to: 1.0
            duration: 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultEffects
        }

        onFinished: {
            root.activeLayer = targetLayerIndex;
            if (outgoingRef) outgoingRef.visible = false;
            root.isTransitioning = false;
        }
    }

    MenuCard {
        id: menuCard
        visible: false
        z: 9999

        property real targetGlobalY: 0

        x: root.dockW
        y: Math.max(12, Math.min(root.screenH - height - 12, targetGlobalY - 10))
        width: 260
        implicitWidth: 260

        Behavior on y {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: 220
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }

        // Animated Header Container
        Item {
            width: parent.width
            implicitHeight: 46
            clip: true

            // Top-Level Header
            MenuHeader {
                anchors.fill: parent
                opacity: root.submenuStack.length === 0 ? 1.0 : 0.0
                x: root.submenuStack.length === 0 ? 0 : -20
                visible: opacity > 0.01
                title: root.targetItem ? (root.targetItem.title || root.targetItem.id) : ""
                subtitle: (root.targetItem && root.targetItem.service) ? root.targetItem.service : "System Tray"
                iconSource: Config.iconUrl(root.targetItem ? root.targetItem.rawIcon : "")
                materialIcon: root.targetItem ? (root.targetItem.materialIcon || "widgets") : "widgets"

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveExpressiveDefaultEffects }
                }
                Behavior on x {
                    NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveExpressiveDefaultSpatial }
                }
            }

            // Submenu Header
            Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8
                opacity: root.submenuStack.length > 0 ? 1.0 : 0.0
                x: root.submenuStack.length > 0 ? 0 : 20
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveExpressiveDefaultEffects }
                }
                Behavior on x {
                    NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveExpressiveDefaultSpatial }
                }

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
                        onClicked: root.popSubmenu()
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

        // Animated Viewport with Two-Layer Sliding Transition
        Item {
            width: parent.width
            implicitHeight: Math.min(460, animatedHeight)
            visible: root.currentItems.length > 0
            clip: true

            readonly property real activeContentHeight: {
                if (root.isTransitioning) {
                    const incoming = (root.activeLayer === 0) ? layerB : layerA;
                    return incoming ? incoming.contentHeight : 0;
                }
                const current = (root.activeLayer === 0) ? layerA : layerB;
                return current ? current.contentHeight : 0;
            }
            property real animatedHeight: activeContentHeight > 0 ? activeContentHeight : 30
            Behavior on animatedHeight {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                }
            }

            ContextMenuPage {
                id: layerA
                anchors.fill: parent
                items: root.menuItems || []
                x: 0
                opacity: 1.0
                visible: opacity > 0.001
                onItemClicked: (modelData) => root.handleItemClick(modelData)
            }

            ContextMenuPage {
                id: layerB
                anchors.fill: parent
                items: []
                x: 35
                opacity: 0.0
                visible: opacity > 0.001
                onItemClicked: (modelData) => root.handleItemClick(modelData)
            }
        }
    }

    // ==========================================
    // CONTEXT MENU PAGE COMPONENT
    // ==========================================
    component ContextMenuPage: Item {
        id: pageRoot
        property var items: []
        readonly property real contentHeight: menuCol.implicitHeight
        signal itemClicked(var modelData)

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
                    model: pageRoot.items

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
                            iconSource: Config.iconUrl(modelData.icon)
                            isDangerous: (modelData.label && modelData.label.toLowerCase().indexOf("quit") !== -1)
                            onClicked: pageRoot.itemClicked(modelData)
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

        function resetScroll() {
            menuFlickable.contentY = 0;
        }
    }
}
