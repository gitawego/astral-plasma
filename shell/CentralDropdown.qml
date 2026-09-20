import QtQuick
import QtQuick.Layouts
import "../theme"
import "../config"
import "../components"
import "../dashboard/tabs"

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
            duration: Theme.animExpressiveDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
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
    }

    property bool hoverOverrideActive: false
    property bool hoverOverride: false
    readonly property bool isHovered: hoverOverrideActive ? hoverOverride : dropdownHover.hovered

    readonly property alias layoutItem: cardLayout
    readonly property alias settingsBtnItem: settingsBtn
    readonly property alias tabRepeaterItem: tabRepeater
    readonly property alias tabSlidingIndicatorItem: tabSlidingIndicator

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

    readonly property var tabs: [
        { id: "dashboard", label: "Dashboard", icon: "grid_view" },
        { id: "media", label: "Media", icon: "queue_music" },
        { id: "performance", label: "Performance", icon: "speed" },
        { id: "workspaces", label: "Workspaces", icon: "workspaces" }
    ]

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
                    radius: 6
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

            Row {
                id: tabsRow
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Repeater {
                    id: tabRepeater
                    model: root.tabs

                    delegate: Rectangle {
                        id: tabItem
                        required property var modelData
                        required property int index
                        readonly property bool isSelected: Config.activeDashboardTab === modelData.id

                        width: 175
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
                                color: isSelected ? Colors.primary : (tabHover.containsMouse ? Colors.primary : Colors.textMain)
                                Behavior on color {
                                    ColorAnimation { duration: Theme.animExpressiveFastEffects }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.pixelSize: 12
                                font.weight: isSelected ? Font.Bold : Font.DemiBold
                                font.family: Theme.fontFamily
                                color: isSelected ? Colors.primary : (tabHover.containsMouse ? Colors.primary : Colors.textMain)
                                Behavior on color {
                                    ColorAnimation { duration: Theme.animExpressiveFastEffects }
                                }
                            }
                        }

                        MouseArea {
                            id: tabHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.activeDashboardTab = modelData.id
                        }
                    }
                }
            }

            // Fluid Sliding Underline Indicator
            Rectangle {
                id: tabSlidingIndicator
                anchors.bottom: parent.bottom
                height: 3
                radius: 1.5
                color: Colors.primary

                readonly property int activeIdx: {
                    switch (Config.activeDashboardTab) {
                        case "dashboard": return 0;
                        case "media": return 1;
                        case "performance": return 2;
                        case "workspaces": return 3;
                        default: return 0;
                    }
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
                switch (Config.activeDashboardTab) {
                    case "dashboard": return tabPane0.implicitHeight;
                    case "media": return tabPane1.implicitHeight;
                    case "performance": return tabPane2.implicitHeight;
                    case "workspaces": return tabPane3.implicitHeight;
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
                switch (Config.activeDashboardTab) {
                    case "dashboard": return 0;
                    case "media": return 1;
                    case "performance": return 2;
                    case "workspaces": return 3;
                    default: return 0;
                }
            }

            Item {
                id: tabSlider
                width: tabContentContainer.width * 4
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
            }
        }
    }
}
