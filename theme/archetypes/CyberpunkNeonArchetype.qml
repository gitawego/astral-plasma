import QtQuick

ThemeArchetype {
    id: root

    archetypeId: "cyberpunk_neon"
    name: "Cyberpunk Neon"
    description: "High-tech dystopian sci-fi aesthetic: sharp angular geometry, deep OLED black substrates, neon perimeter bloom, high-contrast borders, mechanical snappy physics, and monospace-first typography."
    author: "Astral Plasma Team"
    version: "1.0.0"

    // Geometry: Razor-sharp 0px rectangular corners, dense technical grid
    filletRounding: 0
    radiusFull: 0
    radiusLarge: 0
    radiusMedium: 0
    radiusSmall: 0
    radiusExtraSmall: 0

    radiusGlassModal: 0
    radiusGlassCard: 0
    radiusGlassItem: 0
    radiusGlassPill: 0

    // Optical surfaces: Laser neon borders & deep OLED void black (Zero glares, zero soft shadows)
    surfaceStyle: "neon_cyber"
    specularEnabled: false
    causticEnabled: false
    shadowsEnabled: false
    innerRimEnabled: false

    glassSpecularWidth: 0.0
    glassBorderWidth: 1.0
    glassCausticIntensity: 0.0
    shadowElevationScale: 0.0

    // Glass parameters: OLED Void Black substrate with laser neon tinting
    glassParams: ({
        dark: {
            surfaceBase: [0.02, 0.02, 0.04],
            surfaceAlpha: 0.95,
            surfaceTint: 0.04,
            cardBase: [0.03, 0.03, 0.06],
            cardAlpha: 0.92,
            cardTint: 0.06,
            cardHoverAlpha: 0.96,
            cardHoverTint: 0.14,
            cardActiveAlpha: 0.98,
            cardActiveTint: 0.22,
            cardVibrantAlpha: 0.85,
            cardVibrantTint: 0.35,
            panelBase: [0.02, 0.02, 0.04],
            panelAlpha: 0.98
        },
        light: {
            surfaceBase: [0.92, 0.93, 0.98],
            surfaceAlpha: 0.92,
            surfaceTint: 0.06,
            cardBase: [0.96, 0.97, 1.0],
            cardAlpha: 0.94,
            cardTint: 0.08,
            cardHoverAlpha: 0.98,
            cardHoverTint: 0.14,
            cardActiveAlpha: 1.0,
            cardActiveTint: 0.18,
            cardVibrantAlpha: 0.85,
            cardVibrantTint: 0.25,
            panelBase: [0.90, 0.91, 0.95],
            panelAlpha: 0.96
        }
    })

    // Archetype-driven palette overrides (Domain-Driven Design: Deep OLED Void Black substrates)
    paletteDark: ({
        surface: "#05070D",
        surface_container: "#090C15",
        surface_container_high: "#0F1320",
        surface_container_lowest: "#020305",
        surface_variant: "#141824",
        outline_variant: "#007A82",
        on_surface: "#E0F8FF",
        on_surface_variant: "#80C8D8",
        glassTint: "#00F0FF"
    })
    paletteLight: ({
        surface: "#F4F7FC",
        surface_container: "#E8ECF4",
        surface_container_high: "#DCE1EC",
        surface_container_lowest: "#FFFFFF",
        surface_variant: "#D0D6E4",
        outline_variant: "#7090A0",
        on_surface: "#101822",
        on_surface_variant: "#3A4554",
        glassTint: "#008899"
    })

    // Motion: Mechanical, hyper-snappy transitions
    glassScaleBounce: 0.97
    animGlassPress: 60
    animGlassRelease: 120
    curveGlassElastic: [0.1, 0.9, 0.2, 1.0, 1.0, 1.0]

    animDurationFast: 80
    animDurationNormal: 140
    animDurationSlow: 220

    animExpressiveFastSpatial: 140
    animExpressiveDefaultSpatial: 200
    animExpressiveSlowSpatial: 280
    curveExpressiveDefaultSpatial: [0.0, 0.0, 0.15, 1.0, 1.0, 1.0]

    fontFamily: "JetBrains Mono, monospace"
    fontMonospace: "JetBrains Mono, monospace"

    // Media Presentation: Dystopian high-tech circular cover with sharp cyber radial spectrum ring
    mediaCircularCover: true
    mediaOrbitalRing: true
    mediaVinylSpin: false
    mediaCoverStyle: "cyber_radial"
    defaultHostAvatar: Qt.resolvedUrl("../assets/cyberpunk-avatar.webp").toString()
}

