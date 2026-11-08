import QtQuick
import "../modules/Astral/Kernel/Host"

// ============================================================================
// MediaPort
// ============================================================================
// A migrated media surface cannot read `MprisMedia` (a Loader-loaded component gets
// its own instance, spec C.10), so the shell fills this port and injects it.
//
// What is asserted: the empty state is honest (no fabricated track), data reaches
// the surface, operations reach the shell with their arguments, a seek is clamped,
// and an unsupported or throwing operation is a stated failure.
Item {
    id: testRoot
    width: 400
    height: 300

    property var failures: []

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function run() {
        const port = Qt.createQmlObject(
            'import QtQuick; import "../modules/Astral/Kernel/Host"; MediaPort { }',
            testRoot, "media");
        port.operationFailed.connect(function (operation, reason) {
            failures.push({ operation: operation, reason: reason });
        });

        // ---- idle: nothing invented -----------------------------------------
        assert(!port.hasMedia, "no media until the shell says so");
        assert(port.title === "" && port.artist === "" && port.artUrl === "",
            "an idle port carries no track, not a placeholder track");
        assert(port.status === "stopped", "idle means stopped");
        assert(port.progress === 0, "no progress without a track");
        assert(port.players.length === 0, "no players listed yet");

        // ---- the shell publishes a track ------------------------------------
        port.hasMedia = true;
        port.title = "恭喜发财";
        port.artist = "刘德华";
        port.album = "经典";
        port.artUrl = "image://mpris/art";
        port.status = "playing";
        port.playerName = "NetEase Cloud Music";
        port.position = 60;
        port.length = 240;
        port.players = [{ id: "net", name: "NetEase Cloud Music" }];
        port.activePlayerId = "net";

        assert(port.hasMedia && port.title === "恭喜发财", "the track reaches the surface");
        assert(Math.abs(port.progress - 0.25) < 1e-6, "progress derives from position/length, got " + port.progress);
        assert(port.players.length === 1 && port.activePlayerId === "net", "the player list is available");

        // A zero-length track must not divide by zero.
        port.length = 0;
        assert(port.progress === 0, "no length means no progress");
        port.length = 240;

        // ---- unsupported operations say so -----------------------------------
        assert(port.toggle() === false, "toggle is unsupported until the shell fills it");
        assert(failures.length === 1 && failures[0].operation === "toggle", "and the failure names it");

        // ---- operations reach the shell --------------------------------------
        let toggled = 0;
        let skipped = 0;
        let sought = -1;
        let selected = "";
        port.toggleImpl = function () { toggled++; };
        port.nextImpl = function () { skipped++; };
        port.seekImpl = function (fraction) { sought = fraction; };
        port.selectPlayerImpl = function (id) { selected = id; };

        assert(port.canToggle && port.canSkip && port.canSeek && port.canSelectPlayer,
            "capabilities are advertised once supplied");
        assert(port.toggle(), "toggle works");
        assert(port.next(), "next works");
        assert(port.seek(0.5), "seek works");
        assert(port.selectPlayer("net"), "player selection works");
        assert(toggled === 1 && skipped === 1, "the shell received the commands");
        assert(Math.abs(sought - 0.5) < 1e-6, "seek passed the fraction");

        // Out-of-range seeks are clamped, so a surface cannot ask for 340%.
        assert(port.seek(3.4), "an overshooting seek is accepted");
        assert(sought === 1, "and clamped to the end, got " + sought);
        assert(port.seek(-2), "a negative seek is accepted");
        assert(sought === 0, "and clamped to the start, got " + sought);
        assert(selected === "net", "the player id reached the shell");

        // ---- a throwing implementation is contained --------------------------
        port.previousImpl = function () { throw new Error("player vanished"); };
        assert(port.previous() === false, "a throwing implementation returns false");
        assert(failures.some(function (item) { return item.operation === "previous"; }),
            "and is reported");

        port.destroy();
        console.log("PASS: All media port tests passed!");
        Qt.exit(0);
    }

    Component.onCompleted: run()
}
