import QtQuick
import "../modules/Astral/Kernel/Host"

// ============================================================================
// AppHost state injection
// ============================================================================
// The reason this exists: a surface loaded through a Loader gets its *own*
// singleton instance, so an imported `Config` is a stale copy (spec C.9). The shell
// therefore injects one state object and one intent bus, and the app sees the very
// instance the shell mutates.
//
// What is asserted: the app receives the injected objects, receives *the same*
// instance (identity, not equality), sees a later mutation, and an app that
// declares neither property still loads.
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

    function entry(id, root) {
        return {
            schema: 1,
            id: id,
            version: "1.0.0",
            kernelApi: 1,
            enabled: true,
            blocked: [],
            trust: "official",
            runtime: "embedded",
            entry: { root: root },
            payloadDir: testRoot.fixtureDir
        };
    }

    function run() {
        // A state object the test mutates later, standing in for ShellState.
        const state = Qt.createQmlObject(
            'import QtQuick; QtObject { property bool overviewVisible: false }',
            testRoot, "state");
        const bus = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/Host"; IntentBus { }',
            testRoot, "bus");

        const host = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/Host"; AppHost { }',
            testRoot, "host");
        host.entries = [
            entry("io.github.fixture.stateful", "StatefulApp.qml"),
            entry("io.github.fixture.stateless", "Good.qml")
        ];
        host.state = state;
        host.intents = bus;

        const app = host.activate("io.github.fixture.stateful");
        assert(app !== null, "the stateful app loads");
        assert(app.shellState !== null, "the app received a state object");
        assert(app.shellState === state, "it is the same instance the shell holds, not a copy");
        assert(app.intents === bus, "the app received the shell's intent bus");

        // The identity matters: mutating the shell's object must be visible in the app.
        state.overviewVisible = true;
        assert(app.shellState.overviewVisible === true,
            "a mutation on the shell's state is visible in the app");

        // The app can act through the bus.
        let closed = false;
        bus.register("overview.close", function () { closed = true; return bus.applied(); });
        assert(app.intents.request("overview.close").status === "applied",
            "the app can dispatch an intent");
        assert(closed, "the handler ran");

        // An app that declares neither property still loads (injection is optional).
        const stateless = host.activate("io.github.fixture.stateless");
        assert(stateless !== null, "an app without the contract still loads");

        host.destroy();
        bus.destroy();
        state.destroy();
        console.log("PASS: All app host injection tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
