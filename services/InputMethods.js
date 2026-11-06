.pragma library

// Parsing and labelling for the dock's input-method drawer.
//
// The list must come from whichever IME framework actually owns the session:
// fcitx5 (the documented switcher) or KDE's keyboard-layout service. Both are
// read as `busctl --json=short` payloads, so this module is pure and testable
// without a live session - and malformed output degrades to "no items" rather
// than to a fabricated layout.

function parseJson(text) {
    if (text === undefined || text === null) return null;
    const raw = String(text).trim();
    if (raw === "") return null;
    try {
        const value = JSON.parse(raw);
        return (value && value.data !== undefined) ? value : null;
    } catch (e) {
        return null;
    }
}

/// The compact glyph the dock shows for one method.
///
/// fcitx5 supplies a label that is already intended for a compact space
/// (`en`, `ㄓ`, ...). Use it as-is when it is a language code, keep a single
/// native glyph, and only when it is missing fall back to the id - never invent
/// a language the payload did not name.
function badgeFor(label, id) {
    const text = (label === undefined || label === null) ? "" : String(label).trim();
    if (text !== "") {
        if (/^[A-Za-z0-9]+$/.test(text)) return text.toUpperCase();
        return text.substring(0, 2);
    }
    const ident = (id === undefined || id === null) ? "" : String(id).trim();
    if (ident === "") return "";
    const keyboard = ident.match(/^keyboard-([A-Za-z0-9]{2})(?:-|$)/);
    if (keyboard) return keyboard[1].toUpperCase();
    return ident.substring(0, 2).toUpperCase();
}

/// `CurrentInputMethod` / `CurrentInputMethodGroup` payload (`s`).
function parseFcitx5Current(text) {
    const value = parseJson(text);
    if (!value || !Array.isArray(value.data) || typeof value.data[0] !== "string") return "";
    return value.data[0].trim();
}

/// `FullInputMethodGroupInfo` payload.
///
/// data = [group, defaultIM, defaultLayout, properties, items]
/// item = [uniqueName, name, nativeName, icon, label, language, addon,
///         configurable, config, properties]
function parseFcitx5GroupInfo(text) {
    const result = { group: "", defaultIM: "", layout: "", items: [] };
    const value = parseJson(text);
    if (!value || !Array.isArray(value.data)) return result;
    const data = value.data;
    if (typeof data[0] === "string") result.group = data[0];
    if (typeof data[1] === "string") result.defaultIM = data[1];
    if (typeof data[2] === "string") result.layout = data[2];
    const rows = data[4];
    if (!Array.isArray(rows)) return result;
    for (let i = 0; i < rows.length; ++i) {
        const row = rows[i];
        if (!Array.isArray(row) || typeof row[0] !== "string" || row[0] === "") continue;
        const id = row[0];
        result.items.push({
            id: id,
            name: (typeof row[1] === "string" && row[1] !== "") ? row[1] : id,
            nativeName: (typeof row[2] === "string") ? row[2] : "",
            icon: (typeof row[3] === "string") ? row[3] : "",
            badge: badgeFor((typeof row[4] === "string") ? row[4] : "", id),
            language: (typeof row[5] === "string") ? row[5] : "",
            addon: (typeof row[6] === "string") ? row[6] : "",
            keyboard: row[6] === "keyboard",
            enabled: row[7] !== false
        });
    }
    return result;
}

/// `getLayoutsList` payload: data[0] = [[layout, variant, displayName], ...].
function parseKdeLayouts(text) {
    const value = parseJson(text);
    if (!value || !Array.isArray(value.data) || !Array.isArray(value.data[0])) return [];
    const rows = value.data[0];
    const items = [];
    for (let i = 0; i < rows.length; ++i) {
        const row = rows[i];
        if (!Array.isArray(row) || typeof row[0] !== "string" || row[0] === "") continue;
        const id = row[0];
        items.push({
            id: id,
            name: (typeof row[2] === "string" && row[2] !== "") ? row[2] : id,
            variant: (typeof row[1] === "string") ? row[1] : "",
            badge: badgeFor("", id),
            icon: "",
            language: "",
            addon: "keyboard",
            keyboard: true,
            enabled: true
        });
    }
    return items;
}

/// `getLayout` payload (`u`): the active KDE layout index, or -1.
function parseKdeCurrent(text) {
    const value = parseJson(text);
    if (!value || !Array.isArray(value.data)) return -1;
    const index = Number(value.data[0]);
    return (isFinite(index) && index >= 0) ? Math.floor(index) : -1;
}

function activeIndex(items, id) {
    if (!Array.isArray(items) || !id) return -1;
    for (let i = 0; i < items.length; ++i) {
        if (items[i] && items[i].id === id) return i;
    }
    return -1;
}
