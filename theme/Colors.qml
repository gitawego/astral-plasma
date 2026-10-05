pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
// The palette fallback is a diagnostic: it goes through the leveled logger
// instead of a bare console.log, so a quiet shell stays quiet.
import "../services"

Singleton {
    id: root

    // Reactive mode binding directly from Config
    readonly property bool isDarkMode: (typeof Config !== "undefined") ? Config.isDarkMode : true
    readonly property bool dynamicColorsEnabled: (typeof Config !== "undefined") ? Config.dynamicColors : false
    readonly property string currentPreset: (typeof Config !== "undefined" && Config.themePreset) ? Config.themePreset : "iris"

    // Dynamic parsed palette cache from matugen (XDG cache dir, see the loader below)
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
                on_surface: "#F3EDF6",
                on_surface_variant: "#E1DBE7",
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
                on_surface_variant: "#35313B",
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
                on_surface: "#EEEFF5",
                on_surface_variant: "#D9DEE6",
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
                on_surface_variant: "#2F333A",
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
                on_surface: "#F9ECEA",
                on_surface_variant: "#EFD9D5",
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
                on_surface_variant: "#3F2F2D",
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
                on_surface: "#ECF0EA",
                on_surface_variant: "#D8E0D6",
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
                on_surface_variant: "#2D352D",
                glassTint: "#1E6B42"
            }
        },
        "catppuccin": {
            name: "Catppuccin",
            dark: {
                primary: "#CBA6F7",
                on_primary: "#11111B",
                primary_container: "#45475A",
                on_primary_container: "#F5E0DC",
                secondary: "#89B4FA",
                on_secondary: "#181825",
                secondary_container: "#313244",
                on_secondary_container: "#CDD6F4",
                tertiary: "#F5C2E7",
                on_tertiary: "#11111B",
                tertiary_container: "#585B70",
                on_tertiary_container: "#F5E0DC",
                surface: "#181825",
                surface_container: "#1E1E2E",
                surface_container_high: "#313244",
                surface_container_lowest: "#11111B",
                surface_variant: "#45475A",
                outline: "#6C7086",
                outline_variant: "#45475A",
                on_surface: "#F2EFFB",
                on_surface_variant: "#E4E1F0",
                glassTint: "#CBA6F7"
            },
            light: {
                primary: "#8839EF",
                on_primary: "#FFFFFF",
                primary_container: "#EA76CB",
                on_primary_container: "#30005B",
                secondary: "#1E66F5",
                on_secondary: "#FFFFFF",
                secondary_container: "#CCD0DA",
                on_secondary_container: "#1E1E2E",
                tertiary: "#EA76CB",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#E6E9EF",
                on_tertiary_container: "#4C4F69",
                surface: "#EFF1F5",
                surface_container: "#E6E9EF",
                surface_container_high: "#DCE0E8",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#CCD0DA",
                outline: "#9CA0B0",
                outline_variant: "#BCC0CC",
                on_surface: "#1E1F29",
                on_surface_variant: "#303242",
                glassTint: "#8839EF"
            }
        },
        "tokyo-night": {
            name: "Tokyo Night",
            dark: {
                primary: "#7AA2F7",
                on_primary: "#15161E",
                primary_container: "#283457",
                on_primary_container: "#C0CAF5",
                secondary: "#BB9AF7",
                on_secondary: "#1A1B26",
                secondary_container: "#3D3857",
                on_secondary_container: "#E0AF68",
                tertiary: "#7DCFFF",
                on_tertiary: "#15161E",
                tertiary_container: "#23405C",
                on_tertiary_container: "#B4F9F8",
                surface: "#16161E",
                surface_container: "#1A1B26",
                surface_container_high: "#24283B",
                surface_container_lowest: "#101014",
                surface_variant: "#292E42",
                outline: "#565F89",
                outline_variant: "#414868",
                on_surface: "#EDF1FF",
                on_surface_variant: "#DFE4F7",
                glassTint: "#7AA2F7"
            },
            light: {
                primary: "#34548A",
                on_primary: "#FFFFFF",
                primary_container: "#CFD8DC",
                on_primary_container: "#0F1A2C",
                secondary: "#5A4A78",
                on_secondary: "#FFFFFF",
                secondary_container: "#E0DBE8",
                on_secondary_container: "#1F1530",
                tertiary: "#0F4B6E",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#CCE6F4",
                on_tertiary_container: "#001D2E",
                surface: "#F2F3F7",
                surface_container: "#E6E8EF",
                surface_container_high: "#DCDEE7",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#D0D3DF",
                outline: "#6E738D",
                outline_variant: "#B5B8C8",
                on_surface: "#181B26",
                on_surface_variant: "#282D3D",
                glassTint: "#34548A"
            }
        },
        "nord": {
            name: "Nord",
            dark: {
                primary: "#88C0D0",
                on_primary: "#2E3440",
                primary_container: "#434C5E",
                on_primary_container: "#ECEFF4",
                secondary: "#81A1C1",
                on_secondary: "#2E3440",
                secondary_container: "#3B4252",
                on_secondary_container: "#D8DEE9",
                tertiary: "#B48EAD",
                on_tertiary: "#2E3440",
                tertiary_container: "#4C3E49",
                on_tertiary_container: "#E5E9F0",
                surface: "#242933",
                surface_container: "#2E3440",
                surface_container_high: "#3B4252",
                surface_container_lowest: "#1E222A",
                surface_variant: "#434C5E",
                outline: "#6A778D",
                outline_variant: "#4C566A",
                on_surface: "#ECEFF4",
                on_surface_variant: "#E1E7F2",
                glassTint: "#88C0D0"
            },
            light: {
                primary: "#5E81AC",
                on_primary: "#FFFFFF",
                primary_container: "#D8DEE9",
                on_primary_container: "#1E2A38",
                secondary: "#81A1C1",
                on_secondary: "#FFFFFF",
                secondary_container: "#E5E9F0",
                on_secondary_container: "#2E3440",
                tertiary: "#B48EAD",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#EFE5EC",
                on_tertiary_container: "#3A2836",
                surface: "#ECEFF4",
                surface_container: "#E5E9F0",
                surface_container_high: "#D8DEE9",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#CCD3E0",
                outline: "#768296",
                outline_variant: "#B8C1D1",
                on_surface: "#191D26",
                on_surface_variant: "#29303D",
                glassTint: "#5E81AC"
            }
        },
        "everforest": {
            name: "Everforest",
            dark: {
                primary: "#A7C080",
                on_primary: "#1E2326",
                primary_container: "#374137",
                on_primary_container: "#D3C6AA",
                secondary: "#83C092",
                on_secondary: "#1E2326",
                secondary_container: "#323F36",
                on_secondary_container: "#D3C6AA",
                tertiary: "#DBBC7F",
                on_tertiary: "#1E2326",
                tertiary_container: "#463E2D",
                on_tertiary_container: "#E69875",
                surface: "#1E2326",
                surface_container: "#272E33",
                surface_container_high: "#2E383C",
                surface_container_lowest: "#14171A",
                surface_variant: "#414B50",
                outline: "#7A8478",
                outline_variant: "#4F5B58",
                on_surface: "#ECE7DA",
                on_surface_variant: "#E3E8DC",
                glassTint: "#A7C080"
            },
            light: {
                primary: "#4F704A",
                on_primary: "#FFFFFF",
                primary_container: "#D2E5CE",
                on_primary_container: "#12250F",
                secondary: "#496F57",
                on_secondary: "#FFFFFF",
                secondary_container: "#D0E4D7",
                on_secondary_container: "#0E2416",
                tertiary: "#7B622B",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#F5E7C4",
                on_tertiary_container: "#2B1E03",
                surface: "#FDF6E3",
                surface_container: "#F4EED8",
                surface_container_high: "#EAE3CE",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#E0D7C2",
                outline: "#757B70",
                outline_variant: "#C2BBA8",
                on_surface: "#1A2219",
                on_surface_variant: "#283327",
                glassTint: "#4F704A"
            }
        },
        "gruvbox": {
            name: "Gruvbox",
            dark: {
                primary: "#FABD2F",
                on_primary: "#1D2021",
                primary_container: "#504945",
                on_primary_container: "#EBDBB2",
                secondary: "#8EC07C",
                on_secondary: "#1D2021",
                secondary_container: "#3C3836",
                on_secondary_container: "#EBDBB2",
                tertiary: "#FE8019",
                on_tertiary: "#1D2021",
                tertiary_container: "#665C54",
                on_tertiary_container: "#FB4934",
                surface: "#1D2021",
                surface_container: "#282828",
                surface_container_high: "#3C3836",
                surface_container_lowest: "#141617",
                surface_variant: "#504945",
                outline: "#928374",
                outline_variant: "#665C54",
                on_surface: "#F6ECCB",
                on_surface_variant: "#EBE5CC",
                glassTint: "#FABD2F"
            },
            light: {
                primary: "#B57614",
                on_primary: "#FFFFFF",
                primary_container: "#F5DDB3",
                on_primary_container: "#3D2500",
                secondary: "#427B58",
                on_secondary: "#FFFFFF",
                secondary_container: "#D2E9D9",
                on_secondary_container: "#082813",
                tertiary: "#AF3A03",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#FFDAC8",
                on_tertiary_container: "#3B0E00",
                surface: "#FBF1C7",
                surface_container: "#F2E5BC",
                surface_container_high: "#EBDBB2",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#D5C4A1",
                outline: "#7C6F64",
                outline_variant: "#BDAE93",
                on_surface: "#241C16",
                on_surface_variant: "#332921",
                glassTint: "#B57614"
            }
        },
        "rose-pine": {
            name: "Rosé Pine",
            dark: {
                primary: "#EBBCBA",
                on_primary: "#191724",
                primary_container: "#3A354E",
                on_primary_container: "#E0DEF4",
                secondary: "#9CCFD8",
                on_secondary: "#191724",
                secondary_container: "#2B3C46",
                on_secondary_container: "#E0DEF4",
                tertiary: "#C4A7E7",
                on_tertiary: "#191724",
                tertiary_container: "#3B324D",
                on_tertiary_container: "#EB6F92",
                surface: "#14121E",
                surface_container: "#191724",
                surface_container_high: "#26233A",
                surface_container_lowest: "#0F0D17",
                surface_variant: "#403D52",
                outline: "#847E97",
                outline_variant: "#524F67",
                on_surface: "#F4F0FF",
                on_surface_variant: "#E6E2F2",
                glassTint: "#EBBCBA"
            },
            light: {
                primary: "#D7827E",
                on_primary: "#FFFFFF",
                primary_container: "#F6DDD9",
                on_primary_container: "#461816",
                secondary: "#56949F",
                on_secondary: "#FFFFFF",
                secondary_container: "#D7EAF0",
                on_secondary_container: "#112F35",
                tertiary: "#907AA9",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#EADFF2",
                on_tertiary_container: "#2F2040",
                surface: "#FAF4ED",
                surface_container: "#F2E9E1",
                surface_container_high: "#E8DDD2",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#DFD3C7",
                outline: "#79757F",
                outline_variant: "#C3B9B0",
                on_surface: "#1E1829",
                on_surface_variant: "#30283E",
                glassTint: "#D7827E"
            }
        },
        "astral-ai": {
            name: "Astral AI",
            dark: {
                primary: "#818CF8",
                on_primary: "#0F111A",
                primary_container: "#312E81",
                on_primary_container: "#E0E7FF",
                secondary: "#38BDF8",
                on_secondary: "#082F49",
                secondary_container: "#0369A1",
                on_secondary_container: "#E0F2FE",
                tertiary: "#C084FC",
                on_tertiary: "#3B0764",
                tertiary_container: "#581C87",
                on_tertiary_container: "#F3E8FF",
                surface: "#0B0D14",
                surface_container: "#111420",
                surface_container_high: "#1E2235",
                surface_container_lowest: "#07080D",
                surface_variant: "#282E47",
                outline: "#6366F1",
                outline_variant: "#3730A3",
                on_surface: "#EEF2FF",
                on_surface_variant: "#E2E8FF",
                glassTint: "#818CF8"
            },
            light: {
                primary: "#4F46E5",
                on_primary: "#FFFFFF",
                primary_container: "#E0E7FF",
                on_primary_container: "#1E1B4B",
                secondary: "#0284C7",
                on_secondary: "#FFFFFF",
                secondary_container: "#E0F2FE",
                on_secondary_container: "#082F49",
                tertiary: "#7E22CE",
                on_tertiary: "#FFFFFF",
                tertiary_container: "#F3E8FF",
                on_tertiary_container: "#3B0764",
                surface: "#F8FAFC",
                surface_container: "#F1F5F9",
                surface_container_high: "#E2E8F0",
                surface_container_lowest: "#FFFFFF",
                surface_variant: "#CBD5E1",
                outline: "#64748B",
                outline_variant: "#94A3B8",
                on_surface: "#0F172A",
                on_surface_variant: "#1E293B",
                glassTint: "#4F46E5"
            }
        }
    })

    // Canonical list of presets for UI pickers across settings pages
    readonly property var presetList: [
        { id: "dynamic", name: "Dynamic", isDynamic: true, darkColor: "#CFBCFF", lightColor: "#6750A4" },
        { id: "astral-ai", name: "Astral AI", isDynamic: false, darkColor: "#818CF8", lightColor: "#4F46E5" },
        { id: "tokyo-night", name: "Tokyo Night", isDynamic: false, darkColor: "#7AA2F7", lightColor: "#34548A" },
        { id: "catppuccin", name: "Catppuccin", isDynamic: false, darkColor: "#CBA6F7", lightColor: "#8839EF" },
        { id: "nord", name: "Nord", isDynamic: false, darkColor: "#88C0D0", lightColor: "#5E81AC" },
        { id: "everforest", name: "Everforest", isDynamic: false, darkColor: "#A7C080", lightColor: "#4F704A" },
        { id: "gruvbox", name: "Gruvbox", isDynamic: false, darkColor: "#FABD2F", lightColor: "#B57614" },
        { id: "rose-pine", name: "Rosé Pine", isDynamic: false, darkColor: "#EBBCBA", lightColor: "#D7827E" },
        { id: "iris", name: "Iris", isDynamic: false, darkColor: "#CFBCFF", lightColor: "#6750A4" },
        { id: "ocean", name: "Ocean", isDynamic: false, darkColor: "#9ECAFF", lightColor: "#12609A" },
        { id: "emerald", name: "Emerald", isDynamic: false, darkColor: "#81D99C", lightColor: "#1E6B42" },
        { id: "coral", name: "Coral", isDynamic: false, darkColor: "#FFB4A8", lightColor: "#B32810" }
    ]

    readonly property var activeThemeDefinition: {
        const key = (root.currentPreset || "iris").toLowerCase();
        return root.themeRegistry[key] || root.themeRegistry["iris"];
    }

    readonly property var currentThemeTokens: root.isDarkMode
        ? root.activeThemeDefinition.dark
        : root.activeThemeDefinition.light

    function getColor(key, lightFallback, darkFallback) {
        // 1. If dynamic colors is explicitly enabled, use dynamic matugen palette from wallpaper for chromatic accents
        if (root.dynamicColorsEnabled && root.dynamicPalette && root.dynamicPalette[key]) {
            const entry = root.dynamicPalette[key];
            if (root.isDarkMode) {
                if (entry.dark && entry.dark.color) return entry.dark.color;
            } else {
                if (entry.light && entry.light.color) return entry.light.color;
            }
            if (entry.default && entry.default.color) return entry.default.color;
        }

        // 2. Archetype-level surface and substrate overrides (Domain-Driven Design: Cyberpunk OLED black, Nordic matte)
        // Archetypes define surface/substrate roles (surface, surface_container*, on_surface*).
        // They do NOT lock out user-selected chromatic accents unless no preset is active.
        const isAccentRole = (
            key.startsWith("primary") || key.startsWith("on_primary") ||
            key.startsWith("secondary") || key.startsWith("on_secondary") ||
            key.startsWith("tertiary") || key.startsWith("on_tertiary") ||
            key.startsWith("error") || key.startsWith("warning") ||
            key.startsWith("info") || key.startsWith("success")
        );

        if (!isAccentRole && typeof Theme !== "undefined" && Theme.activeArchetype) {
            const archPalette = root.isDarkMode ? Theme.activeArchetype.paletteDark : Theme.activeArchetype.paletteLight;
            if (archPalette && archPalette[key] !== undefined) {
                return archPalette[key];
            }
        }

        // 3. Otherwise use the active chromatic preset theme
        if (root.currentThemeTokens && root.currentThemeTokens[key]) {
            return root.currentThemeTokens[key];
        }

        // 4. Archetype fallback for accents if preset tokens don't specify it
        if (typeof Theme !== "undefined" && Theme.activeArchetype) {
            const archPalette = root.isDarkMode ? Theme.activeArchetype.paletteDark : Theme.activeArchetype.paletteLight;
            if (archPalette && archPalette[key] !== undefined) {
                return archPalette[key];
            }
        }

        // 5. Fallback to provided light/dark fallback
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

    readonly property color accentWarning: getColor("warning", "#785900", "#FFBA28")
    readonly property color accentOnWarning: getColor("on_warning", "#FFFFFF", "#422C00")
    readonly property color accentWarningContainer: getColor("warning_container", "#FFDEA3", "#5F4100")
    readonly property color accentOnWarningContainer: getColor("on_warning_container", "#261900", "#FFDEA3")

    readonly property color accentInfo: getColor("info", "#0061A4", "#97CBFF")
    readonly property color accentOnInfo: getColor("on_info", "#FFFFFF", "#003355")
    readonly property color accentInfoContainer: getColor("info_container", "#CEE5FF", "#004A75")
    readonly property color accentOnInfoContainer: getColor("on_info_container", "#001D33", "#CEE5FF")

    readonly property color accentSuccess: getColor("success", "#206B33", "#95D598")
    readonly property color accentOnSuccess: getColor("on_success", "#FFFFFF", "#003912")
    readonly property color accentSuccessContainer: getColor("success_container", "#B0F2B2", "#125222")
    readonly property color accentOnSuccessContainer: getColor("on_success_container", "#002107", "#B0F2B2")

    // AI-Centric Reactive Aura & Activity Color Tokens
    readonly property bool aiActive: (typeof AiActivityService !== "undefined" && AiActivityService.isActive)
    readonly property color aiActivityColor: (aiActive && typeof AiActivityService !== "undefined" && AiActivityService.brandColor)
        ? AiActivityService.brandColor
        : root.accentPrimary
    readonly property real aiActivityIntensity: (typeof AiActivityService !== "undefined") ? AiActivityService.intensity : 0.0
    readonly property color aiGlowColor: Qt.alpha(aiActivityColor, aiActive ? (0.35 + 0.25 * aiActivityIntensity) : 0.15)

    // Modern typography tokens (high contrast, crisp in both light and dark)
    readonly property color textMain: getColor("on_surface", "#14171F", "#F2EFF4")
    readonly property color textMuted: getColor("on_surface_variant", "#3F434B", "#D0D3DC")
    readonly property color textSubtle: root.isDarkMode ? "#A0A4B0" : "#636772"

    // Public properties
    readonly property color surface: root.bgSurface
    readonly property color surfaceContainer: root.bgSurfaceContainer
    readonly property color surfaceContainerHigh: root.bgSurfaceContainerHigh
    readonly property color surfaceContainerLowest: root.bgSurfaceContainerLowest
    readonly property color outline: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber")
        ? root.primary
        : root.outlineColor
    readonly property color outlineVariant: root.outlineVariantColor

    readonly property color primary: root.accentPrimary
    readonly property color primaryContainer: root.accentPrimaryContainer
    readonly property color secondary: root.accentSecondary
    readonly property color secondaryContainer: root.accentSecondaryContainer
    readonly property color error: root.accentError
    readonly property color errorContainer: root.accentErrorContainer
    readonly property color warning: root.accentWarning
    readonly property color warningContainer: root.accentWarningContainer
    readonly property color info: root.accentInfo
    readonly property color infoContainer: root.accentInfoContainer
    readonly property color success: root.accentSuccess
    readonly property color successContainer: root.accentSuccessContainer

    readonly property color textOnPrimary: root.accentOnPrimary
    readonly property color textOnPrimaryContainer: root.accentOnPrimaryContainer
    readonly property color textOnSurface: root.textMain
    readonly property color textOnSurfaceVariant: root.textMuted
    readonly property color textOnError: root.accentOnError
    readonly property color textOnErrorContainer: root.accentOnErrorContainer
    readonly property color textOnWarning: root.accentOnWarning
    readonly property color textOnWarningContainer: root.accentOnWarningContainer
    readonly property color textOnInfo: root.accentOnInfo
    readonly property color textOnInfoContainer: root.accentOnInfoContainer
    readonly property color textOnSuccess: root.accentOnSuccess
    readonly property color textOnSuccessContainer: root.accentOnSuccessContainer
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
        readonly property color onErrorVal: root.accentOnError
        readonly property color onErrorContainerVal: root.accentOnErrorContainer
        readonly property color onWarningVal: root.accentOnWarning
        readonly property color onWarningContainerVal: root.accentOnWarningContainer
        readonly property color onInfoVal: root.accentOnInfo
        readonly property color onInfoContainerVal: root.accentOnInfoContainer
        readonly property color onSuccessVal: root.accentOnSuccess
        readonly property color onSuccessContainerVal: root.accentOnSuccessContainer
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
    readonly property alias onWarning: tokenBridge.onWarningVal
    readonly property alias onWarningContainer: tokenBridge.onWarningContainerVal
    readonly property alias onInfo: tokenBridge.onInfoVal
    readonly property alias onInfoContainer: tokenBridge.onInfoContainerVal
    readonly property alias onSuccess: tokenBridge.onSuccessVal
    readonly property alias onSuccessContainer: tokenBridge.onSuccessContainerVal
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
    readonly property color m3error: root.accentError
    readonly property color m3onError: root.accentOnError
    readonly property color m3errorContainer: root.accentErrorContainer
    readonly property color m3onErrorContainer: root.accentOnErrorContainer
    readonly property color m3warning: root.accentWarning
    readonly property color m3onWarning: root.accentOnWarning
    readonly property color m3warningContainer: root.accentWarningContainer
    readonly property color m3onWarningContainer: root.accentOnWarningContainer
    readonly property color m3info: root.accentInfo
    readonly property color m3onInfo: root.accentOnInfo
    readonly property color m3infoContainer: root.accentInfoContainer
    readonly property color m3onInfoContainer: root.accentOnInfoContainer
    readonly property color m3success: root.accentSuccess
    readonly property color m3onSuccess: root.accentOnSuccess
    readonly property color m3successContainer: root.accentSuccessContainer
    readonly property color m3onSuccessContainer: root.accentOnSuccessContainer
    readonly property color m3outline: root.outlineColor
    readonly property color m3outlineVariant: root.outlineVariantColor

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
    // GLASS PARAMETER TABLE - single source of truth for glass alpha + substrate.
    //
    // Liquid glass composites over an ARBITRARY wallpaper, so a fixed alpha
    // yields an unbounded surface luminance. Over a blown-out (white) backdrop
    // the surface washes out and light text collapses toward 1:1; over a black
    // one a light surface stops carrying dark text. Both modes must therefore
    // satisfy a two-sided legibility contract while still transmitting enough
    // backdrop to read as glass:
    //
    //   1. LEGIBILITY  - text reaches WCAG AA (4.5:1) on its own surface over
    //                    the worst-case backdrop (white for dark mode, black
    //                    for light mode).
    //   2. TRANSMISSION- the substrate stays translucent so the compositor
    //                    blur remains visible instead of reading as a slab.
    //
    // The contract is enforced by tests/tst_glass_contrast_contract.qml, which
    // parses this table. Alphas are the *minimum* satisfying (1) with margin,
    // so any increase silently costs transparency and any decrease breaks
    // legibility - do not tune them without re-running that suite.
    //
    // CRITICAL - THE STACK, NOT THE LAYERS. Cards are drawn ON TOP of the plate,
    // so the surface the user actually looks through is plate + card. Two
    // independently-reasonable alphas multiply: a 0.76 plate under a 0.78 card
    // transmits only (1-0.755)(1-0.78) = 5.4% of the wallpaper, which renders as
    // an opaque slab no matter how correct each layer is in isolation. Per the
    // three-tier hierarchy in docs/LESSONS.md 9.2, cards are Tier 2 and
    // *inherit blur from Tier 1* - they are a definition tint that separates a
    // card from the plate, NOT a second load-bearing glass layer. Hence
    // cardAlpha is an order of magnitude below surfaceAlpha in effect, and
    // legibility is provided by the plate beneath. The suite asserts the
    // combined transmission, and also that the card stays visually distinct
    // from the plate (a card that transmits perfectly but is invisible fails).
    //
    // Note: the structural plate carries BOTH primary and muted text - the
    // dashboard tab labels and MediaTab metadata render directly on it, with no
    // card underneath - so the plate must clear AA for the dimmer muted token
    // too.
    readonly property var glassParams: ({
        dark: {
            // Pure black substrate maximizes contrast per unit alpha, which lets
            // the plate be substantially more transparent than a lifted
            // substrate can at equal legibility (a 0.01 grey costs ~2%
            // transmission for nothing).
            surfaceBase: [0.0, 0.0, 0.0],
            surfaceAlpha: 0.45,
            surfaceTint: 0.04,
            cardBase: [0.0, 0.0, 0.0],
            cardAlpha: 0.10,
            cardTint: 0.10,
            cardHoverAlpha: 0.30,
            cardHoverTint: 0.14,
            cardActiveAlpha: 0.40,
            cardActiveTint: 0.20,
            cardVibrantAlpha: 0.30,
            cardVibrantTint: 0.30,
            // Large content panels (the Copilot card, the settings pane): a
            // lifted dark base at high alpha, because a page of options must stay
            // legible over a bright wallpaper instead of dissolving into it.
            panelBase: [0.07, 0.08, 0.12],
            panelAlpha: 0.82
        },
        light: {
            surfaceBase: [1.0, 1.0, 1.0],
            surfaceAlpha: 0.45,
            surfaceTint: 0.06,
            cardBase: [1.0, 1.0, 1.0],
            cardAlpha: 0.10,
            cardTint: 0.06,
            cardHoverAlpha: 0.26,
            cardHoverTint: 0.14,
            cardActiveAlpha: 0.36,
            cardActiveTint: 0.22,
            cardVibrantAlpha: 0.28,
            cardVibrantTint: 0.30
,
            panelBase: [0.95, 0.96, 0.99],
            panelAlpha: 0.84
        }
    })

    readonly property var glassActive: {
        const p = (typeof Theme !== "undefined" && Theme.activeArchetype && Theme.activeArchetype.glassParams)
            ? Theme.activeArchetype.glassParams
            : root.glassParams;
        return root.isDarkMode ? (p.dark || root.glassParams.dark) : (p.light || root.glassParams.light);
    }

    readonly property real blurStrength: (typeof Config !== "undefined" && Config.themeBlurStrength !== undefined) ? Config.themeBlurStrength : 0.85
    readonly property real blurStrengthScale: Math.max(0.1, root.blurStrength / 0.85)

    function glassTinted(baseVec, alpha, tintAmount) {
        const effectiveAlpha = Math.min(1.0, Math.max(0.05, alpha * root.blurStrengthScale));
        return Qt.tint(
            Qt.rgba(baseVec[0], baseVec[1], baseVec[2], effectiveAlpha),
            Qt.alpha(root.primary, tintAmount)
        );
    }

    // Master structural plate: rich smoked liquid glass (dark) / crystalline
    // milk glass (light). Carries both primary and muted text.
    readonly property color glassSurface: glassTinted(
        root.glassActive.surfaceBase, root.glassActive.surfaceAlpha, root.glassActive.surfaceTint)

    // Modal sheet surface (Command Launcher, Central Dropdown)
    readonly property color glassModalSurface: glassSurface

    // Dock capsule surface (Left Dock)
    readonly property color glassDockSurface: glassSurface

    // Border frame surface
    readonly property color glassBorderSurface: glassSurface

    // Content cards: a deeper substrate than the plate. In dark mode the
    // substrate is dark (overlays darken, they do not add a white veil that
    // would wash out light text over bright wallpapers); in light mode it is
    // a near-white frosted plate.
    readonly property color glassCard: glassTinted(
        root.glassActive.cardBase, root.glassActive.cardAlpha, root.glassActive.cardTint)
    readonly property color glassCardHover: glassTinted(
        root.glassActive.cardBase, root.glassActive.cardHoverAlpha, root.glassActive.cardHoverTint)
    readonly property color glassCardActive: glassTinted(
        root.glassActive.cardBase, root.glassActive.cardActiveAlpha, root.glassActive.cardActiveTint)

    // Readable substrate for large content panels - the Copilot card and the
    // settings content pane. Nearly opaque so options and long text stay legible
    // over any wallpaper, still translucent enough to read as glass.
    readonly property color glassPanelSubstrate: glassTinted(
        root.glassActive.panelBase, root.glassActive.panelAlpha, root.isDarkMode ? 0.04 : 0.03)

    // Vibrant tinted glass card (e.g. Media Player, Highlighted cards)
    readonly property color glassCardVibrant: glassTinted(
        root.glassActive.cardBase, root.glassActive.cardVibrantAlpha, root.glassActive.cardVibrantTint)

    // Frosted interactive pills
    readonly property color glassPill: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber")
        ? Qt.rgba(0.04, 0.05, 0.08, 0.92)
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.09 : 0.50),
            Qt.alpha(root.primary, root.isDarkMode ? 0.08 : 0.05)
        )
    readonly property color glassPillHover: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber")
        ? Qt.tint(Qt.rgba(0.04, 0.05, 0.08, 0.95), Qt.alpha(root.primary, 0.20))
        : Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.16 : 0.65),
            Qt.alpha(root.primary, root.isDarkMode ? 0.16 : 0.10)
        )
    // Active / Prominent Themed Glass Pill (Luminous translucent frosted glass with theme color)
    readonly property color glassPillActive: Qt.tint(
        Qt.alpha(root.primaryContainer, root.isDarkMode ? 0.65 : 0.80),
        Qt.alpha(root.primary, 0.35)
    )

    // Directional specular rim highlights (ultra-fine 1px hairline catch with luminous theme glint)
    readonly property color glassBorderSpecular: {
        if (typeof Theme !== "undefined" && Theme.material) {
            if (Theme.material.surfaceStyle === "neon_cyber") {
                return Qt.alpha(root.primary, 0.95);
            } else if (!Theme.material.specularEnabled) {
                return root.isDarkMode ? Qt.alpha(root.outline, 0.35) : Qt.alpha(root.outline, 0.25);
            }
        }
        return Qt.tint(
            Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.80 : 0.95),
            Qt.alpha(root.primary, root.isDarkMode ? 0.35 : 0.20)
        );
    }
    readonly property color glassBorderSubtle: {
        if (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber") {
            return Qt.alpha(root.primary, 0.60);
        }
        return root.isDarkMode
            ? Qt.tint(Qt.rgba(1.0, 1.0, 1.0, 0.18), Qt.alpha(root.primary, 0.20))
            : Qt.rgba(0.0, 0.0, 0.0, 0.12);
    }
    readonly property color glassInnerRim: (typeof Theme !== "undefined" && Theme.material && Theme.material.surfaceStyle === "neon_cyber")
        ? Qt.alpha(root.primary, 0.40)
        : Qt.rgba(1.0, 1.0, 1.0, root.isDarkMode ? 0.18 : 0.45)

    // Text vibrancy halo: a soft outline painted under glyphs that sit on glass.
    // Liquid glass transmits the wallpaper, so a glyph's local backdrop is
    // unbounded - over a bright wallpaper light text would collapse toward 1:1
    // unless the glass is made opaque, which destroys the material. Protecting
    // the glyphs instead (the technique Apple calls vibrancy) keeps the plate
    // genuinely transparent AND the text legible at any alpha. Mode-aware: a
    // dark halo guards light text, a light halo guards dark text.
    readonly property color glassTextHalo: root.isDarkMode
        ? Qt.rgba(0.0, 0.0, 0.0, 0.62)
        : Qt.rgba(1.0, 1.0, 1.0, 0.75)

    // Optical refraction caustic glow
    readonly property color glassCausticGlow: Qt.alpha(root.primary, root.isDarkMode ? 0.28 : 0.18)
    readonly property color glassShadowColor: Qt.rgba(0, 0, 0, root.isDarkMode ? 0.45 : 0.14)


    // Dynamic color loader (reads the matugen cache written by the daemon)
    //
    // The cache lives under XDG_CACHE_HOME; falling back to `$HOME/.cache`
    // unconditionally would silently read a stale palette on any machine that
    // redirects the XDG cache directory.
    readonly property string cacheHome: {
        if (typeof Quickshell === "undefined" || !Quickshell.env) return "";
        const xdg = Quickshell.env("XDG_CACHE_HOME");
        if (xdg && xdg.length > 0) return xdg;
        const home = Quickshell.env("HOME");
        return (home && home.length > 0) ? home + "/.cache" : "";
    }
    // Parse and apply the generated palette.
    //
    // Shared by the first read and every watched rewrite: `loaded` fires only
    // once, so a palette regenerated while the shell runs is delivered as
    // `fileChanged`. Without this the accent kept the colours of whatever
    // wallpaper was active when the shell started.
    function applyPalette() {
        try {
            const text = colorsCache.text();
            if (text && text.trim().length > 0) {
                const parsed = JSON.parse(text);
                if (parsed.colors) {
                    root.dynamicPalette = parsed.colors;
                }
            }
        } catch (e) {
            Log.info("palette", "Using default Astral Plasma scheme: " + e);
        }
    }

    FileView {
        id: colorsCache
        path: root.cacheHome.length > 0 ? root.cacheHome + "/astral-plasma/colors.json" : ""
        preload: true
        // The palette is regenerated whenever the wallpaper changes, while the
        // shell keeps running. Matugen rewrites the file from another process,
        // so without watching it the shell would keep the palette it loaded at
        // start-up - the accent would show the colours of whatever wallpaper was
        // active back then (reported as "the dynamic accent is pinky").
        watchChanges: true
        onLoaded: root.applyPalette()
        // `fileChanged` only announces the change - the contents are still the
        // old ones until reload() re-reads them, after which `loaded` fires and
        // applies the new palette.
        onFileChanged: colorsCache.reload()
    }
}
