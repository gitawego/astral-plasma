pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int brightness: 100
    property int brightnessMax: 100
    readonly property real normalized: brightnessMax > 0 ? (brightness / brightnessMax) : 1.0

    // Fetch initial brightness
    Process {
        id: queryProc
        command: ["qdbus6", "org.kde.Solid.PowerManagement", "/org/kde/Solid/PowerManagement/Actions/BrightnessControl", "org.kde.Solid.PowerManagement.Actions.BrightnessControl.brightness"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(this.text.trim());
                if (!isNaN(val)) root.brightness = val;
            }
        }
    }

    Process {
        id: queryMaxProc
        command: ["qdbus6", "org.kde.Solid.PowerManagement", "/org/kde/Solid/PowerManagement/Actions/BrightnessControl", "org.kde.Solid.PowerManagement.Actions.BrightnessControl.brightnessMax"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseInt(this.text.trim());
                if (!isNaN(val) && val > 0) root.brightnessMax = val;
            }
        }
    }

    Process {
        id: setProc
    }

    function setBrightness(val) {
        const target = Math.round(Math.max(1, Math.min(root.brightnessMax, val * root.brightnessMax)));
        root.brightness = target;
        setProc.command = ["qdbus6", "org.kde.Solid.PowerManagement", "/org/kde/Solid/PowerManagement/Actions/BrightnessControl", "org.kde.Solid.PowerManagement.Actions.BrightnessControl.setBrightness", target.toString()];
        setProc.running = true;
    }

    Component.onCompleted: {
        queryMaxProc.running = true;
        queryProc.running = true;
    }
}
