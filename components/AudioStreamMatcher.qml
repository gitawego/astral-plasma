import QtQuick

/// Matches MPRIS players to the applications that are producing audio.
///
/// MPRIS playback state is a claim: a browser media session keeps reporting
/// `Playing` for a background tab, a muted video, or a page that was closed long
/// ago. The sink inputs (see `astral-plasma audio streams`) are the ground truth,
/// and this maps them onto players.
///
/// The match is generic by construction - a normalized containment either way,
/// so "Microsoft Edge" matches `msedge` and "NetEase Cloud Music (Wine)" matches
/// "NetEase Cloud Music" without any per-application table.
Item {
    id: root

    /// `[{ name, binary }]` from the daemon.
    property var streams: []

    function normalize(value) {
        return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function matches(stream, identity, busName) {
        if (!stream) return false;
        const candidates = [normalize(stream.name), normalize(stream.binary)].filter(c => c.length >= 3);
        const players = [normalize(identity), normalize(busName)].filter(p => p.length >= 3);
        for (let i = 0; i < candidates.length; i++) {
            for (let j = 0; j < players.length; j++) {
                if (candidates[i].indexOf(players[j]) !== -1 || players[j].indexOf(candidates[i]) !== -1) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Whether this player owns an application that is making sound.
    function isAudible(identity, busName) {
        if (!streams) return false;
        for (let i = 0; i < streams.length; i++) {
            if (matches(streams[i], identity, busName)) return true;
        }
        return false;
    }

    /// Whether the sound belongs to something other than this player.
    function someoneElseIsAudible(identity, busName) {
        if (!streams || streams.length === 0) return false;
        return !isAudible(identity, busName);
    }
}
