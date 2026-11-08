import QtQuick

// ============================================================================
// The shell must NEVER modify the display refresh rate
// ============================================================================
// Regression: Astral shipped a `display.refreshRate` default of "60", had
// `run.sh` call `astral-plasma display apply auto` before the shell started,
// and a DisplayService that re-applied the preference on startup and on every
// settings change. A user running 240 Hz therefore had the session silently
// knocked down to 60 Hz - the shell changed a session-wide setting the user
// never asked it to manage.
//
// The policy is absolute: the compositor/session owns the refresh rate. This
// suite is the gate that keeps the write path from coming back.
Item {
    id: testRoot
    width: 640
    height: 480

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        try {
            xhr.send();
        } catch (e) {
            return "";
        }
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

    function between(text, from, to) {
        const start = text.indexOf(from);
        if (start < 0) return "";
        const end = to ? text.indexOf(to, start) : -1;
        return end < 0 ? text.substring(start) : text.substring(start, end);
    }

    Component.onCompleted: {
        // ------------------------------------------------------------------ 1 --
        // No shipped preference: the session's current mode is the only truth.
        const settings = JSON.parse(readLocalFile("../modules/Astral/Kernel/config/settings.json"));
        testRoot.assert(settings.display === undefined,
            "settings.json must not ship a display block: the user's rate is not the shell's to set");

        // ------------------------------------------------------------------ 2 --
        // No setting, setter or picker.
        const config = readLocalFile("../modules/Astral/Kernel/config/Config.qml");
        testRoot.assert(config.indexOf("displayRefreshRate") === -1,
            "Config.qml must not expose a refresh-rate setting");
        testRoot.assert(config.indexOf("setDisplayRefreshRate") === -1,
            "Config.qml must not expose a refresh-rate setter");
        testRoot.assert(config.indexOf("displayRefreshOptions") === -1,
            "Config.qml must not offer refresh-rate choices");

        // ------------------------------------------------------------------ 3 --
        // No service applies it, at startup or on change.
        const service = readLocalFile("../modules/Astral/Kernel/services/DisplayService.qml");
        testRoot.assert(service.length === 0,
            "services/DisplayService.qml must not exist: nothing may apply a refresh preference");

        // ------------------------------------------------------------------ 4 --
        // The settings page must not offer the choice.
        const page = readLocalFile("../settings_gui/pages/SystemPage.qml");
        testRoot.assert(page.indexOf("Display Refresh") === -1,
            "SystemPage must not render a Display Refresh control");
        testRoot.assert(page.indexOf("displayRefreshOptions") === -1 &&
            page.indexOf("setDisplayRefreshRate") === -1 &&
            page.indexOf("DisplayService") === -1,
            "SystemPage must not reference the removed refresh-rate machinery");

        // ------------------------------------------------------------------ 5 --
        // run.sh must not touch the display at startup or on exit.
        const run = readLocalFile("../run.sh");
        testRoot.assert(run.indexOf("display apply") === -1,
            "run.sh must never apply a display mode at startup");
        testRoot.assert(run.indexOf("display restore") === -1,
            "run.sh must never restore a display mode on exit");
        testRoot.assert(run.indexOf("astral-plasma\" display") === -1,
            "run.sh must not invoke the display command at all");

        // ------------------------------------------------------------------ 6 --
        // The daemon must not expose a write path either.
        const cli = readLocalFile("../daemon/src/interfaces/cli.rs");
        testRoot.assert(cli.indexOf('"display" =>') === -1,
            "the daemon CLI must not expose a display mutation command");
        testRoot.assert(cli.indexOf("read_display_preference") === -1,
            "the daemon must not read a refresh preference");
        testRoot.assert(cli.indexOf("kscreen-doctor") === -1 &&
            cli.indexOf("KscreenAdapter") === -1,
            "the daemon CLI must never drive kscreen-doctor");

        testRoot.assert(readLocalFile("../daemon/src/domain/display_modes.rs").length === 0,
            "the mode-selection domain module must be gone");
        testRoot.assert(readLocalFile("../daemon/src/infrastructure/kscreen_adapter.rs").length === 0,
            "the kscreen-doctor adapter must be gone");
        testRoot.assert(readLocalFile("../daemon/src/domain/mod.rs").indexOf("display_modes") === -1,
            "domain/mod.rs must not declare a display_modes module");
        testRoot.assert(readLocalFile("../daemon/src/infrastructure/mod.rs").indexOf("kscreen_adapter") === -1,
            "infrastructure/mod.rs must not declare a kscreen_adapter module");

        // ------------------------------------------------------------------ 7 --
        // The session launcher and helper scripts leave the mode alone.
        const session = readLocalFile("../sessions/astral-plasma-session");
        testRoot.assert(session.indexOf("kscreen-doctor") === -1,
            "the session launcher must not change the display mode");

        console.log("PASS: the shell never modifies the display refresh rate");
        Qt.exit(0);
    }
}
