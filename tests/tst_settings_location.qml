import QtQuick

// ============================================================================
// Settings Location Contract
// ============================================================================
// The app-folder `config/settings.json` is the SHIPPED DEFAULT. It lives in a
// git checkout, so treating it as the live file means:
//   - user preferences are mixed into version control and can be clobbered by
//     an update, and
//   - the checkout is dirty for every preference the user changes.
//
// The live file therefore belongs in the XDG config dir:
//   $XDG_CONFIG_HOME/astral-plasma/settings.json   (fallback: ~/.config/...)
//
// Loading must be defaults (+) shipped file (+) user file, with the user file
// winning, and saving must only ever touch the user file.
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(condition, message) {
        if (!condition) {
            console.log("FAIL: " + message);
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
        console.log("RUNNING: Settings Location Contract");

        const cfg = readLocalFile("../config/Config.qml");
        assert(cfg.length > 1000, "config/Config.qml must be readable by the harness");

        // 1. The app-folder file is the DEFAULTS, read through a relative path.
        assert(/readonly property string defaultConfigPath\s*:/.test(cfg),
            "Config.qml must name the app-folder file `defaultConfigPath` (the shipped defaults)");
        const defaultsDecl = cfg.match(/readonly property string defaultConfigPath\s*:([^\n]*)/);
        assert(defaultsDecl !== null && /Qt\.resolvedUrl\("\.\/settings\.json"\)/.test(defaultsDecl[1]),
            "defaultConfigPath must resolve the sibling settings.json, got: " + (defaultsDecl ? defaultsDecl[1] : "none"));

        // 2. The live file is the XDG user config, never the checkout.
        assert(/readonly property string userConfigPath\s*:/.test(cfg),
            "Config.qml must name the live file `userConfigPath`");
        const userDecl = cfg.match(/readonly property string userConfigPath\s*:\s*\{([\s\S]*?)\n    \}/);
        assert(userDecl !== null, "userConfigPath must be a computed path");
        assert(/XDG_CONFIG_HOME/.test(userDecl[1]),
            "userConfigPath must honour XDG_CONFIG_HOME, got: " + (userDecl ? userDecl[1].trim() : "none"));
        assert(/\/astral-plasma\/settings\.json/.test(userDecl[1]),
            "userConfigPath must end in /astral-plasma/settings.json, got: " + (userDecl ? userDecl[1].trim() : "none"));
        assert(!/config\/settings\.json|localConfigPath/.test(cfg),
            "the checkout's settings.json must no longer be used as the live path");

        // 3. Loading merges defaults with the user file, user winning.
        assert(/function\s+mergeSettings\s*\(/.test(cfg),
            "Config.qml must deep-merge the shipped defaults with the user file, so new default "
            + "keys keep working after a user file exists");
        assert(/mergeSettings\(/.test(cfg.slice(cfg.indexOf("applySettings"), cfg.indexOf("applySettings") + 1200)),
            "applySettings must apply the merge");

        // 4. Saving writes ONLY the user file.
        const save = cfg.match(/function\s+saveSettings\s*\([^)]*\)\s*\{([\s\S]*?)\n    \}/);
        assert(save !== null, "Config.qml must expose saveSettings()");
        assert(/config",\s*"write",\s*root\.userConfigPath/.test(save[1].replace(/\s+/g, " ")),
            "saveSettings must write to userConfigPath, got: " + save[1].trim().slice(0, 200));
        assert(!/defaultConfigPath/.test(save[1]),
            "saveSettings must never write the shipped defaults file");

        // 5. The first run seeds the user file (migration path), so a settings
        //    change never has to invent one.
        assert(/saveSettings\(\)/.test(cfg.slice(cfg.indexOf("function applySettings"), cfg.indexOf("function applySettings") + 1500)),
            "applySettings must seed the user file when it does not exist yet");

        console.log("PASS: Settings Location Contract (shipped defaults stay in the checkout; the live "
            + "file is $XDG_CONFIG_HOME/astral-plasma/settings.json and is the only one written)");
        Qt.exit(0);
    }
}
