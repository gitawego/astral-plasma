pragma Singleton

import QtQuick
import Quickshell
import qs.theme

Singleton {
    id: root

    // Corner Radii
    readonly property int radiusFull: 9999
    readonly property int radiusLarge: 24
    readonly property int radiusMedium: 16
    readonly property int radiusSmall: 10
    readonly property int radiusExtraSmall: 6

    // Spacing and Margins
    readonly property int spaceExtraLarge: 24
    readonly property int spaceLarge: 16
    readonly property int spaceMedium: 12
    readonly property int spaceSmall: 8
    readonly property int spaceExtraSmall: 4

    // Padding
    readonly property int padExtraLarge: 20
    readonly property int padLarge: 16
    readonly property int padMedium: 12
    readonly property int padSmall: 8
    readonly property int padExtraSmall: 4

    // Typography - Retina scaled
    readonly property string fontFamily: "Google Sans Flex, Cantarell, Noto Sans, sans-serif"
    readonly property string fontMonospace: "JetBrains Mono, monospace"

    readonly property int fontTitleLarge: 26
    readonly property int fontTitleMedium: 21
    readonly property int fontTitleSmall: 16
    readonly property int fontBodyMedium: 15
    readonly property int fontBodySmall: 13
    readonly property int fontLabelSmall: 12

    readonly property int fontSmall: root.fontBodySmall
    readonly property int fontMedium: root.fontBodyMedium
    readonly property int fontLarge: root.fontTitleMedium

    // Animation presets
    readonly property int animDurationFast: 150
    readonly property int animDurationNormal: 250
    readonly property int animDurationSlow: 400
    readonly property var animEasing: Easing.OutCubic

    // Soft drop shadow
    readonly property color shadowColor: Qt.rgba(0, 0, 0, 0.08)
    readonly property color borderSubtle: Qt.alpha(Colors.outline, 0.18)
}
