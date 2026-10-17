import QtQuick
import "../config"

Item {
    id: testRoot
    width: 800
    height: 600

    property string dockSource: ""
    property string settingsSource: ""

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    Component.onCompleted: {
        console.log("RUNNING: Dock System Tray Auto-Expand Budget Tests");

        dockSource = readLocalFile("../shell/UnifiedDock.qml");
        settingsSource = readLocalFile("../config/settings.json");
        const configSource = readLocalFile("../config/Config.qml");
        const dockPageSource = readLocalFile("../settings_gui/pages/DockPage.qml");

        // 1. Settings default contract: tray.autoExpand must be enabled by default
        assert(settingsSource.indexOf("\"autoExpand\": true") >= 0,
            "config/settings.json must configure tray.autoExpand: true");
        assert(configSource.indexOf("\"autoExpand\": true") >= 0,
            "config/Config.qml defaultSettings must configure tray.autoExpand: true");
        assert(configSource.indexOf("dockTrayAutoExpand") >= 0,
            "config/Config.qml must define dockTrayAutoExpand getter");
        assert(configSource.indexOf("function setDockTrayAutoExpand") >= 0,
            "config/Config.qml must define setDockTrayAutoExpand setter");
        assert(dockPageSource.indexOf("Config.dockTrayAutoExpand") >= 0,
            "settings_gui/pages/DockPage.qml must bind to Config.dockTrayAutoExpand");
        assert(dockPageSource.indexOf("Config.setDockTrayAutoExpand") >= 0,
            "settings_gui/pages/DockPage.qml must invoke Config.setDockTrayAutoExpand");

        // 2. Dock budget calculation logic test
        // Simulate dock geometry constants
        const iconS = 32;
        const listBudget = 600;
        const trayMinHeight = 2 * (iconS - 4 + 2) + 12; // 72px

        function calcTrayMaxHeight(trayNaturalHeight, appsNaturalHeight, autoExpand) {
            const trayAutoExpand = autoExpand;
            const trayAvailableBudget = trayAutoExpand
                ? Math.max(trayMinHeight,
                    Math.max(listBudget * 0.32, listBudget - Math.max(96, appsNaturalHeight)))
                : Math.max(trayMinHeight, listBudget * 0.32);
            return Math.min(trayNaturalHeight, trayAvailableBudget);
        }

        function calcAppsMaxHeight(appsNaturalHeight, trayMaxHeight) {
            return Math.max(96, Math.min(appsNaturalHeight, listBudget - trayMaxHeight));
        }

        // Test Scenario A: Normal desktop workload with 4 tray icons (130px) and 4 apps (150px)
        const tray4IconsHeight = 130;
        const apps4Height = 150;
        const trayMaxA = calcTrayMaxHeight(tray4IconsHeight, apps4Height, true);
        const appsMaxA = calcAppsMaxHeight(apps4Height, trayMaxA);

        assert(trayMaxA === 130,
            "When space permits and autoExpand is true, trayMaxHeight must equal natural height (130px), got " + trayMaxA);
        assert(appsMaxA === 150,
            "Apps must also receive full natural height (150px), got " + appsMaxA);

        // Test Scenario B: Many tray icons (8 icons = 250px) with 2 running apps (100px)
        const tray8IconsHeight = 250;
        const apps2Height = 100;
        const trayMaxB = calcTrayMaxHeight(tray8IconsHeight, apps2Height, true);
        assert(trayMaxB === 250,
            "Tray with 8 icons must expand to full 250px without scrolling when budget is 600px, got " + trayMaxB);

        // Test Scenario C: Legacy compact mode (autoExpand = false) caps at 32% (192px)
        const trayMaxCompact = calcTrayMaxHeight(tray8IconsHeight, apps2Height, false);
        assert(trayMaxCompact === 192,
            "When autoExpand is false, tray must cap at 32% of listBudget (192px), got " + trayMaxCompact);

        // Test Scenario D: Heavy contention (tray 350px, apps 500px, budget 600px)
        // Must guarantee apps at least 96px, and tray at least 32%
        const trayMaxHeavy = calcTrayMaxHeight(350, 500, true);
        assert(trayMaxHeavy >= 192 && trayMaxHeavy <= 600 - 96,
            "Under heavy contention, tray budget must balance between 32% floor and leaving 96px for apps, got " + trayMaxHeavy);

        // 3. UnifiedDock source contract
        assert(dockSource.indexOf("trayAutoExpand") >= 0,
            "UnifiedDock.qml must implement trayAutoExpand");
        assert(dockSource.indexOf("trayAvailableBudget") >= 0,
            "UnifiedDock.qml must compute trayAvailableBudget dynamically");

        console.log("PASS: Dock System Tray Auto-Expand Budget Tests");
        Qt.exit(0);
    }
}
