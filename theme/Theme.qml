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

    // Animation presets & Material 3 Expressive Motion Tokens
    readonly property int animDurationFast: 150
    readonly property int animDurationNormal: 250
    readonly property int animDurationSlow: 400
    readonly property var animEasing: Easing.OutCubic

    // Expressive Motion Durations (ms) matching upstream Caelestia
    readonly property int animExpressiveFastSpatial: 350
    readonly property int animExpressiveDefaultSpatial: 500
    readonly property int animExpressiveSlowSpatial: 650
    readonly property int animExpressiveFastEffects: 150
    readonly property int animExpressiveDefaultEffects: 200
    readonly property int animExpressiveSlowEffects: 300
    readonly property int animEmphasized: 400

    // Expressive Cubic Bezier Spline Control Points: [c1x, c1y, c2x, c2y, endX, endY]
    readonly property var curveExpressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
    readonly property var curveExpressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
    readonly property var curveExpressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1.0, 1.0]
    readonly property var curveExpressiveFastEffects: [0.31, 0.94, 0.34, 1.0, 1.0, 1.0]
    readonly property var curveExpressiveDefaultEffects: [0.34, 0.80, 0.34, 1.0, 1.0, 1.0]
    readonly property var curveExpressiveSlowEffects: [0.34, 0.88, 0.34, 1.0, 1.0, 1.0]
    readonly property var curveEmphasizedDecel: [0.05, 0.70, 0.10, 1.0, 1.0, 1.0]
    readonly property var curveStandard: [0.20, 0.0, 0.0, 1.0, 1.0, 1.0]

    // Soft drop shadow
    readonly property color shadowColor: Qt.rgba(0, 0, 0, 0.08)
    readonly property color borderSubtle: Qt.alpha(Colors.outline, 0.18)
}
