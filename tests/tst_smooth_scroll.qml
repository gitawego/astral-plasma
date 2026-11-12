import QtQuick
import "../modules/Astral/Kernel/components"
import "../modules/Astral/Kernel/components/ScrollPhysics.js" as Physics

// ============================================================================
// Smooth scrolling
// ============================================================================
// One scroll primitive for the shell. A wheel notch adds an impulse and a
// target; the spring-damper integrates every frame, so the content has momentum
// and an elastic overshoot instead of a fixed-duration slide. A surface that
// cannot scroll in that axis hands the wheel to its parent.
Item {
    id: testRoot
    width: 700
    height: 500

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

        // The spring moves with velocity, not a fixed tween: one step must
        // change both the position and the velocity.
        const stepped = Physics.step(0, 600, 60, 1 / 60);
        assert(stepped.position > 0 && stepped.position < 60,
            "one physics frame moves toward the target: " + stepped.position);
        assert(stepped.velocity > 0,
            "the spring accelerates toward the target: " + stepped.velocity);
        const braking = Physics.step(60, 600, 60, 1 / 60);
        assert(braking.velocity < 600,
            "the damper brakes a fast spring at its target: " + braking.velocity);

        // The elastic tail: the spring must overshoot its target, then settle.
        let position = 0;
        let velocity = 600;
        let peak = 0;
        for (let i = 0; i < 180; ++i) {
            const next = Physics.step(position, velocity, 60, 1 / 60);
            position = next.position;
            velocity = next.velocity;
            peak = Math.max(peak, position);
        }
        assert(peak > 62, "the spring overshoots its target elastically (peak " + peak + ")");
        assert(Math.abs(position - 60) < 0.5,
            "and settles back on the target (got " + position + ")");

        // At a bound, the same spring gives a rubber-band overshoot.
        position = 800;
        velocity = 600;
        peak = 800;
        for (let i = 0; i < 180; ++i) {
            const next = Physics.step(position, velocity, 800, 1 / 60);
            position = next.position;
            velocity = next.velocity;
            peak = Math.max(peak, position);
        }
        assert(peak > 803, "the bound overshoots elastically (peak " + peak + ")");
        assert(Math.abs(position - 800) < 0.5,
            "and returns to the bound (got " + position + ")");
        assert(Physics.settled(60, 0, 60) === true,
            "an at-rest spring at its target is settled");
        assert(Physics.settled(0, 600, 60) === false,
            "a moving spring is not settled");

        // Target clamping at both ends.
        assert(Physics.targetFor(0, 100000, 800) === 0,
            "an upward wheel at the top clamps to the start");
        assert(Physics.targetFor(0, -100000, 800) === 800,
            "a downward wheel clamps to the end");

        // At a boundary the wheel belongs to the parent, not to a surface
        // that has nowhere left to go.
        assert(vertical.wheelHandler.canScrollBy(0, 60) === false,
            "at the top, an upward wheel is left for the parent");
        assert(vertical.wheelHandler.canScrollBy(0, -60) === true,
            "at the top, a downward wheel is consumed");

        // Start one real spring gesture. The position must not jump there.
        vertical.wheelHandler.scrollBy(0, -120);
        assert(vertical.wheelHandler.animating === true,
            "a wheel step starts the physics frame loop");
        assert(vertical.contentY === 0,
            "the content has not jumped to the target");
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: checkMidGlide()
    }

    Timer {
        interval: 1000
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
            "the spring is still integrating mid-glide");
    }

    function finishTests() {
        assert(Math.abs(vertical.contentY - 120) < 1,
            "the spring settles on the wheel target (got " + vertical.contentY + ")");
        assert(vertical.wheelHandler.animating === false,
            "the physics frame loop stops at rest");

        // Horizontal-only surfaces route the wheel to contentX.
        assert(horizontal.wheelHandler.scrollBy(-120, 0) === true,
            "a horizontal surface takes a horizontal wheel");
        assert(horizontal.wheelHandler.animating === true,
            "the horizontal spring starts");
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
