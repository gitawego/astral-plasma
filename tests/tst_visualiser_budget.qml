import QtQuick
import "../components/motion"

// ============================================================================
// Audio-visualiser frame budget
// ============================================================================
// The daemon streams spectrum data at audio rate (tens of updates per second).
// Every visualiser component bound to `AudioVisualizer.bands`/`energy`/`beat`
// directly, so each stream frame re-evaluated 40+ bound bars and repainted the
// host surface - the dashboard and media tabs measured ~80 % of a CPU core each,
// and a continuously updating glass surface also costs the compositor a blur of
// the whole region at that rate.
//
// The stream is ground truth; the *presentation* is decoration. `AudioVisualizer`
// therefore mirrors the stream onto the shared MotionClock (`displayBands` and
// friends) at `Theme.decorativeMaxFps`, and every visualiser reads the mirror.
Item {
    id: testRoot
    width: 600
    height: 400

    property string serviceSource: ""
    property string consumersSource: ""
    property int ticks: 0
    property int clockTicks: 0

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

    MotionTick {
        id: probeTick
        running: true
    }

    Connections {
        target: probeTick
        function onTicked() { testRoot.ticks++; }
    }

    Connections {
        target: MotionClock
        function onTickChanged() { testRoot.clockTicks++; }
    }

    // ---------------------------------------------------------------- phase 1 --
    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: {
            const budget = MotionClock.frameBudget;
            const budgeted = Math.ceil((budget * 500) / 1000) + 3;
            testRoot.assert(testRoot.ticks > 0, "a running MotionTick must tick");
            testRoot.assert(
                testRoot.ticks <= budgeted,
                "a MotionTick must not advance faster than the decorative budget (ticks=" +
                    testRoot.ticks + ", budget<=" + budgeted + ")"
            );
            testRoot.assert(
                testRoot.ticks <= testRoot.clockTicks + 1,
                "a MotionTick must emit per clock frame, never one per display frame"
            );

            probeTick.running = false;
            phaseTwo.start();
        }
    }

    Timer {
        id: phaseTwo
        interval: 60
        running: false
        repeat: false
        onTriggered: {
            testRoot.assert(
                MotionClock.consumers === 0,
                "a stopped MotionTick must release the clock (consumers=" + MotionClock.consumers + ")"
            );
            sourceContracts();
        }
    }

    // ---------------------------------------------------------------- phase 2 --
    function sourceContracts() {
        testRoot.serviceSource = readLocalFile("../services/AudioVisualizer.qml");

        const service = testRoot.serviceSource;
        testRoot.assert(service.length > 0, "AudioVisualizer.qml must be readable");
        testRoot.assert(
            service.indexOf("property var displayBands") !== -1 &&
                service.indexOf("property real displayEnergy") !== -1 &&
                service.indexOf("property real displayBeat") !== -1,
            "the service must expose clock-paced mirrors of the stream"
        );
        testRoot.assert(
            service.indexOf("MotionTick") !== -1,
            "the mirrors must advance on the shared clock, not on stream frames"
        );
        testRoot.assert(
            /displayBands\s*=\s*(root\.)?bands/.test(service),
            "the mirror must be a sample of the real band data"
        );
        testRoot.assert(
            /bands\s*=\s*data\.bands\.slice\(\)/.test(service),
            "the stream must still write ground-truth data into `bands`"
        );

        // Every visualiser draws from the mirror; none may bind to the raw stream.
        const components = [
            "RadialCoverRing",
            "RadialCoverVisualiser",
            "HeatmapCoverRing",
            "HeatmapSpeakerPlayer",
            "VinylPlayer",
        ];
        let mirrored = 0;
        for (const name of components) {
            const src = readLocalFile("../components/" + name + ".qml");
            testRoot.assert(src.length > 0, name + ".qml must be readable");
            for (const raw of ["bands", "energy", "beat", "bass", "treble"]) {
                testRoot.assert(
                    src.indexOf("AudioVisualizer." + raw) < 0,
                    name + " must read AudioVisualizer.display" + raw[0].toUpperCase() + raw.substring(1) +
                        " instead of the raw stream value"
                );
            }
            if (src.indexOf("AudioVisualizer.display") !== -1) {
                mirrored++;
            }
        }
        testRoot.assert(
            mirrored === components.length,
            "every visualiser must draw from the clock-paced mirror (found " + mirrored + ")"
        );

        // The playback-detection logic in MprisMedia legitimately needs the truth,
        // and is the one place allowed to read it.
        const mpris = readLocalFile("../services/MprisMedia.qml");
        if (mpris.length > 0) {
            testRoot.assert(mpris.indexOf("MotionTick") < 0, "MprisMedia must not hold the decorative clock");
        }

        console.log("PASS: visualiser frame budget (" + testRoot.ticks + " ticks in 500 ms at " +
            MotionClock.frameBudget + " fps)");
        Qt.exit(0);
    }
}
