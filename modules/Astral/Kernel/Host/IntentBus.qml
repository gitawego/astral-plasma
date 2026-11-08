import QtQuick

// ============================================================================
// IntentBus — how a surface asks the shell to do something
// ============================================================================
// A migrated app cannot call `Config.closeOverview()`: it does not share the
// shell's singleton instances (see spec C.9), so an imported `Config` is a stale
// copy. Actions therefore travel as named intents through one bus the shell owns
// and hands to the app instance.
//
// The result is the shell's existing `ActionResult` vocabulary — `applied`,
// `pending`, `unsupported`, `denied`, `invalid`, `stale` — so a caller can render
// "this app is not installed" instead of attaching an empty handler or a dead
// button.
//
// Nothing here may throw: a handler that throws is reported as `invalid`, because
// a misbehaving app must not take the caller down with it.
QtObject {
    id: root

    /// `name -> handler`. Handlers are JS functions: `(args) => result`.
    property var handlers: ({})

    /// Registered intent names (a function, not a binding: `handlers` is replaced
    /// wholesale on every change, and callers want the current list).
    function list() {
        return Object.keys(handlers);
    }

    signal intentFailed(string name, string reason)

    // ---- result constructors ------------------------------------------------

    function applied(value) {
        return value === undefined
            ? { status: "applied" }
            : { status: "applied", value: value };
    }

    function pending(token) {
        return token === undefined
            ? { status: "pending" }
            : { status: "pending", token: token };
    }

    function unsupported(name) {
        return {
            status: "unsupported",
            reason: "nothing handles '" + String(name) + "' (is the app installed?)"
        };
    }

    function denied(reason) {
        return { status: "denied", reason: reason || "denied" };
    }

    function invalid(reason) {
        return { status: "invalid", reason: reason || "invalid request" };
    }

    // ---- registration -------------------------------------------------------

    /// Register a handler. Replacing an existing one is reported, not silent: two
    /// owners for one intent is a wiring bug.
    function register(name, handler) {
        if (typeof name !== "string" || name.length === 0) {
            return false;
        }
        if (typeof handler !== "function") {
            return false;
        }
        const next = handlers;
        next[name] = handler;
        handlers = next;
        return true;
    }

    function unregister(name) {
        if (!handlers[name]) {
            return false;
        }
        const next = handlers;
        delete next[name];
        handlers = next;
        return true;
    }

    function has(name) {
        return typeof handlers[name] === "function";
    }

    // ---- dispatch -----------------------------------------------------------

    /// Ask for something. Always returns a result object; never throws.
    function request(name, args) {
        if (typeof name !== "string" || name.length === 0) {
            return invalid("an intent needs a name");
        }
        const handler = handlers[name];
        if (typeof handler !== "function") {
            return unsupported(name);
        }
        let result = null;
        try {
            result = handler(args === undefined ? ({}) : args);
        } catch (error) {
            const reason = "handler for '" + name + "' threw: " + error;
            root.intentFailed(name, reason);
            return invalid(reason);
        }
        if (!result || typeof result !== "object" || typeof result.status !== "string") {
            const reason = "handler for '" + name + "' returned no ActionResult";
            root.intentFailed(name, reason);
            return invalid(reason);
        }
        if (result.status === "denied" || result.status === "invalid") {
            root.intentFailed(name, result.reason || result.status);
        }
        return result;
    }
}
