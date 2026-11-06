import QtQuick
import "../dashboard/tabs"

/// The window's stage must not move when the segment changes.
///
/// The empty state used to be a 150 px item parked in the middle of the
/// ColumnLayout while the task list filled from the top, so switching to
/// "Finished" (with an item) made the whole composition jump. Both now share
/// one full-height stage, and the ledger keeps the window's bottom edge stable.
Item {
    id: testRoot
    width: 1000
    height: 900

    DownloadsTab {
        id: winTab
        anchors.fill: parent
        windowMode: true
        testMode: true
        testTasks: []
        segment: "active"
    }

    property real emptyStageY: -1
    property real segmentX: -1

    Timer {
        interval: 150
        running: true
        repeat: false
        onTriggered: {
            console.log("RUNNING: Downloads Window Stage Stability");
            testRoot.emptyStageY = winTab.emptyStateItem.y;
            testRoot.segmentX = winTab.segmentBarItem.x;

            assert(winTab.showEmptyState, "no tasks → empty state");
            assert(winTab.emptyStateItem.height > 300,
                "in the window the empty state fills the stage, got " + winTab.emptyStateItem.height);
            assert(winTab.ledgerItem.visible, "the window ledger is visible");

            winTab.testTasks = [
                { gid: "g1", name: "file.bin", status: "complete",
                  completed_length: 11900000000, total_length: 11900000000, dir: "/tmp" }
            ];
            winTab.segment = "finished";
            handoff.start();
        }
    }

    Timer {
        id: handoff
        interval: 120
        repeat: false
        onTriggered: {
            assert(winTab.showTaskList, "one finished task → list");
            const listY = winTab.taskListFlickableItem.y;
            assert(Math.abs(listY - testRoot.emptyStageY) <= 1,
                "the stage top must not move between empty and list, got " + listY + " vs " + testRoot.emptyStageY);
            // The Clear action used to be inserted between the segments and
            // Add, shifting the tab strip left under the pointer when a
            // finished item appeared. The strip must stay put.
            assert(Math.abs(winTab.segmentBarItem.x - testRoot.segmentX) <= 1,
                "the segment strip must not move when Clear appears, got "
                    + winTab.segmentBarItem.x + " vs " + testRoot.segmentX);
            assert(winTab.clearButtonItem.visible, "finished with an item shows Clear");
            assert(winTab.clearButtonItem.mapToItem(winTab, 0, 0).y > winTab.height * 0.6,
                "Clear belongs to the bottom ledger, not the header row");
            assert(winTab.ledgerText.indexOf("1 FINISHED") === 0,
                "the ledger names the finished count, got " + winTab.ledgerText);
            assert(winTab.ledgerText.indexOf("GiB") !== -1,
                "the ledger carries the finished size, got " + winTab.ledgerText);
            console.log("PASS: Downloads Window Stage Stability");
            Qt.exit(0);
        }
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
}
