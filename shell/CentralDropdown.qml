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
    property real dropH: 520
    property bool isOpen: (typeof Config !== "undefined") ? Config.dashboardVisible : false
    readonly property real currentDropH: dropH * offsetProgress
    property real offsetProgress: isOpen ? 1.0 : 0.0

    property bool hoverOverrideActive: false
    property bool hoverOverride: false
    readonly property bool isHovered: hoverOverrideActive ? hoverOverride : dropdownHover.hovered

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
        root.isOpen = false;
        if (typeof Config !== "undefined") Config.dashboardVisible = false;
    }

    HoverHandler {
        id: dropdownHover
    }

    readonly property var tabs: [
        { id: "dashboard", label: "Dashboard", icon: "dashboard" },
        { id: "media", label: "Media", icon: "queue_music" },
        { id: "performance", label: "Performance", icon: "speed" },
        { id: "workspaces", label: "Workspaces", icon: "grid_view" }
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
            Rectangle {
                id: settingsBtn
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 38
                radius: Theme.radiusGlassItem
                color: settingsHover.containsMouse ? Colors.glassPillHover : Colors.glassPill
                border.color: settingsHover.containsMouse ? Colors.glassBorderSpecular : Colors.glassBorderSubtle
                border.width: 1

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "settings"
                    size: 18
                    color: settingsHover.containsMouse ? "#FFFFFF" : Qt.alpha("#FFFFFF", 0.70)
                }

                MouseArea {
                    id: settingsHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Config.dashboardVisible = false;
                        Config.openSettings();
                    }
                }

                // Tooltip
                Rectangle {
                    z: 100
                    visible: settingsHover.containsMouse
                    anchors.top: parent.bottom
                    anchors.topMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: settingsTip.implicitWidth + 16
                    implicitHeight: settingsTip.implicitHeight + 8
                    radius: 6
                    color: Colors.glassModalSurface
                    border.color: Colors.glassBorderSubtle
                    border.width: 1

                    Text {
                        id: settingsTip
                        anchors.centerIn: parent
                        text: "Theme Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: "#FFFFFF"
                    }
                }
            }

            Row {
                id: tabsRow
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Repeater {
                    id: tabRepeater
                    model: root.tabs

                    delegate: Rectangle {
                        id: tabItem
                        required property var modelData
                        required property int index
                        readonly property bool isSelected: Config.activeDashboardTab === modelData.id

                        width: 160
                        height: 42
                        radius: Theme.radiusGlassItem
                        color: isSelected 
                            ? Colors.glassPillActive 
                            : (tabHover.containsMouse ? Colors.glassPillHover : "transparent")
                        border.color: isSelected 
                            ? Colors.glassBorderSpecular 
                            : (tabHover.containsMouse ? Colors.glassBorderSubtle : "transparent")
                        border.width: 1

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.animExpressiveFastEffects
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveFastEffects
                            }
                        }

                        // Subtle top specular gleam on selected tab
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 0.5
                            anchors.left: parent.left
                            anchors.leftMargin: parent.radius * 0.4
                            anchors.right: parent.right
                            anchors.rightMargin: parent.radius * 0.4
                            height: 1
                            color: Colors.glassBorderSpecular
                            visible: isSelected
                            opacity: 0.8
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon
                                size: 18
                                color: isSelected ? "#FFFFFF" : (tabHover.containsMouse ? "#FFFFFF" : Qt.alpha("#FFFFFF", 0.65))
                                Behavior on color {
                                    ColorAnimation { duration: Theme.animExpressiveFastEffects }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: 12
                                font.weight: isSelected ? Font.DemiBold : Font.Normal
                                font.family: Theme.fontFamily
                                color: isSelected ? "#FFFFFF" : (tabHover.containsMouse ? "#FFFFFF" : Qt.alpha("#FFFFFF", 0.65))
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
        }

        // Header Separator with subtle glass border
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Colors.glassBorderSubtle
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
