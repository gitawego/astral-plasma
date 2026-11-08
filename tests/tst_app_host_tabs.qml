import QtQuick
import "../modules/Astral/Kernel/Host"

// ============================================================================
// Dashboard tabs from data
// ============================================================================
// The dashboard used to `switch` over six known tab ids with a `Component` per tab -
// a hardcoded feature list. Tabs are now offered by apps: a manifest declares
// `entry.dashboardTab`, and the host answers "who provides this tab?".
//
// What is asserted: providers are collected from the plan (not from a list), an
// unowned tab has no provider, and an app for a newer platform is not consulted.
Item {
    id: testRoot
    width: 600
    height: 400

    readonly property string fixtureDir: Qt.resolvedUrl("fixtures/apphost/").toString()

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function entry(id, tab) {
        const entry = {
            schema: 1,
            id: id,
            version: "1.0.0",
            kernelApi: 1,
            enabled: true,
            blocked: [],
            trust: "official",
            runtime: "embedded",
            entry: { root: "TabApp.qml" },
            payloadDir: testRoot.fixtureDir
        };
        if (tab) {
            entry.entry.dashboardTab = tab;
        }
        return entry;
    }

    function run() {
        const host = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/Host"; AppHost { }',
            testRoot, "host");
        host.entries = [
            entry("org.astralplasma.workspaces", "workspaces"),
            entry("org.astralplasma.media", "media"),
            entry("org.astralplasma.silent")
        ];

        assert(host.providerForTab("workspaces") === "org.astralplasma.workspaces",
            "the workspaces tab is provided by its app");
        assert(host.providerForTab("media") === "org.astralplasma.media",
            "the media tab is provided by its app");
        assert(host.providerForTab("downloads") === "",
            "a tab no installed app declares has no provider");

        // Providers come from the *plan*: an app for a newer platform is skipped, so
        // its tab is not offered.
        host.entries = [
            entry("org.astralplasma.future", "futuretab"),
            { schema: 1, id: "org.astralplasma.broken", version: "1.0.0", kernelApi: 9,
              enabled: true, blocked: [], trust: "official", runtime: "embedded",
              entry: { root: "TabApp.qml", dashboardTab: "broken" },
              payloadDir: testRoot.fixtureDir }
        ];
        assert(host.providerForTab("broken") === "",
            "an incompatible app provides no tab");
        assert(host.providerForTab("futuretab") === "org.astralplasma.future",
            "the compatible app still provides its tab");

        // A disabled app provides nothing, and its files stay. (Assigning a new list
        // is what re-evaluates the plan: mutating an element in place would not.)
        const disabled = entry("org.astralplasma.workspaces", "workspaces");
        disabled.enabled = false;
        host.entries = [disabled];
        assert(host.providerForTab("workspaces") === "",
            "a disabled app provides no tab");

        // No apps: no providers, no error.
        host.entries = [];
        assert(Object.keys(host.tabProviders).length === 0, "an empty registry offers no tabs");

        host.destroy();
        console.log("PASS: All app host tab tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
