import QtQuick
import "../modules/Astral/Kernel/components"
import "../modules/Astral/Kernel/components/ScrollPhysics.js" as Physics

// ============================================================================
// Smooth scrolling
// ============================================================================
// One scroll primitive for the shell. A wheel notch should glide, a trackpad's
// pixel stream should accumulate into the same glide, and a surface that cannot
// scroll in that direction must not trap the event from its parent.
Item {
    id: testRoot
    width: 700
    height: 500

    property int step: 0
    readonly property var tokens: ({
        animExpressiveFastEffects: 150,
        curveExpressiveFastEffects: [0.31, 0.94, 0.34, 1.0, 1.0, 1.0]
    })

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
        vertical.wheelHandler.motionTokens = testRoot.tokens;
        horizontal.wheelHandler.motionTokens = null;
        locked.wheelHandler.motionTokens = testRoot.tokens;
    }

    Timer {
        interval: 80
        running: true
        repeat: true
        onTriggered: testRoot.advance()
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

    function advance() {
        switch (testRoot.step++) {
        case 0: {
            console.log("RUNNING: Smooth Scrolling");

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

            // At a boundary the wheel belongs to the parent, not to a surface
            // that has nowhere left to go.
            assert(vertical.wheelHandler.canScrollBy(0, 60) === false,
                "at the top, an upward wheel is left for the parent");
            assert(vertical.wheelHandler.canScrollBy(0, -60) === true,
                "at the top, a downward wheel is consumed");

            // Vertical glide: the target is accepted, but the position has not
            // jumped there yet.
            vertical.wheelHandler.scrollBy(0, -120);
            assert(vertical.wheelHandler.animating === true,
                "a wheel step starts an animation, not a jump");
            assert(vertical.contentY === 0,
                "the content has not jumped to the target");
            break;
        }
        case 1:
            assert(vertical.contentY > 0 && vertical.contentY < 120,
                "the content is mid-glide (got " + vertical.contentY + ")");
            assert(vertical.wheelHandler.animating === true,
                "the animation is still running mid-glide");
            break;
        case 2: {
            assert(Math.abs(vertical.contentY - 120) < 1,
                "the glide lands on the wheel target (got " + vertical.contentY + ")");
            assert(vertical.wheelHandler.animating === false,
                "the glide settles");

            // A horizontal-only surface routes the wheel to contentX, and the
            // no-token path is an immediate jump (the harness has no Theme).
            horizontal.wheelHandler.scrollBy(-120, 0);
            assert(horizontal.contentX === 120,
                "a horizontal surface scrolls horizontally (got " + horizontal.contentX + ")");

            // A non-interactive surface must ignore the wheel entirely.
            locked.wheelHandler.scrollBy(0, -120);
            assert(locked.contentY === 0,
                "a non-interactive surface never scrolls");

            // Clamping at both ends.
            vertical.wheelHandler.motionTokens = null;
            vertical.wheelHandler.scrollBy(0, -100000);
            assert(vertical.contentY === 800,
                "the target clamps to the scrollable end (got " + vertical.contentY + ")");
            assert(vertical.wheelHandler.canScrollBy(0, -60) === false,
                "at the bottom, a downward wheel is left for the parent");
            assert(vertical.wheelHandler.canScrollBy(0, 60) === true,
                "at the bottom, an upward wheel is consumed");
            vertical.wheelHandler.scrollBy(0, 100000);
            assert(vertical.contentY === 0,
                "and clamps back to the start (got " + vertical.contentY + ")");

            // The generic contract: every shipped scroll surface uses the
            // shared wrapper. WallpaperCarousel is intentionally wheel-driven
            // (it selects a wallpaper), not scrolled.
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
                assert(src.indexOf("Kernel/components") >= 0 || src.indexOf("Kernel\\components") >= 0
                        || src.indexOf("SmoothFlickable") >= 0 || src.indexOf("SmoothListView") >= 0
                        || src.indexOf("SmoothGridView") >= 0,
                    files[i] + ": resolves the shared scroll components");
            }

            console.log("PASS: Smooth Scrolling");
            Qt.exit(0);
            break;
        }
        default:
            break;
        }
    }
}
