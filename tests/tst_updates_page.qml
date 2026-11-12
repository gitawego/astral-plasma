import QtQuick
import "../settings_gui/pages"

// ============================================================================
// Updates page: what the daemon says, and nothing else
// ============================================================================
// The page is a view over `astral-plasma update status`. These assertions pin the
// states that matter - an available update, a refused install (package-managed or
// already staged), a rollback explanation, and the two-press removal - and they
// count actions instead of performing them, so the suite never touches the
// running system.
Item {
    id: testRoot
    width: 900
    height: 700

    function status(overrides) {
        const base = {
            current_version: "0.1.3",
            channel: "stable",
            install_method: "managed",
            arch: "x86_64",
            can_apply: false,
            last_check_unix: 0,
            candidate: null
        };
        for (const key in overrides) base[key] = overrides[key];
        return base;
    }

    UpdatesPage {
        id: idlePage
        testMode: true
        testStatus: testRoot.status({})
        testChangelog: [
            {
                version: "0.1.3",
                date: "2026-10-01",
                highlights: ["Volume controls redesigned", "Beat-driven visualiser"]
            },
            { version: "0.1.2", date: "2026-10-01", highlights: ["Downloads manager"] }
        ]
    }

    UpdatesPage {
        id: readyPage
        testMode: true
        testStatus: testRoot.status({
            can_apply: true,
            candidate: {
                version: "0.2.0",
                highlights: ["Faster dock", "New settings page"],
                size: 22000000,
                changelog: null
            }
        })
    }

    UpdatesPage {
        id: refusedPage
        testMode: true
        testStatus: testRoot.status({
            install_method: "package",
            can_apply: false,
            refuse_reason: "Your package manager owns this install; update it with pacman.",
            candidate: { version: "0.2.0", highlights: [], size: 1000 }
        })
    }

    UpdatesPage {
        id: rolledBackPage
        testMode: true
        testStatus: testRoot.status({
            rollback: { version: "0.2.0", reason: "the restarted shell did not answer IPC" }
        })
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Component.onCompleted: {
        // A page adopts the hub contract: identity and Atlas tabs.
        assert(idlePage.title === "Updates & About", "the page names itself");
        assert(idlePage.subtitle.length > 0, "the page describes itself");
        assert(idlePage.icon !== "", "the page carries an icon");
        assert(idlePage.tabs.length === 4, "four tabs (got " + idlePage.tabs.length + ")");
        const ids = idlePage.tabs.map(t => t.id).join(",");
        assert(ids === "version,update,notes,maintenance", "tab order: " + ids);
        for (let i = 0; i < idlePage.tabs.length; ++i) {
            const tab = idlePage.tabs[i];
            assert(tab.label && tab.label !== "",
                "tab '" + tab.id + "' must carry a label");
            assert(tab.icon && tab.icon !== "",
                "tab '" + tab.id + "' must carry an icon");
        }
        assert(idlePage.zones.length === 0, "the page no longer declares a scroll rail");
        assert(idlePage.currentTab === "version", "the page opens on Version");
        idlePage.selectTab("notes");
        assert(idlePage.currentTab === "notes", "selectTab switches to What's New");
        idlePage.selectTab("version");

        // Idle: nothing on offer, and the notes that are compiled in are shown.
        assert(idlePage.currentVersion === "0.1.3", "the running version is shown");
        assert(!idlePage.updateAvailable, "no candidate on an idle install");
        assert(!idlePage.applyButton.active, "Update must be inert with no candidate");
        assert(idlePage.notes.length === 2, "two release notes (got " + idlePage.notes.length + ")");
        assert(idlePage.notes[0].highlights.length === 2, "the newest note's highlights render");

        // Available: the version, the real size, and an enabled action.
        assert(readyPage.candidateVersion === "0.2.0", "the candidate version is shown");
        assert(readyPage.canApply, "the daemon said this install may apply");
        assert(readyPage.applyButton.active, "the apply control is enabled");
        assert(readyPage.sizeText === "21 MiB", "real size, got '" + readyPage.sizeText + "'");

        // Refused: the daemon's own reason, and no apply control.
        assert(!refusedPage.canApply, "a package-managed install cannot apply");
        assert(refusedPage.refuseReason.indexOf("pacman") >= 0, "the reason names the owner");
        assert(!refusedPage.applyButton.active,
            "a package-managed install must not offer an apply control");
        assert(refusedPage.installMethod === "package", "the install method is reported");

        // A rollback is explained, not hidden.
        assert(rolledBackPage.rollback !== null, "a rollback is surfaced");
        assert(rolledBackPage.rollback.version === "0.2.0", "the failed version is named");
        assert(rolledBackPage.rollback.reason.indexOf("did not answer IPC") >= 0,
            "the reason is the daemon's, verbatim");

        // Actions are delegated exactly once.
        readyPage.checkCalls = 0;
        readyPage.applyCalls = 0;
        readyPage.checkButton.clicked();
        assert(readyPage.checkCalls === 1, "check is delegated");
        readyPage.applyButton.clicked();
        assert(readyPage.applyCalls === 1, "apply is delegated");

        // Removal takes two presses; the first one only arms it.
        readyPage.uninstallCalls = 0;
        readyPage.armedUninstall = false;
        readyPage.requestUninstall();
        assert(readyPage.uninstallCalls === 0, "one press must never remove the install");
        assert(readyPage.armedUninstall, "the first press arms the removal");
        readyPage.requestUninstall();
        assert(readyPage.uninstallCalls === 1, "the second press removes");
        assert(!readyPage.armedUninstall, "the confirmation resets after it is used");

        // Revert follows the same ownership rule as apply.
        assert(readyPage.revertButton.active, "a managed install can revert");
        assert(!refusedPage.revertButton.active, "a package-managed install cannot");
        readyPage.revertCalls = 0;
        readyPage.revertButton.clicked();
        assert(readyPage.revertCalls === 1, "revert is delegated");

        console.log("PASS: Updates Page");
        Qt.exit(0);
    }
}
