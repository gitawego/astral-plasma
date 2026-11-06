import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../components"
import "../config"
import "../dashboard/tabs"

/// Dedicated download manager: a real desktop window, not a drawer.
///
/// Like the Copilot and Settings windows, this is a `FloatingWindow`
/// (docs/LESSONS.md §8.9): a normal xdg-toplevel that stacks, moves, resizes
/// and appears in Alt+Tab. The drawer (`DownloadsTab`) remains the quick view;
/// this window hosts the same tab in `windowMode`, so there is one download UI
/// and two hosts - never a second implementation to drift.
///
/// KWin's existing "no titlebar and frame" rule for `wmclass=org.quickshell`
/// covers this toplevel; the card draws its own glass edge and the tab's header
/// starts a compositor-native move.
FloatingWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    visible: Config.downloadsWindowVisible

    // Identity for Alt+Tab and every window list.
    title: "Astral Downloads"
    color: "transparent"

    // A Wayland toplevel cannot resize itself while mapped, so the shell
    // publishes the size to open with and the compositor owns the geometry from
    // then on. Limits travel as the window's size hints.
    readonly property int referenceWidth: (root.targetScreen && root.targetScreen.width > 0)
        ? root.targetScreen.width
        : ((typeof Window !== "undefined" && Window.window && Window.window.width > 0) ? Window.window.width : 1920)
    readonly property int referenceHeight: (root.targetScreen && root.targetScreen.height > 0)
        ? root.targetScreen.height
        : ((typeof Window !== "undefined" && Window.window && Window.window.height > 0) ? Window.window.height : 1080)
    readonly property int minCardWidth: Math.min(760, Math.max(620, root.referenceWidth - 48))
    readonly property int minCardHeight: Math.min(560, Math.max(440, root.referenceHeight - 48))
    readonly property int maxCardWidth: Math.max(root.minCardWidth, Math.min(1180, root.referenceWidth - 48))
    readonly property int maxCardHeight: Math.max(root.minCardHeight, Math.min(900, root.referenceHeight - 48))
    readonly property int preferredWidth: Math.min(root.maxCardWidth,
        Math.max(root.minCardWidth, Math.round(root.referenceWidth * 0.42)))
    readonly property int preferredHeight: Math.min(root.maxCardHeight,
        Math.max(root.minCardHeight, Math.round(root.referenceHeight * 0.72)))

    /// Opens the window with the engine-settings panel showing (IPC / tests).
    function openSettings() {
        if (downloads) downloads.settingsOpen = true;
    }

    // A closed window reopens on the task list, not on whatever sub-sheet was
    // left open the last time.
    onVisibleChanged: {
        if (!visible && downloads) {
            downloads.settingsOpen = false;
            downloads.addDialogOpen = false;
        }
    }

    implicitWidth: root.preferredWidth
    implicitHeight: root.preferredHeight
    minimumSize: Qt.size(root.minCardWidth, root.minCardHeight)
    maximumSize: Qt.size(root.maxCardWidth, root.maxCardHeight)

    // Compositor backdrop blur behind the glass card. The window surface is
    // exactly the card, so the card item is the region.
    BackgroundEffect.blurRegion: Region {
        item: card
    }

    LiquidGlassCard {
        id: card
        anchors.fill: parent
        radius: (typeof Theme !== "undefined") ? Theme.radiusGlassModal : 24
        elevation: 24
        showShadow: false
        color: (typeof Colors !== "undefined") ? Colors.glassPanelSubstrate : "#1e1e2e"

        DownloadsTab {
            id: downloads
            anchors.fill: parent
            windowMode: true
            windowHandle: root
            onCloseRequested: Config.closeDownloadsWindow()
        }
    }
}
