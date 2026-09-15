pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    // Dark mode by default to match Caelestia aesthetics and KDE Dark themes
    property bool isDarkMode: true

    function applyPreset(name) {
        if (!name) return;
        switch (name.toLowerCase()) {
            case "coral":
                root.accentPrimary = root.isDarkMode ? "#FFB4A8" : "#D85338";
                root.accentPrimaryContainer = root.isDarkMode ? "#8C1D07" : "#FFE8E0";
                root.accentOnPrimaryContainer = root.isDarkMode ? "#FFDAD4" : "#3E1208";
                break;
            case "ocean":
                root.accentPrimary = root.isDarkMode ? "#9ECAFF" : "#1B6CA8";
                root.accentPrimaryContainer = root.isDarkMode ? "#00497D" : "#D4E9F7";
                root.accentOnPrimaryContainer = root.isDarkMode ? "#D1E4FF" : "#001D33";
                break;
            case "emerald":
                root.accentPrimary = root.isDarkMode ? "#81D99C" : "#2E7D52";
                root.accentPrimaryContainer = root.isDarkMode ? "#0F522C" : "#D7F2E3";
                root.accentOnPrimaryContainer = root.isDarkMode ? "#9DF5B6" : "#052111";
                break;
            case "iris":
            default:
                root.accentPrimary = root.isDarkMode ? "#CFBCFF" : "#6B4FA0";
                root.accentPrimaryContainer = root.isDarkMode ? "#4F378B" : "#EDE7F6";
                root.accentOnPrimaryContainer = root.isDarkMode ? "#EADDFF" : "#21005D";
                break;
        }
    }

    Component.onCompleted: {
        if (Config.settings && Config.settings.theme && Config.settings.theme.preset) {
            root.applyPreset(Config.settings.theme.preset);
        }
    }

    // Base surface tokens
    property color bgSurface: root.isDarkMode ? "#121318" : "#FAF8F5"
    property color bgSurfaceContainer: root.isDarkMode ? "#1A1B21" : "#F2EDE7"
    property color bgSurfaceContainerHigh: root.isDarkMode ? "#282A30" : "#E8E2DA"
    property color bgSurfaceContainerLowest: root.isDarkMode ? "#0C0E13" : "#FFFFFF"
    property color bgSurfaceVariant: root.isDarkMode ? "#44464F" : "#E4DED7"

    property color outlineColor: root.isDarkMode ? "#8F9099" : "#D6CEC5"
    property color outlineVariantColor: root.isDarkMode ? "#44464F" : "#E8E2DA"

    // Modern vibrant celestial accent
    property color accentPrimary: root.isDarkMode ? "#B1C5FF" : "#6B4FA0"
    property color accentPrimaryContainer: root.isDarkMode ? "#2A4F9C" : "#EDE7F6"
    property color accentOnPrimary: root.isDarkMode ? "#002C70" : "#FFFFFF"
    property color accentOnPrimaryContainer: root.isDarkMode ? "#DAE2FF" : "#21005D"

    property color accentSecondary: root.isDarkMode ? "#C0C6DC" : "#526070"
    property color accentOnSecondary: root.isDarkMode ? "#2A3042" : "#FFFFFF"
    property color accentSecondaryContainer: root.isDarkMode ? "#404659" : "#D8E4F8"
    property color accentOnSecondaryContainer: root.isDarkMode ? "#DCE2F9" : "#0E1D2A"

    property color accentError: root.isDarkMode ? "#FFB4AB" : "#BA1A1A"
    property color accentOnError: root.isDarkMode ? "#690005" : "#FFFFFF"
    property color accentErrorContainer: root.isDarkMode ? "#93000A" : "#FFDAD6"
    property color accentOnErrorContainer: root.isDarkMode ? "#FFDAD6" : "#410002"

    // Refined modern typography
    property color textMain: root.isDarkMode ? "#E4E2E6" : "#1D1B20"
    property color textMuted: root.isDarkMode ? "#C7C6CA" : "#49454F"
    property color textSubtle: root.isDarkMode ? "#8F9099" : "#79747E"

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
    readonly property color textInverse: root.isDarkMode ? "#1D1B20" : "#FFFFFF"

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

    readonly property color tertiary: root.isDarkMode ? "#E0BBDD" : "#386A20"
    readonly property color tertiaryContainer: root.isDarkMode ? "#593D59" : "#B7F397"
    readonly property color m3onTertiary: root.isDarkMode ? "#412742" : "#FFFFFF"
    readonly property color m3onTertiaryContainer: root.isDarkMode ? "#FDD7FA" : "#042100"

    // Acrylic translucent variants
    readonly property color surfaceTranslucent: Qt.alpha(root.surface, 0.88)
    readonly property color containerTranslucent: Qt.alpha(root.surfaceContainer, 0.75)
    readonly property color cardBackground: Qt.alpha(root.surfaceContainerLowest, 0.65)
    readonly property color pillHover: Qt.alpha(root.textMain, 0.12)
    readonly property color pillPress: Qt.alpha(root.textMain, 0.22)

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
                    const dark = (parsed.is_dark_mode !== undefined) ? parsed.is_dark_mode : (parsed.mode === "dark");
                    root.isDarkMode = dark;

                    if (parsed.colors) {
                        const getC = (key) => {
                            if (parsed.colors[key]) {
                                if (dark && parsed.colors[key].dark && parsed.colors[key].dark.color) return parsed.colors[key].dark.color;
                                if (!dark && parsed.colors[key].light && parsed.colors[key].light.color) return parsed.colors[key].light.color;
                                if (parsed.colors[key].default && parsed.colors[key].default.color) return parsed.colors[key].default.color;
                            }
                            return null;
                        };
                        const s = getC("surface"); if (s) root.bgSurface = s;
                        const sc = getC("surface_container"); if (sc) root.bgSurfaceContainer = sc;
                        const sch = getC("surface_container_high"); if (sch) root.bgSurfaceContainerHigh = sch;
                        const scl = getC("surface_container_lowest"); if (scl) root.bgSurfaceContainerLowest = scl;
                        const sv = getC("surface_variant"); if (sv) root.bgSurfaceVariant = sv;
                        const p = getC("primary"); if (p) root.accentPrimary = p;
                        const op = getC("on_primary"); if (op) root.accentOnPrimary = op;
                        const pc = getC("primary_container"); if (pc) root.accentPrimaryContainer = pc;
                        const opc = getC("on_primary_container"); if (opc) root.accentOnPrimaryContainer = opc;
                        const os = getC("on_surface"); if (os) root.textMain = os;
                        const osv = getC("on_surface_variant"); if (osv) root.textMuted = osv;
                        const sec = getC("secondary"); if (sec) root.accentSecondary = sec;
                        const out = getC("outline"); if (out) root.outlineColor = out;
                    }
                }
            } catch (e) {
                console.log("[Palette] Using default Caelestia scheme");
            }
        }
    }
}
