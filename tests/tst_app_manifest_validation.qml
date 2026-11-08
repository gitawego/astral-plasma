import QtQuick
import "../modules/Astral/Kernel/Host/AppManifest.js" as Manifest

// ============================================================================
// Manifest validation at load time
// ============================================================================
// Rust validates at install; the shell re-validates at load, because a payload can
// be edited after install and the host must never resolve an import it cannot
// satisfy.
//
// The fixtures and their expected verdicts are shared with
// `daemon/tests/test_app_manifest_fixtures.rs`, which feeds the same files through
// the Rust validator. Two implementations, one contract: if either drifts, one of
// the two suites fails.
Item {
    id: testRoot
    width: 600
    height: 400

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function parse(text) {
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    function run() {
        const cases = parse(readLocalFile("fixtures/apps/index.json"));
        assert(Array.isArray(cases) && cases.length > 0, "the fixture index must list cases");

        for (let index = 0; index < cases.length; index++) {
            const name = cases[index];
            const expect = parse(readLocalFile("fixtures/apps/" + name + "/expect.json"));
            assert(expect !== null, name + ": expect.json must parse");

            const raw = readLocalFile("fixtures/apps/" + name + "/manifest.json");
            const manifest = parse(raw);
            const verdict = Manifest.validate(manifest);

            assert(verdict.ok === expect.load,
                name + ": expected load=" + expect.load + ", got " + verdict.ok
                    + " (" + verdict.reason + ")");
            if (!expect.load) {
                assert(verdict.reason.indexOf(expect.reason) >= 0,
                    name + ": reason must mention '" + expect.reason + "', got '" + verdict.reason + "'");
            }
        }

        // A missing manifest is the same refusal as an unparsable one.
        const absent = Manifest.validate(null);
        assert(!absent.ok && absent.reason.indexOf("not an object") >= 0,
            "a missing manifest is refused");

        // Nothing here may throw, whatever the input shape.
        [null, undefined, 42, "text", [], { id: null }].forEach(function (value) {
            const verdict = Manifest.validate(value);
            assert(!verdict.ok, "arbitrary input must be refused, not thrown on");
        });

        // The id rule is the same one the installer enforces.
        assert(Manifest.isAppId("io.github.alice.clock"), "reverse-DNS ids are accepted");
        assert(!Manifest.isAppId("Clock"), "upper case is refused");
        assert(!Manifest.isAppId("clock"), "a single segment is refused");

        console.log("PASS: All manifest validation tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
