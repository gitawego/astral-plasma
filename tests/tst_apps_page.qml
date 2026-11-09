import QtQuick
import QtQuick.Controls
import "../settings_gui/pages"

// ============================================================================
// Apps page
// ============================================================================
// The page lists every app the desktop knows, with the three numbers a user needs
// (version, API level, state) and the platform's own actions: enable/disable and
// remove. It renders the daemon's list — it does not keep its own truth.
ApplicationWindow {
    id: testRoot
    visible: false
    width: 900
    height: 700

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

    readonly property var fixtures: [
        { id: "org.astralplasma.dock", name: "Dock", version: "0.1.0", kernelApi: 1,
          preinstalled: true, enabled: true, compatible: true, reason: null,
          trust: "official", granted: ["session.read"], dbusNames: [] },
        { id: "org.astralplasma.media", name: "Media", version: "0.2.1", kernelApi: 1,
          preinstalled: true, enabled: false, compatible: true, reason: null,
          trust: "official", granted: ["media.read", "media.control"],
          dbusNames: ["org.mpris.MediaPlayer2"] },
        { id: "io.github.alice.clock", name: "World Clock", version: "1.4.0", kernelApi: 9,
          preinstalled: false, enabled: true, compatible: false,
          reason: "needs a newer Astral (API 9); this is API 1",
          trust: "community", granted: [], dbusNames: [] }
    ]

    AppsPage {
        id: page
        anchors.fill: parent
        testMode: true
        testApps: testRoot.fixtures
        testRemoved: ["org.astralplasma.media"]
        testPendingInstall: ({
            id: "io.github.alice.timer", name: "Timer", version: "0.3.0", kernelApi: 1,
            trust: "community", publisher: "Alice", permissions: ["windows.read", "network"],
            summaries: ["see your open windows and their titles", "reach the network"],
            dbusNames: ["org.freedesktop.Notifications"], nativeFiles: false,
            path: "/tmp/timer.astralapp"
        })
    }

    Component.onCompleted: {
        // ---- the rows carry identity, version and API -----------------------
        assert(page.apps.length === 3, "the page lists every app it is given");
        assert(page.stateLabel(page.apps[0]) === "Enabled", "an enabled app reads Enabled");
        assert(page.stateLabel(page.apps[1]) === "Disabled", "a disabled app reads Disabled");
        assert(page.stateLabel(page.apps[2]) === "Incompatible", "an incompatible app says so");

        // ---- the consent record: who published it, and what it may do -------
        assert(page.trustLabel(page.apps[0]) === "Official", "a bundled app reads Official");
        assert(page.trustLabel(page.apps[2]) === "Community", "an installed app names its tier");
        assert(page.trustLabel({}) === "Unknown publisher",
            "a record without a tier says so rather than guessing");
        assert(page.permissionsLabel(page.apps[0]) === "session.read",
            "grants are listed as given");
        assert(page.permissionsLabel(page.apps[1])
                === "media.read, media.control, 1 DBus service",
            "DBus names are summarised, not hidden");
        assert(page.permissionsLabel(page.apps[2]) === "Asks for nothing",
            "an app with no grants says exactly that");

        // ---- the consent copy ------------------------------------------------
        // Installing is a decision: the card must say who published it, what it may do,
        // and what the sandbox confines regardless.
        const consent = page.consentSummary(page.pendingInstall);
        assert(consent.indexOf("see your open windows") >= 0,
            "a permission is spelled out in words, not as a key");
        assert(consent.indexOf("reach the network") >= 0, "every permission is listed");
        assert(consent.indexOf("org.freedesktop.Notifications") >= 0,
            "DBus services are named, not hidden");
        assert(consent.indexOf("no access to your files") >= 0,
            "the card states what the sandbox confines regardless of grants");
        assert(page.consentSummary(null) === "", "no pending install, no sentence");
        assert(page.consentSummary({ permissions: [], summaries: [], dbusNames: [] })
                .indexOf("asks for no permissions") >= 0,
            "an app that asks for nothing says so");

        const consentSource = readLocalFile("../settings_gui/pages/AppsPage.qml");
        assert(consentSource.indexOf("AppsService.inspect(") >= 0,
            "the card is fed by an inspection of the artifact");
        assert(readLocalFile("../modules/Astral/Kernel/services/AppsService.qml")
                .indexOf("--accept-permissions") >= 0,
            "consent must be explicit when installing");
        assert(consentSource.indexOf("FileDialog") >= 0, "the user picks the artifact");

        // ---- a removal can be undone from the page --------------------------
        assert(page.removedApps.length === 1, "removed bundled apps are offered for restore");
        assert(page.appName("org.astralplasma.media") === "Media",
            "a removed app still has a readable name");
        assert(readLocalFile("../modules/Astral/Kernel/services/AppsService.qml")
                .indexOf('"app", "restore"') >= 0,
            "restoring goes through the daemon, not the page");
        assert(readLocalFile("../modules/Astral/Kernel/services/AppsService.qml")
                .indexOf('"app", "removed", "--json"') >= 0,
            "the removed list is the daemon's");

        // ---- the page is data-driven and action-bearing ---------------------
        const source = readLocalFile("../settings_gui/pages/AppsPage.qml");
        assert(source.length > 1000, "the page must be readable");
        assert(source.indexOf("AppsService.refresh()") >= 0, "the page refreshes from the service");
        assert(source.indexOf("setEnabled(") >= 0, "the page must offer enable/disable");
        assert(source.indexOf("remove(") >= 0, "the page must offer remove");
        assert(source.indexOf("modelData.version") >= 0, "each row shows its version");
        assert(source.indexOf("modelData.kernelApi") >= 0, "each row shows its API level");
        assert(source.indexOf("trustLabel(modelData)") >= 0, "each row shows its trust tier");
        assert(source.indexOf("permissionsLabel(modelData)") >= 0,
            "each row shows what the app was granted");
        assert(source.indexOf("Config.") === -1,
            "the page must not read Config directly; the service owns the daemon call");

        // ---- the service speaks the daemon's language -----------------------
        const service = readLocalFile("../modules/Astral/Kernel/services/AppsService.qml");
        assert(service.indexOf('"app", "list", "--json"') >= 0, "the service lists from the daemon");
        assert(service.indexOf('enabled ? "enable" : "disable"') >= 0,
            "the service toggles through the daemon");
        assert(service.indexOf('"app", "remove"') >= 0, "the service removes through the daemon");

        console.log("PASS: All Apps page tests passed!");
        Qt.exit(0);
    }
}
