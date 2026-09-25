import QtQuick
import QtQuick.Controls

Item {
    id: root
    width: 300
    height: 300

    Component.onCompleted: {
        try {
            console.log("[TEST] Verifying Arch Linux Astral Plasma theme logo contract");

            // 1. Check UnifiedDock.qml references logo.svg
            const dockSrc = readLocalFile("../shell/UnifiedDock.qml");
            assert(/source:\s*Qt\.resolvedUrl\("\.\.\/theme\/assets\/logo\.svg/.test(dockSrc),
                "UnifiedDock.qml must reference ../theme/assets/logo.svg for launcherIcon");

            // 2. Check logo.svg content
            const logoSrc = readLocalFile("../theme/assets/logo.svg");
            assert(logoSrc.indexOf("<svg") !== -1, "logo.svg must be an SVG file");

            // 3. Verify Arch Linux silhouette path
            assert(logoSrc.indexOf("M 128 12") !== -1 || logoSrc.indexOf("m127.98") !== -1,
                "logo.svg must contain Arch Linux silhouette");

            // 4. Verify slender proportion or Arch silhouette
            assert(logoSrc.indexOf("scale(0.7") !== -1 || logoSrc.indexOf("Slender") !== -1 || logoSrc.indexOf("m127.98") !== -1,
                "logo.svg must use slender proportioned Arch silhouette");

            // 5. Verify palette matching: uses dock icon color #cad3f5
            assert(logoSrc.indexOf("#cad3f5") !== -1,
                "logo.svg must use unified dock slate-white color (#cad3f5)");

            // 6. Verify transparent background (no background rect or opaque fill container)
            assert(logoSrc.indexOf("<rect") === -1,
                "logo.svg must have a 100% transparent background (no rect elements)");

            console.log("PASS: Arch Linux Astral Plasma theme logo test passed!");
            Qt.exit(0);
        } catch (e) {
            console.error("TEST FAILED:", e.message);
            Qt.exit(1);
        }
    }

    function readLocalFile(relativePath) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relativePath), false);
        xhr.send(null);
        return xhr.responseText;
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("ASSERTION FAILED: " + message);
            throw new Error(message);
        }
    }
}
