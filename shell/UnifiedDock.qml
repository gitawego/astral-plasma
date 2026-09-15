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
        const pinned = Config.pinnedApps || [];
        const wins = WindowService.windows || [];
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
                    isActive: found.isActive
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
                    isActive: w.isActive
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
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Config.dashboardVisible = !Config.dashboardVisible;
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
                    text: "App Launcher & Dashboard"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Colors.textOnSurface
                }
            }
        }

        // 2. Workspaces Vertical Pill
        Rectangle {
            id: wsContainer
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property int wsBtnSize: 24
            readonly property int wsSpacing: 8
            readonly property int wsPad: 6
            implicitWidth: 30
            implicitHeight: (wsBtnSize + wsSpacing) * 4 - wsSpacing + wsPad * 2
            radius: Theme.radiusFull
            color: Colors.surfaceContainer
            border.color: Theme.borderSubtle
            border.width: 1

            readonly property int activeWsIndex: {
                for (let i = 0; i < Math.min(4, KWinWorkspaces.desktops.length); i++) {
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
                    model: [
                        { index: 0, name: "Desktop 1" },
                        { index: 1, name: "Desktop 2" },
                        { index: 2, name: "Desktop 3" },
                        { index: 3, name: "Desktop 4" }
                    ]

                    delegate: Item {
                        id: wsDelegate
                        required property var modelData
                        readonly property bool isActive: wsContainer.activeWsIndex === modelData.index
                        readonly property int itemSize: wsContainer.wsBtnSize

                        width: itemSize
                        height: itemSize
                        implicitWidth: itemSize
                        implicitHeight: itemSize

                        // Inactive State: Gray Dot Icon
                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: 3
                            visible: !wsDelegate.isActive
                            color: wsHover.containsMouse ? Colors.primary : Colors.outline
                            scale: wsHover.containsMouse ? 1.3 : 1.0

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
                                if (KWinWorkspaces.desktops && KWinWorkspaces.desktops.length > modelData.index && KWinWorkspaces.desktops[modelData.index]) {
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
                                text: (KWinWorkspaces.desktops.length > modelData.index && KWinWorkspaces.desktops[modelData.index].name)
                                    ? KWinWorkspaces.desktops[modelData.index].name
                                    : modelData.name
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
    Item {
        id: activeWindowPill
        anchors.top: topSection.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: root.iconS + 16
        implicitHeight: Math.max(0, root.height - topSection.implicitHeight - bottomCol.implicitHeight - 20)
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
                source: {
                    if (!WindowService.activeIconName) return "";
                    if (WindowService.activeIconName.indexOf("/") !== -1) {
                        return WindowService.activeIconName.startsWith("file://") ? WindowService.activeIconName : ("file://" + WindowService.activeIconName);
                    }
                    return Quickshell.iconPath(WindowService.activeIconName);
                }
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
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            width: 24
            height: Math.max(0, parent.height - activeIconContainer.height - 8)
            clip: true
            visible: height >= 36

            readonly property string windowTitle: WindowService.activeTitle || "Desktop"
            property bool showingFirst: true

            TextMetrics {
                id: titleMetrics
                font.family: Theme.fontFamily
                font.pixelSize: 11
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

    // LOWER SECTION & BOTTOM SECTION
    Column {
        id: bottomCol
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        anchors.bottomMargin: 8

        // 1. APPS CONTAINER (Taskbar)
        Rectangle {
            id: appsContainer
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.iconS + 16
            readonly property int maxAppsHeight: Math.max(120, root.height - topSection.implicitHeight - 360)
            implicitHeight: Math.min(appsCol.implicitHeight + 8, maxAppsHeight)
            radius: Math.round((root.iconS + 16) * 0.25)
            color: Colors.surfaceContainer
            border.color: Theme.borderSubtle
            border.width: 1
            visible: root.taskbarList.length > 0
            clip: true

            Flickable {
                id: appsFlickable
                anchors.fill: parent
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                contentWidth: width
                contentHeight: appsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                interactive: contentHeight > height

                Column {
                    id: appsCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(0, (parent.height - implicitHeight) / 2)
                    spacing: 4

                    Component {
                        id: appDelegateComponent

                        Rectangle {
                            id: appDelegate
                            required property var modelData

                            readonly property int itemSize: root.iconS + 10

                            width: itemSize
                            height: itemSize
                            implicitWidth: itemSize
                            implicitHeight: itemSize
                            radius: Math.max(6, Math.round(itemSize * 0.22))
                            color: modelData.isActive ? Colors.primaryContainer : (appHover.containsMouse ? Colors.surfaceContainerHigh : "transparent")

                            // Active left pill indicator
                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 1
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
                                anchors.leftMargin: 1
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
                                source: {
                                    if (!modelData.iconName) return "";
                                    if (modelData.iconName.indexOf("/") !== -1) {
                                        return modelData.iconName.startsWith("file://") ? modelData.iconName : ("file://" + modelData.iconName);
                                    }
                                    return Quickshell.iconPath(modelData.iconName);
                                }
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
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        const mapped = mapToItem(null, 0, 0);
                                        root.requestContextMenu(modelData, mapped.y);
                                    } else {
                                        if (modelData.isRunning) {
                                            WindowService.activateWindow(modelData.id);
                                        } else {
                                            WindowService.launchApp(modelData.desktopFile || modelData.appId);
                                        }
                                    }
                                }
                            }

                            // Tooltip on hover
                            Rectangle {
                                z: 100
                                visible: appHover.containsMouse
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
        Rectangle {
            id: trayContainer
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.iconS + 16
            implicitHeight: trayCol.implicitHeight + 8
            radius: Math.round((root.iconS + 16) * 0.25)
            color: Colors.surfaceContainer
            border.color: Theme.borderSubtle
            border.width: 1
            visible: WindowService.tray.length > 0

            Column {
                id: trayCol
                anchors.centerIn: parent
                spacing: 4

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

                        readonly property int itemSize: root.iconS + 4

                        width: itemSize
                        height: itemSize
                        implicitWidth: itemSize
                        implicitHeight: itemSize
                        radius: Math.max(6, Math.round(itemSize * 0.22))
                        color: trayHover.containsMouse ? Colors.surfaceContainerHigh : "transparent"

                        Text {
                            id: imBadgeText
                            anchors.centerIn: parent
                            visible: isInputMethod && !!modelData.imBadge
                            text: modelData.imBadge || ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.max(13, Math.round(root.iconS * 0.48))
                            font.bold: true
                            color: (modelData.imBadge === "中" || modelData.imBadge === "拼")
                                ? Colors.primary
                                : (trayHover.containsMouse ? Colors.primary : Colors.textOnSurface)
                        }

                        Image {
                            id: trayIconImg
                            anchors.centerIn: parent
                            width: root.iconS
                            height: root.iconS
                            source: (modelData.rawIcon && !modelData.rawIcon.startsWith("Error")) ? Quickshell.iconPath(modelData.rawIcon) : ""
                            fillMode: Image.PreserveAspectFit
                            visible: !imBadgeText.visible && status === Image.Ready
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: modelData.materialIcon || "circle"
                            size: Math.round(root.iconS * 0.82)
                            color: trayHover.containsMouse ? Colors.primary : Colors.onSurfaceVariant
                            visible: !imBadgeText.visible && (!trayIconImg.visible || trayIconImg.status !== Image.Ready)
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
                                Config.scheduleCloseBottomPopout();
                            }
                            onClicked: mouse => {
                                const targetCenterY = trayDelegate.mapToItem(null, 0, trayDelegate.height / 2).y;
                                if (mouse.button === Qt.RightButton) {
                                    if (modelData.menuPath && modelData.menuPath.length > 0) {
                                        WindowService.loadTrayMenu(modelData);
                                        Config.openBottomPopout("tray", targetCenterY);
                                    } else {
                                        WindowService.contextMenuTray(modelData.service, modelData.path);
                                    }
                                } else {
                                    if (modelData.menuPath && modelData.menuPath.length > 0) {
                                        WindowService.loadTrayMenu(modelData);
                                        Config.openBottomPopout("tray", targetCenterY);
                                    } else {
                                        WindowService.activateTray(modelData.service, modelData.path);
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
                color: (Config.bottomPopoutVisible && Config.bottomPopoutMode === "clock")
                    ? Colors.primary
                    : (clockHover.hovered ? Colors.surfaceContainerHigh : "transparent")
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
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
