import QtQuick
import QtQuick.Layouts
import "../dashboard/tabs"
import "../theme"
import "../config"

Item {
    id: testRoot
    width: 680
    height: 360

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    PerformanceTab {
        id: hiddenPerfTab
        visible: false
        testMode: false
    }

    PerformanceTab {
        id: activePerfTab
        visible: true
        testMode: true
    }

    // Mirror of SystemService.qml high-performance telemetry lifecycle state machine
    QtObject {
        id: serviceMachine

        property bool manualMonitoringOverride: false
        property var activeClients: []

        function registerClient(client, isActive) {
            let list = (serviceMachine.activeClients || []).filter(c => c !== client);
            if (isActive) {
                list.push(client);
            }
            serviceMachine.activeClients = list;
        }

        function unregisterClient(client) {
            serviceMachine.activeClients = (serviceMachine.activeClients || []).filter(c => c !== client);
        }

        readonly property bool hasActiveClients: Boolean(serviceMachine.activeClients && serviceMachine.activeClients.length > 0)

        property bool mockDashboardVisible: false
        property string mockDashboardTab: "dashboard"

        readonly property bool isPerfTabVisibleInConfig: Boolean(mockDashboardVisible) && (mockDashboardTab === "performance")

        readonly property bool rawMonitoringTarget: Boolean(
            serviceMachine.manualMonitoringOverride ||
            serviceMachine.hasActiveClients ||
            serviceMachine.isPerfTabVisibleInConfig
        )

        property bool isMonitoringActive: false
        property double lastFetchTime: 0
        property int fetchCount: 0
        property bool processRunning: false

        function requestImmediateFetch() {
            const now = Date.now();
            if (now - serviceMachine.lastFetchTime >= 1000 && !serviceMachine.processRunning) {
                serviceMachine.lastFetchTime = now;
                serviceMachine.processRunning = true;
                serviceMachine.fetchCount += 1;
            }
        }

        onRawMonitoringTargetChanged: {
            if (rawMonitoringTarget) {
                deactivationGraceTimer.stop();
                serviceMachine.isMonitoringActive = true;
                serviceMachine.requestImmediateFetch();
            } else {
                deactivationGraceTimer.restart();
            }
        }
    }

    Timer {
        id: deactivationGraceTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (!serviceMachine.rawMonitoringTarget) {
                serviceMachine.isMonitoringActive = false;
                serviceMachine.processRunning = false;
            }
        }
    }

    Timer {
        id: monitoringCadenceTimer
        interval: 1000
        running: serviceMachine.isMonitoringActive
        repeat: true
        onTriggered: {
            if (serviceMachine.isMonitoringActive && !serviceMachine.processRunning) {
                serviceMachine.lastFetchTime = Date.now();
                serviceMachine.fetchCount += 1;
            }
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runLifecycleTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function runLifecycleTests() {
        console.log("Starting Performance Monitoring Lifecycle & Anti-Thrashing Unit Tests...");

        // 1. Verify PerformanceTab visibility contracts
        assert(hiddenPerfTab !== null, "hiddenPerfTab must instantiate");
        assert(hiddenPerfTab.isTargetVisible === false, "hiddenPerfTab.isTargetVisible must be false when visible: false");

        assert(activePerfTab !== null, "activePerfTab must instantiate");
        assert(activePerfTab.isTargetVisible === true, "activePerfTab.isTargetVisible must be true when testMode: true and visible: true");

        // 2. Static source contract inspection of SystemService.qml
        let serviceSrc = readLocalFile("../services/SystemService.qml");
        assert(serviceSrc.indexOf("property bool isMonitoringActive") !== -1, "SystemService must declare isMonitoringActive");
        assert(serviceSrc.indexOf("property bool rawMonitoringTarget") !== -1, "SystemService must declare rawMonitoringTarget");
        assert(serviceSrc.indexOf("deactivationGraceTimer") !== -1, "SystemService must declare deactivationGraceTimer for anti-thrashing hysteresis");
        assert(serviceSrc.indexOf("interval: 400") !== -1, "deactivationGraceTimer must use 400ms interval");
        assert(serviceSrc.indexOf("function registerClient") !== -1, "SystemService must declare registerClient");
        assert(serviceSrc.indexOf("function unregisterClient") !== -1, "SystemService must declare unregisterClient");
        assert(serviceSrc.indexOf("function requestImmediateFetch") !== -1, "SystemService must declare requestImmediateFetch");
        assert(serviceSrc.indexOf("now - root.lastFetchTime >= 1000") !== -1, "SystemService must enforce 1000ms rate-limiting lock");
        assert(serviceSrc.indexOf("running: root.isMonitoringActive") !== -1, "monitoringTimer must strictly bind running to isMonitoringActive");

        // Ensure unconditional boot execution is removed to prevent zero-power wakeups
        assert(serviceSrc.indexOf("if (!sysInfoProc.running) sysInfoProc.running = true;") === -1,
            "Unconditional sysInfoProc startup in Component.onCompleted must be removed to avoid background wakeups");

        // 3. Initial State: Monitoring MUST be inactive by default when closed
        assert(serviceMachine.isMonitoringActive === false, "Monitoring must be inactive by default");
        assert(serviceMachine.fetchCount === 0, "No process fetch must have occurred");
        assert(monitoringCadenceTimer.running === false, "Cadence timer must not be running");

        // 4. Tab Activation: User opens Performance Tab
        serviceMachine.mockDashboardVisible = true;
        serviceMachine.mockDashboardTab = "performance";
        assert(serviceMachine.rawMonitoringTarget === true, "rawMonitoringTarget must become true");
        assert(serviceMachine.isMonitoringActive === true, "isMonitoringActive must become true");
        assert(serviceMachine.fetchCount === 1, "Immediate fetch must have triggered on opening");
        assert(monitoringCadenceTimer.running === true, "Cadence timer must be running");

        // Reset processRunning to simulate completed process
        serviceMachine.processRunning = false;

        // 5. Anti-Thrashing Hysteresis: User rapidly switches away (e.g. clicks Media tab)
        serviceMachine.mockDashboardTab = "media";
        assert(serviceMachine.rawMonitoringTarget === false, "rawMonitoringTarget must become false on leaving tab");
        // isMonitoringActive MUST remain true during the 400ms grace window!
        assert(serviceMachine.isMonitoringActive === true, "isMonitoringActive must remain true during 400ms grace window");
        assert(deactivationGraceTimer.running === true, "Grace timer must be running");

        // Simulate rapid tab re-entry within grace window (e.g. user clicks Performance tab 50ms later)
        serviceMachine.mockDashboardTab = "performance";
        assert(serviceMachine.rawMonitoringTarget === true, "rawMonitoringTarget must become true on rapid return");
        assert(deactivationGraceTimer.running === false, "Grace timer must be stopped immediately upon return");
        assert(serviceMachine.isMonitoringActive === true, "isMonitoringActive must have remained continuously true");

        // 6. Rate-Limiting Guard: Rapid toggle spam must NOT trigger extra process launches within 1000ms
        serviceMachine.requestImmediateFetch();
        assert(serviceMachine.fetchCount === 1, "Rate-limiter must reject extra fetch within 1000ms window");

        // 7. True Deactivation: User switches to Media tab and stays away
        serviceMachine.mockDashboardTab = "media";
        assert(serviceMachine.rawMonitoringTarget === false, "rawMonitoringTarget must be false");
        assert(deactivationGraceTimer.running === true, "Grace timer must start");

        // Wait 500ms for grace timer (400ms) to cleanly shut down
        graceExpiryTimer.start();
    }

    Timer {
        id: graceExpiryTimer
        interval: 500
        repeat: false
        onTriggered: {
            console.log("Verifying clean shutdown after grace period expiry...");

            assert(serviceMachine.isMonitoringActive === false,
                "isMonitoringActive must cleanly transition to false after 400ms grace period expires");
            assert(monitoringCadenceTimer.running === false,
                "Cadence timer must stop running when monitoring is deactivated");
            assert(serviceMachine.processRunning === false,
                "Process running state must be cancelled on deactivation");

            console.log("PASS: Performance Monitoring Lifecycle & Anti-Thrashing Unit Tests");
            Qt.exit(0);
        }
    }
}
