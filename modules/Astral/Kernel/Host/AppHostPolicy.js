.pragma library

// ============================================================================
// App host policy
// ============================================================================
// What the shell should load, and what it should skip, decided from data alone.
//
// `AppHost` is the thing that instantiates QML items, so it cannot be unit
// tested without a session. Everything it *decides* lives here instead: which
// entries are loadable, why the rest are not, and in what order the loadable ones
// come. The shell renders the answer; the tests assert it.
//
// Nothing here knows any app by name. An app is loadable because its own data
// says so (enabled, inside the API window, its dependencies present) - not
// because the shell has a list of the apps it likes.
//
// States, in the order the checks run:
//   invalid              the entry is unusable (no id, duplicate id)
//   disabled             the user turned it off; its files stay
//   blocked              this exact version is blocked after a failed load
//   incompatible         outside the platform's API window
//   unresolvedDependency a required app is missing, disabled, or in a cycle
//   ready                the host should load it

/// Platform window, injected by the caller so the policy never guesses.
var DEFAULT_HOST = { level: 1, floor: 1, quickshell: "" };

function normalizeHost(host) {
    const level = host && isFinite(host.level) ? Number(host.level) : DEFAULT_HOST.level;
    const floor = host && isFinite(host.floor) ? Number(host.floor) : DEFAULT_HOST.floor;
    // A floor above the level would reject everything; clamp rather than emit a
    // policy that can only say no.
    return {
        level: level,
        floor: Math.min(floor, level),
        quickshell: (host && host.quickshell) ? String(host.quickshell) : ""
    };
}

/// Compare two MAJOR.MINOR.PATCH[-pre] versions. Returns <0, 0, >0.
function compareVersions(a, b) {
    function split(text) {
        const parts = String(text || "").trim().split("-");
        return {
            core: parts[0].split(".").map(function (p) { return parseInt(p, 10) || 0; }),
            pre: parts.length > 1 ? parts.slice(1).join("-") : null
        };
    }
    const left = split(a);
    const right = split(b);
    const length = Math.max(left.core.length, right.core.length);
    for (let index = 0; index < length; index++) {
        const l = left.core[index] || 0;
        const r = right.core[index] || 0;
        if (l !== r) {
            return l < r ? -1 : 1;
        }
    }
    if (left.pre === null && right.pre === null) return 0;
    if (left.pre === null) return 1;
    if (right.pre === null) return -1;
    return left.pre < right.pre ? -1 : (left.pre > right.pre ? 1 : 0);
}

function isVersion(text) {
    return /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/.test(String(text || "").trim());
}

/// Why an entry cannot load, or "" when it can.
function compatibilityIssue(entry, host) {
    const level = Number(entry.kernelApi || 0);
    if (!level) {
        return "the manifest declares no kernelApi";
    }
    if (level > host.level) {
        return "needs a newer Astral (API " + level + "); this is API " + host.level;
    }
    if (level < host.floor) {
        return "built for API " + level + ", which this shell no longer loads (floor "
            + host.floor + ")";
    }
    const floor = entry.minQuickshell;
    if (floor) {
        if (!host.quickshell) {
            return "needs Quickshell " + floor + " or newer; this shell did not say";
        }
        if (compareVersions(floor, host.quickshell) > 0) {
            return "needs Quickshell " + floor + " or newer; this is " + host.quickshell;
        }
    }
    return "";
}

function requiresOf(entry) {
    const requires = entry && entry.requires ? entry.requires : null;
    const apps = requires && Array.isArray(requires.apps) ? requires.apps : [];
    return apps.filter(function (id) { return typeof id === "string" && id.length > 0; });
}

/// Decide the load set.
///
/// Returns `{ load: [entry...], skipped: [{ id, state, reason }] }`.
/// `load` is dependency-ordered; ties break by id so two boots of the same
/// registry produce the same scene graph in the same order.
function plan(entries, host) {
    const window = normalizeHost(host);
    const skipped = [];
    const candidates = [];
    const seen = {};

    (Array.isArray(entries) ? entries : []).forEach(function (entry) {
        if (!entry || typeof entry.id !== "string" || entry.id.length === 0) {
            skipped.push({ id: "", state: "invalid", reason: "the entry has no id" });
            return;
        }
        if (seen[entry.id]) {
            skipped.push({
                id: entry.id,
                state: "invalid",
                reason: "the registry lists this id more than once"
            });
            return;
        }
        seen[entry.id] = true;
        if (!isVersion(entry.version)) {
            skipped.push({
                id: entry.id,
                state: "invalid",
                reason: "'" + String(entry.version) + "' is not a version"
            });
            return;
        }
        if (!entry.enabled) {
            skipped.push({
                id: entry.id,
                state: "disabled",
                reason: "disabled in the registry; its files stay on disk"
            });
            return;
        }
        const blocked = Array.isArray(entry.blocked) ? entry.blocked : [];
        if (blocked.indexOf(entry.version) >= 0) {
            skipped.push({
                id: entry.id,
                state: "blocked",
                reason: entry.version + " is blocked after a failed load"
            });
            return;
        }
        const issue = compatibilityIssue(entry, window);
        if (issue) {
            skipped.push({ id: entry.id, state: "incompatible", reason: issue });
            return;
        }
        candidates.push(entry);
    });

    // Resolve dependencies over the *candidate* set: a dependency that is
    // disabled or incompatible is as unavailable as a missing one.
    const byId = {};
    candidates.forEach(function (entry) { byId[entry.id] = entry; });

    const state = {};
    const ordered = [];
    const visiting = {};

    function visit(entry, chain) {
        if (state[entry.id] === "done") {
            return true;
        }
        if (state[entry.id] === "fail") {
            return false;
        }
        if (visiting[entry.id]) {
            const cycle = chain.slice(chain.indexOf(entry.id)).concat([entry.id]).join(" -> ");
            skipped.push({
                id: entry.id,
                state: "unresolvedDependency",
                reason: "dependency cycle: " + cycle
            });
            state[entry.id] = "fail";
            return false;
        }
        visiting[entry.id] = true;
        const missing = [];
        const requires = requiresOf(entry);
        for (let index = 0; index < requires.length; index++) {
            const dependency = byId[requires[index]];
            if (!dependency) {
                missing.push(requires[index]);
                continue;
            }
            if (!visit(dependency, chain.concat([entry.id]))) {
                missing.push(requires[index]);
            }
        }
        delete visiting[entry.id];
        if (missing.length > 0) {
            skipped.push({
                id: entry.id,
                state: "unresolvedDependency",
                reason: "requires " + missing.join(", ")
            });
            state[entry.id] = "fail";
            return false;
        }
        state[entry.id] = "done";
        ordered.push(entry);
        return true;
    }

    candidates
        .slice()
        .sort(function (a, b) { return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0); })
        .forEach(function (entry) { visit(entry, []); });

    return { load: ordered, skipped: skipped };
}

/// The ids the host should load, in order.
function loadIds(entries, host) {
    return plan(entries, host).load.map(function (entry) { return entry.id; });
}

/// A skipped entry, looked up by id (for the Apps page and the logs).
function reasonFor(planResult, id) {
    for (let index = 0; index < planResult.skipped.length; index++) {
        if (planResult.skipped[index].id === id) {
            return planResult.skipped[index];
        }
    }
    return null;
}
