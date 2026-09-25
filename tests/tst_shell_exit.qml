import QtQuick
import "../components"

// ============================================================================
// Shell Exit Contract
// ============================================================================
// There must be a way out of the shell from the interface. Three surfaces offer
// it - the settings page, the launcher command and the power menu - and all of
// them go through the daemon (`astral-plasma shell exit`), which asks the
// running shell to quit; the supervisor that started the shell restores the
// Plasma panels when it exits.
//
// The quit itself is pinned by daemon/tests/test_shell_lifecycle.rs.
Item {
    id: testRoot

    MaterialIcon {
        id: testExitToAppIcon
        text: "exit_to_app"
    }

    MaterialIcon {
        id: testExitIcon
        text: "exit"
    }

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
        console.log("RUNNING: Shell Exit Contract");

        // The shell exposes the IPC the daemon calls.
        const root = readLocalFile("../shell.qml");
        assert(/IpcHandler\s*\{[\s\S]{0,200}target:\s*"shell"/.test(root),
            "shell.qml must expose the `shell` IPC target");
        assert(/function quit\(\)[\s\S]{0,80}Qt\.quit\(\)/.test(root),
            "the shell must quit on `shell quit`");

        // The daemon owns the quit and the fallback.
        const daemon = readLocalFile("../daemon/src/application/shell_lifecycle.rs");
        assert(/"call"\.to_string\(\)[\s\S]{0,120}"shell"[\s\S]{0,80}"quit"/.test(daemon),
            "the daemon must call the shell's `shell quit` IPC");
        assert(/pkill/.test(daemon),
            "a wedged shell must still be quittable");

        // Every interface surface routes through Config.exitShell().
        const config = readLocalFile("../config/Config.qml");
        assert(/function exitShell\(\)/.test(config),
            "Config must expose exitShell()");
        assert(/\[root\.daemonBin,\s*"shell",\s*"exit"\]/.test(config),
            "exitShell must call the daemon's shell exit");

        const settings = readLocalFile("../settings_gui/pages/SystemPage.qml");
        assert(/Exit Astral Plasma/.test(settings) && /Config\.exitShell\(\)/.test(settings),
            "the settings page must offer Exit Astral Plasma");

        const launcher = readLocalFile("../shell/CommandLauncher.qml");
        assert(/id:\s*"exit"[\s\S]{0,200}aliases:\s*\[[^\]]*"quit"/.test(launcher),
            "the launcher must offer an exit command");
        assert(/item\.id === "exit"[\s\S]{0,200}Config\.exitShell\(\)/.test(launcher),
            "the launcher's exit command must call Config.exitShell()");

        const power = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        assert(/label:\s*"Exit Astral Plasma"[\s\S]{0,200}Config\.exitShell\(\)/.test(power),
            "the power menu must offer Exit Astral Plasma");

        // Icon Contract: Exit Astral Plasma must have a valid, resolved icon across all surfaces
        assert(testExitToAppIcon.hasIcon && testExitToAppIcon.displaySymbol === "󰈆",
            "MaterialIcon must resolve 'exit_to_app' to the 󰈆 glyph");
        assert(testExitIcon.hasIcon && testExitIcon.displaySymbol === "󰈆",
            "MaterialIcon must resolve 'exit' to the 󰈆 glyph");
        assert(/icon:\s*"exit_to_app"[\s\S]{0,50}label:\s*"Exit Astral Plasma"/.test(power),
            "the power menu must use icon: 'exit_to_app' for Exit Astral Plasma");
        assert(/id:\s*"exit"[\s\S]{0,200}icon:\s*"exit_to_app"/.test(launcher),
            "the launcher exit suggestion must use icon: 'exit_to_app'");
        assert(/id:\s*exitShellButton[\s\S]{0,200}iconText:\s*"exit_to_app"/.test(settings),
            "the settings exit button must use iconText: 'exit_to_app'");

        console.log("PASS: Shell Exit Contract (shell IPC + daemon quit + icons, offered by "
            + "settings, launcher and power menu)");
        Qt.exit(0);
    }
}
