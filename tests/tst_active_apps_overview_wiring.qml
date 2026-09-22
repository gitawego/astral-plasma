import QtQuick

// Meta-key active-apps overview: the cross-file wiring contract.
//
// The chain is: KWin registerShortcut("Meta") -> daemon ShellIpc whitelist ->
// quickshell IPC target "overview" -> Config.overviewVisible -> the
// ActiveAppsOverview surface -> WindowService thumbnail cycle ->
// WindowService.activateWindow on pick, with `focus restore` on dismiss.
// Every hop is a different file and a rename at ANY hop silently kills the
// feature while every other suite stays green, so each link is pinned here at
// the source level (cache-busted reads; see tst_blur_region_teardown.qml for
// why the bust matters).
Item {
    id: testRoot
    width: 400
    height: 300

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        // Cache-buster: Qt caches file:// reads, so a guard can silently test
        // STALE source and pass while the real file has changed. (CACHEBUST)
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
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
            // Halt: falling through to the final Qt.exit(0) would overwrite
            // the exit code and turn a failing suite green.
            throw new Error(msg);
        }
    }

    function runTests() {
        console.log("RUNNING: Active apps overview Meta wiring tests");

        // ---- 1. KWin shortcut script: bare Meta registers the action -------
        const kwinJs = readLocalFile("../kwin/astral-plasma-shortcuts/contents/code/main.js");
        assert(kwinJs.length > 200, "KWin shortcuts script must be readable");
        assert(/registerShortcut\(\s*"AstralOverview"/.test(kwinJs),
            "the KWin script must register the AstralOverview action");
        assert(/"AstralOverview"[\s\S]{0,600}"Meta"/.test(kwinJs),
            "AstralOverview must be bound to the bare Meta key");
        assert(/"overview\.toggle"/.test(kwinJs),
            "AstralOverview must forward to the overview.toggle whitelisted action");

        // ---- 2. Daemon whitelist: only overview.toggle may cross ------------
        const watch = readLocalFile("../daemon/src/application/watch_events.rs");
        assert(watch.length > 1000, "watch_events.rs must be readable");
        assert(/"overview\.toggle"\s*=>\s*Some\(vec!\["call",\s*"overview",\s*"toggle"\]\)/.test(watch),
            "shell_ipc_arguments must map overview.toggle to the overview toggle IPC");

        // ---- 3. Branding: the shortcut identity exists exactly once --------
        const branding = readLocalFile("../daemon/src/domain/branding.rs");
        assert(branding.length > 500, "branding.rs must be readable");
        assert(/SHORTCUT_OVERVIEW_KEY:\s*&str\s*=\s*"AstralOverview"/.test(branding),
            "branding must own the AstralOverview shortcut key");
        assert(/SHORTCUT_OVERVIEW_LABEL/.test(branding),
            "branding must own the overview shortcut label");

        // ---- 4. Shortcut lifecycle: monitored for backup + cleared in-memory -
        const shortcuts = readLocalFile("../daemon/src/infrastructure/kwin_shortcuts.rs");
        assert(shortcuts.length > 1000, "kwin_shortcuts.rs must be readable");
        assert(/SHORTCUT_OVERVIEW_KEY/.test(shortcuts),
            "the overview key must be part of the granular backup/restore set");
        assert(/setForeignShortcut\(\[\s*'kwin',\s*'\{overview\}'/.test(shortcuts),
            "restore must clear the in-memory AstralOverview registration");

        // ---- 5. The installer binds Meta and frees it from plasmashell ------
        const bind = readLocalFile("../scripts/bind_shortcuts.sh");
        assert(bind.length > 1000, "bind_shortcuts.sh must be readable");
        assert(/--key "AstralOverview"/.test(bind),
            "the bind script must write the AstralOverview kglobalaccel entry");
        assert(/"activate application launcher"/.test(bind),
            "the bind script must free the launcher's claim on the Meta key");
        assert(/'AstralOverview'/.test(bind),
            "the bind script must register AstralOverview over D-Bus");
        assert(/16777250/.test(bind),
            "bare Meta must use Qt::Key_Meta = 16777250 - the exact code KDE matches on Super presses (plasmashell's own former binding used it); any other code silently never fires");

        // ---- 6. Manual fallback script follows the toggle-script convention -
        const toggle = readLocalFile("../scripts/toggle_overview.sh");
        assert(/call overview toggle/.test(toggle),
            "scripts/toggle_overview.sh must call the overview toggle IPC");

        // ---- 7. Shell IPC surface ------------------------------------------------
        const shell = readLocalFile("../shell.qml");
        assert(shell.length > 1000, "shell.qml must be readable");
        assert(/IpcHandler\s*\{[\s\S]{0,200}target:\s*"overview"/.test(shell),
            "shell.qml must expose the overview IPC target");
        assert(/function toggle\(\)[\s\S]{0,120}Config\.toggleOverview\(\)/.test(shell),
            "overview IPC toggle must route to Config.toggleOverview()");
        assert(/ActiveAppsOverview\s*\{/.test(shell),
            "shell.qml must instantiate the ActiveAppsOverview surface");

        // ---- 8. Config state machine ------------------------------------------------
        const config = readLocalFile("../config/Config.qml");
        assert(config.length > 1000, "Config.qml must be readable");
        assert(/property bool overviewVisible/.test(config),
            "Config must expose the overviewVisible gate");
        assert(/function toggleOverview\(\)[\s\S]{0,200}function openOverview\(\)/.test(config),
            "Config must expose toggle/open overview functions");
        assert(/function closeOverview\(\)/.test(config),
            "Config must expose closeOverview()");
        assert(/openOverview\(\)[\s\S]{0,300}closeBottomPopout\(\)/.test(config),
            "opening the overview must close the bottom popout (single capture owner)");

        // ---- 9. The surface itself ---------------------------------------------------
        const surface = readLocalFile("../shell/ActiveAppsOverview.qml");
        assert(surface.length > 1000, "shell/ActiveAppsOverview.qml must exist and be readable");
        assert(/Config\.overviewVisible/.test(surface),
            "the surface must be gated by Config.overviewVisible");
        assert(/Keys\.onEscapePressed/.test(surface),
            "the surface must close on Escape");
        assert(/WindowService\.activateWindow\(/.test(surface),
            "picking a card must activate that window");
        assert(/"focus",\s*"restore"/.test(surface),
            "dismissing without a pick must hand compositor activation back (focus restore)");
        assert(/startOverviewThumbnails\(/.test(surface) && /stopOverviewThumbnails\(/.test(surface),
            "the surface must drive the thumbnail cycle from its visibility");

        // ---- 10. WindowService thumbnail cycle ---------------------------------------
        const ws = readLocalFile("../services/WindowService.qml");
        assert(ws.length > 1000, "WindowService.qml must be readable");
        assert(/function startOverviewThumbnails\(/.test(ws),
            "WindowService must expose startOverviewThumbnails()");
        assert(/function stopOverviewThumbnails\(/.test(ws),
            "WindowService must expose stopOverviewThumbnails()");
        assert(/overviewThumbnails/.test(ws),
            "WindowService must publish the per-window thumbnail map");

        console.log("PASS: Active apps overview Meta wiring tests passed");
        Qt.exit(0);
    }
}
