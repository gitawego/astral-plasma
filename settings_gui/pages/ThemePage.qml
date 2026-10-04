import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"

SettingsPage {
    id: root

    title: "Theming & Appearance"
    subtitle: "Customize desktop aesthetics, switch between Light and Dark mode, and choose dynamic or preset color palettes."
    // Zones in document order: style, colors, shape, the live preview.
    zones: [
        { id: "style", label: "Style", anchor: styleHeader },
        { id: "colors", label: "Colors", anchor: colorsHeader },
        { id: "shape", label: "Shape", anchor: shapeHeader },
        { id: "preview", label: "Preview", anchor: previewHeader }
    ]

    property bool testMode: false
    property bool testDarkMode: true
    property bool testDynamicColors: false
    property string testPreset: "iris"
    property int testCornerRadius: 20
    property string testArchetype: "liquid_glass"
    property real testBlurStrength: 0.85

    readonly property bool isDark: testMode
        ? testDarkMode
        : ((typeof Config !== "undefined" && Config.isDarkMode !== undefined) ? Config.isDarkMode : true)

    readonly property bool isDynamic: testMode
        ? testDynamicColors
        : ((typeof Config !== "undefined" && Config.dynamicColors !== undefined) ? Config.dynamicColors : false)

    readonly property string presetName: testMode
        ? testPreset
        : ((typeof Config !== "undefined" && Config.themePreset !== undefined) ? Config.themePreset : "iris")

    readonly property int cornerRad: testMode
        ? testCornerRadius
        : ((typeof Config !== "undefined" && Config.themeCornerRadius !== undefined) ? Config.themeCornerRadius : 20)

    readonly property string currentArchetype: testMode
        ? testArchetype
        : ((typeof Config !== "undefined" && Config.themeArchetype) ? Config.themeArchetype : "liquid_glass")

    readonly property real blurStrengthVal: testMode
        ? testBlurStrength
        : ((typeof Config !== "undefined" && Config.themeBlurStrength !== undefined) ? Config.themeBlurStrength : 0.85)

    // Robust token fallbacks for offscreen testing where Theme/Colors singletons may be partially loaded
    readonly property color colPrimary: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : (isDark ? "#CFBCFF" : "#6750A4")
    readonly property color colOnPrimary: (typeof Colors !== "undefined" && Colors.onPrimary) ? Colors.onPrimary : (isDark ? "#381E72" : "#FFFFFF")
    readonly property color colPrimaryContainer: (typeof Colors !== "undefined" && Colors.primaryContainer) ? Colors.primaryContainer : (isDark ? "#4F378B" : "#EADDFF")
    readonly property color colOnPrimaryContainer: (typeof Colors !== "undefined" && Colors.m3onPrimaryContainer) ? Colors.m3onPrimaryContainer : (isDark ? "#EADDFF" : "#21005D")
    readonly property color colSecondary: (typeof Colors !== "undefined" && Colors.secondary) ? Colors.secondary : (isDark ? "#CBC2DB" : "#625B71")
    readonly property color colTertiary: (typeof Colors !== "undefined" && Colors.tertiary) ? Colors.tertiary : (isDark ? "#EFB8C8" : "#7D5260")
    readonly property color colSurface: (typeof Colors !== "undefined" && Colors.surface) ? Colors.surface : (isDark ? "#141218" : "#FEF7FF")
    readonly property color colSurfaceContainer: (typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : (isDark ? "#1D1B20" : "#F2EDE7")
    readonly property color colSurfaceContainerHigh: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : (isDark ? "#2B2930" : "#E8E2DC")
    readonly property color colSurfaceContainerHighest: (typeof Colors !== "undefined" && Colors.surfaceContainerHighest) ? Colors.surfaceContainerHighest : (isDark ? "#36343B" : "#DDD7D1")
    readonly property color colOnSurface: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : (isDark ? "#F3EDF6" : "#231917")
    readonly property color colOnSurfaceVariant: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : (isDark ? "#E1DBE7" : "#524340")
    readonly property color colBorderSubtle: (typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : (isDark ? "#44464F" : "#D6CEC5")
    readonly property color colPillHover: (typeof Colors !== "undefined" && Colors.pillHover) ? Colors.pillHover : (isDark ? "#33ffffff" : "#1a000000")
    readonly property color colOutlineVariant: (typeof Colors !== "undefined" && Colors.outlineVariant) ? Colors.outlineVariant : (isDark ? "#49454F" : "#C4C7C5")

    readonly property int valRadiusMedium: (typeof Theme !== "undefined" && Theme.radiusMedium !== undefined) ? Theme.radiusMedium : 16
    readonly property int valRadiusFull: (typeof Theme !== "undefined" && Theme.radiusFull !== undefined) ? Theme.radiusFull : 9999
    readonly property int valRadiusPill: (typeof Theme !== "undefined" && Theme.radiusGlassPill !== undefined) ? Theme.radiusGlassPill : 9999
    readonly property int valRadiusCard: (typeof Theme !== "undefined" && Theme.radiusGlassCard !== undefined) ? Theme.radiusGlassCard : 18
    readonly property int valRadiusItem: (typeof Theme !== "undefined" && Theme.radiusGlassItem !== undefined) ? Theme.radiusGlassItem : 12
    readonly property int valPadLarge: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16
    readonly property int valPadMedium: (typeof Theme !== "undefined" && Theme.padMedium) ? Theme.padMedium : 12
    readonly property int valSpaceMedium: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12
    readonly property int valSpaceSmall: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 8
    readonly property int valAnimMedium: (typeof Theme !== "undefined" && Theme.animDurationMedium) ? Theme.animDurationMedium : 250
    readonly property int valAnimFast: (typeof Theme !== "undefined" && Theme.animDurationFast) ? Theme.animDurationFast : 150
    readonly property string valFontFamily: (typeof Theme !== "undefined" && Theme.surfaceStyle === "neon_cyber" && Theme.fontMonospace)
        ? Theme.fontMonospace
        : ((typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif")

    function setDarkMode(val) {
        if (testMode) {
            testDarkMode = val;
        } else if (typeof Config !== "undefined" && Config.setDarkMode) {
            Config.setDarkMode(val);
        }
    }

    function setDynamicColors(val) {
        if (testMode) {
            testDynamicColors = val;
        } else if (typeof Config !== "undefined" && Config.setDynamicColors) {
            Config.setDynamicColors(val);
        }
    }

    function setThemePreset(val) {
        if (testMode) {
            testPreset = val;
            testDynamicColors = false;
        } else if (typeof Config !== "undefined" && Config.setThemePreset) {
            Config.setThemePreset(val);
        }
    }

    function setThemeCornerRadius(val) {
        if (testMode) {
            testCornerRadius = val;
        } else if (typeof Config !== "undefined" && Config.setThemeCornerRadius) {
            Config.setThemeCornerRadius(val);
        }
    }

    function setThemeArchetype(val) {
        if (testMode) {
            testArchetype = val;
        } else if (typeof Config !== "undefined" && Config.setThemeArchetype) {
            Config.setThemeArchetype(val);
        }
    }

    function setBlurStrength(val) {
        if (testMode) {
            testBlurStrength = val;
        } else if (typeof Config !== "undefined" && Config.setThemeBlurStrength) {
            Config.setThemeBlurStrength(val);
        }
    }

    spacing: root.valSpaceMedium

    // =========================================================================
    // SECTION 1: STYLE
    // =========================================================================
    SectionHeader {
        id: styleHeader
        title: "Theme Style"
        eyebrow: root.isDark ? "dark mode · celestial atmosphere" : "light mode · paper atmosphere"
    }

    // Theme Mode Segmented Pill Card
    Rectangle {
        id: styleSection
        Layout.fillWidth: true
        implicitHeight: 64
        radius: root.valRadiusMedium
        color: root.colSurfaceContainer
        border.color: (root.isZoneCurrent("style")) ? root.colPrimary : root.colBorderSubtle
        border.width: (root.isZoneCurrent("style")) ? 1.5 : 1

        Behavior on border.color { ColorAnimation { duration: root.valAnimMedium } }
        Behavior on border.width { NumberAnimation { duration: root.valAnimMedium } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.valPadLarge
            anchors.rightMargin: root.valPadLarge
            spacing: root.valSpaceMedium

            RowLayout {
                spacing: root.valSpaceMedium

                Rectangle {
                    width: 38
                    height: 38
                    radius: Math.min(root.valRadiusPill, 19)
                    color: root.colSurfaceContainerHigh

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.isDark ? "dark_mode" : "light_mode"
                        size: 20
                        color: root.colPrimary
                    }
                }

                ColumnLayout {
                    spacing: 2

                    Text {
                        text: "Appearance Mode"
                        font.family: root.valFontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: root.colOnSurface
                    }

                    Text {
                        text: root.isDark ? "Dark celestial theme active" : "Light paper theme active"
                        font.family: root.valFontFamily
                        font.pixelSize: 11
                        color: root.colOnSurfaceVariant
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Material 3 Segmented Pill
            Rectangle {
                implicitHeight: 38
                implicitWidth: 172
                radius: Math.min(root.valRadiusPill, 19)
                color: root.colSurfaceContainerHigh
                border.color: root.colBorderSubtle
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 2

                    // Dark Segment
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Math.max(0, Math.min(root.valRadiusPill, 19) - 2)
                        color: root.isDark ? root.colPrimaryContainer : (darkMouse.containsMouse ? root.colPillHover : "transparent")
                        border.color: root.isDark ? Qt.alpha(root.colPrimary, 0.4) : "transparent"
                        border.width: root.isDark ? 1 : 0

                        Behavior on color { ColorAnimation { duration: root.valAnimFast } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "dark_mode"
                                size: 16
                                color: root.isDark ? root.colOnPrimaryContainer : root.colOnSurfaceVariant
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Dark"
                                font.family: root.valFontFamily
                                font.pixelSize: 13
                                font.weight: root.isDark ? Font.Bold : Font.Normal
                                color: root.isDark ? root.colOnPrimaryContainer : root.colOnSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: darkMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setDarkMode(true)
                        }
                    }

                    // Light Segment
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Math.max(0, Math.min(root.valRadiusPill, 19) - 2)
                        color: !root.isDark ? root.colPrimaryContainer : (lightMouse.containsMouse ? root.colPillHover : "transparent")
                        border.color: !root.isDark ? Qt.alpha(root.colPrimary, 0.4) : "transparent"
                        border.width: !root.isDark ? 1 : 0

                        Behavior on color { ColorAnimation { duration: root.valAnimFast } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "light_mode"
                                size: 16
                                color: !root.isDark ? root.colOnPrimaryContainer : root.colOnSurfaceVariant
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Light"
                                font.family: root.valFontFamily
                                font.pixelSize: 13
                                font.weight: !root.isDark ? Font.Bold : Font.Normal
                                color: !root.isDark ? root.colOnPrimaryContainer : root.colOnSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: lightMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setDarkMode(false)
                        }
                    }
                }
            }
        }
    }

    // Design Archetypes Selector Card
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: archetypeLayout.implicitHeight + root.valPadLarge * 2
        radius: root.valRadiusMedium
        color: root.colSurfaceContainer
        border.color: (root.isZoneCurrent("style")) ? root.colPrimary : root.colBorderSubtle
        border.width: (root.isZoneCurrent("style")) ? 1.5 : 1

        Behavior on border.color { ColorAnimation { duration: root.valAnimMedium } }
        Behavior on border.width { NumberAnimation { duration: root.valAnimMedium } }

        ColumnLayout {
            id: archetypeLayout
            anchors.fill: parent
            anchors.margins: root.valPadLarge
            spacing: root.valSpaceMedium

            ColumnLayout {
                spacing: 2

                Text {
                    text: "Design Archetype"
                    font.family: root.valFontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: root.colOnSurface
                }

                Text {
                    text: "Choose the physical material physics and styling language for shell surfaces"
                    font.family: root.valFontFamily
                    font.pixelSize: 11
                    color: root.colOnSurfaceVariant
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.valSpaceMedium

                Repeater {
                    model: [
                        {
                            id: "liquid_glass",
                            archetypeId: "liquid_glass",
                            name: "Liquid Glass",
                            icon: "blur_on",
                            desc: "Fluid physics, specular glints & caustics"
                        },
                        {
                            id: "nordic_minimal",
                            archetypeId: "nordic_minimal",
                            name: "Nordic Minimal",
                            icon: "crop_square",
                            desc: "Clean matte surfaces & calm contrast"
                        },
                        {
                            id: "cyberpunk_neon",
                            archetypeId: "cyberpunk_neon",
                            name: "Cyberpunk Neon",
                            icon: "electric_bolt",
                            desc: "High-contrast dark substrate & neon glows"
                        }
                    ]

                    delegate: Rectangle {
                        id: archCard
                        required property var modelData
                        readonly property string archId: (modelData && (modelData.archetypeId || modelData.id)) ? (modelData.archetypeId || modelData.id) : ""
                        readonly property bool isSelected: root.currentArchetype === archId

                        Layout.fillWidth: true
                        implicitHeight: 76

                        // Authentic Archetype Self-Styling:
                        // 1. Geometry (radius)
                        radius: archId === "liquid_glass" ? 18 : (archId === "nordic_minimal" ? 6 : 2)

                        // 2. Substrate Fill Color
                        color: {
                            if (archId === "liquid_glass") {
                                if (root.isDark) {
                                    return isSelected ? Qt.rgba(1, 1, 1, 0.16) : (archHover.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.06));
                                } else {
                                    return isSelected ? Qt.rgba(0, 0, 0, 0.10) : (archHover.containsMouse ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(0, 0, 0, 0.03));
                                }
                            } else if (archId === "nordic_minimal") {
                                if (root.isDark) {
                                    return isSelected ? Qt.alpha(root.colPrimary, 0.14) : (archHover.containsMouse ? "#262933" : "#1B1E25");
                                } else {
                                    return isSelected ? Qt.alpha(root.colPrimary, 0.12) : (archHover.containsMouse ? "#E5E7EB" : "#F3F4F6");
                                }
                            } else {
                                // cyberpunk_neon: Deep OLED black
                                return isSelected ? Qt.rgba(0, 0.94, 1.0, 0.14) : (archHover.containsMouse ? "#0F121C" : "#07080D");
                            }
                        }

                        // 3. Border Color & Width
                        border.color: {
                            if (archId === "liquid_glass") {
                                return isSelected ? root.colPrimary : (root.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12));
                            } else if (archId === "nordic_minimal") {
                                return isSelected ? root.colPrimary : (root.isDark ? "#383E4C" : "#CBD5E1");
                            } else {
                                // cyberpunk_neon: Electrified neon cyan
                                return isSelected ? "#00F0FF" : Qt.alpha("#00F0FF", archHover.containsMouse ? 0.70 : 0.38);
                            }
                        }
                        border.width: isSelected ? 2 : (archId === "cyberpunk_neon" ? 1.5 : 1)

                        Behavior on color { ColorAnimation { duration: root.valAnimFast } }
                        Behavior on border.color { ColorAnimation { duration: root.valAnimFast } }

                        // Liquid Glass: Top Specular Glint Hairline
                        Rectangle {
                            id: liquidSpecularGlint
                            visible: archCard.archId === "liquid_glass"
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: archCard.radius
                            anchors.rightMargin: archCard.radius
                            height: 1
                            color: root.isDark ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(1, 1, 1, 0.85)
                            opacity: archCard.isSelected ? 1.0 : (archHover.containsMouse ? 0.8 : 0.45)
                        }

                        // Cyberpunk Neon: Left Laser Accent Strip
                        Rectangle {
                            id: cyberNeonStrip
                            visible: archCard.archId === "cyberpunk_neon"
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 3
                            radius: 1
                            color: "#00F0FF"
                            opacity: archCard.isSelected ? 1.0 : (archHover.containsMouse ? 0.8 : 0.45)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: root.valPadMedium
                            anchors.leftMargin: archCard.archId === "cyberpunk_neon" ? root.valPadMedium + 3 : root.valPadMedium
                            spacing: root.valSpaceSmall

                            Rectangle {
                                width: 34
                                height: 34
                                radius: archCard.archId === "liquid_glass" ? 17 : (archCard.archId === "nordic_minimal" ? 4 : 2)
                                color: {
                                    if (archCard.archId === "liquid_glass") {
                                        return archCard.isSelected ? root.colPrimary : (root.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06));
                                    } else if (archCard.archId === "nordic_minimal") {
                                        return archCard.isSelected ? root.colPrimary : (root.isDark ? "#282C37" : "#E2E8F0");
                                    } else {
                                        return archCard.isSelected ? "#00F0FF" : Qt.rgba(0, 0.94, 1.0, 0.14);
                                    }
                                }
                                border.color: {
                                    if (archCard.archId === "liquid_glass") {
                                        return root.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10);
                                    } else if (archCard.archId === "nordic_minimal") {
                                        return root.isDark ? "#383E4C" : "#CBD5E1";
                                    } else {
                                        return "#00F0FF";
                                    }
                                }
                                border.width: 1

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    size: 18
                                    color: {
                                        if (archCard.archId === "cyberpunk_neon") {
                                            return archCard.isSelected ? "#07080D" : "#00F0FF";
                                        }
                                        return archCard.isSelected ? root.colOnPrimary : root.colOnSurface;
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    spacing: 6
                                    Text {
                                        text: modelData.name
                                        font.family: archCard.archId === "cyberpunk_neon"
                                            ? ((typeof Theme !== "undefined" && Theme.fontMonospace) ? Theme.fontMonospace : "monospace")
                                            : root.valFontFamily
                                        font.pixelSize: 13
                                        font.weight: archCard.isSelected ? Font.Bold : Font.DemiBold
                                        color: {
                                            if (archCard.archId === "cyberpunk_neon") {
                                                return archCard.isSelected ? "#00F0FF" : (root.isDark ? "#E0F7FA" : "#004D40");
                                            }
                                            return archCard.isSelected ? root.colPrimary : root.colOnSurface;
                                        }
                                    }
                                    Rectangle {
                                        visible: archCard.isSelected
                                        width: 14; height: 14
                                        radius: archCard.archId === "liquid_glass" ? 7 : (archCard.archId === "nordic_minimal" ? 3 : 1)
                                        color: archCard.archId === "cyberpunk_neon" ? "#00F0FF" : root.colPrimary
                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: "check"
                                            size: 10
                                            color: archCard.archId === "cyberpunk_neon" ? "#07080D" : root.colOnPrimary
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.desc
                                    font.family: archCard.archId === "cyberpunk_neon"
                                        ? ((typeof Theme !== "undefined" && Theme.fontMonospace) ? Theme.fontMonospace : "monospace")
                                        : root.valFontFamily
                                    font.pixelSize: archCard.archId === "cyberpunk_neon" ? 9.5 : 10
                                    color: archCard.archId === "cyberpunk_neon"
                                        ? Qt.alpha("#00F0FF", 0.65)
                                        : root.colOnSurfaceVariant
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: archHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setThemeArchetype(archCard.archId)
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // SECTION 2: COLORS
    // =========================================================================
    SectionHeader {
        id: colorsHeader
        title: "Colors & Palettes"
        eyebrow: root.isDynamic ? "dynamic palette · extracted from active wallpaper" : ("preset palette · " + root.presetName)
    }

    // Dynamic Wallpaper Colors Toggle
    SettingToggle {
        id: colorsSection
        Layout.fillWidth: true
        title: "Dynamic Wallpaper Colors (Material You)"
        description: "Extract soft harmonic color palettes dynamically from your active wallpaper"
        checked: root.isDynamic
        onToggled: val => root.setDynamicColors(val)
    }

    // Accent Palette Presets
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: paletteLayout.implicitHeight + root.valPadLarge * 2
        radius: root.valRadiusMedium
        color: root.colSurfaceContainer
        border.color: (root.isZoneCurrent("colors")) ? root.colPrimary : root.colBorderSubtle
        border.width: (root.isZoneCurrent("colors")) ? 1.5 : 1

        Behavior on border.color { ColorAnimation { duration: root.valAnimMedium } }
        Behavior on border.width { NumberAnimation { duration: root.valAnimMedium } }

        ColumnLayout {
            id: paletteLayout
            anchors.fill: parent
            anchors.margins: root.valPadLarge
            spacing: root.valSpaceMedium

            ColumnLayout {
                spacing: 2

                Text {
                    text: "Accent Palette Presets"
                    font.family: root.valFontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: root.colOnSurface
                }

                Text {
                    text: "Choose vibrant accent hues for highlights, controls and indicators"
                    font.family: root.valFontFamily
                    font.pixelSize: 11
                    color: root.colOnSurfaceVariant
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        { id: "astral-ai", name: "Astral AI", darkColor: "#818CF8", lightColor: "#4F46E5" },
                        { id: "tokyo-night", name: "Tokyo Night", darkColor: "#7AA2F7", lightColor: "#34548A" },
                        { id: "catppuccin", name: "Catppuccin", darkColor: "#CBA6F7", lightColor: "#8839EF" },
                        { id: "nord", name: "Nord", darkColor: "#88C0D0", lightColor: "#5E81AC" },
                        { id: "everforest", name: "Everforest", darkColor: "#A7C080", lightColor: "#4F704A" },
                        { id: "gruvbox", name: "Gruvbox", darkColor: "#FABD2F", lightColor: "#B57614" },
                        { id: "rose-pine", name: "Rosé Pine", darkColor: "#EBBCBA", lightColor: "#D7827E" },
                        { id: "iris", name: "Iris", darkColor: "#CFBCFF", lightColor: "#6750A4" },
                        { id: "ocean", name: "Ocean", darkColor: "#9ECAFF", lightColor: "#12609A" },
                        { id: "emerald", name: "Emerald", darkColor: "#81D99C", lightColor: "#1E6B42" },
                        { id: "coral", name: "Coral", darkColor: "#FFB4A8", lightColor: "#B32810" }
                    ]

                    delegate: Item {
                        id: swatchItem
                        readonly property bool isSelected: !root.isDynamic && (root.presetName === modelData.id)
                        readonly property color accentHue: root.isDark ? modelData.darkColor : modelData.lightColor

                        width: 36
                        height: 36

                        // Outer selection ring
                        Rectangle {
                            anchors.fill: parent
                            radius: root.valRadiusFull
                            color: "transparent"
                            border.color: swatchItem.isSelected ? root.colPrimary : "transparent"
                            border.width: swatchItem.isSelected ? 2 : 0

                            Behavior on border.width { NumberAnimation { duration: root.valAnimFast } }
                        }

                        // Inner colored circle
                        Rectangle {
                            anchors.centerIn: parent
                            width: swatchItem.isSelected ? 24 : 28
                            height: swatchItem.isSelected ? 24 : 28
                            radius: root.valRadiusFull
                            color: swatchItem.accentHue

                            Behavior on width { NumberAnimation { duration: root.valAnimFast } }
                            Behavior on height { NumberAnimation { duration: root.valAnimFast } }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "check"
                                size: 14
                                color: root.isDark ? "#121318" : "#FFFFFF"
                                visible: swatchItem.isSelected
                            }
                        }

                        MouseArea {
                            id: swatchMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setThemePreset(modelData.id)
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // SECTION 3: SHAPE
    // =========================================================================
    SectionHeader {
        id: shapeHeader
        title: "Shape & Geometry"
        eyebrow: root.cornerRad + "px corner radius · " + Math.round(root.blurStrengthVal * 100) + "% blur strength"
    }

    // Corner Radius Slider
    SettingSlider {
        id: shapeSection
        Layout.fillWidth: true
        title: "Corner Radius"
        min: 12
        max: 32
        suffix: "px"
        value: root.cornerRad
        onValueModified: val => root.setThemeCornerRadius(Math.round(val))
    }

    // Blur & Surface Opacity Slider
    SettingSlider {
        Layout.fillWidth: true
        title: "Blur & Specular Intensity"
        min: 30
        max: 100
        suffix: "%"
        value: Math.round(root.blurStrengthVal * 100)
        onValueModified: val => root.setBlurStrength(val / 100.0)
    }

    // =========================================================================
    // SECTION 4: PREVIEW
    // =========================================================================
    SectionHeader {
        id: previewHeader
        title: "Live Theme Preview"
        eyebrow: "palette swatches & material components"
    }

    // Rich Live Theme Palette Preview
    Rectangle {
        id: previewSection
        Layout.fillWidth: true
        implicitHeight: previewContent.implicitHeight + root.valPadLarge * 2
        radius: root.valRadiusMedium
        color: root.colSurfaceContainer
        border.color: (root.isZoneCurrent("preview")) ? root.colPrimary : root.colBorderSubtle
        border.width: (root.isZoneCurrent("preview")) ? 1.5 : 1

        Behavior on border.color { ColorAnimation { duration: root.valAnimMedium } }
        Behavior on border.width { NumberAnimation { duration: root.valAnimMedium } }

        ColumnLayout {
            id: previewContent
            anchors.fill: parent
            anchors.margins: root.valPadLarge
            spacing: root.valSpaceMedium

            RowLayout {
                Layout.fillWidth: true
                spacing: root.valSpaceMedium

                ColumnLayout {
                    spacing: 2

                    Text {
                        text: "Palette Swatches"
                        font.family: root.valFontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: root.colOnSurface
                    }

                    Text {
                        text: "Surface, Container, Primary, Container, Secondary, Tertiary"
                        font.family: root.valFontFamily
                        font.pixelSize: 11
                        color: root.colOnSurfaceVariant
                    }
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 8

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: root.colSurface
                        border.color: root.colOutlineVariant; border.width: 1
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: root.colSurfaceContainer
                        border.color: root.colOutlineVariant; border.width: 1
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: root.colPrimary
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: root.colPrimaryContainer
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: root.colSecondary
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: root.colTertiary
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: root.colBorderSubtle
                opacity: 0.6
            }

            // Interactive Sample Components Preview
            RowLayout {
                Layout.fillWidth: true
                spacing: root.valSpaceMedium

                PillButton {
                    label: "Filled Action"
                    variant: "filled"
                    active: true
                    iconText: "check"
                }

                PillButton {
                    label: "Tonal Component"
                    variant: "tonal"
                    active: false
                    iconText: "palette"
                }

                Rectangle {
                    implicitHeight: 34
                    implicitWidth: sampleChipText.implicitWidth + 28
                    radius: Math.min(root.valRadiusPill, 17)
                    color: root.colSurfaceContainerHighest
                    border.color: root.colBorderSubtle
                    border.width: 1

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "auto_awesome"
                            size: 14
                            color: root.colPrimary
                        }

                        Text {
                            id: sampleChipText
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Astral Shell"
                            font.family: root.valFontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: root.colOnSurface
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    // Bottom Scroll Runway / Overscroll Spacer
    // Ensures that when navigating to trailing sections (shape, preview), the scroll pane
    // has adequate runway to smoothly scroll that section up toward the top of the viewport.
    Item {
        Layout.fillWidth: true
        implicitHeight: (typeof Theme !== "undefined" && Theme.padExtraLarge) ? Theme.padExtraLarge * 6 : 140
    }
}
