import QtQuick
import "../settings_gui/pages"
import "../services/PiUpdateMessage.js" as PiUpdateMessage

// ============================================================================
// Pi Harness card (Settings -> AI)
// ============================================================================
// The Copilot's engine is the user's own pi installation, so the AI page offers
// its update as a button instead of a command to remember. The card has to say
// which version is installed, disable itself while an update runs, and report
// what the update actually did - all of it without a daemon, through the page's
// test seam.
Item {
    id: harnessRoot
    width: 900
    height: 700

    // Installed and current.
    AiPage {
        id: harnessPage
        testMode: true
        testHarnessInstalled: true
        testHarnessVersion: "1.0.0"
    }

    // No harness at all: guide, never pretend to update.
    AiPage {
        id: noHarnessPage
        testMode: true
        testHarnessInstalled: false
        testHarnessVersion: ""
    }

    // Mid-update.
    AiPage {
        id: updatingPage
        testMode: true
        testHarnessInstalled: true
        testHarnessVersion: "1.0.0"
        testHarnessUpdateState: "running"
    }

    // A failed update, with pi's own output.
    AiPage {
        id: failedPage
        testMode: true
        testHarnessUpdateState: "failed"
        testHarnessUpdateMessage: "`pi update self` failed (exit status: 1): npm ERR! EACCES"
        testHarnessUpdateDetail: "npm ERR! EACCES"
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
        console.log("RUNNING: Pi Harness Card");

        // ------------------------------------------------------------------
        // Status is the real probed version
        // ------------------------------------------------------------------
        assert(harnessPage.harnessStatusItem.text.indexOf("1.0.0") >= 0,
            "the card reports the installed version, got: " + harnessPage.harnessStatusItem.text);
        assert(harnessPage.harnessInstalled === true, "an installed harness is reported as such");
        assert(harnessPage.updatePiButtonItem.visible === true, "an installed harness can be updated");
        assert(harnessPage.updatePiButtonItem.label === "Update Pi", "the primary action names the harness");
        assert(harnessPage.harnessInstallButtonItem.visible === false,
            "no install command while the harness is present");
        assert(harnessPage.harnessResultItem.visible === false,
            "no result line before an update has run");

        // ------------------------------------------------------------------
        // Missing harness: guide instead of updating nothing
        // ------------------------------------------------------------------
        assert(noHarnessPage.harnessStatusItem.text.indexOf("not installed") >= 0,
            "a missing harness says so, got: " + noHarnessPage.harnessStatusItem.text);
        assert(noHarnessPage.updatePiButtonItem.visible === false
                && noHarnessPage.updatePackagesButtonItem.visible === false
                && noHarnessPage.refreshCatalogsButtonItem.visible === false,
            "nothing to update without a harness");
        assert(noHarnessPage.harnessInstallButtonItem.visible === true,
            "the missing harness offers the install command");
        assert(noHarnessPage.harnessHintItem.text.indexOf("needs the pi harness") >= 0,
            "the hint explains what is missing");

        // ------------------------------------------------------------------
        // One update at a time
        // ------------------------------------------------------------------
        assert(updatingPage.harnessUpdating === true, "the running state is visible");
        assert(updatingPage.updatePiButtonItem.label === "Updating…",
            "the button says what is happening, got: " + updatingPage.updatePiButtonItem.label);
        assert(updatingPage.updatePiButtonItem.enabled === false,
            "a running update cannot be started twice");

        // ------------------------------------------------------------------
        // The buttons drive the three pi update targets
        // ------------------------------------------------------------------
        harnessPage.updatePi();
        harnessPage.updatePiPackages();
        harnessPage.refreshPiModelCatalogs();
        harnessPage.copyHarnessInstallCommand();
        assert(harnessPage.testUpdatePiRequests === 1, "Update Pi runs the harness update");
        assert(harnessPage.testUpdatePackagesRequests === 1, "Update packages runs the package update");
        assert(harnessPage.testRefreshCatalogsRequests === 1, "Refresh catalogs runs the catalog update");
        assert(harnessPage.testCopyCommandRequests === 1, "the install command can be copied");

        // ------------------------------------------------------------------
        // Results are reported; failures are not dressed up
        // ------------------------------------------------------------------
        assert(failedPage.harnessResultItem.visible === true, "a failed update is shown");
        assert(failedPage.harnessResultItem.text.indexOf("EACCES") >= 0,
            "the failure carries the real output, got: " + failedPage.harnessResultItem.text);
        assert(failedPage.harnessDetailItem.visible === true, "the output detail is shown");

        // ------------------------------------------------------------------
        // The summary line: what the update did, in the user's words
        // ------------------------------------------------------------------
        assert(PiUpdateMessage.describe({ target: "pi", before: "1.0.0", after: "1.0.2", changed: true })
                === "Updated 1.0.0 → 1.0.2",
            "a version move names both versions: "
                + PiUpdateMessage.describe({ target: "pi", before: "1.0.0", after: "1.0.2", changed: true }));
        assert(PiUpdateMessage.describe({ target: "pi", before: "1.0.0", after: "1.0.0", changed: false })
                === "Already up to date (1.0.0)",
            "nothing to do is said plainly");
        assert(PiUpdateMessage.describe({ target: "extensions", changed: null })
                === "Packages reconciled with npm",
            "a package update is not dressed up as a version change");
        assert(PiUpdateMessage.describe({ target: "models", changed: null })
                === "Model catalogs refreshed",
            "a catalog refresh says what it refreshed");
        // A report with missing fields must still produce a sentence.
        assert(PiUpdateMessage.describe({}) === "Update finished", "an unknown report still answers");
        assert(PiUpdateMessage.describe(null) === "Update finished", "no report at all still answers");

        assert(PiUpdateMessage.tail("checking\npi is already up to date (v1.0.0)\n\n")
                === "pi is already up to date (v1.0.0)",
            "the detail row shows pi's verdict, not its progress");
        assert(PiUpdateMessage.tail("") === "" && PiUpdateMessage.tail(null) === "",
            "no output means no detail");

        console.log("PASS: Pi Harness Card");
        Qt.exit(0);
    }
}
