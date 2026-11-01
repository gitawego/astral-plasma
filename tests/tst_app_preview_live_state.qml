import QtQuick
import "../services/PreviewAppState.js" as Preview

// ============================================================================
// App Preview Drawer — Live Window State
// ============================================================================
// The drawer shows an application and the windows it currently has. Closing a
// window from the drawer's own × used to leave the row behind: the drawer held a
// snapshot of the window list taken when it opened, while the dock's icons (fed
// by the same push) updated. Reported with two Edge windows: one was closed, the
// drawer kept saying "2 Open Windows".
//
// The repair derives the drawer's subject from the live window model. This suite
// exercises that derivation directly - services/PreviewAppState.js is the same
// code the shell runs - and pins the two contracts that keep it wired.
Item {
    id: testRoot
    width: 600
    height: 400

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

    // A window as the daemon pushes it.
    function win(id, title, active) {
        return {
            id: id,
            title: title,
            isActive: Boolean(active),
            appId: "Alacritty",
            appName: "Alacritty",
            iconName: "Alacritty",
            materialIcon: "terminal",
            desktopFile: "Alacritty.desktop"
        };
    }

    // The dock's group for a running app (what appHover hands to the drawer).
    function appGroup(windows, activeId) {
        const active = windows.filter(w => w.id === activeId)[0] || windows[0] || null;
        return {
            id: active ? active.id : null,
            appId: "Alacritty",
            appName: "Alacritty",
            iconName: "Alacritty",
            materialIcon: "terminal",
            desktopFile: "Alacritty.desktop",
            title: active ? active.title : "",
            isRunning: true,
            isActive: Boolean(active),
            isPinned: true,
            windows: windows,
            windowCount: windows.length
        };
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: App Preview Drawer Live State Tests");

        // ---- 1. A group seed tracks exactly its own windows ------------------
        const w1 = win("f31d1cf6-4499-485d-a8f1-30bea778c06c", "hlu@cachyos: ~", true);
        const w2 = win("c3662a76-eb7a-454e-a470-70db3c45cf57", "hlu@cachyos: ~ 2", false);
        const seed = appGroup([w1, w2], w1.id);

        assert(Preview.isGroup(seed), "A dock app entry is a group");
        assert(!Preview.isGroup(w1), "A bare window is not a group");

        const ids = Preview.trackedIds(seed);
        assert(ids.length === 2, "The group tracks both windows");
        assert(ids[0] === "f31d1cf6-4499-485d-a8f1-30bea778c06c", "Tracked ids are the window ids");

        // ---- 2. Opening the drawer shows the live list -----------------------
        var app = Preview.derive(seed, ids, [w1, w2], w1.id);
        assert(app.windows.length === 2 && app.windowCount === 2, "Drawer starts with 2 windows");
        assert(app.isRunning === true, "App is running while a window exists");
        assert(app.id === w1.id, "Representative is the focused window");

        // ---- 3. THE REGRESSION: closing the focused window ------------------
        // The daemon pushes the remaining window; the row must leave immediately.
        app = Preview.derive(seed, ids, [w2], w1.id);
        assert(app.windows.length === 1, "Closing one window leaves exactly one row in the drawer");
        assert(app.windowCount === 1, "The drawer's header count drops to 1");
        assert(app.id === w2.id, "The representative moves to the surviving window");
        assert(app.title === w2.title, "The drawer shows the survivor's title");
        assert(app.isRunning === true, "The app is still running");

        // ---- 4. Closing the last window ends the app view -------------------
        app = Preview.derive(seed, ids, [], w1.id);
        assert(app.windows.length === 0, "No window may linger once every one is closed");
        assert(app.windowCount === 0, "Header count is 0");
        assert(app.id === "", "No representative window id survives");
        assert(app.isRunning === false, "The app is no longer running");
        assert(app.isActive === false, "A closed app cannot be active");
        assert(app.appName === "Alacritty", "The app's own labels survive so the drawer can offer a new window");
        assert(app.isPinned === true, "Pinned state is preserved");

        // ---- 5. Focus moves the representative without moving the set --------
        const w2Active = win(w2.id, w2.title, true);
        app = Preview.derive(seed, ids, [win(w1.id, w1.title, false), w2Active], w1.id);
        assert(app.windows.length === 2, "Both rows remain when focus moves");
        assert(app.id === w1.id, "The preview stays on the window the drawer opened on");
        assert(app.isActive === true, "ACTIVE is derived from the live windows, not the anchor");

        app = Preview.derive(seed, ids, [w2Active], w1.id);
        assert(app.id === w2.id, "When the anchor closes, the focused window becomes the subject");

        const noneActive = Preview.derive(seed, ids, [win(w1.id, w1.title, false), win(w2.id, w2.title, false)], "");
        assert(noneActive.id === w1.id, "With nothing focused and no anchor, the first surviving window leads");
        assert(noneActive.isActive === false, "Nothing focused means no ACTIVE badge");

        // ---- 6. Foreign windows are never absorbed ---------------------------
        const foreign = win("11111111-2222-3333-4444-555555555555", "another app", true);
        foreign.appId = "Ghostty";
        foreign.appName = "Ghostty";
        app = Preview.derive(seed, ids, [foreign], w1.id);
        assert(app.windows.length === 0, "A window outside the tracked set cannot enter the drawer");
        assert(app.isRunning === false, "A same-named foreign window does not keep the app running");

        // ---- 7. Brace-wrapped ids are the same window ------------------------
        const braced = win("{" + w1.id + "}", w1.title, true);
        app = Preview.derive(seed, Preview.trackedIds(seed), [braced, w2], w1.id);
        assert(app.windows.length === 2, "A braced uuid still matches its window");
        assert(Preview.windowKey("{" + w1.id + "}") === w1.id, "windowKey normalises braces");

        // ---- 8. Pinned but not running: nothing to derive from --------------
        const notRunning = {
            id: null,
            appId: "org.alacritty",
            appName: "Alacritty",
            isRunning: false,
            isPinned: true,
            windows: []
        };
        assert(Preview.trackedIds(notRunning).length === 0, "An unlaunched app tracks no windows");
        app = Preview.derive(notRunning, [], [], null);
        assert(app.isRunning === false && app.windows.length === 0, "Unlaunched app keeps its not-running view");
        assert(app.appName === "Alacritty", "Unlaunched app keeps its name");

        // ---- 9. Signature stability: no needless re-renders ------------------
        const sigA = Preview.signature(Preview.derive(seed, ids, [w1, w2], w1.id));
        const sigB = Preview.signature(Preview.derive(seed, ids, [win(w1.id, w1.title, true), win(w2.id, w2.title, false)], w1.id));
        assert(sigA === sigB, "Identical window data yields an identical signature (no preview churn)");
        const sigClosed = Preview.signature(Preview.derive(seed, ids, [w2], w1.id));
        assert(sigClosed !== sigA, "A closed window changes the signature");
        const sigTitle = Preview.signature(Preview.derive(seed, ids, [win(w1.id, "a new tab", true), w2], w1.id));
        assert(sigTitle !== sigA, "A title change changes the signature");

        // ---- 10. Wiring contracts -------------------------------------------
        const wsCode = readLocalFile("../services/WindowService.qml");
        assert(wsCode.length > 1000, "WindowService.qml must be readable");
        assert(/import "PreviewAppState\.js" as PreviewAppState/.test(wsCode),
            "WindowService must import the preview state module");
        assert(/function syncPreviewApp\s*\(/.test(wsCode),
            "WindowService must expose syncPreviewApp()");
        assert(/PreviewAppState\.derive\(/.test(wsCode),
            "WindowService must derive the drawer's app from the live window model");
        // Exactly one handler per signal: a duplicate does not override, it fails
        // the whole configuration with "Property value set multiple times" - and a
        // running shell then keeps the old code while looking alive.
        const winHandlers = (wsCode.match(/^\s*onWindowsChanged\s*:/gm) || []).length;
        assert(winHandlers === 1, "WindowService must declare exactly one onWindowsChanged handler");
        const wsHook = wsCode.search(/^\s*onWindowsChanged\s*:/m);
        assert(wsHook !== -1 && /root\.syncPreviewApp\(\)/.test(wsCode.slice(wsHook, wsHook + 260)),
            "Every window push must re-derive the drawer's app");
        assert(!/root\.activePreviewApp\s*=\s*app\b/.test(wsCode),
            "loadAppPreview must not store the app object as the drawer's state");

        const popoutCode = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        assert(popoutCode.length > 1000, "FusedBottomPopout.qml must be readable");
        assert(/appSection\.winList\.slice\(\)/.test(popoutCode),
            "Close All Windows must iterate a snapshot: the row list is live now");

        // ---- 11. The multi-window drawer shows a preview without hovering ---
        // A drawer with 2+ windows used to render nothing but title bars until the
        // pointer happened to rest on a row: the row only expanded for the hovered
        // window id, so "some apps have no preview".
        const rows = [win(w1.id, w1.title, true), win(w2.id, w2.title, false)];

        assert(Preview.expandedWindowId("", rows, w1.id) === w1.id,
            "With no row hovered the drawer expands its subject, so a preview is always visible");
        assert(Preview.expandedWindowId(w2.id, rows, w1.id) === w2.id,
            "A hovered row takes the preview");
        assert(Preview.expandedWindowId("stale-id", rows, w1.id) === w1.id,
            "A hover pointing at a window that left the list falls back to the subject");
        assert(Preview.expandedWindowId("", rows, "gone-id") === "",
            "A subject that is not in the list expands nothing");
        assert(Preview.expandedWindowId("", [], w1.id) === "", "No rows, nothing to expand");

        // ---- 12. A hover survives a window push -----------------------------
        // Rows are re-derived on every push, so identity changes constantly; only
        // a change in *which* windows are listed may end a hover.
        assert(Preview.rowsSignature(rows) === Preview.rowsSignature([win(w1.id, "a new tab", false), win(w2.id, w2.title, true)]),
            "Rows signature ignores titles and focus - a tab change is not a membership change");
        assert(Preview.rowsSignature(rows) !== Preview.rowsSignature([rows[0]]),
            "Rows signature changes when a window leaves");

        assert(Preview.hoverAfterRowsChange(w2.id, rows) === w2.id,
            "Hovering a row must survive an unrelated window push");
        assert(Preview.hoverAfterRowsChange(w2.id, [rows[0]]) === "",
            "The hover ends with the window it points at");
        assert(Preview.hoverAfterRowsChange("", rows) === "",
            "No hover stays no hover");

        // ---- 13. The popout must use that policy ----------------------------
        assert(/import "\.\.\/\.\.\/services\/PreviewAppState\.js" as PreviewAppState/.test(popoutCode),
            "FusedBottomPopout must import the preview state module");
        assert(/PreviewAppState\.expandedWindowId\(/.test(popoutCode),
            "Row expansion must go through the tested policy");
        assert(/appSection\.expandedId/.test(popoutCode),
            "The expanded row must be the policy's answer, not raw hover state");
        assert(/PreviewAppState\.rowsSignature\(/.test(popoutCode) && /PreviewAppState\.hoverAfterRowsChange\(/.test(popoutCode),
            "The row-list handler must distinguish membership changes from content changes");

        // ---- 14. Fast hovering between rows must not kill the capture --------
        // Hovering two rows quickly used to kill the capture process outright
        // (running = false; command = ...; running = true in one tick), and the
        // preview stopped appearing until something else started a capture.
        const q = Preview.captureQueue();
        assert(Preview.captureRequest(q, false, "w1") === "w1",
            "An idle queue dispatches a capture at once");
        assert(Preview.captureRequest(q, true, "w2") === "",
            "A capture already in flight is never restarted");
        assert(q.pending === "w2", "The request that arrived mid-capture is remembered");
        assert(Preview.captureRequest(q, true, "w3") === "" && q.pending === "w3",
            "The latest hover wins over an older queued one");
        assert(Preview.captureFinished(q) === "w3" && q.pending === "",
            "Finishing hands over exactly one queued request");
        assert(Preview.captureFinished(q) === "", "Nothing queued, nothing dispatched");
        assert(Preview.captureRequest(q, false, "") === "", "An empty key never dispatches a capture");
        assert(Preview.captureRequest(q, false, "{w9}") === "w9", "Keys are normalised to a bare uuid");

        // ---- 15. WindowService must capture through that queue --------------
        assert(/PreviewAppState\.captureRequest\(/.test(wsCode) && /PreviewAppState\.captureFinished\(/.test(wsCode),
            "WindowService must capture previews through the single-slot queue");
        const loadStart = wsCode.indexOf("function loadAppPreview(");
        const loadBody = wsCode.slice(loadStart, wsCode.indexOf("function ", loadStart + 10));
        assert(/root\._dispatchPreview\(/.test(loadBody),
            "loadAppPreview must dispatch previews through the queue");
        assert(!/previewCaptureProc\.running = true/.test(loadBody),
            "loadAppPreview must never start the capture process directly");

        console.log("PASS: App Preview Drawer Live State Tests");
        Qt.exit(0);
    }
}
