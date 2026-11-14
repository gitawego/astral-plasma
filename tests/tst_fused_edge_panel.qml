import QtQuick
import "../modules/Astral/Kernel/components"
import "../modules/Astral/Kernel/theme"

// FusedEdgePanel geometry contract:
// - the welded header (strip + shoulders) is static in slideBody;
// - the body is clipped below the top border and only its offset moves;
// - body offset/opacity are clamped against the expressive bezier overshoot;
// - blur rects describe exactly the drawn surfaces;
// - the same content host is reparented, never duplicated.
Item {
    id: testRoot
    width: 2560
    height: 1600

    FusedEdgePanel {
        id: body
        attachEdge: "top"
        motion: "slideBody"
        panelWidth: 1028
        panelHeight: 560
        bodyInset: 20
        borderThickness: 14
        borderRounding: 20
        bodyRounding: 20
        offsetProgress: 0.5

        Rectangle {
            id: bodyContent
            width: 100
            height: 50
        }
    }

    FusedEdgePanel {
        id: grown
        attachEdge: "top"
        motion: "grow"
        panelWidth: 980
        panelHeight: 520
        borderThickness: 14
        borderRounding: 24
        offsetProgress: 1.0

        Rectangle {
            id: grownContent
            width: 100
            height: 50
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function runTests() {
        console.log("RUNNING: FusedEdgePanel Tests");

        // Body inset: the body sits inside the panel, the shoulders outside it.
        assert(body.slideBodyMotion, "slideBody mode is active for a top edge");
        assert(body.bodyWidth === 988, "body width = panelWidth - 2*bodyInset (got " + body.bodyWidth + ")");
        assert(body.bodyHeight === 546, "body height = panelHeight - borderThickness (got " + body.bodyHeight + ")");
        assert(body.bodyClipItem.x === 20, "body clip starts at bodyInset (got " + body.bodyClipItem.x + ")");
        assert(body.bodyClipItem.y === 14, "body clip starts below the top border (got " + body.bodyClipItem.y + ")");
        assert(body.bodyClipItem.width === 988, "body clip width");
        assert(body.bodyClipItem.height === 546, "body clip height");
        assert(body.headerItem.height === 14, "header strip is exactly the border thickness");
        assert(body.headerItem.width === 1028, "header strip spans the full panel width");
        assert(body.bodyClipItem.clip === true, "the body clip is on");

        // Half progress: the body is above its resting place and clipped.
        assert(Math.abs(body.bodyOffset + 273) < 0.01, "body offset at 0.5 (got " + body.bodyOffset + ")");
        assert(Math.abs(body.visibleBodyHeight - 273) < 0.01, "visible body height at 0.5 (got " + body.visibleBodyHeight + ")");
        assert(body.bodyBlurRect.x === 20 && body.bodyBlurRect.y === 14,
            "body blur rect starts at the body origin");
        assert(body.bodyBlurRect.width === 988, "body blur rect width");
        assert(Math.abs(body.bodyBlurRect.height - 273) < 0.01,
            "body blur rect only covers the visible body (got " + body.bodyBlurRect.height + ")");
        assert(body.headerBlurRect.width === 1028 && body.headerBlurRect.height === 34,
            "header blur rect covers the strip + shoulders");
        assert(body.contentHostItem.parent === body.bodyClipItem,
            "slideBody content host is reparented into the body clip");
        assert(bodyContent.parent === body.contentHostItem,
            "slideBody content stays in the shared content host");

        // Overshoot clamp: the bezier can exceed 1; the body must not go below 0.
        body.offsetProgress = 1.1;
        assert(Math.abs(body.bodyOffset) < 0.01, "body offset clamps at 0 on overshoot (got " + body.bodyOffset + ")");
        assert(Math.abs(body.visibleBodyHeight - 546) < 0.01, "body is fully visible on overshoot");

        // Closed: the body is entirely above the clip.
        body.offsetProgress = 0.0;
        assert(Math.abs(body.bodyOffset + 546) < 0.01, "body starts entirely above the clip");
        assert(body.visibleBodyHeight === 0, "no body area is visible at progress 0");

        // Grow mode keeps the legacy card/content host and full size.
        assert(!grown.slideBodyMotion, "grow is the default choreography");
        assert(grown.card.x === 0 && grown.card.width === 980, "grow card width is the panel width");
        assert(grown.card.height === 520, "grow card reaches panelHeight at progress 1");
        assert(grown.contentHostItem.parent === grown.card, "grow content host stays in the card");
        assert(grownContent.parent === grown.contentHostItem, "grow content stays in the shared content host");

        console.log("PASS: FusedEdgePanel Tests");
        Qt.exit(0);
    }
}
