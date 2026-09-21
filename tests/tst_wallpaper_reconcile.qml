import QtQuick

// ============================================================================
// Wallpaper Reconcile Contract
// ============================================================================
// The picker focuses the wallpaper the daemon reports as current, so that value
// must not drift away from the user's choice. A plasmashell restart rewrites its
// containment config from its own saved state and silently reverts the
// wallpaper; the shell watches that config and reconciles, and the daemon owns
// the policy (state wins, desktop-only wallpapers are adopted).
//
// The policy itself is covered by daemon/tests/test_wallpaper_ground_truth.rs;
// this pins the wiring that makes it fire.
Item {
    id: testRoot

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
        console.log("RUNNING: Wallpaper Reconcile Contract");

        const engine = readLocalFile("../services/WallpaperEngine.qml");
        assert(engine.length > 1000, "WallpaperEngine.qml must be readable");

        // The containment config is watched (polling would be both slower and
        // heavier than the compositor's own change notification).
        assert(/plasma-org\.kde\.plasma\.desktop-appletsrc/.test(engine),
            "the engine must watch Plasma's containment config");
        assert(/watchChanges:\s*true/.test(engine),
            "the config must be watched, not polled");
        assert(/onFileChanged:[^\n]*reconcileActiveWallpaper/.test(engine),
            "a rewritten config must trigger reconciliation");

        // The policy lives in the daemon, and the engine re-reads the current
        // wallpaper afterwards instead of trusting the stale value.
        assert(/\[Config\.daemonBin,\s*"wallpaper",\s*"reconcile"\]/.test(engine),
            "reconciliation must go through the daemon's wallpaper reconcile");
        assert(/onStreamFinished:[\s\S]{0,200}getProc\.running\s*=\s*true/.test(engine),
            "the current wallpaper must be re-read after reconciling");

        // And it runs at start-up, not only when Plasma rewrites the file.
        assert(/Component\.onCompleted:[\s\S]{0,200}reconcileActiveWallpaper\(\)/.test(engine),
            "start-up must reconcile too");

        console.log("PASS: Wallpaper Reconcile Contract (watches Plasma's config, "
            + "reconciles through the daemon, re-reads the current wallpaper)");
        Qt.exit(0);
    }
}
