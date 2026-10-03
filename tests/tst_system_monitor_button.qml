import QtQuick
import QtQuick.Layouts
import "../dashboard/tabs"
import "../theme"

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
        id: perfTab
        anchors.fill: parent
        testMode: true
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: {
            console.log("Starting System Monitor Button Unit Tests...");

            function assert(condition, message) {
                if (!condition) {
                    console.error("FAIL: " + message);
                    Qt.exit(1);
                    throw new Error(message);
                }
            }

            // 1. Instantiation & API presence
            assert(perfTab !== null, "PerformanceTab must instantiate");
            assert(typeof perfTab.openSystemMonitor === "function", "PerformanceTab must expose openSystemMonitor function");

            // Calling openSystemMonitor in testMode must succeed cleanly without side effects
            perfTab.openSystemMonitor();

            // 2. PerformanceTab Source Audit
            const perfSrc = readLocalFile("../dashboard/tabs/PerformanceTab.qml");
            assert(perfSrc.length > 500, "PerformanceTab.qml source must be readable");
            assert(perfSrc.indexOf("import Quickshell") === -1, "PerformanceTab must not import Quickshell (must remain instantiable under standard qml6)");
            assert(perfSrc.indexOf("Quickshell.execDetached") === -1, "PerformanceTab must not use raw Quickshell.execDetached without service abstraction");
            assert(perfSrc.indexOf("openSystemMonitor") !== -1, "PerformanceTab must implement openSystemMonitor");
            assert(/sysMonMa[\s\S]*?cursorShape:\s*Qt\.PointingHandCursor/.test(perfSrc), "System monitor MouseArea must have cursorShape: Qt.PointingHandCursor");
            assert(/sysMonMa[\s\S]*?onClicked:\s*root\.openSystemMonitor\(\)/.test(perfSrc) || /sysMonMa[\s\S]*?onClicked:[\s\S]*?openSystemMonitor/.test(perfSrc), "System monitor MouseArea onClicked must call openSystemMonitor");

            // 3. WindowService Service Audit
            const wsSrc = readLocalFile("../services/WindowService.qml");
            assert(wsSrc.length > 500, "WindowService.qml source must be readable");
            assert(wsSrc.indexOf("function openSystemMonitor()") !== -1, "WindowService must expose openSystemMonitor()");
            assert(wsSrc.indexOf('"system-monitor"') !== -1 || wsSrc.indexOf("'system-monitor'") !== -1, "WindowService must invoke daemon system-monitor command");

            // 4. SystemService Service Audit
            const ssSrc = readLocalFile("../services/SystemService.qml");
            assert(ssSrc.length > 500, "SystemService.qml source must be readable");
            assert(ssSrc.indexOf("function openSystemMonitor()") !== -1, "SystemService must expose openSystemMonitor()");

            console.log("PASS: System Monitor Button Tests");
            Qt.exit(0);
        }
    }
}
