import QtQuick

// ============================================================================
// Display refresh preference — setting, service and lifecycle contracts
// ============================================================================
// The panel here runs at 240 Hz, which multiplies the per-frame work of every
// client (docs/LESSONS.md 33). The shell's motion budget is 30 fps, so the refresh
// rate is a power/heat preference: shipped default 60 Hz, `max` leaves the session
// alone, and the mode the session was running is restored when the shell exits.
//
// The switch itself lives in the daemon (`astral-plasma display apply|restore`,
// pure logic in `domain/display_modes.rs`); this suite pins the wiring: the
// setting, the service that reacts to it, the settings UI, and run.sh's
// apply-on-start / restore-on-exit symmetry.
Item {
    id: testRoot
    width: 640
    height: 480

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

    function between(text, from, to) {
        const start = text.indexOf(from);
        if (start < 0) return "";
        const end = to ? text.indexOf(to, start) : -1;
        return end < 0 ? text.substring(start) : text.substring(start, end);
    }

    Component.onCompleted: {
        // ------------------------------------------------------------------ 1 --
        // The shipped default is 60 Hz, in the file users actually read.
        const settings = JSON.parse(readLocalFile("../config/settings.json"));
        testRoot.assert(settings.display !== undefined, "settings.json must carry a display block");
        testRoot.assert(
            ("" + settings.display.refreshRate) === "60",
            "the shipped display refresh default must be 60 Hz, got " + settings.display.refreshRate
        );

        // ------------------------------------------------------------------ 2 --
        const config = readLocalFile("../config/Config.qml");
        const block = between(config, "Display refresh rate", "function setMediaVisualizerStyle");
        testRoot.assert(block.length > 0, "Config.qml must own the display refresh block");
        testRoot.assert(
            block.indexOf('defaultDisplayRefreshRate: "60"') !== -1,
            "the default must be 60 Hz in Config.qml too"
        );
        testRoot.assert(
            /displayRefreshOptions:\s*\["60",\s*"120",\s*"144",\s*"165",\s*"max"\]/.test(block),
            "the picker must offer the common rates plus max"
        );
        testRoot.assert(
            block.indexOf("root.settings.display.refreshRate !== undefined") !== -1,
            "the getter must tolerate an absent display block (an older settings.json)"
        );
        const setter = between(config, "function setDisplayRefreshRate", "\n    //");
        testRoot.assert(
            setter.indexOf("root.settings.display.refreshRate = value") !== -1 &&
                setter.indexOf("root.saveSettings()") !== -1,
            "the setter must persist the choice"
        );

        // ------------------------------------------------------------------ 3 --
        const service = readLocalFile("../services/DisplayService.qml");
        testRoot.assert(service.length > 0, "services/DisplayService.qml must exist");
        testRoot.assert(
            service.indexOf("Component.onCompleted: root.apply()") !== -1 &&
                service.indexOf("onPreferenceChanged: root.apply()") !== -1,
            "the service must apply the preference at startup and on every change"
        );
        testRoot.assert(
            service.indexOf('"display", "apply"') !== -1 && service.indexOf("daemonBin") !== -1,
            "the service must ask the daemon to do the switch"
        );
        testRoot.assert(
            service.indexOf("lastApplySucceeded") !== -1,
            "the service must report whether the apply actually succeeded"
        );

        // ------------------------------------------------------------------ 4 --
        // The settings page is where a user meets the option, and it references the
        // service (QML singletons are instantiated on first reference, so this is
        // what keeps it alive).
        const page = readLocalFile("../settings_gui/pages/SystemPage.qml");
        testRoot.assert(page.length > 0, "SystemPage.qml must be readable");
        testRoot.assert(
            page.indexOf('import "../../services"') !== -1 && page.indexOf("DisplayService") !== -1,
            "the settings page must reference DisplayService"
        );
        testRoot.assert(
            page.indexOf("Config.displayRefreshOptions") !== -1 &&
                page.indexOf("Config.setDisplayRefreshRate") !== -1,
            "the settings page must offer the options and set them"
        );

        // ------------------------------------------------------------------ 5 --
        // run.sh symmetry: apply before the shell exists, restore on the way out.
        const run = readLocalFile("../run.sh");
        testRoot.assert(run.length > 0, "run.sh must be readable");
        const applyAt = run.indexOf('"$DIR/bin/astral-plasma" display apply auto');
        const shellAt = run.indexOf('quickshell -n -p "$DIR" &');
        testRoot.assert(
            applyAt > 0 && shellAt > applyAt,
            "run.sh must apply the preference before starting the shell"
        );
        const restoreAt = run.indexOf('"$DIR/bin/astral-plasma" display restore');
        testRoot.assert(
            restoreAt > 0 && run.indexOf("plasma restore") < restoreAt,
            "run.sh must restore the session's own mode on exit"
        );

        // ------------------------------------------------------------------ 6 --
        // The daemon owns the decision and its journal.
        const cli = readLocalFile("../daemon/src/interfaces/cli.rs");
        testRoot.assert(
            cli.indexOf('"display" =>') !== -1 &&
                cli.indexOf('"apply" | "refresh" | "set"') !== -1 &&
                cli.indexOf('"restore" =>') !== -1,
            "the daemon CLI must expose display apply/restore"
        );
        testRoot.assert(
            cli.indexOf("fn read_display_preference") !== -1,
            "`display apply auto` must read the preference from settings"
        );
        const adapter = readLocalFile("../daemon/src/infrastructure/kscreen_adapter.rs");
        testRoot.assert(
            adapter.indexOf("display_backup.json") !== -1 &&
                adapter.indexOf("pub fn restore") !== -1 &&
                adapter.indexOf("pub fn apply") !== -1,
            "the adapter must journal the previous modes and restore them"
        );
        const domain = readLocalFile("../daemon/src/domain/display_modes.rs");
        testRoot.assert(
            domain.indexOf("RefreshPreference::Target(60.0)") !== -1,
            "the daemon's default preference must be 60 Hz"
        );
        testRoot.assert(
            domain.indexOf("mode.size.width == width && mode.size.height == height") !== -1,
            "the mode choice must never change the resolution"
        );

        console.log("PASS: display refresh preference wiring (default 60 Hz, max, restore on exit)");
        Qt.exit(0);
    }
}
