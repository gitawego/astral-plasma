.pragma library

// Where each app plugs into the shell, resolved to its owning app.
//
// An app declares its locations in its manifest (`integrations: [{kind, id}]`). The shell
// builds this map once and every surface asks it, so disabling an app removes *all* of its
// locations — tab, dock item, drawer, settings page, window — without a single
// `if (id === "ai")` in the shell. Before this, each surface knew its own app by name and
// unaware surfaces kept advertising a disabled app (spec C.35).

/// `entries` (the registry's merged manifests) -> `{ "kind:id": appId }`, enabled apps only.
function build(entries) {
    const map = ({});
    const list = Array.isArray(entries) ? entries : [];
    for (let index = 0; index < list.length; index++) {
        const entry = list[index];
        if (!entry || typeof entry.id !== "string") continue;
        if (entry.enabled === false) continue;
        const declared = Array.isArray(entry.integrations) ? entry.integrations : [];
        for (let slot = 0; slot < declared.length; slot++) {
            const item = declared[slot];
            if (!item || typeof item.kind !== "string" || typeof item.id !== "string") continue;
            const key = item.kind + ":" + item.id;
            // First declaration wins: a duplicate would otherwise silently hand a surface to
            // whichever app happened to load last.
            if (!map[key]) map[key] = entry.id;
        }
    }
    return map;
}

/// Ids declared for `kind` by enabled apps, in the caller's order (tabs, dock items, …).
function idsForKind(entries, kind) {
    const ids = [];
    const list = Array.isArray(entries) ? entries : [];
    for (let index = 0; index < list.length; index++) {
        const entry = list[index];
        if (!entry || entry.enabled === false) continue;
        const declared = Array.isArray(entry.integrations) ? entry.integrations : [];
        for (let slot = 0; slot < declared.length; slot++) {
            const item = declared[slot];
            if (item && item.kind === kind && typeof item.id === "string" && ids.indexOf(item.id) === -1) {
                ids.push(item.id);
            }
        }
    }
    return ids;
}

/// The app that owns `kind:id`, or "" when nobody does.
function providerOf(map, kind, id) {
    if (!map) return "";
    const owner = map[kind + ":" + id];
    return owner ? owner : "";
}

/// True when some enabled app provides `kind:id`.
function isProvided(map, kind, id) {
    return providerOf(map, kind, id) !== "";
}

/// The integration id of a configured item: `"media"` or `{ id: "media", label: … }`.
///
/// `Config.dashboardTabs` is a list of tab *descriptors* (id, label, icon, enabled), so the
/// filter has to read the id out of the object; stringifying it filtered everything away and
/// left the strip empty (spec C.35).
function idOf(item) {
    if (item && typeof item === "object") {
        return typeof item.id === "string" ? item.id : "";
    }
    return item === undefined || item === null ? "" : String(item);
}

/// Filter a configured list (e.g. `Config.dashboardTabs`) down to what is actually provided.
/// The items keep their shape, so a caller that renders descriptors still gets descriptors.
function providedOnly(map, kind, wanted) {
    const list = Array.isArray(wanted) ? wanted : [];
    const kept = [];
    for (let index = 0; index < list.length; index++) {
        const item = list[index];
        // A descriptor may switch itself off (`enabled: false`) as well.
        if (item && typeof item === "object" && item.enabled === false) continue;
        if (isProvided(map, kind, idOf(item))) kept.push(item);
    }
    return kept;
}
