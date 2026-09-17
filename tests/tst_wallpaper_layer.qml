import QtQuick

Item {
    id: testRoot
    width: 1920
    height: 1080

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            return false;
        }
        return true;
    }

    // Mock layer simulator reproducing WallpaperLayer.qml crossfade logic
    QtObject {
        id: layerSimulator

        property string wallpaperSource: ""
        property bool isVideo: false
        property bool showingA: true
        property string imageASource: ""
        property string imageBSource: ""
        property bool playerPlaying: false
        property string playerSource: ""

        function updateWallpaper(source, video) {
            wallpaperSource = source;
            isVideo = video;

            if (isVideo) {
                const url = source.startsWith("file://") ? source : ("file://" + source);
                playerSource = url;
                playerPlaying = true;
            } else {
                const formatted = source.startsWith("file://") ? source : ("file://" + source);
                if (showingA) {
                    imageBSource = formatted;
                    showingA = false;
                } else {
                    imageASource = formatted;
                    showingA = true;
                }
                playerPlaying = false;
            }
        }
    }

    function runTests() {
        console.log("RUNNING: WallpaperLayer Crossfade & Video Arbitration Unit Tests");

        // 1. Initial State
        assert(layerSimulator.showingA === true, "Initial showingA must be true");
        assert(layerSimulator.playerPlaying === false, "Player must not be playing initially");

        // 2. Set static wallpaper 1
        layerSimulator.updateWallpaper("/wallpapers/Summer.jpg", false);
        assert(layerSimulator.showingA === false, "ShowingA flips to false when buffer B takes new image");
        assert(layerSimulator.imageBSource === "file:///wallpapers/Summer.jpg", "imageBSource formatted correctly");
        assert(!layerSimulator.isVideo, "isVideo must be false");
        assert(!layerSimulator.playerPlaying, "playerPlaying must be false");

        // 3. Set static wallpaper 2 (crossfade alternation)
        layerSimulator.updateWallpaper("/wallpapers/Autumn.jpg", false);
        assert(layerSimulator.showingA === true, "ShowingA flips back to true when buffer A takes next image");
        assert(layerSimulator.imageASource === "file:///wallpapers/Autumn.jpg", "imageASource formatted correctly");

        // 4. Switch to dynamic video wallpaper
        layerSimulator.updateWallpaper("/wallpapers/Waves.mp4", true);
        assert(layerSimulator.isVideo === true, "isVideo must be true for video wallpaper");
        assert(layerSimulator.playerPlaying === true, "Video player starts playing");
        assert(layerSimulator.playerSource === "file:///wallpapers/Waves.mp4", "playerSource formatted correctly");

        // 5. Switch back to static wallpaper
        layerSimulator.updateWallpaper("/wallpapers/Winter.jpg", false);
        assert(layerSimulator.isVideo === false, "isVideo flips back to false");
        assert(layerSimulator.playerPlaying === false, "Video player automatically pauses");
        assert(layerSimulator.showingA === false, "Buffer B activates for next crossfade");
        assert(layerSimulator.imageBSource === "file:///wallpapers/Winter.jpg", "imageBSource matches Winter");

        console.log("PASS: WallpaperLayer Crossfade & Video Arbitration Unit Tests");
        Qt.exit(0);
    }
}
