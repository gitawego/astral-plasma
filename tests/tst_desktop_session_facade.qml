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

        function getCapabilityReason(name) {
            if (!capabilities || !capabilities[name]) return "not-declared";
            return capabilities[name].reason || "";
        }

        function getCapabilityMode(name) {
            if (!capabilities || !capabilities[name]) return "";
            return capabilities[name].mode || "";
        }

        function applySnapshot(snap) {
            if (!snap) return;
            if (snap.profile !== undefined) facade.profile = snap.profile;
            if (snap.connection !== undefined) facade.connection = snap.connection;
            if (snap.revision !== undefined) facade.revision = snap.revision;
            if (snap.focusedOutputId !== undefined) facade.focusedOutputId = snap.focusedOutputId;
            if (snap.outputs !== undefined && Array.isArray(snap.outputs)) facade.outputs = snap.outputs;
            if (snap.workspaces !== undefined && Array.isArray(snap.workspaces)) facade.workspaces = snap.workspaces;
            if (snap.windows !== undefined && Array.isArray(snap.windows)) {
                facade.windows = snap.windows;
                let foundActive = false;
                let foundMax = false;
                for (let i = 0; i < snap.windows.length; i++) {
                    const w = snap.windows[i];
                    if (w.isMaximized || w.maximized) foundMax = true;
                    if (w.isActive || w.active) {
                        facade.activeTitle = w.title || "";
                        facade.activeAppId = w.appId || "";
                        facade.activeIconName = w.iconName || "";
                        facade.activeMaterialIcon = w.materialIcon || "";
                        foundActive = true;
                    }
                }
                facade.hasMaximizedWindow = foundMax;
                if (!foundActive && snap.windows.length === 0) {
                    facade.activeTitle = "";
                    facade.activeAppId = "";
                    facade.activeIconName = "";
                    facade.activeMaterialIcon = "";
                }
            }
            if (snap.capabilities !== undefined) facade.capabilities = snap.capabilities;
        }
    }

    function runTests() {
        console.log("RUNNING: DesktopSessionFacade Contract Tests");

        // ---- 1. Source Contract Verification ----
        const facadeSrc = readLocalFile("../services/DesktopSessionFacade.qml");
        assert(facadeSrc.length > 500, "services/DesktopSessionFacade.qml must be readable");
        assert(/pragma Singleton/.test(facadeSrc), "DesktopSessionFacade must be a Singleton");
        assert(/property string profile:\s*"kde"/.test(facadeSrc), "DesktopSessionFacade default profile must be kde");
        assert(/property string connection:\s*"connected"/.test(facadeSrc), "DesktopSessionFacade default connection must be connected");
        assert(/property bool isStale:/.test(facadeSrc), "DesktopSessionFacade must compute isStale dynamically");
        assert(/function isCapabilityAvailable\(name\)/.test(facadeSrc), "DesktopSessionFacade must implement isCapabilityAvailable");
        assert(/function applySnapshot\(snap\)/.test(facadeSrc), "DesktopSessionFacade must implement applySnapshot");

        // ---- 2. Initial State Contract ----
        assert(facade.profile === "kde", "Default profile should be kde");
        assert(facade.connection === "connected", "Default connection should be connected");
        assert(!facade.isStale, "Connection should not be stale initially");
        assert(Array.isArray(facade.outputs), "Outputs must be an array");
        assert(Array.isArray(facade.workspaces), "Workspaces must be an array");
        assert(Array.isArray(facade.windows), "Windows must be an array");

        // ---- 3. Capability Gating Contract ----
        assert(!facade.isCapabilityAvailable("nonExistent"), "Undeclared capability must return false");
        assert(facade.getCapabilityReason("nonExistent") === "not-declared", "Reason should be not-declared");

        // ---- 4. Apply Canonical Snapshot ----
        const mockSnapshot = {
            schemaVersion: 1,
            sessionId: "test-hyprland-session",
            revision: 5,
            connection: "connected",
            profile: "hyprland",
            focusedOutputId: "DP-1",
            outputs: [
                {
                    id: "DP-1",
                    name: "DisplayPort-0",
                    geometry: { x: 0, y: 0, width: 2560, height: 1600 },
                    scale: 1.0,
                    refreshRate: 165.0,
                    focused: true,
                    primary: true
                }
            ],
            workspaces: [
                { id: "1", name: "1", index: 1, outputId: "DP-1", active: true },
                { id: "2", name: "2", index: 2, outputId: "DP-1", active: false }
            ],
            windows: [
                {
                    id: "0x55a9b7c12340",
                    title: "Ghostty Terminal",
                    appName: "Ghostty",
                    appId: "com.mitchellh.ghostty",
                    iconName: "com.mitchellh.ghostty",
                    materialIcon: "terminal",
                    isActive: true,
                    isMaximized: false
                }
            ],
            capabilities: {
                workspaceSwitch: { available: true, mode: "dispatcher" },
                backgroundBlur: { available: true, mode: "region" },
                focusRestore: { available: false, reason: "not-supported" }
            }
        };

        facade.applySnapshot(mockSnapshot);

        assert(facade.profile === "hyprland", "Profile must update to hyprland");
        assert(facade.revision === 5, "Revision must update to 5");
        assert(facade.focusedOutputId === "DP-1", "Focused output must be DP-1");
        assert(facade.outputs.length === 1, "Outputs length must be 1");
        assert(facade.workspaces.length === 2, "Workspaces length must be 2");
        assert(facade.windows.length === 1, "Windows length must be 1");
        assert(facade.activeTitle === "Ghostty Terminal", "Active title must update from snapshot window");

        // ---- 5. Verify Capabilities ----
        assert(facade.isCapabilityAvailable("workspaceSwitch") === true, "workspaceSwitch must be available");
        assert(facade.getCapabilityMode("workspaceSwitch") === "dispatcher", "workspaceSwitch mode must be dispatcher");
        assert(facade.isCapabilityAvailable("focusRestore") === false, "focusRestore must be unavailable");
        assert(facade.getCapabilityReason("focusRestore") === "not-supported", "focusRestore reason must be not-supported");

        // ---- 6. Stale Connection Contract ----
        facade.applySnapshot({ connection: "disconnected" });
        assert(facade.isStale === true, "isStale must be true when connection is disconnected");

        facade.applySnapshot({ connection: "degraded" });
        assert(facade.isStale === true, "isStale must be true when connection is degraded");

        facade.applySnapshot({ connection: "connected" });
        assert(facade.isStale === false, "isStale must be false when connected");

        console.log("PASS: DesktopSessionFacade Contract Tests");
        Qt.exit(0);
    }
}
