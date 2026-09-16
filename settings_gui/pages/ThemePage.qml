import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"

ColumnLayout {
    id: root

    property bool testMode: false
    property bool testDarkMode: true
    property bool testDynamicColors: false
    property string testPreset: "iris"
    property int testCornerRadius: 20

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

    readonly property color surfaceColor: (typeof Colors !== "undefined" && Colors.surface) ? Colors.surface : (root.isDark ? "#121318" : "#FAF8F5")
    readonly property color surfaceContainerColor: (typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : (root.isDark ? "#1A1B21" : "#F2EDE7")
    readonly property color surfaceContainerHighColor: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh) ? Colors.surfaceContainerHigh : (root.isDark ? "#282A30" : "#E8E2DA")
    readonly property color primaryColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : (root.isDark ? "#CFBCFF" : "#6750A4")
    readonly property color primaryContainerColor: (typeof Colors !== "undefined" && Colors.primaryContainer) ? Colors.primaryContainer : (root.isDark ? "#4F378B" : "#EDE7F6")
    readonly property color onPrimaryColor: (typeof Colors !== "undefined" && Colors.onPrimary) ? Colors.onPrimary : "#FFFFFF"
    readonly property color onPrimaryContainerColor: (typeof Colors !== "undefined" && Colors.m3onPrimaryContainer) ? Colors.m3onPrimaryContainer : (root.isDark ? "#EADDFF" : "#21005D")
    readonly property color onSurfaceColor: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : (root.isDark ? "#E4E2E6" : "#1D1B20")
    readonly property color onSurfaceVariantColor: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : (root.isDark ? "#C7C6CA" : "#49454F")
    readonly property color outlineColor: (typeof Colors !== "undefined" && Colors.outline) ? Colors.outline : (root.isDark ? "#8F9099" : "#D6CEC5")
    readonly property color borderSubtleColor: (typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : Qt.alpha(outlineColor, 0.18)

    readonly property int padLargeVal: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16
    readonly property int padMediumVal: (typeof Theme !== "undefined" && Theme.padMedium) ? Theme.padMedium : 12
    readonly property int padSmallVal: (typeof Theme !== "undefined" && Theme.padSmall) ? Theme.padSmall : 8
    readonly property int radiusMediumVal: (typeof Theme !== "undefined" && Theme.radiusMedium) ? Theme.radiusMedium : 16
    readonly property int radiusFullVal: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 9999
    readonly property int spaceMediumVal: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12
    readonly property int spaceSmallVal: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 8
    readonly property string fontFamilyVal: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
    readonly property int fontTitleMediumVal: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 21
    readonly property int fontBodyMediumVal: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
    readonly property int fontBodySmallVal: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
    readonly property int animDurationFastVal: (typeof Theme !== "undefined" && Theme.animDurationFast) ? Theme.animDurationFast : 150

    spacing: root.spaceMediumVal

    Text {
        text: "Theming & Appearance"
        font.family: root.fontFamilyVal
        font.pixelSize: root.fontTitleMediumVal
        font.weight: Font.Bold
        color: root.onSurfaceColor
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Customize desktop aesthetics, switch between Light and Dark mode, and choose dynamic or preset color palettes."
        font.family: root.fontFamilyVal
        font.pixelSize: root.fontBodySmallVal
        color: root.onSurfaceVariantColor
    }

    // Theme Mode: Dark vs Light
    Text {
        text: "Theme Mode"
        font.family: root.fontFamilyVal
        font.pixelSize: root.fontBodyMediumVal
        font.weight: Font.DemiBold
        color: root.onSurfaceColor
        Layout.topMargin: root.spaceSmallVal
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.spaceMediumVal

        // Dark Mode Card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 72
            radius: root.radiusMediumVal
            color: root.isDark ? root.primaryContainerColor : root.surfaceContainerColor
            border.color: root.isDark ? root.primaryColor : root.borderSubtleColor
            border.width: root.isDark ? 2 : 1

            Behavior on color { ColorAnimation { duration: root.animDurationFastVal } }
            Behavior on border.color { ColorAnimation { duration: root.animDurationFastVal } }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.testMode) {
                        root.testDarkMode = true;
                    } else if (typeof Config !== "undefined" && Config.setDarkMode) {
                        Config.setDarkMode(true);
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.padMediumVal
                    spacing: root.spaceMediumVal

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: root.isDark ? root.primaryColor : root.surfaceContainerHighColor

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "dark_mode"
                            size: 20
                            color: root.isDark ? root.onPrimaryColor : root.onSurfaceColor
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Dark Mode"
                            font.family: root.fontFamilyVal
                            font.pixelSize: root.fontBodyMediumVal
                            font.weight: Font.Bold
                            color: root.isDark ? root.onPrimaryContainerColor : root.onSurfaceColor
                        }

                        Text {
                            text: "Deep charcoal with vibrant accents"
                            font.family: root.fontFamilyVal
                            font.pixelSize: root.fontBodySmallVal
                            color: root.isDark ? root.onPrimaryContainerColor : root.onSurfaceVariantColor
                        }
                    }
                }
            }
        }

        // Light Mode Card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 72
            radius: root.radiusMediumVal
            color: !root.isDark ? root.primaryContainerColor : root.surfaceContainerColor
            border.color: !root.isDark ? root.primaryColor : root.borderSubtleColor
            border.width: !root.isDark ? 2 : 1

            Behavior on color { ColorAnimation { duration: root.animDurationFastVal } }
            Behavior on border.color { ColorAnimation { duration: root.animDurationFastVal } }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.testMode) {
                        root.testDarkMode = false;
                    } else if (typeof Config !== "undefined" && Config.setDarkMode) {
                        Config.setDarkMode(false);
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.padMediumVal
                    spacing: root.spaceMediumVal

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: !root.isDark ? root.primaryColor : root.surfaceContainerHighColor

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "light_mode"
                            size: 20
                            color: !root.isDark ? root.onPrimaryColor : root.onSurfaceColor
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Light Mode"
                            font.family: root.fontFamilyVal
                            font.pixelSize: root.fontBodyMediumVal
                            font.weight: Font.Bold
                            color: !root.isDark ? root.onPrimaryContainerColor : root.onSurfaceColor
                        }

                        Text {
                            text: "Crisp, airy paper with clean tones"
                            font.family: root.fontFamilyVal
                            font.pixelSize: root.fontBodySmallVal
                            color: !root.isDark ? root.onPrimaryContainerColor : root.onSurfaceVariantColor
                        }
                    }
                }
            }
        }
    }

    // Dynamic Colors Toggle
    SettingToggle {
        Layout.fillWidth: true
        title: "Dynamic Wallpaper Colors"
        description: "Extract soft harmonic palettes dynamically from your active wallpaper using matugen"
        checked: root.isDynamic
        onToggled: val => {
            if (root.testMode) {
                root.testDynamicColors = val;
            } else if (typeof Config !== "undefined" && Config.setDynamicColors) {
                Config.setDynamicColors(val);
            }
        }
    }

    // Preset Accent Selection
    Text {
        text: "Preset Color Palettes"
        font.family: root.fontFamilyVal
        font.pixelSize: root.fontBodyMediumVal
        font.weight: Font.DemiBold
        color: root.onSurfaceColor
        Layout.topMargin: root.spaceSmallVal
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.spaceSmallVal

        Repeater {
            model: [
                { id: "iris", name: "Iris", color: "#6750A4" },
                { id: "ocean", name: "Ocean", color: "#12609A" },
                { id: "emerald", name: "Emerald", color: "#1E6B42" },
                { id: "coral", name: "Coral", color: "#B32810" }
            ]

            delegate: Rectangle {
                Layout.fillWidth: true
                implicitHeight: 42
                radius: root.radiusFullVal
                color: (root.presetName === modelData.id) ? root.primaryContainerColor : root.surfaceContainerColor
                border.color: (root.presetName === modelData.id) ? root.primaryColor : root.borderSubtleColor
                border.width: (root.presetName === modelData.id) ? 2 : 1

                Behavior on color { ColorAnimation { duration: root.animDurationFastVal } }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.testMode) {
                            root.testPreset = modelData.id;
                        } else if (typeof Config !== "undefined" && Config.setThemePreset) {
                            Config.setThemePreset(modelData.id);
                        }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: root.spaceSmallVal

                        Rectangle {
                            width: 14
                            height: 14
                            radius: 7
                            color: modelData.color
                        }

                        Text {
                            text: modelData.name
                            font.family: root.fontFamilyVal
                            font.pixelSize: root.fontBodyMediumVal
                            font.weight: (root.presetName === modelData.id) ? Font.Bold : Font.Normal
                            color: (root.presetName === modelData.id) ? root.onPrimaryContainerColor : root.onSurfaceColor
                        }
                    }
                }
            }
        }
    }

    // Corner Radius
    SettingSlider {
        Layout.fillWidth: true
        title: "Corner Radius"
        min: 12
        max: 32
        suffix: "px"
        value: root.cornerRad
        onValueModified: val => {
            if (root.testMode) {
                root.testCornerRadius = Math.round(val);
            } else if (typeof Config !== "undefined" && Config.setThemeCornerRadius) {
                Config.setThemeCornerRadius(Math.round(val));
            }
        }
    }

    // Live Palette Preview
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 64
        radius: root.radiusMediumVal
        color: root.surfaceContainerColor
        border.color: root.borderSubtleColor
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: root.padMediumVal
            spacing: root.spaceMediumVal

            Text {
                text: "Active Theme Preview:"
                font.family: root.fontFamilyVal
                font.pixelSize: root.fontBodySmallVal
                font.weight: Font.DemiBold
                color: root.onSurfaceColor
                Layout.fillWidth: true
            }

            // Swatches
            Row {
                spacing: 8
                Rectangle { width: 28; height: 28; radius: 14; color: root.surfaceColor; border.width: 1; border.color: root.outlineColor }
                Rectangle { width: 28; height: 28; radius: 14; color: root.surfaceContainerColor; border.width: 1; border.color: root.outlineColor }
                Rectangle { width: 28; height: 28; radius: 14; color: root.primaryColor }
                Rectangle { width: 28; height: 28; radius: 14; color: root.primaryContainerColor }
                Rectangle { width: 28; height: 28; radius: 14; color: root.onSurfaceColor }
            }
        }
    }
}
