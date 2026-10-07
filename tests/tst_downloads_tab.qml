import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../config"
import "../shell"
import "../dashboard/tabs"

// ============================================================================
// Downloads Tab & 6-Tab Dropdown + Border Effect Unit Tests (TDD, D1–D15)
// ============================================================================
// Verifies:
// 1. DownloadsTab pure helpers: actionsFor / actionIcon / statusIcon /
//    taskProgress / taskEta / statusColor (no daemon needed).
// 2. DownloadsTab composition: hero header, aggregate progress, M3 segmented
//    control with sliding indicator, composed empty state, add sheet with the
//    1..16 split stepper, and a bounded task list (clamp + scroll).
// 3. CentralDropdown 6-tab registration (downloads between workspaces & ai)
//    + sliding indicator index mapping + tab-strip overflow contract.
// 4. DownloadBorderEffect geometry contract: inside borderT, capped widths,
//    idle timers gated (0% idle CPU), specular nexus present.
Item {
    id: testRoot
    width: 1280
    height: 900

    DownloadsTab {
        id: dlTab
        visible: false
        width: 948
        height: implicitHeight
        testMode: true
    }

    CentralDropdown {
        id: dropdown
        dropX: 150
        dropW: 980
        visible: false
    }

    DownloadBorderEffect {
        id: dlEffect
        width: 1920
        height: 1080
        totalProgress: 0.42
        totalSpeed: 1048576
        activeCount: 2
        indeterminate: false
        effectEnabled: true
        cornerBusy: false
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    // Deferred assertion runner: Repeater/Column geometry settles one frame
    // after a model swap, so list contracts are asserted after the hand-off.
    property var deferredFn: null

    Timer {
        id: deferredTimer
        interval: 60
        repeat: false
        onTriggered: {
            const fn = testRoot.deferredFn;
            testRoot.deferredFn = null;
            fn();
        }
    }

    function deferredRun(fn) {
        testRoot.deferredFn = fn;
        deferredTimer.restart();
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            console.log("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function runTests() {
        console.log("RUNNING: DownloadsTab & 6-Tab Dropdown & Border Effect Unit Tests");

        // ---- 1. Tab instantiation & glass contract ----
        assert(dlTab !== null, "DownloadsTab must instantiate");
        assert(dlTab.implicitWidth >= 680, "DownloadsTab implicitWidth >= 680, got " + dlTab.implicitWidth);
        assert(dlTab.implicitHeight >= 200, "DownloadsTab implicitHeight >= 200 (compact header line), got " + dlTab.implicitHeight);

        // ---- 2. actionsFor verb mapping (D5) ----
        assert(JSON.stringify(dlTab.actionsFor("active")) === JSON.stringify(["pause", "cancel"]),
            "active → pause/cancel");
        assert(JSON.stringify(dlTab.actionsFor("waiting")) === JSON.stringify(["resume", "cancel"]),
            "waiting → resume/cancel");
        assert(JSON.stringify(dlTab.actionsFor("paused")) === JSON.stringify(["resume", "cancel"]),
            "paused → resume/cancel");
        assert(JSON.stringify(dlTab.actionsFor("error")) === JSON.stringify(["retry", "remove"]),
            "error → retry/remove");
        assert(JSON.stringify(dlTab.actionsFor("complete")) === JSON.stringify(["open", "folder", "remove"]),
            "complete → open/folder/remove");
        assert(JSON.stringify(dlTab.actionsFor("Active")) === JSON.stringify(["pause", "cancel"]),
            "status match must be case-insensitive");

        // ---- 3. actionIcon + statusIcon mapping ----
        assert(dlTab.actionIcon("pause") === "pause", "pause icon");
        assert(dlTab.actionIcon("resume") === "play_arrow", "resume icon");
        assert(dlTab.actionIcon("cancel") === "close", "cancel icon");
        assert(dlTab.actionIcon("retry") === "refresh", "retry icon");
        assert(dlTab.actionIcon("open") === "open_in_new", "open icon");
        assert(dlTab.actionIcon("folder") === "folder", "folder icon");
        assert(dlTab.actionIcon("remove") === "delete", "remove icon");
        assert(dlTab.statusIcon("complete") === "check_circle", "complete status icon");
        assert(dlTab.statusIcon("error") === "error", "error status icon");
        assert(dlTab.statusIcon("paused") === "pause", "paused status icon");
        assert(dlTab.statusIcon("active") === "download", "active status icon");
        assert(String(dlTab.statusColor("error")) !== String(dlTab.statusColor("active")), "error tint differs from active");

        // ---- 4. taskProgress clamps + indeterminate guard ----
        assert(dlTab.taskProgress({ completed_length: 50, total_length: 100 }) === 0.5, "progress 0.5");
        assert(dlTab.taskProgress({ completed_length: 150, total_length: 100 }) === 1.0, "progress clamps at 1.0");
        assert(dlTab.taskProgress({ completed_length: 5, total_length: 0 }) === 0.0, "unknown total → 0.0");
        assert(dlTab.taskProgress(null) === 0.0, "null task → 0.0");

        // ---- 5. taskEta ----
        assert(dlTab.taskEta({ total_length: 1000, completed_length: 0, download_speed: 100 }) === "10s", "ETA 10s");
        assert(dlTab.taskEta({ total_length: 100, completed_length: 100, download_speed: 100 }) === "done", "ETA done");
        assert(dlTab.taskEta({ total_length: 100, completed_length: 0, download_speed: 0 }) === "--", "stalled → --");

        // ---- 6. Segment default + switch ----
        assert(dlTab.segment === "active", "default segment is active");
        dlTab.segment = "queued";
        assert(dlTab.segment === "queued", "segment switches to queued");
        dlTab.segment = "finished";
        assert(dlTab.segment === "finished", "segment switches to finished");
        dlTab.segment = "active";

        // ---- 7. CentralDropdown 6-tab registration (D1) ----
        assert(dropdown !== null, "CentralDropdown must instantiate");
        assert(dropdown.tabs.length === 6, "CentralDropdown tabs must be 6, got " + dropdown.tabs.length);
        assert(dropdown.tabs[3].id === "ai", "4th tab must be 'ai', got " + dropdown.tabs[3].id);
        assert(dropdown.tabs[4].id === "workspaces", "5th tab must be 'workspaces', got " + dropdown.tabs[4].id);
        assert(dropdown.tabs[5].id === "downloads", "6th tab must be 'downloads', got " + dropdown.tabs[5].id);
        assert(dropdown.tabs[5].label === "Downloads", "downloads tab label");

        assert(dropdown.downloadsTabItem !== undefined && dropdown.downloadsTabItem !== null,
            "CentralDropdown must expose downloadsTabItem");
        assert(dropdown.textInputActive === dropdown.downloadsTabItem.addDialogOpen,
            "dropdown textInputActive must track the add sheet");

        const repeater = dropdown.tabRepeaterItem;
        assert(repeater !== undefined && repeater !== null, "must expose tabRepeaterItem");
        assert(repeater.count === 6, "tabRepeater count must be 6, got " + repeater.count);

        const indicator = dropdown.tabSlidingIndicatorItem;
        assert(indicator !== undefined && indicator !== null, "must expose tabSlidingIndicatorItem");
        dropdown.activeTab = "downloads";
        assert(indicator.activeIdx === 5, "activeIdx 5 for downloads, got " + indicator.activeIdx);
        dropdown.activeTab = "ai";
        assert(indicator.activeIdx === 3, "activeIdx 3 for ai, got " + indicator.activeIdx);
        dropdown.activeTab = "workspaces";
        assert(indicator.activeIdx === 4, "workspaces stays 4, got " + indicator.activeIdx);
        dropdown.activeTab = "dashboard";

        // ---- 7b. Tab-bar overflow contract: 6 cells fit left of the gear ----
        // Root cause of the overlap: 6 fixed 145px centered cells (870px +
        // 60px spacing) overflowed the 980px dropdown, pushing AI under the
        // settings button. Cells are now an even split of the row width.
        const tabsRow = dropdown.tabsRowItem;
        assert(tabsRow !== undefined && tabsRow !== null, "must expose tabsRowItem");
        assert(repeater.count === dropdown.tabs.length, "one cell per tab");
        const firstCell = repeater.itemAt(0);
        const lastCell = repeater.itemAt(repeater.count - 1);
        assert(firstCell !== null && lastCell !== null, "tab cells must exist");
        const expectedCell = Math.max(80, Math.floor((tabsRow.width - (dropdown.tabs.length - 1) * tabsRow.spacing) / dropdown.tabs.length));
        assert(Math.abs(firstCell.width - expectedCell) < 2.0,
            "cells split the row evenly, got " + firstCell.width + " expected ~" + expectedCell);
        // Last cell must end where the row ends: no slide under the gear.
        const rowEnd = tabsRow.x + tabsRow.width;
        const lastEnd = tabsRow.x + lastCell.x + lastCell.width;
        assert(Math.abs(lastEnd - rowEnd) <= 5.0,
            "last cell ends at row end (no gear overlap), rowEnd=" + rowEnd + " lastEnd=" + lastEnd);

        // ---- 8. Border effect geometry contract (D10) ----
        assert(dlEffect !== null, "DownloadBorderEffect must instantiate");
        assert(dlEffect.topWidth <= 420, "topWidth capped (no dropdown invasion), got " + dlEffect.topWidth);
        assert(dlEffect.rightHeight <= 260, "rightHeight capped, got " + dlEffect.rightHeight);
        assert(dlEffect.borderT === 14, "borderT stays 14 (no physical growth)");
        assert(dlEffect.visible === true, "effect visible with activeCount 2");
        assert(dlEffect.active === true, "effect active with downloads running");

        // Idle contract: no activity → hidden, timers gated.
        dlEffect.activeCount = 0;
        dlEffect.showCompleteFlash = false;
        assert(dlEffect.hasActivity === false, "no activity when count 0");
        assert(dlEffect.active === false, "inactive when idle");
        // growthProgress eases toward 0 via Behavior; the fade target is
        // what the contract pins (visible follows once the animation lands).
        assert(dlEffect.growthProgress <= 1.0 && (dlEffect.active === false), "fade target is hidden when idle");
        dlEffect.activeCount = 2;

        // Corner busy (notification owns top-right) → hidden.
        dlEffect.cornerBusy = true;
        assert(dlEffect.active === false, "effect yields to notification popup");
        dlEffect.cornerBusy = false;
        assert(dlEffect.active === true, "effect returns after notification");

        // Indeterminate → loop mode, fill hidden.
        dlEffect.indeterminate = true;
        assert(dlEffect.travelDuration >= 1350, "indeterminate travel duration sane");
        dlEffect.indeterminate = false;

        // Error tint.
        dlEffect.hasError = true;
        assert(String(dlEffect.stateColor) !== "", "error state color set");

        // ---- 9. Composition: header, empty state, segments, add sheet ----
        assert(dlTab.headerItem !== undefined && dlTab.headerItem !== null, "must expose headerItem");
        assert(dlTab.emptyStateItem !== undefined && dlTab.emptyStateItem !== null, "must expose emptyStateItem");
        assert(dlTab.showEmptyState === true, "empty state active with no tasks");
        assert(dlTab.showTaskList === false, "list hidden while empty");
        assert(dlTab.emptyStateTitleItem.text.length > 0, "empty state has a headline");
        assert(dlTab.emptyStateHintItem.text.length > 0, "empty state has a hint");
        assert(dlTab.emptyStateItem.height >= 120, "empty state has breathing room, got " + dlTab.emptyStateItem.height);
        assert(dlTab.implicitHeight <= 460, "empty tab stays compact, got " + dlTab.implicitHeight);

        // The composed moment is centred, not pinned to the left.
        const emptyCx = dlTab.emptyStateTitleItem.mapToItem(dlTab, dlTab.emptyStateTitleItem.width / 2, 0).x;
        assert(Math.abs(emptyCx - dlTab.width / 2) <= 2,
            "empty state centred, got " + emptyCx + " vs " + (dlTab.width / 2));

        // Segment control: the sliding indicator index maps 1:1 to segments.
        assert(dlTab.segmentBarItem.activeIdx === 0, "active segment is index 0");
        dlTab.segment = "queued";
        assert(dlTab.segmentBarItem.activeIdx === 1, "queued segment is index 1, got " + dlTab.segmentBarItem.activeIdx);
        assert(dlTab.emptyStateTitleItem.text.indexOf("Queue") !== -1, "queued empty copy follows the segment");
        dlTab.segment = "finished";
        assert(dlTab.segmentBarItem.activeIdx === 2, "finished segment is index 2");
        assert(dlTab.emptyStateTitleItem.text.indexOf("finished") !== -1, "finished empty copy follows the segment");
        dlTab.segment = "active";

        const chip0 = dlTab.segmentRepeaterItem.itemAt(0);
        assert(chip0 !== null && chip0 !== undefined, "segment chips must exist");
        assert(Math.abs(dlTab.segmentIndicatorItem.x - (dlTab.segmentRowItem.x + chip0.x)) <= 1,
            "segment indicator sits on the active chip, got " + dlTab.segmentIndicatorItem.x
                + " vs " + (dlTab.segmentRowItem.x + chip0.x));

        // Add sheet: single header entry; stepper clamps; both exits close it.
        assert(dlTab.addDialogOpen === false, "add sheet closed initially");
        dlTab.addButtonItem.clicked();
        assert(dlTab.addDialogOpen === true, "header Add opens the add sheet");
        assert(dlTab.showTaskList === false, "list hidden while adding");
        assert(dlTab.showSegments === false, "segments hidden while the sheet is open");

        dlTab.splitValue = 16;
        dlTab.splitPlusButtonItem.clicked(null);
        assert(dlTab.splitValue === 16, "split clamps at 16, got " + dlTab.splitValue);
        dlTab.splitValue = 1;
        dlTab.splitMinusButtonItem.clicked(null);
        assert(dlTab.splitValue === 1, "split clamps at 1, got " + dlTab.splitValue);
        dlTab.setSplitValue(7);
        assert(dlTab.splitValue === 7 && dlTab.splitValueTextItem.text === "7",
            "stepper renders the clamped value, got " + dlTab.splitValueTextItem.text);
        dlTab.setSplitValue(99);
        assert(dlTab.splitValue === 16, "setSplitValue clamps high");
        dlTab.setSplitValue(0);
        assert(dlTab.splitValue === 1, "setSplitValue clamps low");
        dlTab.setSplitValue(4);

        dlTab.cancelButtonItem.clicked();
        assert(dlTab.addDialogOpen === false, "cancel closes the sheet");
        dlTab.addButtonItem.clicked();
        assert(dlTab.addDialogOpen === true, "header Add reopens the sheet");
        dlTab.closeDialogButtonItem.clicked();
        assert(dlTab.addDialogOpen === false, "close button closes the sheet");

        // ---- 9b. Keyboard capture + clipboard paste + context menu ----
        assert(dlTab.wantsKeyboard === false, "closed sheet does not capture keyboard");
        dlTab.addButtonItem.clicked();
        assert(dlTab.wantsKeyboard === true, "open sheet captures keyboard (shell grants Exclusive)");
        assert(dlTab.urlInputItem.focus === true, "URL field takes focus while the sheet is open");

        // Paste goes through the clipboard bridge (injected under testMode).
        dlTab.testClipboardText = "https://example.com/one.iso";
        dlTab.pasteButtonMouseItem.clicked(null);
        assert(dlTab.urlInputItem.text.indexOf("example.com/one.iso") !== -1,
            "paste button writes the clipboard into the field, got: " + dlTab.urlInputItem.text);
        dlTab.testClipboardText = "https://example.com/two.iso\n";
        dlTab.pasteFromClipboard();
        const pastedLines = dlTab.urlInputItem.text.split("\n").filter(function(l) { return l.length > 0; });
        assert(pastedLines.length === 2, "a second paste appends a new line, got " + pastedLines.length + " line(s)");
        assert(pastedLines[1] === "https://example.com/two.iso",
            "pasted text is stripped of the trailing newline, got '" + pastedLines[1] + "'");

        // Right-click opens the glass menu; its actions act and dismiss.
        assert(dlTab.inputMenuOpen === false, "context menu starts closed");
        dlTab.inputRightClickItem.clicked(null);
        assert(dlTab.inputMenuOpen === true, "right-click opens the paste menu");
        dlTab.handleMenuAction("select_all");
        assert(dlTab.inputMenuOpen === false, "menu dismisses after an action");
        dlTab.inputRightClickItem.clicked(null);
        dlTab.handleMenuAction("clear");
        assert(dlTab.urlInputItem.text === "", "Clear empties the field");
        dlTab.testClipboardText = null;

        // ---- 9c. Missing aria2 handling & empty state guidance ----
        assert(dlTab.isAriaAvailable === true, "default aria available");
        dlTab.testAriaAvailable = false;
        assert(dlTab.isAriaAvailable === false, "testAriaAvailable overrides availability");
        assert(dlTab.submitButtonItem.text === "Install Aria2", "submit button prompts install when aria2 missing, got: " + dlTab.submitButtonItem.text);

        dlTab.cancelButtonItem.clicked(); // close dialog
        assert(dlTab.emptyStateTitleItem.text === "Aria2 not installed", "empty state shows aria2 missing title, got: " + dlTab.emptyStateTitleItem.text);
        assert(dlTab.emptyStateHintItem.text.indexOf("Install aria2") !== -1, "empty state hint guides installation");

        dlTab.segment = "finished";
        assert(dlTab.emptyStateTitleItem.text.indexOf("finished") !== -1, "finished segment empty copy is retained even without aria2");
        dlTab.segment = "active";
        dlTab.testAriaAvailable = null;
        assert(dlTab.isAriaAvailable === true, "clearing testAriaAvailable restores default");

        // An empty clipboard must not inject a blank line.
        dlTab.pasteFromClipboard();
        assert(dlTab.urlInputItem.text === "", "empty clipboard leaves the field untouched");

        dlTab.cancelButtonItem.clicked();
        assert(dlTab.wantsKeyboard === false, "closing the sheet releases keyboard capture");
        assert(dlTab.inputMenuOpen === false, "closing the sheet dismisses the menu");

        // The shell must route that capture to the compositor and must not
        // auto-close the drawer while a text sheet is open.
        const shellSrc2 = readLocalFile("../shell/UnifiedShell.qml");
        assert(/dropdownContainer\.textInputActive/.test(shellSrc2),
            "UnifiedShell must honour the dropdown text-input capture");
        assert(/requestsKeyboardFocus:[\s\S]{0,240}textInputActive/.test(shellSrc2),
            "UnifiedShell must derive its keyboard-focus request from the dropdown text-input capture");
        assert(/keyboardFocus:[\s\S]{0,600}WlrKeyboardFocus\.Exclusive/.test(shellSrc2),
            "UnifiedShell must grant Exclusive keyboard focus while text input is active");
        assert(/!root\.isDashboardHovered && !\(dropdownContainer && dropdownContainer\.textInputActive\)/.test(shellSrc2),
            "auto-close must be suppressed while a text sheet is open");

        // ---- 10. Bounded task list with injected tasks ----
        dlTab.testTasks = [
            { gid: "g1", name: "ubuntu-24.04.iso", status: "active", total_length: 4000000000, completed_length: 1000000000, download_speed: 5242880 },
            { gid: "g2", name: "arch.iso", status: "active", total_length: 1000000000, completed_length: 250000000, download_speed: 2621440 },
            { gid: "g3", name: "notes.pdf", status: "waiting", total_length: 1000000, completed_length: 0, download_speed: 0 },
            { gid: "g4", name: "old.zip", status: "complete", total_length: 100, completed_length: 100, download_speed: 0 }
        ];

        deferredRun(function() {
            assert(dlTab.activeCount === 2, "2 active tasks counted, got " + dlTab.activeCount);
            assert(dlTab.queuedCount === 1, "1 queued task counted, got " + dlTab.queuedCount);
            assert(dlTab.finishedCount === 1, "1 finished task counted, got " + dlTab.finishedCount);
            assert(dlTab.taskRowRepeaterItem.count === 2, "active segment shows 2 rows, got " + dlTab.taskRowRepeaterItem.count);
            assert(dlTab.showTaskList === true, "list active with tasks");
            assert(dlTab.showEmptyState === false, "empty state hidden with tasks");
            assert(dlTab.showAggregateProgress === true, "aggregate progress active while downloading");

            dlTab.segment = "queued";
            assert(dlTab.taskRowRepeaterItem.count === 1, "queued segment shows 1 row, got " + dlTab.taskRowRepeaterItem.count);
            assert(dlTab.showClearButton === false, "clear button hidden in queued segment");
            dlTab.segment = "finished";
            assert(dlTab.taskRowRepeaterItem.count === 1, "finished segment shows 1 row, got " + dlTab.taskRowRepeaterItem.count);
            assert(dlTab.showClearButton === true, "clear button visible in finished segment with items");
            dlTab.segment = "active";
            assert(dlTab.showClearButton === false, "clear button hidden in active segment");

            // Clamp: an unbounded row count scrolls inside maxListHeight.
            const many = [];
            for (let i = 0; i < 9; i++) {
                many.push({ gid: "b" + i, name: "file-" + i + ".bin", status: "active", total_length: 1000 + i, completed_length: 100, download_speed: 1024 });
            }
            dlTab.testTasks = many;

            deferredRun(function() {
                assert(dlTab.taskRowRepeaterItem.count === 9, "9 injected rows, got " + dlTab.taskRowRepeaterItem.count);
                assert(dlTab.taskListFlickableItem.height <= dlTab.maxListHeight + 0.5,
                    "list clamps at maxListHeight, got " + dlTab.taskListFlickableItem.height);
                assert(dlTab.taskListFlickableItem.contentHeight > dlTab.taskListFlickableItem.height - 0.5,
                    "overflow rows scroll instead of expanding, contentHeight=" + dlTab.taskListFlickableItem.contentHeight);
                assert(dlTab.implicitHeight <= 480, "tab stays bounded with many rows, got " + dlTab.implicitHeight);

                dlTab.testTasks = null;
                deferredRun(function() {
                    assert(dlTab.taskRowRepeaterItem.count === 0, "clearing tasks empties the list");
                    assert(dlTab.showEmptyState === true, "empty state returns");
                    sourceContracts();
                    console.log("PASS: All DownloadsTab & 6-Tab & Border Effect Unit Tests passed!");
                    Qt.exit(0);
                });
            });
        });
    }

    // ---- 11. Source contracts (single source of truth in the files) ----
    function sourceContracts() {
        const svcSrc = readLocalFile("../services/DownloadService.qml");
        assert(svcSrc.length > 1000, "DownloadService.qml readable");
        assert(/pragma Singleton/.test(svcSrc), "DownloadService is a Singleton");
        assert(/downloads.*watch/.test(svcSrc), "DownloadService consumes the `downloads watch` event stream");
        assert(!/interval:\s*1000/.test(svcSrc) || /restartTimer/.test(svcSrc),
            "DownloadService holds no 1s polling timer (only restart backoff)");
        assert(/downloadFinished/.test(svcSrc) && /downloadFailed/.test(svcSrc),
            "DownloadService emits finished/failed edge signals");
        assert(/hudText/.test(svcSrc), "DownloadService exposes hudText aggregate");
        assert(/openFile/.test(svcSrc) && /openFolder/.test(svcSrc) && /xdg-open/.test(svcSrc),
            "DownloadService exposes openFile and openFolder using xdg-open");

        const tabSrc = readLocalFile("../dashboard/tabs/DownloadsTab.qml");
        assert(/LiquidGlassButton/.test(tabSrc), "DownloadsTab uses LiquidGlassButton");
        assert(/Theme\.animExpressive/.test(tabSrc), "DownloadsTab animates with Theme expressive tokens");
        assert(/Flickable/.test(tabSrc), "task list is Flickable-bounded");
        assert(/maxListHeight/.test(tabSrc), "DownloadsTab clamps the list height");
        assert(/segmentIndicator/.test(tabSrc), "DownloadsTab declares the sliding segment indicator");
        assert(/clearButton/.test(tabSrc), "DownloadsTab declares the clear history button");
        assert(/isAriaAvailable/.test(tabSrc), "DownloadsTab checks aria availability");
        assert(/ariaInstallBanner/.test(tabSrc), "DownloadsTab includes aria2 install guidance banner");

        const fxSrc = readLocalFile("../components/DownloadBorderEffect.qml");
        assert(/fusedTopNexus/.test(fxSrc), "effect declares fusedTopNexus");
        assert(/hudCapsule/.test(fxSrc), "effect declares HUD capsule");
        assert(/running:\s*root\.active\s*&&/.test(fxSrc), "effect timers gate on active (0% idle CPU)");
        assert(/openDownloads/.test(fxSrc), "HUD capsule opens the Downloads tab");

        const shellSrc = readLocalFile("../shell/UnifiedShell.qml");
        assert(/DownloadBorderEffect/.test(shellSrc), "shell mounts DownloadBorderEffect");
        assert(/onDownloadFinished/.test(shellSrc), "shell bridges downloadFinished → toast");
        assert(/Config\.downloadsBorderEffect/.test(shellSrc), "shell honours the border-effect toggle");

        const cfgSrc = readLocalFile("../config/Config.qml");
        assert(/downloadsSplit/.test(cfgSrc), "Config exposes downloadsSplit");
        assert(/downloadsDir/.test(cfgSrc), "Config exposes downloadsDir");
        assert(/setDownloadsSplit/.test(cfgSrc), "Config persists split");
    }
}
