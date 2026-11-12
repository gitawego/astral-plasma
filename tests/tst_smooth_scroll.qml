import QtQuick
import "../modules/Astral/Kernel/components"
import "../modules/Astral/Kernel/components/ScrollPhysics.js" as Physics

// ============================================================================
// Smooth scrolling
// ============================================================================
// macOS-style scrolling: a wheel delta is a velocity impulse, momentum decays
// exponentially, and an edge maps the raw position through the UIScrollView
// rubber band. Fast gestures accumulate velocity; they do not fight a target.
Item {
    id: testRoot
    width: 700
    height: 500

    property int scrollStarts: 0
    property int scrollEnds: 0

    SmoothFlickable {
        id: vertical
        width: 200
        height: 200
        contentHeight: 1000
        contentWidth: width

        Rectangle {
            width: 200
            height: 1000
            color: "#333"
        }
    }

    SmoothFlickable {
        id: horizontal
        x: 220
        width: 200
        height: 200
        contentWidth: 1000
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick

        Rectangle {
            width: 1000
            height: 200
            color: "#444"
        }
    }

    SmoothFlickable {
        id: locked
        y: 220
        width: 200
        height: 200
        contentHeight: 1000
        interactive: false

        Rectangle {
            width: 200
            height: 1000
            color: "#555"
        }
    }

    Component.onCompleted: {
        vertical.wheelHandler.scrollStarted.connect(() => testRoot.scrollStarts++);
        vertical.wheelHandler.scrollEnded.connect(() => testRoot.scrollEnds++);

        // Wheel delta normalization: a high-resolution pixel delta wins;
        // a classic 120-unit notch becomes 60 px of content.
        assert(Physics.axisDelta({
            pixelDelta: { x: 0, y: 0 },
            angleDelta: { x: 0, y: 120 }
        }, "y") === 60, "a wheel notch is 60 px of content");
        assert(Physics.axisDelta({
            pixelDelta: { x: 0, y: 3 },
            angleDelta: { x: 0, y: 120 }
        }, "y") === 3, "a trackpad pixel delta is used as-is");

        // Momentum decays every frame instead of easing to a target.
        assert(Physics.decay(600, 1 / 60) < 600,
            "velocity decays with momentum");
        assert(Physics.decay(600, 1 / 60) > 0,
            "and does not stop in one frame");

        // Rubber band: inside the bounds the offset is untouched; outside it is
        // compressed by the UIScrollView curve.
        assert(Physics.displayed(50, 0, 800, 760) === 50,
            "inside the bounds the raw position is the content offset");
        const topBand = Physics.displayed(-50, 0, 800, 760);
        assert(topBand < 0 && topBand > -50,
            "the top overshoot is compressed (got " + topBand + ")");
        const bottomBand = Physics.displayed(850, 0, 800, 760);
        assert(bottomBand > 800 && bottomBand < 850,
            "the bottom overshoot is compressed (got " + bottomBand + ")");

        // One notch: 420 px/s decays to rest after travelling about 60 px.
        let position = 0;
        let velocity = 60 * Physics.SCROLL_IMPULSE;
        for (let i = 0; i < 180; ++i) {
            const next = Physics.advance(position, velocity, 1 / 60);
            position = next.position;
            velocity = Physics.applyEdge(position, next.velocity, 0, 800, 1 / 60);
        }
        assert(position > 55 && position < 70,
            "one notch travels about 60 px (got " + position + ")");
        assert(Math.abs(velocity) < 1, "one notch settles");

        // Fast input accumulates velocity and travels farther.
        position = 0;
        velocity = Math.min(5 * 60 * Physics.SCROLL_IMPULSE, Physics.SCROLL_MAX_VELOCITY);
        for (let i = 0; i < 240; ++i) {
            const next = Physics.advance(position, velocity, 1 / 60);
            position = next.position;
            velocity = Physics.applyEdge(position, next.velocity, 0, 800, 1 / 60);
        }
        assert(position > 250,
            "a fast gesture travels farther than a notch (got " + position + ")");

        // At a bound the raw position overshoots, the displayed offset is
        // compressed, and the edge spring returns to the bound.
        position = 800;
        velocity = 60 * Physics.SCROLL_IMPULSE;
        let rawPeak = position;
        let displayPeak = position;
        for (let i = 0; i < 180; ++i) {
            const next = Physics.advance(position, velocity, 1 / 60);
            position = next.position;
            velocity = Physics.applyEdge(position, next.velocity, 0, 800, 1 / 60);
            rawPeak = Math.max(rawPeak, position);
            displayPeak = Math.max(displayPeak, Physics.displayed(position, 0, 800, 760));
        }
        assert(rawPeak > 803, "the raw position overshoots the bound (peak " + rawPeak + ")");
        assert(displayPeak > 800 && displayPeak < rawPeak,
            "the displayed overshoot is compressed (" + displayPeak + " < " + rawPeak + ")");
        assert(Physics.snapped(position, 0, 800) === 800,
            "and the edge spring snaps back to the bound (got " + position + ")");

        // Start one real gesture through the QML handler.
        vertical.wheelHandler.scrollBy(0, -120);
        assert(vertical.wheelHandler.animating === true,
            "a wheel step starts the physics frame loop");
        assert(vertical.contentY === 0,
            "the content has not jumped to the target");
        assert(testRoot.scrollStarts === 1, "the scroll-start signal fires");
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: checkMidGlide()
    }

    Timer {
        interval: 1500
        running: true
        repeat: false
        onTriggered: finishTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function checkMidGlide() {
        assert(vertical.contentY > 0 && vertical.contentY < 120,
            "the content is mid-glide with momentum (got " + vertical.contentY + ")");
        assert(vertical.wheelHandler.animating === true,
            "the momentum loop is still running mid-glide");
    }

    function finishTests() {
        assert(Math.abs(vertical.contentY - 120) < 1,
            "momentum settles on the wheel distance (got " + vertical.contentY + ")");
        assert(vertical.wheelHandler.animating === false,
            "the physics frame loop stops at rest");
        assert(testRoot.scrollEnds === 1, "the scroll-end signal fires once");

        // Horizontal-only surfaces route the wheel to contentX.
        assert(horizontal.wheelHandler.scrollBy(-120, 0) === true,
            "a horizontal surface takes a horizontal wheel");
        assert(horizontal.wheelHandler.animating === true,
            "the horizontal momentum starts");
        horizontal.wheelHandler.stopPhysics();

        // A non-interactive surface must ignore the wheel entirely.
        assert(locked.wheelHandler.scrollBy(0, -120) === false,
            "a non-interactive surface never takes the wheel");
        assert(locked.contentY === 0,
            "a non-interactive surface never scrolls");

        // The generic contract: every shipped scroll surface uses the shared
        // wrapper. WallpaperCarousel is intentionally wheel-driven (it selects
        // a wallpaper), not scrolled.
        const files = [
            "dashboard/tabs/WorkspacesTab.qml",
            "dock/LeftDock.qml",
            "dock/components/DockScrollCapsule.qml",
            "dock/popouts/AiTokensSection.qml",
            "dock/popouts/FusedBottomPopout.qml",
            "dock/popouts/WifiPopout.qml",
            "modules/Astral/Apps/Assistant/components/ChatInputBar.qml",
            "modules/Astral/Apps/Assistant/components/ChatView.qml",
            "modules/Astral/Apps/Assistant/components/LiquidGlassFilePicker.qml",
            "modules/Astral/Apps/Assistant/components/MermaidDiagramCard.qml",
            "modules/Astral/Apps/Assistant/components/ModelProviderBar.qml",
            "modules/Astral/Apps/Assistant/components/QuickActionChips.qml",
            "modules/Astral/Apps/Assistant/components/SessionListDrawer.qml",
            "modules/Astral/Apps/Downloads/DownloadSettingsPanel.qml",
            "modules/Astral/Apps/Downloads/DownloadsApp.qml",
            "modules/Astral/Apps/Launcher/LauncherApp.qml",
            "modules/Astral/Apps/Workspaces/WorkspacesApp.qml",
            "modules/Astral/Kernel/components/InputMethodList.qml",
            "settings_gui/NexusHub.qml",
            "settings_gui/pages/TimePage.qml",
            "settings_gui/pages/VoicePage.qml",
            "shell/ActiveAppsOverview.qml",
            "shell/TrayContextMenu.qml"
        ];
        for (let i = 0; i < files.length; ++i) {
            const src = testRoot.readLocalFile("../" + files[i]);
            assert(src !== "", files[i] + ": source is readable");
            assert(!/\bFlickable\s*\{/.test(src) && !/\bListView\s*\{/.test(src)
                    && !/\bGridView\s*\{/.test(src),
                files[i] + ": uses the shared Smooth* scroll surface");
        }

        console.log("PASS: Smooth Scrolling");
        Qt.exit(0);
    }
}
