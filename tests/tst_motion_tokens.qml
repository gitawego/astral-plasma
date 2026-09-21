import QtQuick

// ============================================================================
// Motion Token Contract: Theme.qml must match DESIGN.md
// ============================================================================
// DESIGN.md section 2.1 is the authoritative motion spec, and it declares
// theme/Theme.qml as its formalization. AGENTS.md forbids hardcoded durations,
// so every spatial transition in the shell reads these tokens.
//
// This suite parses the token table out of DESIGN.md and the declarations out of
// Theme.qml, then asserts they agree. It exists because a temporary diagnostic
// slowdown (changing animExpressiveDefaultSpatial to 4000ms to make a transition
// easy to screenshot) was left in the tree: it made the drawer morph 8x too slow
// and read as a mechanical box expanding rather than a fluid fused transition.
// Nothing caught it, because nothing tied the token back to its documentation.
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        // Cache-buster: Qt caches file:// reads, so a guard can silently test
        // STALE source and pass while the real file has changed. Appending a
        // unique query forces a fresh read. (CACHEBUST)
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

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    // Parse DESIGN.md's token table: | **`token`** | 500ms | `[a, b, c, d, e, f]` | ... |
    function parseDesignTokens(md) {
        const out = {};
        const re = /^\|\s*\*\*`([A-Za-z0-9_]+)`\*\*\s*\|\s*(\d+)ms\s*\|\s*`\[([^\]]+)\]`/gm;
        let m;
        while ((m = re.exec(md)) !== null) {
            out[m[1]] = {
                duration: parseInt(m[2], 10),
                bezier: m[3].split(',').map(function (s) { return parseFloat(s.trim()); })
            };
        }
        return out;
    }

    // Parse Theme.qml's `readonly property <int|var> <token>: <value>` lines.
    function parseThemeTokens(qml) {
        const out = {};
        const re = /readonly property (?:int|var|real|double)\s+([A-Za-z0-9_]+)\s*:\s*([^\n]+)/g;
        let m;
        while ((m = re.exec(qml)) !== null) {
            const name = m[1];
            const raw = m[2].trim();
            const arr = raw.match(/^\[([^\]]+)\]/);
            if (arr) {
                out[name] = {
                    bezier: arr[1].split(',').map(function (s) { return parseFloat(s.trim()); })
                };
            } else if (/^-?\d+$/.test(raw)) {
                out[name] = { duration: parseInt(raw, 10) };
            }
        }
        return out;
    }

    function runTests() {
        console.log("RUNNING: Motion Token Contract (DESIGN.md <-> Theme.qml)");

        const design = readLocalFile("../DESIGN.md");
        const theme = readLocalFile("../theme/Theme.qml");
        assert(design.length > 500, "DESIGN.md must be readable");
        assert(theme.length > 500, "theme/Theme.qml must be readable");

        const spec = parseDesignTokens(design);
        const actual = parseThemeTokens(theme);

        const names = Object.keys(spec);
        assert(names.length >= 6,
            "DESIGN.md must document the motion token palette, found " + names.length + " tokens");

        let checked = 0;

        // DESIGN.md lists a duration and a curve on the same row. Theme.qml's
        // naming does not pair them by a single rule (`animEmphasized` /
        // `curveEmphasizedDecel`; `animExpressiveDefaultSpatial` /
        // `curveExpressiveDefaultSpatial`), so validate by CONTENT:
        //
        //   * every documented duration must appear as an integer token in
        //     Theme.qml (matched by the documented value, since the doc names the
        //     motion and Theme may name it slightly differently);
        //   * every documented curve must appear as a bezier token, matched by the
        //     documented control values.
        //
        // That keeps the guard robust to naming while still failing loudly if a
        // token is edited away from its documentation.
        const themeDurations = [];
        const themeBeziers = [];
        for (const k in actual) {
            if (actual[k].duration !== undefined) themeDurations.push({ name: k, value: actual[k].duration });
            if (actual[k].bezier !== undefined) themeBeziers.push({ name: k, bezier: actual[k].bezier });
        }

        for (let i = 0; i < names.length; i++) {
            const name = names[i];
            const want = spec[name];

            // ---- Duration: must exist with the documented value -----------
            const dur = themeDurations.filter(function (d) { return d.value === want.duration; });
            assert(dur.length > 0,
                "DESIGN.md documents a " + want.duration + "ms token (`" + name
                + "`) but no duration token in Theme.qml has that value");

            // Specific tokens that must exist by name, because the shell's
            // spatial transitions depend on them.
            if (name.indexOf("animExpressive") === 0) {
                const exact = actual[name];
                assert(exact !== undefined && exact.duration !== undefined,
                    "Theme.qml must declare `" + name + "` (used by the shell's transitions)");
                assert(exact.duration === want.duration,
                    "`" + name + "` duration must match DESIGN.md: documented " + want.duration
                    + "ms, Theme.qml has " + exact.duration + "ms. A slowed token makes every "
                    + "transition using it look mechanical instead of fluid.");
            }
            checked++;

            // ---- Curve: must exist with the documented control values -----
            const match = themeBeziers.filter(function (b) {
                for (let k = 0; k < 6; k++)
                    if (Math.abs(b.bezier[k] - want.bezier[k]) > 1e-6) return false;
                return true;
            });
            assert(match.length > 0,
                "DESIGN.md documents a curve [" + want.bezier.join(", ") + "] for `" + name
                + "` but no bezier token in Theme.qml matches those control values");
            checked++;
        }

        // The two curves the spatial tokens are REQUIRED to use, by name.
        for (const pair of [["animExpressiveDefaultSpatial", "curveExpressiveDefaultSpatial"],
                            ["animExpressiveFastSpatial", "curveExpressiveFastSpatial"],
                            ["animExpressiveSlowSpatial", "curveExpressiveSlowSpatial"]]) {
            assert(actual[pair[0]] !== undefined && actual[pair[1]] !== undefined
                   && actual[pair[1]].bezier !== undefined,
                "Theme.qml must declare both `" + pair[0] + "` and its curve `" + pair[1] + "`");
            assert(actual[pair[1]].bezier.length === 6,
                "`" + pair[1] + "` must be a 6-value bezier");
            checked++;
        }

        // ---- The specific token this guard exists for --------------------
        // Spatial transitions must stay in the documented spring range. A value
        // far outside it is a leftover diagnostic, not a design change.
        const spatial = ["animExpressiveFastSpatial", "animExpressiveDefaultSpatial",
                         "animExpressiveSlowSpatial"];
        for (let i = 0; i < spatial.length; i++) {
            const t = actual[spatial[i]];
            assert(t !== undefined && t.duration !== undefined,
                spatial[i] + " must exist in Theme.qml");
            assert(t.duration >= 150 && t.duration <= 800,
                spatial[i] + " = " + t.duration + "ms is outside the documented spring range "
                + "(150-800ms). Spatial transitions in this range are what make the shell feel "
                + "fluid; a much larger value reads as a mechanical expansion.");
        }

        console.log("PASS: Motion Token Contract (" + names.length + " tokens, "
            + checked + " properties matched against DESIGN.md; spatial durations in range)");
        Qt.exit(0);
    }
}
