import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import "../services"
import "../theme"
import "../config"

PanelWindow {
    id: root

    property ShellScreen targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    screen: targetScreen

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "caelestia-wallpaper"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "#0a0a0c"

    readonly property string wallpaperSource: (typeof WallpaperEngine !== "undefined") ? WallpaperEngine.effectiveWallpaper : ""
    readonly property bool isVideo: (typeof WallpaperEngine !== "undefined") ? WallpaperEngine.isVideo : false

    // State tracking for double-buffered crossfade
    property bool showingA: true

    onWallpaperSourceChanged: {
        if (!wallpaperSource) return;
        if (isVideo) {
            const url = wallpaperSource.startsWith("file://") ? wallpaperSource : ("file://" + wallpaperSource);
            player.source = url;
            player.play();
        } else {
            const formatted = (wallpaperSource.startsWith("file://") ? "" : "file://") + wallpaperSource;
            if (showingA) {
                imageB.source = formatted;
                showingA = false;
            } else {
                imageA.source = formatted;
                showingA = true;
            }
            if (player.playbackState === MediaPlayer.PlayingState) {
                player.pause();
            }
        }
    }

    // Double-buffered static image layers for seamless crossfade
    Image {
        id: imageA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        opacity: (!root.isVideo && root.showingA) ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }
    }

    Image {
        id: imageB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        opacity: (!root.isVideo && !root.showingA) ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }
    }

    // Hardware-accelerated dynamic video wallpaper surface
    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: root.isVideo
        opacity: root.isVideo ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animExpressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
            }
        }
    }

    MediaPlayer {
        id: player
        videoOutput: videoOutput
        loops: MediaPlayer.Infinite
        audioOutput: null // Zero audio footprint
    }

    Component.onCompleted: {
        if (wallpaperSource) {
            const formatted = (wallpaperSource.startsWith("file://") ? "" : "file://") + wallpaperSource;
            if (isVideo) {
                player.source = formatted;
                player.play();
            } else {
                imageA.source = formatted;
                showingA = true;
            }
        }
    }
}
