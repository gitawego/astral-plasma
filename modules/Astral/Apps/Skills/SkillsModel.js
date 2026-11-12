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

/// What a hit is: a whole repository (GitHub) or one skill inside one (skills.sh).
function hitKind(hit) {
    return (hit && hit.kind === "skill") ? "skill" : "repository";
}

/// The title of a search row.
///
/// A GitHub hit names a repository, so the repository is the title. A skills.sh hit names one
/// skill of a repository, so the skill is the title and the repository is context — rendering both
/// as `source` made the two tabs look identical while they return different things.
function hitTitle(hit) {
    if (!hit) return "";
    if (hitKind(hit) === "skill") {
        return String(hit.name || hit.source || "");
    }
    return String(hit.source || hit.name || "");
}

/// The badge a row shows: `repo` or `skill`.
function hitBadge(hit) {
    return hitKind(hit) === "skill" ? "skill" : "repo";
}

/// What the row says under the title.
function hitSubtitle(hit) {
    if (!hit) return "";
    const detail = hitDetail(hit);
    if (hitKind(hit) === "skill" && hit.source) {
        return detail.length > 0 ? detail + " · " + hit.source : String(hit.source);
    }
    return detail;
}

/// The install call a hit implies: a repository installs all of it, a skill hit installs that
/// one skill of its repository.
function installTarget(hit) {
    if (!hit) return { source: "", skills: [] };
    if (hitKind(hit) === "skill") {
        return { source: String(hit.source || ""), skills: [String(hit.name || "")] };
    }
    return { source: String(hit.source || ""), skills: [] };
}

/// The one-line description under a search hit.
function hitDetail(hit) {
    if (!hit) return "";
    if (hit.description && hit.description.length > 0) return hit.description;
    if (Number(hit.installs || 0) > 0) return Number(hit.installs) + " installs";
    return "";
}

// ---- MCP status -----------------------------------------------------------

/// The server state as a short word. A missing report is "checking", not "down":
/// the page must not accuse a server before the probe has run.
function mcpState(server) {
    if (!server) return "checking";
    return String(server.state || (server.reachable ? "up" : "down"));
}

function mcpStateLabel(server) {
    switch (mcpState(server)) {
        case "up": return "Up";
        case "down": return "Down";
        case "wrong-service": return "Wrong service";
        default: return "Checking…";
    }
}

function mcpStateIcon(server) {
    return mcpState(server) === "up" ? "check_circle" : "warning";
}

/// "4 tools · 2026-07-28", or the refusal sentence when the probe failed.
function mcpDetail(server) {
    if (!server) return "Checking the endpoint…";
    if (mcpState(server) === "up") {
        const tools = (server.tools || []).length;
        return tools + " tools" + (server.protocol ? " · " + server.protocol : "");
    }
    return String(server.detail || "");
}

function agentState(agent) {
    if (!agent) return "unknown";
    if (!agent.installed) return "not-installed";
    return agent.configured ? "configured" : "not-configured";
}

function agentStateLabel(agent) {
    switch (agentState(agent)) {
        case "configured": return "Configured";
        case "not-configured": return "Not configured";
        case "not-installed": return "Not installed";
        default: return "Unknown";
    }
}

function agentStateIcon(agent) {
    return agentState(agent) === "configured" ? "check_circle" : "radio_button_unchecked";
}

function mcpSummary(report) {
    if (!report) return "Checking…";
    const installed = Number(report.installedCount || 0);
    const configured = Number(report.configuredCount || 0);
    if (installed === 0) return "No supported agent detected";
    return configured + " of " + installed + " installed agents configured";
}
