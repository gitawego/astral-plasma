pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../components/motion"
import "."
import "../config"

Singleton {
    id: root

    // ==========================================
    // Visualizer Public Properties
    // ==========================================
    property real energy: 0.0
    property real bass: 0.0
    property real mid: 0.0
    property real treble: 0.0
    property real beat: 0.0
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property bool active: false
    readonly property bool isStreaming: visualizerProc.running
    property int frameCount: 0

    signal frameUpdated()

    // ==========================================
    // Decorative presentation mirrors
    // ==========================================
    // The stream above is ground truth at audio rate (tens of frames per second).
    // Handing that rate straight to the visualisers made every one of their 40+
    // bound bars re-evaluate per stream frame and repainted the host surface at the
    // same rate: the dashboard and media tabs measured ~80 % of a CPU core each,
    // and a glass surface that keeps updating also costs the compositor a blur of
    // the whole region every frame.
    //
    // Presentation is decoration, so it advances on the shared clock instead -
    // at most `Theme.decorativeMaxFps` samples per second. The visualisers read
    // these mirrors, which are samples of the real stream (never synthesised), and
    // a stream that goes quiet settles once and then holds no clock at all.
    property var displayBands: bands
    property real displayEnergy: 0.0
    property real displayBass: 0.0
    property real displayMid: 0.0
    property real displayTreble: 0.0
    property real displayBeat: 0.0
    property int _sampledFrame: -1
    property bool _sampledSilent: true

    function _sampleStream() {
        if (!root.active && root._sampledSilent) {
            return;
        }
        root._sampledFrame = root.frameCount;
        root._sampledSilent = !root.active;
        root.displayBands = root.bands;
        root.displayEnergy = root.energy;
        root.displayBass = root.bass;
        root.displayMid = root.mid;
        root.displayTreble = root.treble;
        root.displayBeat = root.beat;
    }

    MotionTick {
        running: root.procShouldRun && root.active
        onTicked: {
            if (root.frameCount !== root._sampledFrame) {
                root._sampleStream();
            }
        }
    }

    // Periodic re-check tick for *arbitration* consumers: while audio flows, a
    // player can keep claiming playback with stale state, so the arbiter has to
    // look again. Deliberately slow (4 Hz): the raw stream frame counter used to
    // serve as this tick, and because it changes ~90 times per second, every
    // binding that read it re-evaluated 90 times per second - worth ~80 % of a CPU
    // core for as long as a visualiser tab was open.
    property int arbitrationTick: 0

    Timer {
        interval: 250
        repeat: true
        running: root.procShouldRun
        onTriggered: root.arbitrationTick++
    }

    // Silence settles immediately, so nothing is left oscillating on a frozen frame.
    onActiveChanged: {
        if (!root.active) {
            root._sampleStream();
        }
    }

    // ==========================================
    // Lifecycle & Visibility State
    // ==========================================
    readonly property bool isPlaying: (typeof MprisMedia !== "undefined" && MprisMedia)
        ? (MprisMedia.isPlaying || MprisMedia.isAnyPlayerPlaying)
        : false
    readonly property bool isDashboardVisible: (typeof Config !== "undefined" && Config) ? Config.dashboardVisible : false
    readonly property string activeTab: (typeof Config !== "undefined" && Config) ? Config.activeDashboardTab : "dashboard"
    readonly property bool isEffectVisible: isDashboardVisible && (activeTab === "dashboard" || activeTab === "media")

    Connections {
        target: (typeof Config !== "undefined") ? Config : null
        function onDashboardVisibleChanged() { root.updateLifecycle(); }
        function onActiveDashboardTabChanged() { root.updateLifecycle(); }
    }

    Connections {
        target: (typeof MprisMedia !== "undefined") ? MprisMedia : null
        function onIsPlayingChanged() { root.updateLifecycle(); }
    }

    // Subprocess execution gate
    property bool procShouldRun: false

    // Grace timer: 2000ms delay after visibility is lost before stopping
    Timer {
        id: graceTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (!root.isEffectVisible) {
                root.procShouldRun = false;
                root.active = false;
                root.energy = 0.0;
                root.bass = 0.0;
                root.mid = 0.0;
                root.treble = 0.0;
                root.beat = 0.0;
                root.bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
                root.frameUpdated();
            }
        }
    }

    function updateLifecycle() {
        if (root.isEffectVisible) {
            // Dashboard / Media tab is visible: run visualizer process to sample real audio
            graceTimer.stop();
            root.procShouldRun = true;
        } else {
            // Hidden: start 5-second grace countdown before shutting down to save CPU
            if (root.procShouldRun && !graceTimer.running) {
                graceTimer.start();
            }
        }
    }

    onIsEffectVisibleChanged: updateLifecycle()

    Component.onCompleted: updateLifecycle()

    readonly property string serviceDir: Qt.resolvedUrl(".").toString().replace("file://", "")
    readonly property string daemonBin: root.serviceDir + "/../bin/astral-plasma"

    // ==========================================
    // Subprocess: astral-plasma visualizer
    // ==========================================
    Process {
        id: visualizerProc
        command: [root.daemonBin, "visualizer"]
        running: root.procShouldRun

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (raw) => {
                try {
                    const line = raw.trim();
                    if (!line || !line.startsWith("{")) return;
                    const data = JSON.parse(line);
                    if (!data) return;

                    if (data.e !== undefined) root.energy = data.e;
                    if (data.b !== undefined) root.bass = data.b;
                    if (data.m !== undefined) root.mid = data.m;
                    if (data.t !== undefined) root.treble = data.t;
                    if (data.beat !== undefined) root.beat = data.beat;
                    if (data.bands && Array.isArray(data.bands)) root.bands = data.bands.slice();

                    root.active = (root.energy > 0.005 || root.beat > 0.005);
                    root.frameCount++;
                    root.frameUpdated();
                } catch (e) {
                    // Ignore parse errors on truncated frames
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.active = false;
            root.energy = 0.0;
            root.bass = 0.0;
            root.mid = 0.0;
            root.treble = 0.0;
            root.beat = 0.0;
            root.bands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            root.frameUpdated();
        }
    }

    // ==========================================
    // Heatmap Color Helper
    // ==========================================
    // Returns hex color corresponding to normalized intensity [0.0 .. 1.0]
    // 0.00 - 0.25: Cool Indigo / Cyan (#06b6d4 -> #6366f1)
    // 0.25 - 0.55: Magenta / Hot Pink (#8b5cf6 -> #ec4899)
    // 0.55 - 0.85: Fiery Orange / Coral (#f43f5e -> #f97316)
    // 0.85 - 1.00: Radiant Golden Yellow / White (#facc15 -> #ffffff)
    function getHeatmapColor(val, alpha) {
        val = Math.max(0.0, Math.min(1.0, val || 0.0));
        var a = (alpha !== undefined) ? alpha : 1.0;

        var r = 0, g = 0, b = 0;
        if (val < 0.25) {
            // [0.0, 0.25] Cyan (6, 182, 212) -> Indigo (99, 102, 241)
            var t = val / 0.25;
            r = Math.round(6 + (99 - 6) * t);
            g = Math.round(182 + (102 - 182) * t);
            b = Math.round(212 + (241 - 212) * t);
        } else if (val < 0.55) {
            // [0.25, 0.55] Indigo (99, 102, 241) -> Hot Pink / Magenta (236, 72, 153)
            var t = (val - 0.25) / 0.30;
            r = Math.round(99 + (236 - 99) * t);
            g = Math.round(102 + (72 - 102) * t);
            b = Math.round(241 + (153 - 241) * t);
        } else if (val < 0.85) {
            // [0.55, 0.85] Hot Pink (236, 72, 153) -> Fiery Orange (249, 115, 22)
            var t = (val - 0.55) / 0.30;
            r = Math.round(236 + (249 - 236) * t);
            g = Math.round(72 + (115 - 72) * t);
            b = Math.round(153 + (22 - 153) * t);
        } else {
            // [0.85, 1.00] Fiery Orange (249, 115, 22) -> Golden Yellow / White (250, 204, 21)
            var t = (val - 0.85) / 0.15;
            r = Math.round(249 + (255 - 249) * t);
            g = Math.round(115 + (220 - 115) * t);
            b = Math.round(22 + (120 - 22) * t);
        }

        return Qt.rgba(r / 255.0, g / 255.0, b / 255.0, a);
    }
}
