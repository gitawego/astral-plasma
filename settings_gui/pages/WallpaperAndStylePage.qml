import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../config"
import "../../services"

SettingsPage {
    id: root
    spacing: Theme.spaceLarge
    width: parent ? parent.width : 600

    title: "Wallpaper & Style"
    subtitle: "Material 3 Expressive palettes, live previews & motion wallpapers"
    // Zones in document order: the showcase, the palette, the mode, the gallery.
    zones: [
        { id: "wallpaper", label: "Wallpaper", anchor: showcaseSection },
        { id: "palette", label: "Accent", anchor: paletteSection },
        { id: "mode", label: "Mode", anchor: modeSection },
        { id: "gallery", label: "Gallery", anchor: gallerySection }
    ]

    property bool testMode: false
    property var testWallpapers: []

    readonly property var wallpapersList: {
        if (testMode && testWallpapers.length > 0) return testWallpapers;
        if (typeof WallpaperEngine !== "undefined" && WallpaperEngine.wallpapers) {
            return WallpaperEngine.wallpapers;
        }
        return [];
    }

    readonly property string currentPath: {
        if (typeof WallpaperEngine !== "undefined" && WallpaperEngine.effectiveWallpaper) {
            return WallpaperEngine.effectiveWallpaper;
        }
        return "/usr/share/wallpapers/cachyos-wallpapers/splash.png";
    }

    readonly property bool isVideo: {
        if (typeof WallpaperEngine !== "undefined") return WallpaperEngine.isVideo;
        return false;
    }

    // Active Wallpaper Showcase Card
    Rectangle {
        id: showcaseSection
        Layout.fillWidth: true
        Layout.preferredHeight: 180
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        clip: true

        // Background Image preview
        Image {
            anchors.fill: parent
            source: root.currentPath ? (root.currentPath.startsWith("file://") ? root.currentPath : ("file://" + root.currentPath)) : ""
            fillMode: Image.PreserveAspectCrop
            opacity: 0.65
            asynchronous: true
        }

        // Dark gradient overlay for text readability
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.4) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.85) }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: Theme.spaceMedium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Row {
                    spacing: 8
                    Rectangle {
                        height: 22
                        implicitWidth: typeLabel.implicitWidth + 16
                        radius: 11
                        color: Colors.primary
                        Text {
                            id: typeLabel
                            anchors.centerIn: parent
                            text: root.isVideo ? "DYNAMIC VIDEO" : "HIGH RES WALLPAPER"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Colors.onPrimary
                        }
                    }
                    Rectangle {
                        height: 22
                        implicitWidth: dynLabel.implicitWidth + 16
                        radius: 11
                        color: Colors.surfaceContainerHighest
                        border.color: Theme.borderSubtle
                        border.width: 1
                        Text {
                            id: dynLabel
                            anchors.centerIn: parent
                            text: "MATUGEN SYNCED"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Colors.primary
                        }
                    }
                }

                Text {
                    text: {
                        const parts = root.currentPath.split("/");
                        return parts[parts.length - 1] || "Default Wallpaper";
                    }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.Bold
                    color: "white"
                    elide: Text.ElideRight
                }

                Text {
                    text: root.currentPath
                    font.family: Theme.fontMonospace
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.7)
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }

            // Quick Launcher Button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 44
                height: 44
                radius: 22
                color: openCarouselHover.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                border.color: Theme.borderSubtle
                border.width: 1

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "view_carousel"
                    size: 20
                    color: openCarouselHover.containsMouse ? Colors.onPrimary : Colors.m3onSurface
                }

                MouseArea {
                    id: openCarouselHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof Config !== "undefined") {
                            Config.commandLauncherVisible = true;
                        }
                    }
                }
            }
        }
    }

    // Color Scheme Presets Row
    ColumnLayout {
        id: paletteSection
        Layout.fillWidth: true
        spacing: 8

        SectionHeader {
            title: "Accent Color Scheme"
            eyebrow: (typeof Config !== "undefined" && Config.dynamicColors)
                ? "dynamic · derived from the wallpaper"
                : "preset · " + ((typeof Config !== "undefined" && Config.themePreset) ? Config.themePreset : "iris")
        }

        Row {
            spacing: 10
            readonly property var presets: [
                { name: "Dynamic", key: "dynamic", isDynamic: true, col: Colors.primary },
                { name: "Iris", key: "iris", isDynamic: false, col: "#cba6f7" },
                { name: "Ocean", key: "ocean", isDynamic: false, col: "#89b4fa" },
                { name: "Coral", key: "coral", isDynamic: false, col: "#fab387" },
                { name: "Emerald", key: "emerald", isDynamic: false, col: "#a6e3a1" }
            ]

            Repeater {
                model: parent.presets
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool isActive: modelData.isDynamic
                        ? ((typeof Config !== "undefined") ? Config.dynamicColors : false)
                        : ((typeof Config !== "undefined") && !Config.dynamicColors && Config.themePreset === modelData.key)
                    height: 36
                    implicitWidth: pRow.implicitWidth + 24
                    radius: 18
                    color: isActive ? Qt.alpha(modelData.col, 0.25) : (presetHover.containsMouse ? Colors.pillHover : Colors.surfaceContainer)
                    border.color: isActive ? modelData.col : Theme.borderSubtle
                    border.width: isActive ? 2 : 1

                    Row {
                        id: pRow
                        anchors.centerIn: parent
                        spacing: 8
                        Item {
                            width: 14; height: 14
                            anchors.verticalCenter: parent.verticalCenter

                            // Dynamic Wallpaper gradient circle
                            Rectangle {
                                anchors.fill: parent
                                radius: 7
                                visible: modelData.isDynamic
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#f38ba8" }
                                    GradientStop { position: 0.5; color: "#89b4fa" }
                                    GradientStop { position: 1.0; color: "#a6e3a1" }
                                }
                            }

                            // Preset solid color circle
                            Rectangle {
                                anchors.fill: parent
                                radius: 7
                                visible: !modelData.isDynamic
                                color: modelData.col
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: isActive ? Font.Bold : Font.Normal
                            color: Colors.m3onSurface
                        }
                    }

                    MouseArea {
                        id: presetHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (typeof Config !== "undefined") {
                                if (modelData.isDynamic) {
                                    Config.setDynamicColors(true);
                                } else {
                                    Config.setThemePreset(modelData.key);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Dark Mode / Light Mode Chooser
    ColumnLayout {
        id: modeSection
        Layout.fillWidth: true
        spacing: 8

        SectionHeader {
            title: "Appearance Mode"
            eyebrow: ((typeof Config !== "undefined" ? Config.isDarkMode : true) ? "dark" : "light") + " mode active"
        }

        Row {
            spacing: 12

            Rectangle {
                id: darkBtn
                readonly property bool isDark: (typeof Config !== "undefined" ? Config.isDarkMode : true)
                height: 38
                implicitWidth: 130
                radius: 19
                color: darkBtn.isDark ? Colors.primary : Colors.surfaceContainer
                border.color: darkBtn.isDark ? Colors.primary : Theme.borderSubtle
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialIcon {
                        text: "dark_mode"
                        size: 18
                        color: darkBtn.isDark ? Colors.onPrimary : Colors.m3onSurfaceVariant
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Dark Mode"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: darkBtn.isDark ? Font.Bold : Font.Normal
                        color: darkBtn.isDark ? Colors.onPrimary : Colors.m3onSurface
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof Config !== "undefined") Config.setDarkMode(true);
                    }
                }
            }

            Rectangle {
                id: lightBtn
                readonly property bool isLight: (typeof Config !== "undefined" ? !Config.isDarkMode : false)
                height: 38
                implicitWidth: 130
                radius: 19
                color: lightBtn.isLight ? Colors.primary : Colors.surfaceContainer
                border.color: lightBtn.isLight ? Colors.primary : Theme.borderSubtle
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialIcon {
                        text: "light_mode"
                        size: 18
                        color: lightBtn.isLight ? Colors.onPrimary : Colors.m3onSurfaceVariant
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Light Mode"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: lightBtn.isLight ? Font.Bold : Font.Normal
                        color: lightBtn.isLight ? Colors.onPrimary : Colors.m3onSurface
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof Config !== "undefined") Config.setDarkMode(false);
                    }
                }
            }
        }
    }

    // Quick Wallpapers Grid
    ColumnLayout {
        id: gallerySection
        Layout.fillWidth: true
        spacing: 8

        SectionHeader {
            title: "Quick Wallpapers"
            eyebrow: root.wallpapersList.length + " available"
        }

        Flow {
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: root.wallpapersList.slice(0, 8)
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: 120
                    height: 75
                    radius: Theme.radiusSmall
                    color: Colors.surfaceContainerHigh
                    border.color: (root.currentPath === modelData.path) ? Colors.primary : Theme.borderSubtle
                    border.width: (root.currentPath === modelData.path) ? 2 : 1
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: {
                            const p = modelData.thumbnail_path || modelData.path || "";
                            if (!p) return "";
                            return p.startsWith("file://") ? p : ("file://" + p);
                        }
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: gridCardHover.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                    }

                    MouseArea {
                        id: gridCardHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.testMode && typeof WallpaperEngine !== "undefined" && WallpaperEngine.setWallpaper) {
                                WallpaperEngine.setWallpaper(modelData.path);
                            }
                        }
                    }
                }
            }
        }
    }
}
