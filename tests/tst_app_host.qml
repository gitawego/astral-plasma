import QtQuick
import "../modules/Astral/Kernel/Host"

// ============================================================================
// AppHost — load planning, isolation, and on-demand activation
// ============================================================================
// The host is the piece that must never take the shell down. What is asserted here:
//
//  * a corrupt or illegal manifest is reported and skipped, and the apps beside it
//    still load (one bad payload cannot blank the desktop);
//  * nothing is instantiated at boot - activation is a call, not a side effect;
//  * a payload whose QML does not compile reports `appFailed` and returns null
//    instead of throwing into the caller;
//  * dependencies keep loading before their dependants.
//
// The tests use fixture components from `tests/fixtures/apphost/`, so no real app
// is involved and nothing here names an app.
Item {
    id: testRoot
    width: 900
    height: 600

    readonly property string fixtureDir: Qt.resolvedUrl("fixtures/apphost/").toString()

    property var failures: []
    property var loadedEvents: []

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function entry(id, extra) {
        const base = {
            schema: 1,
            id: id,
            version: "1.0.0",
            kernelApi: 1,
            enabled: true,
            blocked: [],
            trust: "official",
            runtime: "embedded",
            entry: { root: "Good.qml" },
            payloadDir: testRoot.fixtureDir
        };
        if (extra) {
            for (const key in extra) {
                base[key] = extra[key];
            }
        }
        return base;
    }

    property var host: null

    function build(entries, options) {
        host = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/Host"; AppHost { }',
            testRoot, "apphost");
        host.entries = entries;
        if (options && options.level !== undefined) {
            host.host = { level: options.level, floor: options.floor };
        }
        host.appFailed.connect(function (id, reason) {
            failures.push({ id: id, reason: reason });
        });
        host.appLoaded.connect(function (id) {
            loadedEvents.push(id);
        });
        return host;
    }

    function stateOf(id) {
        const reason = host.reasonFor(id);
        return reason ? reason.state : "ready";
    }

    function run() {
        // ---- the plan -------------------------------------------------------
        let appHost = build([
            entry("io.github.fixture.good"),
            entry("io.github.fixture.disabled", { enabled: false }),
            entry("io.github.fixture.brokenmanifest", { kernelApi: 0 }),
            entry("io.github.fixture.future", { kernelApi: 9 })
        ]);

        assert(appHost.loadedIds.indexOf("io.github.fixture.good") >= 0,
            "a valid app is in the load plan");
        assert(appHost.loadedIds.indexOf("io.github.fixture.disabled") < 0,
            "a disabled app is not in the load plan");
        assert(stateOf("io.github.fixture.disabled") === "disabled", "state is disabled");

        // A corrupt manifest arrives as an object without kernelApi; the validator
        // refuses it and the host keeps the rest of the plan intact.
        const broken = appHost.reasonFor("io.github.fixture.brokenmanifest");
        assert(broken !== null && broken.state === "invalid", "an illegal manifest is invalid");
        assert(broken.reason.indexOf("kernelApi") >= 0,
            "the reason names the field, got: " + broken.reason);

        const future = appHost.reasonFor("io.github.fixture.future");
        assert(future !== null && future.state === "incompatible",
            "an app for a newer platform is incompatible");
        assert(future.reason.indexOf("API 9") >= 0, "the reason names the level it needs");

        // A hosted app is not this host's job; it is skipped with a distinct state.
        const hosted = build([entry("io.github.fixture.hosted", { runtime: "hosted", entry: { root: "shell.qml" } })]);
        assert(hosted.loadedIds.length === 0, "a hosted app is not embedded");
        const hostedSkip = hosted.reasonFor("io.github.fixture.hosted");
        assert(hostedSkip !== null && hostedSkip.state === "hosted",
            "a hosted app is skipped as hosted, got: " + JSON.stringify(hostedSkip));
        hosted.destroy();

        appHost = build([
            entry("io.github.fixture.good"),
            entry("io.github.fixture.disabled", { enabled: false }),
            entry("io.github.fixture.brokenmanifest", { kernelApi: 0 }),
            entry("io.github.fixture.future", { kernelApi: 9 })
        ]);

        // ---- nothing is instantiated at boot --------------------------------
        assert(appHost.loaders["io.github.fixture.good"] !== undefined,
            "a loader exists for each loadable app");
        assert(appHost.loaders["io.github.fixture.good"].active === false,
            "boot must not instantiate an app");
        assert(loadedEvents.length === 0, "no app is reported loaded before activation");

        // ---- activation -----------------------------------------------------
        const good = appHost.activate("io.github.fixture.good");
        assert(good !== null, "activating a valid app returns its item");
        assert(loadedEvents.indexOf("io.github.fixture.good") >= 0, "appLoaded fires on activation");

        // Activating twice is not an error: the same item comes back.
        const again = appHost.activate("io.github.fixture.good");
        assert(again === good, "activation is idempotent");

        // An unknown id is a reported failure, not a throw.
        assert(appHost.activate("io.github.fixture.ghost") === null,
            "activating an unknown app returns null");
        assert(failures.some(function (item) { return item.id === "io.github.fixture.ghost"; }),
            "activating an unknown app reports appFailed");

        appHost.destroy();
        failures = [];
        loadedEvents = [];

        // ---- a payload that does not compile --------------------------------
        appHost = build([entry("io.github.fixture.broken", { entry: { root: "Broken.qml" } })]);
        assert(appHost.loadedIds.length === 1, "the broken app is planned (its manifest is fine)");
        const brokenItem = appHost.activate("io.github.fixture.broken");
        assert(brokenItem === null, "a payload that does not compile yields null");
        assert(failures.some(function (item) { return item.id === "io.github.fixture.broken"; }),
            "a broken payload reports appFailed");
        // And the shell is still running: this very test continues.
        appHost.destroy();
        failures = [];
        loadedEvents = [];

        // ---- a payload that is not there at all -----------------------------
        appHost = build([entry("io.github.fixture.absent", { entry: { root: "Ghost.qml" } })]);
        assert(appHost.activate("io.github.fixture.absent") === null,
            "a missing payload yields null");
        assert(failures.length === 1, "a missing payload is reported once");
        appHost.destroy();
        failures = [];
        loadedEvents = [];

        // ---- dependencies load first ----------------------------------------
        appHost = build([
            entry("io.github.fixture.child", { requires: { apps: ["io.github.fixture.parent"] } }),
            entry("io.github.fixture.parent")
        ]);
        assert(appHost.loadedIds.join(",") === "io.github.fixture.parent,io.github.fixture.child",
            "dependency order is respected, got: " + appHost.loadedIds.join(","));
        appHost.destroy();
        failures = [];
        loadedEvents = [];

        // ---- one bad payload beside good ones -------------------------------
        // This is the whole point: the plan is built from data, so a corrupt entry
        // changes one row of it and nothing else.
        appHost = build([
            entry("io.github.fixture.good"),
            entry("io.github.fixture.broken", { entry: { root: "Broken.qml" } }),
            entry("io.github.fixture.good2")
        ]);
        assert(appHost.loadedIds.length === 3, "three valid manifests are planned");
        appHost.activate("io.github.fixture.broken");
        assert(appHost.activate("io.github.fixture.good") !== null,
            "a broken app does not prevent another app from loading");
        assert(appHost.activate("io.github.fixture.good2") !== null,
            "the apps after the broken one still load");
        appHost.destroy();
        failures = [];
        loadedEvents = [];

        // ---- mounting into a host-owned surface ------------------------------
        // A dashboard pane embeds an app's item; the pane owns layout, the app owns
        // behaviour. Mounting twice must move the same item, not duplicate it.
        appHost = build([entry("io.github.fixture.good")]);
        const pane = Qt.createQmlObject('import QtQuick; Item { width: 400; height: 300 }', testRoot, "pane");
        const mounted = appHost.mount("io.github.fixture.good", pane);
        assert(mounted !== null, "mounting returns the item");
        assert(mounted.parent === pane, "the item is parented into the pane");
        const remounted = appHost.mount("io.github.fixture.good", pane);
        assert(remounted === mounted, "mounting twice moves the same instance");
        assert(appHost.mount("io.github.fixture.ghost", pane) === null,
            "mounting an unknown app returns null");
        pane.destroy();
        appHost.destroy();
        failures = [];
        loadedEvents = [];

        // ---- the shell only uses host API that exists -------------------------
        // A scripted edit once dropped `itemFor` from AppHost while leaving
        // `shell.qml` calling it: nothing failed at load, only when that IPC ran. This
        // asserts every `featureHost.<name>` in the shell exists on the host.
        const shellSource = (function () {
            const xhr = new XMLHttpRequest();
            xhr.open("GET", Qt.resolvedUrl("../shell.qml") + "?v=" + Date.now(), false);
            xhr.send();
            return xhr.responseText || "";
        })();
        assert(shellSource.length > 1000, "shell.qml must be readable");

        appHost = build([entry("io.github.fixture.good")]);
        const used = [];
        const pattern = /featureHost\.([A-Za-z_][A-Za-z0-9_]*)/g;
        let match = pattern.exec(shellSource);
        while (match !== null) {
            if (used.indexOf(match[1]) < 0) {
                used.push(match[1]);
            }
            match = pattern.exec(shellSource);
        }
        assert(used.length > 0, "the shell must talk to the host");
        for (const name of used) {
            assert(typeof appHost[name] !== "undefined",
                "shell.qml calls featureHost." + name + " but AppHost does not define it");
        }
        appHost.destroy();
        failures = [];
        loadedEvents = [];

        // ---- an empty registry ----------------------------------------------
        appHost = build([]);
        assert(appHost.loaded.length === 0 && appHost.skipped.length === 0,
            "an empty registry is silent");
        appHost.destroy();

        console.log("PASS: All app host tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
