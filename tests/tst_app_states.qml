import QtQuick
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

        // Drawer ownership moved to the integration declarations (spec C.35), so this suite
        // only covers the registry document; tst_app_integrations.qml covers the locations.

        // ---- the wiring that uses them --------------------------------------
        const service = readLocalFile("../modules/Astral/Kernel/services/AiTokenService.qml");
        assert(service.indexOf("if (!root.appEnabled) return false;") >= 0,
            "the pill hides when its app is disabled");
        assert(service.indexOf("onAppEnabledChanged") >= 0,
            "and an open drawer closes when that happens");

        const shell = readLocalFile("../shell.qml");
        assert(shell.indexOf("AiTokenService.appEnabled = bundledApps.isEnabled") >= 0,
            "the shell pushes the answer, because a singleton must not reach another");
        assert(shell.indexOf('AppStates.integrationEnabled("drawer", "ai")') >= 0,
            "the drawer opener asks whether an enabled app declares that location");
        assert(shell.indexOf('AppStates.providedOnly("dashboardTab", Config.dashboardTabs)') >= 0,
            "the dashboard strip is filtered by the declarations, not by a list of app names");

        const dock = readLocalFile("../dock/components/DockStatusIcons.qml");
        assert(dock.indexOf('AppStates.integrationEnabled("dockItem", "ai")') >= 0,
            "the dock item exists only while an enabled app declares that location");
        assert(dock.indexOf("AiActivityService.isActive") >= 0,
            "agent activity is still shown when the app is enabled");

        const registry = readLocalFile("../modules/Astral/Kernel/Host/AppRegistry.qml");
        assert(registry.indexOf("function isEnabled(") >= 0,
            "the registry answers for shell surfaces, from the records the plan uses");

        console.log("PASS: All app state tests passed!");
        Qt.exit(0);
    }
}
