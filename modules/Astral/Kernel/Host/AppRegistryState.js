.pragma library

// The registry document, parsed once, with the one question shell surfaces ask of it.
//
// Three consumers need this answer (`AppRegistry` for the plan, `AppsService` for the
// page, `AppStates` for shell surfaces that represent an app), so the parsing lives here
// rather than being written three times and drifting.

/// `text` -> `{ ok, apps: [], byId: {} }`. An unreadable document is `ok: false`, not a
/// throw: a shell must survive a corrupt registry and say so.
function parse(text) {
    const empty = { ok: false, apps: [], byId: {} };
    if (typeof text !== "string" || text.length === 0) return empty;
    let parsed = null;
    try {
        parsed = JSON.parse(text);
    } catch (error) {
        return empty;
    }
    // A registry document is an object with an `apps` list; an array is somebody else's
    // JSON and must not be mistaken for an empty registry.
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return empty;
    // `apps` must be a list when it is present: a string here is a corrupt document, not an
    // empty registry (silently treating it as empty would disable every bundled app).
    if (parsed.apps !== undefined && !Array.isArray(parsed.apps)) return empty;
    const apps = Array.isArray(parsed.apps) ? parsed.apps : [];
    const byId = ({});
    for (let index = 0; index < apps.length; index++) {
        const entry = apps[index];
        if (entry && typeof entry.id === "string" && entry.id.length > 0) {
            byId[entry.id] = entry;
        }
    }
    return { ok: true, apps: apps, byId: byId };
}

/// Is `id` on? A bundled app with no record is enabled (that is how a fresh install has
/// apps at all); a record with `enabled: false` is the user's decision and wins.
function isEnabled(state, id) {
    if (!state || !state.byId) return true;
    const record = state.byId[id];
    if (!record) return true;
    return record.enabled !== false;
}

/// Ids the user disabled, in registry order (the Apps page and the shell both use this).
function disabledIds(state) {
    if (!state || !state.apps) return [];
    const ids = [];
    for (let index = 0; index < state.apps.length; index++) {
        const entry = state.apps[index];
        if (entry && typeof entry.id === "string" && entry.enabled === false) ids.push(entry.id);
    }
    return ids;
}
