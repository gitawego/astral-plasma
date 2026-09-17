import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../theme"
import "../config"
import "../services"

Item {
    id: root

    implicitWidth: 200
    implicitHeight: 200

    // Test overrides (used by unit tests)
    property real testVolume: -1
    property int testMuted: -1

    readonly property real currentVolume: (testVolume >= 0)
        ? testVolume
        : ((typeof PipewireAudio !== "undefined" && PipewireAudio) ? (PipewireAudio.volume ?? 0.5) : 0.5)

    readonly property bool isMuted: (testMuted >= 0)
        ? (testMuted === 1)
        : ((typeof PipewireAudio !== "undefined" && PipewireAudio) ? (PipewireAudio.muted ?? false) : false)

    // Smoothed animated volume for 60fps buttery motion
    property bool isTesting: false
    property real animatedVolume: currentVolume
    Behavior on animatedVolume {
        enabled: !root.isTesting
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    onCurrentVolumeChanged: {
        animatedVolume = currentVolume;
    }

    property bool isInitialized: false
    property real lastVolume: currentVolume
    property bool lastMuted: isMuted
    property bool localOpen: false
    readonly property bool isOpen: (typeof Config !== "undefined" && Config.volumeOsdVisible !== undefined)
        ? Config.volumeOsdVisible
        : localOpen

    opacity: isOpen ? 1.0 : 0.0
    visible: opacity > 0.001

    Behavior on opacity {
        NumberAnimation {
            duration: root.isOpen ? 120 : 250
            easing.type: root.isOpen ? Easing.OutCubic : Easing.InCubic
        }
    }

    Timer {
        id: initTimer
        interval: 800
        running: true
        repeat: false
        onTriggered: {
            root.lastVolume = root.currentVolume;
            root.lastMuted = root.isMuted;
            root.isInitialized = true;
        }
    }

    Timer {
        id: hideTimer
        interval: 1600
        repeat: false
        onTriggered: root.localOpen = false
    }

    // Dynamic Tactile Speaker Pulse Animation on Every Volume Change
    property real iconPulseScale: 1.0

    SequentialAnimation {
        id: pulseAnim
        alwaysRunToEnd: false

        NumberAnimation {
            target: root
            property: "iconPulseScale"
            to: 1.10
            duration: 75
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "iconPulseScale"
            to: 0.97
            duration: 95
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: root
            property: "iconPulseScale"
            to: 1.0
            duration: 130
            easing.type: Easing.OutBack
            easing.overshoot: 1.4
        }
    }

    function trigger() {
        if (!isInitialized) return;
        pulseAnim.restart();
        if (typeof Config !== "undefined" && typeof Config.triggerVolumeOsd === "function") {
            Config.triggerVolumeOsd();
        } else {
            root.localOpen = true;
            hideTimer.restart();
        }
    }

    Connections {
        target: (typeof PipewireAudio !== "undefined") ? PipewireAudio : null
        function onVolumeChanged() {
            if (root.isInitialized && Math.abs(root.currentVolume - root.lastVolume) > 0.002) {
                root.lastVolume = root.currentVolume;
                root.trigger();
            }
        }
        function onMutedChanged() {
            if (root.isInitialized && root.isMuted !== root.lastMuted) {
                root.lastMuted = root.isMuted;
                root.trigger();
            }
        }
    }

    // =========================================================================
    // CONTINUOUS SOUND WAVE DYNAMICS (Updates smoothly upon every volume change)
    // =========================================================================
    // Wave 1: active from 0.01 up to 0.35, scales and deepens continuously
    readonly property real wave1Progress: Math.max(0.0, Math.min(1.0, animatedVolume / 0.35))
    readonly property real wave1Opacity: root.isMuted ? 0.0 : (animatedVolume > 0.005 ? Math.min(1.0, 0.35 + 0.65 * wave1Progress) : 0.0)
    readonly property real wave1Spread: wave1Progress * 2.5
    readonly property real wave1Scale: 0.92 + 0.10 * wave1Progress

    // Wave 2: emerges smoothly starting from 0.16, reaches full strength at 0.66
    readonly property real wave2Progress: Math.max(0.0, Math.min(1.0, (animatedVolume - 0.16) / 0.50))
    readonly property real wave2Opacity: root.isMuted ? 0.0 : (animatedVolume <= 0.16 ? 0.0 : Math.min(1.0, (animatedVolume - 0.16) / 0.20))
    readonly property real wave2Spread: wave2Progress * 5.0
    readonly property real wave2Scale: 0.90 + 0.12 * wave2Progress

    // Wave 3: emerges smoothly starting from 0.48, reaches full strength at 0.95
    readonly property real wave3Progress: Math.max(0.0, Math.min(1.0, (animatedVolume - 0.48) / 0.48))
    readonly property real wave3Opacity: root.isMuted ? 0.0 : (animatedVolume <= 0.48 ? 0.0 : Math.min(1.0, (animatedVolume - 0.48) / 0.22))
    readonly property real wave3Spread: wave3Progress * 7.5
    readonly property real wave3Scale: 0.88 + 0.14 * wave3Progress

    // =========================================================================
    // THEME PALETTE BINDINGS (Consistent with Iris & Caelestia pastel presets)
    // =========================================================================
    readonly property color cardColor: (typeof Colors !== "undefined" && Colors.glassSurface)
        ? Colors.glassSurface
        : Qt.rgba(0.06, 0.07, 0.09, 0.72)

    readonly property color cardBorderColor: (typeof Colors !== "undefined" && Colors.glassBorderSubtle)
        ? Colors.glassBorderSubtle
        : Qt.rgba(1, 1, 1, 0.12)

    readonly property color fgColor: (typeof Colors !== "undefined" && Colors.textMain)
        ? Colors.textMain
        : "#1D1B20"

    readonly property color accentColor: (typeof Colors !== "undefined" && Colors.primary)
        ? Colors.primary
        : "#6B4FA0"

    readonly property color trackBgColor: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh)
        ? Qt.alpha(Colors.surfaceContainerHigh, 0.80)
        : Qt.rgba(0, 0, 0, 0.08)

    readonly property color trackBorderColor: (typeof Colors !== "undefined" && Colors.outlineVariant)
        ? Qt.alpha(Colors.outlineVariant, 0.45)
        : Qt.rgba(0, 0, 0, 0.06)

    readonly property color tickUnfilledColor: (typeof Colors !== "undefined" && Colors.surfaceContainerLowest)
        ? Qt.alpha(Colors.surfaceContainerLowest, 0.65)
        : Qt.rgba(1, 1, 1, 0.50)

    // ==========================================
    // 1. TRANSLUCENT CONTAINER CARD (~0.6 opacity)
    // ==========================================
    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: 28
        color: root.cardColor
        border.width: 1
        border.color: root.cardBorderColor

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            blurMax: 32
            shadowBlur: 0.7
            shadowVerticalOffset: 4
            shadowColor: (typeof Colors !== "undefined" && Colors.glassShadowColor) ? Colors.glassShadowColor : Qt.rgba(0, 0, 0, 0.25)
        }

        // Top specular rim glare line
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 0.5
            anchors.left: parent.left
            anchors.leftMargin: parent.radius * 0.35
            anchors.right: parent.right
            anchors.rightMargin: parent.radius * 0.35
            height: 1.2
            color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.75)
            opacity: 0.85
        }
    }

    // ==========================================
    // 2. VECTOR SPEAKER ICON & SOUND WAVES
    // ==========================================
    Item {
        id: speakerIconContainer
        width: 96
        height: 84
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 38
        transformOrigin: Item.Center
        scale: root.iconPulseScale * (root.isMuted ? 0.94 : (0.96 + 0.07 * root.animatedVolume))

        Behavior on scale {
            enabled: !pulseAnim.running
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        // Speaker Body & Horn
        Shape {
            id: speakerBody
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: root.fgColor
                strokeColor: root.fgColor
                strokeWidth: 1.5
                joinStyle: ShapePath.RoundJoin

                // Left rectangular box: x from 6 to 24, y from 28 to 56
                startX: 6; startY: 28
                PathLine { x: 24; y: 28 }
                // Expanding cone: from (24, 28) to (46, 10)
                PathLine { x: 46; y: 10 }
                // Flat mouth: from (46, 10) to (46, 74)
                PathLine { x: 46; y: 74 }
                // Expanding cone bottom: from (46, 74) to (24, 56)
                PathLine { x: 24; y: 56 }
                // Left box bottom: from (24, 56) to (6, 56)
                PathLine { x: 6; y: 56 }
                // Close back
                PathLine { x: 6; y: 28 }
            }
        }

        // Sound Wave 1 Container (themed Iris accent)
        Item {
            id: wave1Item
            anchors.fill: parent
            transformOrigin: Item.Left
            x: root.wave1Spread
            scale: root.wave1Scale
            opacity: root.wave1Opacity
            visible: opacity > 0.005

            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.accentColor
                    strokeWidth: 4.5
                    capStyle: ShapePath.RoundCap

                    startX: 56; startY: 24
                    PathArc {
                        x: 56; y: 60
                        radiusX: 24; radiusY: 24
                        direction: PathArc.Clockwise
                    }
                }
            }
        }

        // Sound Wave 2 Container (themed Iris accent)
        Item {
            id: wave2Item
            anchors.fill: parent
            transformOrigin: Item.Left
            x: root.wave2Spread
            scale: root.wave2Scale
            opacity: root.wave2Opacity
            visible: opacity > 0.005

            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.accentColor
                    strokeWidth: 4.5
                    capStyle: ShapePath.RoundCap

                    startX: 68; startY: 14
                    PathArc {
                        x: 68; y: 70
                        radiusX: 38; radiusY: 38
                        direction: PathArc.Clockwise
                    }
                }
            }
        }

        // Sound Wave 3 Container (themed Iris accent)
        Item {
            id: wave3Item
            anchors.fill: parent
            transformOrigin: Item.Left
            x: root.wave3Spread
            scale: root.wave3Scale
            opacity: root.wave3Opacity
            visible: opacity > 0.005

            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.accentColor
                    strokeWidth: 4.5
                    capStyle: ShapePath.RoundCap

                    startX: 80; startY: 4
                    PathArc {
                        x: 80; y: 80
                        radiusX: 52; radiusY: 52
                        direction: PathArc.Clockwise
                    }
                }
            }
        }

        // Mute Cross Indicator
        Item {
            id: muteCrossItem
            anchors.fill: parent
            transformOrigin: Item.Center
            opacity: root.isMuted ? 1.0 : 0.0
            scale: root.isMuted ? 1.0 : 0.5
            visible: opacity > 0.01

            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.fgColor
                    strokeWidth: 4
                    capStyle: ShapePath.RoundCap

                    startX: 56; startY: 30
                    PathLine { x: 76; y: 54 }
                }

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: root.fgColor
                    strokeWidth: 4
                    capStyle: ShapePath.RoundCap

                    startX: 76; startY: 30
                    PathLine { x: 56; y: 54 }
                }
            }
        }
    }

    // ==========================================
    // 3. 16-SEGMENT THEMED PROGRESS TICK BAR
    // ==========================================
    Rectangle {
        id: tickBarFrame
        width: 147
        height: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 26
        color: root.trackBgColor
        radius: 2
        border.width: 1
        border.color: root.trackBorderColor

        Row {
            anchors.centerIn: parent
            spacing: 1

            Repeater {
                model: 16

                delegate: Rectangle {
                    id: tickItem
                    required property int index
                    width: 8
                    height: 8
                    radius: 1

                    readonly property real tickFraction: Math.max(0.0, Math.min(1.0, (root.animatedVolume * 16) - tickItem.index))
                    readonly property bool isFullyFilled: !root.isMuted && (tickFraction >= 0.99)
                    readonly property bool isPartiallyFilled: !root.isMuted && (tickFraction > 0.01)

                    color: root.isMuted
                        ? root.tickUnfilledColor
                        : (isFullyFilled
                            ? root.accentColor
                            : (isPartiallyFilled ? Qt.alpha(root.accentColor, 0.25 + 0.75 * tickFraction) : root.tickUnfilledColor))

                    border.width: 0.5
                    border.color: (!root.isMuted && isPartiallyFilled) ? Qt.alpha(root.accentColor, 0.40) : "transparent"
                }
            }
        }
    }
}
