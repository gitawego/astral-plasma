import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../theme"
import "../config"
import "../components"
import "../services"

Item {
    id: root

    implicitWidth: 60
    implicitHeight: 280

    readonly property color activePrimary: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#6B4FA0"
    readonly property color activeContainer: (typeof Colors !== "undefined" && Colors.primaryContainer) ? Colors.primaryContainer : "#EDE7F6"

    readonly property real currentVolume: (typeof PipewireAudio !== "undefined" && PipewireAudio) ? (PipewireAudio.volume ?? 0.5) : 0.5
    readonly property bool isMuted: (typeof PipewireAudio !== "undefined" && PipewireAudio) ? (PipewireAudio.muted ?? false) : false
    readonly property string volumeIcon: {
        if (isMuted || currentVolume <= 0.01) return "volume_mute";
        if (currentVolume < 0.5) return "volume_down";
        return "volume_up";
    }

    readonly property real currentBrightness: (typeof BrightnessService !== "undefined" && BrightnessService) ? (BrightnessService.normalized ?? 1.0) : 1.0

    HoverHandler {
        id: controlHover
        onHoveredChanged: {
            if (hovered) {
                if (typeof Config !== "undefined") Config.keepRightEdgeControl();
            } else {
                if (typeof Config !== "undefined") Config.scheduleCloseRightEdgeControl();
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 20

        // ==========================================
        // 1. VOLUME VERTICAL CAPSULE SLIDER
        // ==========================================
        Item {
            id: volumeSlider
            width: 22
            height: 114

            // Track background capsule
            Rectangle {
                id: volumeTrack
                anchors.fill: parent
                radius: width / 2
                color: root.activeContainer
                clip: true

                // Filled portion from bottom up to knob center
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.max(0, volumeSlider.height - (volumeKnob.y + volumeKnob.height / 2))
                    bottomLeftRadius: volumeSlider.width / 2
                    bottomRightRadius: volumeSlider.width / 2
                    topLeftRadius: 0
                    topRightRadius: 0
                    color: root.activePrimary
                }
            }

            // Circular knob handle with icon
            Rectangle {
                id: volumeKnob
                width: 26
                height: 26
                radius: 13
                anchors.horizontalCenter: parent.horizontalCenter
                y: {
                    const v = Math.min(1.0, Math.max(0.0, root.currentVolume));
                    return (1.0 - v) * (volumeSlider.height - height);
                }
                color: root.activePrimary

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowBlur: 0.35
                    shadowVerticalOffset: 1
                    shadowColor: Qt.rgba(0, 0, 0, 0.25)
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.volumeIcon
                    size: 15
                    color: "#FFFFFF"
                }
            }

            // Interactive MouseArea
            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: -14
                anchors.rightMargin: -14
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                property real pressY: 0
                property bool isDragging: false

                function updateVolume(mouseY) {
                    if (typeof Config !== "undefined") Config.keepRightEdgeControl();
                    const availableH = volumeSlider.height - volumeKnob.height;
                    const clampedY = Math.max(0, Math.min(availableH, mouseY - volumeKnob.height / 2));
                    const norm = Math.max(0.0, Math.min(1.0, 1.0 - (clampedY / availableH)));
                    if (typeof PipewireAudio !== "undefined" && typeof PipewireAudio.setVolume === "function") {
                        PipewireAudio.setVolume(norm);
                    }
                }

                onPressed: mouse => {
                    pressY = mouse.y;
                    isDragging = false;
                    if (typeof Config !== "undefined") Config.keepRightEdgeControl();
                }

                onPositionChanged: mouse => {
                    if (pressed) {
                        if (Math.abs(mouse.y - pressY) > 4) {
                            isDragging = true;
                        }
                        if (isDragging) {
                            updateVolume(mouse.y);
                        }
                    }
                }

                onReleased: mouse => {
                    if (!isDragging) {
                        // Pure single click without dragging:
                        const knobTop = volumeKnob.y;
                        const knobBottom = volumeKnob.y + volumeKnob.height;
                        if (mouse.y >= knobTop - 4 && mouse.y <= knobBottom + 4) {
                            // Single click on knob: toggle mute
                            if (typeof PipewireAudio !== "undefined" && typeof PipewireAudio.toggleMute === "function") {
                                PipewireAudio.toggleMute();
                            }
                        } else {
                            // Single click on track: jump volume to clicked level
                            updateVolume(mouse.y);
                        }
                    }
                    isDragging = false;
                }

                onWheel: wheel => {
                    if (typeof Config !== "undefined") Config.keepRightEdgeControl();
                    const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                    if (typeof PipewireAudio !== "undefined" && typeof PipewireAudio.setVolume === "function") {
                        PipewireAudio.setVolume(Math.max(0.0, Math.min(1.0, root.currentVolume + step)));
                    }
                }
            }
        }

        // ==========================================
        // 2. BRIGHTNESS VERTICAL CAPSULE SLIDER
        // ==========================================
        Item {
            id: brightnessSlider
            width: 22
            height: 114

            // Track background capsule
            Rectangle {
                id: brightnessTrack
                anchors.fill: parent
                radius: width / 2
                color: root.activeContainer
                clip: true

                // Filled portion from bottom up to knob center
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.max(0, brightnessSlider.height - (brightnessKnob.y + brightnessKnob.height / 2))
                    bottomLeftRadius: brightnessSlider.width / 2
                    bottomRightRadius: brightnessSlider.width / 2
                    topLeftRadius: 0
                    topRightRadius: 0
                    color: root.activePrimary
                }
            }

            // Circular knob handle with icon
            Rectangle {
                id: brightnessKnob
                width: 26
                height: 26
                radius: 13
                anchors.horizontalCenter: parent.horizontalCenter
                y: {
                    const b = Math.min(1.0, Math.max(0.0, root.currentBrightness));
                    return (1.0 - b) * (brightnessSlider.height - height);
                }
                color: root.activePrimary

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowBlur: 0.35
                    shadowVerticalOffset: 1
                    shadowColor: Qt.rgba(0, 0, 0, 0.25)
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "brightness"
                    size: 15
                    color: "#FFFFFF"
                }
            }

            // Interactive MouseArea
            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: -14
                anchors.rightMargin: -14
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                property real pressY: 0
                property bool isDragging: false

                function updateBrightness(mouseY) {
                    if (typeof Config !== "undefined") Config.keepRightEdgeControl();
                    const availableH = brightnessSlider.height - brightnessKnob.height;
                    const clampedY = Math.max(0, Math.min(availableH, mouseY - brightnessKnob.height / 2));
                    const norm = Math.max(0.05, Math.min(1.0, 1.0 - (clampedY / availableH)));
                    if (typeof BrightnessService !== "undefined" && typeof BrightnessService.setBrightness === "function") {
                        BrightnessService.setBrightness(norm);
                    }
                }

                onPressed: mouse => {
                    pressY = mouse.y;
                    isDragging = false;
                    if (typeof Config !== "undefined") Config.keepRightEdgeControl();
                }

                onPositionChanged: mouse => {
                    if (pressed) {
                        if (Math.abs(mouse.y - pressY) > 4) {
                            isDragging = true;
                        }
                        if (isDragging) {
                            updateBrightness(mouse.y);
                        }
                    }
                }

                onReleased: mouse => {
                    if (!isDragging) {
                        // Pure single click without dragging:
                        const knobTop = brightnessKnob.y;
                        const knobBottom = brightnessKnob.y + brightnessKnob.height;
                        if (mouse.y >= knobTop - 4 && mouse.y <= knobBottom + 4) {
                            // Single click on knob: cycle brightness between 40% and 100%
                            if (typeof BrightnessService !== "undefined" && typeof BrightnessService.setBrightness === "function") {
                                const nextVal = root.currentBrightness > 0.6 ? 0.4 : 1.0;
                                BrightnessService.setBrightness(nextVal);
                            }
                        } else {
                            // Single click on track: jump brightness to clicked level
                            updateBrightness(mouse.y);
                        }
                    }
                    isDragging = false;
                }

                onWheel: wheel => {
                    if (typeof Config !== "undefined") Config.keepRightEdgeControl();
                    const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                    if (typeof BrightnessService !== "undefined" && typeof BrightnessService.setBrightness === "function") {
                        BrightnessService.setBrightness(Math.max(0.05, Math.min(1.0, root.currentBrightness + step)));
                    }
                }
            }
        }
    }
}
