pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property bool ready: Pipewire.ready
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    // Always track sink and source so Pipewire nodes are bound for volume/mute control
    PwObjectTracker {
        objects: [root.sink, root.source].filter(n => Boolean(n))
    }

    // Internal fallback volume when Pipewire is still binding
    property real fallbackVolume: 0.5
    property bool fallbackMuted: false

    readonly property real volume: (sink && sink.ready && sink.audio) ? sink.audio.volume : root.fallbackVolume
    readonly property bool muted: (sink && sink.ready && sink.audio) ? sink.audio.muted : root.fallbackMuted
    readonly property string sinkName: sink ? (sink.description || sink.name || "Default Audio") : "Default Audio"

    function setVolume(val) {
        val = Math.max(0.0, Math.min(1.5, val));
        root.fallbackVolume = val;
        root.fallbackMuted = false;

        let ok = false;
        try {
            if (sink && sink.ready && sink.audio) {
                sink.audio.muted = false;
                sink.audio.volume = val;
                ok = true;
            }
        } catch (e) {
            ok = false;
        }
        if (!ok) {
            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", val.toFixed(2)]);
        }
    }

    function toggleMute() {
        root.fallbackMuted = !root.fallbackMuted;
        let ok = false;
        try {
            if (sink && sink.ready && sink.audio) {
                sink.audio.muted = !sink.audio.muted;
                ok = true;
            }
        } catch (e) {
            ok = false;
        }
        if (!ok) {
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        }
    }

    function getVolumeIcon() {
        if (muted || volume <= 0.01) return "volume_mute";
        if (volume < 0.5) return "volume_down";
        return "volume_up";
    }

    // Sync fallback volume from wpctl on startup
    Process {
        id: initWpctl
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const match = this.text.match(/Volume:\s+([0-9.]+)/);
                    if (match && match[1]) {
                        root.fallbackVolume = parseFloat(match[1]);
                    }
                    if (this.text.includes("[MUTED]")) {
                        root.fallbackMuted = true;
                    }
                } catch (e) {}
            }
        }
    }
}
