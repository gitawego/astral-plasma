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
    readonly property color onPrimary: (typeof Colors !== "undefined" && Colors.onPrimary) ? Colors.onPrimary : "#FFFFFF"
    readonly property color trackBg: (typeof Colors !== "undefined" && Colors.surfaceContainerHighest) ? Qt.alpha(Colors.surfaceContainerHighest, 0.72) : Qt.rgba(1, 1, 1, 0.12)
    readonly property color trackBorder: (typeof Colors !== "undefined" && Colors.outlineVariant) ? Qt.alpha(Colors.outlineVariant, 0.3) : Qt.rgba(1, 1, 1, 0.08)

    readonly property real currentVolume: (typeof PipewireAudio !== "undefined" && PipewireAudio) ? (PipewireAudio.volume ?? 0.5) : 0.5
    readonly property bool isMuted: (typeof PipewireAudio !== "undefined" && PipewireAudio) ? (PipewireAudio.muted ?? false) : false
    readonly property string volumeIcon: {
        if (isMuted || currentVolume <= 0.01) return "volume_mute";
        if (currentVolume < 0.5) return "volume_down";
        return "volume_up";
    }

    readonly property real currentBrightness: (typeof BrightnessService !== "undefined" && BrightnessService) ? (BrightnessService.normalized ?? 1.0) : 1.0

    readonly property alias cardItem: sliderCard
    readonly property alias volumeTrackItem: volumeTrack
    readonly property alias volumeKnobItem: volumeKnob
    readonly property alias volumeFillItem: volumeFill
    readonly property alias brightnessTrackItem: brightnessTrack
    readonly property alias brightnessKnobItem: brightnessKnob
    readonly property alias brightnessFillItem: brightnessFill

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

    WheelHandler {
        target: root
        orientation: Qt.Vertical
        onWheel: event => {
            if (typeof Config !== "undefined") Config.keepRightEdgeControl();
            const step = event.angleDelta.y > 0 ? 0.05 : -0.05;
            if (typeof PipewireAudio !== "undefined" && typeof PipewireAudio.setVolume === "function") {
                PipewireAudio.setVolume(Math.max(0.0, Math.min(1.0, root.currentVolume + step)));
            }
        }
    }

    // Inner Liquid Glass Substrate Card Layer (Elevated frosted glass plate behind sliders)
    LiquidGlassCard {
        id: sliderCard
        anchors.centerIn: parent
        width: 48
        height: 256
        radius: 24
        elevation: 4
    }

    Column {
        anchors.centerIn: parent
        spacing: 16

        // ==========================================
        // 1. VOLUME VERTICAL LIQUID GLASS SLIDER
        // ==========================================
        Item {
            id: volumeSlider
            width: 38
            height: 108

            // Sleek Recessed Glass Rail / Groove (width: 12px)
            Rectangle {
                id: volumeTrack
                width: 12
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 6
                clip: true

                // Recessed frosted groove trough background
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.rgba(0.0, 0.0, 0.0, 0.42)
                    : Qt.rgba(0.0, 0.0, 0.0, 0.12)
                border.width: 1
                border.color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.rgba(1.0, 1.0, 1.0, 0.10)
                    : Qt.rgba(1.0, 1.0, 1.0, 0.28)

                // Groove depth shading
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(0.0, 0.0, 0.0, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.35 : 0.16)
                        }
                        GradientStop { position: 0.18; color: "transparent" }
                        GradientStop { position: 0.82; color: "transparent" }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(0.0, 0.0, 0.0, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.25 : 0.10)
                        }
                    }
                }

                // Vibrant Liquid Glass Level Bar (Confined strictly inside the 12px groove)
                Rectangle {
                    id: volumeFill
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: {
                        if (root.isMuted || root.currentVolume <= 0.005) return 0;
                        return Math.max(0, volumeSlider.height - (volumeKnob.y + volumeKnob.height / 2));
                    }
                    radius: 6

                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            // Glowing liquid meniscus highlight at the top
                            color: root.isMuted
                                ? (typeof Colors !== "undefined" && Colors.outline ? Qt.alpha(Colors.outline, 0.45) : Qt.rgba(0.6, 0.6, 0.6, 0.45))
                                : Qt.tint(root.activePrimary, Qt.rgba(1.0, 1.0, 1.0, 0.35))
                        }
                        GradientStop {
                            position: 1.0
                            // Rich liquid volume base at the bottom
                            color: root.isMuted
                                ? (typeof Colors !== "undefined" && Colors.outline ? Qt.alpha(Colors.outline, 0.20) : Qt.rgba(0.5, 0.5, 0.5, 0.20))
                                : Qt.alpha(root.activePrimary, 0.85)
                        }
                    }
                }
            }

            // Floating Circular Liquid Glass Disc Controller (Diameter: 34px)
            Rectangle {
                id: volumeKnob
                width: 34
                height: 34
                radius: 17
                anchors.horizontalCenter: parent.horizontalCenter
                y: {
                    const v = Math.min(1.0, Math.max(0.0, root.currentVolume));
                    return (1.0 - v) * (volumeSlider.height - height);
                }

                readonly property bool isHovered: volumeMouseArea.containsMouse
                readonly property bool isDragging: volumeMouseArea.isDragging

                // Interactive scale expansion
                scale: isDragging ? 1.10 : (isHovered ? 1.06 : 1.0)
                Behavior on scale {
                    NumberAnimation {
                        duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastSpatial) ? Theme.animExpressiveFastSpatial : 150
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.4, 0, 0.2, 1]
                    }
                }

                // Smooth glide when external volume changes (disabled during active drag for 0-latency tracking)
                Behavior on y {
                    enabled: !volumeKnob.isDragging
                    NumberAnimation {
                        duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastSpatial) ? Theme.animExpressiveFastSpatial : 150
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.4, 0, 0.2, 1]
                    }
                }

                // Base foundation to cleanly occlude underlying track seam while preserving frosted glass aesthetics
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                        ? Qt.rgba(0.13, 0.14, 0.17, 0.96)
                        : Qt.rgba(0.95, 0.95, 0.97, 0.96)
                }

                // Crystalline translucent glass disc substrate tint
                color: {
                    if (root.isMuted) {
                        return (typeof Colors !== "undefined" && Colors.isDarkMode)
                            ? Qt.rgba(0.20, 0.20, 0.22, 0.60)
                            : Qt.rgba(0.88, 0.88, 0.90, 0.60);
                    }
                    if (isDragging) {
                        return Qt.alpha(root.activePrimary, 0.40);
                    }
                    if (isHovered) {
                        return Qt.alpha(root.activePrimary, 0.28);
                    }
                    return Qt.alpha(root.activePrimary, 0.18);
                }

                // Specular perimeter ring
                border.width: 1
                border.color: {
                    if (isDragging) return Qt.rgba(1.0, 1.0, 1.0, 0.90);
                    if (isHovered) return Qt.rgba(1.0, 1.0, 1.0, 0.70);
                    return (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1.0, 1.0, 1.0, 0.45) : Qt.rgba(1.0, 1.0, 1.0, 0.75);
                }

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                // Optical glass lens refraction cushion
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(1.0, 1.0, 1.0, volumeKnob.isDragging ? 0.45 : (volumeKnob.isHovered ? 0.35 : 0.25))
                        }
                        GradientStop {
                            position: 0.48
                            color: Qt.rgba(1.0, 1.0, 1.0, 0.03)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(0.0, 0.0, 0.0, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.22 : 0.08)
                        }
                    }
                }


                // Floating glass elevation drop shadow
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowBlur: volumeKnob.isDragging ? 0.55 : (volumeKnob.isHovered ? 0.45 : 0.35)
                    shadowVerticalOffset: volumeKnob.isDragging ? 2.5 : 1.5
                    shadowHorizontalOffset: 0
                    shadowColor: Qt.rgba(0.0, 0.0, 0.0, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.50 : 0.25)
                }

                // Centered Volume Glyphs
                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.volumeIcon
                    size: 17
                    color: {
                        if (root.isMuted) return (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#888888";
                        if (typeof Colors !== "undefined" && Colors.isDarkMode) return "#FFFFFF";
                        return (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#111111";
                    }
                }
            }

            // Interactive MouseArea
            MouseArea {
                id: volumeMouseArea
                anchors.fill: parent
                anchors.leftMargin: -12
                anchors.rightMargin: -12
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
                            if (typeof Config !== "undefined") Config.isUserDraggingVolume = true;
                        }
                        if (isDragging) {
                            updateVolume(mouse.y);
                        }
                    }
                }

                onReleased: mouse => {
                    if (typeof Config !== "undefined") Config.isUserDraggingVolume = false;
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
        // 2. BRIGHTNESS VERTICAL LIQUID GLASS SLIDER
        // ==========================================
        Item {
            id: brightnessSlider
            width: 38
            height: 108

            // Sleek Recessed Glass Rail / Groove (width: 12px)
            Rectangle {
                id: brightnessTrack
                width: 12
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 6
                clip: true

                // Recessed frosted groove trough background
                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.rgba(0.0, 0.0, 0.0, 0.42)
                    : Qt.rgba(0.0, 0.0, 0.0, 0.12)
                border.width: 1
                border.color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                    ? Qt.rgba(1.0, 1.0, 1.0, 0.10)
                    : Qt.rgba(1.0, 1.0, 1.0, 0.28)

                // Groove depth shading
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(0.0, 0.0, 0.0, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.35 : 0.16)
                        }
                        GradientStop { position: 0.18; color: "transparent" }
                        GradientStop { position: 0.82; color: "transparent" }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(0.0, 0.0, 0.0, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.25 : 0.10)
                        }
                    }
                }

                // Vibrant Liquid Glass Level Bar (Confined strictly inside the 12px groove)
                Rectangle {
                    id: brightnessFill
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.max(0, brightnessSlider.height - (brightnessKnob.y + brightnessKnob.height / 2))
                    radius: 6

                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            // Radiant warm meniscus highlight
                            color: Qt.tint(root.activePrimary, Qt.rgba(1.0, 0.95, 0.70, 0.38))
                        }
                        GradientStop {
                            position: 1.0
                            // Rich liquid volume base
                            color: Qt.alpha(root.activePrimary, 0.85)
                        }
                    }
                }
            }

            // Floating Circular Liquid Glass Disc Controller (Diameter: 34px)
            Rectangle {
                id: brightnessKnob
                width: 34
                height: 34
                radius: 17
                anchors.horizontalCenter: parent.horizontalCenter
                y: {
                    const b = Math.min(1.0, Math.max(0.0, root.currentBrightness));
                    return (1.0 - b) * (brightnessSlider.height - height);
                }

                readonly property bool isHovered: brightnessMouseArea.containsMouse
                readonly property bool isDragging: brightnessMouseArea.isDragging

                // Interactive scale expansion
                scale: isDragging ? 1.10 : (isHovered ? 1.06 : 1.0)
                Behavior on scale {
                    NumberAnimation {
                        duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastSpatial) ? Theme.animExpressiveFastSpatial : 150
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.4, 0, 0.2, 1]
                    }
                }

                // Smooth glide when external brightness changes (disabled during active drag for 0-latency tracking)
                Behavior on y {
                    enabled: !brightnessKnob.isDragging
                    NumberAnimation {
                        duration: (typeof Theme !== "undefined" && Theme.animExpressiveFastSpatial) ? Theme.animExpressiveFastSpatial : 150
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.4, 0, 0.2, 1]
                    }
                }

                // Base foundation to cleanly occlude underlying track seam while preserving frosted glass aesthetics
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                        ? Qt.rgba(0.13, 0.14, 0.17, 0.96)
                        : Qt.rgba(0.95, 0.95, 0.97, 0.96)
                }

                // Crystalline translucent glass disc substrate tint
                color: {
                    if (isDragging) {
                        return Qt.alpha(root.activePrimary, 0.40);
                    }
                    if (isHovered) {
                        return Qt.alpha(root.activePrimary, 0.28);
                    }
                    return Qt.alpha(root.activePrimary, 0.18);
                }

                // Specular perimeter ring
                border.width: 1
                border.color: {
                    if (isDragging) return Qt.rgba(1.0, 1.0, 1.0, 0.90);
                    if (isHovered) return Qt.rgba(1.0, 1.0, 1.0, 0.70);
                    return (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1.0, 1.0, 1.0, 0.45) : Qt.rgba(1.0, 1.0, 1.0, 0.75);
                }

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                // Optical glass lens refraction cushion
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(1.0, 1.0, 1.0, brightnessKnob.isDragging ? 0.45 : (brightnessKnob.isHovered ? 0.35 : 0.25))
                        }
                        GradientStop {
                            position: 0.48
                            color: Qt.rgba(1.0, 1.0, 1.0, 0.03)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(0.0, 0.0, 0.0, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.22 : 0.08)
                        }
                    }
                }


                // Floating glass elevation drop shadow
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowBlur: brightnessKnob.isDragging ? 0.55 : (brightnessKnob.isHovered ? 0.45 : 0.35)
                    shadowVerticalOffset: brightnessKnob.isDragging ? 2.5 : 1.5
                    shadowHorizontalOffset: 0
                    shadowColor: Qt.rgba(0.0, 0.0, 0.0, (typeof Colors !== "undefined" && Colors.isDarkMode) ? 0.50 : 0.25)
                }

                // Centered Brightness Glyph
                MaterialIcon {
                    anchors.centerIn: parent
                    text: "brightness"
                    size: 17
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? "#FFFFFF" : ((typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#111111")
                }
            }

            // Interactive MouseArea
            MouseArea {
                id: brightnessMouseArea
                anchors.fill: parent
                anchors.leftMargin: -12
                anchors.rightMargin: -12
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
