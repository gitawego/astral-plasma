import QtQuick
import "../components"

Item {
    id: testRoot
    width: 800
    height: 600

    PillButton {
        id: testPill
        accent: "primary"
        label: "Pill Action"
    }

    Timer {
        interval: 10
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
        return true;
    }

    function runTests() {
        console.log("=== Running Omarchy Borrowed Features Test Suite ===");

        // -------------------------------------------------------------
        // Test 1: Verify AI-Centric & Omarchy-inspired presets in Colors.qml
        // -------------------------------------------------------------
        console.log("Test 1: Omarchy Developer Palettes & AI Preset in Colors.qml");
        const colorsSrc = readLocalFile("../theme/Colors.qml");
        assert(colorsSrc.length > 1000, "theme/Colors.qml must be readable by the test harness");

        const requiredPresets = ["astral-ai", "catppuccin", "tokyo-night", "nord", "everforest", "gruvbox", "rose-pine"];
        for (let i = 0; i < requiredPresets.length; i++) {
            const key = requiredPresets[i];
            const hasPreset = colorsSrc.indexOf('"' + key + '":') !== -1;
            assert(hasPreset, "Colors.qml must contain theme preset '" + key + "'");

            // Verify both dark and light modes exist for this preset
            const blockStart = colorsSrc.indexOf('"' + key + '":');
            const blockChunk = colorsSrc.substr(blockStart, 1500);
            assert(blockChunk.indexOf("dark: {") !== -1, "Preset '" + key + "' must contain dark mode block");
            assert(blockChunk.indexOf("light: {") !== -1, "Preset '" + key + "' must contain light mode block");
            assert(blockChunk.indexOf("primary:") !== -1, "Preset '" + key + "' must define primary color");
            assert(blockChunk.indexOf("surface:") !== -1, "Preset '" + key + "' must define surface color");
            assert(blockChunk.indexOf("glassTint:") !== -1, "Preset '" + key + "' must define glassTint");
        }
        console.log("Passed Test 1: All 7 curated presets verified in Colors.qml");

        // -------------------------------------------------------------
        // Test 2: AI-Centric Reactive Aura & Semantic Tokens
        // -------------------------------------------------------------
        console.log("Test 2: AI Reactive Aura Tokens in Colors.qml");
        assert(colorsSrc.indexOf("aiActive") !== -1, "Colors.qml must define aiActive property");
        assert(colorsSrc.indexOf("aiActivityColor") !== -1, "Colors.qml must define aiActivityColor property");
        assert(colorsSrc.indexOf("aiGlowColor") !== -1, "Colors.qml must define aiGlowColor property");
        console.log("Passed Test 2: AI reactive aura tokens verified");

        // -------------------------------------------------------------
        // Test 3: PillButton Multi-Button Click Signals (Left, Right, Middle)
        // -------------------------------------------------------------
        console.log("Test 3: PillButton Multi-Button Signals");
        let leftClicked = false;
        let rightClicked = false;
        let middleClicked = false;

        testPill.clicked.connect(function() { leftClicked = true; });
        testPill.rightClicked.connect(function() { rightClicked = true; });
        testPill.middleClicked.connect(function() { middleClicked = true; });

        testPill.clicked();
        assert(leftClicked, "PillButton clicked signal must fire");
        testPill.rightClicked();
        assert(rightClicked, "PillButton rightClicked signal must fire");
        testPill.middleClicked();
        assert(middleClicked, "PillButton middleClicked signal must fire");

        // Verify PillButton.qml mouse area has acceptedButtons
        const pillSrc = readLocalFile("../components/PillButton.qml");
        assert(pillSrc.indexOf("acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton") !== -1,
               "PillButton.qml must accept Left, Right, and Middle mouse buttons");
        console.log("Passed Test 3: PillButton multi-button signals verified");

        // -------------------------------------------------------------
        // Test 4: ThemeExportService Architecture (SoC)
        // -------------------------------------------------------------
        console.log("Test 4: ThemeExportService Architecture & Formats");
        const exportSrc = readLocalFile("../services/ThemeExportService.qml");
        assert(exportSrc.length > 500, "ThemeExportService.qml must exist and be readable");
        assert(exportSrc.indexOf("formatToml") !== -1, "ThemeExportService must provide formatToml");
        assert(exportSrc.indexOf("formatJson") !== -1, "ThemeExportService must provide formatJson");
        assert(exportSrc.indexOf("formatEnv") !== -1, "ThemeExportService must provide formatEnv");
        assert(exportSrc.indexOf("colors.toml") !== -1, "ThemeExportService must target colors.toml");
        assert(exportSrc.indexOf("current-palette.json") !== -1, "ThemeExportService must target current-palette.json");
        assert(exportSrc.indexOf("agent-theme.env") !== -1, "ThemeExportService must target agent-theme.env");
        console.log("Passed Test 4: ThemeExportService file generation contracts verified");

        // -------------------------------------------------------------
        // Test 5: CommandLauncher AI-First Prompt Mode
        // -------------------------------------------------------------
        console.log("Test 5: CommandLauncher AI Prompt Dispatch Mode");
        const launcherSrc = readLocalFile("../shell/CommandLauncher.qml");
        assert(launcherSrc.length > 1000, "CommandLauncher.qml must be readable");
        assert(launcherSrc.indexOf("isAiMode") !== -1, "CommandLauncher must define isAiMode");
        assert(launcherSrc.indexOf("aiPromptText") !== -1, "CommandLauncher must extract aiPromptText");
        assert(launcherSrc.indexOf("Ask AI Agent") !== -1, "CommandLauncher must suggest Ask AI Agent");
        assert(launcherSrc.indexOf("launchAgent") !== -1, "CommandLauncher must dispatch via launchAgent");
        console.log("Passed Test 5: CommandLauncher AI Prompt Dispatch verified");

        // -------------------------------------------------------------
        // Test 6: DesktopSessionFacade & Dock Multi-Action Gestures
        // -------------------------------------------------------------
        console.log("Test 6: Facade Popout Toggle & Dock Status Icons Multi-Gestures");
        const facadeSrc = readLocalFile("../services/DesktopSessionFacade.qml");
        assert(facadeSrc.indexOf("function togglePopout(name)") !== -1, "DesktopSessionFacade must expose togglePopout(name)");

        const dockStatusSrc = readLocalFile("../dock/components/DockStatusIcons.qml");
        assert(dockStatusSrc.indexOf("audioItem") !== -1, "DockStatusIcons must feature audioItem");
        assert(dockStatusSrc.indexOf("PipewireAudio.toggleMute()") !== -1, "DockStatusIcons must support right-click mute toggle");
        assert(dockStatusSrc.indexOf("PipewireAudio.setVolume(") !== -1, "DockStatusIcons must support wheel volume scrubbing");
        assert(dockStatusSrc.indexOf("BluetoothService.togglePower()") !== -1, "DockStatusIcons must support right-click Bluetooth toggle");
        assert(dockStatusSrc.indexOf("PowerService.cycleProfile()") !== -1, "DockStatusIcons must support middle-click Power Profile cycle");
        assert(dockStatusSrc.indexOf("AiTokenService.launchAgent()") !== -1, "DockStatusIcons must support right-click AI Agent launch");

        const dockClockSrc = readLocalFile("../dock/components/DockClock.qml");
        assert(dockClockSrc.indexOf("is24Hour") !== -1, "DockClock must support toggling 24h format");

        // -------------------------------------------------------------
        // Test 7: Review regressions - export service must actually run
        // -------------------------------------------------------------
        console.log("Test 7: ThemeExportService wiring, opt-out, hook path, popout toggle");
        const shellSrc = readLocalFile("../shell.qml");
        assert(shellSrc.indexOf("ThemeExportService") !== -1, "shell.qml must instantiate ThemeExportService (singletons are lazy)");
        assert(exportSrc.indexOf("aiThemeSyncEnabled") !== -1, "ThemeExportService must honour Config.aiThemeSyncEnabled");
        assert(exportSrc.indexOf("hooks/on-theme-change.sh") !== -1, "hook path must be hooks/on-theme-change.sh");
        assert(exportSrc.indexOf("hooks/theme-set") === -1, "legacy hooks/theme-set path must be gone");
        assert(exportSrc.indexOf("Colors.glassTint") === -1, "Colors.glassTint does not exist; must not be exported");
        assert(exportSrc.indexOf("ASTRAL_SURFACE") !== -1 && exportSrc.indexOf("ASTRAL_PRIMARY") !== -1 && exportSrc.indexOf("ASTRAL_AI_COLOR") !== -1, "agent-theme.env must carry ASTRAL_SURFACE/PRIMARY/AI_COLOR");
        assert(exportSrc.indexOf("target: (typeof Colors") !== -1, "export must re-run when Colors (wallpaper palette) change");
        assert(dockClockSrc.indexOf("Config.toggleBottomPopout(\"clock\"") !== -1, "DockClock middle-click must toggle (not only open) the clock popout");
        console.log("Passed Test 7");

        console.log("PASS: Omarchy Borrowed Features Test Suite Passed Successfully");
        Qt.exit(0);
    }
}
