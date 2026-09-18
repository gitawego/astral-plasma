pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    // Reactive mode binding directly from Config
    readonly property bool isDarkMode: (typeof Config !== "undefined") ? Config.isDarkMode : true
    readonly property bool dynamicColorsEnabled: (typeof Config !== "undefined") ? Config.dynamicColors : false
    readonly property string currentPreset: (typeof Config !== "undefined" && Config.themePreset) ? Config.themePreset : "iris"

    // Dynamic parsed palette cache from matugen (~/.cache/caelestia/colors.json)
    property var dynamicPalette: null

    function getColor(key, lightFallback, darkFallback) {
        const fallback = root.isDarkMode ? darkFallback : lightFallback;
        if (!root.dynamicColorsEnabled || !root.dynamicPalette || !root.dynamicPalette[key]) {
            return fallback;
        }
        const entry = root.dynamicPalette[key];
        if (root.isDarkMode) {
            if (entry.dark && entry.dark.color) return entry.dark.color;
        } else {
            if (entry.light && entry.light.color) return entry.light.color;
        }
        if (entry.default && entry.default.color) return entry.default.color;
        return fallback;
    }

    // Presets definitions for Accents
    readonly property color presetPrimary: {
        switch (root.currentPreset.toLowerCase()) {
            case "coral": return root.isDarkMode ? "#FFB4A8" : "#B32810";
            case "ocean": return root.isDarkMode ? "#9ECAFF" : "#12609A";
            case "emerald": return root.isDarkMode ? "#81D99C" : "#1E6B42";
            case "iris":
            default: return root.isDarkMode ? "#CFBCFF" : "#6750A4";
        }
    }

    readonly property color presetPrimaryContainer: {
        switch (root.currentPreset.toLowerCase()) {
            case "coral": return root.isDarkMode ? "#8C1D07" : "#FFDAD4";
            case "ocean": return root.isDarkMode ? "#00497D" : "#D1E4FF";
            case "emerald": return root.isDarkMode ? "#0F522C" : "#9DF5B6";
            case "iris":
            default: return root.isDarkMode ? "#4F378B" : "#EDE7F6";
        }
    }

    readonly property color presetOnPrimary: root.isDarkMode ? "#002C70" : "#FFFFFF"

    readonly property color presetOnPrimaryContainer: {
        switch (root.currentPreset.toLowerCase()) {
            case "coral": return root.isDarkMode ? "#FFDAD4" : "#3E1208";
            case "ocean": return root.isDarkMode ? "#D1E4FF" : "#001D33";
            case "emerald": return root.isDarkMode ? "#9DF5B6" : "#052111";
            case "iris":
            default: return root.isDarkMode ? "#EADDFF" : "#21005D";
        }
    }

    readonly property color presetSecondary: root.isDarkMode ? "#C0C6DC" : "#526070"
    readonly property color presetSecondaryContainer: root.isDarkMode ? "#404659" : "#D8E4F8"
    readonly property color presetOnSecondary: root.isDarkMode ? "#2A3042" : "#FFFFFF"
    readonly property color presetOnSecondaryContainer: root.isDarkMode ? "#DCE2F9" : "#0E1D2A"

    // Base surface tokens (fully reactive)
    readonly property color bgSurface: getColor("surface", "#FAF8F5", "#121318")
    readonly property color bgSurfaceContainer: getColor("surface_container", "#F2EDE7", "#1A1B21")
    readonly property color bgSurfaceContainerHigh: getColor("surface_container_high", "#E8E2DA", "#282A30")
    readonly property color bgSurfaceContainerLowest: getColor("surface_container_lowest", "#FFFFFF", "#0C0E13")
    readonly property color bgSurfaceVariant: getColor("surface_variant", "#E4DED7", "#44464F")

    readonly property color outlineColor: getColor("outline", "#D6CEC5", "#8F9099")
    readonly property color outlineVariantColor: getColor("outline_variant", "#E8E2DA", "#44464F")

    // Vibrant celestial accents (dynamic if enabled, otherwise preset)
    readonly property color accentPrimary: getColor("primary", root.presetPrimary, root.presetPrimary)
    readonly property color accentPrimaryContainer: getColor("primary_container", root.presetPrimaryContainer, root.presetPrimaryContainer)
    readonly property color accentOnPrimary: getColor("on_primary", root.presetOnPrimary, root.presetOnPrimary)
    readonly property color accentOnPrimaryContainer: getColor("on_primary_container", root.presetOnPrimaryContainer, root.presetOnPrimaryContainer)

    readonly property color accentSecondary: getColor("secondary", root.presetSecondary, root.presetSecondary)
    readonly property color accentSecondaryContainer: getColor("secondary_container", root.presetSecondaryContainer, root.presetSecondaryContainer)
    readonly property color accentOnSecondary: getColor("on_secondary", root.presetOnSecondary, root.presetOnSecondary)
    readonly property color accentOnSecondaryContainer: getColor("on_secondary_container", root.presetOnSecondaryContainer, root.presetOnSecondaryContainer)

    readonly property color accentError: getColor("error", "#BA1A1A", "#FFB4AB")
    readonly property color accentOnError: getColor("on_error", "#FFFFFF", "#690005")
    readonly property color accentErrorContainer: getColor("error_container", "#FFDAD6", "#93000A")
    readonly property color accentOnErrorContainer: getColor("on_error_container", "#410002", "#FFDAD6")

    // Modern typography tokens (high contrast, crisp in both light and dark)
    readonly property color textMain: getColor("on_surface", "#1D1B20", "#E4E2E6")
    readonly property color textMuted: getColor("on_surface_variant", "#49454F", "#C7C6CA")
    readonly property color textSubtle: root.isDarkMode ? "#8F9099" : "#79747E"

    // Public properties
    readonly property color surface: root.bgSurface
    readonly property color surfaceContainer: root.bgSurfaceContainer
    readonly property color surfaceContainerHigh: root.bgSurfaceContainerHigh
    readonly property color surfaceContainerLowest: root.bgSurfaceContainerLowest
    readonly property color surfaceVariant: root.bgSurfaceVariant
    readonly property color outline: root.outlineColor
    readonly property color outlineVariant: root.outlineVariantColor

    readonly property color primary: root.accentPrimary
    readonly property color primaryContainer: root.accentPrimaryContainer
    readonly property color secondary: root.accentSecondary
    readonly property color secondaryContainer: root.accentSecondaryContainer
    readonly property color error: root.accentError
    readonly property color errorContainer: root.accentErrorContainer

    readonly property color textOnPrimary: root.accentOnPrimary
    readonly property color textOnPrimaryContainer: root.accentOnPrimaryContainer
    readonly property color textOnSurface: root.textMain
    readonly property color textOnSurfaceVariant: root.textMuted
    readonly property color textInverse: root.isDarkMode ? "#1D1B20" : "#FFFFFF"

    // Material 3 "on" Tokens Bridge (Resolves QML on<Signal> grammar collision)
    QtObject {
        id: tokenBridge
        readonly property color onSurfaceVal: root.textMain
        readonly property color onSurfaceVariantVal: root.textMuted
        readonly property color onPrimaryVal: root.accentOnPrimary
        readonly property color onPrimaryContainerVal: root.accentOnPrimaryContainer
        readonly property color onSecondaryVal: root.accentOnSecondary
        readonly property color onSecondaryContainerVal: root.accentOnSecondaryContainer
        readonly property color onErrorVal: root.accentError
        readonly property color onErrorContainerVal: root.accentOnErrorContainer
        readonly property color onTertiaryVal: root.m3onTertiary
        readonly property color onTertiaryContainerVal: root.m3onTertiaryContainer
    }

    readonly property alias onSurface: tokenBridge.onSurfaceVal
    readonly property alias onSurfaceVariant: tokenBridge.onSurfaceVariantVal
    readonly property alias onPrimary: tokenBridge.onPrimaryVal
    readonly property alias onPrimaryContainer: tokenBridge.onPrimaryContainerVal
    readonly property alias onSecondary: tokenBridge.onSecondaryVal
    readonly property alias onSecondaryContainer: tokenBridge.onSecondaryContainerVal
    readonly property alias onError: tokenBridge.onErrorVal
    readonly property alias onErrorContainer: tokenBridge.onErrorContainerVal
    readonly property alias onTertiary: tokenBridge.onTertiaryVal
    readonly property alias onTertiaryContainer: tokenBridge.onTertiaryContainerVal

    readonly property color surfaceContainerHighest: root.bgSurfaceContainerHigh

    readonly property color m3onSurface: root.textMain
    readonly property color m3onSurfaceVariant: root.textMuted
    readonly property color m3onPrimary: root.accentOnPrimary
    readonly property color m3onPrimaryContainer: root.accentOnPrimaryContainer
    readonly property color m3onSecondary: root.accentOnSecondary
    readonly property color m3onSecondaryContainer: root.accentOnSecondaryContainer
    readonly property color m3surface: root.bgSurface
    readonly property color m3surfaceContainer: root.bgSurfaceContainer
    readonly property color m3surfaceContainerHigh: root.bgSurfaceContainerHigh
    readonly property color m3surfaceContainerLowest: root.bgSurfaceContainerLowest
    readonly property color m3primary: root.accentPrimary
    readonly property color m3primaryContainer: root.accentPrimaryContainer
    readonly property color m3secondary: root.accentSecondary
    readonly property color m3secondaryContainer: root.accentSecondaryContainer

    readonly property color tertiary: getColor("tertiary", "#386A20", "#E0BBDD")
    readonly property color tertiaryContainer: getColor("tertiary_container", "#B7F397", "#593D59")
    readonly property color m3onTertiary: root.isDarkMode ? "#412742" : "#FFFFFF"
    readonly property color m3onTertiaryContainer: root.isDarkMode ? "#FDD7FA" : "#042100"

    // Acrylic translucent variants
    readonly property color surfaceTranslucent: Qt.alpha(root.surface, root.isDarkMode ? 0.88 : 0.94)
    readonly property color containerTranslucent: Qt.alpha(root.surfaceContainer, root.isDarkMode ? 0.75 : 0.85)
    readonly property color cardBackground: Qt.alpha(root.surfaceContainerLowest, root.isDarkMode ? 0.65 : 0.80)
    readonly property color pillHover: Qt.alpha(root.textMain, root.isDarkMode ? 0.12 : 0.08)
    readonly property color pillPress: Qt.alpha(root.textMain, root.isDarkMode ? 0.22 : 0.14)

    // =========================================================================
    // Apple Liquid Glass Dynamic Themed Material Tokens
    // =========================================================================
    // Master surface tint: translucent frosted glass infused with active theme palette
    readonly property color glassSurface: {
        const base = root.isDarkMode ? Qt.rgba(0.06, 0.08, 0.12, 0.70) : Qt.rgba(0.96, 0.96, 0.98, 0.72);
        return Qt.tint(base, Qt.alpha(root.primary, root.isDarkMode ? 0.08 : 0.05));
    }

    // Modal sheet surface (Command Launcher, Central Dropdown)
    readonly property color glassModalSurface: {
        const base = root.isDarkMode ? Qt.rgba(0.07, 0.09, 0.14, 0.75) : Qt.rgba(0.97, 0.97, 1.0, 0.78);
        return Qt.tint(base, Qt.alpha(root.primary, root.isDarkMode ? 0.10 : 0.06));
    }

    // Dock capsule surface (Left Dock)
    readonly property color glassDockSurface: {
        const base = root.isDarkMode ? Qt.rgba(0.06, 0.08, 0.12, 0.70) : Qt.rgba(0.95, 0.95, 0.98, 0.72);
        return Qt.tint(base, Qt.alpha(root.primary, root.isDarkMode ? 0.08 : 0.05));
    }

    // Border frame surface
    readonly property color glassBorderSurface: glassSurface

    // Distinct glass card surfaces (sculpted frosted glass plates with chromatic depth)
    readonly property color glassCard: root.isDarkMode
        ? Qt.tint(Qt.rgba(0.04, 0.05, 0.08, 0.30), Qt.alpha(root.primary, 0.05))
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, 0.50),
            Qt.alpha(root.primary, 0.08)
        )
    readonly property color glassCardHover: root.isDarkMode
        ? Qt.tint(Qt.rgba(0.08, 0.10, 0.14, 0.45), Qt.alpha(root.primary, 0.10))
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, 0.65),
            Qt.alpha(root.primary, 0.12)
        )
    readonly property color glassCardActive: root.isDarkMode
        ? Qt.tint(Qt.rgba(0.12, 0.15, 0.20, 0.55), Qt.alpha(root.primary, 0.15))
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, 0.80),
            Qt.alpha(root.primary, 0.18)
        )

    // Vibrant tinted glass card (e.g. Media Player, Highlighted cards)
    readonly property color glassCardVibrant: root.isDarkMode
        ? Qt.tint(Qt.rgba(0.04, 0.05, 0.08, 0.30), Qt.alpha(root.primary, 0.12))
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, 0.55),
            Qt.alpha(root.primary, 0.18)
        )

    // Frosted interactive pills
    readonly property color glassPill: Qt.tint(
        Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.08 : 0.45),
        Qt.alpha(root.primary, root.isDarkMode ? 0.08 : 0.05)
    )
    readonly property color glassPillHover: Qt.tint(
        Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.14 : 0.60),
        Qt.alpha(root.primary, root.isDarkMode ? 0.16 : 0.10)
    )
    // Active / Prominent Themed Glass Pill (Luminous translucent frosted glass with theme color)
    readonly property color glassPillActive: Qt.tint(
        Qt.alpha(root.primaryContainer, root.isDarkMode ? 0.55 : 0.70),
        Qt.alpha(root.primary, 0.25)
    )

    // Directional specular rim highlights (ultra-fine 1px hairline catch with subtle theme glint)
    readonly property color glassBorderSpecular: Qt.tint(
        Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.32 : 0.65),
        Qt.alpha(root.primary, root.isDarkMode ? 0.25 : 0.15)
    )
    readonly property color glassBorderSubtle: Qt.tint(
        root.isDarkMode ? Qt.rgba(1.0, 1.0, 1.0, 0.12) : Qt.rgba(0.0, 0.0, 0.0, 0.08),
        Qt.alpha(root.primary, 0.10)
    )
    readonly property color glassInnerRim: Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.08 : 0.30)

    // Optical refraction caustic glow
    readonly property color glassCausticGlow: Qt.alpha(root.primary, root.isDarkMode ? 0.10 : 0.06)
    readonly property color glassShadowColor: Qt.rgba(0, 0, 0, root.isDarkMode ? 0.25 : 0.10)


    // Dynamic color loader (reads ~/.cache/caelestia/colors.json if matugen was run)
    FileView {
        id: colorsCache
        path: Quickshell.env("HOME") + "/.cache/caelestia/colors.json"
        preload: true

        onLoaded: {
            try {
                const text = colorsCache.text();
                if (text && text.trim().length > 0) {
                    const parsed = JSON.parse(text);
                    if (parsed.colors) {
                        root.dynamicPalette = parsed.colors;
                    }
                }
            } catch (e) {
                console.log("[Palette] Using default Caelestia scheme");
            }
        }
    }
}
