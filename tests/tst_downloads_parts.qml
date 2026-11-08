import QtQuick
import "../dashboard/tabs"
import "../modules/Astral/Apps/Downloads"
import "../modules/Astral/Kernel/config"

/// Per-task connection control.
///
/// The add sheet chose parts for a *new* download; a running task could only be
/// changed by hand over aria2's RPC. The row now owns a small stepper that
/// reads the engine's own `split` (enriched into the snapshot) and writes it
/// back through the daemon, clamped to the same 1..16 as the add sheet.
Item {
    id: testRoot
    width: 900
    height: 700

    DownloadsApp {
        id: dlTab
        visible: false
        width: 880
        height: implicitHeight
        testMode: true
    }

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
        return true;
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Downloads Per-Task Parts Contract");

        // 1. The row reads the engine's split, and falls back to the configured
        //    default only when the engine did not answer.
        assert(dlTab.taskParts({ split: 8 }) === 8, "an engine split must be shown as-is");
        assert(dlTab.taskParts({ split: "12" }) === 12, "aria2 sends strings; the row must parse them");
        assert(dlTab.taskParts({ split: 0 }) === dlTab.defaultSplit,
            "a zero/absent split must fall back to the configured default");
        assert(dlTab.taskParts({}) === dlTab.defaultSplit,
            "a task without a split must not invent a number");

        // 2. The stepper clamps at both ends instead of sending 0/17.
        assert(dlTab.nextParts({ split: 16 }, 1) === 16, "parts must clamp at 16");
        assert(dlTab.nextParts({ split: 1 }, -1) === 1, "parts must clamp at 1");
        assert(dlTab.nextParts({ split: 4 }, 1) === 5, "one step adds one part");

        // 3. Wiring: the tab calls the service, the service calls the daemon.
        const tabSrc = readLocalFile("../modules/Astral/Apps/Downloads/DownloadsApp.qml");
        assert(tabSrc.indexOf("root.downloads.setParts(") >= 0,
            "the stepper must write through the injected download service");
        assert(tabSrc.indexOf("task.split") >= 0 || tabSrc.indexOf("t.split") >= 0,
            "the row must read the task's own split");
        assert(/partsStepper[\s\S]{0,400}status === "active"/.test(tabSrc),
            "the stepper belongs to live tasks (active/waiting/paused)");

        const svcSrc = readLocalFile("../modules/Astral/Kernel/services/DownloadService.qml");
        assert(/function setParts\(gid, parts\)/.test(svcSrc), "DownloadService must expose setParts()");
        assert(svcSrc.indexOf("\"set-parts\"") >= 0, "setParts must call the daemon's set-parts verb");
        assert(/Math\.max\(1, Math\.min\(16/.test(svcSrc), "setParts must clamp 1..16 in the UI too");

        // 4. Backend contract: the CLI verb and the RPC call exist.
        const cliSrc = readLocalFile("../daemon/src/interfaces/cli.rs");
        assert(cliSrc.indexOf("\"set-parts\"") >= 0, "the daemon must expose downloads set-parts");
        const appSrc = readLocalFile("../daemon/src/application/download_service.rs");
        assert(/fn set_parts\(/.test(appSrc), "the use case must own the set-parts rule");
        assert(appSrc.indexOf("change_options") >= 0, "set-parts must reach the port's change_options");
        const adapterSrc = readLocalFile("../daemon/src/infrastructure/aria2_adapter.rs");
        assert(adapterSrc.indexOf("\"changeOption\"") >= 0, "the adapter must call aria2.changeOption");

        console.log("PASS: Downloads Per-Task Parts Contract");
        Qt.exit(0);
    }
}
