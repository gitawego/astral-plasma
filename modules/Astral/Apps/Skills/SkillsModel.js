.pragma library

// Pure presentation logic for the Skills app, kept out of the QML so it is testable offscreen.

/// How a skill's state reads, and which colour role it asks for.
function stateLabel(skill) {
    if (!skill) return "Unknown";
    return skill.state === "linked" ? "Enabled" : "Disabled";
}

/// A list that works whether QML handed us a JS array or a QVariantList proxy.
///
/// `Array.isArray` is false for a list property read through the QML engine, and treating that as
/// "no skills" made a repository row read `0 of 0` while its skills were listed underneath.
function listOf(value) {
    if (!value) return [];
    if (Array.isArray(value)) return value;
    const length = typeof value.length === "number" ? value.length : 0;
    const out = [];
    for (let index = 0; index < length; index++) {
        out.push(value[index]);
    }
    return out;
}

/// Share of a source's skills that are enabled, 0..100.
function sourcePercent(source) {
    if (!source) return 0;
    const skills = listOf(source.skills);
    if (skills.length === 0) return 0;
    const enabled = skills.filter(function (skill) { return skill && skill.state === "linked"; }).length;
    return Math.round(100 * enabled / skills.length);
}

/// "3 of 12 enabled" — the sentence a repository row shows.
function sourceSummary(source) {
    const skills = listOf(source && source.skills);
    const enabled = skills.filter(function (skill) { return skill && skill.state === "linked"; }).length;
    return enabled + " of " + skills.length + " enabled";
}

/// Group findings by kind, newest kinds last, for the Doctor section.
function groupFindings(findings) {
    const order = [];
    const groups = ({});
    const list = listOf(findings);
    for (let index = 0; index < list.length; index++) {
        const finding = list[index];
        const kind = (finding && typeof finding.kind === "string") ? finding.kind : "other";
        if (!groups[kind]) {
            groups[kind] = [];
            order.push(kind);
        }
        groups[kind].push(finding);
    }
    return order.map(function (kind) { return { kind: kind, items: groups[kind] }; });
}

/// What a search box should do: an empty query is not a search.
function shouldSearch(query) {
    return typeof query === "string" && query.trim().length >= 2;
}

/// The one-line description under a search hit.
function hitDetail(hit) {
    if (!hit) return "";
    if (hit.description && hit.description.length > 0) return hit.description;
    if (Number(hit.installs || 0) > 0) return Number(hit.installs) + " installs";
    return "";
}
