import QtQuick
import "../shell/launcher"

// ============================================================================
// Wallpaper Picker Focus Contract
// ============================================================================
// Opening the picker must focus the wallpaper that is currently applied, so the
// carousel starts on the card the user is looking at instead of the first card
// in the list. The wallpaper to focus is injected here: in the shell it is
// `WallpaperEngine.currentWallpaper`, which the daemon answers from the desktop
// containment's own image (the wallpaper actually on screen).
Item {
    id: testRoot
    width: 1200
    height: 300

    readonly property var model: [
        { name: "Abstract", path: "/wallpapers/abstract.png", is_video: false },
        { name: "Air", path: "/wallpapers/air.png", is_video: false },
        { name: "Altai", path: "/wallpapers/altai.png", is_video: false },
        { name: "GreenNekoLady", path: "/wallpapers/green.png", is_video: false },
        { name: "Grey", path: "/wallpapers/grey.png", is_video: false }
    ]

    WallpaperCarousel {
        id: carousel
        anchors.fill: parent
        testMode: true
        testModel: testRoot.model
        currentWallpaperSource: "/wallpapers/green.png"
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Wallpaper Picker Focus Contract");

        assert(carousel.currentIndex === 3,
            "the picker must focus the applied wallpaper (index 3), got " + carousel.currentIndex);

        // The wallpaper can change while the shell runs (Plasma's own settings,
        // another tool). The picker must follow it rather than staying on the
        // card it happened to show first.
        carousel.currentWallpaperSource = "/wallpapers/air.png";
        assert(carousel.currentIndex === 1,
            "focus must follow the applied wallpaper, got " + carousel.currentIndex);

        // An unknown wallpaper (deleted file, a desktop that has none) must not
        // make the carousel jump to an unrelated card.
        carousel.currentWallpaperSource = "/wallpapers/not-in-the-list.png";
        assert(carousel.currentIndex === 1,
            "an unknown wallpaper must leave the focus where it was, got " + carousel.currentIndex);

        // And it must come back when the wallpaper reappears in the list.
        carousel.currentWallpaperSource = "/wallpapers/grey.png";
        assert(carousel.currentIndex === 4,
            "focus must return to the applied wallpaper, got " + carousel.currentIndex);

        console.log("PASS: Wallpaper Picker Focus Contract (opens on the applied wallpaper, follows changes, ignores unknown paths)");
        Qt.exit(0);
    }
}
