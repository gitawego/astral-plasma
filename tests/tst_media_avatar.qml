import QtQuick
import QtMultimedia
import "../components"
import "../theme"

Item {
    id: testRoot
    width: 600
    height: 600

    property string gojoPath: "/home/hlu/Downloads/Gojo-Satoru-Jujutsu-Kaisen-Character.png"
    property string sampleVideo: "/home/hlu/Downloads/soramane.mp4"

    MediaAvatar {
        id: testAvatar
        width: 140
        height: 140
        source: testRoot.gojoPath
        isPlaying: true
    }

    Timer {
        id: stepTimer
        interval: 60
        repeat: false
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
        }
    }

    Timer {
        interval: 40
        running: true
        repeat: false
        onTriggered: runPart1()
    }

    function runPart1() {
        console.log("RUNNING: MediaAvatar QML Tests - Part 1");

        // 1. Format Sniffing
        assert(testAvatar.detectMediaType("cat.gif") === "gif", "cat.gif must be gif");
        assert(testAvatar.detectMediaType("CAT.GIF?param=1") === "gif", "uppercase with params must be gif");
        assert(testAvatar.detectMediaType("/path/to/movie.mp4") === "video", "mp4 must be video");
        assert(testAvatar.detectMediaType("movie.webm") === "video", "webm must be video");
        assert(testAvatar.detectMediaType("clip.mkv") === "video", "mkv must be video");
        assert(testAvatar.detectMediaType("logo.svg") === "image", "svg must be image");
        assert(testAvatar.detectMediaType("photo.jpg") === "image", "jpg must be image");
        assert(testAvatar.detectMediaType("photo.png") === "image", "png must be image");
        assert(testAvatar.detectMediaType("avatar.webp") === "image", "webp must be image");
        console.log("PASS: Media format detection verified");

        // 2. Path normalization
        assert(testAvatar.normalizeUrl("file:///abc.png") === "file:///abc.png", "file:// must remain intact");
        assert(testAvatar.normalizeUrl("/home/user/pic.png") === "file:///home/user/pic.png", "absolute path must gain file://");
        assert(testAvatar.normalizeUrl("").length > 0, "empty path must resolve to default asset");
        console.log("PASS: Path normalization verified");

        // 3. User Gojo PNG test
        assert(testAvatar.activeMediaType === "image", "Gojo avatar must have activeMediaType == 'image'");
        assert(testAvatar.effectiveSource.indexOf("Gojo-Satoru-Jujutsu-Kaisen-Character.png") !== -1, "effectiveSource must contain Gojo filename");
        console.log("PASS: Gojo PNG source binding verified");

        // 4. Video configuration & strictly muted audio
        testAvatar.source = testRoot.sampleVideo;
        assert(testAvatar.activeMediaType === "video", "Sample video must have activeMediaType == 'video'");
        assert(testAvatar.isVideoMuted === true, "Video audio MUST be muted by default");
        assert(testAvatar.videoVolume === 0.0, "Video volume MUST be 0.0 by default");
        console.log("PASS: Video audio strictly muted by default verified");

        // 5. Automatic fallback behavior on missing/removed media
        testAvatar.source = "/nonexistent/invalid/file_path_12345.png";
        stepTimer.triggered.connect(runPart2);
        stepTimer.restart();
    }

    function runPart2() {
        console.log("RUNNING: MediaAvatar QML Tests - Part 2 (Missing image fallback)");
        assert(testAvatar.isFallbackActive === true, "Fallback active flag must automatically be set on missing file");
        assert(testAvatar.activeMediaType === "gif", "Fallback must automatically revert to default gif");
        assert(testAvatar.effectiveSource === testAvatar.fallbackSource, "effectiveSource must equal fallbackSource");
        console.log("PASS: Automatic missing image fallback verified");

        // 6. Test missing video fallback
        testAvatar.source = "file:///nonexistent/invalid/video_file_99999.mp4";
        stepTimer.triggered.disconnect(runPart2);
        stepTimer.triggered.connect(runPart3);
        stepTimer.restart();
    }

    function runPart3() {
        console.log("RUNNING: MediaAvatar QML Tests - Part 3 (Missing video fallback)");
        assert(testAvatar.isFallbackActive === true, "Fallback active flag must automatically be set on missing video");
        assert(testAvatar.activeMediaType === "gif", "Missing video must fall back to default gif");
        console.log("PASS: Automatic missing video fallback verified");

        // 7. Test re-validation trigger on removed file
        testAvatar.validateMediaSource();
        assert(testAvatar.isFallbackActive === true, "validateMediaSource retains fallback if file still missing");
        console.log("PASS: validateMediaSource verified");

        // 8. Restore valid Gojo
        testAvatar.source = testRoot.gojoPath;
        stepTimer.triggered.disconnect(runPart3);
        stepTimer.triggered.connect(runPart4);
        stepTimer.restart();
    }

    function runPart4() {
        console.log("RUNNING: MediaAvatar QML Tests - Part 4 (Restoration)");
        assert(testAvatar.isFallbackActive === false, "Restoring valid Gojo clears fallback flag");
        assert(testAvatar.activeMediaType === "image", "Valid source restores image type");
        console.log("PASS: Source restoration verified");

        console.log("ALL MEDIA AVATAR TESTS PASSED!");
        Qt.exit(0);
    }
}
