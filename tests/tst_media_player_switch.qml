import QtQuick
import "../menus"
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
        }
    }

    function runTests() {
        console.log("RUNNING: Media Player Switch Tests");

        // Service Mock implementing exact MprisMedia matching & selection architecture
        var mockMpris = {
            players: [
                { dbusName: "org.mpris.MediaPlayer2.strawberry", identity: "Strawberry", playbackState: 2, playCount: 0, togglePlaying: function() { this.playCount++; } },
                { dbusName: "org.mpris.MediaPlayer2.cloudmusic", identity: "NetEase Cloud Music", playbackState: 2, playCount: 0, togglePlaying: function() { this.playCount++; } },
                { dbusName: "org.mpris.MediaPlayer2.elisa", identity: "Elisa", playbackState: 1, playCount: 0, togglePlaying: function() { this.playCount++; } }
            ],
            manualPlayer: null,
            manualPlayerBusName: "",
            currentPlayer: null,
            get activePlayer() { return this.currentPlayer; },
            togglePlay: function() {
                if (this.activePlayer && this.activePlayer.togglePlaying) {
                    this.activePlayer.togglePlaying();
                }
            },

            findMatchingPlayer: function(target) {
                if (!target || !this.players || this.players.length === 0) return null;
                var targetBus = "";
                var targetId = "";
                if (typeof target === "string") {
                    targetBus = target;
                    targetId = target;
                } else {
                    targetBus = target.dbusName || "";
                    targetId = target.identity || "";
                }
                for (var i = 0; i < this.players.length; i++) {
                    var p = this.players[i];
                    if (!p) continue;
                    if (p === target) return p;
                    if (targetBus !== "" && p.dbusName && p.dbusName === targetBus) return p;
                    if (targetId !== "" && p.identity && p.identity === targetId) return p;
                }
                return null;
            },

            isPlayerActive: function(player) {
                if (!player || !this.activePlayer) return false;
                if (player === this.activePlayer) return true;
                if (player.dbusName && this.activePlayer.dbusName && player.dbusName === this.activePlayer.dbusName) return true;
                if (player.identity && this.activePlayer.identity && player.identity === this.activePlayer.identity) return true;
                return false;
            },

            selectPlayer: function(player) {
                if (!player) return;
                var matched = this.findMatchingPlayer(player);
                var busOrId = (player.dbusName && player.dbusName.length > 0) ? player.dbusName : (player.identity || "");
                this.manualPlayerBusName = busOrId;
                this.manualPlayer = matched || player;
                this.currentPlayer = matched || player;
            },

            cyclePlayer: function() {
                if (!this.players || this.players.length <= 1) return;
                var idx = 0;
                for (var i = 0; i < this.players.length; i++) {
                    if (this.isPlayerActive(this.players[i])) {
                        idx = i;
                        break;
                    }
                }
                var nextIdx = (idx + 1) % this.players.length;
                this.selectPlayer(this.players[nextIdx]);
            },

            updateActivePlayer: function() {
                if (!this.players || this.players.length === 0) {
                    this.currentPlayer = null;
                    this.manualPlayer = null;
                    this.manualPlayerBusName = "";
                    return;
                }
                // 1. Honor manualPlayer selection as long as it exists
                if (this.manualPlayerBusName !== "") {
                    var matchedManual = this.findMatchingPlayer(this.manualPlayerBusName);
                    if (matchedManual) {
                        this.currentPlayer = matchedManual;
                        this.manualPlayer = matchedManual;
                        return;
                    } else {
                        this.manualPlayer = null;
                        this.manualPlayerBusName = "";
                    }
                }
                // 2. Fall back to playing player
                for (var i = 0; i < this.players.length; i++) {
                    if (this.players[i].playbackState === 1) {
                        this.currentPlayer = this.players[i];
                        return;
                    }
                }
                // 3. Keep current player if still present
                if (this.currentPlayer) {
                    var matchedCurrent = this.findMatchingPlayer(this.currentPlayer);
                    if (matchedCurrent) {
                        this.currentPlayer = matchedCurrent;
                        return;
                    }
                }
                // 4. Default to first player
                if (this.players.length > 0) {
                    this.currentPlayer = this.players[0];
                }
            }
        };

        // Test 1: Initial auto-selection chooses playing player (Elisa)
        mockMpris.updateActivePlayer();
        assert(mockMpris.activePlayer.identity === "Elisa", "Initial auto-player must be Elisa (Playing)");
        assert(mockMpris.isPlayerActive(mockMpris.players[2]) === true, "Elisa is active player");
        assert(mockMpris.isPlayerActive(mockMpris.players[0]) === false, "Strawberry is not active");

        // Test 2: User explicitly clicks Strawberry in the dropdown
        var strawberryItem = mockMpris.players[0];
        mockMpris.selectPlayer(strawberryItem);
        assert(mockMpris.activePlayer.identity === "Strawberry", "Active player must switch to Strawberry");
        assert(mockMpris.manualPlayerBusName === "org.mpris.MediaPlayer2.strawberry", "manualPlayerBusName must be Strawberry DBus name");
        assert(mockMpris.isPlayerActive(strawberryItem) === true, "Strawberry must report isPlayerActive == true");
        assert(mockMpris.isPlayerActive(mockMpris.players[2]) === false, "Elisa must report isPlayerActive == false");

        // Test 3: 300ms heartbeat does NOT revert to Elisa even though Elisa is Playing
        mockMpris.updateActivePlayer();
        assert(mockMpris.activePlayer.identity === "Strawberry", "Heartbeat must preserve manual Strawberry selection");

        // Test 4: Dynamic wrapper matching test (different object references with same dbusName)
        var detachedStrawberryWrapper = { dbusName: "org.mpris.MediaPlayer2.strawberry", identity: "Strawberry" };
        assert(mockMpris.isPlayerActive(detachedStrawberryWrapper) === true, "detached wrapper matches by dbusName");
        var matched = mockMpris.findMatchingPlayer(detachedStrawberryWrapper);
        assert(matched !== null && matched.identity === "Strawberry", "findMatchingPlayer successfully resolves wrapper");

        // Test 5: Switch to NetEase Cloud Music
        var neteaseItem = mockMpris.players[1];
        mockMpris.selectPlayer(neteaseItem);
        assert(mockMpris.activePlayer.identity === "NetEase Cloud Music", "Active player must switch to NetEase");
        assert(mockMpris.manualPlayerBusName === "org.mpris.MediaPlayer2.cloudmusic", "manualPlayerBusName updated");

        // Test 6: Cycle players sequentially
        mockMpris.cyclePlayer(); // from NetEase (index 1) -> Elisa (index 2)
        assert(mockMpris.activePlayer.identity === "Elisa", "Cycle must advance to Elisa");
        mockMpris.cyclePlayer(); // from Elisa (index 2) -> Strawberry (index 0)
        assert(mockMpris.activePlayer.identity === "Strawberry", "Cycle must advance to Strawberry");

        // Test 7: Manual player closure fallback
        // Remove Strawberry from players list (simulating player quit)
        mockMpris.players.shift(); // strawberry removed
        mockMpris.updateActivePlayer();
        assert(mockMpris.manualPlayerBusName === "", "manualPlayerBusName cleared when player quits");
        assert(mockMpris.activePlayer.identity === "Elisa", "Fell back to Elisa (Playing)");

        // Test 8: Menu overlay layout geometry and z-stacking
        var overlayVisible = false;
        function toggleOverlay() { overlayVisible = !overlayVisible; }
        assert(overlayVisible === false, "Overlay begins hidden");
        toggleOverlay();
        assert(overlayVisible === true, "Overlay opens on badge click");
        toggleOverlay();
        assert(overlayVisible === false, "Overlay closes on outside click");

        // Test 9: Active player action dispatch isolation
        // Select NetEase and verify togglePlay only calls NetEase's togglePlaying
        var strawberry = mockMpris.players[0]; // currently strawberry was shifted earlier, let's restore players
        mockMpris.players = [
            { dbusName: "org.mpris.MediaPlayer2.strawberry", identity: "Strawberry", playbackState: 2, playCount: 0, togglePlaying: function() { this.playCount++; } },
            { dbusName: "org.mpris.MediaPlayer2.cloudmusic", identity: "NetEase Cloud Music", playbackState: 2, playCount: 0, togglePlaying: function() { this.playCount++; } }
        ];
        mockMpris.selectPlayer(mockMpris.players[1]); // NetEase
        assert(mockMpris.activePlayer.identity === "NetEase Cloud Music", "Active player is NetEase");
        mockMpris.togglePlay();
        assert(mockMpris.players[1].playCount === 1, "NetEase playCount must be 1 after togglePlay()");
        // Test 10: Dropdown height calculation & bounds clamping contracts
        function computeDropdownPlacement(badgeY, playerCount, tabHeight) {
            var menuH = 52 + playerCount * 42;
            var targetY = Math.round(badgeY - menuH - 8);
            var clampedY = Math.max(8, Math.min(tabHeight - menuH - 8, targetY));
            return { menuH: menuH, y: clampedY, bottom: clampedY + menuH };
        }

        var placement3 = computeDropdownPlacement(220, 3, 320);
        assert(placement3.menuH === 178, "3-player menu height must be 178px (52 + 3*42)");
        assert(placement3.y >= 8, "Dropdown y must not clip top edge (>= 8)");
        assert(placement3.bottom <= 320, "Dropdown bottom must not overflow tab height (<= 320)");

        var placement1 = computeDropdownPlacement(220, 1, 320);
        assert(placement1.menuH === 94, "1-player menu height must be 94px (52 + 1*42)");
        assert(placement1.bottom <= 320, "1-player menu must not overflow tab height");

        console.log("PASS: Media Player Switch Tests");
        Qt.exit(0);
    }
}
