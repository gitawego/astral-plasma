import QtQuick
import QtQuick.Layouts
import "../../Kernel/theme"
import "../../Kernel/components"

import "./DashboardTabs.js" as DashboardTabs
import "../../Kernel/services"

Item {
    id: root

    property real dropX: (parent.width - dropW) / 2
    property real dropW: (root.shellState && root.shellState.dashboardWidth) || 980
    readonly property real targetDropH: cardLayout.implicitHeight > 0
        ? (cardLayout.implicitHeight + Theme.padLarge * 2)
        : 440
    property real dropH: targetDropH

    Behavior on dropH {
        NumberAnimation {
            duration: (typeof Theme !== "undefined" && Theme.animExpressiveDefaultSpatial) ? Theme.animExpressiveDefaultSpatial : 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveDefaultSpatial) ? Theme.curveExpressiveDefaultSpatial : [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    property bool isOpen: root.shellState !== null && root.shellState.dashboardVisible
    readonly property real currentDropH: dropH * offsetProgress
    property real offsetProgress: isOpen ? 1.0 : 0.0

    Connections {
        target: root.shellState
        enabled: root.shellState !== null
        ignoreUnknownSignals: true
        function onDashboardVisibleChanged() {
            if (root.shellState !== null) {
                root.isOpen = root.shellState.dashboardVisible;
            }
        }
        function onActiveDashboardTabChanged() {
            if (root.shellState !== null && root.shellState.activeDashboardTab
                    && root.activeTab !== root.shellState.activeDashboardTab) {
                root.activeTab = root.shellState.activeDashboardTab;
            }
        }
    }

    /// Whether the download engine is present. Unknown (no snapshot yet, or a
    /// context without the service) counts as present: hiding a tab the user has
    /// enabled must be a statement about the engine, never about missing data.
    readonly property bool ariaAvailable: (typeof DownloadService !== "undefined" && DownloadService
        && DownloadService.ariaAvailable !== undefined) ? Boolean(DownloadService.ariaAvailable) : true

    /// The tabs this machine can render: the ones enabled in settings, minus the
    /// tabs whose dependency is missing (the Downloads tab needs the aria2
    /// engine).
    ///
    /// The *panes* keep their fixed order below - the content strip and the
    /// per-pane visibility are index-based - so a tab hidden here is simply
    /// never selected, instead of shifting every pane.
    readonly property var visibleTabs: DashboardTabs.availableTabs(root.shellState ? root.shellState.dashboardTabs : [], root.ariaAvailable)

    function tabIndex(tabId) {
        for (let i = 0; i < root.visibleTabs.length; ++i) {
            if (root.visibleTabs[i] && root.visibleTabs[i].id === tabId) {
                return i;
            }
        }
        return -1;
    }

    /// The selected tab, falling back to one that is actually rendered: the
    /// stored preference can point at a hidden tab (it was disabled, or the
    /// engine went away), and a view left on a tab with no chip is a view the
    /// user cannot leave.
    property string activeTab: DashboardTabs.fallbackActiveTab(root.visibleTabs,
        (root.shellState && root.shellState.activeDashboardTab) ? root.shellState.activeDashboardTab : "dashboard")
    onActiveTabChanged: {
        // Only a *selected* tab is worth persisting. Writing the fallback back
        // would overwrite the user's choice with the fallback and lose it as soon
        // as the tab becomes available again.
        if (root.shellState === null) return;
        if (!root.visibleTabs.some(t => t.id === root.activeTab)) return;
        if (root.shellState.activeDashboardTab !== activeTab) {
            if (root.intents) root.intents.request("dashboard.show", { tab: activeTab });
        }
    }

    property bool hoverOverrideActive: false
    property bool hoverOverride: false
    readonly property bool isHovered: hoverOverrideActive ? hoverOverride : dropdownHover.hovered

    readonly property alias layoutItem: cardLayout
    readonly property alias settingsBtnItem: settingsBtn
    readonly property alias tabRepeaterItem: tabRepeater
    readonly property alias tabSlidingIndicatorItem: tabSlidingIndicator
    // --- host access ---------------------------------------------------------
    // The dashboard reads the host through these, so a host that does not support app
    // mounting (a test stub, or a shell without the platform) yields an empty pane with
    // a reason instead of a TypeError.
    function hostTabStatus(tabId) {
        if (root.appHost && typeof root.appHost.tabStatus === "function") {
            return root.appHost.tabStatus(tabId);
        }
        return { id: "", available: false, reason: "this shell does not host apps" };
    }

    function mountTab(tabId, surface) {
        if (!root.appHost || typeof root.appHost.providerForTab !== "function") {
            return null;
        }
        const provider = root.appHost.providerForTab(tabId);
        if (provider.length === 0 || typeof root.appHost.loaderFor !== "function") {
            return null;
        }
        if (root.appHost.loaderFor(provider) === null || surface.children.length > 0) {
            return null;
        }
        return root.appHost.mount(provider, surface);
    }

    /// Injected by UnifiedShell: the app host. Every port this app needs is reachable
    /// from it (state, intents, session, media, metrics), so the shell injects one
    /// object instead of nine (spec C.21).
    property var appHost: null

    readonly property var shellState: appHost ? appHost.state : null
    readonly property var intents: appHost ? appHost.intents : null
    readonly property var session: appHost ? appHost.session : null
    readonly property var media: appHost ? appHost.media : null
    readonly property var metrics: appHost ? appHost.metrics : null

    readonly property alias tabsRowItem: tabsRow
    readonly property alias tabContentContainerItem: tabContentContainer
    readonly property alias tabSliderItem: tabSlider
    /// The hosted downloads app's item, or null while it is not mounted.
    readonly property Item downloadsTabItem: dlAppHostSurface.children.length > 0
        ? dlAppHostSurface.children[0] : null
    readonly property Item workspacesTabItem: wsAppSurface.children.length > 0 ? wsAppSurface.children[0] : null

    // Keyboard contract for the shell's layer surface: while a tab captures
    // text (the Downloads add sheet, Workspaces search), UnifiedShell requests
    // compositor keyboard focus. A new text-capturing tab must OR its state in here.
    readonly property bool textInputActive: Boolean(downloadsTabItem && downloadsTabItem.addDialogOpen)
        || Boolean(workspacesTabItem && workspacesTabItem.searchActive)

    x: dropX
    y: 0
    width: dropW
    height: currentDropH
    visible: offsetProgress > 0.001
    clip: true

    Behavior on offsetProgress {
        NumberAnimation {
            duration: Theme.animExpressiveDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
        }
    }

    focus: true
    Keys.onEscapePressed: {
        if (root.intents) root.intents.request("dashboard.close");
        root.isOpen = false;
    }

    HoverHandler {
        id: dropdownHover
    }

    // Shield: consume clicks within the dropdown bounds so unhandled clicks
    // never fall through to the background dismiss scrim in UnifiedShell.
    MouseArea {
        anchors.fill: parent
        onClicked: mouse.accepted = true
    }

    readonly property var tabs: root.visibleTabs

    ColumnLayout {
        id: cardLayout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.padLarge
        anchors.topMargin: Theme.padLarge + Math.min(0, root.currentDropH - root.dropH)
        spacing: Theme.spaceMedium

        // Tabs Header with Fluid Sliding Indicator & Quick Settings Button
        Item {
            id: tabsHeader
            Layout.fillWidth: true
            implicitHeight: 60

            // Settings Button on the right
            LiquidGlassButton {
                id: settingsBtn
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 38
                implicitHeight: 38
                paddingHorizontal: 6
                paddingVertical: 6
                iconText: "settings"
                iconSize: 18
                elevation: 4
                onClicked: {
                    if (root.intents) {
                        root.intents.request("dashboard.close");
                        root.intents.request("settings.open", {});
                    }
                }

                // Tooltip
                Rectangle {
                    id: settingsTip
                    z: 100
                    visible: settingsBtn.hovered
                    anchors.top: parent.bottom
                    anchors.topMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: settingsTipText.implicitWidth + 16
                    implicitHeight: settingsTipText.implicitHeight + 8
                    radius: (typeof Theme !== "undefined" && Theme.radiusExtraSmall !== undefined) ? Theme.radiusExtraSmall : 6
                    color: Colors.glassModalSurface
                    border.color: Colors.glassBorderSubtle
                    border.width: 1

                    Text {
                        id: settingsTipText
                        anchors.centerIn: parent
                        text: "Theme Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Colors.isDarkMode ? "#FFFFFF" : Colors.textMain
                    }
                }
            }

            // Justified row: fills the header width LEFT of the settings
            // button by construction, so a 6th tab can never slide under the
            // gear (fixed 145px centered cells overflowed by ~40px).
            Row {
                id: tabsRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: settingsBtn.left
                anchors.rightMargin: 8
                spacing: 8

                Repeater {
                    id: tabRepeater
                    model: root.tabs

                    delegate: Rectangle {
                        id: tabItem
                        required property var modelData
                        required property int index
                        readonly property bool isSelected: root.activeTab === modelData.id

                        // Even split of the available row width: total is
                        // exactly row width, so the last cell ends where the
                        // settings button begins. No centering overflow.
                        width: Math.max(80, Math.floor((tabsRow.width - (root.tabs.length - 1) * tabsRow.spacing) / Math.max(1, root.tabs.length)))
                        height: 50
                        radius: Theme.radiusSmall
                        color: tabHover.containsMouse ? Qt.alpha(Colors.textMain, 0.08) : "transparent"

                        Column {
                            anchors.centerIn: parent
                            spacing: 3

                            MaterialIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon || modelData.id || ""
                                size: 20
                                color: isSelected ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb") : (tabHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb") : ((typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#e3e3e3"))
                                Behavior on color {
                                    ColorAnimation { duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastEffects) ? Theme.animExpressiveFastEffects : 150 }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(implicitWidth, tabItem.width - 12)
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.label || modelData.id || ""
                                font.pixelSize: 12
                                font.weight: isSelected ? Font.Bold : Font.DemiBold
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                color: isSelected ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb") : (tabHover.containsMouse ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb") : ((typeof Colors !== "undefined" && Colors.textMain) ? Colors.textMain : "#e3e3e3"))
                                elide: Text.ElideRight
                                Behavior on color {
                                    ColorAnimation { duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastEffects) ? Theme.animExpressiveFastEffects : 150 }
                                }
                            }
                        }

                        MouseArea {
                            id: tabHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.activeTab = modelData.id;
                                if (root.intents) root.intents.request("dashboard.show", { tab: modelData.id });
                            }
                        }
                    }
                }
            }

            // Fluid Sliding Underline Indicator
            Rectangle {
                id: tabSlidingIndicator
                anchors.bottom: parent.bottom
                height: 3
                radius: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") ? 0 : 1.5
                color: Colors.primary

                // Position within the *rendered* bar: the indicator has to sit
                // under the chip that is selected, and the bar is no longer the
                // fixed six-tab list.
                readonly property int activeIdx: {
                    for (let i = 0; i < root.tabs.length; ++i) {
                        if (root.tabs[i].id === root.activeTab) return i;
                    }
                    return 0;
                }

                readonly property Item activeTabItem: (tabRepeater.count > activeIdx) ? tabRepeater.itemAt(activeIdx) : null
                readonly property real targetWidth: activeTabItem ? activeTabItem.width : 0
                readonly property real targetX: activeTabItem ? (tabsRow.x + activeTabItem.x) : 0

                x: targetX
                width: targetWidth

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.animExpressiveDefaultSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }
                }

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.animExpressiveDefaultSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }
                }
            }
        }

        // Tab Content Sliding View
        Item {
            id: tabContentContainer
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            clip: true
            implicitHeight: {
                switch (root.activeTab) {
                    case "dashboard": return tabPaneDashboard.implicitHeight;
                    case "media": return tabPaneMedia.implicitHeight;
                    case "performance": return tabPanePerformance.implicitHeight;
                    case "ai": return tabPaneAi.implicitHeight;
                    case "workspaces": return tabPaneWorkspaces.implicitHeight;
                    case "downloads": return tabPaneDownloads.implicitHeight;
                    default: return tabPaneDashboard.implicitHeight;
                }
            }

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: Theme.animExpressiveDefaultSpatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                }
            }

            readonly property int activeTabIndex: {
                const idx = root.tabIndex(root.activeTab);
                return idx >= 0 ? idx : 0;
            }

            Item {
                id: tabSlider
                width: tabContentContainer.width * Math.max(6, root.visibleTabs.length)
                height: parent.height
                x: -tabContentContainer.activeTabIndex * tabContentContainer.width

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.animExpressiveDefaultSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                    }
                }

                readonly property bool isAnimating: Math.abs(tabSlider.x - (-tabContentContainer.activeTabIndex * tabContentContainer.width)) > 1

                Item {
                    id: tabPaneDashboard
                    readonly property int myIndex: root.tabIndex("dashboard")
                    x: myIndex >= 0 ? myIndex * tabContentContainer.width : 0
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: dashTab.implicitHeight
                    clip: true
                    visible: (myIndex >= 0 ? tabContentContainer.activeTabIndex === myIndex : tabContentContainer.activeTabIndex === 0) || tabSlider.isAnimating

                    DashboardTab {
                        id: dashTab
                        width: parent.width
                        height: parent.height
                        session: root.session
                        media: root.media
                        metrics: root.metrics
                        shellState: root.shellState
                        intents: root.intents
                    }
                }

                Item {
                    id: tabPaneMedia
                    readonly property int myIndex: root.tabIndex("media")
                    x: myIndex >= 0 ? myIndex * tabContentContainer.width : tabContentContainer.width
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: mediaAppSurface.children.length > 0
                        ? Math.max(mediaAppSurface.children[0].implicitHeight, 320) : 320
                    clip: true
                    visible: (myIndex >= 0 ? tabContentContainer.activeTabIndex === myIndex : tabContentContainer.activeTabIndex === 1) || tabSlider.isAnimating

                    Item {
                        id: mediaApp
                        width: parent.width
                        height: parent.height

                        /// The app's item lives here, so the pane can also hold a hint.
                        Item {
                            id: mediaAppSurface
                            anchors.fill: parent
                        }

                        AppUnavailableHint {
                            id: mediaAppHint
                            anchors.fill: parent
                            appName: "Media"
                            readonly property var status: root.hostTabStatus("media")
                            visible: !status.available
                            reason: status.reason
                        }

                        readonly property int hostReadiness: {
                            if (!root.appHost) return 0;
                            return root.appHost.loaderCount * 1000
                                + Object.keys(root.appHost.tabProviders).length;
                        }
                        onHostReadinessChanged: mountApp()
                        Component.onCompleted: mountApp()

                        function mountApp() {
                            if (!root.appHost) return;
                            root.mountTab("media", mediaAppSurface);
                        }
                    }
                }

                Item {
                    id: tabPanePerformance
                    readonly property int myIndex: root.tabIndex("performance")
                    x: myIndex >= 0 ? myIndex * tabContentContainer.width : tabContentContainer.width * 2
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: perfAppSurface.children.length > 0
                        ? Math.max(perfAppSurface.children[0].implicitHeight, 320) : 320
                    clip: true
                    visible: (myIndex >= 0 ? tabContentContainer.activeTabIndex === myIndex : tabContentContainer.activeTabIndex === 2) || tabSlider.isAnimating

                    Item {
                        id: perfApp
                        width: parent.width
                        height: parent.height

                        /// The app's item lives here, so the pane can also hold a hint.
                        Item {
                            id: perfAppSurface
                            anchors.fill: parent
                        }

                        AppUnavailableHint {
                            id: perfAppHint
                            anchors.fill: parent
                            appName: "Performance"
                            readonly property var status: root.hostTabStatus("performance")
                            visible: !status.available
                            reason: status.reason
                        }

                        readonly property int hostReadiness: {
                            if (!root.appHost) return 0;
                            return root.appHost.loaderCount * 1000
                                + Object.keys(root.appHost.tabProviders).length;
                        }
                        onHostReadinessChanged: mountApp()
                        Component.onCompleted: mountApp()

                        function mountApp() {
                            if (!root.appHost) return;
                            root.mountTab("performance", perfAppSurface);
                        }
                    }
                }

                Item {
                    id: tabPaneAi
                    readonly property int myIndex: root.tabIndex("ai")
                    x: myIndex >= 0 ? myIndex * tabContentContainer.width : tabContentContainer.width * 3
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: aiAppSurface.children.length > 0
                        ? Math.max(aiAppSurface.children[0].implicitHeight, 320) : 320
                    clip: true
                    visible: (myIndex >= 0 ? tabContentContainer.activeTabIndex === myIndex : tabContentContainer.activeTabIndex === 3) || tabSlider.isAnimating

                    Item {
                        id: aiApp
                        width: parent.width
                        height: parent.height

                        /// The app's item lives here, so the pane can also hold a hint.
                        Item {
                            id: aiAppSurface
                            anchors.fill: parent
                        }

                        AppUnavailableHint {
                            id: aiAppHint
                            anchors.fill: parent
                            appName: "AI Quotas"
                            readonly property var status: root.hostTabStatus("ai")
                            visible: !status.available
                            reason: status.reason
                        }

                        readonly property int hostReadiness: {
                            if (!root.appHost) return 0;
                            return root.appHost.loaderCount * 1000
                                + Object.keys(root.appHost.tabProviders).length;
                        }
                        onHostReadinessChanged: mountApp()
                        Component.onCompleted: mountApp()

                        function mountApp() {
                            if (!root.appHost) return;
                            root.mountTab("ai", aiAppSurface);
                        }
                    }
                }

                Item {
                    id: tabPaneWorkspaces
                    readonly property int myIndex: root.tabIndex("workspaces")
                    x: myIndex >= 0 ? myIndex * tabContentContainer.width : tabContentContainer.width * 4
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: wsAppSurface.children.length > 0
                        ? Math.max(wsAppSurface.children[0].implicitHeight, 320) : 320
                    clip: true
                    visible: (myIndex >= 0 ? tabContentContainer.activeTabIndex === myIndex : tabContentContainer.activeTabIndex === 4) || tabSlider.isAnimating

                    Item {
                        id: wsApp
                        width: parent.width
                        height: parent.height

                        /// The app's item lives here, so the pane can also hold a hint.
                        Item {
                            id: wsAppSurface
                            anchors.fill: parent
                        }

                        AppUnavailableHint {
                            id: wsAppHint
                            anchors.fill: parent
                            appName: "Workspaces"
                            readonly property var status: root.hostTabStatus("workspaces")
                            visible: !status.available
                            reason: status.reason
                        }

                        readonly property int hostReadiness: {
                            if (!root.appHost) return 0;
                            return root.appHost.loaderCount * 1000
                                + Object.keys(root.appHost.tabProviders).length;
                        }
                        onHostReadinessChanged: mountApp()
                        Component.onCompleted: mountApp()

                        function mountApp() {
                            root.mountTab("workspaces", wsAppSurface);
                        }
                    }
                }

                Item {
                    id: tabPaneDownloads
                    readonly property int myIndex: root.tabIndex("downloads")
                    x: myIndex >= 0 ? myIndex * tabContentContainer.width : tabContentContainer.width * 5
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: dlAppHostSurface.children.length > 0
                        ? Math.max(dlAppHostSurface.children[0].implicitHeight, 320) : 320
                    clip: true
                    visible: (myIndex >= 0 ? tabContentContainer.activeTabIndex === myIndex : tabContentContainer.activeTabIndex === 5) || tabSlider.isAnimating

                    Item {
                        id: dlAppHost
                        width: parent.width
                        height: parent.height

                        /// The app's item lives here, so the pane can also hold a hint.
                        Item {
                            id: dlAppHostSurface
                            anchors.fill: parent
                        }

                        AppUnavailableHint {
                            id: dlAppHostHint
                            anchors.fill: parent
                            appName: "Downloads"
                            readonly property var status: root.hostTabStatus("downloads")
                            visible: !status.available
                            reason: status.reason
                        }

                        readonly property int hostReadiness: {
                            if (!root.appHost) return 0;
                            return root.appHost.loaderCount * 1000
                                + Object.keys(root.appHost.tabProviders).length;
                        }
                        onHostReadinessChanged: mountApp()
                        Component.onCompleted: mountApp()

                        function mountApp() {
                            if (!root.appHost) return;
                            root.mountTab("downloads", dlAppHostSurface);
                        }
                    }
                }
            }
        }
    }
}
