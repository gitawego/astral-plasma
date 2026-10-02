.pragma library

// ============================================================================
// Section spy
// ============================================================================
// Which section is the user looking at, given the scroll offset?
//
// The settings hub pins the page header and highlights the section the reader is
// in, so this rule lives in one place instead of being re-derived per page:
// a zone becomes current once its anchor has passed the top of the viewport, and
// the page's first zone is current before that (a header with nothing highlighted
// looks broken). Zones whose offset is unknown are skipped rather than guessed.
//
// Pure: asserted by `tests/tst_settings_sticky_header.qml`.

/// The id of the zone at `offset` (usually `contentY` plus a small margin).
///
/// `zones` is `[{ id, label }]` in document order; `offsets` maps an id to its y
/// inside the page. Returns "" when there are no zones - a page whose layout we
/// do not know must not highlight an arbitrary pill.
///
/// `endOffset` is the scroll offset at which the viewport shows the end of the
/// page (`contentHeight - viewportHeight`), or `undefined` when unknown. It
/// matters because a page's trailing section can be shorter than the viewport:
/// its anchor then never reaches the top, so the rule above would keep an
/// earlier zone lit while the reader looks at the last one - and the pill they
/// clicked would never light up. At the end of a page that actually scrolls, the
/// last zone is therefore the current one. A page that fits entirely does not
/// scroll (`endOffset` is 0), and its first zone stays current.
function sectionAt(zones, offsets, offset, endOffset) {
    if (!zones || !zones.length) return "";
    var current = zones[0] && zones[0].id ? zones[0].id : "";
    for (var i = 0; i < zones.length; ++i) {
        var zone = zones[i];
        if (!zone || !zone.id) continue;
        var y = offsets ? offsets[zone.id] : undefined;
        if (y === undefined || y === null || isNaN(y)) continue;
        if (y <= offset) current = zone.id;
    }
    if (endOffset !== undefined && endOffset !== null && !isNaN(endOffset)
            && endOffset > 0 && offset >= endOffset) {
        for (var last = zones.length - 1; last >= 0; --last) {
            if (zones[last] && zones[last].id) return zones[last].id;
        }
    }
    return current;
}
