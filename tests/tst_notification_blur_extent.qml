import QtQuick

// ============================================================================
// Notification Blur-Mask & Border Contract
// ============================================================================
// The notification panel is drawn by FusedPanel (inside NotificationPopup) and the
// compositor blur behind it is a mask declared in UnifiedShell. Two defects are
// pinned here.
//
// 1. MASK OVERHANG. The mask added `filletR` to BOTH its width and height
//    unconditionally:
//
//        x = width - notifWidth - filletR
//        w = notifWidth + filletR
//        h = notifHeight + filletR
//
//    The panel's painted body is exactly `0,0,panelWidth,currentEnvelopeHeight`,
//    so that added a 20px strip of BARE desktop along the bottom and a 20px column
//    down the left. Measured live: panel bottom y=78, mask bottom y=98, and rows
//    78..97 read bright (bare wallpaper) while their local energy was suppressed
//    by the blur - frosted wallpaper with nothing drawn over it.
//
//    The only painted area outside the panel rect is the single concave corner
//    fillet at the top-left junction, which lives in the top `borderRounding` rows.
//    It is therefore exposed as a separate `shoulderRect` so the mask can cover
//    that stub without frosting a full-height column.
//
// 2. STRAY INNER BORDER. The inner notifCard drew its own 1px perimeter ring,
//    visible as a second, smaller rounded box inside the panel (empirically two
//    hairlines at y=16 and y=71 against the panel edge at y=77-78). A resting
//    container should not draw a ring; the specular hairlines already define the
//    glass edge (docs/LESSONS.md 9.1, "Clean Glass Materials").
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        // Cache-buster: Qt caches file:// reads, which would let this guard test
        // stale source and pass while the real file changed.
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
        console.log("RUNNING: Notification Blur-Mask & Border Contract");

        const popup = readLocalFile("../notifications/NotificationPopup.qml");
        const shell = readLocalFile("../shell/UnifiedShell.qml");
        const card = readLocalFile("../components/LiquidGlassCard.qml");

        assert(popup.length > 1000 && shell.length > 1000 && card.length > 500,
            "sources must be readable");

        // ---- 1. NotificationPopup must publish its painted extents --------
        assert(/readonly property real surfaceWidth/.test(popup),
            "NotificationPopup must expose `surfaceWidth`");
        assert(/readonly property real surfaceHeight/.test(popup),
            "NotificationPopup must expose `surfaceHeight`");
        assert(/readonly property real surfaceX/.test(popup),
            "NotificationPopup must expose `surfaceX`");
        assert(/readonly property rect shoulderRect/.test(popup),
            "NotificationPopup must expose `shoulderRect` for the top-left fillet stub");

        // The body must be the panel's own rect, not extended by the rounding.
        const sw = popup.match(/readonly property real surfaceWidth:\s*([^\n]+)/);
        assert(sw !== null, "surfaceWidth must be declared");
        assert(!/borderRounding/.test(sw[1]),
            "surfaceWidth must be the panel width, not extended by borderRounding "
            + "(that frosted bare desktop): got " + sw[1].trim());
        const sh = popup.match(/readonly property real surfaceHeight:\s*([^\n]+)/);
        assert(sh !== null, "surfaceHeight must be declared");
        assert(!/borderRounding/.test(sh[1]),
            "surfaceHeight must be the panel height, not extended by borderRounding "
            + "(that frosted bare desktop below the panel): got " + sh[1].trim());

        // The shoulder stub must be limited to the fillet's own depth, never the
        // full panel height.
        const sr = popup.match(/readonly property rect shoulderRect:[\s\S]*?borderRounding[^)]*\)/);
        assert(sr !== null, "shoulderRect must be a Qt.rect(...) covering the fillet stub");
        assert(!/surfaceHeight/.test(sr[0]) && !/\bheight\b/.test(sr[0].replace(/borderRounding/g, '')),
            "shoulderRect must be bounded by the fillet depth, not the panel height - a "
            + "full-height column would frost bare desktop below the shoulder");

        // ---- 2. The mask must consume those extents ----------------------
        // Capture the comment plus the following region blocks (there are two:
        // the body and the shoulder stub). Take a generous window and strip the
        // comment's leading whitespace so nested braces do not truncate it.
        const start = shell.indexOf("System Notifications Popup");
        assert(start >= 0, "UnifiedShell must declare a notification blur region");
        const region = shell.substring(start, start + 2600);
        assert(/notifPopup\.surfaceWidth/.test(region),
            "the notification mask width must read NotificationPopup.surfaceWidth");
        assert(/notifPopup\.surfaceHeight/.test(region),
            "the notification mask height must read NotificationPopup.surfaceHeight");
        assert(/notifPopup\.surfaceX/.test(region),
            "the notification mask x must read NotificationPopup.surfaceX");
        assert(/notifPopup\.shoulderRect/.test(region),
            "the notification mask must cover the shoulder stub separately");
        assert(!/notifPopup\.width \+ root\.filletR/.test(region),
            "the notification mask must not add root.filletR to the panel width - that "
            + "frosts a strip of bare desktop");
        assert(!/notifPopup\.height \+ root\.filletR/.test(region),
            "the notification mask must not add root.filletR to the panel height - that "
            + "was the reported overhang below the panel");

        // ---- 3. The inner ring must be off ------------------------------
        assert(/property bool showBorder/.test(card),
            "LiquidGlassCard must expose `showBorder` so a resting container can drop the ring");
        assert(/border\.width:\s*root\.showBorder/.test(card),
            "LiquidGlassCard's border must honour showBorder");
        const innerCard = popup.match(/id:\s*notifCard[\s\S]*?(?=\n        Item|\n    \})/);
        assert(innerCard !== null, "the notification must declare its inner notifCard");
        assert(/showBorder:\s*false/.test(innerCard[0]),
            "the notification's inner card must set showBorder: false - a 1px ring there "
            + "renders as a second rounded box inside the panel");

        // ---- 4. Quantify the defect for the record ----------------------
        const filletR = 20, panelH = 78, panelW = 380;
        const oldMaskH = panelH + filletR;
        const oldMaskW = panelW + filletR;
        const newMaskH = panelH;
        const newMaskW = panelW;
        assert(oldMaskH > newMaskH && oldMaskW > newMaskW,
            "sanity: the legacy mask must exceed the panel in both axes");
        const overhang = (oldMaskH - newMaskH) + (oldMaskW - newMaskW);
        assert(overhang === 2 * filletR,
            "sanity: legacy overhang should be filletR per axis, got " + overhang);

        console.log("PASS: Notification Blur-Mask & Border Contract "
            + "(mask consumes the panel's own extents + a " + filletR
            + "px shoulder stub instead of overhanging " + filletR
            + "px on two sides; inner ring disabled)");
        Qt.exit(0);
    }
}
