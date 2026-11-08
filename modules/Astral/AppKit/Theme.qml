pragma Singleton

import QtQuick

// ============================================================================
// Theme — the public design surface
// ============================================================================
// Radii and typeface come from the host's palette file, so an archetype change
// (flat, glass, neon) reaches community apps without a rebuild. The fallbacks are
// the shell's own defaults; `AppPalette.source` distinguishes "the host told us" from
// "we had to guess".
QtObject {
    readonly property int radiusSmall: AppPalette.number("radius_small", 10)
    readonly property int radiusMedium: AppPalette.number("radius_medium", 16)
    readonly property int radiusLarge: AppPalette.number("radius_large", 24)
    readonly property string fontFamily: AppPalette.color(
        "font_family",
        "Google Sans Flex, Cantarell, Noto Sans, sans-serif")
    readonly property bool isDarkMode: Colors.isDarkMode
    readonly property string source: AppPalette.source
}
