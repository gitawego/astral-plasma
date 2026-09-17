import QtQuick
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

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
            throw new Error("FAIL: " + message);
        }
    }

    // Lifecycle Simulation Mock of AudioVisualizer
    QtObject {
        id: mockVisualizer
        property real energy: 0.0
        property real bass: 0.0
        property real mid: 0.0
        property real treble: 0.0
        property real beat: 0.0
        property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        property bool active: false

        property bool isPlaying: false
        property bool isDashboardVisible: false
        property string activeTab: "dashboard"
        property bool isEffectVisible: isDashboardVisible && (activeTab === "dashboard" || activeTab === "media")

        property bool procShouldRun: false
        property bool graceTimerRunning: false

        function startGraceTimer() {
            graceTimerRunning = true;
        }

        function stopGraceTimer() {
            graceTimerRunning = false;
        }

        function triggerGraceTimerExpire() {
            if (!isEffectVisible) {
                procShouldRun = false;
                active = false;
                energy = 0.0;
                bass = 0.0;
                mid = 0.0;
                treble = 0.0;
                beat = 0.0;
                bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
                graceTimerRunning = false;
            }
        }

        function updateLifecycle() {
            if (!isPlaying) {
                stopGraceTimer();
                procShouldRun = false;
                active = false;
                energy = 0.0;
                bass = 0.0;
                mid = 0.0;
                treble = 0.0;
                beat = 0.0;
                bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
                return;
            }

            if (isEffectVisible) {
                stopGraceTimer();
                procShouldRun = true;
            } else {
                if (procShouldRun && !graceTimerRunning) {
                    startGraceTimer();
                }
            }
        }

        function getHeatmapColor(val, alpha) {
            val = Math.max(0.0, Math.min(1.0, val || 0.0));
            var a = (alpha !== undefined) ? alpha : 1.0;
            var r = 0, g = 0, b = 0;
            if (val < 0.25) {
                var t = val / 0.25;
                r = Math.round(6 + (99 - 6) * t);
                g = Math.round(182 + (102 - 182) * t);
                b = Math.round(212 + (241 - 212) * t);
            } else if (val < 0.55) {
                var t = (val - 0.25) / 0.30;
                r = Math.round(99 + (236 - 99) * t);
                g = Math.round(102 + (72 - 102) * t);
                b = Math.round(241 + (153 - 241) * t);
            } else if (val < 0.85) {
                var t = (val - 0.55) / 0.30;
                r = Math.round(236 + (249 - 236) * t);
                g = Math.round(72 + (115 - 72) * t);
                b = Math.round(153 + (22 - 153) * t);
            } else {
                var t = (val - 0.85) / 0.15;
                r = Math.round(249 + (255 - 249) * t);
                g = Math.round(115 + (220 - 115) * t);
                b = Math.round(22 + (120 - 22) * t);
            }
            return Qt.rgba(r / 255.0, g / 255.0, b / 255.0, a);
        }
    }

    HeatmapCoverRing {
        id: testRing
        anchors.centerIn: parent
        innerRadius: 41
        outerRadius: 50
        isTargetVisible: true
    }

    HeatmapSpeakerPlayer {
        id: testSpeaker
        anchors.centerIn: parent
        width: 230
        height: 230
        isPlaying: true
        isTargetVisible: true
    }

    function runTests() {
        console.log("RUNNING: Audio Heatmap Cover Tests");

        // 1. Initial State
        assert(mockVisualizer.energy === 0.0, "Initial energy should be 0.0");
        assert(mockVisualizer.bass === 0.0, "Initial bass should be 0.0");
        assert(mockVisualizer.bands.length === 16, "Should have 16 frequency bands");
        assert(!mockVisualizer.procShouldRun, "Process should not run initially");

        // 2. Heatmap Color Function Tests
        var c0 = mockVisualizer.getHeatmapColor(0.0);
        assert(c0.r !== undefined && c0.g !== undefined && c0.b !== undefined, "c0 should be a valid RGBA color");

        var cMid = mockVisualizer.getHeatmapColor(0.5);
        assert(cMid.r > 0.3, "Mid-range heatmap should have warm red/magenta component");

        var cPeak = mockVisualizer.getHeatmapColor(1.0);
        assert(cPeak.r > 0.9 && cPeak.g > 0.7, "Peak heatmap should have golden/yellow component");

        // 3. Playback Paused: Should Halt Calculation & Subprocess
        mockVisualizer.isPlaying = false;
        mockVisualizer.isDashboardVisible = true;
        mockVisualizer.activeTab = "dashboard";
        mockVisualizer.updateLifecycle();
        assert(!mockVisualizer.procShouldRun, "Should not run when music is paused");
        assert(!mockVisualizer.graceTimerRunning, "Grace timer should not run when music is paused");

        // 4. Playback Active + Dashboard Tab Visible: Should Immediately Start
        mockVisualizer.isPlaying = true;
        mockVisualizer.isDashboardVisible = true;
        mockVisualizer.activeTab = "dashboard";
        mockVisualizer.updateLifecycle();
        assert(mockVisualizer.procShouldRun, "Should start when playing and visible");
        assert(!mockVisualizer.graceTimerRunning, "Grace timer should not run when actively visible");

        // 5. Visibility Lost (Dashboard Closed): Should Enter 5-Second Grace Window
        mockVisualizer.isDashboardVisible = false;
        mockVisualizer.updateLifecycle();
        assert(mockVisualizer.procShouldRun, "Should stay running during 5s grace window");
        assert(mockVisualizer.graceTimerRunning, "Grace timer must start countdown when hidden");

        // 6. Grace Timer Expired: Subprocess Stops (0% CPU)
        mockVisualizer.triggerGraceTimerExpire();
        assert(!mockVisualizer.procShouldRun, "Should halt subprocess once grace timer expires");
        assert(!mockVisualizer.active, "Should be inactive after grace timer expires");

        // 7. Media Tab Visibility: Should Run in Media Tab Too
        mockVisualizer.isDashboardVisible = true;
        mockVisualizer.activeTab = "media";
        mockVisualizer.updateLifecycle();
        assert(mockVisualizer.procShouldRun, "Should run when playing in media tab");

        // 8. HeatmapCoverRing Geometry Verification
        assert(testRing.innerRadius === 41, "innerRadius should be 41");
        assert(testRing.outerRadius === 50, "outerRadius should be 50");
        assert(testRing.width === (50 * 2 + 36), "width should match outerRadius * 2 + 36 with jumping dots/notes padding");

        // 9. Auto-switch to Playing Player on Dashboard / Media Open
        var playersList = [
            { id: "strawberry", identity: "Strawberry", playbackState: 2 }, // Paused
            { id: "cloudmusic", identity: "NetEase Cloud Music", playbackState: 1 } // Playing (1)
        ];
        var curPlayer = playersList[0]; // currently Strawberry
        var manualName = "Strawberry";

        // Simulating syncToPlayingPlayer()
        function syncPlaying() {
            for (var i = 0; i < playersList.length; i++) {
                if (playersList[i].playbackState === 1) {
                    manualName = "";
                    curPlayer = playersList[i];
                    return;
                }
            }
        }

        // On open dashboard:
        syncPlaying();
        assert(curPlayer.identity === "NetEase Cloud Music", "Must auto-switch to playing player (Cloud Music) on open");
        assert(manualName === "", "Manual player selection must reset to follow actively playing track");

        // 10. HeatmapSpeakerPlayer Target Design Verification
        assert(testSpeaker.implicitWidth === 260, "Speaker implicitWidth should be 260");
        assert(testSpeaker.dynamicElements.length >= 24, "Speaker must have dynamic jumping notes and music dots");
        assert(testSpeaker.dynamicElements[0].color === "#FFD600", "First element must be golden yellow");
        assert(testSpeaker.speakerRadius > 50, "Speaker radius must be appropriately scaled");

        // 11. Visualizer Pause Contract Verification
        testSpeaker.isPlaying = false;
        assert(testSpeaker.audioEnergy === 0.0, "Speaker audioEnergy must be 0.0 when paused");
        assert(testSpeaker.audioBeat === 0.0, "Speaker audioBeat must be 0.0 when paused");

        // In testRoot, testRing.isPlaying defaults to false (no MprisMedia playing)
        assert(testRing.audioEnergy === 0.0, "CoverRing audioEnergy must be 0.0 when paused");
        assert(testRing.audioBeat === 0.0, "CoverRing audioBeat must be 0.0 when paused");

        mockVisualizer.isPlaying = true;
        mockVisualizer.energy = 0.002; // Below 0.005 noise threshold
        mockVisualizer.beat = 0.0;
        var isActiveWithNoise = mockVisualizer.isPlaying && (mockVisualizer.energy > 0.005 || mockVisualizer.beat > 0.005);
        assert(!isActiveWithNoise, "Visualizer must not activate on near-zero noise floor <= 0.005");

        mockVisualizer.energy = 0.45;
        var isActiveWithMusic = mockVisualizer.isPlaying && (mockVisualizer.energy > 0.005 || mockVisualizer.beat > 0.005);
        assert(isActiveWithMusic, "Visualizer must activate when energy > 0.005");

        // 12. Wine Player Ground-Truth Audio Arbitration Contract
        function isWinePlayerCheck(p) {
            if (!p) return false;
            let bus = p.dbusName || "";
            let id = p.identity || "";
            return bus.indexOf("cloudmusic") !== -1 || id.indexOf("NetEase") !== -1 || id.indexOf("Wine") !== -1;
        }

        function isPlayerPlayingCheck(p, vis) {
            if (!p) return false;
            if (isWinePlayerCheck(p)) {
                if (typeof vis !== "undefined" && vis) {
                    return (vis.active === true || vis.energy > 0.005 || vis.beat > 0.005);
                }
            }
            if (p.isPlaying === true) return true;
            if (p.playbackState === 1) return true;
            return false;
        }

        var wineMockPlayer = {
            dbusName: "org.mpris.MediaPlayer2.cloudmusic",
            identity: "NetEase Cloud Music",
            playbackState: 1, // Stale DBus state "Playing" from when music was active
            isPlaying: true
        };

        // Sub-threshold decay energy (e.g. 0.002) must be treated as silent (false)
        mockVisualizer.energy = 0.002;
        mockVisualizer.beat = 0.000;
        mockVisualizer.active = false;
        assert(!isPlayerPlayingCheck(wineMockPlayer, mockVisualizer), "Wine player with sub-threshold decay energy (0.002) must evaluate to false, not fall through to DBus state");

        // Complete silence (0.0) must evaluate to false
        mockVisualizer.energy = 0.000;
        mockVisualizer.beat = 0.000;
        mockVisualizer.active = false;
        assert(!isPlayerPlayingCheck(wineMockPlayer, mockVisualizer), "Wine player with 0.0 energy must evaluate to false, ignoring stale DBus playbackState=1");

        // Active acoustic energy (> 0.005) must evaluate to true
        mockVisualizer.energy = 0.420;
        mockVisualizer.beat = 0.150;
        mockVisualizer.active = true;
        assert(isPlayerPlayingCheck(wineMockPlayer, mockVisualizer), "Wine player with active acoustic energy (> 0.005) must evaluate to true");

        console.log("PASS: All Audio Heatmap Cover tests passed successfully!");
        Qt.exit(0);
    }
}
