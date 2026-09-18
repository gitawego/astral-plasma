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

    // Comprehensive chromatic theme registry
    readonly property var themeRegistry: ({
        "iris": {
            name: "Iris",
            dark: {
                primary: "#CFBCFF",
                on_primary: "#381E72",
                primary_container: "#4F378B",
                on_primary_container: "#EADDFF",
                secondary: "#CBC2DB",
                on_secondary: "#332D41",
                secondary_container: "#4A4458",
                on_secondary_container: "#E8DEF8",
                tertiary: "#EFB8C8",
                on_tertiary: "#492532",
                tertiary_container: "#633B48",
                on_tertiary_container: "#FFD8E4",
                surface: "#141218",
                surface_container: "#1D1B20",
                surface_container_high: "#2B2930",
                surface_container_lowest: "#0F0D13",
                surface_variant: "#49454F",
                outline: "#938F99",
                outline_variant: "#49454F",
                on_surface: "#E6E0E9",
                on_surface_variant: "#CAC4D0",
                glassTint: "#CFBCFF"
            },
            light: {
                primary: "#6750A4",
                on_primary: "#FFFFFF",
                primary_container: "#EADDFF",
                on_primary_container: "#21005D",
                secondary: "#625B71",
                on_secondary: "#FFFFFF",
                secondary_container: "#E8DEF8",
                on_secondary_container: "#1D192B",
                tertiary: "#7D5260",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#FFD8E4",
                on_tertiary_container: "#31111D",
                surface: "#FEF7FF",
                surface_container: "#F3EDF7",
                surface_container_high: "#ECE6F0",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#E7E0EC",
                outline: "#79747E",
                outline_variant: "#CAC4D0",
                on_surface: "#1D1B20",
                on_surface_variant: "#49454F",
                glassTint: "#6750A4"
            }
        },
        "ocean": {
            name: "Ocean",
            dark: {
                primary: "#9ECAFF",
                on_primary: "#003258",
                primary_container: "#00497D",
                on_primary_container: "#D1E4FF",
                secondary: "#BCC7DB",
                on_secondary: "#263140",
                secondary_container: "#3D4758",
                on_secondary_container: "#D8E3F8",
                tertiary: "#D6BEE4",
                on_tertiary: "#3B2948",
                tertiary_container: "#523F5F",
                on_tertiary_container: "#F2DAFF",
                surface: "#101418",
                surface_container: "#181C20",
                surface_container_high: "#23262B",
                surface_container_lowest: "#0B0E12",
                surface_variant: "#42474E",
                outline: "#8C9199",
                outline_variant: "#42474E",
                on_surface: "#E1E2E8",
                on_surface_variant: "#C2C7CF",
                glassTint: "#89b4fa"
            },
            light: {
                primary: "#12609A",
                on_primary: "#FFFFFF",
                primary_container: "#D1E4FF",
                on_primary_container: "#001D36",
                secondary: "#535F70",
                on_secondary: "#FFFFFF",
                secondary_container: "#D7E3F7",
                on_secondary_container: "#101C2B",
                tertiary: "#6B5778",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#F2DAFF",
                on_tertiary_container: "#251432",
                surface: "#F7F9FF",
                surface_container: "#EDEFEA",
                surface_container_high: "#E2E2E9",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#DFE2EB",
                outline: "#73777F",
                outline_variant: "#C3C7D0",
                on_surface: "#181C20",
                on_surface_variant: "#43474E",
                glassTint: "#12609A"
            }
        },
        "coral": {
            name: "Coral",
            dark: {
                primary: "#FFB4A8",
                on_primary: "#690005",
                primary_container: "#8C1D07",
                on_primary_container: "#FFDAD4",
                secondary: "#E7BDB6",
                on_secondary: "#442A25",
                secondary_container: "#5D3F3B",
                on_secondary_container: "#FFDAD4",
                tertiary: "#DDC3A1",
                on_tertiary: "#3E2E16",
                tertiary_container: "#56442B",
                on_tertiary_container: "#FBDEBC",
                surface: "#181211",
                surface_container: "#201A19",
                surface_container_high: "#2B2423",
                surface_container_lowest: "#120D0C",
                surface_variant: "#534341",
                outline: "#A08C89",
                outline_variant: "#534341",
                on_surface: "#EDE0DE",
                on_surface_variant: "#D8C2BE",
                glassTint: "#fab387"
            },
            light: {
                primary: "#B32810",
                on_primary: "#FFFFFF",
                primary_container: "#FFDAD4",
                on_primary_container: "#410002",
                secondary: "#775651",
                on_secondary: "#FFFFFF",
                secondary_container: "#FFDAD4",
                on_secondary_container: "#2C1512",
                tertiary: "#6F5B40",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#FBDEBC",
                on_tertiary_container: "#271904",
                surface: "#FFF8F6",
                surface_container: "#FCEEEB",
                surface_container_high: "#F7E8E5",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#F5DDD9",
                outline: "#857370",
                outline_variant: "#D8C2BE",
                on_surface: "#201A19",
                on_surface_variant: "#534341",
                glassTint: "#B32810"
            }
        },
        "emerald": {
            name: "Emerald",
            dark: {
                primary: "#81D99C",
                on_primary: "#00391A",
                primary_container: "#0F522C",
                on_primary_container: "#9DF5B6",
                secondary: "#B7CCB8",
                on_secondary: "#233427",
                secondary_container: "#394B3C",
                on_secondary_container: "#D3E8D3",
                tertiary: "#A1CED5",
                on_tertiary: "#00363C",
                tertiary_container: "#1F4D53",
                on_tertiary_container: "#BCEBF2",
                surface: "#101511",
                surface_container: "#181D19",
                surface_container_high: "#222823",
                surface_container_lowest: "#0A0F0B",
                surface_variant: "#414941",
                outline: "#8B938A",
                outline_variant: "#414941",
                on_surface: "#E0E4DE",
                on_surface_variant: "#C1C9BF",
                glassTint: "#81D99C"
            },
            light: {
                primary: "#1E6B42",
                on_primary: "#FFFFFF",
                primary_container: "#9DF5B6",
                on_primary_container: "#00210C",
                secondary: "#516353",
                on_secondary: "#FFFFFF",
                secondary_container: "#D3E8D3",
                on_secondary_container: "#0E1F13",
                tertiary: "#39656B",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#BCEBF2",
                on_tertiary_container: "#001F23",
                surface: "#F6FBF4",
                surface_container: "#EAEFE7",
                surface_container_high: "#E4EAE1",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#DDE5DA",
                outline: "#727971",
                outline_variant: "#C1C9BF",
                on_surface: "#181D19",
                on_surface_variant: "#414941",
                glassTint: "#1E6B42"
            }
        }
    })

    readonly property var activeThemeDefinition: {
        const key = (root.currentPreset || "iris").toLowerCase();
        return root.themeRegistry[key] || root.themeRegistry["iris"];
    }

    readonly property var currentThemeTokens: root.isDarkMode
        ? root.activeThemeDefinition.dark
        : root.activeThemeDefinition.light

    function getColor(key, lightFallback, darkFallback) {
        // 1. If dynamic colors is explicitly enabled, use dynamic matugen palette from wallpaper
        if (root.dynamicColorsEnabled && root.dynamicPalette && root.dynamicPalette[key]) {
            const entry = root.dynamicPalette[key];
            if (root.isDarkMode) {
                if (entry.dark && entry.dark.color) return entry.dark.color;
            } else {
                if (entry.light && entry.light.color) return entry.light.color;
            }
            if (entry.default && entry.default.color) return entry.default.color;
        }

        // 2. Otherwise use the active chromatic preset theme
        if (root.currentThemeTokens && root.currentThemeTokens[key]) {
            return root.currentThemeTokens[key];
        }

        // 3. Fallback to provided light/dark fallback
        return root.isDarkMode ? darkFallback : lightFallback;
    }

    // Presets definitions for Accents (directly connected to activeThemeDefinition)
    readonly property color presetPrimary: root.currentThemeTokens.primary
    readonly property color presetPrimaryContainer: root.currentThemeTokens.primary_container
    readonly property color presetOnPrimary: root.currentThemeTokens.on_primary
    readonly property color presetOnPrimaryContainer: root.currentThemeTokens.on_primary_container
    readonly property color presetSecondary: root.currentThemeTokens.secondary
    readonly property color presetSecondaryContainer: root.currentThemeTokens.secondary_container
    readonly property color presetOnSecondary: root.currentThemeTokens.on_secondary
    readonly property color presetOnSecondaryContainer: root.currentThemeTokens.on_secondary_container

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
        const base = root.isDarkMode ? Qt.rgba(0.06, 0.08, 0.12, 0.22) : Qt.rgba(0.96, 0.96, 0.98, 0.35);
        return Qt.tint(base, Qt.alpha(root.primary, root.isDarkMode ? 0.10 : 0.08));
    }

    // Modal sheet surface (Command Launcher, Central Dropdown)
    readonly property color glassModalSurface: glassSurface

    // Dock capsule surface (Left Dock)
    readonly property color glassDockSurface: glassSurface

    // Border frame surface
    readonly property color glassBorderSurface: glassSurface

    // Distinct glass card surfaces (sculpted frosted glass plates with crystalline translucency)
    readonly property color glassCard: root.isDarkMode
        ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.06), Qt.alpha(root.primary, 0.08))
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, 0.40),
            Qt.alpha(root.primary, 0.08)
        )
    readonly property color glassCardHover: root.isDarkMode
        ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.12), Qt.alpha(root.primary, 0.15))
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, 0.55),
            Qt.alpha(root.primary, 0.12)
        )
    readonly property color glassCardActive: root.isDarkMode
        ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.18), Qt.alpha(root.primary, 0.22))
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, 0.70),
            Qt.alpha(root.primary, 0.18)
        )

    // Vibrant tinted glass card (e.g. Media Player, Highlighted cards)
    readonly property color glassCardVibrant: root.isDarkMode
        ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.10), Qt.alpha(root.primary, 0.22))
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, 0.50),
            Qt.alpha(root.primary, 0.22)
        )

    // Frosted interactive pills
    readonly property color glassPill: Qt.tint(
        Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.08 : 0.45),
        Qt.alpha(root.primary, root.isDarkMode ? 0.08 : 0.05)
    )
    readonly property color glassPillHover: Qt.tint(
        Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.15 : 0.60),
        Qt.alpha(root.primary, root.isDarkMode ? 0.16 : 0.10)
    )
    // Active / Prominent Themed Glass Pill (Luminous translucent frosted glass with theme color)
    readonly property color glassPillActive: Qt.tint(
        Qt.alpha(root.primaryContainer, root.isDarkMode ? 0.60 : 0.75),
        Qt.alpha(root.primary, 0.30)
    )

    // Directional specular rim highlights (ultra-fine 1px hairline catch with luminous theme glint)
    readonly property color glassBorderSpecular: Qt.tint(
        Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.40 : 0.85),
        Qt.alpha(root.primary, root.isDarkMode ? 0.30 : 0.20)
    )
    readonly property color glassBorderSubtle: Qt.tint(
        root.isDarkMode ? Qt.rgba(1.0, 1.0, 1.0, 0.14) : Qt.rgba(0.0, 0.0, 0.0, 0.09),
        Qt.alpha(root.primary, 0.12)
    )
    readonly property color glassInnerRim: Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.12 : 0.35)

    // Optical refraction caustic glow
    readonly property color glassCausticGlow: Qt.alpha(root.primary, root.isDarkMode ? 0.18 : 0.12)
    readonly property color glassShadowColor: Qt.rgba(0, 0, 0, root.isDarkMode ? 0.28 : 0.12)


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
