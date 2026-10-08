pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../config"

Singleton {
    id: root

    readonly property var rawPlayers: Mpris.players.values
    /**
     * A raw Chromium instance bus (`...edge.instance3610`) duplicates the
     * plasma-browser-integration player; Firefox's bus
     * (`...firefox.instance_1_1212245`, underscores, not a bare PID) is a
     * real player and must survive. Matching ".instance" alone deleted
     * Firefox whenever Edge was present — the player was never even a
     * candidate, so no arbitration could ever elect it.
     */
    function isRawChromiumInstance(busName) {
        if (!busName) return false;
        return /\.(chrome|chromium|edge|brave|vivaldi|opera|microsoft-edge)\.instance\d+$/.test(busName);
    }
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
            if (isRawChromiumInstance(p.dbusName)) {
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

    /**
     * A finished session masquerading as Playing: position has reached a known
     * duration while the state never cleared (e.g. 13:18 of 13:18). Browsers
     * leave these behind on ended media; trusting the claim elects a dead
     * session over the music that is actually audible.
     */
    function isStaleFinishedSession(p) {
        if (!p) return false;
        const length = Number(p.length || 0);
        const position = Number(p.position || 0);
        return length > 0 && position >= length;
    }

    function hasOtherNativePlayingPlayer(excludePlayer) {
        if (!players || players.length === 0) return false;
        for (let i = 0; i < players.length; i++) {
            let other = players[i];
            if (!other || other === excludePlayer) continue;
            if (isWinePlayer(other)) continue;
            if (isStaleFinishedSession(other)) continue;
            if (other.isPlaying === true || other.playbackState === 1 || (typeof MprisPlaybackState !== "undefined" && other.playbackState === MprisPlaybackState.Playing)) {
                return true;
            }
        }
        return false;
    }

    /// Whether the sound server's stream list can decide who is playing.
    ///
    /// It can when it is available *and* every audible stream belongs to one of
    /// the players we know; unattributed audio (a game, a tool with a generic
    /// stream name) falls back to the players' own claims rather than reporting
    /// that nothing is playing.
    /// Whether sound is actually flowing through the speakers right now.
    ///
    /// The stream list says which application *owns* a stream; the visualizer's
    /// PCM energy says whether that stream is producing sound. A paused player
    /// keeps an uncorked, unmuted stream open, so ownership alone kept reporting
    /// "playing" long after the music stopped. The short hold keeps quiet
    /// passages from flickering.
    property double silentSinceMs: 0
    property bool audioFlowing: false
    onAudioFlowingChanged: {
        // Rising edge only: music started somewhere, so the audible owner
        // should hold the selection. The falling edge (pause) is deliberately
        // not synced — there is no grounded winner in silence, and a sync
        // there could only demote a correctly paused display.
        if (audioFlowing) syncToPlayingPlayer(true);
    }

    Timer {
        interval: 250
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            const viz = (typeof AudioVisualizer !== "undefined") ? AudioVisualizer : null;
            if (!viz || !(viz.isStreaming || viz.active)) {
                root.audioFlowing = false;
                root.silentSinceMs = 0;
                return;
            }

            // Digital silence is exact: the capture reports a clean 0.0 when no
            // samples flow, which is what a pause looks like. A quiet passage
            // still reports *some* energy, so this tells the two apart without
            // waiting for a long hold - confirmed over a few frames so a single
            // zero cannot flicker the state.
            const silent = (viz.energy || 0) <= 0 && (viz.beat || 0) <= 0;
            const now = Date.now();
            if (silent) {
                if (root.silentSinceMs === 0) root.silentSinceMs = now;
                if (now - root.silentSinceMs >= 350) root.audioFlowing = false;
            } else {
                root.silentSinceMs = 0;
                root.audioFlowing = true;
            }
        }
    }

    readonly property bool audioArbitrationAvailable: {
        if (typeof AudioStreams === "undefined" || !AudioStreams.available) return false;
        // Without the visualizer there is no way to tell silence from sound, so
        // fall back to the players' own claims rather than guessing.
        if (typeof AudioVisualizer === "undefined" || !AudioVisualizer || !AudioVisualizer.isStreaming) return false;
        if (!AudioStreams.streams || AudioStreams.streams.length === 0) return true;
        if (!players || players.length === 0) return false;
        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (!p) continue;
            if (AudioStreams.matcher.isAudible(p.identity || "", p.dbusName || "")) return true;
        }
        return false;
    }

    function isPlayerPlaying(p) {
        if (!p) return false;

        // Physical audio is the ground truth: a player that owns an application
        // making sound is playing, and one that only *claims* Playing while
        // another application owns the sound is not. Browsers keep reporting
        // Playing for background tabs and muted videos, which is how a stale
        // browser session used to outrank the music that was actually audible.
        if (audioArbitrationAvailable) {
            return AudioStreams.matcher.isPlaying(p.identity || "", p.dbusName || "", audioFlowing);
        }

        // Wine player handling: Wine emits no native DBus playback signals.
        // When user plays/pauses inside Wine GUI, DBus playbackState remains stale.
        // Therefore physical audio energy is the sole ground truth, provided no other native player is playing!
        if (isWinePlayer(p)) {
            // 1. If another native player is actively playing (e.g. Edge playing YouTube),
            // physical audio energy belongs to that player, NOT to Wine!
            if (hasOtherNativePlayingPlayer(p)) {
                return false;
            }
            // 2. If visualizer is streaming audio from PipeWire, real physical audio energy is the ground truth.
            //    `active` is the same predicate (`energy > 0.005 || beat > 0.005`) but changes only when sound
            //    starts or stops. Reading the per-frame `energy`/`beat` values here registered a 90 Hz dependency
            //    on every binding that reached this function, which cost ~80 % of a CPU core whenever a
            //    visualiser tab (dashboard/media) was open.
            if (typeof AudioVisualizer !== "undefined" && AudioVisualizer && AudioVisualizer.isStreaming) {
                return AudioVisualizer.active === true;
            }
            // 3. If visualizer is active or has energy:
            if (typeof AudioVisualizer !== "undefined" && AudioVisualizer && AudioVisualizer.active === true) {
                return true;
            }
            // 4. Fallback when visualizer is offline or not streaming yet: check DBus state
            if (p.isPlaying === true || p.playbackState === 1 || (typeof MprisPlaybackState !== "undefined" && p.playbackState === MprisPlaybackState.Playing)) {
                return true;
            }
            return false;
        }

        // Native MPRIS players (Edge, Chrome, Firefox, Strawberry, Elisa, etc.):
        // DBus state is authoritative for native Linux players, except for a
        // finished session still claiming Playing (see isStaleFinishedSession).
        if (isStaleFinishedSession(p)) return false;
        if (p.playbackState === 2 || p.playbackState === 0) return false;
        if (typeof MprisPlaybackState !== "undefined") {
            if (p.playbackState === MprisPlaybackState.Paused || p.playbackState === MprisPlaybackState.Stopped) return false;
        }
        if (p.isPlaying === true) return true;
        if (p.playbackState === 1) return true;
        if (typeof MprisPlaybackState !== "undefined" && p.playbackState === MprisPlaybackState.Playing) return true;
        return false;
    }

    /// A finished session: still on the bus, but with nothing to show.
    function isPlayerStopped(p) {
        if (!p) return true;
        if (typeof MprisPlaybackState !== "undefined" && MprisPlaybackState.Stopped !== undefined) {
            return p.playbackState === MprisPlaybackState.Stopped;
        }
        // Quickshell's enum order: Stopped = 0, Playing = 1, Paused = 2.
        return p.playbackState === 0;
    }

    readonly property bool isAnyPlayerPlaying: {
        // Re-checked on the audio service's *arbitration* tick (4 Hz), never on its
        // stream frame counter (90 Hz): reading the frame counter here made every
        // dependent binding re-evaluate 90 times per second.
        let tick = (typeof AudioVisualizer !== "undefined" && AudioVisualizer) ? AudioVisualizer.arbitrationTick : 0;
        if (tick < 0) return false;
        if (!players || players.length === 0) return false;
        for (let i = 0; i < players.length; i++) {
            if (isPlayerPlaying(players[i])) return true;
        }
        return false;
    }

    function syncToPlayingPlayer(corrective) {
        if (!players || players.length === 0) return;
        // A corrective sync fires when ground truth arrives or changes (stream
        // list, arbitration availability, audio flow). It may only demote a
        // stale selection toward an arbitration-proven winner: promoting on
        // bare DBus claims here would re-elect the same stale browser session
        // the correction is meant to dethrone, and clearing a manual pick
        // would make the dropdown useless (it reverts within one poll).
        const isCorrection = corrective === true;
        if (isCorrection && manualPlayerBusName !== "") return;
        // Prioritize any actively playing native player first (e.g. Edge, Chrome, Firefox)
        let winner = null;
        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (!isWinePlayer(p) && isPlayerPlaying(p)) {
                winner = p;
                break;
            }
        }
        if (!winner) {
            for (let i = 0; i < players.length; i++) {
                let p = players[i];
                if (isPlayerPlaying(p)) {
                    winner = p;
                    break;
                }
            }
        }
        // Stream owners outrank bare claimants. Arbitration needs *flowing*
        // audio, so a paused owner (uncorked stream, silent room) and a stale
        // claimant (Playing state, no stream) tie at zero under it — yet the
        // stream list still names the owner. Preferring an owner elects the
        // paused Firefox over a stale Edge, and never elects anything that
        // owns nothing. Paused displays are preserved: when no stream exists
        // at all this finds nothing and selection keeps.
        if (!winner && audioArbitrationAvailable && AudioStreams.streams && AudioStreams.streams.length > 0) {
            for (let i = 0; i < players.length; i++) {
                let p = players[i];
                if (!isWinePlayer(p)
                        && AudioStreams.matcher.isAudible(p.identity || "", p.dbusName || "")) {
                    winner = p;
                    break;
                }
            }
            if (!winner) {
                for (let j = 0; j < players.length; j++) {
                    let q = players[j];
                    if (AudioStreams.matcher.isAudible(q.identity || "", q.dbusName || "")) {
                        winner = q;
                        break;
                    }
                }
            }
        }
        if (isCorrection && !audioArbitrationAvailable) return;
        if (winner) {
            manualPlayer = null;
            manualPlayerBusName = "";
            if (currentPlayer !== winner) {
                currentPlayer = winner;
            }
            return;
        }
        if (isCorrection) return;
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

    // Ground truth arrives on its own schedule (daemon poll, visualizer
    // energy), not on dashboard events. A selection made while arbitration
    // was unavailable would otherwise keep a stale browser session forever:
    // re-sync correctively so the audible player dethrones it within one
    // poll. Corrective syncs never promote on bare claims and never clear a
    // manual pick (see syncToPlayingPlayer), so pauses and dropdown choices
    // are unaffected.
    Connections {
        target: (typeof AudioStreams !== "undefined") ? AudioStreams : null
        function onAvailableChanged() {
            if (AudioStreams.available) root.syncToPlayingPlayer(true);
        }
        function onStreamsChanged() {
            root.syncToPlayingPlayer(true);
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

        // 3. Keep the current player while it is still meaningful: present on
        //    DBus and not a finished session. A browser session that stopped an
        //    hour ago must not pin the widget while nothing else is playing.
        if (currentPlayer && !isPlayerStopped(currentPlayer)) {
            let matchedCurrent = findMatchingPlayer(currentPlayer);
            if (matchedCurrent) {
                if (currentPlayer !== matchedCurrent) currentPlayer = matchedCurrent;
                return;
            }
        }

        // 4. Prefer Cloud Music, then any live session, then whatever is left.
        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (p && !isPlayerStopped(p) && ((p.dbusName && p.dbusName.indexOf("cloudmusic") !== -1) || (p.identity && p.identity.indexOf("Cloud Music") !== -1))) {
                currentPlayer = p;
                return;
            }
        }

        for (let i = 0; i < players.length; i++) {
            let p = players[i];
            if (p && !isPlayerStopped(p)) {
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
    readonly property string rawTrackAlbum: activePlayer ? (activePlayer.trackAlbum || (activePlayer.metadata && activePlayer.metadata["xesam:album"]) || "") : ""
    readonly property string title: hasMedia ? cleanTitle(rawTrackTitle, rawTrackArtist) : "No Media Playing"
    readonly property string artist: hasMedia ? cleanArtist(rawTrackTitle, rawTrackArtist, identity) : "Unknown Artist"
    readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || activePlayer.artUrl || "") : ""
    readonly property bool isPlaying: {
        // The audio-flow read below is deliberate: it is the *dependency* that
        // re-runs this binding when ground truth changes (a browser player can keep
        // claiming Playing while it sends silence). It reads the service's flow
        // flag, which flips only when audio starts or stops - not the per-frame
        // stream values this used to touch, which change ~90 times per second and
        // dragged every dependent binding along with them.
        const audioFlow = (typeof AudioVisualizer !== "undefined" && AudioVisualizer)
            ? AudioVisualizer.active
            : false;
        void audioFlow;
        return root.isPlayerPlaying(activePlayer);
    }

    property real currentPosition: 0

    readonly property real length: {
        if (activePlayer && activePlayer.length > 0) return activePlayer.length;
        return 1;
    }

    readonly property real position: currentPosition
    readonly property real progress: length > 0 ? Math.min(1.0, Math.max(0.0, currentPosition / length)) : 0

    readonly property string album: activePlayer ? (activePlayer.trackAlbum || (activePlayer.metadata && activePlayer.metadata["xesam:album"]) || "") : ""
    readonly property bool shuffle: activePlayer ? (activePlayer.shuffle ?? false) : false
    readonly property bool shuffleSupported: activePlayer ? (activePlayer.shuffleSupported ?? false) : false
    readonly property int loopState: activePlayer ? (activePlayer.loopState ?? 0) : 0
    readonly property bool loopSupported: activePlayer ? (activePlayer.loopSupported ?? false) : false

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
        // Keep the bridge's advertised state in step with the audio truth: a
        // reload begins with the players list empty, so waiting for a transition
        // would leave it claiming "Playing" for the rest of the session.
        if (activePlayer && isWinePlayer(activePlayer)) {
            WindowService.updateWinePlaybackStatus(isPlaying);
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

    // Push the state once at start-up as well: a reload begins with the music
    // already paused, so no transition would ever fire and the bridge would keep
    // advertising "Playing" to every other MPRIS client.
    Component.onCompleted: {
        if (activePlayer && isWinePlayer(activePlayer)) {
            WindowService.updateWinePlaybackStatus(isPlaying);
        }
    }

    // The bridge advertises the Wine player's state to every MPRIS client, but our
    // own view comes from the audio and settles a moment after start-up. Keep it
    // in step instead of trusting a single transition (the push is idempotent: the
    // daemon only emits a change when the value actually differs).
    Timer {
        interval: 5000
        repeat: true
        running: root.activePlayer !== null && root.isWinePlayer(root.activePlayer)
        onTriggered: WindowService.updateWinePlaybackStatus(root.isPlaying)
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
        if (!canSeek) return;
        let frac = Math.max(0.0, Math.min(1.0, fraction));
        let targetSecs = frac * length;
        currentPosition = targetSecs;
        if (typeof activePlayer.position !== "undefined") {
            try {
                activePlayer.position = targetSecs;
            } catch (e) {
                if (typeof activePlayer.seek === "function") {
                    try {
                        activePlayer.seek(targetSecs - currentPosition);
                    } catch (e2) {}
                }
            }
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

    function toggleShuffle() {
        if (activePlayer && activePlayer.shuffleSupported) {
            try {
                activePlayer.shuffle = !activePlayer.shuffle;
            } catch (e) {}
        }
    }

    function cycleLoop() {
        if (activePlayer && activePlayer.loopSupported) {
            try {
                let next = (activePlayer.loopState + 1) % 3;
                activePlayer.loopState = next;
            } catch (e) {}
        }
    }
}
