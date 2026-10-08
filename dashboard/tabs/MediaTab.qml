import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../menus"
import "../../config"

Item {
    id: root

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

                readonly property bool isSpeakerStyle: (typeof Config !== "undefined") &&
                    (Config.mediaVisualizerStyle === "speaker" || Config.mediaVisualizerStyle === "heatmap")
                readonly property bool isCyberpunk: (typeof Theme !== "undefined" && Theme.isCyberpunk)

                // Radial Visualizer (Spectrum halo around circular album art - Cyberpunk or Radial style)
                RadialCoverVisualiser {
                    id: radialViz
                    anchors.centerIn: parent
                    width: 240
                    height: 240
                    visible: visualizerSlot.isCyberpunk || !visualizerSlot.isSpeakerStyle
                    isPlaying: MprisMedia.isPlaying
                    artUrl: MprisMedia.artUrl
                    title: MprisMedia.title
                    artist: MprisMedia.artist
                    isTargetVisible: (typeof Config !== "undefined") ? (Config.dashboardVisible && Config.activeDashboardTab === "media" && visible) : false
                }

                // Original Heatmap Speaker Player (Pulsing speaker cone with orbiting rainbow notes & beads)
                HeatmapSpeakerPlayer {
                    id: speakerViz
                    anchors.centerIn: parent
                    width: 240
                    height: 240
                    visible: !visualizerSlot.isCyberpunk && visualizerSlot.isSpeakerStyle
                    isPlaying: MprisMedia.isPlaying
                    artUrl: MprisMedia.artUrl
                    title: MprisMedia.title
                    artist: MprisMedia.artist
                    isTargetVisible: (typeof Config !== "undefined") ? (Config.dashboardVisible && Config.activeDashboardTab === "media" && visible) : false
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
                        if (typeof Config !== "undefined" && Config.setMediaVisualizerStyle) {
                            Config.setMediaVisualizerStyle(visualizerSlot.isSpeakerStyle ? "radial" : "speaker");
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
                    text: MprisMedia.title || "No Media Playing"
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
                    text: MprisMedia.album || ""
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
                    text: MprisMedia.artist || "Unknown Artist"
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
                        interactive: (typeof MprisMedia !== "undefined") ? MprisMedia.canGoPrevious : true
                        opacity: ((typeof MprisMedia !== "undefined") ? MprisMedia.canGoPrevious : true) ? 1.0 : 0.40
                        onClicked: MprisMedia.previous()
                    }

                    // Play / Pause (Hero Circular Liquid Glass Gem)
                    LiquidGlassButton {
                        implicitWidth: 48
                        implicitHeight: 48
                        paddingHorizontal: 8
                        paddingVertical: 8
                        isPrimary: true
                        iconText: (typeof MprisMedia !== "undefined" && MprisMedia.isPlaying) ? "pause" : "play_arrow"
                        iconSize: 24
                        accentColor: Colors.primary
                        elevation: 6
                        onClicked: MprisMedia.playPause()
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
                        interactive: (typeof MprisMedia !== "undefined") ? MprisMedia.canGoNext : true
                        opacity: ((typeof MprisMedia !== "undefined") ? MprisMedia.canGoNext : true) ? 1.0 : 0.40
                        onClicked: MprisMedia.next()
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
                        : Math.min(1.0, Math.max(0.0, MprisMedia.progress))

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
                            visible: MprisMedia.length > 0
                            opacity: MprisMedia.canSeek ? 1.0 : 0.60

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
                        enabled: (typeof MprisMedia !== "undefined") && MprisMedia.canSeek && MprisMedia.length > 0
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
                                MprisMedia.seekTo(frac);
                            }
                        }
                        onCanceled: {
                            isDragging = false;
                        }
                        onClicked: mouse => {
                            if (!enabled) return;
                            let frac = Math.max(0.0, Math.min(1.0, mouse.x / width));
                            MprisMedia.seekTo(frac);
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
                                ? (sliderMouse.dragFraction * (MprisMedia.length || 0))
                                : (MprisMedia.position || 0));
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
                            const secs = Math.floor(MprisMedia.length || 0);
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
                        color: (typeof MprisMedia !== "undefined" && MprisMedia.shuffle)
                            ? Qt.alpha(Colors.primary, 0.22)
                            : (shufHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent")
                        border.color: (typeof MprisMedia !== "undefined" && MprisMedia.shuffle)
                            ? Qt.alpha(Colors.primary, 0.60)
                            : (shufHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.16) : "transparent")
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "shuffle"
                            size: 16
                            color: (typeof MprisMedia !== "undefined" && MprisMedia.shuffle) ? Colors.primary : Colors.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: shufHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MprisMedia.toggleShuffle()
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
                                text: (MprisMedia.players && MprisMedia.players.length > 1) ? "graphic_eq" : "music_note"
                                size: 14
                                color: Colors.primary
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                text: MprisMedia.identity || "Media Player"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontLabelSmall
                                font.weight: Font.Medium
                                color: (playerBadgeMouse.containsMouse || playerDropdownOverlay.visible) ? Colors.onPrimaryContainer : Colors.m3onSurface
                                Layout.alignment: Qt.AlignVCenter
                                style: Text.Outline
                                styleColor: Colors.glassTextHalo
                            }

                            MaterialIcon {
                                visible: MprisMedia.players && MprisMedia.players.length > 1
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
                            cursorShape: (MprisMedia.players && MprisMedia.players.length > 1) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (MprisMedia.players && MprisMedia.players.length > 1) {
                                    if (!playerDropdownOverlay.visible) {
                                        playerDropdownOverlay.open();
                                    } else {
                                        playerDropdownOverlay.visible = false;
                                    }
                                } else {
                                    MprisMedia.cyclePlayer();
                                }
                            }
                        }
                    }

                    // Loop Mode Button (Sleek Micro-Control)
                    Rectangle {
                        width: 32
                        height: 32
                        radius: (typeof Theme !== "undefined" && Theme.radiusGlassPill !== undefined) ? Math.min(Theme.radiusGlassPill, 16) : 16
                        color: (typeof MprisMedia !== "undefined" && MprisMedia.loopState !== 0)
                            ? Qt.alpha(Colors.primary, 0.22)
                            : (loopHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent")
                        border.color: (typeof MprisMedia !== "undefined" && MprisMedia.loopState !== 0)
                            ? Qt.alpha(Colors.primary, 0.60)
                            : (loopHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.16) : "transparent")
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: (typeof MprisMedia !== "undefined" && MprisMedia.loopState === 1) ? "repeat_one" : "repeat"
                            size: 16
                            color: (typeof MprisMedia !== "undefined" && MprisMedia.loopState !== 0) ? Colors.primary : Colors.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: loopHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MprisMedia.cycleLoop()
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
                    source: Config.mediaAvatar
                    isPlaying: MprisMedia.isPlaying
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
                let count = (MprisMedia.players && MprisMedia.players.length > 0) ? MprisMedia.players.length : 1;
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
                    model: MprisMedia.players

                    MenuItem {
                        required property var modelData
                        width: parent.width
                        text: MprisMedia.playerIdentity(modelData)
                        subtext: modelData.playbackState === 1 ? "Playing" : (modelData.playbackState === 2 ? "Paused" : "Stopped")
                        materialIcon: modelData.playbackState === 1 ? "play_arrow" : "pause"
                        checked: MprisMedia.isPlayerActive(modelData)
                        onClicked: {
                            MprisMedia.selectPlayer(modelData);
                            playerDropdownOverlay.visible = false;
                        }
                    }
                }
            }
        }
    }
}
