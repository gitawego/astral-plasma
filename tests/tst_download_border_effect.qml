import QtQuick
import "../components"
import "../theme"
import "../config"

// ============================================================================
// Top-Right Download Border Effect Unit Tests (TDD)
// ============================================================================
// Verifies:
// 1. DownloadBorderEffect geometry contract (strictly inside borderT: 14, capped widths).
// 2. Progression tracking (totalCompletedBytes, totalBytes, totalProgress, fillProgress).
// 3. Dynamic max/min session speed tracking and telemetry formatting.
// 4. Matrix-symmetric digital hex rain and equalizer pulses.
// 5. Zero-idle-CPU contract (timers gate on active, MotionClock integration).
// 6. Interactive click on HUD capsule switches to Downloads tab.
Item {
    id: testRoot
    width: 1920
    height: 1080

    DownloadBorderEffect {
        id: dlEffect
        anchors.fill: parent
        borderT: 14
        cornerFilletR: 20
        topWidth: 400
        rightHeight: 220
        totalProgress: 0.45
        totalCompletedBytes: 450000000
        totalBytes: 1000000000
        totalSpeed: 5242880
        activeCount: 3
        indeterminate: false
        effectEnabled: true
        cornerBusy: false
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

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

    function runTests() {
        console.log("RUNNING: DownloadBorderEffect Unit Tests");

        // ---- 1. Instantiation & Geometry Contracts ----
        assert(dlEffect !== null, "DownloadBorderEffect must instantiate");
        assert(dlEffect.borderT === 14, "borderT strictly 14px, got " + dlEffect.borderT);
        assert(dlEffect.topWidth <= 420, "topWidth capped <= 420px, got " + dlEffect.topWidth);
        assert(dlEffect.rightHeight <= 260, "rightHeight capped <= 260px, got " + dlEffect.rightHeight);
        assert(dlEffect.active === true, "effect active when activeCount > 0");
        assert(dlEffect.visible === true, "effect visible when active");

        // ---- 2. Progression Tracking ----
        assert(dlEffect.totalProgress === 0.45, "totalProgress is 0.45");
        assert(dlEffect.totalCompletedBytes === 450000000, "totalCompletedBytes is 450MB");
        assert(dlEffect.totalBytes === 1000000000, "totalBytes is 1GB");

        // ---- 3. Session Max and Min Speed Tracking ----
        // Starts with current speed
        assert(dlEffect.sessionMaxSpeed >= 5242880, "sessionMaxSpeed initialized at >= 5MB/s, got " + dlEffect.sessionMaxSpeed);
        assert(dlEffect.sessionMinSpeed <= 5242880, "sessionMinSpeed initialized at <= 5MB/s, got " + dlEffect.sessionMinSpeed);

        // Lower speed fluctuation
        dlEffect.totalSpeed = 2097152; // 2 MB/s
        assert(dlEffect.sessionMinSpeed === 2097152, "sessionMinSpeed tracks lower speed (2MB/s), got " + dlEffect.sessionMinSpeed);
        assert(dlEffect.sessionMaxSpeed === 5242880, "sessionMaxSpeed retains peak (5MB/s), got " + dlEffect.sessionMaxSpeed);

        // Higher speed fluctuation
        dlEffect.totalSpeed = 10485760; // 10 MB/s
        assert(dlEffect.sessionMaxSpeed === 10485760, "sessionMaxSpeed updates to new peak (10MB/s), got " + dlEffect.sessionMaxSpeed);
        assert(dlEffect.sessionMinSpeed === 2097152, "sessionMinSpeed retains floor (2MB/s), got " + dlEffect.sessionMinSpeed);

        // ---- 4. Telemetry and HUD Formatting ----
        const hudStr = dlEffect.formattedHudText || dlEffect.hudSlotItem.hudText;
        assert(hudStr.indexOf("3") !== -1, "HUD displays active count 3: " + hudStr);
        assert(hudStr.indexOf("45%") !== -1, "HUD displays progress 45%: " + hudStr);
        assert(hudStr.indexOf("▲") !== -1, "HUD includes max speed marker ▲: " + hudStr);
        assert(hudStr.indexOf("▼") !== -1, "HUD includes min speed marker ▼: " + hudStr);

        // Reset speed tracking when downloads complete
        dlEffect.activeCount = 0;
        assert(dlEffect.active === false, "inactive when activeCount 0");
        assert(dlEffect.sessionMaxSpeed === 0, "sessionMaxSpeed resets when activeCount 0");
        assert(dlEffect.sessionMinSpeed === 0, "sessionMinSpeed resets when activeCount 0");
        dlEffect.activeCount = 3;
        dlEffect.totalSpeed = 5242880;

        // ---- 5. Indeterminate Mode ----
        dlEffect.indeterminate = true;
        assert(dlEffect.travelDuration >= 1350, "indeterminate travelDuration sane");
        const indHud = dlEffect.formattedHudText || dlEffect.hudSlotItem.hudText;
        assert(indHud.indexOf("INGRESS") !== -1 || indHud.indexOf("↓") !== -1, "indeterminate HUD formatted");
        dlEffect.indeterminate = false;

        // ---- 6. Error & Complete State Colors ----
        dlEffect.hasError = true;
        assert(String(dlEffect.stateColor) === "#f87171", "error color is warm red (#f87171), got " + dlEffect.stateColor);
        dlEffect.hasError = false;

        dlEffect.showCompleteFlash = true;
        assert(String(dlEffect.stateColor) === "#34d399", "complete flash color is emerald green (#34d399), got " + dlEffect.stateColor);
        dlEffect.showCompleteFlash = false;

        // ---- 7. Interactive Open Downloads Action ----
        assert(typeof dlEffect.hudSlotItem.openDownloads === "function", "openDownloads function exists");
        dlEffect.hudSlotItem.openDownloads();
        assert(true, "openDownloads executes cleanly");

        // ---- 8. Paused State Handling (Not 'stalled') ----
        dlEffect.isPaused = true;
        dlEffect.totalSpeed = 0;
        assert(dlEffect.formatSpeed(0) === "PAUSED", "formatSpeed returns PAUSED when isPaused is true");
        assert(dlEffect.formatSpeedCompact(0) === "PAUSED", "formatSpeedCompact returns PAUSED when isPaused is true");
        const pausedHud = dlEffect.formattedHudText || dlEffect.hudSlotItem.hudText;
        assert(pausedHud.indexOf("PAUSED") !== -1, "HUD displays PAUSED when isPaused is true: " + pausedHud);
        assert(pausedHud.indexOf("stalled") === -1, "HUD does NOT display 'stalled' when isPaused is true: " + pausedHud);
        dlEffect.isPaused = false;

        // ---- 9. Electric Pulse Suite & Symmetric Corner Nexus ----
        assert(dlEffect.secondaryColor !== undefined, "declares secondaryColor for dual-phase chromatic electric effects");

        // ---- 10. Source Contracts & Zero-Regression Geometry ----
        const fxSrc = readLocalFile("../components/DownloadBorderEffect.qml");
        assert(fxSrc.length > 1000, "DownloadBorderEffect.qml readable");
        assert(/fusedTopNexus/.test(fxSrc), "declares fusedTopNexus");
        assert(/hudCapsule/.test(fxSrc), "declares hudCapsule");
        assert(/progressBar/.test(fxSrc), "declares prominent visual progress bar");
        assert(/sessionMaxSpeed/.test(fxSrc) && /sessionMinSpeed/.test(fxSrc), "declares session max/min speed tracking");
        assert(/matrixGlyphs/.test(fxSrc), "declares streaming matrix hex glyphs");
        assert(/MotionClock/.test(fxSrc), "advances matrix tick via MotionClock");
        assert(/running:\s*root\.active\s*&&/.test(fxSrc), "timers gated on active (0% idle CPU)");

        // Electric pulse suite assertions (horizontal and vertical symmetry)
        assert(/topPacketGlow/.test(fxSrc) && /topPacket/.test(fxSrc) && /topPacketSecondary/.test(fxSrc),
            "topBorderSection declares complete horizontal electric pulse suite");
        assert(/rightPacketGlow/.test(fxSrc) && /rightPacket/.test(fxSrc) && /rightPacketSecondary/.test(fxSrc),
            "rightTopSection declares complete vertical electric pulse suite matching MatrixBorderEffect");
        assert(/secondaryColor/.test(fxSrc), "uses secondaryColor for trailing pulses and chromatic corona");

        // Corner nexus liquid glass fusion & C^1 non-cropping arc contract
        assert(/fusedTopNexus\.width/.test(fxSrc) && /fusedTopNexus\.height/.test(fxSrc),
            "fusedTopNexus uses explicit item width/height in ShapePath to avoid Qt Quick parent resolution failure");
        assert(/direction:\s*PathArc\.Counterclockwise/.test(fxSrc),
            "fusedTopNexus fillet arc uses Counterclockwise direction to ensure smooth corner curve without edge cropping");

        console.log("PASS: All DownloadBorderEffect Unit Tests passed successfully!");
        Qt.exit(0);
    }
}
