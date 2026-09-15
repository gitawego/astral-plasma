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

        // Tabs Header with Fluid Sliding Indicator
        Item {
            id: tabsHeader
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: tabsRow.implicitWidth
            implicitHeight: 60

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
                        color: tabHover.containsMouse ? Qt.alpha(Colors.textMain, 0.04) : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.animExpressiveFastEffects
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveFastEffects
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 3

                            MaterialIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                size: 20
                                color: isSelected ? Colors.primary : (tabHover.containsMouse ? Colors.primary : Colors.onSurfaceVariant)
                                Behavior on color {
                                    ColorAnimation { duration: Theme.animExpressiveFastEffects }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.family: Theme.fontFamily
                                color: isSelected ? Colors.primary : (tabHover.containsMouse ? Colors.primary : Colors.onSurfaceVariant)
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
                height: 2
                radius: 1
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
                readonly property real targetWidth: 60
                readonly property real targetX: activeTabItem ? (tabsRow.x + activeTabItem.x + (activeTabItem.width - targetWidth) / 2) : 0

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

        // Header Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.borderSubtle
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

                Item {
                    id: tabPane0
                    x: 0
                    width: tabContentContainer.width
                    height: implicitHeight
                    implicitHeight: dashTab.implicitHeight

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
