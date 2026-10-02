import QtQuick
import "../services/Logging.js" as Logging

// ============================================================================
// Log Level Contract
// ============================================================================
// The shell used to have one boolean (`debugMode`) for every diagnostic trail:
// turning it on to investigate the glass emitted per-frame lines (`[BlurAudit]
// active: (none)`, `[CommitPump] ...`) that buried everything else, and there was
// no way to keep one category verbose without keeping them all verbose.
//
// Levels replace the boolean: each message carries a level, each category can be
// tuned on its own, the shipped default stays quiet, and the Debug Mode toggle
// keeps working as the legacy "show me everything" switch. All of the decisions
// live in `services/Logging.js` so they can be asserted here without a session;
// the QML singleton (`services/Log.qml`) is a thin shell over that core.
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        // Cache-buster: Qt caches file:// reads, so a guard can silently test
        // STALE source and pass while the real file has changed.
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Log Level Contract");

        // --------------------------------------------------------------------
        // The level ladder
        // --------------------------------------------------------------------
        assert(Logging.rank("off") < Logging.rank("error"), "off is quieter than error");
        assert(Logging.rank("error") < Logging.rank("warn"), "error is quieter than warn");
        assert(Logging.rank("warn") < Logging.rank("info"), "warn is quieter than info");
        assert(Logging.rank("info") < Logging.rank("debug"), "info is quieter than debug");
        assert(Logging.rank("debug") < Logging.rank("trace"), "debug is quieter than trace");

        assert(Logging.parseLevel("DEBUG") === "debug", "levels are case-insensitive");
        assert(Logging.parseLevel(" info ") === "info", "surrounding whitespace is ignored");
        assert(Logging.parseLevel("") === null, "an empty level is not a level");
        assert(Logging.parseLevel("nonsense") === null, "an unknown level is not a level");
        assert(Logging.normalize("nonsense") === Logging.DEFAULT_LEVEL,
            "an unknown level falls back to the quiet default");
        assert(Logging.rank("bogus") === Logging.rank(Logging.DEFAULT_LEVEL),
            "an unparseable level must not be louder than the default");

        // --------------------------------------------------------------------
        // The shipped default is quiet
        // --------------------------------------------------------------------
        const shipped = JSON.parse(readLocalFile("../config/settings.json"));
        assert(shipped.logging && shipped.logging.level,
            "the shipped settings must carry a logging block");
        assert(shipped.logging.level === Logging.DEFAULT_LEVEL,
            "the shipped level (" + shipped.logging.level + ") and the code default ("
            + Logging.DEFAULT_LEVEL + ") must agree");
        assert(Logging.rank(shipped.logging.level) <= Logging.rank("info"),
            "the shipped default must be info or quieter, got " + shipped.logging.level);

        assert(!Logging.isEnabled("blur", "debug", shipped, {}),
            "per-frame blur traces must be OFF by default");
        assert(Logging.isEnabled("blur", "warn", shipped, {}),
            "warnings stay visible by default");
        assert(Logging.isEnabled("blur", "error", shipped, {}),
            "errors stay visible by default");

        // --------------------------------------------------------------------
        // Per-category tuning: verbose where it helps, quiet everywhere else
        // --------------------------------------------------------------------
        const tuned = { logging: { level: "warn", categories: { blur: "debug" } } };
        assert(Logging.isEnabled("blur", "debug", tuned, {}),
            "a category override raises exactly that category");
        assert(!Logging.isEnabled("commit", "debug", tuned, {}),
            "a category override leaves the other categories quiet");
        assert(Logging.levelFor("blur", tuned, {}) === "debug",
            "the resolved level is what the UI and the trails report");

        // --------------------------------------------------------------------
        // Environment overrides: one run, no file edit
        // --------------------------------------------------------------------
        assert(Logging.isEnabled("commit", "trace", tuned, { level: "trace" }),
            "ASTRAL_PLASMA_LOG_LEVEL raises the level for one run");
        assert(Logging.isEnabled("blur", "debug", { logging: { level: "off" } },
                { categories: { blur: "debug" } }),
            "a per-category env override beats the configured level");
        const parsed = Logging.parseCategories("blur=debug, commit=trace, broken, =info");
        assert(parsed.blur === "debug" && parsed.commit === "trace",
            "ASTRAL_PLASMA_LOG_CATEGORIES parses category=level pairs");
        assert(parsed.broken === undefined && parsed[""] === undefined,
            "malformed category entries are ignored, not guessed");

        // --------------------------------------------------------------------
        // Legacy Debug Mode still works, but an explicit level wins
        // --------------------------------------------------------------------
        assert(Logging.isEnabled("blur", "debug", { debugMode: true }, {}),
            "Debug Mode keeps showing every trail when no level is configured");
        assert(!Logging.isEnabled("blur", "debug", { debugMode: true, logging: { level: "warn" } }, {}),
            "an explicit level beats the legacy toggle");
        assert(Logging.isEnabled("blur", "error", { debugMode: true }, { level: "off" }) === false,
            "off silences everything, even the legacy toggle");

        // --------------------------------------------------------------------
        // Formatting: the category is the log line's identity
        // --------------------------------------------------------------------
        assert(Logging.format("blur", "active: 3") === "[blur] active: 3",
            "a line is prefixed with its category, got: " + Logging.format("blur", "active: 3"));

        // --------------------------------------------------------------------
        // Wiring: the shell's trails go through the logger
        // --------------------------------------------------------------------
        const shell = readLocalFile("../shell/UnifiedShell.qml");
        assert(shell.length > 1000, "UnifiedShell.qml must be readable by the harness");
        assert(shell.indexOf("Log.debug(") >= 0,
            "UnifiedShell must log its diagnostic trails through Log");
        assert(shell.indexOf("Log.debugEnabled(") >= 0,
            "the per-frame trails must be guarded before building their strings");
        assert(shell.indexOf('console.log("[BlurAudit]') < 0
                && shell.indexOf('console.log("[CommitPump]') < 0
                && shell.indexOf('console.log("[BlurRegion]') < 0,
            "raw console.log trails must be replaced by the leveled logger");

        const log = readLocalFile("../services/Log.qml");
        assert(log.indexOf("Logging.levelFor(") >= 0 && log.indexOf("Logging.isEnabled(") >= 0,
            "the singleton must resolve levels through the pure core");
        assert(log.indexOf("function emit(") >= 0 && log.indexOf("console.warn(line)") >= 0
                && log.indexOf("console.error(line)") >= 0 && log.indexOf("console.info(line)") >= 0
                && log.indexOf("console.debug(line)") >= 0,
            "the singleton owns the console channels, one per level, so Qt's prefix matches ours");

        // The setting and its UI: a level has to be reachable without editing
        // files by hand, and both live in the reactive config.
        const config = readLocalFile("../config/Config.qml");
        assert(config.indexOf("readonly property string logLevel") >= 0,
            "Config must expose the level reactively");
        assert(config.indexOf("function setLogLevel(") >= 0,
            "Config must accept a level change");
        assert(config.indexOf("function setLogCategoryLevel(") >= 0,
            "Config must accept a per-category override");
        const page = readLocalFile("../settings_gui/pages/SystemPage.qml");
        assert(page.indexOf("Config.setLogLevel(") >= 0,
            "the settings UI must write the level through Config");
        assert(page.indexOf("logLevelOptions") >= 0,
            "the settings UI must offer the whole level ladder");

        console.log("PASS: Log Level Contract");
        Qt.exit(0);
    }
}
