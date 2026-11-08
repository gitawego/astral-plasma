import QtQuick
import "../modules/Astral/Kernel/Host"

// ============================================================================
// IntentBus
// ============================================================================
// A migrated surface cannot call `Config.*` (it gets a stale singleton), so every
// action it takes is a named intent. What is asserted here is the contract the
// callers rely on: unknown intents are `unsupported` rather than silent, a thrown
// handler is `invalid` rather than fatal, and results are always result objects.
Item {
    id: testRoot
    width: 400
    height: 300

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    property int calls: 0
    property var failed: []

    function run() {
        const bus = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/Host"; IntentBus { }',
            testRoot, "intentbus");
        bus.intentFailed.connect(function (name, reason) { failed.push({ name: name, reason: reason }); });

        // ---- unsupported is a first-class answer -----------------------------
        const missing = bus.request("downloads.open");
        assert(missing.status === "unsupported", "an unhandled intent is unsupported");
        assert(missing.reason.indexOf("downloads.open") >= 0, "the reason names the intent");

        // ---- registration and dispatch ---------------------------------------
        let received = null;
        assert(bus.register("overview.close", function (args) {
            received = args;
            return bus.applied("closed");
        }), "register accepts a function");
        assert(bus.has("overview.close"), "the intent is now known");
        assert(bus.list().indexOf("overview.close") >= 0, "list() reports registered intents");

        const ok = bus.request("overview.close", { reason: "escape" });
        assert(ok.status === "applied", "a handled intent is applied");
        assert(ok.value === "closed", "the handler's value is passed through");
        assert(received.reason === "escape", "arguments reach the handler");

        // ---- a handler that throws is contained ------------------------------
        bus.register("boom", function () { throw new Error("exploded"); });
        const boom = bus.request("boom");
        assert(boom.status === "invalid", "a throwing handler is invalid, not fatal");
        assert(boom.reason.indexOf("exploded") >= 0, "the reason carries the error");
        assert(failed.some(function (item) { return item.name === "boom"; }),
            "a throwing handler is reported through intentFailed");

        // ---- a handler that returns nothing is a wiring bug -------------------
        bus.register("nothing", function () { return undefined; });
        const nothing = bus.request("nothing");
        assert(nothing.status === "invalid", "a handler must return an ActionResult");
        assert(nothing.reason.indexOf("nothing") >= 0, "the reason names the intent");

        // ---- denied passes through, and is reported --------------------------
        bus.register("permission", function () { return bus.denied("no network grant"); });
        const denied = bus.request("permission");
        assert(denied.status === "denied" && denied.reason === "no network grant",
            "a denial is preserved verbatim");

        // ---- pending carries a token -----------------------------------------
        bus.register("install", function () { return bus.pending("tok-1"); });
        assert(bus.request("install").token === "tok-1", "pending carries its token");

        // ---- registration hygiene --------------------------------------------
        assert(!bus.register("", function () { return bus.applied(); }),
            "an empty name is refused");
        assert(!bus.register("bad", "not a function"), "a non-function is refused");
        assert(bus.unregister("overview.close"), "unregister removes the handler");
        assert(!bus.has("overview.close"), "the intent is gone");
        assert(bus.request("overview.close").status === "unsupported",
            "an unregistered intent is unsupported again");
        assert(!bus.unregister("overview.close"), "unregistering twice reports false");

        // ---- malformed requests ----------------------------------------------
        assert(bus.request("").status === "invalid", "an empty name is invalid");
        assert(bus.request(null).status === "invalid", "a null name is invalid");

        bus.destroy();
        console.log("PASS: All intent bus tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
