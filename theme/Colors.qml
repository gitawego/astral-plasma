pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    function applyPreset(name) {
        if (!name) return;
        switch (name.toLowerCase()) {
            case "coral":
                root.accentPrimary = "#D85338";
                root.accentPrimaryContainer = "#FFE8E0";
                root.accentOnPrimaryContainer = "#3E1208";
                break;
            case "ocean":
                root.accentPrimary = "#1B6CA8";
                root.accentPrimaryContainer = "#D4E9F7";
                root.accentOnPrimaryContainer = "#001D33";
                break;
            case "emerald":
                root.accentPrimary = "#2E7D52";
                root.accentPrimaryContainer = "#D7F2E3";
                root.accentOnPrimaryContainer = "#052111";
                break;
            case "iris":
            default:
                root.accentPrimary = "#6B4FA0";
                root.accentPrimaryContainer = "#EDE7F6";
                root.accentOnPrimaryContainer = "#21005D";
                break;
        }
    }

    Component.onCompleted: {
        if (Config.settings && Config.settings.theme && Config.settings.theme.preset) {
            root.applyPreset(Config.settings.theme.preset);
        }
    }

    // Base tokens (using unique names to avoid QML on<Property> signal handler collisions)
    property color bgSurface: "#FAF8F5"
    property color bgSurfaceContainer: "#F2EDE7"
    property color bgSurfaceContainerHigh: "#E8E2DA"
    property color bgSurfaceContainerLowest: "#FFFFFF"
    property color bgSurfaceVariant: "#E4DED7"

    property color outlineColor: "#D6CEC5"
    property color outlineVariantColor: "#E8E2DA"

    // Modern vibrant celestial accent
    property color accentPrimary: "#6B4FA0"           // Elegant Iris Violet
    property color accentPrimaryContainer: "#EDE7F6"  // Clean soft lavender
    property color accentOnPrimary: "#FFFFFF"         // Crisp white
    property color accentOnPrimaryContainer: "#21005D" // Deep purple

    property color accentSecondary: "#526070"
    property color accentOnSecondary: "#FFFFFF"
    property color accentSecondaryContainer: "#D8E4F8"
    property color accentOnSecondaryContainer: "#0E1D2A"

    property color accentError: "#BA1A1A"
    property color accentOnError: "#FFFFFF"
    property color accentErrorContainer: "#FFDAD6"
    property color accentOnErrorContainer: "#410002"

    // Refined modern typography
    property color textMain: "#1D1B20"                // Obsidian / deep charcoal (never harsh black)
    property color textMuted: "#49454F"               // Refined slate
    property color textSubtle: "#79747E"

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
    readonly property color onError: root.accentOnError
    readonly property color errorContainer: root.accentErrorContainer
    readonly property color onErrorContainer: root.accentOnErrorContainer

    readonly property color textOnPrimary: root.accentOnPrimary
    readonly property color textOnPrimaryContainer: root.accentOnPrimaryContainer
    readonly property color textOnSurface: root.textMain
    readonly property color textOnSurfaceVariant: root.textMuted
    readonly property color textInverse: "#FFFFFF"

    readonly property color onPrimary: root.accentOnPrimary
    readonly property color onPrimaryContainer: root.accentOnPrimaryContainer
    readonly property color onSurface: root.textMain
    readonly property color onSurfaceVariant: root.textMuted
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

    readonly property color tertiary: "#386A20"
    readonly property color tertiaryContainer: "#B7F397"
    readonly property color m3onTertiary: "#FFFFFF"
    readonly property color m3onTertiaryContainer: "#042100"

    // Acrylic translucent variants
    readonly property color surfaceTranslucent: Qt.alpha(root.surface, 0.88)
    readonly property color containerTranslucent: Qt.alpha(root.surfaceContainer, 0.75)
    readonly property color cardBackground: Qt.alpha(root.surfaceContainerLowest, 0.65)
    readonly property color pillHover: Qt.alpha(root.textMain, 0.08)
    readonly property color pillPress: Qt.alpha(root.textMain, 0.16)

    // Dynamic color loader (reads ~/.cache/caelestia/colors.json if matugen was run)
    FileView {
        id: colorsCache
        path: Quickshell.env("HOME") + "/.cache/caelestia/colors.json"
        preload: true

        onLoaded: {
            // Only override if explicitly requested and not using the curated caelestia-pastel preset
            if (Config.settings.theme && Config.settings.theme.preset === "caelestia-pastel") {
                return;
            }
            try {
                const text = colorsCache.text();
                if (text && text.trim().length > 0) {
                    const parsed = JSON.parse(text);
                    if (parsed.colors) {
                        const getC = (key) => {
                            if (parsed.colors[key]) {
                                if (parsed.colors[key].light && parsed.colors[key].light.color) return parsed.colors[key].light.color;
                                if (parsed.colors[key].default && parsed.colors[key].default.color) return parsed.colors[key].default.color;
                            }
                            return null;
                        };
                        const s = getC("surface"); if (s) root.surface = s;
                        const sc = getC("surface_container"); if (sc) root.surfaceContainer = sc;
                        const sch = getC("surface_container_high"); if (sch) root.surfaceContainerHigh = sch;
                        const p = getC("primary"); if (p) root.primary = p;
                        const op = getC("on_primary"); if (op) root.m3onPrimary = op;
                        const pc = getC("primary_container"); if (pc) root.primaryContainer = pc;
                        const opc = getC("on_primary_container"); if (opc) root.m3onPrimaryContainer = opc;
                        const os = getC("on_surface"); if (os) root.m3onSurface = os;
                        const osv = getC("on_surface_variant"); if (osv) root.m3onSurfaceVariant = osv;
                        const sec = getC("secondary"); if (sec) root.secondary = sec;
                        const out = getC("outline"); if (out) root.outline = out;
                    }
                }
            } catch (e) {
                console.log("[Palette] Using default Caelestia pastel scheme");
            }
        }
    }
}
