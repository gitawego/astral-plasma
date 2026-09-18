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

    spacing: Theme.spaceMedium

    // Header Title & Description
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: "Theming & Appearance"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontTitleMedium
            font.weight: Font.Bold
            color: Colors.m3onSurface
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Customize desktop aesthetics, switch between Light and Dark mode, and choose dynamic or preset color palettes."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBodySmall
            color: Colors.m3onSurfaceVariant
        }
    }

    // Row 1: Theme Style Segmented Pill Card
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 62
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            spacing: Theme.spaceMedium

            RowLayout {
                spacing: Theme.spaceMedium

                Rectangle {
                    width: 38
                    height: 38
                    radius: 19
                    color: Colors.surfaceContainerHigh

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.isDark ? "dark_mode" : "light_mode"
                        size: 20
                        color: Colors.primary
                    }
                }

                ColumnLayout {
                    spacing: 2

                    Text {
                        text: "Theme Style"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        font.weight: Font.DemiBold
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: root.isDark ? "Dark celestial theme active" : "Light paper theme active"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Material 3 Segmented Pill
            Rectangle {
                implicitHeight: 38
                implicitWidth: 172
                radius: Theme.radiusFull
                color: Colors.surfaceContainerHigh
                border.color: Theme.borderSubtle
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 2

                    // Dark Segment
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusFull
                        color: root.isDark ? Colors.primaryContainer : (darkMouse.containsMouse ? Colors.pillHover : "transparent")
                        border.color: root.isDark ? Qt.alpha(Colors.primary, 0.4) : "transparent"
                        border.width: root.isDark ? 1 : 0

                        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "dark_mode"
                                size: 16
                                color: root.isDark ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Dark"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBodySmall
                                font.weight: root.isDark ? Font.Bold : Font.Normal
                                color: root.isDark ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
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
                        radius: Theme.radiusFull
                        color: !root.isDark ? Colors.primaryContainer : (lightMouse.containsMouse ? Colors.pillHover : "transparent")
                        border.color: !root.isDark ? Qt.alpha(Colors.primary, 0.4) : "transparent"
                        border.width: !root.isDark ? 1 : 0

                        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "light_mode"
                                size: 16
                                color: !root.isDark ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Light"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBodySmall
                                font.weight: !root.isDark ? Font.Bold : Font.Normal
                                color: !root.isDark ? Colors.m3onPrimaryContainer : Colors.m3onSurfaceVariant
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

    // Row 2: Dynamic Wallpaper Colors Toggle
    SettingToggle {
        Layout.fillWidth: true
        title: "Dynamic Wallpaper Colors (Material You)"
        description: "Extract soft harmonic color palettes dynamically from your active wallpaper"
        checked: root.isDynamic
        onToggled: val => root.setDynamicColors(val)
    }

    // Row 3: Accent Palette Presets
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 64
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            spacing: Theme.spaceMedium

            ColumnLayout {
                spacing: 2

                Text {
                    text: "Accent Palette Presets"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Text {
                    text: "Choose vibrant accent hues for highlights and controls"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                }
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: 10

                Repeater {
                    model: [
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
                            radius: Theme.radiusFull
                            color: "transparent"
                            border.color: swatchItem.isSelected ? Colors.primary : "transparent"
                            border.width: swatchItem.isSelected ? 2 : 0

                            Behavior on border.width { NumberAnimation { duration: Theme.animDurationFast } }
                        }

                        // Inner colored circle
                        Rectangle {
                            anchors.centerIn: parent
                            width: swatchItem.isSelected ? 24 : 28
                            height: swatchItem.isSelected ? 24 : 28
                            radius: Theme.radiusFull
                            color: swatchItem.accentHue

                            Behavior on width { NumberAnimation { duration: Theme.animDurationFast } }
                            Behavior on height { NumberAnimation { duration: Theme.animDurationFast } }

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

    // Row 4: Corner Radius Slider
    SettingSlider {
        Layout.fillWidth: true
        title: "Corner Radius"
        min: 12
        max: 32
        suffix: "px"
        value: root.cornerRad
        onValueModified: val => root.setThemeCornerRadius(Math.round(val))
    }

    // Row 5: Live Theme Palette Preview
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 56
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            spacing: Theme.spaceMedium

            ColumnLayout {
                spacing: 2

                Text {
                    text: "Active Theme Preview"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Text {
                    text: "Surface, Container, Primary, Primary Container, Secondary"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                }
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: 8

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Colors.surface
                    border.color: Colors.outlineVariant
                    border.width: 1
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Colors.surfaceContainer
                    border.color: Colors.outlineVariant
                    border.width: 1
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Colors.primary
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Colors.primaryContainer
                }

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Colors.secondary
                }
            }
        }
    }
}
