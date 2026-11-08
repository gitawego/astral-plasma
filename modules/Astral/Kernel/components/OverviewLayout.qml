import QtQml

// Pure grid math for the active-apps overview.
//
// Uniform cells sized by the width budget (capped), column count gated by
// minCellW so columns never squeeze below a usable size, rows derived from the
// count. Vertical space first shrinks cells toward minCellH; below that floor
// the grid reports gridH > availH so the surface scrolls (Flickable/GridView)
// instead of clipping - dynamic lists must stay bounded (AGENTS.md 7.2).
// No visual types: instantiable and assertable under the offscreen qml6
// harness, where Quickshell singletons are inert.
QtObject {
    id: root

    readonly property var defaults: ({
        gap: 16,
        minCellW: 170,
        maxCellW: 440,
        minCellH: 110,
        cardAspect: 1.5
    })

    /// @return {{cols, rows, cellW, cellH, gridW, gridH}} for the biggest
    /// uniform grid that fits `availW x availH` holding `count` cells, or an
    /// all-zero result when either the area or the count is empty.
    function compute(availW, availH, count, opts) {
        const o = Object.assign({}, root.defaults, opts || {});
        const empty = { cols: 0, rows: 0, cellW: 0, cellH: 0, gridW: 0, gridH: 0 };
        if (!(availW > 0) || !(availH > 0) || !(count > 0)) return empty;

        const gap = o.gap;
        const maxCols = Math.max(1, Math.floor((availW + gap) / (o.minCellW + gap)));
        const cols = Math.max(1, Math.min(Math.ceil(Math.sqrt(count)), count, maxCols));
        const rows = Math.ceil(count / cols);

        const cellW = Math.max(1, Math.min(o.maxCellW,
            Math.floor((availW - (cols - 1) * gap) / cols)));
        let cellH = Math.floor(cellW / o.cardAspect);
        if (rows * cellH + (rows - 1) * gap > availH) {
            cellH = Math.max(o.minCellH, Math.floor((availH - (rows - 1) * gap) / rows));
        }

        return {
            cols: cols,
            rows: rows,
            cellW: cellW,
            cellH: cellH,
            gridW: cols * cellW + (cols - 1) * gap,
            gridH: rows * cellH + (rows - 1) * gap
        };
    }
}
