pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "../components"

/// The applications producing sound right now.
///
/// The daemon reads them from the sound server; the shell uses them to decide
/// which MPRIS player is *really* playing, so a browser session that merely
/// claims `Playing` cannot outrank the music the user is listening to.
Singleton {
    id: root

    property var streams: []
    /// False until the daemon has answered once: "no audio" and "no data" mean
    /// different things to the arbitration.
    property bool available: false

    readonly property alias matcher: matcher

    AudioStreamMatcher {
        id: matcher
        streams: root.streams
    }

    Process {
        id: streamsProc
        command: [Config.daemonBin, "audio", "streams"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text.trim());
                    if (Array.isArray(parsed)) {
                        root.streams = parsed;
                        root.available = true;
                    }
                } catch (e) {
                    root.available = false;
                }
            }
        }
    }

    readonly property bool needsPolling: {
        if (typeof MprisMedia === "undefined" || !MprisMedia) return true;
        return (MprisMedia.players && MprisMedia.players.length > 0) ||
               (typeof AudioVisualizer !== "undefined" && AudioVisualizer && AudioVisualizer.isStreaming);
    }

    Component.onCompleted: {
        if (!streamsProc.running) streamsProc.running = true;
    }

    // A sound server stream appears and disappears with playback, so a short
    // poll keeps the arbitration honest without any event source to subscribe to.
    Timer {
        interval: 2000
        repeat: true
        running: root.needsPolling
        triggeredOnStart: false
        onTriggered: {
            if (!streamsProc.running) streamsProc.running = true;
        }
    }
}
