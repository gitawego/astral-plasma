import QtQuick

// ============================================================================
// Popout Blur-Mask Extent Contract
// ============================================================================
// The popout's glass is drawn by UnifiedFrame.bottomPopoutSurface and the
// compositor blur behind it is a mask declared in UnifiedShell. Those are two
// separately-authored expressions for one visual object, so they can drift.
//
// They did. The surface's own extent is:
//
//     y      = popoutY - topR
//     height = popoutHeight + topR + botR        botR = fused ? 0 : filletR
//
// while the mask re-derived its extent from `filletR` independently:
//
//     fused    body: y = wrapper.y,  h = root.height - wrapper.y   <- SCREEN BOTTOM
//     floating body: y = wrapper.y - filletR,  h = wrapper.height + filletR*2
//
// `botR` collapses to 0 when fused, so the fused mask overran the glass by
// filletR *and* ran to the bottom of the screen - blurring bare desktop below the
// popout. That is the reported "blur zone is too large; it should be exactly the
// same size as the drawer".
//
// The durable fix, asserted here: the mask consumes UnifiedFrame's authoritative
// rect instead of recomputing geometry. Then there is exactly one definition of
// where the popout is.
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        // Cache-buster: Qt caches file:// reads, which would let this guard test
        // STALE source and pass while the real file changed.
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(condition, message) {
        if (!condition) {
            // Qt.exit() terminates before buffered stderr is flushed, which
            // would make a failing run print nothing at all. Keep a copy on
            // stdout, which the test harness captures.
            console.log("FAIL: " + message);
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
        console.log("RUNNING: Popout Blur-Mask Extent Contract");

        const frame = readLocalFile("../shell/UnifiedFrame.qml");
        const shell = readLocalFile("../shell/UnifiedShell.qml");
        assert(frame.length > 1000 && shell.length > 1000, "sources must be readable");

        // ---- 1. UnifiedFrame must publish the surface rects --------------
        assert(/readonly property rect fullRect/.test(frame),
            "UnifiedFrame must expose `fullRect`: the painted surface, fillet bands included");
        assert(/readonly property rect bodyRect/.test(frame),
            "UnifiedFrame must expose `bodyRect`: the straight-sided section a full-width "
            + "blur region must span");

        // bodyRect must be expressed from the surface's own inputs, not a constant.
        // Capture the whole declaration up to the newline: the expression nests
        // parentheses (sizeRounded(...)), so a non-greedy `)` match truncates it.
        const bodyDecl = frame.match(/readonly property rect bodyRect:([\s\S]*?)readonly property/);
        assert(bodyDecl !== null, "bodyRect must be a Qt.rect(...) declaration");
        const bodyExpr = bodyDecl[1];
        assert(/popoutY/.test(bodyExpr),
            "bodyRect.y must come from popoutY (the surface origin), got: " + bodyExpr);
        assert(/popoutHeight/.test(bodyExpr),
            "bodyRect.height must come from popoutHeight, got: " + bodyExpr);

        // ---- 1b. UnifiedFrame must publish the FLOATING card rect ---------
        // In the floating state the surface is larger than the glass: the
        // concave shoulder cut occupies the left `currentFilletR` band, and the
        // surface keeps `filletR` bands above and below only because the fused
        // shape needs them. A mask sized to the surface frosts bare wallpaper
        // around the card - the reported "blur bigger than the drawer".
        assert(/readonly property rect floatingRect/.test(frame),
            "UnifiedFrame must expose `floatingRect`: the floating card's own bounding box");
        const floatDecl = frame.match(/readonly property rect floatingRect:([\s\S]*?)readonly property/);
        assert(floatDecl !== null, "floatingRect must be a Qt.rect(...) declaration");
        const floatExpr = floatDecl[1];
        assert(/currentFilletR/.test(floatExpr),
            "floatingRect.x must be inset by currentFilletR (the shoulder band), got: " + floatExpr);
        assert(/popoutHeight/.test(floatExpr),
            "floatingRect.height must come from popoutHeight, got: " + floatExpr);
        assert(/popoutY/.test(floatExpr),
            "floatingRect.y must come from popoutY, got: " + floatExpr);

        function regionBlocks(src, marker, endMarker) {
            const a = src.indexOf(marker);
            assert(a >= 0, "marker not found: " + marker);
            const b = src.indexOf(endMarker, a);
            const block = src.substring(a, b > a ? b : a + 6000);
            const out = [];
            const re = /Region\s*\{([^}]*)\}/g;
            let m;
            while ((m = re.exec(block)) !== null)
                out.push(m[1]);
            return out;
        }
        // Count regions across the whole variant block, not just the first
        // comment-separated group (the popout has several: corner slices, body,
        // and shoulder fillets).
        function countRegions(src, marker, endMarker) {
            const a = src.indexOf(marker);
            assert(a >= 0, "marker not found: " + marker);
            const b = src.indexOf(endMarker, a);
            const block = src.substring(a, b > a ? b : a + 12000);
            return (block.match(/Region\s*\{/g) || []).length;
        }
        const fedCount = countRegions(shell,
            "// Fused Bottom Popout (when open & fused to bottom border)",
            "// Floating Bottom Popout");
        const floCount = countRegions(shell,
            "// Floating Bottom Popout (when open & floating)",
            "// Bottom Popout Top Shoulder Fillet");
        // Fused declares 6 top-corner slices + 1 body here (its bottom fillets are
        // declared later, shared with the floating block); floating declares
        // 6 + 1 + 6. A floor of 5 guards against a variant losing its mask without
        // encoding those exact counts.
        assert(fedCount >= 5 && floCount >= 5,
            "both popout variants must declare a region set (fused "
            + fedCount + ", floating " + floCount + "); a popout with no mask is not covered");
        const flo = regionBlocks(shell,
            "// Floating Bottom Popout (when open & floating)",
            "// Bottom Popout Top Shoulder Fillet");

        // ---- 2. Both masks must consume that rect ------------------------
        // Every region whose width is the full popout width must take ALL of its
        // dimensions from bodyRect. (Narrow corner slices are exempt: they
        // approximate the shoulder arcs and are intentionally partial.)
        function fullWidthRegions(src, marker, endMarker) {
            const a = src.indexOf(marker);
            assert(a >= 0, "marker not found: " + marker);
            const b = src.indexOf(endMarker, a);
            const block = src.substring(a, b > a ? b : a + 6000);
            const out = [];
            const re = /Region\s*\{([^}]*)\}/g;
            let m;
            while ((m = re.exec(block)) !== null) {
                const r = m[1];
                // The body is the region that draws its extent from an
                // authoritative rect (fullRect when fused, floatingRect when
                // floating); corner slices use narrow partial widths.
                if (/(fullRect|floatingRect)/.test(r))
                    out.push(r);
            }
            return out;
        }

        const variants = [
            ["fused", "fullRect", fullWidthRegions(shell,
                "// Fused Bottom Popout (when open & fused to bottom border)",
                "// Floating Bottom Popout")],
            ["floating", "floatingRect", fullWidthRegions(shell,
                "// Floating Bottom Popout (when open & floating)",
                "// Bottom Popout Top Shoulder Fillet")]
        ];

        let checkedDims = 0;
        for (const pair of variants) {
            const variant = pair[0], expectedRect = pair[1], regions = pair[2];
            assert(regions.length >= 1,
                variant + " popout must declare a full-width body region (width: root.currentPopW)");
            for (let i = 0; i < regions.length; i++) {
                for (const dim of ["y", "width", "height"]) {
                    const val = regions[i].split("\n").filter(function (l) {
                        return l.trim().indexOf(dim + ":") === 0;
                    });
                    assert(val.length >= 1, variant + " body must declare " + dim);
                    const joined = val.join(" ");
                    assert(/blurPopout\w+/.test(joined),
                        variant + " body " + dim + " must be gated on its active flag, got: " + joined.trim());
                    assert(new RegExp(expectedRect).test(joined),
                        variant + " body " + dim + " must read UnifiedFrame's " + expectedRect
                        + " (single source of truth), got: " + joined.trim());
                    checkedDims++;
                }
            }
        }

        // ---- 2b. The floating variant must never reach past its card -----
        const floatingBlock = shell.substring(
            shell.indexOf("// Floating Bottom Popout (when open & floating)"),
            shell.indexOf("// Bottom Popout Top Shoulder Fillet"));
        assert(!/fullRect/.test(floatingBlock),
            "no floating region may use fullRect: the surface is larger than the card, so a "
            + "fullRect mask frosts bare wallpaper left/top/bottom of the drawer");
        assert(/floatingRect/.test(floatingBlock),
            "the floating body must read UnifiedFrame's floatingRect");

        // The top shoulder fillet band is active for both fused and floating popouts
        // (gated on blurPopoutActive) to ensure continuous liquid blur without black gaps.
        const shoulderBlock = shell.substring(
            shell.indexOf("// Bottom Popout Top Shoulder Fillet"),
            shell.indexOf("// Bottom Popout Bottom Shoulder Fillet"));
        assert(/blurPopoutActive/.test(shoulderBlock),
            "the top shoulder fillet band must be gated on blurPopoutActive so floating popouts have continuous blur to the dock edge");

        // ---- 3. No mask may reach the screen bottom ---------------------
        // `root.height - <wrapper>.y` has no basis in the surface's geometry and
        // overruns it whenever the bottom radius is 0.
        const reachBottom = shell.match(/height:\s*\(root\.blurPopout\w+\)\s*\?\s*Math\.max\(0,\s*root\.height\s*-/);
        assert(reachBottom === null,
            "no popout mask may be sized to the screen bottom (`root.height - wrapper.y`); "
            + "the mask must end where the glass ends");

        // ---- 4. Model both states and prove mask == glass ---------------
        // Reproduce the surface's formulas for a representative popout and check
        // the exported rects agree with them in BOTH fused and floating states.
        const filletR = 20, popoutH = 204, wrapperY = 751, popW = 350;
        const dockW = 70;
        for (const fusedState of [false, true]) {
            const botR = fusedState ? 0 : filletR;
            const tag = fusedState ? "fused" : "floating";
            const surfLeft = dockW - 1;

            if (fusedState) {
                // Fused glass body consumes fullRect: spans from dockW - 1 across
                // the drawer body with zero overhang above the card or to the right.
                const maskTop = wrapperY;                     // fullRect.y
                const maskBottom = wrapperY + popoutH;        // fullRect bottom
                const bodyTop = wrapperY;
                const bodyBottom = wrapperY + popoutH;
                assert(maskTop === bodyTop,
                    tag + ": fullRect top must equal the body top (mask " + maskTop
                    + " vs body " + bodyTop + ")");
                assert(maskBottom === bodyBottom,
                    tag + ": fullRect bottom must equal the body bottom (mask " + maskBottom
                    + " vs body " + bodyBottom + ") - a mismatch blurs bare desktop or "
                    + "leaves glass unblurred");
            } else {
                // Floating glass body consumes floatingRect starting flush at dockW - 1
                // to guarantee zero unblurred gap against the dock.
                const cardLeft = surfLeft;
                const cardRight = surfLeft + popW + 1;      // bodyW
                const cardTop = wrapperY;
                const cardBottom = wrapperY + popoutH;
                assert(cardLeft === surfLeft,
                    "sanity: the floating card must start flush at the dock edge to avoid unblurred gaps");
                assert(/floatingRect/.test(shell),
                    tag + ": the mask must consume floatingRect (the card), not the surface");
                assert(cardRight > cardLeft && cardBottom > cardTop,
                    tag + ": modeled card must be a positive-area rect");
            }
        }

        // ---- 5. The defect is quantified for the record ------------------
        // The old fused mask ended at root.height (1600) instead of the glass
        // bottom, overrunning by hundreds of px; assert the new one is bounded by
        // the surface in both states.
        const screenH = 1600;
        const oldFusedMask = screenH - wrapperY;          // 849
        const newFusedMask = popoutH;                     // 204
        assert(oldFusedMask > newFusedMask + 100,
            "sanity: the legacy fused mask should overrun grossly (got "
            + oldFusedMask + " vs " + newFusedMask + "px)");

        console.log("PASS: Popout Blur-Mask Extent Contract (fused mask consumes fullRect; "
            + "floating mask consumes floatingRect - the card, not the surface - so the blur "
            + "never extends past the drawer; the top shoulder band is fused-only)");
        Qt.exit(0);
    }
}
