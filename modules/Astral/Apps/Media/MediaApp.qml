import QtQuick
import QtQuick.Layouts
import "../../Kernel/theme"
import "../../Kernel/components"
import "../../../../menus"

// Media app (`manifest.entry.dashboardTab` = "media").
//
// Declared as a Component in `shell.qml`, so it shares the shell's kernel registration and
// therefore its palette (spec C.18). Reads the injected `media` + `shellState`, writes
// through `intents`.
Item {
    id: root

    property var media: null
    property var shellState: null
    property var intents: null

    readonly property bool hasPlayer: media !== null && media.hasMedia
    /// Whether this surface is actually on screen. `dashboardVisible` records the *toggle*,
    /// not the truth: the dashboard is also shown on hover, and a stale flag gated the
    /// audio visualiser off while the pane was plainly visible.
    readonly property bool isDashboardMediaTab: root.visible
        && shellState !== null
        && shellState.activeDashboardTab === "media"

    implicitWidth: 680
    implicitHeight: 260
    clip: true

    readonly property alias vizSwitchBtn: vizSwitchBtn





    Item {
        anchors.fill: parent
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            anchors.topMargin: Theme.padSmall
            anchors.bottomMargin: Theme.padSmall
            spacing: Theme.spaceLarge

            // Left: Audio Spectrum Visualizer (User-selectable: Radial Halo vs Heatmap Speaker)
            Item {
                id: visualizerSlot
                Layout.preferredWidth: 240
                Layout.preferredHeight: 240
                Layout.alignment: Qt.AlignVCenter

                readonly property string style: root.shellState ? root.shellState.mediaVisualizerStyle : "radial"
                readonly property bool isSpeakerStyle: style === "speaker" || style === "heatmap"
                readonly property bool isCyberpunk: (typeof Theme !== "undefined" && Theme.isCyberpunk)

                // Radial Visualizer (Spectrum halo around circular album art - Cyberpunk or Radial style)
                RadialCoverVisualiser {
                    id: radialViz
                    anchors.centerIn: parent
                    width: 240
                    height: 240
                    visible: visualizerSlot.isCyberpunk || !visualizerSlot.isSpeakerStyle
                    isPlaying: root.media ? root.media.isPlaying === true : false
                    artUrl: (root.media && root.media.artUrl)
                    title: (root.media && root.media.title)
                    artist: (root.media && root.media.artist)
                    isTargetVisible: root.isDashboardMediaTab && visible
                    audioSource: root.media
                }

                // Original Heatmap Speaker Player (Pulsing speaker cone with orbiting rainbow notes & beads)
                HeatmapSpeakerPlayer {
                    id: speakerViz
                    anchors.centerIn: parent
                    width: 240
                    height: 240
                    visible: !visualizerSlot.isCyberpunk && visualizerSlot.isSpeakerStyle
                    isPlaying: root.media ? root.media.isPlaying === true : false
                    artUrl: (root.media && root.media.artUrl)
                    title: (root.media && root.media.title)
                    artist: (root.media && root.media.artist)
                    isTargetVisible: root.isDashboardMediaTab && visible
                    audioSource: root.media
                }

                // Visualizer Switcher Pill Button (Floating subtle toggle - hidden in Cyberpunk)
                LiquidGlassButton {
                    id: vizSwitchBtn
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 4
                    anchors.rightMargin: 4
                    z: 50
                    implicitWidth: 28
                    implicitHeight: 28
                    paddingHorizontal: 6
                    paddingVertical: 6
                    iconText: "equalizer"
                    iconSize: 16
                    elevation: 4
                    visible: !visualizerSlot.isCyberpunk
                    onClicked: {
                        if (root.intents) {
                            root.intents.request("media.visualizerStyle", {
                                style: visualizerSlot.isSpeakerStyle ? "radial" : "speaker"
                            });
                        }
                    }
                }
            }

            // Center: Track Details & Controls
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                // Track Title
                Text {
                    text: (root.media && root.media.title) || "No Media Playing"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleLarge
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                    style: Text.Outline
                    styleColor: Colors.glassTextHalo
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                // Track Album (if present)
                Text {
                    text: (root.media && root.media.album) || ""
                    visible: text.length > 0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.primary
                    style: Text.Outline
                    styleColor: Colors.glassTextHalo
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                // Track Artist
                Text {
                    text: (root.media && root.media.artist) || "Unknown Artist"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    color: Colors.m3onSurfaceVariant
                    style: Text.Outline
                    styleColor: Colors.glassTextHalo
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Item { Layout.preferredHeight: 4; Layout.fillWidth: true }

                // Playback Controls Row (|<<  [ > ]  >>|)
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spaceMedium

                    // Skip Previous
                    LiquidGlassButton {
                        implicitWidth: 38
                        implicitHeight: 38
                        paddingHorizontal: 6
                        paddingVertical: 6
                        iconText: "skip_previous"
                        iconSize: 20
                        elevation: 2
                        interactive: (root.media !== null) ? (root.media && root.media.canGoPrevious) : true
                        opacity: ((root.media !== null) ? (root.media && root.media.canGoPrevious) : true) ? 1.0 : 0.40
                        onClicked: root.media && root.media.previous()
                    }

                    // Play / Pause (Hero Circular Liquid Glass Gem)
                    LiquidGlassButton {
                        implicitWidth: 48
                        implicitHeight: 48
                        paddingHorizontal: 8
                        paddingVertical: 8
                        isPrimary: true
                        iconText: (root.media !== null && (root.media && root.media.isPlaying)) ? "pause" : "play_arrow"
                        iconSize: 24
                        accentColor: Colors.primary
                        elevation: 6
                        onClicked: root.media && root.media.toggle()
                    }

                    // Skip Next
                    LiquidGlassButton {
                        implicitWidth: 38
                        implicitHeight: 38
                        paddingHorizontal: 6
                        paddingVertical: 6
                        iconText: "skip_next"
                        iconSize: 20
                        elevation: 2
                        interactive: (root.media !== null) ? (root.media && root.media.canGoNext) : true
                        opacity: ((root.media !== null) ? (root.media && root.media.canGoNext) : true) ? 1.0 : 0.40
                        onClicked: root.media && root.media.next()
                    }
                }

                Item { Layout.preferredHeight: 4; Layout.fillWidth: true }

                // Progress Bar with Vertical Pill Thumb & Interactive Seeking
                Item {
                    id: sliderContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18

                    readonly property real effectiveProgress: (sliderMouse.isDragging)
                        ? sliderMouse.dragFraction
                        : Math.min(1.0, Math.max(0.0, (root.media && root.media.progress)))

                    // Frosted Glass Track Groove
                    Rectangle {
                        id: sliderTrack
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 6
                        radius: 3
                        color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                            ? Qt.rgba(1.0, 1.0, 1.0, 0.10)
                            : Qt.rgba(0.0, 0.0, 0.0, 0.08)
                        border.color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                            ? Qt.rgba(1.0, 1.0, 1.0, 0.12)
                            : Qt.rgba(0.0, 0.0, 0.0, 0.06)
                        border.width: 1

                        // Filled Liquid Progress Bar
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 0.5
                            width: Math.max(0, (parent.width - 1) * sliderContainer.effectiveProgress)
                            radius: 2.5

                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.darker(Colors.primary, 1.1) }
                                GradientStop { position: 1.0; color: Colors.primary }
                            }

                            // Top subtle highlight inside progress
                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: Qt.rgba(1.0, 1.0, 1.0, 0.45)
                                radius: 1
                            }
                        }

                        // Bespoke Liquid Glass Capsule Thumb
                        Rectangle {
                            id: sliderThumb
                            width: 6
                            height: 16
                            radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(parent.width - width, parent.width * sliderContainer.effectiveProgress - width / 2))
                            color: Colors.primary
                            visible: (root.media && root.media.length) > 0
                            opacity: (root.media && root.media.canSeek) ? 1.0 : 0.60

                            border.color: Qt.rgba(1.0, 1.0, 1.0, 0.85)
                            border.width: 1

                            scale: (sliderMouse.enabled && sliderMouse.pressed) ? 1.30 : ((sliderMouse.enabled && sliderMouse.containsMouse) ? 1.15 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 120 } }
                        }
                    }

                    // Interactive seeking MouseArea
                    MouseArea {
                        id: sliderMouse
                        anchors.fill: parent
                        enabled: (root.media !== null) && (root.media && root.media.canSeek) && (root.media && root.media.length) > 0
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                        property bool isDragging: false
                        property real dragFraction: 0.0

                        onPressed: mouse => {
                            if (!enabled) return;
                            isDragging = true;
                            dragFraction = Math.max(0.0, Math.min(1.0, mouse.x / width));
                        }
                        onPositionChanged: mouse => {
                            if (isDragging) {
                                dragFraction = Math.max(0.0, Math.min(1.0, mouse.x / width));
                            }
                        }
                        onReleased: mouse => {
                            if (isDragging) {
                                isDragging = false;
                                let frac = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                root.media && root.media.seekTo(frac);
                            }
                        }
                        onCanceled: {
                            isDragging = false;
                        }
                        onClicked: mouse => {
                            if (!enabled) return;
                            let frac = Math.max(0.0, Math.min(1.0, mouse.x / width));
                            root.media && root.media.seekTo(frac);
                        }
                    }
                }

                // Timestamps Row below progress slider
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: -2

                    Text {
                        text: {
                            const secs = Math.floor(sliderMouse.isDragging
                                ? (sliderMouse.dragFraction * ((root.media && root.media.length) || 0))
                                : ((root.media && root.media.position) || 0));
                            const m = Math.floor(secs / 60);
                            const s = secs % 60;
                            return m + ":" + (s < 10 ? "0" : "") + s;
                        }
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: {
                            const secs = Math.floor((root.media && root.media.length) || 0);
                            const m = Math.floor(secs / 60);
                            const s = secs % 60;
                            return m + ":" + (s < 10 ? "0" : "") + s;
                        }
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                Item { Layout.preferredHeight: 4; Layout.fillWidth: true }

                // Bottom Utility Row (Shuffle + Active Player Pill Badge + Loop)
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    // Shuffle Button (Sleek Micro-Control)
                    Rectangle {
                        width: 32
                        height: 32
                        radius: (typeof Theme !== "undefined" && Theme.radiusGlassPill !== undefined) ? Math.min(Theme.radiusGlassPill, 16) : 16
                        color: (root.media !== null && (root.media && root.media.shuffle))
                            ? Qt.alpha(Colors.primary, 0.22)
                            : (shufHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent")
                        border.color: (root.media !== null && (root.media && root.media.shuffle))
                            ? Qt.alpha(Colors.primary, 0.60)
                            : (shufHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.16) : "transparent")
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "shuffle"
                            size: 16
                            color: (root.media !== null && (root.media && root.media.shuffle)) ? Colors.primary : Colors.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: shufHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.media && root.media.toggleShuffle()
                        }
                    }

                    // Active Player Pill Badge (Subtle Frosted Glass Capsule)
                    Rectangle {
                        id: playerBadge
                        implicitWidth: playerRow.implicitWidth + 24
                        implicitHeight: 28
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: implicitHeight
                        radius: (typeof Theme !== "undefined" && Theme.radiusGlassPill !== undefined) ? Math.min(Theme.radiusGlassPill, 14) : 14
                        color: (playerBadgeMouse.containsMouse || playerDropdownOverlay.visible)
                            ? Qt.alpha(Colors.primary, 0.20)
                            : ((typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1.0, 1.0, 1.0, 0.06) : Qt.rgba(1.0, 1.0, 1.0, 0.45))
                        border.color: (playerBadgeMouse.containsMouse || playerDropdownOverlay.visible)
                            ? Qt.alpha(Colors.primary, 0.50)
                            : ((typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1.0, 1.0, 1.0, 0.12) : Qt.rgba(1.0, 1.0, 1.0, 0.35))
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            id: playerRow
                            anchors.centerIn: parent
                            spacing: 5

                            MaterialIcon {
                                text: ((root.media && root.media.players) && (root.media && root.media.players).length > 1) ? "graphic_eq" : "music_note"
                                size: 14
                                color: Colors.primary
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                text: (root.media && root.media.playerName) || "Media Player"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontLabelSmall
                                font.weight: Font.Medium
                                color: (playerBadgeMouse.containsMouse || playerDropdownOverlay.visible) ? Colors.onPrimaryContainer : Colors.m3onSurface
                                Layout.alignment: Qt.AlignVCenter
                                style: Text.Outline
                                styleColor: Colors.glassTextHalo
                            }

                            MaterialIcon {
                                visible: (root.media && root.media.players) && (root.media && root.media.players).length > 1
                                text: "expand_more"
                                size: 14
                                color: Colors.onSurfaceVariant
                                Layout.alignment: Qt.AlignVCenter
                                rotation: playerDropdownOverlay.visible ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: playerBadgeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: ((root.media && root.media.players) && (root.media && root.media.players).length > 1) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if ((root.media && root.media.players) && (root.media && root.media.players).length > 1) {
                                    if (!playerDropdownOverlay.visible) {
                                        playerDropdownOverlay.open();
                                    } else {
                                        playerDropdownOverlay.visible = false;
                                    }
                                } else {
                                    (root.media && root.media.cyclePlayer)();
                                }
                            }
                        }
                    }

                    // Loop Mode Button (Sleek Micro-Control)
                    Rectangle {
                        width: 32
                        height: 32
                        radius: (typeof Theme !== "undefined" && Theme.radiusGlassPill !== undefined) ? Math.min(Theme.radiusGlassPill, 16) : 16
                        color: (root.media !== null && (root.media && root.media.loopState) !== 0)
                            ? Qt.alpha(Colors.primary, 0.22)
                            : (loopHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent")
                        border.color: (root.media !== null && (root.media && root.media.loopState) !== 0)
                            ? Qt.alpha(Colors.primary, 0.60)
                            : (loopHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.16) : "transparent")
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: (root.media !== null && (root.media && root.media.loopState) === 1) ? "repeat_one" : "repeat"
                            size: 16
                            color: (root.media !== null && (root.media && root.media.loopState) !== 0) ? Colors.primary : Colors.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: loopHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (root.media && root.media.cycleLoop)()
                        }
                    }
                }
            }

            // Right: Media Avatar (clean, seamless without heavy framing)
            Item {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 200
                Layout.alignment: Qt.AlignVCenter

                MediaAvatar {
                    id: mediaAvatar
                    anchors.fill: parent
                    source: (root.shellState ? root.shellState.mediaAvatar : "")
                    isPlaying: root.media ? root.media.isPlaying === true : false
                }
            }
        }

        // Dropdown Overlay (Floating above RowLayout)
        Item {
            id: playerDropdownOverlay
            anchors.fill: parent
            z: 999
            visible: false

            function open() {
                let pos = playerBadge.mapToItem(playerDropdownOverlay, 0, 0);
                let count = ((root.media && root.media.players) && (root.media && root.media.players).length > 0) ? (root.media && root.media.players).length : 1;
                let menuH = 52 + count * 42;
                let targetX = Math.round(pos.x + (playerBadge.width - playerDropdownMenu.width) / 2);
                let targetY = Math.round(pos.y - menuH - 8);
                playerDropdownMenu.x = Math.max(8, Math.min(playerDropdownOverlay.width - playerDropdownMenu.width - 8, targetX));
                playerDropdownMenu.y = Math.max(8, Math.min(playerDropdownOverlay.height - menuH - 8, targetY));
                playerDropdownOverlay.visible = true;
            }

            // Backdrop dismiss: clicks outside the menu close it
            MouseArea {
                anchors.fill: parent
                onClicked: playerDropdownOverlay.visible = false
            }

            MenuCard {
                id: playerDropdownMenu
                z: 1000
                width: 230

                MenuHeader {
                    title: "Media Sources"
                    materialIcon: "queue_music"
                }

                Repeater {
                    model: (root.media && root.media.players)

                    MenuItem {
                        required property var modelData
                        width: parent.width
                        text: (root.media ? root.media.nameOf(modelData) : "")
                        subtext: modelData.playbackState === 1 ? "Playing" : (modelData.playbackState === 2 ? "Paused" : "Stopped")
                        materialIcon: modelData.playbackState === 1 ? "play_arrow" : "pause"
                        checked: root.media !== null
                            && String(modelData.busName || "") === root.media.activePlayerId
                        onClicked: {
                            if (root.media) root.media.selectPlayer(modelData);
                            playerDropdownOverlay.visible = false;
                        }
                    }
                }
            }
        }
    }
}
