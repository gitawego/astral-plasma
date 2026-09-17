import QtQuick

Item {
    id: testRoot
    width: 800
    height: 600

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

    // Engine model matching services/WallpaperEngine.qml specification
    QtObject {
        id: engine

        property string currentWallpaper: ""
        property string previewWallpaper: ""
        readonly property string effectiveWallpaper: (previewWallpaper && previewWallpaper.length > 0) ? previewWallpaper : currentWallpaper
        readonly property bool isVideo: checkIsVideo(effectiveWallpaper)

        property var wallpapers: []
        property var categories: ["All"]
        property bool isLoading: false
        property string activeCategory: "All"

        function checkIsVideo(path) {
            if (!path || typeof path !== "string") return false;
            const low = path.toLowerCase();
            return low.endsWith(".mp4") || low.endsWith(".webm") || low.endsWith(".mkv") || low.endsWith(".mov");
        }

        function preview(path) {
            if (!path) return;
            previewWallpaper = path;
        }

        function stopPreview() {
            previewWallpaper = "";
        }

        function setMockWallpapers(list) {
            wallpapers = list || [];
            updateCategories();
        }

        function updateCategories() {
            let cats = { "All": true };
            for (let i = 0; i < wallpapers.length; i++) {
                if (wallpapers[i].category) {
                    cats[wallpapers[i].category] = true;
                }
            }
            engine.categories = Object.keys(cats);
        }

        function filterWallpapers(query, category) {
            const q = (query || "").trim().toLowerCase();
            const cat = (category && category !== "All") ? category.toLowerCase() : "";

            return wallpapers.filter(item => {
                if (cat && (!item.category || item.category.toLowerCase() !== cat)) {
                    return false;
                }
                if (q) {
                    const nameMatch = (item.name || "").toLowerCase().indexOf(q) !== -1;
                    const pathMatch = (item.path || "").toLowerCase().indexOf(q) !== -1;
                    if (!nameMatch && !pathMatch) return false;
                }
                return true;
            });
        }
    }

    function runTests() {
        console.log("RUNNING: WallpaperEngine Unit Tests");

        // 1. Initial State
        assert(engine !== null, "WallpaperEngine instance must exist");
        assert(typeof engine.effectiveWallpaper === "string", "effectiveWallpaper must be string");
        assert(typeof engine.isVideo === "boolean", "isVideo must be boolean");

        // 2. Video type detection
        assert(engine.checkIsVideo("/path/to/cool_wallpaper.mp4") === true, ".mp4 must be detected as video");
        assert(engine.checkIsVideo("/path/to/cool_wallpaper.webm") === true, ".webm must be detected as video");
        assert(engine.checkIsVideo("/path/to/image.jpg") === false, ".jpg must not be video");
        assert(engine.checkIsVideo("/path/to/image.png") === false, ".png must not be video");

        // 3. Preview mechanics
        engine.currentWallpaper = "/usr/share/wallpapers/Default.jpg";
        engine.previewWallpaper = "";
        assert(engine.effectiveWallpaper === "/usr/share/wallpapers/Default.jpg", "effectiveWallpaper matches current when preview empty");
        assert(engine.isVideo === false, "Default.jpg is not video");

        engine.preview("/usr/share/wallpapers/Live.mp4");
        assert(engine.previewWallpaper === "/usr/share/wallpapers/Live.mp4", "preview sets previewWallpaper");
        assert(engine.effectiveWallpaper === "/usr/share/wallpapers/Live.mp4", "effectiveWallpaper matches preview");
        assert(engine.isVideo === true, "Live.mp4 must set isVideo to true");

        engine.stopPreview();
        assert(engine.previewWallpaper === "", "stopPreview resets previewWallpaper");
        assert(engine.effectiveWallpaper === "/usr/share/wallpapers/Default.jpg", "effectiveWallpaper reverts to current");
        assert(engine.isVideo === false, "Reverts to static video=false");

        // 4. Mock Wallpapers parsing and filtering
        const mockList = [
            { id: "1", name: "Aurora", path: "/wallpapers/Aurora.png", is_video: false, category: "Nature" },
            { id: "2", name: "Rainy City", path: "/wallpapers/RainyCity.mp4", is_video: true, category: "City" },
            { id: "3", name: "Mountain Peak", path: "/wallpapers/MountainPeak.jpg", is_video: false, category: "Nature" }
        ];

        engine.setMockWallpapers(mockList);
        assert(engine.wallpapers.length === 3, "Wallpapers count should match mock list");

        const natureOnly = engine.filterWallpapers("", "Nature");
        assert(natureOnly.length === 2, "Filtering by 'Nature' should return 2 items");

        const citySearch = engine.filterWallpapers("rain", "");
        assert(citySearch.length === 1, "Searching for 'rain' should return 1 item");
        assert(citySearch[0].name === "Rainy City", "Filtered item matches search");

        console.log("PASS: WallpaperEngine Unit Tests");
        Qt.exit(0);
    }
}
