import QtQuick
import "../modules/Astral/Kernel/components"

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

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

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

        // A paused player keeps its stream open (uncorked, unmuted), so ownership
        // alone must not count as playing - the audio has to be flowing.
        assert(!matcher.isPlaying("NetEase Cloud Music (Wine)", "org.mpris.MediaPlayer2.cloudmusic", false),
            "a paused player must not be reported as playing");
        assert(matcher.isPlaying("NetEase Cloud Music (Wine)", "org.mpris.MediaPlayer2.cloudmusic", true),
            "the audible player is playing while sound is flowing");
        assert(!matcher.isPlaying("Microsoft Edge", "org.mpris.MediaPlayer2.edge.instance3710", true),
            "a silent session is not playing even while other audio flows");

        // When the audible application is a browser, the browser wins.
        const edgeAudible = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/components"; AudioStreamMatcher { streams: [{ name: "Microsoft Edge", binary: "msedge" }] }',
            testRoot);
        assert(edgeAudible.isAudible("Microsoft Edge", "org.mpris.MediaPlayer2.edge.instance3710"),
            "a browser that is really making sound is playing");
        assert(!edgeAudible.isAudible("NetEase Cloud Music (Wine)", "org.mpris.MediaPlayer2.cloudmusic"),
            "and the silent music player is not");

        // Unattributed audio (a game, a generic stream name) matches nobody, so
        // the caller falls back to the players' own claims instead of reporting
        // that nothing is playing.
        const unknown = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/components"; AudioStreamMatcher { streams: [{ name: "audio-src", binary: "wine-preloader" }] }',
            testRoot);
        assert(!unknown.isAudible("NetEase Cloud Music (Wine)", "org.mpris.MediaPlayer2.cloudmusic"),
            "a generic stream name must not be guessed onto a player");

        // ------------------------------------------------------------------
        // Several applications can hold an uncorked, unmuted stream at once.
        // A paused consumer keeps its node open (browsers never cork on pause),
        // so "owns a stream" is not "produces sound". On this user's box Edge
        // keeps two uncorked streams alive while paused, and the election
        // promoted Edge over the NetEase music that was actually audible.
        //
        // The player's own playback claim is the only per-player signal that
        // separates them, so it must arbitrate *between* claimants: a player
        // that claims Paused cannot win an election while another player that
        // owns a stream claims Playing.
        // ------------------------------------------------------------------
        // The claim-aware election itself lives in services/MediaElection.js
        // (pinned by tests/tst_media_election.qml) so the service and the suite
        // share one implementation rather than a copy. What this suite still
        // owns is *ownership*: an uncorked stream is reported for every client
        // that holds one, which is why ownership alone cannot elect.
        const multi = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/components"; AudioStreamMatcher { streams: ['
            + '{ name: "Microsoft Edge", binary: "msedge" },'
            + '{ name: "NetEase Cloud Music", binary: "wine-preloader" }] }',
            testRoot);
        assert(multi.isAudible("Microsoft Edge", "org.mpris.MediaPlayer2.plasma-browser-integration"),
            "an open stream still counts for *ownership* (it is what the sound server reports)");
        assert(multi.isAudible("NetEase Cloud Music (Wine)", "org.mpris.MediaPlayer2.cloudmusic"),
            "both applications own a stream at once - the case that broke the election");

        const mpris = readLocalFile("../modules/Astral/Kernel/services/MprisMedia.qml");
        const election = readLocalFile("../modules/Astral/Kernel/services/MediaElection.js");
        assert(/import "MediaElection.js" as MediaElection/.test(mpris),
            "MprisMedia must import the shared election module");
        assert(/MediaElection\.resolveSelection\(/.test(mpris),
            "the election must delegate to MediaElection.resolveSelection");
        const helpers = (mpris.match(/resolveElectedPlayer\(\)/g) || []).length;
        assert(helpers >= 3,
            "both election sites must go through resolveElectedPlayer, found " + helpers);
        assert(!/if\s*\(\s*!isWinePlayer\(p\)\s*&&\s*isPlayerPlaying\(p\)\)\s*\{\s*winner/.test(mpris),
            "the old 'first non-Wine owner' shortcut must be gone (it let a paused browser win)");
        assert(/function resolveSelection\(/.test(election),
            "the election rule must be defined once, in MediaElection.js");
        assert(/function stickyWinner\(/.test(election),
            "the sticky memory must live with the rule");
        assert(!/audioArbitrationAvailable[\s\S]{0,80}electAudible/.test(mpris),
            "the election must not be gated on the dashboard-only audio arbitration");

        // The flow gate must not wait for a long hold: a pause stops the samples,
        // which the capture reports as exact 0.0, while a quiet passage still
        // reports some energy.
        const media = readLocalFile("../modules/Astral/Kernel/services/MprisMedia.qml");
        assert(/interval:\s*250/.test(media),
            "the audio-flow gate must poll fast enough to feel immediate");
        assert(/silentSinceMs[\s\S]{0,120}350/.test(media),
            "a pause must be confirmed within a few frames, not seconds");
        assert(!/2500/.test(media),
            "the old multi-second hold is what made a pause take 2-3s to show");

        console.log("PASS: Audio Stream Arbitration (audible streams decide, claims do not)");
        Qt.exit(0);
    }
}
