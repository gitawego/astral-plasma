import QtQuick

// ============================================================================
// Dynamic Palette Reload Contract
// ============================================================================
// The dynamic accent comes from a generated palette file
// (`$XDG_CACHE_HOME/astral-plasma/colors.json`, produced by matugen from the
// wallpaper). That file is rewritten whenever the wallpaper changes or the
// palette is regenerated - while the shell keeps running.
//
// Quickshell's FileView reads its file once and does NOT watch it unless
// `watchChanges` is set. Without it the shell keeps the palette it loaded at
// start-up, so the accent stops following the wallpaper and shows the colours
// of whatever wallpaper was active when the shell started (reported as "the
// dynamic accent is pinky").
//
// These assertions pin the reload path: watched file, XDG-aware location, and a
// loader that actually applies the parsed colours.
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(condition, message) {
        if (!condition) {
            console.log("FAIL: " + message);
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
        console.log("RUNNING: Dynamic Palette Reload Contract");

        const colors = readLocalFile("../theme/Colors.qml");
        assert(colors.length > 1000, "theme/Colors.qml must be readable by the harness");

        // Isolate the palette loader.
        const start = colors.indexOf("FileView {");
        assert(start >= 0, "Colors.qml must declare a FileView for the palette cache");
        const end = colors.indexOf("}", colors.indexOf("onLoaded", start));
        const loader = colors.substring(start, end > start ? end + 1 : start + 2000);

        // 1. The file must be watched, or a regenerated palette never reaches the UI.
        assert(/watchChanges\s*:\s*true/.test(loader),
            "the palette FileView must set `watchChanges: true`: the generated palette is "
            + "rewritten while the shell runs, and without watching, the accent keeps the "
            + "colours of the wallpaper that was active at start-up");

        // 2. The path must honour XDG_CACHE_HOME (the daemon and generate_palette.sh
        //    write there), with the conventional $HOME/.cache fallback.
        assert(/XDG_CACHE_HOME/.test(colors),
            "the palette path must honour XDG_CACHE_HOME: the palette writer uses the XDG "
            + "cache dir, and a hardcoded $HOME path reads a file that is never written");
        assert(/astral-plasma\/colors\.json/.test(colors),
            "the palette file must be <cache>/astral-plasma/colors.json");

        // 3. A (re)load must actually apply the parsed palette.
        //    `loaded` fires on the first read only - a watched change emits
        //    `fileChanged`, so the reload path must be handled too or the
        //    palette stays stale for the whole session.
        assert(/onLoaded\s*:/.test(loader), "the loader must handle onLoaded");
        assert(/onFileChanged\s*:\s*colorsCache\.reload\(\)/.test(loader),
            "onFileChanged must call reload(): the signal only announces the change, so the "
            + "file contents are still the old ones until reload() re-reads them (after which "
            + "`loaded` applies the new palette)");
        const apply = colors.match(/function\s+applyPalette\s*\([^)]*\)\s*\{([\s\S]*?)\n    \}/);
        assert(apply !== null, "Colors.qml must expose an applyPalette() that parses the file");
        assert(/dynamicPalette\s*=\s*parsed\.colors/.test(apply[1]),
            "applyPalette() must assign parsed.colors to dynamicPalette, or a reload is a no-op");
        assert(/onLoaded\s*:\s*root\.applyPalette\(\)/.test(loader),
            "onLoaded must call applyPalette(): every completed read (first load and each "
            + "reload) applies the palette through one code path");

        console.log("PASS: Dynamic Palette Reload Contract (palette file is watched, XDG-aware, "
            + "and reloads apply the parsed colours)");
        Qt.exit(0);
    }
}
