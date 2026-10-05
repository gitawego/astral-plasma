import QtQuick
import "../settings_gui/pages"

// ============================================================================
// Desktop Agent Skills Card (Settings -> AI)
// ============================================================================
// Astral Plasma provides the `astral-desktop-tools` skill definition so AI
// agents (Antigravity, Agy, Claude Code, Cursor) can autonomously inspect
// windows, switch virtual workspaces, query telemetry, and trigger crash diagnostics.
// The settings page must provide reactive controls to install, reinstall, and
// uninstall skills cleanly across standard discovery directories.
Item {
    id: testRoot
    width: 900
    height: 700

    // State 1: Skill is installed
    AiPage {
        id: installedPage
        testMode: true
        testSkillInstalled: true
        testSkillLocations: [
            "/home/hlu/.config/astral-plasma/skills/astral-desktop-tools/SKILL.md",
            ".agents/skills/astral-desktop-tools/SKILL.md"
        ]
    }

    // State 2: Skill is not installed
    AiPage {
        id: uninstalledPage
        testMode: true
        testSkillInstalled: false
        testSkillLocations: []
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
        console.log("RUNNING: Desktop Agent Skills Card Unit Tests");

        // 1. Verify installed state presentation
        assert(installedPage.skillInstalled === true, "installedPage reports skill installed");
        assert(installedPage.skillStatusItem.text.indexOf("astral-desktop-tools installed") >= 0,
            "status text reflects installed state: " + installedPage.skillStatusItem.text);
        assert(installedPage.skillStatusItem.text.indexOf("2 target(s)") >= 0,
            "status text reflects number of installed targets: " + installedPage.skillStatusItem.text);
        assert(installedPage.installSkillButtonItem.visible === false, "Install button hidden when already installed");
        assert(installedPage.reinstallSkillButtonItem.visible === true, "Reinstall / Update button visible when installed");
        assert(installedPage.uninstallSkillButtonItem.visible === true, "Uninstall button visible when installed");

        // 2. Verify uninstalled state presentation
        assert(uninstalledPage.skillInstalled === false, "uninstalledPage reports skill uninstalled");
        assert(uninstalledPage.skillStatusItem.text.indexOf("is not installed") >= 0,
            "status text reflects uninstalled state: " + uninstalledPage.skillStatusItem.text);
        assert(uninstalledPage.installSkillButtonItem.visible === true, "Install button visible when uninstalled");
        assert(uninstalledPage.reinstallSkillButtonItem.visible === false, "Reinstall button hidden when uninstalled");
        assert(uninstalledPage.uninstallSkillButtonItem.visible === false, "Uninstall button hidden when uninstalled");

        // 3. Verify interaction hooks (SoC and test seam)
        assert(uninstalledPage.testInstallSkillRequests === 0, "no install requests initially");
        uninstalledPage.installSkill();
        assert(uninstalledPage.testInstallSkillRequests === 1, "install request triggered cleanly");

        assert(installedPage.testUninstallSkillRequests === 0, "no uninstall requests initially");
        installedPage.uninstallSkill();
        assert(installedPage.testUninstallSkillRequests === 1, "uninstall request triggered cleanly");

        // Reinstall button calls installSkill()
        installedPage.installSkill();
        assert(installedPage.testInstallSkillRequests === 1, "reinstall calls installSkill()");

        // 4. Verify deep link anchors
        assert(typeof installedPage.sectionY === "function", "sectionY function must exist");
        assert(installedPage.sectionY("skills") >= 0, "skills anchor exists");
        assert(installedPage.sectionY("skill") === installedPage.sectionY("skills"), "skill and skills aliases match");

        console.log("PASS: Desktop Agent Skills Card Unit Tests");
        Qt.exit(0);
    }
}
