import QtQuick

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
        console.log("RUNNING: Browser Media Arbitration Tests");

        // Service implementation replicating MprisMedia.qml architecture
        var service = {
            cleanTitle: function(rawTitle, rawArtist) {
                if (!rawTitle || rawTitle.length === 0) return "No Media Playing";
                var t = rawTitle.trim();
                t = t.replace(/^\(\d+\+?\)\s*/, "");
                t = t.replace(/\s*-\s*(YouTube|Bilibili|SoundCloud|Spotify)\s*$/i, "");
                if (rawArtist && rawArtist.length > 0 && rawArtist !== "Unknown Artist") {
                    var prefix = rawArtist.trim() + " - ";
                    if (t.toLowerCase().indexOf(prefix.toLowerCase()) === 0) {
                        t = t.slice(prefix.length).trim();
                    }
                } else {
                    var sepIdx = t.indexOf(" - ");
                    if (sepIdx === -1) sepIdx = t.indexOf(" | ");
                    if (sepIdx !== -1) {
                        var candidate = t.slice(sepIdx + 3).trim();
                        if (candidate.length > 0) t = candidate;
                    }
                }
                return t.length > 0 ? t : rawTitle;
            },

            cleanArtist: function(rawTitle, rawArtist, fallbackIdentity) {
                var a = (rawArtist && rawArtist.length > 0) ? rawArtist.trim() : "";
                if (a && a !== "Unknown Artist") {
                    return a;
                }
                if (rawTitle) {
                    var t = rawTitle.trim().replace(/^\(\d+\+?\)\s*/, "").replace(/\s*-\s*(YouTube|Bilibili|SoundCloud|Spotify)\s*$/i, "");
                    var sepIdx = t.indexOf(" - ");
                    if (sepIdx === -1) sepIdx = t.indexOf(" | ");
                    if (sepIdx !== -1) {
                        var extractedArtist = t.slice(0, sepIdx).trim();
                        if (extractedArtist.length > 0) {
                            return extractedArtist;
                        }
                    }
                }
                if (fallbackIdentity && fallbackIdentity !== "No Player" && fallbackIdentity !== "Media Player") {
                    return fallbackIdentity;
                }
                return "Unknown Artist";
            },

            isWinePlayer: function(p) {
                if (!p) return false;
                var bus = p.dbusName || "";
                var id = p.identity || "";
                return bus.indexOf("cloudmusic") !== -1 || id.indexOf("NetEase") !== -1 || id.indexOf("Wine") !== -1;
            },

            hasOtherNativePlayingPlayer: function(excludePlayer) {
                if (!this.players || this.players.length === 0) return false;
                for (var i = 0; i < this.players.length; i++) {
                    var other = this.players[i];
                    if (!other || other === excludePlayer) continue;
                    if (this.isWinePlayer(other)) continue;
                    if (other.isPlaying === true || other.playbackState === 1) {
                        return true;
                    }
                }
                return false;
            },

            isPlayerPlaying: function(p, visualizer) {
                if (!p) return false;
                if (this.isWinePlayer(p)) {
                    if (this.hasOtherNativePlayingPlayer(p)) {
                        return false;
                    }
                    if (visualizer && visualizer.isStreaming) {
                        return (visualizer.energy > 0.005 || visualizer.beat > 0.005);
                    }
                    if (p.isPlaying === true || p.playbackState === 1) {
                        return true;
                    }
                    return false;
                }
                if (p.playbackState === 2 || p.playbackState === 0) return false;
                if (p.isPlaying === true) return true;
                if (p.playbackState === 1) return true;
                return false;
            },

            filterPlayers: function(rawList) {
                var list = rawList || [];
                if (!list || list.length <= 1) return list;
                var hasPbi = false;
                for (var i = 0; i < list.length; i++) {
                    var p = list[i];
                    if (p && p.dbusName && p.dbusName.indexOf("plasma-browser-integration") !== -1) {
                        hasPbi = true;
                        break;
                    }
                }
                if (!hasPbi) return list;
                var res = [];
                for (var i = 0; i < list.length; i++) {
                    var p = list[i];
                    if (!p) continue;
                    if (p.dbusName && p.dbusName.indexOf(".instance") !== -1) {
                        continue;
                    }
                    res.push(p);
                }
                return res;
            },

            updateActivePlayer: function() {
                if (!this.players || this.players.length === 0) {
                    this.currentPlayer = null;
                    this.manualPlayer = null;
                    this.manualPlayerBusName = "";
                    return;
                }
                if (this.manualPlayerBusName !== "") {
                    for (var i = 0; i < this.players.length; i++) {
                        if (this.players[i].dbusName === this.manualPlayerBusName) {
                            this.currentPlayer = this.players[i];
                            return;
                        }
                    }
                    this.manualPlayer = null;
                    this.manualPlayerBusName = "";
                }
                var playingPlayer = null;
                for (var i = 0; i < this.players.length; i++) {
                    var p = this.players[i];
                    if (!this.isWinePlayer(p) && this.isPlayerPlaying(p, this.visualizer)) {
                        playingPlayer = p;
                        break;
                    }
                }
                if (!playingPlayer) {
                    for (var i = 0; i < this.players.length; i++) {
                        var p = this.players[i];
                        if (this.isPlayerPlaying(p, this.visualizer)) {
                            playingPlayer = p;
                            break;
                        }
                    }
                }
                if (playingPlayer) {
                    this.currentPlayer = playingPlayer;
                    return;
                }
                if (this.currentPlayer) {
                    return;
                }
                this.currentPlayer = this.players[0];
            },

            players: [],
            currentPlayer: null,
            manualPlayer: null,
            manualPlayerBusName: "",
            visualizer: { isStreaming: true, energy: 0.15, beat: 0.20 }
        };

        // 1. Title and Artist Cleaning Tests
        var t1 = service.cleanTitle("(4) Mylène Farmer - Des lois et des quoi (Clip Officiel) - YouTube", "Mylène Farmer");
        var a1 = service.cleanArtist("(4) Mylène Farmer - Des lois et des quoi (Clip Officiel) - YouTube", "Mylène Farmer", "Microsoft Edge");
        assert(t1 === "Des lois et des quoi (Clip Officiel)", "t1 must strip (4), - YouTube, and redundant artist prefix: got " + t1);
        assert(a1 === "Mylène Farmer", "a1 must retain Mylène Farmer: got " + a1);

        var t2 = service.cleanTitle("(99+) Heilung | Anoana [Official Video] - YouTube", "");
        var a2 = service.cleanArtist("(99+) Heilung | Anoana [Official Video] - YouTube", "", "Microsoft Edge");
        assert(t2 === "Anoana [Official Video]", "t2 must strip prefix/suffix and extract title from pipe separator: got " + t2);
        assert(a2 === "Heilung", "a2 must extract artist from pipe separator: got " + a2);

        var t3 = service.cleanTitle("陈粒 - 世界正中 - YouTube", "");
        var a3 = service.cleanArtist("陈粒 - 世界正中 - YouTube", "", "Microsoft Edge");
        assert(t3 === "世界正中", "t3 must extract title from dash separator: got " + t3);
        assert(a3 === "陈粒", "a3 must extract artist: got " + a3);

        var t4 = service.cleanTitle("Epic Live Stream", "");
        var a4 = service.cleanArtist("Epic Live Stream", "", "Microsoft Edge");
        assert(t4 === "Epic Live Stream", "t4 must keep single title intact: got " + t4);
        assert(a4 === "Microsoft Edge", "a4 must fallback to player identity: got " + a4);

        // 2. Playback Ground-Truth Arbitration Tests
        var pausedWinePlayer = {
            dbusName: "org.mpris.MediaPlayer2.cloudmusic",
            identity: "NetEase Cloud Music (Wine)",
            playbackState: 2, // Paused
            isPlaying: false
        };

        var playingEdgePlayer = {
            dbusName: "org.mpris.MediaPlayer2.plasma-browser-integration",
            identity: "Microsoft Edge",
            playbackState: 1, // Playing
            isPlaying: true
        };

        var rawEdgeInstance = {
            dbusName: "org.mpris.MediaPlayer2.edge.instance3610",
            identity: "Microsoft Edge",
            playbackState: 1, // Playing
            isPlaying: true
        };

        service.players = [pausedWinePlayer, playingEdgePlayer];

        // Paused Wine player must NEVER be considered playing even with high audio visualizer energy
        assert(service.isPlayerPlaying(pausedWinePlayer, service.visualizer) === false, "Paused Wine player must return false for isPlayerPlaying even with energy");
        assert(service.isPlayerPlaying(playingEdgePlayer, service.visualizer) === true, "Playing Edge player must return true for isPlayerPlaying");

        // 3. Native player priority over Wine
        service.updateActivePlayer();
        assert(service.currentPlayer !== null, "currentPlayer must not be null");
        assert(service.currentPlayer.identity === "Microsoft Edge", "Active player must be Edge when NetEase is paused: got " + service.currentPlayer.identity);

        // 4. Raw Chromium instance deduplication
        var rawList = [pausedWinePlayer, rawEdgeInstance, playingEdgePlayer];
        var deduplicated = service.filterPlayers(rawList);
        assert(deduplicated.length === 2, "Deduplicated list must have 2 entries (Wine and PBI): got " + deduplicated.length);
        assert(deduplicated[0].identity === "NetEase Cloud Music (Wine)", "Entry 0 is NetEase");
        assert(deduplicated[1].dbusName === "org.mpris.MediaPlayer2.plasma-browser-integration", "Entry 1 is PBI Edge");

        // 5. Raw Chromium instance preservation when PBI is absent
        var rawOnlyList = [pausedWinePlayer, rawEdgeInstance];
        var preserved = service.filterPlayers(rawOnlyList);
        assert(preserved.length === 2, "Preserved list must keep raw Edge instance when PBI absent: got " + preserved.length);
        assert(preserved[1].dbusName === "org.mpris.MediaPlayer2.edge.instance3610", "Raw Edge is preserved");

        // 6. Switching from Browser to Wine: Browser paused, Wine starts playing
        var pausedEdgePlayer = {
            dbusName: "org.mpris.MediaPlayer2.plasma-browser-integration",
            identity: "Microsoft Edge",
            playbackState: 2, // Paused
            isPlaying: false
        };
        var winePlayerWithStaleState = {
            dbusName: "org.mpris.MediaPlayer2.cloudmusic",
            identity: "NetEase Cloud Music (Wine)",
            playbackState: 2, // Stale DBus state from Wine
            isPlaying: false
        };
        service.players = [winePlayerWithStaleState, pausedEdgePlayer];

        // Edge is paused, so hasOtherNativePlayingPlayer is false.
        // PipeWire visualizer detects audio energy from Wine -> Wine isPlaying must be true!
        var activeStreamingVisualizer = { isStreaming: true, energy: 0.85, beat: 0.90 };
        assert(service.isPlayerPlaying(winePlayerWithStaleState, activeStreamingVisualizer) === true, "Wine with stale DBus state must be playing when audio energy is present and no native player is playing");
        assert(service.isPlayerPlaying(pausedEdgePlayer, activeStreamingVisualizer) === false, "Paused Edge player must remain false even with audio energy");

        service.updateActivePlayer();
        assert(service.currentPlayer !== null, "currentPlayer must not be null");
        assert(service.currentPlayer.identity === "NetEase Cloud Music (Wine)", "Active player must switch/stay on NetEase when NetEase is playing: got " + service.currentPlayer.identity);

        // When Wine is truly paused, audio energy is 0.0 -> isPlayerPlaying must be false
        var quietVisualizer = { isStreaming: true, energy: 0.0, beat: 0.0 };
        assert(service.isPlayerPlaying(winePlayerWithStaleState, quietVisualizer) === false, "Wine player must be not playing when visualizer has zero energy");

        console.log("PASS: Browser Media Arbitration Tests");
        Qt.exit(0);
    }
}

