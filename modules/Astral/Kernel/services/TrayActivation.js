.pragma library

// Tray menu items are owned by the application (dbusmenu). Clicking "Open
// Telegram" sends the app's own event, but a window that is merely behind
// another one is not raised by every toolkit. The shell can honour an
// open-like action generically: find the window that belongs to the tray item
// and activate it after the app's click succeeds. No app identity is hard-coded.

function normalize(value) {
    return String(value === undefined || value === null ? "" : value)
        .toLowerCase()
        .replace(/[^a-z0-9]/g, "");
}

function opensWindow(label) {
    return /^(open|show|activate|bring|raise|restore|unhide)\b/i.test(String(label || "").trim());
}

function windowForTray(tray, windows) {
    if (!tray || !windows || !windows.length) return null;

    const keys = [tray.id, tray.title, tray.desktopFile, tray.service]
        .map(normalize)
        .filter(k => k.length >= 3);
    if (!keys.length) return null;

    for (let i = 0; i < windows.length; ++i) {
        const w = windows[i];
        if (!w) continue;
        const fields = [w.appId, w.appName, w.desktopFile, w.cls, w.title]
            .map(normalize)
            .filter(f => f.length >= 3);
        for (let k = 0; k < keys.length; ++k) {
            for (let f = 0; f < fields.length; ++f) {
                if (fields[f] === keys[k]
                        || fields[f].indexOf(keys[k]) !== -1
                        || keys[k].indexOf(fields[f]) !== -1) {
                    return w;
                }
            }
        }
    }
    return null;
}
