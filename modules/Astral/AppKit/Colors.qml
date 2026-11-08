pragma Singleton

import QtQuick

// ============================================================================
// Colors — the public Material 3 roles
// ============================================================================
// Resolved from the host's exported palette, so an app looks like the desktop it
// is running on without importing a single kernel file. The fallbacks are the
// Material 3 dark roles: they are what an app paints with before a wallpaper
// palette exists, and `AppPalette.source` says whether that is what happened.
QtObject {
    readonly property bool isDarkMode: AppPalette.color("mode", "dark") !== "light"

    readonly property color primary: AppPalette.color("primary", "#818cf8")
    readonly property color primaryContainer: AppPalette.color("surface_container", "#111420")
    readonly property color surface: AppPalette.color("surface", "#0b0d14")
    readonly property color outline: AppPalette.color("outline", "#6366f1")
    readonly property color textOnSurface: AppPalette.color("on_surface", "#eef2ff")
    readonly property color textOnSurfaceVariant: AppPalette.color("secondary", "#38bdf8")
    readonly property color accentSecondary: AppPalette.color("secondary", "#38bdf8")
    readonly property color accentTertiary: AppPalette.color("tertiary", "#c084fc")
    readonly property color onPrimary: AppPalette.color("on_primary", "#0f111a")
}
