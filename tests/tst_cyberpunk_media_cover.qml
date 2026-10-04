import QtQuick
import "../theme"
import "../theme/archetypes"
import "../dashboard/tabs"

Item {
    id: testRoot
    width: 800
    height: 600

    CyberpunkNeonArchetype { id: cpArchetype }
    LiquidGlassArchetype { id: lgArchetype }
    NordicMinimalArchetype { id: nmArchetype }

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
        console.log("RUNNING: Cyberpunk Media Cover Archetype & Presentation Tests");

        // 1. Domain Archetype Token Verification for Cyberpunk Neon
        assert(cpArchetype.mediaCircularCover === true,
               "CyberpunkNeonArchetype mediaCircularCover must be true (circular cover with cyber radial visualizer)");
        assert(cpArchetype.mediaOrbitalRing === true,
               "CyberpunkNeonArchetype mediaOrbitalRing must be true (cyber radial spectrum ring enabled)");
        assert(cpArchetype.mediaVinylSpin === false,
               "CyberpunkNeonArchetype mediaVinylSpin must be false (zero vinyl spinning)");
        assert(cpArchetype.mediaCoverStyle === "cyber_radial",
               "CyberpunkNeonArchetype mediaCoverStyle must be 'cyber_radial'");

        // 2. Liquid Glass & Nordic Minimal Must Retain Circular Presentation (Zero Regressions)
        assert(lgArchetype.mediaCircularCover === true,
               "LiquidGlassArchetype mediaCircularCover must remain true");
        assert(lgArchetype.mediaOrbitalRing === true,
               "LiquidGlassArchetype mediaOrbitalRing must remain true");
        assert(lgArchetype.mediaVinylSpin === true,
               "LiquidGlassArchetype mediaVinylSpin must remain true");
        assert(lgArchetype.mediaCoverStyle === "circular",
               "LiquidGlassArchetype mediaCoverStyle must be 'circular'");

        assert(nmArchetype.mediaCircularCover === true,
               "NordicMinimalArchetype mediaCircularCover must remain true");
        assert(nmArchetype.mediaOrbitalRing === true,
               "NordicMinimalArchetype mediaOrbitalRing must remain true");
        assert(nmArchetype.mediaVinylSpin === true,
               "NordicMinimalArchetype mediaVinylSpin must remain true");

        // 3. Theme Singleton Delegation Facade Inspection
        const themeSrc = readLocalFile("../theme/Theme.qml");
        assert(/readonly\s+property\s+bool\s+mediaCircularCover:/.test(themeSrc),
               "Theme.qml must expose mediaCircularCover");
        assert(/readonly\s+property\s+bool\s+mediaOrbitalRing:/.test(themeSrc),
               "Theme.qml must expose mediaOrbitalRing");
        assert(/readonly\s+property\s+bool\s+mediaVinylSpin:/.test(themeSrc),
               "Theme.qml must expose mediaVinylSpin");
        assert(/readonly\s+property\s+string\s+mediaCoverStyle:/.test(themeSrc),
               "Theme.qml must expose mediaCoverStyle");
        assert(/readonly\s+property\s+bool\s+isCyberpunk:/.test(themeSrc),
               "Theme.qml must expose isCyberpunk");

        // 4. Component Cyber Style Capabilities
        const radVizSrc = readLocalFile("../components/RadialCoverVisualiser.qml");
        assert(/readonly\s+property\s+bool\s+isCyberStyle:/.test(radVizSrc),
               "RadialCoverVisualiser must expose isCyberStyle");
        assert(/cyberHudFrame/.test(radVizSrc),
               "RadialCoverVisualiser must include cyber HUD corner reticles");

        const radRingSrc = readLocalFile("../components/RadialCoverRing.qml");
        assert(/readonly\s+property\s+bool\s+isCyberStyle:/.test(radRingSrc),
               "RadialCoverRing must expose isCyberStyle");

        // 5. DashboardTab Source Contract Verification
        const dashSrc = readLocalFile("../dashboard/tabs/DashboardTab.qml");
        assert(/RadialCoverRing/.test(dashSrc),
               "DashboardTab must include RadialCoverRing for cyberpunk and radial styles");
        assert(/visible:\s*mediaCard\.showOrbitalRing\s*&&\s*!mediaCard\.isCyberpunk/.test(dashSrc),
               "vizSwitchBtn must be hidden in cyberpunk to prevent switching to cartoon notes");
        assert(/cyberProgressBar/.test(dashSrc),
               "DashboardTab must include cyberProgressBar for cyberpunk linear seek track");

        // 6. MediaTab Source Contract Verification
        const mediaSrc = readLocalFile("../dashboard/tabs/MediaTab.qml");
        assert(/RadialCoverVisualiser/.test(mediaSrc),
               "MediaTab must include RadialCoverVisualiser");
        assert(/visible:\s*visualizerSlot\.isCyberpunk\s*\|\|\s*!visualizerSlot\.isSpeakerStyle/.test(mediaSrc),
               "MediaTab must display RadialCoverVisualiser in Cyberpunk mode");

        console.log("PASS: Cyberpunk media cover presentation tests passed successfully!");
        Qt.exit(0);
    }
}

