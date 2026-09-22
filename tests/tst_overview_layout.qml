import QtQuick
import "../components"

// Active-apps overview grid math contract.
//
// Uniform cells, width-driven column count, vertical shrink with a scroll
// floor: the grid must fit the available area whenever minCellH rows fit, and
// must never overflow horizontally (Flickable handles vertical overflow).
Item {
    id: testRoot
    width: 400
    height: 300

    OverviewLayout {
        id: layout
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    readonly property var opts: ({
        gap: 16,
        minCellW: 170,
        maxCellW: 440,
        minCellH: 110,
        cardAspect: 1.5
    })

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            // Halt: falling through to the final Qt.exit(0) would overwrite
            // the exit code and turn a failing suite green.
            throw new Error(msg);
        }
    }

    function capacityCheck(count, availW, availH) {
        const g = layout.compute(availW, availH, count, opts);
        assert(g.cols * g.rows >= count,
            "capacity: cols*rows must cover count=" + count + " (got " + g.cols + "x" + g.rows + ")");
        assert(g.gridW <= availW,
            "width fit: gridW " + g.gridW + " must fit availW " + availW + " for count=" + count);
        assert(g.cellW >= 1 && g.cellH >= 1,
            "cells must be positive for count=" + count);
        assert(Number.isFinite(g.gridH) && g.gridH > 0,
            "gridH must be finite and positive for count=" + count);
    }

    function runTests() {
        console.log("RUNNING: Overview grid layout tests");

        // 1. Degenerate inputs: empty grid, no NaN.
        const empty = layout.compute(1792, 952, 0, opts);
        assert(empty.cols === 0 && empty.rows === 0, "count=0 must produce an empty grid");
        assert(empty.gridW === 0 && empty.gridH === 0, "count=0 must have zero extent");
        const noArea = layout.compute(0, 0, 5, opts);
        assert(noArea.cols === 0 && noArea.rows === 0, "zero area must produce an empty grid");

        // 2. Single window: one capped cell, centered by the caller via gridW/gridH.
        const one = layout.compute(1792, 952, 1, opts);
        assert(one.cols === 1 && one.rows === 1, "count=1 must be a single cell");
        assert(one.cellW === 440, "count=1 cellW must respect maxCellW, got " + one.cellW);
        assert(one.cellH === Math.floor(one.cellW / opts.cardAspect),
            "cellH must derive from cardAspect");
        assert(one.gridW === one.cellW && one.gridH === one.cellH, "single-cell grid extent must match the cell");

        // 3. Twelve windows on 1920x1080 available area: 4 columns.
        const twelve = layout.compute(1792, 952, 12, opts);
        assert(twelve.cols === 4, "count=12 must produce 4 columns, got " + twelve.cols);
        assert(twelve.rows === 3, "count=12 must produce 3 rows, got " + twelve.rows);
        assert(twelve.gridW <= 1792, "count=12 grid must fit width");
        assert(twelve.gridH <= 952, "count=12 grid must fit height without scrolling, got " + twelve.gridH);
        assert(twelve.gridW === twelve.cols * twelve.cellW + (twelve.cols - 1) * opts.gap,
            "gridW must equal cols*cellW + gaps");
        assert(twelve.gridH === twelve.rows * twelve.cellH + (twelve.rows - 1) * opts.gap,
            "gridH must equal rows*cellH + gaps");

        // 4. Capacity + width fit across counts and screen sizes.
        const counts = [1, 2, 3, 5, 7, 13, 30];
        for (let i = 0; i < counts.length; i++) {
            capacityCheck(counts[i], 1792, 952);
            capacityCheck(counts[i], 1176, 660);
            capacityCheck(counts[i], 3600, 1900);
        }

        // 5. Narrow columns respect minCellW as the column-count gate: on a
        //    small area the grid must not squeeze below minCellW per column.
        const small = layout.compute(760, 600, 12, opts);
        assert(small.cols <= Math.floor((760 + opts.gap) / (opts.minCellW + opts.gap)),
            "columns must be gated by minCellW on narrow areas, got cols=" + small.cols);
        assert(small.cellW >= opts.minCellW,
            "cellW must stay at or above minCellW when the width gate allows it, got " + small.cellW);

        // 6. Vertical overflow: cells shrink to the minCellH floor and the grid
        //    reports gridH > availH so the surface scrolls instead of clipping.
        const tall = layout.compute(1792, 300, 40, opts);
        assert(tall.cellH >= opts.minCellH,
            "cellH must never fall below the minCellH scroll floor, got " + tall.cellH);
        assert(tall.gridH > 300,
            "overflowing rows must report gridH > availH so the view scrolls, got " + tall.gridH);

        // 7. Very wide window thumbnails must not distort the cell box: cellH
        //    always derives from cellW via cardAspect before vertical fitting.
        const two = layout.compute(1792, 952, 2, opts);
        assert(two.cols === 2 && two.rows === 1, "count=2 must be one row of two");
        assert(two.cellH === Math.floor(two.cellW / opts.cardAspect),
            "unconstrained row must keep the card aspect");

        console.log("PASS: Overview grid layout tests passed");
        Qt.exit(0);
    }
}
