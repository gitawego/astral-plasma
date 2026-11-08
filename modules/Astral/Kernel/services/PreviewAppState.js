.pragma library

// Pure state helpers for the app preview drawer (used by services/WindowService.qml
// and exercised directly by tests/tst_app_preview_live_state.qml).
//
// The drawer shows "this application and its windows". The windows are a LIVE
// list - a window closed from the drawer must leave it immediately - while the
// labels come from the dock's app entry at the moment the drawer opened. Storing
// both in one object is what made a closed window linger: a snapshot of a live
// list is a stale list (docs/LESSONS.md §29).

/** KWin uuids arrive with braces; a bare id and a braced id are one window. */
function windowKey(id) {
    if (id === undefined || id === null) return "";
    return String(id).replace(/[{}]/g, "");
}

/** A group (dock icon hover) carries its own window list; a bare window is a row. */
function isGroup(app) {
    return Boolean(app && app.windows && app.windows.length > 0);
}

/**
 * The windows an app object stands for when it seeds the drawer.
 *
 * Membership is by window id, never by application name: two applications can
 * share a display name and Wine/XWayland clients can publish none at all, so a
 * name match would let a foreign window into the drawer. A window that opens
 * while the drawer is already open is picked up the next time the drawer opens
 * (hovering the dock icon re-seeds the group).
 */
function trackedIds(app) {
    if (!app) return [];
    const list = isGroup(app) ? app.windows : ((app.id !== undefined && app.id !== null) ? [app] : []);
    const ids = [];
    for (let i = 0; i < list.length; i++) {
        const key = windowKey(list[i] ? list[i].id : null);
        if (key !== "" && ids.indexOf(key) === -1) ids.push(key);
    }
    return ids;
}

/**
 * The drawer's subject, re-derived from the live window list.
 *
 * Labels: the seed wins (the dock knows the pinned entry's name and icon); a
 * window only fills a label the seed does not carry.
 *
 * Representative (`anchorId`): the window the drawer was opened on, or the row
 * being hovered - so the preview never jumps while the user is looking at it.
 * Only when that window is gone does the focused window take over, and failing
 * both, the first survivor.
 */
function derive(seed, ids, windows, anchorId) {
    if (!seed) return null;
    const tracked = ids || [];
    const live = windows || [];
    const matches = [];
    for (let i = 0; i < live.length; i++) {
        const w = live[i];
        if (!w) continue;
        if (tracked.indexOf(windowKey(w.id)) !== -1) matches.push(w);
    }

    if (matches.length === 0) {
        // Every window this drawer stood for is gone: the app is not running.
        return Object.assign({}, seed, {
            id: "",
            title: "",
            windows: [],
            windowCount: 0,
            isRunning: false,
            isActive: false
        });
    }

    let representative = null;
    const anchorKey = windowKey(anchorId);
    if (anchorKey !== "") {
        for (let a = 0; a < matches.length; a++) {
            if (windowKey(matches[a].id) === anchorKey) {
                representative = matches[a];
                break;
            }
        }
    }
    if (!representative) {
        for (let b = 0; b < matches.length; b++) {
            if (matches[b].isActive) {
                representative = matches[b];
                break;
            }
        }
    }
    if (!representative) representative = matches[0];

    let anyActive = false;
    for (let c = 0; c < matches.length; c++) {
        if (matches[c].isActive) anyActive = true;
    }

    const derived = Object.assign({}, seed);
    derived.id = representative.id;
    derived.title = representative.title || "";
    derived.windows = matches;
    derived.windowCount = matches.length;
    derived.isRunning = true;
    derived.isActive = anyActive;
    if (!derived.appName && representative.appName) derived.appName = representative.appName;
    if (!derived.iconName) derived.iconName = representative.iconName;
    if (!derived.materialIcon) derived.materialIcon = representative.materialIcon;
    if (!derived.desktopFile) derived.desktopFile = representative.desktopFile;
    return derived;
}

/**
 * Single-slot queue for the drawer's preview capture.
 *
 * Only one `astral-plasma preview` runs at a time. Moving quickly between the
 * rows of a multi-window drawer requests a capture per row; force-restarting the
 * process for each request left it dead (the second `running = true` lands while
 * the first instance is still stopping), so the preview stopped appearing until
 * something else triggered a capture. A request that arrives during a capture is
 * therefore remembered, and the latest one is dispatched when the current one
 * finishes - the in-flight key is never overwritten.
 */
function captureQueue() {
    return { pending: "" };
}

/** The key to dispatch now, or "" when a capture is already in flight. */
function captureRequest(queue, running, key) {
    const wanted = windowKey(key);
    if (wanted === "") return "";
    if (running) {
        queue.pending = wanted;
        return "";
    }
    queue.pending = "";
    return wanted;
}

/** The key to dispatch because a capture just finished, or "". */
function captureFinished(queue) {
    const next = queue.pending || "";
    queue.pending = "";
    return next;
}

/** Id signature of the rows a drawer lists: membership only, never titles. */
function rowsSignature(windows) {
    const list = windows || [];
    const parts = [];
    for (let i = 0; i < list.length; i++) {
        const key = windowKey(list[i] ? list[i].id : null);
        if (key !== "") parts.push(key);
    }
    return parts.join(",");
}

/**
 * A hover outlives a list update; it only ends with the window it points at.
 *
 * The rows are re-derived on every window push, so the list is a new array even
 * when nothing the user can see moved. Resetting the hover on arrival made the
 * expanded row collapse under the pointer whenever a browser tab retitled itself.
 */
function hoverAfterRowsChange(hoveredId, windows) {
    const hovered = windowKey(hoveredId);
    if (hovered === "") return "";
    const list = windows || [];
    for (let i = 0; i < list.length; i++) {
        if (windowKey(list[i] ? list[i].id : null) === hovered) return hoveredId;
    }
    return "";
}

/**
 * Which row shows the live preview: the hovered one, else the drawer's subject.
 *
 * Falls back to the subject when the hover points at a window that has left the
 * list, so a drawer can never end up with no expanded row - a multi-window drawer
 * with every row collapsed is exactly "the preview is not showing".
 */
function expandedWindowId(hoveredId, windows, representativeId) {
    const list = windows || [];
    const hovered = windowKey(hoveredId);
    if (hovered !== "") {
        for (let i = 0; i < list.length; i++) {
            if (windowKey(list[i] ? list[i].id : null) === hovered) return hoveredId;
        }
    }
    const subject = windowKey(representativeId);
    if (subject === "") return "";
    for (let i = 0; i < list.length; i++) {
        if (windowKey(list[i] ? list[i].id : null) === subject) return representativeId;
    }
    return "";
}

/**
 * Change token for a derived app: what the drawer displays. Re-deriving on every
 * window poll is cheap, but handing consumers a new object when nothing visible
 * moved would re-run their preview capture for no reason.
 */
function signature(app) {
    if (!app) return "";
    const parts = [
        windowKey(app.id),
        app.isRunning ? "1" : "0",
        app.isActive ? "1" : "0",
        app.title || ""
    ];
    const wins = app.windows || [];
    for (let i = 0; i < wins.length; i++) {
        const w = wins[i] || {};
        parts.push(windowKey(w.id) + ":" + (w.title || "") + ":" + (w.isActive ? "1" : "0"));
    }
    return parts.join("\u0001");
}
