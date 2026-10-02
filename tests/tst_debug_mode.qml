import QtQuick
import "../settings_gui/pages"
import "../services"
import "../services/Logging.js" as Logging

Item {
    id: testRoot
    width: 800
    height: 600

    // Mock settings object simulating Config.qml
    property var settings: ({
        "debugMode": false,
        "logging": { "level": "info", "categories": {} }
    })

    readonly property bool debugMode: settings.debugMode ?? false
    readonly property bool freezeAutoClose: debugMode

    // The picker drives a level; the system page reports it back so the value
    // survives the mock's object replacement the way Config's reactive
    // settings do.
    property string logLevel: (settings.logging && settings.logging.level) ? settings.logging.level : "info"

    function setDebugMode(val) {
        let copy = JSON.parse(JSON.stringify(settings));
        copy.debugMode = val;
        settings = copy;
    }

    function setLogLevel(level) {
        let copy = JSON.parse(JSON.stringify(settings));
        if (!copy.logging) copy.logging = {};
        copy.logging.level = level;
        settings = copy;
        logLevel = level;
        sysPage.testLogLevel = level;
    }

    SystemPage {
        id: sysPage
        anchors.fill: parent
        testMode: true
        testDebugMode: testRoot.debugMode
        testLogLevel: testRoot.logLevel
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    function runTests() {
        console.log("RUNNING: Single Debug Mode Toggle & Decoupled Debug System Tests");

        // 1. Initial State: debugMode MUST default to false in production
        assert(testRoot.debugMode === false, "Debug Mode must default to false");
        assert(testRoot.freezeAutoClose === false, "freezeAutoClose must be false by default");
        assert(sysPage.debugModeActive === false, "SystemPage must report debugMode as inactive");

        // 2. Toggling Debug Mode ON
        testRoot.setDebugMode(true);
        sysPage.testDebugMode = testRoot.debugMode;
        assert(testRoot.debugMode === true, "Debug Mode must become active when toggled on");
        assert(testRoot.freezeAutoClose === true, "freezeAutoClose must be active when debugMode is true");
        assert(sysPage.debugModeActive === true, "SystemPage must reflect active debugMode");

        // 3. Toggling Debug Mode OFF
        testRoot.setDebugMode(false);
        sysPage.testDebugMode = testRoot.debugMode;
        assert(testRoot.debugMode === false, "Debug Mode must become inactive when toggled off");
        assert(testRoot.freezeAutoClose === false, "freezeAutoClose must be false when debugMode is false");
        assert(sysPage.debugModeActive === false, "SystemPage must reflect inactive debugMode");

        // 4. Verbosity is a level, not the boolean
        assert(sysPage.logLevelActive === "info",
            "SystemPage must show the configured log level, got: " + sysPage.logLevelActive);
        assert(sysPage.logLevelOptions.length === 6
                && sysPage.logLevelOptions[0] === "off"
                && sysPage.logLevelOptions[5] === "trace",
            "the picker must offer the whole ladder (off ... trace)");
        sysPage.selectLogLevel("debug");
        assert(sysPage.logLevelActive === "debug",
            "the picker's write path must set the level, got: " + sysPage.logLevelActive);
        sysPage.selectLogLevel("info");

        // The level - not the Debug Mode toggle - decides whether a trail prints.
        assert(!Logging.isEnabled("blur", "debug", testRoot.settings, {}),
            "the quiet default keeps the per-frame trails off");
        testRoot.setLogLevel("debug");
        assert(Logging.isEnabled("blur", "debug", testRoot.settings, {}),
            "raising the level turns the trails on");
        // ...and turning it down silences them without touching Debug Mode,
        // which only freezes the UI.
        testRoot.setLogLevel("warn");
        assert(!Logging.isEnabled("blur", "debug", testRoot.settings, {}),
            "a quieter level silences the per-frame trails");
        assert(Logging.isEnabled("blur", "warn", testRoot.settings, {}),
            "a quieter level still shows warnings");

        console.log("PASS: Single Debug Mode Toggle & Decoupled Debug System Tests");
        Qt.exit(0);
    }
}
