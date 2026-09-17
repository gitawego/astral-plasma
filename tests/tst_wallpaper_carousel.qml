import QtQuick
import "../shell/launcher"

Item {
    id: testRoot
    width: 1200
    height: 400

    property string lastSelected: ""
    property string lastPreviewed: ""
    property bool cancelledCalled: false

    WallpaperCarousel {
        id: carousel
        anchors.centerIn: parent
        testMode: true
        testModel: [
            { id: "1", name: "Pink.png", path: "/wallpapers/pink.png", thumbnail_path: "/wallpapers/thumb_1.jpg", is_video: false },
            { id: "2", name: "Showdown.jpg", path: "/wallpapers/showdown.jpg", thumbnail_path: "/wallpapers/thumb_2.jpg", is_video: false },
            { id: "3", name: "Violet", path: "/wallpapers/violet.png", thumbnail_path: "/wallpapers/thumb_3.jpg", is_video: false },
            { id: "4", name: "City-Horizon.png", path: "/wallpapers/city-horizon.png", thumbnail_path: "/wallpapers/thumb_4.jpg", is_video: false },
            { id: "5", name: "Octogirl-River.mp4", path: "/wallpapers/octogirl-river.mp4", thumbnail_path: "/wallpapers/thumb_5.jpg", is_video: true }
        ]

        onWallpaperSelected: (p) => testRoot.lastSelected = p
        onWallpaperPreviewed: (p) => testRoot.lastPreviewed = p
        onCancelled: testRoot.cancelledCalled = true
    }

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

    function runTests() {
        console.log("RUNNING: WallpaperCarousel 5-Card Navigation & Live Preview Unit Tests");

        // 1. Initial State: 5 cards
        assert(carousel.wallpapersList.length === 5, "Wallpapers list count should be 5");
        assert(carousel.currentIndex === 0, "Initial currentIndex should be 0");

        // 2. Format names correctly (lowercase without extension)
        assert(carousel.formatWallpaperName("Pink.png", "") === "pink", "Pink.png formatted to pink");
        assert(carousel.formatWallpaperName("City-Horizon.png", "") === "city-horizon", "City-Horizon formatted to city-horizon");
        assert(carousel.formatWallpaperName("Octogirl-River.mp4", "") === "octogirl-river", "Octogirl-River formatted to octogirl-river");

        // 3. Navigation Next
        carousel.selectNext();
        assert(carousel.currentIndex === 1, "After selectNext, currentIndex should be 1");
        assert(carousel.wallpapersList[carousel.currentIndex].path === "/wallpapers/showdown.jpg", "Current item is showdown");
        assert(testRoot.lastPreviewed === "/wallpapers/showdown.jpg", "Instant preview signal fired for showdown");

        // 4. Navigation to index 2 (violet)
        carousel.selectNext();
        assert(carousel.currentIndex === 2, "After selectNext again, currentIndex should be 2");
        assert(carousel.wallpapersList[carousel.currentIndex].name === "Violet", "Current item is Violet");
        assert(testRoot.lastPreviewed === "/wallpapers/violet.png", "Instant preview signal fired for violet");

        // 5. Navigation Previous
        carousel.selectPrevious();
        assert(carousel.currentIndex === 1, "After selectPrevious, currentIndex should be 1");

        // 6. Wrap around backwards
        carousel.selectPrevious(); // index 0
        assert(carousel.currentIndex === 0, "Current index is 0");
        carousel.selectPrevious(); // wraps to index 4
        assert(carousel.currentIndex === 4, "Current index wraps to 4 on selectPrevious from 0");
        assert(carousel.wallpapersList[carousel.currentIndex].name === "Octogirl-River.mp4", "Wrapped item is Octogirl-River");

        // 7. Apply Current Selection
        carousel.applyCurrent();
        assert(testRoot.lastSelected === "/wallpapers/octogirl-river.mp4", "Selected wallpaper committed on applyCurrent");

        // 8. Cancel
        carousel.cancel();
        assert(testRoot.cancelledCalled === true, "Cancel signal should fire");

        console.log("PASS: WallpaperCarousel 5-Card Navigation & Live Preview Unit Tests");
        Qt.exit(0);
    }
}
