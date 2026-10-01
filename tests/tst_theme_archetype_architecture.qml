import QtQuick
import "../theme/archetypes"
import "../components"

Item {
    id: testRoot
    width: 800
    height: 600

    // Concrete built-in archetype instances
    LiquidGlassArchetype { id: lgArchetype }
    NordicMinimalArchetype { id: nmArchetype }
    CyberpunkNeonArchetype { id: cpArchetype }

    // Custom 3rd-party Archetype instance proving extensible architecture
    ThemeArchetype {
        id: customSolarizedArchetype
        archetypeId: "solarized_paper"
        name: "Solarized Paper"
        description: "Low-contrast amber and cyan paper tone with flat borders and zero specular flare"
        radiusLarge: 8
        radiusGlassModal: 8
        radiusGlassCard: 4
        surfaceStyle: "paper_tint"
        specularEnabled: false
        causticEnabled: false
        glassBorderWidth: 1.5
        fontFamily: "Fira Code, monospace"
    }

    // Interactive UI components for visual reactivity verification
    LiquidGlassCard {
        id: sampleCard
        width: 200
        height: 100
    }

    LiquidGlassButton {
        id: sampleButton
        text: "Test Action"
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    function runTests() {
        console.log("RUNNING: Theme Archetype Architecture & Modularity Tests");

        // =====================================================================
        // 1. Built-in Archetype Conformance (Liquid Glass)
        // =====================================================================
        assert(lgArchetype.archetypeId === "liquid_glass", "lgArchetype.archetypeId must be 'liquid_glass'");
        assert(lgArchetype.name === "Liquid Glass", "lgArchetype name must be 'Liquid Glass'");
        assert(lgArchetype.surfaceStyle === "liquid_glass", "Default surfaceStyle must be 'liquid_glass'");
        assert(lgArchetype.specularEnabled === true, "Liquid glass must have specularEnabled == true");
        assert(lgArchetype.causticEnabled === true, "Liquid glass must have causticEnabled == true");
        assert(lgArchetype.shadowsEnabled === true, "Liquid glass must have shadowsEnabled == true");
        assert(lgArchetype.radiusLarge === 24, "Liquid glass radiusLarge must be 24");
        assert(lgArchetype.radiusGlassModal === 32, "Liquid glass radiusGlassModal must be 32");
        assert(lgArchetype.radiusGlassCard === 18, "Liquid glass radiusGlassCard must be 18");
        assert(lgArchetype.radiusGlassItem === 12, "Liquid glass radiusGlassItem must be 12");
        assert(lgArchetype.glassScaleBounce === 0.985, "Liquid glass glassScaleBounce must be 0.985");
        assert(lgArchetype.glassSpecularWidth === 1.0, "Liquid glass specular width must be 1.0");
        assert(lgArchetype.fontFamily.indexOf("Google Sans") !== -1, "Liquid glass font family must contain Google Sans");

        // =====================================================================
        // 2. Built-in Archetype Conformance (Nordic Minimal)
        // =====================================================================
        assert(nmArchetype.archetypeId === "nordic_minimal", "nmArchetype.archetypeId must be 'nordic_minimal'");
        assert(nmArchetype.name === "Nordic Minimal", "nmArchetype name must be 'Nordic Minimal'");
        assert(nmArchetype.surfaceStyle === "flat_minimal", "Nordic minimal surfaceStyle must be 'flat_minimal'");
        assert(nmArchetype.specularEnabled === false, "Nordic minimal must disable specular glares");
        assert(nmArchetype.causticEnabled === false, "Nordic minimal must disable caustics");
        assert(nmArchetype.shadowsEnabled === false, "Nordic minimal must disable drop shadows");
        assert(nmArchetype.radiusLarge === 12, "Nordic minimal radiusLarge must be 12");
        assert(nmArchetype.radiusGlassModal === 12, "Nordic minimal radiusGlassModal must be 12");
        assert(nmArchetype.radiusGlassCard === 6, "Nordic minimal radiusGlassCard must be 6");
        assert(nmArchetype.glassScaleBounce === 1.0, "Nordic minimal scale bounce must be 1.0 (flat)");
        assert(nmArchetype.fontFamily.indexOf("Inter") !== -1, "Nordic minimal font must contain Inter");

        // =====================================================================
        // 3. Built-in Archetype Conformance (Cyberpunk Neon)
        // =====================================================================
        assert(cpArchetype.archetypeId === "cyberpunk_neon", "cpArchetype.archetypeId must be 'cyberpunk_neon'");
        assert(cpArchetype.name === "Cyberpunk Neon", "cpArchetype name must be 'Cyberpunk Neon'");
        assert(cpArchetype.surfaceStyle === "neon_cyber", "Cyberpunk neon surfaceStyle must be 'neon_cyber'");
        assert(cpArchetype.specularEnabled === true, "Cyberpunk neon specularEnabled must be true");
        assert(cpArchetype.glassCausticIntensity === 0.18, "Cyberpunk neon glassCausticIntensity must be 0.18");
        assert(cpArchetype.glassBorderWidth === 1.5, "Cyberpunk neon glassBorderWidth must be 1.5");
        assert(cpArchetype.radiusLarge === 4, "Cyberpunk neon radiusLarge must be 4");
        assert(cpArchetype.radiusGlassModal === 6, "Cyberpunk neon radiusGlassModal must be 6");
        assert(cpArchetype.radiusGlassCard === 2, "Cyberpunk neon radiusGlassCard must be 2");
        assert(cpArchetype.fontFamily.indexOf("JetBrains Mono") !== -1, "Cyberpunk neon font must be JetBrains Mono");

        // =====================================================================
        // 4. Custom 3rd-Party Archetype Extensibility Contract
        // =====================================================================
        assert(customSolarizedArchetype.archetypeId === "solarized_paper", "Custom archetype ID must match");
        assert(customSolarizedArchetype.name === "Solarized Paper", "Custom archetype name must match");
        assert(customSolarizedArchetype.radiusLarge === 8, "Custom archetype radiusLarge must be 8");
        assert(customSolarizedArchetype.specularEnabled === false, "Custom archetype specularEnabled must be false");
        assert(customSolarizedArchetype.glassBorderWidth === 1.5, "Custom archetype glassBorderWidth must be 1.5");

        // =====================================================================
        // 5. Dynamic Archetype Registry & Resolution Contract
        // =====================================================================
        const testRegistry = {
            "liquid_glass": lgArchetype,
            "nordic_minimal": nmArchetype,
            "cyberpunk_neon": cpArchetype,
            "solarized_paper": customSolarizedArchetype
        };

        function resolveArchetype(key) {
            const normalized = (key || "liquid_glass").toLowerCase();
            return testRegistry[normalized] || testRegistry["liquid_glass"];
        }

        assert(resolveArchetype("liquid_glass").name === "Liquid Glass", "Resolve liquid_glass");
        assert(resolveArchetype("nordic_minimal").name === "Nordic Minimal", "Resolve nordic_minimal");
        assert(resolveArchetype("cyberpunk_neon").name === "Cyberpunk Neon", "Resolve cyberpunk_neon");
        assert(resolveArchetype("solarized_paper").name === "Solarized Paper", "Resolve custom 3rd-party theme");
        assert(resolveArchetype("unknown_nonexistent").name === "Liquid Glass", "Fallback on unknown theme");

        // =====================================================================
        // 6. Source Contract Inspection for Theme.qml & Architecture Wiring
        // =====================================================================
        const themeSrc = readLocalFile("../theme/Theme.qml");
        assert(themeSrc.length > 500, "Theme.qml must be readable");
        assert(/archetypeLiquidGlass:\s*LiquidGlassArchetype\s*\{/.test(themeSrc), 
               "Theme.qml must declare archetypeLiquidGlass");
        assert(/archetypeNordicMinimal:\s*NordicMinimalArchetype\s*\{/.test(themeSrc), 
               "Theme.qml must declare archetypeNordicMinimal");
        assert(/archetypeCyberpunkNeon:\s*CyberpunkNeonArchetype\s*\{/.test(themeSrc), 
               "Theme.qml must declare archetypeCyberpunkNeon");
        assert(/activeArchetype:/.test(themeSrc), 
               "Theme.qml must declare dynamic activeArchetype property");
        assert(/archetypeName:/.test(themeSrc), 
               "Theme.qml must declare archetypeName property");
        assert(/function\s+listArchetypes\(\)/.test(themeSrc), 
               "Theme.qml must provide listArchetypes() discovery function");
        assert(/material:\s*QtObject\s*\{/.test(themeSrc), 
               "Theme.qml must expose material facade");

        // =====================================================================
        // 7. Config & Settings Architecture Contract
        // =====================================================================
        const configSrc = readLocalFile("../config/Config.qml");
        assert(/themeArchetype/.test(configSrc), "Config.qml must expose themeArchetype");
        assert(/function\s+setThemeArchetype/.test(configSrc), "Config.qml must provide setThemeArchetype helper");

        const settingsJson = readLocalFile("../config/settings.json");
        assert(/"archetype"\s*:\s*"liquid_glass"/.test(settingsJson), 
               "settings.json must ship default theme archetype: liquid_glass");

        // =====================================================================
        // 8. Component Opt-In Properties for Material Effects
        // =====================================================================
        assert(sampleCard.showSpecular !== undefined, "Sample card must expose showSpecular property");
        assert(sampleCard.showCaustic !== undefined, "Sample card must expose showCaustic property");
        assert(sampleButton.showSpecular !== undefined, "Sample button must expose showSpecular property");
        assert(sampleButton.showCaustic !== undefined, "Sample button must expose showCaustic property");

        console.log("PASS: All Theme Archetype Architecture & Modularity Tests Passed!");
        Qt.exit(0);
    }
}
