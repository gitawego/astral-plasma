import QtQuick

// ============================================================================
// Decorative Frame Budget — source contract
// ============================================================================
// Qt Quick repaints the whole window whenever any item changes, and QML
// animations advance at the display refresh rate. On a 165–240 Hz panel a single
// decorative animation therefore forces 165–240 full-window renders per second.
// For the full-screen shell surface that saturates the iGPU and stalls the
// desktop (measured: ~47% CPU with an uncapped activity border vs ~0.3% idle).
//
// Decorative motion that can run for minutes-to-hours while its surface is on
// screen must be driven by MotionPacer at Theme.decorativeMaxFps. Interactive and
// spatial transitions are never throttled.
//
// Transient, user-initiated spinners (loading / refreshing / authenticating) may
// keep a vsync-rate infinite animation: they live for seconds, only while the
// user is actively watching the surface:
//   - dock/popouts/AiTokensSection.qml  (token refresh)
//   - settings_gui/pages/AiPage.qml     (provider sign-in)
//   - shell/UnifiedDock.qml             (app launch / loading rings)
Item {
    id: testRoot
    width: 100
    height: 100

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    // Decorative motion: visible for as long as its feature is active, so it must
    // never advance at display refresh rate.
    readonly property var decorativeFiles: [
        "../components/MatrixBorderEffect.qml",
        "../components/DownloadBorderEffect.qml",
        "../components/VinylPlayer.qml",
        "../components/RadialCoverVisualiser.qml",
        "../components/RadialCoverRing.qml",
        "../components/HeatmapCoverRing.qml",
        "../components/HeatmapSpeakerPlayer.qml",
        "../dashboard/tabs/DashboardTab.qml",
        "../dock/components/DockStatusIcons.qml"
    ]

    Timer {
        interval: 40
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Decorative frame budget contracts");

        // ---- 1. Shared token ------------------------------------------------
        const themeSrc = readLocalFile("../theme/Theme.qml");
        assert(/decorativeMaxFps:\s*30\b/.test(themeSrc),
            "Theme must declare decorativeMaxFps: 30 as the decorative motion budget");

        // ---- 2. MotionClock / MotionPacer implementation contract -----------
        const clockSrc = readLocalFile("../components/motion/MotionClock.qml");
        assert(clockSrc.length > 500, "MotionClock.qml must be readable");
        assert(/frameBudget:[\s\S]{0,200}Theme\.decorativeMaxFps/.test(clockSrc),
            "MotionClock must take its frame budget from Theme.decorativeMaxFps");
        assert(/frameBudget\s*=\s*30|:\s*30\b/.test(clockSrc),
            "MotionClock must fall back to 30 fps when the token is unavailable");
        assert(/property\s+int\s+consumers/.test(clockSrc) && /function\s+acquire/.test(clockSrc)
            && /function\s+release/.test(clockSrc),
            "MotionClock must be reference-counted by its consumers");
        assert(/running:\s*root\.consumers\s*>\s*0/.test(clockSrc),
            "MotionClock ticker must stop when no consumer holds a reference (0% idle CPU)");
        assert(/^[ \t]*(NumberAnimation|SequentialAnimation|RotationAnimation|FrameAnimation)\s*\{/m.test(clockSrc) === false,
            "MotionClock must not use vsync-driven animations (they keep the render loop awake)");

        const pacerSrc = readLocalFile("../components/motion/MotionPacer.qml");
        assert(pacerSrc.length > 500, "MotionPacer.qml must be readable");
        assert(/property\s+bool\s+running/.test(pacerSrc),
            "MotionPacer must gate advancing on a running property (0% idle CPU)");
        assert(/property\s+real\s+period/.test(pacerSrc),
            "MotionPacer must expose the cycle period");
        assert(/readonly\s+property\s+real\s+phase/.test(pacerSrc),
            "MotionPacer must expose a normalized phase");
        assert(/readonly\s+property\s+real\s+breath/.test(pacerSrc),
            "MotionPacer must expose the cosine breath envelope");
        assert(/MotionClock\.elapsedMs/.test(pacerSrc) && /MotionClock\.acquire\(\)/.test(pacerSrc),
            "MotionPacer must derive its phase from MotionClock time");
        assert(!/Timer\s*\{/.test(pacerSrc),
            "MotionPacer must not own a timer; N timers interleave into N frames per tick");
        assert(!/^[ \t]*(NumberAnimation|SequentialAnimation|RotationAnimation|FrameAnimation)\s*\{/m.test(pacerSrc),
            "MotionPacer must not use vsync-driven animations (they keep the render loop awake)");

        // ---- 3. Every decorative host is on the shared clock ----------------
        for (let i = 0; i < decorativeFiles.length; i++) {
            const file = decorativeFiles[i];
            const src = readLocalFile(file);
            assert(src.length > 500, file + " must be readable");
            assert(!/loops:\s*Animation\.Infinite/.test(src),
                file + " must not host a vsync-rate infinite animation; drive it with MotionPacer");
            assert(/MotionPacer\s*\{/.test(src),
                file + " must drive its continuous motion through MotionPacer");
        }

        // ---- 4. The two full-screen border effects stay gated on activity ---
        const matrixSrc = readLocalFile("../components/MatrixBorderEffect.qml");
        assert(/id:\s*pulsePacer[\s\S]{0,200}running:\s*root\.active/.test(matrixSrc),
            "MatrixBorderEffect pulse pacer must be gated on root.active");
        assert(/id:\s*travelPacer[\s\S]{0,200}running:\s*root\.active\s*&&/.test(matrixSrc),
            "MatrixBorderEffect travel pacer must be gated on root.active && growth");
        const dlSrc = readLocalFile("../components/DownloadBorderEffect.qml");
        assert(/id:\s*travelPacer[\s\S]{0,220}running:\s*root\.active\s*&&/.test(dlSrc),
            "DownloadBorderEffect travel pacer must be gated on root.active && activity");
        assert(/id:\s*pulsePacer[\s\S]{0,220}running:\s*root\.active\s*&&/.test(dlSrc),
            "DownloadBorderEffect pulse pacer must be gated on root.active && speed");

        console.log("PASS: Decorative frame budget contracts passed");
        Qt.exit(0);
    }
}
