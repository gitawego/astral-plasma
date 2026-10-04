import QtQuick
import QtQuick.Layouts
import "../theme"
import "../config"
import "../components"
import "../dashboard/tabs"
import "../dashboard/tabs/DashboardTabs.js" as DashboardTabs
import "../services"

Item {
    id: root

    property real dropX: (parent.width - dropW) / 2
    property real dropW: (typeof Config !== "undefined" && Config.dashboardWidth) ? Config.dashboardWidth : 980
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

    property bool isOpen: (typeof Config !== "undefined" && Config.dashboardVisible !== undefined) ? Config.dashboardVisible : false
    readonly property real currentDropH: dropH * offsetProgress
    property real offsetProgress: isOpen ? 1.0 : 0.0

    Connections {
        target: (typeof Config !== "undefined" && Config.dashboardVisible !== undefined) ? Config : null
        function onDashboardVisibleChanged() {
            if (typeof Config !== "undefined" && Config.dashboardVisible !== undefined) {
                root.isOpen = Config.dashboardVisible;
            }
        }
        function onActiveDashboardTabChanged() {
            if (typeof Config !== "undefined" && Config.activeDashboardTab && root.activeTab !== Config.activeDashboardTab) {
                root.activeTab = Config.activeDashboardTab;
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
    readonly property var visibleTabs: DashboardTabs.availableTabs(Config.dashboardTabs, root.ariaAvailable)

    /// The selected tab, falling back to one that is actually rendered: the
    /// stored preference can point at a hidden tab (it was disabled, or the
    /// engine went away), and a view left on a tab with no chip is a view the
    /// user cannot leave.
    property string activeTab: DashboardTabs.fallbackActiveTab(root.visibleTabs, (typeof Config !== "undefined" && Config.activeDashboardTab) ? Config.activeDashboardTab : "dashboard")
    onActiveTabChanged: {
        // Only a *selected* tab is worth persisting. Writing the fallback back
        // would overwrite the user's choice with the fallback and lose it as soon
        // as the tab becomes available again.
        if (typeof Config === "undefined" || Config.activeDashboardTab === undefined) return;
        if (!root.visibleTabs.some(t => t.id === root.activeTab)) return;
        if (Config.activeDashboardTab !== activeTab) {
            Config.activeDashboardTab = activeTab;
        }
    }

    property bool hoverOverrideActive: false
    property bool hoverOverride: false
    readonly property bool isHovered: hoverOverrideActive ? hoverOverride : dropdownHover.hovered

    readonly property alias layoutItem: cardLayout
    readonly property alias settingsBtnItem: settingsBtn
    readonly property alias tabRepeaterItem: tabRepeater
    readonly property alias tabSlidingIndicatorItem: tabSlidingIndicator
    readonly property alias tabsRowItem: tabsRow
    readonly property alias tabContentContainerItem: tabContentContainer
    readonly property alias tabSliderItem: tabSlider
    readonly property alias downloadsTabItem: dlTab

    // Keyboard contract for the shell's layer surface: while a tab captures
    // text (the Downloads add sheet), UnifiedShell requests compositor
    // keyboard focus. A new text-capturing tab must OR its state in here.
    readonly property bool textInputActive: dlTab.addDialogOpen

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
        if (typeof Config !== "undefined") {
            Config.dashboardVisible = false;
        } else {
            root.isOpen = false;
        }
    }

    HoverHandler {
        id: dropdownHover
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
                    Config.dashboardVisible = false;
                    Config.openSettings();
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
                                text: modelData.icon
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
                                text: modelData.label
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
                                if (typeof Config !== "undefined") {
                                    Config.activeDashboardTab = modelData.id;
                                }
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
                    case "dashboard": return tabPane0.implicitHeight;
                    case "media": return tabPane1.implicitHeight;
                    case "performance": return tabPane2.implicitHeight;
                    case "workspaces": return tabPane3.implicitHeight;
                    case "downloads": return tabPane4.implicitHeight;
                    case "ai": return tabPane5.implicitHeight;
                    default: return tabPane0.implicitHeight;
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
                switch (root.activeTab) {
                    case "dashboard": return 0;
                    case "media": return 1;
                    case "performance": return 2;
                    case "workspaces": return 3;
                    case "downloads": return 4;
                    case "ai": return 5;
                    default: return 0;
                }
            }

            Item {
                id: tabSlider
                width: tabContentContainer.width * 6
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
                    id: tabPane0
                    x: 0
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: dashTab.implicitHeight
                    clip: true
                    visible: tabContentContainer.activeTabIndex === 0 || tabSlider.isAnimating

                    DashboardTab {
                        id: dashTab
                        width: parent.width
                        height: parent.height
                    }
                }

                Item {
                    id: tabPane1
                    x: tabContentContainer.width
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: mediaTab.implicitHeight
                    clip: true
                    visible: tabContentContainer.activeTabIndex === 1 || tabSlider.isAnimating

                    MediaTab {
                        id: mediaTab
                        width: parent.width
                        height: parent.height
                    }
                }

                Item {
                    id: tabPane2
                    x: tabContentContainer.width * 2
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: perfTab.implicitHeight
                    clip: true
                    visible: tabContentContainer.activeTabIndex === 2 || tabSlider.isAnimating

                    PerformanceTab {
                        id: perfTab
                        width: parent.width
                        height: parent.height
                    }
                }

                Item {
                    id: tabPane3
                    x: tabContentContainer.width * 3
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: wsTab.implicitHeight
                    clip: true
                    visible: tabContentContainer.activeTabIndex === 3 || tabSlider.isAnimating

                    WorkspacesTab {
                        id: wsTab
                        width: parent.width
                        height: parent.height
                    }
                }

                Item {
                    id: tabPane4
                    x: tabContentContainer.width * 4
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: dlTab.implicitHeight
                    clip: true
                    visible: tabContentContainer.activeTabIndex === 4 || tabSlider.isAnimating

                    DownloadsTab {
                        id: dlTab
                        width: parent.width
                        height: parent.height
                    }
                }

                Item {
                    id: tabPane5
                    x: tabContentContainer.width * 5
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: aiTab.implicitHeight
                    clip: true
                    visible: tabContentContainer.activeTabIndex === 5 || tabSlider.isAnimating

                    AiTab {
                        id: aiTab
                        width: parent.width
                        height: parent.height
                    }
                }
            }
        }
    }
}
