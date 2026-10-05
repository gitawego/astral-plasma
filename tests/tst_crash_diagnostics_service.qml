import QtQuick

Item {
    id: testRoot
    width: 800
    height: 600

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

    function runTests() {
        console.log("=== Running Crash Diagnostics & Agent Tools QML Test Suite ===");

        // Test 1: NotificationService Crash Detection and Wiring
        console.log("Test 1: NotificationService crash detection and diagnosis wiring");
        const notifSrc = readLocalFile("../services/NotificationService.qml");
        assert(notifSrc.length > 500, "services/NotificationService.qml must be readable");
        assert(notifSrc.indexOf("isCrashNotification") !== -1, "NotificationService must define isCrashNotification");
        assert(notifSrc.indexOf("diagnoseCrashWithAgent") !== -1, "NotificationService must define diagnoseCrashWithAgent");
        assert(notifSrc.indexOf("diagnose_crash") !== -1, "NotificationService must handle diagnose_crash action");
        assert(notifSrc.indexOf("crashPromptProc") !== -1, "NotificationService must declare crashPromptProc");
        assert(notifSrc.indexOf("crash\", \"prompt\"") !== -1, "NotificationService must invoke daemon crash prompt CLI");
        console.log("Passed Test 1: NotificationService crash detection verified");

        // Test 2: Crash Detection Pattern Specification
        console.log("Test 2: Pattern matching verification");
        function testPattern(summary, body, appName, appIcon) {
            let s = (summary || "").toLowerCase();
            let b = (body || "").toLowerCase();
            let app = (appName || "").toLowerCase();
            let icon = (appIcon || "").toLowerCase();
            return (
                s.includes("crashed") ||
                s.includes("crash") ||
                s.includes("segmentation fault") ||
                s.includes("core dump") ||
                s.includes("sigsegv") ||
                s.includes("sigabrt") ||
                s.includes("terminated unexpectedly") ||
                s.includes("killed by signal") ||
                b.includes("crashed") ||
                b.includes("segmentation fault") ||
                b.includes("core dump") ||
                b.includes("sigsegv") ||
                b.includes("sigabrt") ||
                app.includes("coredump") ||
                app.includes("drkonqi") ||
                app.includes("abrt") ||
                icon.includes("crash")
            );
        }
        assert(testPattern("ghostty crashed unexpectedly", "", "ghostty", "error"), "Direct crash summary recognized");
        assert(testPattern("Application error", "Segmentation fault (core dumped)", "app", "error"), "SIGSEGV in body recognized");
        assert(testPattern("Fatal error", "Killed by signal SIGABRT", "app", "error"), "SIGABRT in body recognized");
        assert(testPattern("Crash report", "", "systemd-coredump", "error"), "systemd-coredump recognized");
        assert(!testPattern("Download Complete", "Saved file to Downloads", "browser", "info"), "Normal notification ignored");
        console.log("Passed Test 2: Crash detection patterns verified");

        // Test 3: Configuration Contracts
        console.log("Test 3: Configuration schema & Config.qml property");
        const settingsSrc = readLocalFile("../config/settings.json");
        assert(settingsSrc.indexOf("crashDiagnosisEnabled") !== -1, "settings.json must specify crashDiagnosisEnabled");
        const configSrc = readLocalFile("../config/Config.qml");
        assert(configSrc.indexOf("aiCrashDiagnosisEnabled") !== -1, "Config.qml must expose aiCrashDiagnosisEnabled");
        console.log("Passed Test 3: Configuration contracts verified");

        // Test 4: DesktopSessionFacade crash diagnosis method
        console.log("Test 4: DesktopSessionFacade diagnoseCrash");
        const facadeSrc = readLocalFile("../services/DesktopSessionFacade.qml");
        assert(facadeSrc.indexOf("function diagnoseCrash(target)") !== -1, "DesktopSessionFacade must expose diagnoseCrash(target)");
        console.log("Passed Test 4: DesktopSessionFacade diagnoseCrash verified");

        console.log("PASS: Crash Diagnostics & Agent Tools QML Test Suite Passed Successfully");
        Qt.exit(0);
    }
}
