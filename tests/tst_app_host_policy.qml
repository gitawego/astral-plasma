import QtQuick
import "../modules/Astral/Kernel/Host/AppHostPolicy.js" as Policy

// ============================================================================
// App host policy
// ============================================================================
// The host's decisions are data-driven: which apps load, why the others do not,
// and in what order. Nothing here names a real app, and the tests only use
// fixtures - an app is loadable because its own entry says so.
//
// What is asserted: the API window, the blocked-version rule, dependency order,
// missing and cyclic dependencies, duplicate ids, and determinism. What is *not*
// asserted here: that QML items get instantiated - that is `AppHost`, and it needs
// a session (P2 remainder).
Item {
    id: testRoot
    width: 600
    height: 400

    readonly property var host: ({ level: 1, floor: 1, quickshell: "0.3.2" })

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function entry(id, extra) {
        const base = {
            id: id,
            version: "1.0.0",
            kernelApi: 1,
            enabled: true,
            blocked: []
        };
        if (extra) {
            for (const key in extra) {
                base[key] = extra[key];
            }
        }
        return base;
    }

    function stateOf(planResult, id) {
        const found = Policy.reasonFor(planResult, id);
        return found ? found.state : "ready";
    }

    function run() {
        // ---- the happy path --------------------------------------------------
        let result = Policy.plan([entry("a.one"), entry("a.two")], host);
        assert(result.load.length === 2, "both compatible apps load");
        assert(result.skipped.length === 0, "nothing is skipped when everything fits");
        assert(Policy.loadIds([entry("a.two"), entry("a.one")], host).join(",") === "a.one,a.two",
            "load order is deterministic and does not follow registry order");

        // ---- disabled -------------------------------------------------------
        result = Policy.plan([entry("a.one", { enabled: false })], host);
        assert(result.load.length === 0, "a disabled app is not loaded");
        assert(stateOf(result, "a.one") === "disabled", "state is disabled");
        assert(Policy.reasonFor(result, "a.one").reason.indexOf("files stay") >= 0,
            "the reason says the files stay on disk");

        // ---- blocked version ------------------------------------------------
        result = Policy.plan([entry("a.one", { version: "1.2.0", blocked: ["1.2.0"] })], host);
        assert(result.load.length === 0, "a blocked version is not retried");
        assert(stateOf(result, "a.one") === "blocked", "state is blocked");
        assert(Policy.reasonFor(result, "a.one").reason.indexOf("1.2.0") >= 0,
            "the blocked version is named");

        // A different version of the same app is loadable again.
        result = Policy.plan([entry("a.one", { version: "1.2.1", blocked: ["1.2.0"] })], host);
        assert(result.load.length === 1, "blocking one version does not block the app");

        // ---- compatibility window -------------------------------------------
        result = Policy.plan([entry("a.one", { kernelApi: 2 })], host);
        assert(stateOf(result, "a.one") === "incompatible", "an app above the API level is skipped");
        const above = Policy.reasonFor(result, "a.one").reason;
        assert(above.indexOf("API 2") >= 0 && above.indexOf("API 1") >= 0,
            "the reason names both levels, got: " + above);

        result = Policy.plan([entry("a.one")], { level: 3, floor: 2, quickshell: "" });
        assert(stateOf(result, "a.one") === "incompatible", "an app below the floor is skipped");
        assert(Policy.reasonFor(result, "a.one").reason.indexOf("floor 2") >= 0,
            "the reason names the floor");

        result = Policy.plan([entry("a.one", { minQuickshell: "0.4.0" })], host);
        assert(stateOf(result, "a.one") === "incompatible", "a newer Quickshell floor is refused");
        assert(Policy.reasonFor(result, "a.one").reason.indexOf("0.4.0") >= 0,
            "the required Quickshell version is named");

        result = Policy.plan([entry("a.one", { minQuickshell: "0.3.0" })], host);
        assert(result.load.length === 1, "a satisfied Quickshell floor loads");

        result = Policy.plan([entry("a.one", { kernelApi: 0 })], host);
        assert(stateOf(result, "a.one") === "incompatible", "a missing kernelApi is refused");

        // ---- dependencies ---------------------------------------------------
        result = Policy.plan([
            entry("a.child", { requires: { apps: ["a.parent"] } }),
            entry("a.parent")
        ], host);
        assert(Policy.loadIds([
            entry("a.child", { requires: { apps: ["a.parent"] } }),
            entry("a.parent")
        ], host).join(",") === "a.parent,a.child", "dependencies load before their dependants");

        result = Policy.plan([entry("a.child", { requires: { apps: ["a.ghost"] } })], host);
        assert(result.load.length === 0, "an app with a missing dependency is not loaded");
        assert(stateOf(result, "a.child") === "unresolvedDependency", "state is unresolvedDependency");
        assert(Policy.reasonFor(result, "a.child").reason.indexOf("a.ghost") >= 0,
            "the missing dependency is named");

        // A disabled dependency is as unavailable as a missing one.
        result = Policy.plan([
            entry("a.child", { requires: { apps: ["a.parent"] } }),
            entry("a.parent", { enabled: false })
        ], host);
        assert(result.load.length === 0, "a disabled dependency blocks its dependant");
        assert(stateOf(result, "a.child") === "unresolvedDependency", "state is unresolvedDependency");

        // Cycles are reported, not infinite-looped.
        result = Policy.plan([
            entry("a.one", { requires: { apps: ["a.two"] } }),
            entry("a.two", { requires: { apps: ["a.one"] } })
        ], host);
        assert(result.load.length === 0, "a dependency cycle loads neither app");
        assert(stateOf(result, "a.one") === "unresolvedDependency", "cycle is unresolvedDependency");
        assert(Policy.reasonFor(result, "a.one").reason.indexOf("cycle") >= 0,
            "the reason says cycle");

        // ---- malformed registry data ----------------------------------------
        result = Policy.plan([entry("a.one"), entry("a.one")], host);
        assert(result.load.length === 1, "a duplicated id loads once");
        assert(result.skipped.length === 1, "the duplicate is reported");
        assert(stateOf(result, "a.one") === "invalid", "duplicate ids are invalid");

        result = Policy.plan([{ version: "1.0.0", kernelApi: 1, enabled: true }], host);
        assert(stateOf(result, "") === "invalid", "an entry without an id is invalid");

        result = Policy.plan([entry("a.one", { version: "1.0" })], host);
        assert(stateOf(result, "a.one") === "invalid", "a malformed version is invalid");

        result = Policy.plan(null, host);
        assert(result.load.length === 0 && result.skipped.length === 0,
            "an absent registry loads nothing and complains about nothing");

        // ---- a floor above the level cannot reject everything ----------------
        result = Policy.plan([entry("a.one")], { level: 1, floor: 9, quickshell: "" });
        assert(result.load.length === 1, "an incoherent host window is clamped, not fatal");

        console.log("PASS: All app host policy tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
