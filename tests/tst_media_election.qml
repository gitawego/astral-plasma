import QtQuick
import "../services/MediaElection.js" as Election

/// Which player does the media widget show?
///
/// Ground truth captured from the live session: Edge keeps TWO uncorked streams
/// alive with a paused x.com tab, NetEase Cloud Music (Wine) keeps one. All three
/// nodes report `running` to PipeWire whether or not sound flows, and Wine's
/// bridge flips `Playing` -> `Paused` on its own. So neither "owns a stream" nor
/// "claims Playing" is reliable in isolation.
///
/// The rule therefore switches only on POSITIVE evidence (claims Playing *and*
/// owns a stream), never switches on ambiguity, and remembers the last player it
/// saw with that evidence so a flaky claim cannot hand the widget to an idle
/// browser. These cases are the live snapshots, not invented ones.
Item {
    id: testRoot
    width: 400
    height: 400

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    // Live players, in the order MPRIS reported them (Edge first).
    function players(edgeClaim, netClaim, edgeTalking, netTalking) {
        return [
            { identity: "Microsoft Edge", dbusName: "org.mpris.MediaPlayer2.plasma-browser-integration",
              playbackState: edgeClaim },
            { identity: "NetEase Cloud Music (Wine)", dbusName: "org.mpris.MediaPlayer2.cloudmusic",
              playbackState: netClaim }
        ];
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function name(p) { return p ? p.identity : null; }

    // Turn the live MPRIS shape into the candidate list the rule consumes,
    // exactly as MprisMedia does with the sound server's verdict.
    function candidates(edgeClaim, netClaim, edgeTalking, netTalking) {
        return Election.candidatesFrom(players(edgeClaim, netClaim, edgeTalking, netTalking),
            function (identity) {
                return identity.indexOf("Edge") !== -1 ? edgeTalking : netTalking;
            });
    }

    function runTests() {
        console.log("RUNNING: Media Election (positive evidence, sticky, never ambiguous)");

        // ---- claim normalisation, from observed values -------------------
        // Live: NetEase Playing + isPlaying=true reported playbackState 1;
        // Edge Paused + isPlaying=false reported 2.
        assert(Election.claimsPlaying(1), "Quickshell playbackState 1 is Playing (observed live)");
        assert(!Election.claimsPlaying(2), "Quickshell playbackState 2 is Paused (observed live)");
        assert(Election.claimsPlaying("Playing"), "the D-Bus string 'Playing' is playing");
        assert(!Election.claimsPlaying(undefined), "a missing claim never counts as playing");

        // ---- THE BUG: both own streams, both claim Paused ----------------
        // Edge sits on a paused x.com tab; Wine's bridge dropped its claim.
        var snap = candidates(2, 2, true, true);
        var r = Election.resolveSelection(snap, null, null);
        // No positive evidence and no history: nothing may be invented.
        assert(r === -1, "with no positive evidence and no history, nothing is elected (got " + r + ")");

        // With history (music played a moment ago), the widget keeps the music
        // instead of falling to the first idle stream owner - the x.com bug.
        r = Election.resolveSelection(snap, null, "org.mpris.MediaPlayer2.cloudmusic");
        assert(r === 1, "the last positively-playing player must win an ambiguous tie (got " + name(snap[r]) + ")");

        // And it must also take over from a wrong current selection.
        r = Election.resolveSelection(snap, "org.mpris.MediaPlayer2.plasma-browser-integration",
                                      "org.mpris.MediaPlayer2.cloudmusic");
        assert(r === 1, "history must correct a wrong current selection (got " + name(snap[r]) + ")");

        // ---- POSITIVE EVIDENCE binds ------------------------------------
        // NetEase claims Playing and owns a stream -> it wins, history or not.
        r = Election.resolveSelection(candidates(2, 1, true, true), null, null);
        assert(r === 1, "a player that claims Playing and owns a stream wins outright");

        // A player that claims Playing but owns NOTHING must never be elected on
        // that claim alone. (The single owner may still be shown as a cold-start
        // fallback - what must not happen is the silent claimant winning.)
        r = Election.resolveSelection(candidates(2, 1, true, false), null, null);
        assert(r !== 1, "a claim without an owned stream must not win (got index " + r + ")");

        // ---- AMBIGUITY never switches ------------------------------------
        // Both genuinely claim Playing: keep what is already shown.
        r = Election.resolveSelection(candidates(1, 1, true, true),
                                      "org.mpris.MediaPlayer2.plasma-browser-integration", null);
        assert(r === 0, "when both are genuinely playing, the current selection is kept");

        // Current is still present and nothing better exists: keep it.
        r = Election.resolveSelection(candidates(2, 2, true, true),
                                      "org.mpris.MediaPlayer2.plasma-browser-integration", null);
        assert(r === 0, "with no positive evidence the current selection is kept");

        // ---- COLD START ---------------------------------------------------
        // Nothing current, nothing sticky, one owner: show it (best effort).
        r = Election.resolveSelection(candidates(2, 2, false, true), null, null);
        assert(r === 1, "cold start with a single stream owner shows that owner");
        // Cold start with no owners at all: nothing.
        r = Election.resolveSelection(candidates(2, 2, false, false), null, null);
        assert(r === -1, "cold start with no owners elects nobody");

        // ---- Sticky bookkeeping ------------------------------------------
        // Only a positively-playing player becomes the remembered one.
        assert(Election.stickyWinner(candidates(2, 1, true, true)) === "org.mpris.MediaPlayer2.cloudmusic",
            "the positively-playing player becomes the remembered winner");
        assert(Election.stickyWinner(candidates(2, 2, true, true)) === null,
            "an ambiguous snapshot must not overwrite the remembered winner");

        console.log("PASS: Media Election (positive evidence, sticky, never ambiguous)");
        Qt.exit(0);
    }
}
