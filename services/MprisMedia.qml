pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../config"

Singleton {
    id: root

    readonly property var players: Mpris.players.values
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

    function isPlayerPlaying(p) {
        if (!p) return false;
        if (p.isPlaying === true) return true;
        if (p.playbackState === 1) return true;
        if (typeof MprisPlaybackState !== "undefined" && p.playbackState === MprisPlaybackState.Playing) return true;
        return false;
    }

    readonly property bool isAnyPlayerPlaying: {
        if (!players || players.length === 0) return false;
        for (let i = 0; i < players.length; i++) {
            if (isPlayerPlaying(players[i])) return true;
        }
        return false;
    }

    function syncToPlayingPlayer() {
        if (!players || players.length === 0) return;
        // Prioritize any actively playing player
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
                root.updateActivePlayer();
            }
            function onIsPlayingChanged() {
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
        let playingPlayer = null;
        for (let i = 0; i < players.length; i++) {
            if (isPlayerPlaying(players[i])) {
                playingPlayer = players[i];
                break;
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

    readonly property bool hasMedia: activePlayer !== null
    readonly property string title: activePlayer && activePlayer.trackTitle ? activePlayer.trackTitle : "No Media Playing"
    readonly property string artist: activePlayer ? (activePlayer.trackArtist || (activePlayer.trackArtists && activePlayer.trackArtists.length > 0 ? activePlayer.trackArtists.join(", ") : "") || "Unknown Artist") : "Unknown Artist"
    readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || activePlayer.artUrl || "") : ""
    readonly property bool isPlaying: root.isPlayerPlaying(activePlayer)

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
        if (activePlayer) {
            activePlayer.togglePlaying();
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
