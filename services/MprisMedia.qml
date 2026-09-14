pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property var players: Mpris.players.values
    readonly property var activePlayer: players.length > 0 ? players[0] : null

    readonly property bool hasMedia: activePlayer !== null
    readonly property string title: activePlayer && activePlayer.trackTitle ? activePlayer.trackTitle : "No Media Playing"
    readonly property string artist: activePlayer && activePlayer.trackArtists && activePlayer.trackArtists.length > 0 ? activePlayer.trackArtists.join(", ") : "Unknown Artist"
    readonly property string artUrl: activePlayer && activePlayer.artUrl ? activePlayer.artUrl : ""
    readonly property bool isPlaying: activePlayer ? (activePlayer.playbackState === MprisPlaybackState.Playing) : false
    readonly property real position: activePlayer ? activePlayer.position : 0
    readonly property real length: activePlayer ? activePlayer.length : 1
    readonly property real progress: length > 0 ? (position / length) : 0

    function togglePlay() {
        if (activePlayer) {
            activePlayer.togglePlaying();
        }
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
