pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    // Direct color properties with curated warm pastel defaults (matching Caelestia reference)
    property color surface: "#FBF7F4"
    property color surfaceContainer: "#F3ECE4"
    property color surfaceContainerHigh: "#EAE0D6"
    property color surfaceContainerLowest: "#FFFFFF"
    property color surfaceVariant: "#E2D7CC"
    property color m3onSurface: "#2B1F1A"
    property color m3onSurfaceVariant: "#6D5B53"
    property color outline: "#DECFC4"
    property color outlineVariant: "#EAE0D6"
    
    property color primary: "#8F462B"
    property color m3onPrimary: "#FFFFFF"
    property color primaryContainer: "#F5D8CE"
    property color m3onPrimaryContainer: "#3D1308"
    
    property color secondary: "#77574E"
    property color m3onSecondary: "#FFFFFF"
    property color secondaryContainer: "#FFDBCF"
    property color m3onSecondaryContainer: "#2C1610"
    
    property color tertiary: "#6C5D2F"
    property color m3onTertiary: "#FFFFFF"
    property color tertiaryContainer: "#F7E1A6"
    property color m3onTertiaryContainer: "#241A00"

    // Aliases
    readonly property color m3surface: root.surface
    readonly property color m3surfaceContainer: root.surfaceContainer
    readonly property color m3surfaceContainerHigh: root.surfaceContainerHigh
    readonly property color m3surfaceContainerLowest: root.surfaceContainerLowest
    readonly property color m3primary: root.primary
    readonly property color m3primaryContainer: root.primaryContainer
    readonly property color m3secondary: root.secondary
    readonly property color m3secondaryContainer: root.secondaryContainer

    readonly property color onSurface: root.m3onSurface
    readonly property color onSurfaceVariant: root.m3onSurfaceVariant
    readonly property color onPrimary: root.m3onPrimary
    readonly property color surfaceContainerHighest: root.surfaceContainerHigh

    // Acrylic translucent variants
    readonly property color surfaceTranslucent: Qt.alpha(root.surface, 0.88)
    readonly property color containerTranslucent: Qt.alpha(root.surfaceContainer, 0.75)
    readonly property color cardBackground: Qt.alpha(root.surfaceContainerLowest, 0.65)
    readonly property color pillHover: Qt.alpha(root.m3onSurface, 0.08)
    readonly property color pillPress: Qt.alpha(root.m3onSurface, 0.16)

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
