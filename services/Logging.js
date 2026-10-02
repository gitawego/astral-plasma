.pragma library

// ============================================================================
// Diagnostic log levels
// ============================================================================
// One place decides whether a diagnostic message is worth printing. The shell
// used to decide with a single boolean (`debugMode`), which meant the per-frame
// trails (`[blur] active: (none)`, `[commit] ...`) either buried the log or were
// unavailable exactly when they were needed.
//
// Every message carries a level; every message belongs to a category ("blur",
// "commit", "voice", ...). The effective level of a category is resolved from,
// in order of precedence:
//
//   1. `ASTRAL_PLASMA_LOG_CATEGORIES[category]` - one category, this run
//   2. `logging.categories[category]`           - one category, persisted
//   3. `ASTRAL_PLASMA_LOG_LEVEL`                - everything, this run
//   4. `logging.level`                          - everything, persisted
//   5. `debugMode: true`                        - the legacy toggle
//   6. DEFAULT_LEVEL                            - shipped default
//
// Only pure functions live here, so the whole decision table is unit-testable
// without a compositor (`tests/tst_log_level.qml`). `services/Log.qml` is the
// reactive singleton that feeds these functions their inputs and prints.

/// Levels, quietest first. `off` silences everything; `trace` is the loudest.
var LEVELS = ["off", "error", "warn", "info", "debug", "trace"];

/// Level used when nothing else is configured.
///
/// It must match the shipped `logging.level` in `config/settings.json`; the test
/// suite pins the two together so a change in one cannot silently deafen the other.
var DEFAULT_LEVEL = "info";

/// Canonical level name for `value`, or `null` when it is not a level.
///
/// `null` is what callers use to tell "not configured" from "configured to the
/// default": an empty or malformed value must not shadow a setting.
function parseLevel(value) {
    if (value === undefined || value === null) {
        return null;
    }
    var text = String(value).trim().toLowerCase();
    if (text.length === 0) {
        return null;
    }
    for (var i = 0; i < LEVELS.length; ++i) {
        if (LEVELS[i] === text) {
            return text;
        }
    }
    return null;
}

/// Canonical level name, falling back to the quiet default.
function normalize(value) {
    var level = parseLevel(value);
    return level === null ? DEFAULT_LEVEL : level;
}

/// How loud a level is. An unparseable level ranks as the default, so a typo can
/// never make the log louder than the user asked for.
function rank(value) {
    return LEVELS.indexOf(normalize(value));
}

/// Parse `"blur=debug, commit=trace"` into `{ blur: "debug", commit: "trace" }`.
///
/// Malformed entries are ignored rather than guessed: a half-understood override
/// must not silently change what gets printed.
function parseCategories(value) {
    var map = {};
    if (value === undefined || value === null) {
        return map;
    }
    var entries = String(value).split(",");
    for (var i = 0; i < entries.length; ++i) {
        var entry = entries[i];
        var separator = entry.indexOf("=");
        if (separator <= 0) {
            continue;
        }
        var category = entry.substring(0, separator).trim().toLowerCase();
        var level = parseLevel(entry.substring(separator + 1));
        if (category.length === 0 || level === null) {
            continue;
        }
        map[category] = level;
    }
    return map;
}

/// The category entry of an override map, accepting either a parsed map or the
/// raw `"a=b,c=d"` text an environment variable carries.
function categoryLevel(map, category) {
    if (map === undefined || map === null) {
        return null;
    }
    if (typeof map === "string") {
        map = parseCategories(map);
    }
    return map[category];
}

/// Effective level of `category` under `settings` and `env`.
///
/// `env` is `{ level: <string>, categories: <map or string> }`; either field may
/// be absent. `settings` is the shell's settings document, so `debugMode` is
/// still honoured for the people who use it.
function levelFor(category, settings, env) {
    settings = settings || {};
    env = env || {};
    var logging = settings.logging || {};
    var key = String(category === undefined || category === null ? "" : category).trim().toLowerCase();

    var candidates = [
        categoryLevel(env.categories, key),
        categoryLevel(logging.categories, key),
        env.level,
        logging.level
    ];
    for (var i = 0; i < candidates.length; ++i) {
        var level = parseLevel(candidates[i]);
        if (level !== null) {
            return level;
        }
    }

    // The legacy toggle: before levels existed it gated every diagnostic trail,
    // and it keeps doing that until a level is configured.
    if (settings.debugMode === true) {
        return "debug";
    }
    return DEFAULT_LEVEL;
}

/// Should a message of `level` in `category` be printed?
function isEnabled(category, level, settings, env) {
    var messageLevel = parseLevel(level);
    if (messageLevel === null) {
        return false;
    }
    return rank(messageLevel) <= rank(levelFor(category, settings, env));
}

/// Render a line. The category is its identity: it is what a reader greps for
/// and what the level overrides address.
function format(category, message) {
    return "[" + category + "] " + message;
}
