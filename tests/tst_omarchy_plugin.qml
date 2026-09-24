import QtQuick

Item {
    id: testRoot
    width: 400
    height: 300

    Timer {
        interval: 10
        running: true
        repeat: false
        onTriggered: runTests()
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
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    // Mirror of services/DesktopSessionFacade.qml for deterministic offscreen execution
    QtObject {
        id: facade

        property string profile: "kde"
        property string connection: "connected"
        property int revision: 1
        property string focusedOutputId: ""
        property bool isStale: (connection === "disconnected" || connection === "degraded")

        property var outputs: []
        property var workspaces: []
        property var windows: []
        property var capabilities: ({})

        property string activeTitle: ""
        property string activeAppId: ""
        property string activeIconName: ""
        property string activeMaterialIcon: ""
        property bool hasMaximizedWindow: false

        function isCapabilityAvailable(name) {
            if (!capabilities || !capabilities[name]) return false;
            return Boolean(capabilities[name].available);
        }

        function applySnapshot(snap) {
            if (!snap) return;
            if (snap.profile !== undefined) facade.profile = snap.profile;
            if (snap.connection !== undefined) facade.connection = snap.connection;
            if (snap.revision !== undefined) facade.revision = snap.revision;
            if (snap.outputs !== undefined) facade.outputs = snap.outputs;
            if (snap.workspaces !== undefined) facade.workspaces = snap.workspaces;
            if (snap.windows !== undefined) facade.windows = snap.windows;
            if (snap.capabilities !== undefined) facade.capabilities = snap.capabilities;
        }
    }

    function runTests() {
        console.log("=== Testing Omarchy Hosted Plugin Contract ===");

        // 1. Verify manifest.json exists and conforms to schemaVersion 1
        const manifestText = readLocalFile("../omarchy/manifest.json");
        assert(manifestText.length > 0, "manifest.json could not be loaded");

        let manifest = null;
        try {
            manifest = JSON.parse(manifestText);
        } catch (e) {
            assert(false, "manifest.json is not valid JSON: " + e.message);
        }

        assert(manifest.schemaVersion === 1, "manifest.schemaVersion must be 1, got " + manifest.schemaVersion);
        assert(manifest.id === "org.astralplasma.omarchy", "manifest.id must be org.astralplasma.omarchy");
        assert(Array.isArray(manifest.kinds), "manifest.kinds must be an array");
        assert(manifest.kinds.indexOf("service") !== -1, "manifest.kinds must contain 'service'");
        assert(manifest.kinds.indexOf("bar") !== -1, "manifest.kinds must contain 'bar'");
        assert(manifest.entryPoints && manifest.entryPoints.service === "Service.qml", "entryPoints.service must be Service.qml");
        assert(manifest.entryPoints && manifest.entryPoints.bar === "Bar.qml", "entryPoints.bar must be Bar.qml");
        assert(manifest.keepLoaded === true, "manifest.keepLoaded must be true");

        // 2. Verify Service.qml entry point contract
        const serviceSrc = readLocalFile("../omarchy/Service.qml");
        assert(serviceSrc.length > 0, "omarchy/Service.qml must exist and have content");
        assert(serviceSrc.indexOf("DesktopSessionFacade.profile = \"omarchy\"") !== -1, "Service.qml must set omarchy profile");
        assert(serviceSrc.indexOf("toggleDashboard") !== -1, "Service.qml must provide toggleDashboard");
        assert(serviceSrc.indexOf("toggleLauncher") !== -1, "Service.qml must provide toggleLauncher");
        assert(serviceSrc.indexOf("toggleSettings") !== -1, "Service.qml must provide toggleSettings");

        // 3. Verify Bar.qml entry point contract
        const barSrc = readLocalFile("../omarchy/Bar.qml");
        assert(barSrc.length > 0, "omarchy/Bar.qml must exist and have content");
        assert(barSrc.indexOf("RowLayout") !== -1, "Bar.qml must provide layout for bar components");

        // 4. Verify Facade behavior under Omarchy profile
        facade.applySnapshot({
            schemaVersion: 1,
            sessionId: "omarchy-test",
            profile: "omarchy",
            connection: "connected",
            capabilities: {
                workspaceSwitch: { available: true, mode: "dispatcher", owner: "hyprland" },
                backgroundBlur: { available: true, mode: "layerrule", owner: "hyprland" }
            }
        });

        assert(facade.profile === "omarchy", "Profile must be omarchy");
        assert(facade.isCapabilityAvailable("workspaceSwitch"), "workspaceSwitch must be available under omarchy");
        assert(facade.isCapabilityAvailable("backgroundBlur"), "backgroundBlur must be available under omarchy");

        console.log("PASS: Omarchy plugin contract verified");
        Qt.exit(0);
    }
}
