import QtQuick
import "../components"

// ============================================================================
// Audio Stream Arbitration
// ============================================================================
// "Which player is playing" is decided by the sound server, not by MPRIS claims:
// a browser keeps reporting Playing for background tabs, muted videos and pages
// that were closed long ago, which is how a stale browser session used to
// outrank the music that was actually audible.
//
// The matcher maps the daemon's audible streams onto players, generically - no
// per-application table. (The stream parsing itself is pinned by
// daemon/tests/test_audio_streams.rs.)
Item {
    id: testRoot
    width: 800
    height: 600

    // The live case that motivated this: only NetEase Cloud Music is producing
    // sound; the Edge stream is corked (a background tab) and Haruna is muted.
    AudioStreamMatcher {
        id: matcher
        streams: [
            { name: "NetEase Cloud Music", binary: "wine-preloader" }
        ]
    }

    function assert(condition, message) {
        if (!condition) {
            console.log("FAIL: " + message);
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
        console.log("RUNNING: Audio Stream Arbitration");

        // The audible music matches the Wine bridge's player.
        assert(matcher.isAudible("NetEase Cloud Music (Wine)", "org.mpris.MediaPlayer2.cloudmusic"),
            "the audible player must be recognised as playing");

        // A browser session that claims Playing owns no audible stream here, so
        // it is not playing - the bug the user hit.
        assert(!matcher.isAudible("Microsoft Edge", "org.mpris.MediaPlayer2.edge.instance3710"),
            "a silent browser session must not count as playing");
        assert(!matcher.isAudible("Haruna", "org.mpris.MediaPlayer2.haruna"),
            "a muted player must not count as playing");

        // And the bridge can tell that the sound belongs to someone else.
        assert(matcher.someoneElseIsAudible("Microsoft Edge", "org.mpris.MediaPlayer2.edge.instance3710"),
            "the Wine bridge must pause when another application owns the sound");
        assert(!matcher.someoneElseIsAudible("NetEase Cloud Music (Wine)", "org.mpris.MediaPlayer2.cloudmusic"),
            "and must not pause for its own stream");

        // When the audible application is a browser, the browser wins.
        const edgeAudible = Qt.createQmlObject(
            'import QtQuick; import "../components"; AudioStreamMatcher { streams: [{ name: "Microsoft Edge", binary: "msedge" }] }',
            testRoot);
        assert(edgeAudible.isAudible("Microsoft Edge", "org.mpris.MediaPlayer2.edge.instance3710"),
            "a browser that is really making sound is playing");
        assert(!edgeAudible.isAudible("NetEase Cloud Music (Wine)", "org.mpris.MediaPlayer2.cloudmusic"),
            "and the silent music player is not");

        // Unattributed audio (a game, a generic stream name) matches nobody, so
        // the caller falls back to the players' own claims instead of reporting
        // that nothing is playing.
        const unknown = Qt.createQmlObject(
            'import QtQuick; import "../components"; AudioStreamMatcher { streams: [{ name: "audio-src", binary: "wine-preloader" }] }',
            testRoot);
        assert(!unknown.isAudible("NetEase Cloud Music (Wine)", "org.mpris.MediaPlayer2.cloudmusic"),
            "a generic stream name must not be guessed onto a player");

        console.log("PASS: Audio Stream Arbitration (audible streams decide, claims do not)");
        Qt.exit(0);
    }
}
