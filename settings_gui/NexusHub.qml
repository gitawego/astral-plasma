import QtQuick
import QtQuick.Layouts
import "../theme"
import "../components"
import "../config"
import "pages"

Item {
    id: root

    property bool testMode: false
    property string activePage: (typeof Config !== "undefined" && Config.activeSettingsPage) ? Config.activeSettingsPage : "wallpaper"
    property var pageHistory: []

    signal closeRequested()

    implicitWidth: 800
    implicitHeight: 560

    function navigateTo(pageId) {
        if (!pageId || pageId === activePage) return;
        let h = pageHistory.slice();
        h.push(activePage);
        pageHistory = h;
        activePage = pageId;
        if (typeof Config !== "undefined") {
            Config.activeSettingsPage = pageId;
        }
    }

    function goBack() {
        if (pageHistory.length > 0) {
            let h = pageHistory.slice();
            const prev = h.pop();
            pageHistory = h;
            activePage = prev;
            if (typeof Config !== "undefined") {
                Config.activeSettingsPage = prev;
            }
        }
    }

    function scrollTo(y) {
        pageFlickable.contentY = y;
    }

    readonly property bool canGoBack: pageHistory.length > 0

    // Categories structure
    readonly property var navigationSections: [
        {
            title: "Personalization",
            items: [
                { id: "wallpaper", label: "Wallpaper & Style", icon: "wallpaper" },
                { id: "theme", label: "Appearance", icon: "palette" }
            ]
        },
        {
            title: "Connectivity",
            items: [
                { id: "network", label: "Wi-Fi & Network", icon: "wifi" },
                { id: "bluetooth", label: "Bluetooth", icon: "bluetooth" },
                { id: "ai", label: "AI Token Plans", icon: "psychology" }
            ]
        },
        {
            title: "Hardware",
            items: [
                { id: "audio", label: "Sound & Audio", icon: "volume_up" }
            ]
        },
        {
            title: "Desktop Shell",
            items: [
                { id: "dock", label: "Dock & Layout", icon: "dashboard" },
                { id: "status", label: "Status Icons", icon: "tune" },
                { id: "dashboard", label: "Dashboard Tabs", icon: "calendar_month" }
            ]
        },
        {
            title: "System",
            items: [
                { id: "system", label: "System & Services", icon: "memory" }
            ]
        }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Navigation Sidebar
        Rectangle {
            Layout.preferredWidth: 250
            Layout.minimumWidth: 250
            Layout.fillHeight: true
            color: Colors.glassCard
            radius: Theme.radiusMedium
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.padLarge
                spacing: Theme.spaceMedium

                // Hub Header & Drag Handle
                Item {
                    Layout.fillWidth: true
                    height: 32
                    clip: true

                    RowLayout {
                        anchors.fill: parent
                        spacing: Theme.spaceSmall

                        MaterialIcon {
                            text: "tune"
                            size: 22
                            color: Colors.primary
                        }

                        Text {
                            text: "Nexus Settings"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontTitleSmall
                            font.weight: Font.Bold
                            color: Colors.m3onSurface
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        MaterialIcon {
                            text: "drag_indicator"
                            size: 18
                            color: hubHeaderHover.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                            opacity: hubHeaderHover.containsMouse ? 1.0 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: hubHeaderHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.OpenHandCursor
                        acceptedButtons: Qt.NoButton
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                }

                // Categorized Navigation List
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: navCol.implicitHeight
                    clip: true

                    Column {
                        id: navCol
                        width: parent.width
                        spacing: 12

                        Repeater {
                            model: root.navigationSections
                            delegate: Column {
                                required property var modelData
                                width: parent.width
                                spacing: 4

                                // Section Title
                                Text {
                                    text: modelData.title.toUpperCase()
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Colors.m3onSurfaceVariant
                                    leftPadding: 8
                                    topPadding: 4
                                    bottomPadding: 2
                                }

                                Repeater {
                                    model: modelData.items
                                    delegate: PillButton {
                                        required property var modelData
                                        width: parent.width
                                        label: modelData.label
                                        iconText: modelData.icon
                                        active: root.activePage === modelData.id
                                        onClicked: root.navigateTo(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                }

                // Close Button
                PillButton {
                    Layout.fillWidth: true
                    label: "Close"
                    iconText: "close"
                    active: false
                    onClicked: root.closeRequested()
                }
            }
        }

        // Right Content Pane with Breadcrumb Drill-down Header
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.padExtraLarge
                spacing: Theme.spaceMedium

                // Breadcrumb Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.canGoBack

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: backHover.containsMouse ? Colors.pillHover : "transparent"
                        border.color: Theme.borderSubtle
                        border.width: 1
                        z: 10

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            size: 16
                            color: Colors.m3onSurface
                        }

                        MouseArea {
                            id: backHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.goBack()
                        }
                    }

                    Text {
                        text: "Back"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        font.weight: Font.DemiBold
                        color: Colors.primary
                    }

                    Item { Layout.fillWidth: true }
                }

                // Page Scrollable Content Container
                Flickable {
                    id: pageFlickable
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: Math.max(height, pageLoader.item ? pageLoader.item.implicitHeight : pageLoader.implicitHeight)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        target: pageFlickable
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            pageFlickable.contentY = Math.max(0, Math.min(pageFlickable.contentHeight - pageFlickable.height, pageFlickable.contentY - event.angleDelta.y));
                        }
                    }

                    Loader {
                        id: pageLoader
                        width: parent.width
                        height: item ? item.implicitHeight : implicitHeight
                        sourceComponent: {
                            switch (root.activePage) {
                                case "wallpaper":
                                case "wallpaper_style": return wallpaperPageComp;
                                case "theme":
                                case "appearance": return themePageComp;
                                case "network": return networkPageComp;
                                case "bluetooth": return bluetoothPageComp;
                                case "ai": return aiPageComp;
                                case "audio": return audioPageComp;
                                case "dock": return dockPageComp;
                                case "status": return statusPageComp;
                                case "dashboard": return dashPageComp;
                                case "system": return systemPageComp;
                                default: return wallpaperPageComp;
                            }
                        }
                    }

                    // Slim Material 3 Scroll Indicator
                    Rectangle {
                        id: scrollBarIndicator
                        anchors.right: parent.right
                        anchors.rightMargin: 3
                        y: pageFlickable.contentY + (pageFlickable.contentHeight > pageFlickable.height 
                            ? (pageFlickable.contentY / pageFlickable.contentHeight) * pageFlickable.height 
                            : 0)
                        width: 4
                        height: pageFlickable.contentHeight > pageFlickable.height 
                            ? Math.max(28, (pageFlickable.height / pageFlickable.contentHeight) * pageFlickable.height) 
                            : 0
                        radius: 2
                        color: Colors.primary
                        opacity: pageFlickable.moving || pageFlickable.contentHeight > pageFlickable.height ? 0.45 : 0.0
                        visible: pageFlickable.contentHeight > pageFlickable.height
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }
        }
    }

    // Lazy Loaded Page Components
    Component { id: wallpaperPageComp; WallpaperAndStylePage { testMode: root.testMode } }
    Component { id: themePageComp; ThemePage {} }
    Component { id: networkPageComp; NetworkPage { testMode: root.testMode } }
    Component { id: bluetoothPageComp; BluetoothPage { testMode: root.testMode } }
    Component { id: aiPageComp; AiPage { testMode: root.testMode } }
    Component { id: audioPageComp; AudioPage { testMode: root.testMode } }
    Component { id: dockPageComp; DockPage {} }
    Component { id: statusPageComp; StatusIconsPage {} }
    Component { id: dashPageComp; DashboardPage {} }
    Component { id: systemPageComp; SystemPage { testMode: root.testMode } }
}
