import QtQuick
import Quickshell
import Quickshell.Io

// Loads `calendar resolve` JSON from the daemon and publishes it: the
// installed calendar-capable apps (`[{ id, name }]`) plus the system's
// text/calendar default. Lives in its own file so DashboardPage keeps no
// Quickshell import and stays instantiable in the offscreen qml6 test
// harness (which cannot load Quickshell plugins); the page attaches it via
// a testMode-gated Loader. No application name is ever hardcoded here.
Item {
    id: resolver

    /// `[{ id, name }]` of every installed calendar-capable desktop entry.
    signal optionsLoaded(var options)
    /// The system default: desktop id plus its display name (id when the
    /// desktop entry provides no usable `Name=`).
    signal defaultLoaded(string desktopId, string name)

    Process {
        id: calendarResolveProc
        command: [(typeof Config !== "undefined" && Config.daemonBin) ? Config.daemonBin : "./bin/astral-plasma", "calendar", "resolve"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text.trim());
                    if (!parsed) return;
                    if (Array.isArray(parsed.options)) {
                        resolver.optionsLoaded(parsed.options);
                    }
                    if (parsed.mime_default) {
                        let label = parsed.mime_default;
                        const opts = parsed.options || [];
                        for (let i = 0; i < opts.length; i++) {
                            if (opts[i].id === parsed.mime_default) {
                                label = opts[i].name;
                                break;
                            }
                        }
                        resolver.defaultLoaded(parsed.mime_default, label);
                    }
                } catch (e) {}
            }
        }
    }

    function start() {
        if (calendarResolveProc.command && !calendarResolveProc.running) {
            calendarResolveProc.running = true;
        }
    }
}
