import QtQuick

// ============================================================================
// Fillet Blur-Mask Coverage Contract
// ============================================================================
// The compositor can only blur axis-aligned rectangles, so each concave screen
// fillet's arc is approximated by stacked slices. The mask MUST cover the fillet's
// glass: the glass is translucent (alpha ~0.65), so any glass the mask misses
// shows the wallpaper through it unblurred, which renders as a stepped, jagged
// corner - the "border radius is not smooth" defect.
//
// The original profile used hand-tuned widths 12/7/4/2/1, each sized for its
// slice's BOTTOM depth. Because the arc widens steeply toward the tangency, the
// TOP of every slice was left uncovered by up to 8px.
//
// This suite recomputes the arc geometry and asserts that the mask produced by
// the shell's own profile covers the glass at every sampled depth, for a range of
// configured radii.
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

    // Glass width required at depth d for a concave fillet of radius R whose arc
    // is tangent to the two inner edges (circle centre at (R, R) in local space).
    function glassWidth(R, d) {
        const dist = Math.max(0, R - d);
        const inner = Math.max(0, R * R - dist * dist);
        return Math.max(0, R - Math.sqrt(inner));
    }

    // Read the depth fractions the shell actually uses, so editing the source is
    // what this test exercises (mirroring the formula would let a bad edit pass).
    function parseDepths(src) {
        const m = src.match(/const depths = \[([^\]]+)\]/);
        assert(m !== null, "UnifiedShell must declare the fillet depth fractions");
        const raw = m[1].split(",").map(function (t) {
            const v = t.trim();
            return v === "R" ? "R" : parseFloat(v);
        });
        return raw;
    }

    // Build the profile exactly as UnifiedShell does, from the parsed depths.
    function profileFrom(depthsRaw, R) {
        const depths = depthsRaw.map(function (d) { return d === "R" ? R : d; });
        const widths = [];
        const heights = [];
        for (let i = 0; i < depths.length - 1; i++) {
            const dist = Math.max(0, R - depths[i]);
            const w = R - Math.sqrt(Math.max(0, R * R - dist * dist));
            widths.push(Math.max(1, Math.min(R, Math.ceil(w))));
            heights.push(depths[i + 1] - depths[i]);
        }
        return { depths: depths, widths: widths, heights: heights };
    }

    // Mask coverage at depth d: the widest slice that spans d. Slices are stacked
    // from depth 0 downward, so the mask width at d is the width of the slice
    // containing d.
    function maskWidthAt(profile, d) {
        let y = 0;
        for (let i = 0; i < profile.heights.length; i++) {
            const top = y;
            const bottom = y + profile.heights[i];
            if (d >= top && d <= bottom)
                return profile.widths[i];
            y = bottom;
        }
        return 0;
    }

    function runTests() {
        console.log("RUNNING: Fillet Blur-Mask Coverage Contract");

        const src = readLocalFile("../shell/UnifiedShell.qml");
        assert(src.length > 1000, "UnifiedShell.qml must be readable");

        const depthsRaw = parseDepths(src);
        assert(depthsRaw.length === 8,
            "the fillet depth fractions must yield 7 slices (8 boundaries), found "
            + depthsRaw.length + " boundaries");
        // Must start at the tangency and end at the radius.
        assert(depthsRaw[0] === 0, "the profile must start at depth 0");
        assert(depthsRaw[depthsRaw.length - 1] === "R",
            "the profile must end at the full radius");
        // Strictly increasing, and FINE near the tangency: the arc widens fastest
        // there, so a coarse first step is exactly the original defect.
        const numeric = depthsRaw.map(function (d) { return d === "R" ? 20 : d; });
        for (let i = 1; i < numeric.length; i++) {
            assert(numeric[i] > numeric[i - 1],
                "depth fractions must strictly increase at index " + i);
        }
        assert(numeric[1] <= 1,
            "the first depth step must be <= 1px (the arc widens fastest at the tangency); "
            + "a coarse first step is the original stepped-corner defect, got " + numeric[1]);
        assert(numeric[2] <= 3,
            "the second depth step must be fine (<= 3px), got " + numeric[2]);

        // ---- 1. The profile must be derived, not hand-tuned ----------------
        assert(src.indexOf("filletProfile") >= 0,
            "the screen-fillet blur mask must use a computed `filletProfile`, not hand-tuned widths");
        assert(!/Screen Inner Fillet: Top-Left[\s\S]{0,400}?width:\s*12/.test(src),
            "the top-left fillet must not use the old hardcoded width 12");

        // ---- 2. Every corner must use the profile for all slices ----------
        for (const corner of ["Top-Left", "Top-Right", "Bottom-Left", "Bottom-Right"]) {
            const at = src.indexOf("Screen Inner Fillet: " + corner);
            assert(at >= 0, corner + " region block must exist");
            // Delimit the block by the next standalone comment line (the next
            // region group), not a character guess.
            const rest = src.substring(at);
            const nextComment = rest.search(/\n\s*\/\/[^\n]*\n\s*Region/);
            const block = nextComment > 0 ? rest.substring(0, nextComment) : rest;
            // Count DISTINCT slice indices: a corner may reference widths[i]
            // more than once (once for x, once for width on the right corners).
            const idx = new Set();
            const re = /filletProfile\.widths\[(\d+)\]/g;
            let m;
            while ((m = re.exec(block)) !== null)
                idx.add(parseInt(m[1], 10));
            assert(idx.size === 7,
                corner + " must reference filletProfile.widths for all 7 slices, found "
                + idx.size + " distinct indices");
        }

        // ---- 3. Coverage: the mask must cover the glass at every depth ----
        // Test the configured radius plus a spread, so a radius change cannot
        // silently reintroduce under-coverage.
        for (const R of [12, 16, 20, 24, 28, 32]) {
            const profile = profileFrom(depthsRaw, R);
            let worstGap = 0;
            let worstDepth = 0;
            for (let d = 0; d <= R; d += 0.25) {
                const need = glassWidth(R, d);
                const have = maskWidthAt(profile, d);
                const gap = need - have;
                if (gap > worstGap) {
                    worstGap = gap;
                    worstDepth = d;
                }
            }
            assert(worstGap <= 0.5,
                "R=" + R + ": blur mask must cover the fillet glass at every depth; "
                + "worst gap " + worstGap.toFixed(2) + "px at depth " + worstDepth.toFixed(2)
                + " (unblurred glass shows the wallpaper and renders as a stepped corner)");
        }

        // ---- 4. The mask must not balloon far beyond the glass ------------
        // Mild outward bleed is expected and feathered by the blur kernel, but a
        // slice that overshoots grossly would blur unrelated wallpaper.
        for (const R of [16, 20, 24, 32]) {
            const profile = profileFrom(depthsRaw, R);
            let worstOver = 0;
            for (let i = 0; i < profile.heights.length; i++) {
                const bottomDepth = profile.depths[i + 1];
                const needAtBottom = glassWidth(R, bottomDepth);
                worstOver = Math.max(worstOver, profile.widths[i] - needAtBottom);
            }
            assert(worstOver <= R * 0.55,
                "R=" + R + ": slice overshoot of " + worstOver.toFixed(1)
                + "px is excessive; refine the depth fractions");
        }

        // ---- 5. Regression witness ---------------------------------------
        // The old profile's first slice was 12px where 20px was required.
        const legacy = { depths: [0, 2, 5, 9, 14, 20], widths: [12, 7, 4, 2, 1], heights: [2, 3, 4, 5, 6] };
        const legacyGap = glassWidth(20, 0) - maskWidthAt(legacy, 0);
        assert(legacyGap > 5,
            "sanity: the legacy profile should exhibit a large gap (got " + legacyGap.toFixed(1) + "px)");

        const fixed = profileFrom(depthsRaw, 20);
        const fixedWorst = (() => {
            let w = 0;
            for (let d = 0; d <= 20; d += 0.25)
                w = Math.max(w, glassWidth(20, d) - maskWidthAt(fixed, d));
            return w;
        })();
        assert(fixedWorst <= 0.5,
            "the derived profile must close the coverage gap (got " + fixedWorst.toFixed(2) + "px)");

        // ---- 6. The radius actually configured must be covered ------------
        const cfg = readLocalFile("../config/settings.json");
        const rm = cfg.match(/"rounding"\s*:\s*(\d+)/);
        if (rm !== null) {
            const Rc = parseInt(rm[1], 10);
            const pc = profileFrom(depthsRaw, Rc);
            let wc = 0;
            for (let d = 0; d <= Rc; d += 0.25)
                wc = Math.max(wc, glassWidth(Rc, d) - maskWidthAt(pc, d));
            assert(wc <= 0.5,
                "the configured border rounding R=" + Rc + " must be fully covered by the blur mask; "
                + "worst gap " + wc.toFixed(2) + "px");
        }

        console.log("PASS: Fillet Blur-Mask Coverage Contract (4 corners x 7 slices, "
            + "full glass coverage for R=12..32; legacy gap was "
            + legacyGap.toFixed(1) + "px, now " + fixedWorst.toFixed(2) + "px)");
        Qt.exit(0);
    }
}
