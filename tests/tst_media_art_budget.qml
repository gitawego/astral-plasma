// ============================================================================
// Album-artwork decode budget
// ============================================================================
// Measured on a live session: the artwork cache held covers from 108x108 up to
// 4000x4000 / 8.25 MB, and every consumer of `artUrl` decoded them at their
// native size. A 4000x4000 cover is a 64 MB RGBA texture to fill a 42 px badge,
// and a track change that happened to have a large cover cost far more GPU time
// than one with a small cover - the "random spikes when changing the song".
//
// A sourceSize bound is what fixes that, and it must be ONE shared bound: Qt's
// pixmap cache is keyed by (url, sourceSize), so five consumers each picking
// their own number would decode the same cover five times.
//
// Theme is a singleton and plain `qml` (unlike the shell's scanner) does not
// resolve directory-import singletons, so the budget's *value* is read from
// Theme.qml and then applied to a real Image: the binding contract and the
// behaviour are both asserted, just from different sides.
import QtQuick

Item {
    id: testRoot
    width: 600
    height: 400

    // A bundled 2000x1639 asset, used only so the bound can be observed: it is
    // several times larger than the budget, which is what gives the check teeth.
    readonly property string oversizedAsset: "../modules/Astral/Kernel/theme/assets/liquid-glass-avatar.png"

    // Control: no bound -> the asset's natural size (proves the fixture is big).
    Image {
        id: unboundedProbe
        asynchronous: false
        source: Qt.resolvedUrl(testRoot.oversizedAsset)
    }

    // Bounded with the shipped value, exactly as every art consumer must be.
    Image {
        id: boundedProbe
        asynchronous: false
        source: Qt.resolvedUrl(testRoot.oversizedAsset)
    }

    property int attempts: 0
    property int budgetEdge: 0

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    // Every surface that draws album art. The list is the contract: a new art
    // consumer added without the bound has to be listed here to pass.
    readonly property var artConsumers: [
        "notifications/NotificationPopup.qml",
        "modules/Astral/Apps/Dashboard/DashboardTab.qml",
        "modules/Astral/Kernel/components/HeatmapSpeakerPlayer.qml",
        "modules/Astral/Kernel/components/RadialCoverVisualiser.qml",
        "modules/Astral/Kernel/components/VinylPlayer.qml"
    ]

    function checkSourceContract() {
        const themeSrc = readLocalFile("../modules/Astral/Kernel/theme/Theme.qml");
        assert(themeSrc.length > 0, "Theme.qml must be readable");
        const declared = themeSrc.match(/readonly\s+property\s+int\s+mediaArtPreviewEdge\s*:\s*(\d+)/);
        assert(declared !== null, "Theme.qml must declare mediaArtPreviewEdge as an integer budget");
        testRoot.budgetEdge = parseInt(declared[1]);
        assert(testRoot.budgetEdge > 128,
               "the artwork budget must keep enough pixels for a full-size cover (got " + testRoot.budgetEdge + ")");
        assert(testRoot.budgetEdge <= 1024,
               "the artwork budget must bound a cover texture (got " + testRoot.budgetEdge + ")");

        for (let i = 0; i < artConsumers.length; i++) {
            const path = "../" + artConsumers[i];
            const src = readLocalFile(path);
            assert(src.length > 0, artConsumers[i] + " must be readable");
            assert(src.indexOf("sourceSize.width: Theme.mediaArtPreviewEdge") !== -1,
                   artConsumers[i] + " must decode album art at Theme.mediaArtPreviewEdge (width)");
            assert(src.indexOf("sourceSize.height: Theme.mediaArtPreviewEdge") !== -1,
                   artConsumers[i] + " must decode album art at Theme.mediaArtPreviewEdge (height)");
            // A private number here would be a second size for the same URL, i.e. a
            // second decode of the same cover - the cost this budget exists to remove.
            assert(!/sourceSize\.(width|height)\s*:\s*[0-9]/.test(src),
                   artConsumers[i] + " must not hardcode a sourceSize number (use the shared budget)");
        }

        // The stream and the artwork cache are the two inputs a track change pulls
        // in; the cache side is bounded in the daemon, and that bound must be wired
        // to the write, not to a timer nobody starts.
        const coverSrc = readLocalFile("../daemon/src/infrastructure/media/universal_cover.rs");
        assert(coverSrc.length > 0, "universal_cover.rs must be readable");
        assert(/ArtCache::new\(&self\.cache_dir\)\.prune\(Some\(&target_path\)\)/.test(coverSrc),
               "a cover download must prune the cache it just wrote to");
        const neteaseSrc = readLocalFile("../daemon/src/infrastructure/media/netease_adapter.rs");
        assert(neteaseSrc.length > 0, "netease_adapter.rs must be readable");
        assert(/ArtCache::new\(&cache_dir\)\.prune\(Some\(&target_file\)\)/.test(neteaseSrc),
               "an artwork copy must prune the cache it just wrote to");
    }

    function checkBoundIsEffective() {
        assert(unboundedProbe.status === Image.Ready, "the oversized fixture must load");
        assert(boundedProbe.status === Image.Ready, "the bounded probe must load");

        const natural = Math.max(unboundedProbe.implicitWidth, unboundedProbe.implicitHeight);
        const bounded = Math.max(boundedProbe.implicitWidth, boundedProbe.implicitHeight);
        assert(natural > testRoot.budgetEdge,
               "the fixture must be larger than the budget, otherwise this proves nothing ("
               + natural + " vs " + testRoot.budgetEdge + ")");
        assert(bounded <= testRoot.budgetEdge,
               "a sourceSize budget must cap the decoded edge (decoded " + bounded + ")");
        // Bound, not obliterate: the decoded cover must still fill the surfaces it
        // is drawn on (the largest is a few hundred device pixels).
        assert(bounded >= Math.floor(testRoot.budgetEdge / 2),
               "the bounded cover must stay usable, not thumbnail-sized (decoded " + bounded + ")");

        const unboundedBytes = unboundedProbe.implicitWidth * unboundedProbe.implicitHeight * 4;
        const boundedBytes = boundedProbe.implicitWidth * boundedProbe.implicitHeight * 4;
        assert(boundedBytes * 4 < unboundedBytes,
               "the budget must cut the cover texture by at least 4x ("
               + Math.round(unboundedBytes / 1048576) + " MB -> " + Math.round(boundedBytes / 1024) + " KB)");
    }

    // phase 0 -> read the shipped budget and apply it to the probe
    // phase 1 -> wait for both probes, then assert the bound held
    property int phase: 0

    function probing() {
        if (testRoot.phase === 0) {
            testRoot.checkSourceContract();
            boundedProbe.sourceSize.width = testRoot.budgetEdge;
            boundedProbe.sourceSize.height = testRoot.budgetEdge;
            testRoot.phase = 1;
            return;
        }
        const loaded = unboundedProbe.status === Image.Ready && boundedProbe.status === Image.Ready;
        const applied = loaded && boundedProbe.implicitWidth !== unboundedProbe.implicitWidth;
        testRoot.attempts++;
        if (applied) {
            testRoot.checkBoundIsEffective();
            console.log("PASS: album artwork is decoded inside one shared budget (" + testRoot.budgetEdge + " px)");
            Qt.exit(0);
            return;
        }
        if (testRoot.attempts > 80) {
            testRoot.assert(false, "the sourceSize budget was never applied to the probe (status "
                             + unboundedProbe.status + "/" + boundedProbe.status
                             + ", sizes " + unboundedProbe.implicitWidth + "/" + boundedProbe.implicitWidth + ")");
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: testRoot.probing()
    }
}
