import QtQuick
import QtMultimedia
import "../theme"
import "../config"

Item {
    id: root

    property string source: ""
    property bool isPlaying: false
    property string defaultSource: Qt.resolvedUrl("../theme/assets/bongocat.gif")
    property int fillMode: Image.PreserveAspectFit

    implicitWidth: 200
    implicitHeight: 200

    // Fallback tracking
    property bool isFallbackActive: false
    readonly property string fallbackSource: defaultSource.toString()

    // Validation counter for re-checking removed files
    property int validationKey: 0

    function detectMediaType(urlOrPath) {
        if (!urlOrPath) return "gif";
        let clean = urlOrPath.toString().split("?")[0].split("#")[0].toLowerCase();
        if (clean.endsWith(".mp4") || clean.endsWith(".webm") || clean.endsWith(".mkv") ||
            clean.endsWith(".mov") || clean.endsWith(".avi") || clean.endsWith(".m4v") ||
            clean.endsWith(".ogv") || clean.endsWith(".flv")) {
            return "video";
        }
        if (clean.endsWith(".gif")) {
            return "gif";
        }
        return "image";
    }

    function normalizeUrl(path) {
        if (!path || typeof path !== "string" || path.trim() === "") {
            return defaultSource.toString();
        }
        let p = path.trim();
        if (p.startsWith("~/")) {
            let home = (typeof Quickshell !== "undefined" && Quickshell.env) ? Quickshell.env("HOME") : "/home/hlu";
            p = home + p.substring(1);
        }
        if (p.startsWith("file://") || p.startsWith("http://") || p.startsWith("https://") || p.startsWith("qrc:/")) {
            return p;
        }
        if (p.startsWith("/")) {
            return "file://" + p;
        }
        // Relative path
        return Qt.resolvedUrl(p).toString();
    }

    readonly property string effectiveSource: {
        if (isFallbackActive) return fallbackSource;
        let src = root.source;
        if (!src && typeof Config !== "undefined" && Config.mediaAvatar) {
            src = Config.mediaAvatar;
        }
        if (!src || src.trim() === "") return fallbackSource;

        let norm = normalizeUrl(src);
        if (validationKey > 0 && norm.startsWith("file://")) {
            return norm + "?v=" + validationKey;
        }
        return norm;
    }

    readonly property string activeMediaType: {
        if (isFallbackActive) return "gif";
        return detectMediaType(effectiveSource);
    }

    // Video audio state (strictly muted by default)
    readonly property bool isVideoMuted: audioOutputItem.muted
    readonly property real videoVolume: audioOutputItem.volume

    function triggerFallback() {
        if (!isFallbackActive) {
            console.warn("[MediaAvatar] Media not found or removed. Falling back to default avatar:", fallbackSource);
            isFallbackActive = true;
        }
    }

    function validateMediaSource() {
        let src = root.source;
        if (!src && typeof Config !== "undefined" && Config.mediaAvatar) {
            src = Config.mediaAvatar;
        }
        if (!src || src.trim() === "") {
            triggerFallback();
            return;
        }

        // Re-validate by bumping key
        validationKey++;
    }

    onSourceChanged: {
        isFallbackActive = false;
        if (root.source === "") {
            isFallbackActive = true;
        }
    }

    onActiveMediaTypeChanged: {
        if (activeMediaType !== "video") {
            videoPlayer.stop();
        } else if (isPlaying) {
            videoPlayer.play();
        }
    }

    // Auto re-validate when Media Tab or dashboard becomes visible
    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onDashboardVisibleChanged() {
            if (Config && Config.dashboardVisible && Config.activeDashboardTab === "media") {
                root.validateMediaSource();
            }
        }
        function onActiveDashboardTabChanged() {
            if (Config && Config.dashboardVisible && Config.activeDashboardTab === "media") {
                root.validateMediaSource();
            }
        }
    }

    // 1. Static Image (PNG, JPG, SVG, WebP, etc.)
    Image {
        id: staticImage
        anchors.fill: parent
        fillMode: root.fillMode
        cache: false
        source: (!root.isFallbackActive && root.activeMediaType === "image") ? root.effectiveSource : ""
        asynchronous: false
        smooth: true
        mipmap: true
        visible: !root.isFallbackActive && root.activeMediaType === "image"

        onStatusChanged: {
            if (status === Image.Error && !root.isFallbackActive) {
                Qt.callLater(root.triggerFallback);
            }
        }
    }

    // 2. Animated Image (GIF)
    AnimatedImage {
        id: animatedImage
        anchors.fill: parent
        fillMode: root.fillMode
        cache: false
        source: root.isFallbackActive ? root.fallbackSource : (root.activeMediaType === "gif" ? root.effectiveSource : "")
        playing: root.isPlaying
        speed: 1.0
        asynchronous: false
        visible: root.isFallbackActive || root.activeMediaType === "gif"

        onStatusChanged: {
            if (status === Image.Error && !root.isFallbackActive) {
                Qt.callLater(root.triggerFallback);
            }
        }
    }

    // 3. Video (MP4, WEBM, MKV, etc.)
    MediaPlayer {
        id: videoPlayer
        source: (!root.isFallbackActive && root.activeMediaType === "video") ? root.effectiveSource : ""
        videoOutput: videoOutput
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            id: audioOutputItem
            muted: true
            volume: 0.0
        }

        onErrorOccurred: {
            if (!root.isFallbackActive) {
                console.warn("[MediaAvatar] MediaPlayer error:", videoPlayer.errorString);
                Qt.callLater(root.triggerFallback);
            }
        }

        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.InvalidMedia && !root.isFallbackActive) {
                Qt.callLater(root.triggerFallback);
            }
        }
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
        visible: !root.isFallbackActive && root.activeMediaType === "video"
    }

    // Playback sync for video
    onIsPlayingChanged: {
        if (!root.isFallbackActive && root.activeMediaType === "video") {
            if (root.isPlaying) {
                if (videoPlayer.playbackState !== MediaPlayer.PlayingState) {
                    videoPlayer.play();
                }
            } else {
                if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
                    videoPlayer.pause();
                }
            }
        }
    }

    Component.onCompleted: {
        if (!root.isFallbackActive && root.activeMediaType === "video" && root.isPlaying) {
            videoPlayer.play();
        }
    }
}
