import QtQuick
import Quickshell
import "../theme"
import "../config"
import "../components"
import "../services"
import "../dock/components"

Item {
    id: root

    required property real iconS
    signal requestContextMenu(var app, real globalY)
    signal requestTrayContextMenu(var item, real globalY)

    readonly property var pinnedList: {
        const _actId = WindowService.activeId;
        const _actApp = WindowService.activeAppId;
        const wins = WindowService.windows || [];
        const pinned = Config.pinnedApps || [];
        const result = [];
        const matchedWinIds = new Set();

        for (let i = 0; i < pinned.length; i++) {
            const p = pinned[i];
            const pId = (p.appId || "").toLowerCase();
            const pDesk = (p.desktopFile || "").toLowerCase();
            const pName = (p.appName || "").toLowerCase();
            let found = null;

            for (let j = 0; j < wins.length; j++) {
                const w = wins[j];
                if (matchedWinIds.has(w.id)) continue;
                const wId = (w.appId || "").toLowerCase();
                const wDesk = (w.desktopFile || "").toLowerCase();
                const wName = (w.appName || "").toLowerCase();
                const wCls = (w.cls || "").toLowerCase();

                if ((pId && (wId === pId || wDesk === pId || wCls === pId))
                    || (pDesk && (wDesk === pDesk || wId === pDesk))
                    || (pName && wName === pName)) {
                    found = w;
                    break;
                }
            }

            if (found) {
                matchedWinIds.add(found.id);
                const isAct = Boolean(found.isActive)
                    || (Boolean(_actId) && String(found.id).replace(/[{}]/g, "") === String(_actId).replace(/[{}]/g, ""))
                    || (Boolean(_actApp) && (String(p.appId).toLowerCase() === String(_actApp).toLowerCase() || String(found.appId).toLowerCase() === String(_actApp).toLowerCase()));
                result.push({
                    isPinned: true,
                    isRunning: true,
                    id: found.id,
                    appId: p.appId,
                    appName: p.appName || found.appName,
                    iconName: p.iconName || found.iconName,
                    materialIcon: p.materialIcon || found.materialIcon,
                    desktopFile: p.desktopFile || found.desktopFile || p.appId,
                    title: found.title,
                    isActive: isAct
                });
            } else {
                result.push({
                    isPinned: true,
                    isRunning: false,
                    id: null,
                    appId: p.appId,
                    appName: p.appName,
                    iconName: p.iconName,
                    materialIcon: p.materialIcon,
                    desktopFile: p.desktopFile || p.appId,
                    title: "",
                    isActive: false
                });
            }
        }
        return result;
    }

    readonly property var unpinnedList: {
        const _actId = WindowService.activeId;
        const _actApp = WindowService.activeAppId;
        const wins = WindowService.windows || [];
        const pinned = Config.pinnedApps || [];
        const result = [];
        const matchedWinIds = new Set();

        for (let i = 0; i < pinned.length; i++) {
            const p = pinned[i];
            const pId = (p.appId || "").toLowerCase();
            const pDesk = (p.desktopFile || "").toLowerCase();
            const pName = (p.appName || "").toLowerCase();

            for (let j = 0; j < wins.length; j++) {
                const w = wins[j];
                if (matchedWinIds.has(w.id)) continue;
                const wId = (w.appId || "").toLowerCase();
                const wDesk = (w.desktopFile || "").toLowerCase();
                const wName = (w.appName || "").toLowerCase();
                const wCls = (w.cls || "").toLowerCase();

                if ((pId && (wId === pId || wDesk === pId || wCls === pId))
                    || (pDesk && (wDesk === pDesk || wId === pDesk))
                    || (pName && wName === pName)) {
                    matchedWinIds.add(w.id);
                    break;
                }
            }
        }

        for (let k = 0; k < wins.length; k++) {
            const w = wins[k];
            if (!matchedWinIds.has(w.id)) {
                const isAct = Boolean(w.isActive)
                    || (Boolean(_actId) && String(w.id).replace(/[{}]/g, "") === String(_actId).replace(/[{}]/g, ""))
                    || (Boolean(_actApp) && String(w.appId).toLowerCase() === String(_actApp).toLowerCase());
                result.push({
                    isPinned: false,
                    isRunning: true,
                    id: w.id,
                    appId: w.appId || (w.appName ? w.appName.toLowerCase() : "window"),
                    appName: w.appName,
                    iconName: w.iconName,
                    materialIcon: w.materialIcon,
                    desktopFile: w.desktopFile || w.appId,
                    title: w.title,
                    isActive: isAct
                });
            }
        }

        return result;
    }

    readonly property var taskbarList: pinnedList.concat(unpinnedList)

    // TOP SECTION: Launcher & Workspaces Pill
    Column {
        id: topSection
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

        // 1. App Launcher Button (Arch Linux Logo)
        Item {
            id: launcherBtn
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.iconS
            height: root.iconS
            implicitWidth: root.iconS
            implicitHeight: root.iconS

            Text {
                id: launcherIcon
                anchors.centerIn: parent
                text: "\uf303" // Arch Linux logo glyph
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(root.iconS * 0.72)
                color: Colors.primary
                opacity: launcherHover.containsMouse ? 1.0 : 0.85
                scale: launcherHover.pressed ? 0.9 : (launcherHover.containsMouse ? 1.12 : 1.0)

                Behavior on scale {
                    NumberAnimation { duration: Theme.animDurationFast; easing.type: Easing.OutQuad }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.animDurationFast }
                }
            }

            MouseArea {
                id: launcherHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        Config.dashboardVisible = !Config.dashboardVisible;
                    } else {
                        Config.toggleCommandLauncher();
                    }
                }
            }

            // Launcher Tooltip
            Rectangle {
                z: 100
                visible: launcherHover.containsMouse
                anchors.left: parent.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: launcherTipText.implicitWidth + 16
                implicitHeight: launcherTipText.implicitHeight + 10
                radius: 8
                color: Colors.surfaceContainerHighest
                border.color: Theme.borderSubtle
                border.width: 1

                Text {
                    id: launcherTipText
                    anchors.centerIn: parent
                    text: "Command Launcher (Right-click: Dashboard)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Colors.textOnSurface
                }
            }
        }

        // 2. Workspaces Vertical Pill
        LiquidGlassCard {
            id: wsContainer
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property int wsBtnSize: 24
            readonly property int wsSpacing: 8
            readonly property int wsPad: 6
            readonly property int desktopCount: (KWinWorkspaces.desktops && KWinWorkspaces.desktops.length > 0)
                ? Math.min(6, Math.max(1, KWinWorkspaces.desktops.length))
                : 4
            implicitWidth: 30
            implicitHeight: (wsBtnSize + wsSpacing) * desktopCount - wsSpacing + wsPad * 2
            radius: Theme.radiusFull

            readonly property int activeWsIndex: {
                for (let i = 0; i < Math.min(desktopCount, KWinWorkspaces.desktops.length); i++) {
                    if (KWinWorkspaces.desktops[i].active) return i;
                }
                return 0;
            }

            // Asymmetric Stretch Liquid Indicator
            property real startY: 0
            property real endY: wsBtnSize

            function updateLiquidTrail() {
                const newStart = activeWsIndex * (wsBtnSize + wsSpacing);
                const goingUp = newStart < startY;
                const lead = Theme.animExpressiveDefaultSpatial;
                const trail = Math.round(lead * 1.5);

                startAnim.stop();
                endAnim.stop();
                startAnim.to = newStart;
                endAnim.to = newStart + wsBtnSize;
                startAnim.duration = goingUp ? lead : trail;
                endAnim.duration = goingUp ? trail : lead;
                startAnim.start();
                endAnim.start();
            }

            onActiveWsIndexChanged: updateLiquidTrail()
            Component.onCompleted: updateLiquidTrail()

            // Liquid Pill Graphic
            Rectangle {
                id: wsLiquidIndicator
                anchors.horizontalCenter: parent.horizontalCenter
                y: wsContainer.startY + wsContainer.wsPad
                width: wsContainer.wsBtnSize
                height: Math.max(wsContainer.wsBtnSize, wsContainer.endY - wsContainer.startY)
                radius: Theme.radiusFull
                color: Colors.primary
                border.color: Qt.alpha(Colors.textOnPrimary, 0.15)
                border.width: 1
                z: 0

                NumberAnimation {
                    id: startAnim
                    target: wsContainer
                    property: "startY"
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                }

                NumberAnimation {
                    id: endAnim
                    target: wsContainer
                    property: "endY"
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: wsContainer.wsSpacing
                z: 1

                Repeater {
                    model: {
                        if (KWinWorkspaces.desktops && KWinWorkspaces.desktops.length > 0) {
                            return KWinWorkspaces.desktops.slice(0, wsContainer.desktopCount);
                        }
                        return [
                            { index: 0, name: "Desktop 1" },
                            { index: 1, name: "Desktop 2" },
                            { index: 2, name: "Desktop 3" },
                            { index: 3, name: "Desktop 4" }
                        ];
                    }

                    delegate: Item {
                        id: wsDelegate
                        required property var modelData
                        readonly property bool isActive: wsContainer.activeWsIndex === modelData.index
                        readonly property int itemSize: wsContainer.wsBtnSize

                        width: itemSize
                        height: itemSize
                        implicitWidth: itemSize
                        implicitHeight: itemSize

                        // Inactive State: High-contrast Desktop Dot
                        Rectangle {
                            anchors.centerIn: parent
                            width: wsHover.containsMouse ? 8 : 7
                            height: wsHover.containsMouse ? 8 : 7
                            radius: width / 2
                            visible: !wsDelegate.isActive
                            color: wsHover.containsMouse ? Colors.primary : Qt.alpha(Colors.textOnSurface, 0.70)
                            scale: wsHover.containsMouse ? 1.25 : 1.0

                            Behavior on color {
                                ColorAnimation { duration: Theme.animDurationFast }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: Theme.animDurationFast }
                            }
                        }

                        // Active State: Pacman SVG Icon
                        PacmanIcon {
                            anchors.centerIn: parent
                            size: 16
                            color: Colors.textOnPrimary
                            visible: wsDelegate.isActive
                        }

                        MouseArea {
                            id: wsHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.id) {
                                    KWinWorkspaces.switchToDesktop(modelData.id);
                                } else if (KWinWorkspaces.desktops && KWinWorkspaces.desktops.length > modelData.index && KWinWorkspaces.desktops[modelData.index]) {
                                    KWinWorkspaces.switchToDesktop(KWinWorkspaces.desktops[modelData.index].id);
                                } else {
                                    KWinWorkspaces.switchToWorkspace(modelData.index);
                                }
                            }
                        }

                        // Tooltip
                        Rectangle {
                            z: 100
                            visible: wsHover.containsMouse
                            anchors.left: parent.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: wsTipText.implicitWidth + 16
                            implicitHeight: wsTipText.implicitHeight + 10
                            radius: 8
                            color: Colors.surfaceContainerHighest
                            border.color: Theme.borderSubtle
                            border.width: 1

                            Text {
                                id: wsTipText
                                anchors.centerIn: parent
                                text: modelData.name || ("Desktop " + (modelData.index + 1))
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Colors.textOnSurface
                            }
                        }
                    }
                }
            }
        }
    }

    // MIDDLE SECTION: Vertical Rotated Active Window
    // Kept clear of the workspaces switcher above it: the 16px outer gap
    // reads as a true module separation instead of a cramped stack.
    Item {
        id: activeWindowPill
        anchors.top: topSection.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: root.iconS + 16
        implicitHeight: Math.max(0, root.height - topSection.implicitHeight - bottomCol.implicitHeight - 28)
        visible: implicitHeight >= (root.iconS + 10)

        // 1. App Icon
        Item {
            id: activeIconContainer
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.iconS + 4
            height: root.iconS + 4

            Image {
                id: activeIconImg
                anchors.centerIn: parent
                width: root.iconS
                height: root.iconS
                source: Config.iconUrl(WindowService.activeIconName)
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: WindowService.activeMaterialIcon || "desktop_windows"
                size: Math.round(root.iconS * 0.82)
                color: Colors.primary
                visible: !activeIconImg.visible || activeIconImg.status !== Image.Ready
            }
        }

        // 2. Vertical Rotated Title
        Item {
            id: activeTitleRotated
            anchors.top: activeIconContainer.bottom
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            width: 24
            height: Math.max(0, parent.height - activeIconContainer.height - 12)
            clip: true
            visible: height >= 36

            readonly property string windowTitle: WindowService.activeTitle || "Desktop"
            property bool showingFirst: true

            TextMetrics {
                id: titleMetrics
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.Medium
                text: activeTitleRotated.windowTitle
                elide: Text.ElideRight
                elideWidth: Math.max(20, activeTitleRotated.height)

                onTextChanged: {
                    activeTitleRotated.showingFirst = !activeTitleRotated.showingFirst;
                    if (activeTitleRotated.showingFirst) {
                        titleText1.text = elidedText;
                    } else {
                        titleText2.text = elidedText;
                    }
                }
                onElideWidthChanged: {
                    if (activeTitleRotated.showingFirst) {
                        titleText1.text = elidedText;
                    } else {
                        titleText2.text = elidedText;
                    }
                }
            }

            Component.onCompleted: {
                titleText1.text = titleMetrics.elidedText;
            }

            Text {
                id: titleText1
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                font: titleMetrics.font
                color: Colors.textOnSurfaceVariant
                opacity: activeTitleRotated.showingFirst ? 1.0 : 0.0
                width: implicitHeight
                height: implicitWidth
                horizontalAlignment: Text.AlignLeft

                transform: [
                    Rotation {
                        angle: 90
                        origin.x: titleText1.implicitHeight / 2
                        origin.y: titleText1.implicitHeight / 2
                    }
                ]

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animExpressiveDefaultEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }
            }

            Text {
                id: titleText2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                font: titleMetrics.font
                color: Colors.textOnSurfaceVariant
                opacity: activeTitleRotated.showingFirst ? 0.0 : 1.0
                width: implicitHeight
                height: implicitWidth
                horizontalAlignment: Text.AlignLeft

                transform: [
                    Rotation {
                        angle: 90
                        origin.x: titleText2.implicitHeight / 2
                        origin.y: titleText2.implicitHeight / 2
                    }
                ]

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animExpressiveDefaultEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }
            }
        }
    }

    // Vertical budget for the two scrollable capsules (taskbar, tray).
    //
    // The top section (launcher, workspaces, active-window label) and the fixed
    // bottom modules (clock, status pill) are reserved FIRST, so a long taskbar or
    // a crowded tray can never grow into them - the reported collision between the
    // app icons and the active app name. `trayMinHeight` guarantees the tray keeps a
    // usable window before the taskbar takes the rest of the budget.
    readonly property real fixedDockHeight: dockClockArea.height + dockStatusPill.implicitHeight
        + bottomCol.spacing * 3 + bottomCol.anchors.bottomMargin + 8
    // Visible gap between the taskbar capsule and the active-window label above it,
    // so a full list still reads as a separate module.
    readonly property real listGap: 14
    // The active-window module (app icon + rotated name) lives in the MIDDLE
    // section, which is anchored below the top section and whose height is the
    // leftover space - it is not part of `topSection.implicitHeight`. Reserving
    // its content here is what stops a long taskbar from growing over it (the
    // reported "no more active app icon and name on the task bar").
    // 92 = 16px switcher clearance + 36px icon + 10px icon/title gap + ~30px
    // of title breathing room.
    readonly property real activeWindowReserve: 92
    readonly property real listBudget: Math.max(150,
        root.height - topSection.implicitHeight - root.activeWindowReserve
            - root.fixedDockHeight - root.listGap)
    readonly property real trayMinHeight: Math.min(trayContainer.naturalHeight,
        2 * (root.iconS - 4 + 2) + 12)
    // The tray keeps its natural height (capped to a third of the budget, so a
    // crowded tray can never squeeze the app list); the taskbar takes the rest and
    // grows into it as the app count rises.
    readonly property real trayMaxHeight: Math.max(root.trayMinHeight,
        Math.min(trayContainer.naturalHeight, root.listBudget * 0.32))
    readonly property real appsMaxHeight: Math.max(96,
        Math.min(appsContainer.naturalHeight, root.listBudget - root.trayMaxHeight))

    // LOWER SECTION & BOTTOM SECTION
    Column {
        id: bottomCol
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        anchors.bottomMargin: 8

        // 1. APPS CONTAINER (Taskbar)
        //
        // Scrollable and capped: the visible icons never grow past the height budget
        // (`root.appsMaxHeight`), which reserves the top section (launcher, workspaces,
        // active-window label) and the fixed modules below, so a long taskbar cannot
        // collide with the active app name or the clock. Overflow shows a scrollbar
        // thumb and end chevrons.
        DockScrollCapsule {
            id: appsContainer
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.iconS + 16
            radius: Math.round((root.iconS + 16) * 0.5)
            visible: root.taskbarList.length > 0
            itemSize: root.iconS + 8
            itemSpacing: 4
            vPad: 10
            // Grows into the bar as the app count rises (whole-item viewport,
            // scrolling beyond), capped so it can never grow over the
            // active-window module above it.
            maxHeight: root.appsMaxHeight
            maxVisibleItems: Config.maxVisibleApps


            HoverHandler {
                id: appsContainerHover
                onHoveredChanged: {
                    if (!hovered && Config.bottomPopoutMode === "app") {
                        Config.scheduleCloseBottomPopout();
                    }
                }
            }

            Component {
                id: appDelegateComponent

                Rectangle {
                    id: appDelegate
                    required property var modelData

                    readonly property int itemSize: root.iconS + 8

                    width: itemSize
                    height: itemSize
                    implicitWidth: itemSize
                    implicitHeight: itemSize
                    radius: Math.max(8, Math.round(itemSize * 0.28))
                    color: modelData.isActive ? Colors.primaryContainer : (appHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                    // Active left pill indicator
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: modelData.isActive ? Math.round(root.iconS * 0.65) : 0
                        radius: 1.5
                        color: Colors.primary
                        visible: modelData.isActive

                        Behavior on height {
                            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                        }
                    }

                    // Running dot indicator
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 3
                        radius: 1.5
                        color: Colors.textMuted
                        visible: modelData.isRunning && !modelData.isActive
                    }

                    // App Icon
                    Image {
                        id: appIconImg
                        anchors.centerIn: parent
                        width: root.iconS
                        height: root.iconS
                        opacity: modelData.isRunning ? 1.0 : 0.65
                        source: Config.iconUrl(modelData.iconName)
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: modelData.materialIcon || "desktop_windows"
                        size: Math.round(root.iconS * 0.82)
                        opacity: modelData.isRunning ? 1.0 : 0.65
                        color: modelData.isActive ? Colors.primary : Colors.onSurfaceVariant
                        visible: !appIconImg.visible || appIconImg.status !== Image.Ready
                    }

                    MouseArea {
                        id: appHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            WindowService.loadAppPreview(modelData);
                            const mapped = appDelegate.mapToItem(null, 0, appDelegate.height / 2);
                            const fallbackY = appsContainer.mapToItem(null, 0, appsContainer.height / 2).y;
                            const targetCenterY = (mapped && mapped.y > 50) ? mapped.y : fallbackY;
                            Config.openBottomPopout("app", targetCenterY);
                        }
                        onExited: {
                            if (!appsContainerHover.hovered) {
                                Config.scheduleCloseBottomPopout();
                            }
                        }
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                const mapped = mapToItem(null, 0, 0);
                                root.requestContextMenu(modelData, mapped.y);
                                Config.closeBottomPopout();
                            } else {
                                if (modelData.isRunning) {
                                    WindowService.activateWindow(modelData.id);
                                } else {
                                    WindowService.launchApp(modelData.desktopFile || modelData.appId);
                                }
                                Config.closeBottomPopout();
                            }
                        }
                    }

                    // Tooltip on hover (hidden when drawer is open)
                    Rectangle {
                        z: 100
                        visible: appHover.containsMouse && !Config.bottomPopoutVisible
                        anchors.left: parent.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: tipText.implicitWidth + 16
                        implicitHeight: tipText.implicitHeight + 10
                        radius: 7
                        color: Colors.surfaceContainerHighest
                        border.color: Colors.outlineVariant
                        border.width: 1

                        Text {
                            id: tipText
                            anchors.centerIn: parent
                            text: {
                                if (modelData.isPinned && modelData.isRunning) {
                                    return (modelData.appName + (modelData.title ? (" — " + modelData.title.slice(0, 32)) : "")) + " (Pinned)";
                                } else if (modelData.isPinned && !modelData.isRunning) {
                                    return modelData.appName + " (Click to launch)";
                                } else {
                                    return (modelData.appName + (modelData.title ? (" — " + modelData.title.slice(0, 32)) : "")) + " (Running)";
                                }
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Colors.onSurface
                        }
                    }
                }
            }

            // Pinned Apps
            Repeater {
                model: root.pinnedList
                delegate: appDelegateComponent
            }

            // Divider between Pinned Apps and Unpinned Running Apps
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: root.iconS + 10
                implicitHeight: 12
                visible: root.pinnedList.length > 0 && root.unpinnedList.length > 0

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.round(root.iconS * 0.65)
                    height: 2
                    radius: 1
                    color: Colors.outline
                    opacity: 0.7
                }
            }

            // Unpinned Running Apps
            Repeater {
                model: root.unpinnedList
                delegate: appDelegateComponent
            }
        }

        // Divider between Apps & Status
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.iconS + 16
            implicitHeight: 16
            visible: root.taskbarList.length > 0 && WindowService.tray.length > 0

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(root.iconS * 0.75)
                height: 2.5
                radius: 1.25
                color: Colors.outline
                opacity: 0.85
            }
        }

        // 2. SYSTEM TRAY ICONS CONTAINER
        //
        // Secondary group: flatter glass, an inner rim and smaller icons, so tray
        // items are visually distinct from running-app icons. Capped and scrollable
        // like the taskbar, so a crowded tray cannot push the clock or the status
        // pill out of the dock either.
        DockScrollCapsule {
            id: trayContainer
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.iconS + 8
            radius: Math.round((root.iconS + 8) * 0.5)
            visible: WindowService.tray.length > 0
            subtle: true
            // No card: the tray is a column of icons, not another panel.
            bare: true
            itemSize: root.iconS - 4
            itemSpacing: 2
            vPad: 6
            maxHeight: root.trayMaxHeight

            HoverHandler {
                id: trayContainerHover
                onHoveredChanged: {
                    if (!hovered && Config.bottomPopoutMode === "tray") {
                        Config.scheduleCloseBottomPopout();
                    }
                }
            }

            Repeater {
                model: WindowService.tray

                delegate: Rectangle {
                    id: trayDelegate
                    required property var modelData

                    readonly property bool isInputMethod: {
                        const raw = (modelData.rawIcon || "").toLowerCase();
                        const id = (modelData.id || "").toLowerCase();
                        const title = (modelData.title || "").toLowerCase();
                        return raw.includes("keyboard") || raw.includes("fcitx") || id.includes("fcitx") || id.includes("input") || title.includes("input");
                    }

                    readonly property int itemSize: root.iconS - 4

                    width: itemSize
                    height: itemSize
                    implicitWidth: itemSize
                    implicitHeight: itemSize
                    radius: Math.max(8, Math.round(itemSize * 0.32))
                    color: trayHover.containsMouse ? Colors.surfaceContainerHigh : "transparent"

                    Text {
                        id: imBadgeText
                        anchors.centerIn: parent
                        visible: isInputMethod && !!modelData.imBadge
                        text: modelData.imBadge || ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(11, Math.round(root.iconS * 0.40))
                        font.bold: true
                        color: (modelData.imBadge === "中" || modelData.imBadge === "拼")
                            ? Colors.primary
                            : (trayHover.containsMouse ? Colors.primary : Colors.textOnSurface)
                    }

                    ThemedIcon {
                        id: trayThemedIcon
                        anchors.centerIn: parent
                        // Secondary group: the glyph is deliberately smaller than an
                        // app icon, so the tray never competes with the taskbar.
                        size: Math.round(root.iconS * 0.62)
                        source: Config.iconUrl(modelData.rawIcon)
                        materialIcon: modelData.materialIcon || "circle"
                        color: trayHover.containsMouse ? Colors.primary : Colors.textOnSurface
                        visible: !imBadgeText.visible
                    }

                    MouseArea {
                        id: trayHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (modelData.menuPath && modelData.menuPath.length > 0) {
                                WindowService.loadTrayMenu(modelData);
                                const targetCenterY = trayDelegate.mapToItem(null, 0, trayDelegate.height / 2).y;
                                Config.openBottomPopout("tray", targetCenterY);
                            }
                        }
                        onExited: {
                            if (!trayContainerHover.hovered) {
                                Config.scheduleCloseBottomPopout();
                            }
                        }
                        onClicked: mouse => {
                            const targetCenterY = trayDelegate.mapToItem(null, 0, trayDelegate.height / 2).y;
                            const globalPt = trayDelegate.mapToItem(null, mouse.x, mouse.y);
                            if (mouse.button === Qt.RightButton) {
                                if (modelData.menuPath && modelData.menuPath.length > 0) {
                                    WindowService.loadTrayMenu(modelData);
                                    Config.openBottomPopout("tray", targetCenterY);
                                } else {
                                    WindowService.contextMenuTray(modelData.service, modelData.path, globalPt.x, globalPt.y);
                                }
                            } else {
                                if (modelData.itemIsMenu && modelData.menuPath && modelData.menuPath.length > 0) {
                                    WindowService.loadTrayMenu(modelData);
                                    Config.openBottomPopout("tray", targetCenterY);
                                } else {
                                    Config.closeBottomPopout();
                                    WindowService.activateTray(modelData.service, modelData.path, globalPt.x, globalPt.y);
                                }
                            }
                        }
                    }

                    // Tooltip on hover (hidden when drawer is open)
                    Rectangle {
                        z: 100
                        visible: trayHover.containsMouse && !Config.bottomPopoutVisible
                        anchors.left: parent.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: trayTipText.implicitWidth + 16
                        implicitHeight: trayTipText.implicitHeight + 10
                        radius: 7
                        color: Colors.surfaceContainerHighest
                        border.color: Colors.outlineVariant
                        border.width: 1

                        Text {
                            id: trayTipText
                            anchors.centerIn: parent
                            text: (modelData.title && !modelData.title.startsWith("Error")) ? modelData.title : ((modelData.id && !modelData.id.startsWith("Error")) ? modelData.id : "Application")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Colors.onSurface
                        }
                    }
                }
            }
        }

        // 3. Stacked Clock
        Item {
            id: dockClockArea
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.iconS
            height: clockPill.implicitHeight

            Rectangle {
                id: clockPill
                anchors.centerIn: parent
                width: root.iconS
                implicitHeight: clockCol.implicitHeight + 8
                radius: Theme.radiusMedium
                // No resting card: bare text, tinted only on hover or while the
                // clock popout is open.
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "clock")
                    ? Colors.primary
                    : (clockHover.hovered ? Colors.glassPillHover : "transparent")
                // No border: the clock is a translucent pill, and its active state is
                // already expressed by the fill colour.
                Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }

                Column {
                    id: clockCol
                    anchors.centerIn: parent
                    spacing: 1

                    Timer {
                        id: clockTimer
                        interval: 1000
                        running: true
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: {
                            const now = new Date();
                            hourText.text = Qt.formatDateTime(now, "HH");
                            minuteText.text = Qt.formatDateTime(now, "mm");
                        }
                    }

                    Text {
                        id: hourText
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "12"
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(13, Math.round(root.iconS * 0.44))
                        font.weight: Font.DemiBold
                        color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "clock")
                            ? Colors.textOnPrimary
                            : Colors.textOnSurface
                    }

                    Text {
                        id: minuteText
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "00"
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.max(13, Math.round(root.iconS * 0.44))
                        font.weight: Font.DemiBold
                        color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "clock")
                            ? Colors.textOnPrimary
                            : Colors.textOnSurface
                    }
                }

                HoverHandler {
                    id: clockHover
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered) {
                            Config.openBottomPopout("clock", dockClockArea.mapToItem(null, 0, dockClockArea.height / 2).y);
                        } else {
                            Config.scheduleCloseBottomPopout();
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (Config.bottomPopoutVisible && Config.bottomPopoutMode === "clock") {
                            Config.closeBottomPopout();
                        } else {
                            Config.openBottomPopout("clock", dockClockArea.mapToItem(null, 0, dockClockArea.height / 2).y);
                        }
                    }
                }
            }
        }

        // 4. Anchored Status Icons Group Pill
        DockStatusIcons {
            id: dockStatusPill
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
