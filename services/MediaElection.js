.pragma library

// Which media player does the shell show?
//
// Kept out of MprisMedia.qml so the decision can be exercised directly by the
// offscreen suite: the service itself is a Quickshell singleton bound to live
// D-Bus and PipeWire state, and a test that only greps its source cannot tell
// whether the *decision* is right.
//
// Two independent signals describe a player:
//
//   * `talking`  - the sound server says this player owns an uncorked, unmuted
//                  stream. Ground truth about *who could* be heard.
//   * `claim`    - the player's own MPRIS playback state. Ground truth about
//                  *what the application thinks it is doing*.
//
// Neither is sufficient. A paused browser never releases its PipeWire node, so
// it keeps "talking" forever; the Wine bridge can report a stale claim because
// Wine emits no native D-Bus playback signals. Combining them is what makes the
// widget agree with the user's ears.

/// Normalise a MPRIS playback claim to `playing` / `paused` / `stopped`.
///
/// Accepts the enum Quickshell reports (`0` stopped, `1` playing, `2` paused),
/// the strings D-Bus exposes, and booleans for callers that already resolved it.
function claimState(claim) {
    if (claim === undefined || claim === null) return "";
    if (claim === true) return "playing";
    if (claim === false) return "paused";
    var text = String(claim).trim().toLowerCase();
    if (text === "playing" || text === "1") return "playing";
    if (text === "paused" || text === "2") return "paused";
    if (text === "stopped" || text === "0") return "stopped";
    return "";
}

function claimsPlaying(claim) {
    return claimState(claim) === "playing";
}

/// Whether a player is *positively* playing: it says Playing AND owns a stream.
///
/// This is the only evidence strong enough to move the widget. Either signal
/// alone has been observed lying on a live session:
///   * a paused Edge tab keeps two uncorked, unmuted streams alive forever;
///   * Wine's MPRIS bridge drops `Playing` back to `Paused` on its own.
/// Requiring both means an idle stream can never capture the widget, and a
/// stale claim can never do it either.
function isPositive(candidate) {
    return !!(candidate && candidate.talking === true && claimsPlaying(candidate.claim));
}

/// Elect the player the widget should show.
///
/// `candidates` is `[{ busName, talking, claim }]` in presentation order.
/// `currentBus` is what the widget is showing now (or null); `stickyBus` is the
/// last player observed to be positively playing (or null).
///
/// Returns an index into `candidates`, or -1 to mean "keep what you have".
///
/// 1. **Positive evidence wins.** A player that claims Playing and owns a
///    stream is unambiguous - show it, and it becomes the remembered one.
/// 2. **History corrects drift.** A remembered winner whose stream is still
///    alive takes the widget back. Without this, a single ambiguous moment
///    stranded the widget on a paused browser tab and nothing could undo it.
/// 3. **Otherwise ambiguity never switches.** If the current selection is still
///    present, keep it: the old code fell through to "first stream owner" and
///    showed a paused Edge tab while music was audible.
/// 4. **Last resort.** Exactly one stream owner, otherwise nothing.
function resolveSelection(candidates, currentBus, stickyBus) {
    if (!candidates || candidates.length === 0) return -1;

    // 1. Positive evidence.
    for (var i = 0; i < candidates.length; i++) {
        if (isPositive(candidates[i])) return i;
    }

    // 2. A remembered winner with a live stream corrects a wrong current
    //    selection. This is what actually showed music instead of an idle
    //    browser tab: the widget had drifted to Edge during an ambiguous
    //    moment, and only the memory of "NetEase was playing" can undo that.
    if (stickyBus && stickyBus !== currentBus) {
        for (var k = 0; k < candidates.length; k++) {
            if (candidates[k].busName === stickyBus && candidates[k].talking === true) return k;
        }
    }

    // 3. Otherwise keep the current selection while it is still on the bus.
    if (currentBus) {
        for (var j = 0; j < candidates.length; j++) {
            if (candidates[j].busName === currentBus) return j;
        }
    }

    // 4. Cold start: only when exactly one application owns a stream, which
    //    leaves nothing to choose between. Two owners is an ambiguity.
    var owner = -1;
    var owners = 0;
    for (var m = 0; m < candidates.length; m++) {
        if (candidates[m].talking === true) {
            owners++;
            owner = m;
        }
    }
    return owners === 1 ? owner : -1;
}

/// The player to remember after a snapshot: only positive evidence counts.
///
/// An ambiguous snapshot must NOT overwrite the memory, otherwise one flaky
/// `Paused` from the Wine bridge would erase the player we know is playing, and
/// the next ambiguity would fall back to guessing.
function stickyWinner(players) {
    if (!players) return null;
    for (var i = 0; i < players.length; i++) {
        if (isPositive(players[i])) return players[i].busName || null;
    }
    return null;
}

/// Build the candidate list from players, given an audibility predicate.
///
/// `isAudible(identity, busName)` is injected so this module never reaches into
/// the sound-server matcher itself.
function candidatesFrom(players, isAudible) {
    var out = [];
    if (!players) return out;
    for (var i = 0; i < players.length; i++) {
        var p = players[i];
        if (!p) continue;
        var identity = p.identity || "";
        var busName = p.dbusName || "";
        out.push({
            identity: identity,
            busName: busName,
            talking: isAudible ? isAudible(identity, busName) === true : false,
            claim: p.playbackState
        });
    }
    return out;
}

/// Recover the player for an election index (null when nothing won).
function winnerFrom(players, index) {
    if (!players || index < 0 || index >= players.length) return null;
    return players[index];
}
