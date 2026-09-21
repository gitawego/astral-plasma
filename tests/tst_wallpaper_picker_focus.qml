import QtQuick
import "../shell/launcher"

// ============================================================================
// Wallpaper Picker Focus Contract
// ============================================================================
// Opening the picker must focus the wallpaper that is currently applied, so the
// carousel starts on the card the user is looking at - and that card must
// actually be inside the viewport. A focused card that is scrolled off-screen
// looks exactly like "the picker is not focusing my wallpaper".
//
// The wallpaper to focus is injected here: in the shell it is
// `WallpaperEngine.currentWallpaper`, which the daemon answers from the desktop
// containment's own image (the wallpaper actually on screen).
Item {
    id: testRoot
    width: 1200
    height: 300

    readonly property var model: [
        { name: "Abstract", path: "/wallpapers/abstract.png", is_video: false },
        { name: "Air", path: "/usr/share/wallpapers/Air/contents/images/1440x2960.png", is_video: false },
        { name: "Altai", path: "/usr/share/wallpapers/Altai/contents/images/1080x1920.png", is_video: false },
        { name: "GreenNekoLady", path: "/wallpapers/green.png", is_video: false },
        { name: "Grey", path: "/wallpapers/grey.png", is_video: false }
    ]

    WallpaperCarousel {
        id: carousel
        x: 0
        y: 0
        width: 1200
        height: 300
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

        // 1. Opens on the applied wallpaper, and that card is on screen.
        assert(carousel.currentIndex === 3,
            "the picker must focus the applied wallpaper (index 3), got " + carousel.currentIndex);
        assert(carousel.focusedCardIsVisible,
            "the focused card must be inside the viewport, not scrolled off-screen");

        // 2. KDE wallpaper packages are directories of resolution variants: the
        //    applied file can be a different one than the card lists. The picker
        //    must still land on that wallpaper's card.
        carousel.currentWallpaperSource = "/usr/share/wallpapers/Air/contents/images/1080x1920.png";
        assert(carousel.currentIndex === 1,
            "a resolution variant must focus its wallpaper's card (index 1), got " + carousel.currentIndex);
        assert(carousel.focusedCardIsVisible,
            "the variant's card must be scrolled into view");

        // 3. An unknown wallpaper (deleted file, a desktop that has none) must
        //    not make the carousel jump to an unrelated card.
        carousel.currentWallpaperSource = "/wallpapers/not-in-the-list.png";
        assert(carousel.currentIndex === 1,
            "an unknown wallpaper must leave the focus where it was, got " + carousel.currentIndex);

        // 4. The picker can open before the view has been laid out (the modal
        //    animates open). The focus must still land on the card once the
        //    layout settles, instead of staying scrolled to the start.
        carousel.visible = false;
        carousel.width = 0;
        carousel.currentWallpaperSource = "/usr/share/wallpapers/Altai/contents/images/1440x900.png";
        carousel.visible = true;
        carousel.width = 1200;
        assert(carousel.currentIndex === 2,
            "the focus must be applied after an unlaid view settles, got " + carousel.currentIndex);
        assert(carousel.focusedCardIsVisible,
            "the card must be scrolled into view once the layout settles");

        // 5. And it must come back when the wallpaper changes again.
        carousel.currentWallpaperSource = "/wallpapers/grey.png";
        assert(carousel.currentIndex === 4,
            "focus must follow the applied wallpaper, got " + carousel.currentIndex);
        assert(carousel.focusedCardIsVisible, "the card must be scrolled into view");

        console.log("PASS: Wallpaper Picker Focus Contract (opens on the applied wallpaper, "
            + "matches resolution variants, survives an unlaid view, ignores unknown paths)");
        Qt.exit(0);
    }
}
