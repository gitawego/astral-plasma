import QtQuick
import "../settings_gui/pages"

/// A settings file written before volume/brightness moved to the right-edge rail
/// may still list `audio` / `brightness` status icons. The Settings page must not
/// offer switches for indicators the dock no longer renders: it filters to the
/// known set, so the list and its "N of M shown" header stay honest.
Item {
    id: testRoot
    width: 600
    height: 800

    StatusIconsPage {
        id: page
        width: parent.width
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: {
            console.log("RUNNING: Status Icons Stale-Id Filtering");

            assert(page.statusIcons !== undefined, "StatusIconsPage must publish `statusIcons`");
            const known = page.knownIconIds;
            for (let i = 0; i < page.statusIcons.length; ++i) {
                const id = page.statusIcons[i] && page.statusIcons[i].id;
                assert(known.indexOf(id) !== -1,
                    "StatusIconsPage must not offer a switch for unknown/removed id '" + id + "'");
            }
            assert(known.indexOf("audio") === -1,
                "audio must not be in the known indicator set (the right rail owns volume)");
            assert(known.indexOf("brightness") === -1,
                "brightness must not be in the known indicator set (the right rail owns brightness)");
            assert(known.indexOf("network") !== -1 && known.indexOf("bluetooth") !== -1,
                "the surviving indicators must stay available");
            assert(page.enabledIconCount <= page.statusIcons.length,
                "the header count must never exceed the rendered list");

            console.log("PASS: Status Icons Stale-Id Filtering");
            Qt.exit(0);
        }
    }
}
