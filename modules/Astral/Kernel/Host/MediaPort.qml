import QtQuick

// ============================================================================
// MediaPort — the now-playing model a surface may read and drive
// ============================================================================
// The third port (after `ShellState` and `SessionPort`), and for the same reason: a
// component loaded through a Loader gets its own kernel singleton instances, so a
// migrated media surface that imported `MprisMedia` would see a player that never
// changes (spec C.9/C.10).
//
// The shell fills this from its own media service and injects it. Data is plain
// properties (QML notifies on assignment); operations are callables that default to
// `null`, so "this shell cannot do that" is a representable state rather than a
// silent no-op. Every call is contained.
QtObject {
    id: root

    // ---- data ---------------------------------------------------------------

    /// True when a player is elected and has media. A surface shows its empty state
    /// when false — there is no fabricated "nothing playing" track anywhere.
    property bool hasMedia: false
    property string title: ""
    property string artist: ""
    property string album: ""
    /// Artwork URL; empty when the player offers none.
    property string artUrl: ""
    /// `playing`, `paused`, or `stopped`.
    property string status: "stopped"
    /// Human name of the elected player (MPRIS identity).
    property string playerName: ""

    /// `enabled`, `track`, or `playlist` — the player's loop mode.
    property string loopState: "enabled"
    property bool shuffle: false
    property bool canGoNext: true
    property bool canGoPrevious: true

    property real position: 0
    property real length: 0
    readonly property real progress: length > 0 ? Math.min(1, Math.max(0, position / length)) : 0

    /// Playing, as a boolean, because that is what every surface actually asks. The port
    /// carries it explicitly: an app cannot read `MprisMedia`, and deriving it in each app
    /// from `status` invited a silent `undefined` (spec C.31) that gated playback state,
    /// the visualiser and the transport glyph all at once.
    readonly property bool isPlaying: status === "playing"

    // ---- audio reactivity ---------------------------------------------------
    // The visualiser's ground truth is the daemon's DSP stream. A migrated app cannot
    // import the `AudioVisualizer` singleton (the kernel is not mounted for apps), so the
    // shell samples it here and the app animates from what it is given. All zero when
    // nothing is playing: motion is never synthesised.
    property bool audioActive: false
    property real audioEnergy: 0
    property real audioBass: 0
    property real audioMid: 0
    property real audioTreble: 0
    property real audioBeat: 0
    property var audioBands: []

    /// Other players the user may switch to: `[{ id, name }]`.
    property var players: []
    /// The elected player's id, as listed in `players`.
    property string activePlayerId: ""

    // ---- operations (supplied by the shell) ---------------------------------

    property var toggleImpl: null
    property var nextImpl: null
    property var previousImpl: null
    property var seekImpl: null
    property var selectPlayerImpl: null
    property var toggleShuffleImpl: null
    property var cyclePlayerImpl: null
    property var cycleLoopImpl: null

    readonly property bool canToggle: toggleImpl !== null
    readonly property bool canSkip: nextImpl !== null
    readonly property bool canSeek: seekImpl !== null
    readonly property bool canSelectPlayer: selectPlayerImpl !== null
    readonly property bool canShuffle: toggleShuffleImpl !== null
    readonly property bool canCyclePlayer: cyclePlayerImpl !== null
    readonly property bool canCycleLoop: cycleLoopImpl !== null

    signal operationFailed(string operation, string reason)

    // ---- dispatch -----------------------------------------------------------

    function call(operation, impl, args) {
        if (typeof impl !== "function") {
            root.operationFailed(operation, "not supported by this shell");
            return false;
        }
        try {
            const result = impl.apply(null, args || []);
            return result === undefined ? true : !!result;
        } catch (error) {
            root.operationFailed(operation, String(error));
            return false;
        }
    }

    function toggle() {
        return call("toggle", toggleImpl, []);
    }

    function next() {
        return call("next", nextImpl, []);
    }

    function previous() {
        return call("previous", previousImpl, []);
    }

    /// Seek to a fraction of the track, clamped: a surface should not need to know
    /// whether the player can seek, only that asking is safe.
    function seekTo(fraction) {
        const value = Math.min(1, Math.max(0, Number(fraction) || 0));
        return call("seekTo", seekImpl, [value]);
    }

    function selectPlayer(playerOrId) {
        const id = (playerOrId && typeof playerOrId === "object")
            ? String(playerOrId.busName || playerOrId.id || "")
            : String(playerOrId || "");
        return call("selectPlayer", selectPlayerImpl, [id]);
    }

    /// The display name of a player entry (or id). Named `nameOf`, not `playerName`:
    /// a function and a property with one name collide, and the property wins.
    function nameOf(playerOrId) {
        if (playerOrId && typeof playerOrId === "object") {
            if (playerOrId.name) return String(playerOrId.name);
            if (playerOrId.identity) return String(playerOrId.identity);
            if (playerOrId.busName) return String(playerOrId.busName);
        }
        const id = typeof playerOrId === "string"
            ? playerOrId
            : (playerOrId && playerOrId.id ? String(playerOrId.id) : "");
        for (let index = 0; index < players.length; index++) {
            const entry = players[index];
            if (String(entry.id || entry.busName || "") === id) {
                return String(entry.name || entry.identity || id);
            }
        }
        return "";
    }

    /// Move to the next player the desktop knows (nothing when there is only one).
    function cyclePlayer() {
        return call("cyclePlayer", cyclePlayerImpl, []);
    }

    /// Cycle the elected player's loop mode (none → track → playlist).
    function cycleLoop() {
        return call("cycleLoop", cycleLoopImpl, []);
    }

    function toggleShuffle() {
        return call("toggleShuffle", toggleShuffleImpl, []);
    }
}
