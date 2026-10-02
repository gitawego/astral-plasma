import QtQuick
import Quickshell
import Quickshell.Io
import "../../config"

// ============================================================================
// Application audio streams (daemon probe)
// ============================================================================
// The daemon's `settings audio status` probe and the per-application volume
// write live in their own Quickshell-importing file, the same split
// `DashboardPage` uses for `CalendarAppResolver`: it keeps `AudioPage` free of
// `Quickshell` types, so the page can be instantiated by the offscreen qml6
// harness. The page owns the state; this component only asks the daemon and
// reports back.
//
// The probe is on demand: the page asks once when it appears and again after a
// volume change, so the stream list is real telemetry rather than a poller
// burning CPU in the background.
Item {
    id: root

    /// `[{ id, name, volume, is_muted }]` - the streams the daemon reports.
    signal streamsLoaded(var apps)

    readonly property bool busy: statusProc.running

    /// Ask the daemon for the current app streams.
    function refresh() {
        if (!statusProc.running) statusProc.running = true;
    }

    /// Push one app's volume to the running PipeWire graph.
    function setAppVolume(appId, volume) {
        Quickshell.execDetached([Config.daemonBin, "settings", "audio", "app-volume",
                                 "" + appId, Number(volume).toFixed(2)]);
    }

    Process {
        id: statusProc
        command: [(typeof Config !== "undefined" && Config.daemonBin) ? Config.daemonBin : "./bin/astral-plasma",
                  "settings", "audio", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text.trim());
                    if (parsed && Array.isArray(parsed.apps)) {
                        root.streamsLoaded(parsed.apps);
                    }
                } catch (e) {}
            }
        }
    }
}
