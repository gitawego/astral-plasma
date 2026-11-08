.pragma library

// ============================================================================
// App manifest at load time
// ============================================================================
// Rust is the authority: it validates at install and refuses to record a bad
// manifest. The shell still has to re-check at *load*, because the payload on disk
// can be edited after install and because the host must never resolve an import it
// cannot satisfy.
//
// This is the minimum the host needs to decide, not a second schema: identity,
// version shape, the API level, and an entry root that stays inside the payload.
// Everything else is the installer's job, and the two sides are kept honest by the
// shared fixtures in `tests/fixtures/apps/` (both this file and
// `daemon/tests/test_app_manifest_fixtures.rs` read them).
//
// Every refusal returns a state + reason, so the Apps page can explain it instead
// of showing an app that silently never appears.

/// Validate a parsed manifest object. Returns `{ ok: bool, state, reason }`.
function validate(manifest) {
    if (!manifest || typeof manifest !== "object") {
        return fail("invalid", "the manifest is not an object");
    }
    if (manifest.schema !== 1) {
        return fail("invalid", "manifest schema " + manifest.schema + " is not supported");
    }
    const id = manifest.id;
    if (typeof id !== "string" || !isAppId(id)) {
        return fail("invalid", "app id '" + id + "' is not a reverse-DNS id");
    }
    if (typeof manifest.version !== "string" || !isVersion(manifest.version)) {
        return fail("invalid", "version '" + manifest.version
            + "' is not MAJOR.MINOR.PATCH[-prerelease]");
    }
    const level = manifest.kernelApi;
    if (typeof level !== "number" || !isFinite(level) || level < 1) {
        return fail("invalid", "the manifest declares no valid kernelApi");
    }
    const entry = manifest.entry;
    if (!entry || typeof entry.root !== "string" || entry.root.length === 0) {
        return fail("invalid", "entry.root is missing");
    }
    const problem = rootProblem(entry.root);
    if (problem) {
        return fail("invalid", problem);
    }
    const trust = manifest.trust;
    if (["official", "verified", "community", "local-dev"].indexOf(trust) < 0) {
        return fail("invalid", "trust '" + trust + "' is not a known trust level");
    }
    const runtime = manifest.runtime;
    if (runtime !== "embedded" && runtime !== "hosted") {
        return fail("invalid", "runtime '" + runtime + "' is not embedded or hosted");
    }
    if (runtime === "embedded" && trust !== "official") {
        return fail("invalid", "a " + trust + " app cannot run embedded");
    }
    if (runtime === "hosted" && entry.root !== "shell.qml") {
        return fail("invalid", "a hosted app's entry.root must be shell.qml");
    }
    return { ok: true, state: "ready", reason: "" };
}

function fail(state, reason) {
    return { ok: false, state: state, reason: reason };
}

/// `io.github.alice.clock`: lower-case segments, at least two, joined by dots.
function isAppId(id) {
    if (id.length === 0 || id.length > 128) return false;
    const segments = id.split(".");
    if (segments.length < 2) return false;
    for (let index = 0; index < segments.length; index++) {
        const segment = segments[index];
        if (segment.length === 0 || segment.length > 63) return false;
        if (!/^[a-z0-9][a-z0-9-]*$/.test(segment)) return false;
    }
    return true;
}

function isVersion(text) {
    return /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/.test(String(text || "").trim());
}

/// Why `entry.root` cannot be used, or "" when it can.
function rootProblem(root) {
    if (root.charAt(0) === "/") {
        return "entry.root '" + root + "' must be relative to the payload";
    }
    const segments = root.split("/");
    for (let index = 0; index < segments.length; index++) {
        if (segments[index] === "..") {
            return "entry.root '" + root + "' must not escape the payload";
        }
    }
    if (!/\.qml$/.test(root)) {
        return "entry.root '" + root + "' must be a .qml file";
    }
    return "";
}
