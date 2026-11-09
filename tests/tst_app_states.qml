import QtQuick
import "../modules/Astral/Kernel/config/PopoutModes.js" as PopoutModes
import "../modules/Astral/Kernel/Host/AppRegistryState.js" as Registry

// ============================================================================
// App state: is this app on, and what does a disabled app own?
// ============================================================================
// Disabling an app used to change nothing visible: the AI Quotas pill stayed on the dock
// and its drawer still opened, because those surfaces are the shell's own and never asked
// the registry (reported as "the disable of an app does nothing").
//
// Two pure pieces make the rule testable without a shell: the registry document parser and
// the drawer→app map. The wiring that uses them is asserted at the source level, because a
// QtObject cannot observe a singleton's file watch here.
Item {
    id: testRoot
    width: 400
    height: 300

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + "?v=" + Date.now(), false);
        xhr.send();
        return xhr.responseText || "";
    }

    Component.onCompleted: {
        // ---- the registry document ------------------------------------------
        let state = Registry.parse('{"schema":1,"apps":[{"id":"a.one","enabled":true},{"id":"a.two","enabled":false}]}');
        assert(state.ok === true, "a registry document parses");
        assert(state.apps.length === 2, "both records are kept");
        assert(Registry.isEnabled(state, "a.one") === true, "an enabled record is on");
        assert(Registry.isEnabled(state, "a.two") === false, "a disabled record is off");
        assert(Registry.isEnabled(state, "not.installed") === true,
            "an unknown app is on: that is how a bundled app exists before its first record");
        assert(JSON.stringify(Registry.disabledIds(state)) === '["a.two"]',
            "the disabled list names exactly the disabled apps");

        // A record without `enabled` is not a disabled record.
        state = Registry.parse('{"schema":1,"apps":[{"id":"a.one"}]}');
        assert(Registry.isEnabled(state, "a.one") === true, "a missing flag means on");

        // Corrupt or absent input is data, not a crash: the shell must survive it.
        for (const broken of ["", "not json", "[]", '{"apps":"nope"}']) {
            const parsed = Registry.parse(broken);
            assert(parsed.ok === false, "unreadable registry: " + JSON.stringify(broken));
            assert(Registry.isEnabled(parsed, "a.one") === true,
                "an unreadable registry fails open, not closed");
            assert(Registry.disabledIds(parsed).length === 0, "nothing is disabled by accident");
        }

        // ---- drawers that belong to an app ----------------------------------
        assert(PopoutModes.appForMode("ai") === "org.astralplasma.ai",
            "the AI drawer belongs to the AI Quotas app");
        assert(PopoutModes.appForMode("AI") === "org.astralplasma.ai", "case does not matter");
        assert(PopoutModes.appForMode("audio") === "", "a shell-owned drawer has no app");
        assert(PopoutModes.appForMode("") === "", "no mode, no owner");
        assert(PopoutModes.appForMode(null) === "", "null mode, no owner");

        // ---- the wiring that uses them --------------------------------------
        const service = readLocalFile("../modules/Astral/Kernel/services/AiTokenService.qml");
        assert(service.indexOf("AppStates.isEnabled(\"org.astralplasma.ai\")") >= 0,
            "the pill asks whether its app is enabled");
        assert(service.indexOf("Config.closeBottomPopout()") >= 0,
            "an open drawer closes when the app is disabled");

        const shell = readLocalFile("../shell.qml");
        assert(shell.indexOf("bundledApps.isEnabled(\"org.astralplasma.ai\")") >= 0,
            "the drawer opener refuses a disabled app, through the registry the shell mounts from");

        const registry = readLocalFile("../modules/Astral/Kernel/Host/AppRegistry.qml");
        assert(registry.indexOf("function isEnabled(") >= 0,
            "the registry answers for shell surfaces, from the records the plan uses");

        console.log("PASS: All app state tests passed!");
        Qt.exit(0);
    }
}
