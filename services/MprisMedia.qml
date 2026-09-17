pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../config"

Singleton {
    id: root

    readonly property var rawPlayers: Mpris.players.values
    readonly property var players: {
        let list = rawPlayers || [];
        if (!list || list.length <= 1) return list;
        let hasPbi = false;
        for (let i = 0; i < list.length; i++) {
            let p = list[i];
            if (p && p.dbusName && p.dbusName.indexOf("plasma-browser-integration") !== -1) {
                hasPbi = true;
                break;
            }
        }
        if (!hasPbi) return list;
        let res = [];
        for (let i = 0; i < list.length; i++) {
            let p = list[i];
            if (!p) continue;
            // When plasma-browser-integration is active, deduplicate raw Chromium instance bus names
            if (p.dbusName && p.dbusName.indexOf(".instance") !== -1) {
                continue;
            }
            res.push(p);
        }
        return res;
    }
    property var manualPlayer: null
    property string manualPlayerBusName: ""
    property var currentPlayer: null

    readonly property var activePlayer: currentPlayer

    function findMatchingPlayer(target) {
        if (!target || !players || players.length === 0) return null;
        let targetBus = "";
        let targetId = "";
        if (typeof target === "string") {
            targetBus = target;
            targetId = target;
        } else {
            targetBus = target.dbusName || "";
            targetId = target.identity || "";
        }
        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (!p) continue;
            if (p === target) return p;
            if (targetBus !== "" && p.dbusName && p.dbusName === targetBus) return p;
            if (targetId !== "" && p.identity && p.identity === targetId) return p;
        }
        return null;
    }

    function isPlayerActive(player) {
        if (!player || !activePlayer) return false;
        if (player === activePlayer) return true;
        if (player.dbusName && activePlayer.dbusName && player.dbusName === activePlayer.dbusName) return true;
        if (player.identity && activePlayer.identity && player.identity === activePlayer.identity) return true;
        return false;
    }

    function isWinePlayer(p) {
        if (!p) return false;
        let bus = p.dbusName || "";
        let id = p.identity || "";
        return bus.indexOf("cloudmusic") !== -1 || id.indexOf("NetEase") !== -1 || id.indexOf("Wine") !== -1;
    }

    function hasOtherNativePlayingPlayer(excludePlayer) {
        if (!players || players.length === 0) return false;
        for (let i = 0; i < players.length; i++) {
            let other = players[i];
            if (!other || other === excludePlayer) continue;
            if (isWinePlayer(other)) continue;
            if (other.isPlaying === true || other.playbackState === 1 || (typeof MprisPlaybackState !== "undefined" && other.playbackState === MprisPlaybackState.Playing)) {
                return true;
            }
        }
        return false;
    }

    function isPlayerPlaying(p) {
        if (!p) return false;

        // Wine player handling: Wine emits no native DBus playback signals.
        // When user plays/pauses inside Wine GUI, DBus playbackState remains stale.
        // Therefore physical audio energy is the sole ground truth, provided no other native player is playing!
        if (isWinePlayer(p)) {
            // 1. If another native player is actively playing (e.g. Edge playing YouTube),
            // physical audio energy belongs to that player, NOT to Wine!
            if (hasOtherNativePlayingPlayer(p)) {
                return false;
            }
            // 2. If visualizer is streaming audio from PipeWire, real physical audio energy is the ground truth
            if (typeof AudioVisualizer !== "undefined" && AudioVisualizer && AudioVisualizer.isStreaming) {
                return (AudioVisualizer.energy > 0.005 || AudioVisualizer.beat > 0.005);
            }
            // 3. If visualizer is active or has energy:
            if (typeof AudioVisualizer !== "undefined" && AudioVisualizer && (AudioVisualizer.active === true || AudioVisualizer.energy > 0.005 || AudioVisualizer.beat > 0.005)) {
                return true;
            }
            // 4. Fallback when visualizer is offline or not streaming yet: check DBus state
            if (p.isPlaying === true || p.playbackState === 1 || (typeof MprisPlaybackState !== "undefined" && p.playbackState === MprisPlaybackState.Playing)) {
                return true;
            }
            return false;
        }

        // Native MPRIS players (Edge, Chrome, Firefox, Strawberry, Elisa, etc.):
        // DBus state is authoritative for native Linux players
        if (p.playbackState === 2 || p.playbackState === 0) return false;
        if (typeof MprisPlaybackState !== "undefined") {
            if (p.playbackState === MprisPlaybackState.Paused || p.playbackState === MprisPlaybackState.Stopped) return false;
        }
        if (p.isPlaying === true) return true;
        if (p.playbackState === 1) return true;
        if (typeof MprisPlaybackState !== "undefined" && p.playbackState === MprisPlaybackState.Playing) return true;
        return false;
    }

    readonly property bool isAnyPlayerPlaying: {
        let fc = (typeof AudioVisualizer !== "undefined" && AudioVisualizer) ? AudioVisualizer.frameCount : 0;
        if (!players || players.length === 0) return false;
        for (let i = 0; i < players.length; i++) {
            if (isPlayerPlaying(players[i])) return true;
        }
        return false;
    }

    function syncToPlayingPlayer() {
        if (!players || players.length === 0) return;
        // Prioritize any actively playing native player first (e.g. Edge, Chrome, Firefox)
        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (!isWinePlayer(p) && isPlayerPlaying(p)) {
                manualPlayer = null;
                manualPlayerBusName = "";
                if (currentPlayer !== p) {
                    currentPlayer = p;
                }
                return;
            }
        }
        // Then any other playing player (e.g. Wine)
        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (isPlayerPlaying(p)) {
                manualPlayer = null;
                manualPlayerBusName = "";
                if (currentPlayer !== p) {
                    currentPlayer = p;
                }
                return;
            }
        }
        // If none playing, prefer Cloud Music if available
        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (p && ((p.dbusName && p.dbusName.indexOf("cloudmusic") !== -1) || (p.identity && p.identity.indexOf("Cloud Music") !== -1))) {
                if (manualPlayerBusName === "") {
                    if (currentPlayer !== p) currentPlayer = p;
                    return;
                }
            }
        }
    }

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onDashboardVisibleChanged() {
            if (Config.dashboardVisible) {
                root.syncToPlayingPlayer();
            }
        }
        function onActiveDashboardTabChanged() {
            if (Config.dashboardVisible && (Config.activeDashboardTab === "dashboard" || Config.activeDashboardTab === "media")) {
                root.syncToPlayingPlayer();
            }
        }
    }

    // Reactively observe playback state transitions across all registered MPRIS players
    Instantiator {
        model: root.players
        delegate: Connections {
            target: modelData
            ignoreUnknownSignals: true
            function onPlaybackStateChanged() {
                if (modelData && root.isPlayerPlaying(modelData) && root.currentPlayer !== modelData) {
                    // Auto-sync when a player transitions to Playing
                    root.manualPlayer = null;
                    root.manualPlayerBusName = "";
                }
                root.updateActivePlayer();
            }
            function onIsPlayingChanged() {
                if (modelData && root.isPlayerPlaying(modelData) && root.currentPlayer !== modelData) {
                    root.manualPlayer = null;
                    root.manualPlayerBusName = "";
                }
                root.updateActivePlayer();
            }
        }
    }

    function updateActivePlayer() {
        if (!players || players.length === 0) {
            if (currentPlayer !== null) currentPlayer = null;
            manualPlayer = null;
            manualPlayerBusName = "";
            return;
        }

        // 1. Strictly honor explicit manual selection if the player is still present on DBus
        if (manualPlayerBusName !== "") {
            let matchedManual = findMatchingPlayer(manualPlayerBusName);
            if (matchedManual) {
                manualPlayer = matchedManual;
                if (currentPlayer !== matchedManual) currentPlayer = matchedManual;
                return;
            } else {
                // Player closed or disconnected
                manualPlayer = null;
                manualPlayerBusName = "";
            }
        }

        // 2. Check if any player is actively Playing
        // Prioritize native playing players first, then wine
        let playingPlayer = null;
        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (!isWinePlayer(p) && isPlayerPlaying(p)) {
                playingPlayer = p;
                break;
            }
        }
        if (!playingPlayer) {
            for (let i = 0; i < players.length; i++) {
                let p = players[i];
                if (isPlayerPlaying(p)) {
                    playingPlayer = p;
                    break;
                }
            }
        }

        if (playingPlayer) {
            if (currentPlayer !== playingPlayer) currentPlayer = playingPlayer;
            return;
        }

        // 3. Keep current player if still active
        if (currentPlayer) {
            let matchedCurrent = findMatchingPlayer(currentPlayer);
            if (matchedCurrent) {
                if (currentPlayer !== matchedCurrent) currentPlayer = matchedCurrent;
                return;
            }
        }

        // 4. Default to Cloud Music if present, else first available
        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (p && ((p.dbusName && p.dbusName.indexOf("cloudmusic") !== -1) || (p.identity && p.identity.indexOf("Cloud Music") !== -1))) {
                currentPlayer = p;
                return;
            }
        }

        if (players.length > 0) {
            currentPlayer = players[0];
        }
    }

    // 300ms heartbeat to ensure player transitions (play/pause/new player) are reactively tracked
    Timer {
        id: playerWatcher
        interval: 300
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.updateActivePlayer()
    }

    onPlayersChanged: updateActivePlayer()

    readonly property string identity: {
        if (!activePlayer) return "No Player";
        if (activePlayer.identity && activePlayer.identity.length > 0) return activePlayer.identity;
        if (activePlayer.desktopEntry && activePlayer.desktopEntry.length > 0) return activePlayer.desktopEntry;
        if (activePlayer.dbusName && activePlayer.dbusName.length > 0) {
            let parts = activePlayer.dbusName.split('.');
            return parts[parts.length - 1];
        }
        return "Media Player";
    }

    function cleanTitle(rawTitle, rawArtist) {
        if (!rawTitle || rawTitle.length === 0) return "No Media Playing";
        let t = rawTitle.trim();
        // 1. Remove leading notification counts like "(4) " or "(99+) "
        t = t.replace(/^\(\d+\+?\)\s*/, "");
        // 2. Remove trailing site identifiers like " - YouTube"
        t = t.replace(/\s*-\s*(YouTube|Bilibili|SoundCloud|Spotify)\s*$/i, "");

        // 3. If rawArtist is given and title starts with "Artist - ", remove redundant artist from title
        if (rawArtist && rawArtist.length > 0 && rawArtist !== "Unknown Artist") {
            let prefix = rawArtist.trim() + " - ";
            if (t.toLowerCase().indexOf(prefix.toLowerCase()) === 0) {
                t = t.slice(prefix.length).trim();
            }
        } else {
            // If rawArtist is empty/unknown, and title has "Artist - Title" or "Artist | Title", extract title
            let sepIdx = t.indexOf(" - ");
            if (sepIdx === -1) sepIdx = t.indexOf(" | ");
            if (sepIdx !== -1) {
                let candidate = t.slice(sepIdx + 3).trim();
                if (candidate.length > 0) t = candidate;
            }
        }
        return t.length > 0 ? t : rawTitle;
    }

    function cleanArtist(rawTitle, rawArtist, fallbackIdentity) {
        let a = (rawArtist && rawArtist.length > 0) ? rawArtist.trim() : "";
        if (a && a !== "Unknown Artist") {
            return a;
        }
        // If rawArtist is missing, attempt to extract from title
        if (rawTitle) {
            let t = rawTitle.trim().replace(/^\(\d+\+?\)\s*/, "").replace(/\s*-\s*(YouTube|Bilibili|SoundCloud|Spotify)\s*$/i, "");
            let sepIdx = t.indexOf(" - ");
            if (sepIdx === -1) sepIdx = t.indexOf(" | ");
            if (sepIdx !== -1) {
                let extractedArtist = t.slice(0, sepIdx).trim();
                if (extractedArtist.length > 0) {
                    return extractedArtist;
                }
            }
        }
        if (fallbackIdentity && fallbackIdentity !== "No Player" && fallbackIdentity !== "Media Player") {
            return fallbackIdentity;
        }
        return "Unknown Artist";
    }

    readonly property bool hasMedia: activePlayer !== null
    readonly property string rawTrackTitle: activePlayer && activePlayer.trackTitle ? activePlayer.trackTitle : ""
    readonly property string rawTrackArtist: activePlayer ? (activePlayer.trackArtist || (activePlayer.trackArtists && activePlayer.trackArtists.length > 0 ? activePlayer.trackArtists.join(", ") : "") || "") : ""
    readonly property string title: hasMedia ? cleanTitle(rawTrackTitle, rawTrackArtist) : "No Media Playing"
    readonly property string artist: hasMedia ? cleanArtist(rawTrackTitle, rawTrackArtist, identity) : "Unknown Artist"
    readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || activePlayer.artUrl || "") : ""
    readonly property bool isPlaying: {
        let e = (typeof AudioVisualizer !== "undefined" && AudioVisualizer) ? AudioVisualizer.energy : 0;
        let a = (typeof AudioVisualizer !== "undefined" && AudioVisualizer) ? AudioVisualizer.active : false;
        let b = (typeof AudioVisualizer !== "undefined" && AudioVisualizer) ? AudioVisualizer.beat : 0;
        let fc = (typeof AudioVisualizer !== "undefined" && AudioVisualizer) ? AudioVisualizer.frameCount : 0;
        let s = (typeof AudioVisualizer !== "undefined" && AudioVisualizer) ? AudioVisualizer.isStreaming : false;
        return root.isPlayerPlaying(activePlayer);
    }

    property real currentPosition: 0

    readonly property real length: {
        if (activePlayer && activePlayer.length > 0) return activePlayer.length;
        return 1;
    }

    readonly property real position: currentPosition
    readonly property real progress: length > 0 ? Math.min(1.0, Math.max(0.0, currentPosition / length)) : 0

    readonly property bool canPlay: activePlayer ? activePlayer.canPlay : false
    readonly property bool canPause: activePlayer ? activePlayer.canPause : false
    readonly property bool canGoNext: activePlayer ? activePlayer.canGoNext : false
    readonly property bool canGoPrevious: activePlayer ? activePlayer.canGoPrevious : false
    readonly property bool canSeek: activePlayer ? activePlayer.canSeek : false

    // Smooth 250ms progress ticker
    Timer {
        id: ticker
        interval: 250
        repeat: true
        running: root.isPlaying && root.hasMedia
        onTriggered: {
            if (root.length > 0 && root.currentPosition < root.length) {
                root.currentPosition = Math.min(root.length, root.currentPosition + 0.25);
            }
        }
    }

    // Sync position when active player or player state changes
    onActivePlayerChanged: {
        if (activePlayer) {
            currentPosition = activePlayer.position || 0;
        } else {
            currentPosition = 0;
        }
    }

    property string lastNotifiedTrack: ""
    property string lastNotifiedArtUrl: ""

    function checkTrackNotification(forceUpdateArt) {
        if (!root.isPlaying || !root.title || root.title === "No Media Playing" || root.title === "") {
            return;
        }
        const trackKey = root.title + " - " + root.artist;
        const art = root.artUrl || "";
        if (trackKey !== lastNotifiedTrack || (forceUpdateArt && art !== "" && art !== lastNotifiedArtUrl)) {
            lastNotifiedTrack = trackKey;
            lastNotifiedArtUrl = art;
            NotificationService.show(
                root.title,
                root.artist || "Unknown Artist",
                "music_note",
                root.identity || "Media Player",
                art
            );
        }
    }

    onTitleChanged: checkTrackNotification(false)
    onArtUrlChanged: {
        if (artUrl && artUrl !== "" && artUrl !== lastNotifiedArtUrl) {
            checkTrackNotification(true);
        }
    }
    onIsPlayingChanged: {
        if (isPlaying) {
            checkTrackNotification(false);
        }
        if (activePlayer && isWinePlayer(activePlayer)) {
            WindowService.updateWinePlaybackStatus(isPlaying);
        }
    }

    Connections {
        target: root.activePlayer
        ignoreUnknownSignals: true
        function onPositionChanged() {
            if (root.activePlayer) {
                root.currentPosition = root.activePlayer.position || 0;
            }
        }
        function onPlaybackStateChanged() {
            if (root.activePlayer) {
                root.currentPosition = root.activePlayer.position || 0;
                if (root.isPlaying) {
                    root.checkTrackNotification(false);
                }
            }
        }
        function onTrackTitleChanged() {
            if (root.activePlayer) {
                root.currentPosition = root.activePlayer.position || 0;
                root.checkTrackNotification(false);
            }
        }
        function onTrackArtUrlChanged() {
            if (root.activePlayer && root.artUrl && root.artUrl !== "") {
                root.checkTrackNotification(true);
            }
        }
    }

    function selectPlayer(player) {
        if (!player) return;
        let matched = findMatchingPlayer(player);
        let busOrId = (player.dbusName && player.dbusName.length > 0) ? player.dbusName : (player.identity || "");
        manualPlayerBusName = busOrId;
        manualPlayer = matched || player;
        currentPlayer = matched || player;
    }

    function playerIdentity(player) {
        if (!player) return "No Player";
        if (player.identity && player.identity.length > 0) return player.identity;
        if (player.desktopEntry && player.desktopEntry.length > 0) return player.desktopEntry;
        if (player.dbusName && player.dbusName.length > 0) {
            let parts = player.dbusName.split('.');
            let last = parts[parts.length - 1];
            if (last.length > 0) return last.charAt(0).toUpperCase() + last.slice(1);
            return last;
        }
        return "Media Player";
    }

    function cyclePlayer() {
        if (!players || players.length <= 1) return;
        let idx = 0;
        for (let i = 0; i < players.length; i++) {
            if (isPlayerActive(players[i])) {
                idx = i;
                break;
            }
        }
        let nextIdx = (idx + 1) % players.length;
        selectPlayer(players[nextIdx]);
    }

    function seekTo(fraction) {
        if (!activePlayer || length <= 0) return;
        let targetSecs = fraction * length;
        currentPosition = targetSecs;
        if (activePlayer.canSeek) {
            try {
                activePlayer.position = targetSecs;
            } catch (e) {}
        }
    }

    function togglePlay() {
        if (!activePlayer) return;
        if (activePlayer.canTogglePlaying) {
            activePlayer.togglePlaying();
        } else if (isPlaying) {
            if (activePlayer.canPause) activePlayer.pause();
            else activePlayer.togglePlaying();
        } else {
            if (activePlayer.canPlay) activePlayer.play();
            else activePlayer.togglePlaying();
        }
    }

    function playPause() {
        togglePlay();
    }

    function next() {
        if (activePlayer && activePlayer.canGoNext) {
            activePlayer.next();
        }
    }

    function previous() {
        if (activePlayer && activePlayer.canGoPrevious) {
            activePlayer.previous();
        }
    }
}
