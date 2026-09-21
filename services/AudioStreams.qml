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

    // A sound server stream appears and disappears with playback, so a short
    // poll keeps the arbitration honest without any event source to subscribe to.
    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!streamsProc.running) streamsProc.running = true;
        }
    }
}
