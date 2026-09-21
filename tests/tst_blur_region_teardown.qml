import QtQuick

// ============================================================================
// Blur Region Teardown Contract
// ============================================================================
// The compositor blur behind the shell's drawers is driven by
// BackgroundEffect.blurRegion, whose geometry follows the open/close animation.
// The compositor keeps applying the LAST region it was handed, so a region that
// collapses through a partially-zero (degenerate) state on the animation's final
// frame can stay on screen until some unrelated repaint commits the clear. That
// is what makes a closed drawer leave its blur behind for up to a second.
//
// Two invariants prevent it, both asserted here against the real source:
//
//   A. ATOMIC DIMENSIONS - every dropdown region dimension is gated by ONE
//      boolean, so the region is either a valid positive-area rectangle or
//      completely empty. It must never pass through 980x0.
//   B. EARLY TEARDOWN      - that boolean clears while the close animation still
//      has frames left, so the compositor has time to flush the clear.
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

    function runTests() {
        console.log("RUNNING: Blur Region Teardown Contract");

        const src = readLocalFile("../shell/UnifiedShell.qml");
        assert(src.length > 1000, "UnifiedShell.qml must be readable by the harness");

        // Isolate the blurRegion block.
        const start = src.indexOf("BackgroundEffect.blurRegion");
        assert(start >= 0, "UnifiedShell must declare BackgroundEffect.blurRegion");
        const endMarker = src.indexOf("// Configuration and Tokens", start);
        assert(endMarker > start, "could not delimit the blurRegion block");
        const block = src.substring(start, endMarker);

        // ---- A. one gate, no per-dimension progress tests -----------------
        // Every dropdown-driven dimension must key off the single gate property.
        const activeGate = (block.match(/root\.blurRegionActive/g) || []).length;
        assert(activeGate > 0,
            "the blur region must be gated by root.blurRegionActive so all its dimensions switch atomically");

        // The buggy pattern: dimensions compared directly against a tiny
        // progress epsilon, which zeroes width and height at DIFFERENT offsets.
        const rawEps = (block.match(/dropdownContainer\.offsetProgress\s*>\s*0\.001/g) || []).length;
        assert(rawEps === 0,
            "blur regions must not compare offsetProgress against 0.001 directly - width and height then "
            + "collapse at different offsets and the region passes through a degenerate state. Found "
            + rawEps + " such comparison(s)");

        // Any residual per-dimension epsilon is also a hazard.
        const anyEps = (block.match(/offsetProgress\s*>\s*0\.0*[0-9]+/g) || []).length;
        assert(anyEps === 0,
            "no dropdown blur dimension may test offsetProgress against an epsilon directly; use root.blurRegionActive. Found "
            + anyEps + " occurrence(s)");

        // ---- A2. the body height must be clamped, not merely epsilon-gated --
        // The clamp lives in the blurDropH declaration (root scope), so assert on
        // the whole file rather than the region block.
        assert(/blurDropH\s*:[\s\S]{0,120}Math\.max\(\s*1\s*,/.test(src),
            "blurDropH must have a positive floor (Math.max(1, ...)) so the active region always has "
            + "positive area and never degenerates to a zero-height strip");
        assert(block.indexOf("root.blurDropH") >= 0,
            "the blur body height must be routed through root.blurDropH");

        // ---- B. teardown must begin while frames remain -------------------
        const minMatch = src.match(/blurRegionMinProgress\s*:\s*([0-9.]+)/);
        assert(minMatch !== null,
            "UnifiedShell must expose `blurRegionMinProgress` so the teardown lead time stays explicit");
        const minProgress = parseFloat(minMatch[1]);
        assert(minProgress > 0.0,
            "blurRegionMinProgress must be > 0 so the region clears before the animation ends");
        // The close behaviour animates offsetProgress 1 -> 0 over ~500ms
        // (Theme.animExpressiveDefaultSpatial). Clearing at `minProgress` leaves
        // minProgress * 500ms of frames to flush the region clear.
        const animationMs = 500;
        const leadMs = minProgress * animationMs;
        assert(leadMs >= 20,
            "teardown must begin at least 20ms before the animation ends so the compositor can flush the "
            + "region clear; blurRegionMinProgress=" + minProgress + " gives only "
            + leadMs.toFixed(0) + "ms of lead time");

        // ---- C. gate is declared at root scope ----------------------------
        // It is referenced as root.blurRegionActive from inside the Region tree,
        // so it must live on the PanelWindow root, not inside the Region.
        assert(/readonly property bool blurRegionActive/.test(src),
            "blurRegionActive must be declared as a root-level property");
        const decl = src.indexOf("readonly property bool blurRegionActive");
        const rootScope = src.lastIndexOf("\n    readonly property", decl);
        assert(rootScope > 0 && (decl - rootScope) < 200,
            "blurRegionActive must be declared at four-space indent (root scope), not nested inside the Region");

        // ---- D. description of the failure is documented -------------------
        assert(/keeps applying the LAST region|LAST region it received|last region/i.test(block)
               || /keeps applying the LAST region/i.test(src),
            "the region-teardown hazard must be documented next to the gate so it is not reintroduced");

        console.log("PASS: Blur Region Teardown Contract (atomic gate, "
            + activeGate + " gated dimensions, "
            + leadMs.toFixed(0) + "ms teardown lead)");
        Qt.exit(0);
    }
}
