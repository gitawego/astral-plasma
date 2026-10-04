import QtQuick

/**
 * Chat stream watchdog contract.
 *
 * Regression: a Copilot turn that ran several tools was cut off at a fixed
 * 60 s after it started, mid-investigation, with no answer and no notice
 * (the cut-off only explained itself when the transcript was still empty).
 * A healthy agent turn is long and multi-step, so the watchdog must measure
 * *silence*, not elapsed time: every event from the stream re-arms it, and a
 * genuine stall is always reported to the user.
 */
Item {
    id: testRoot
    width: 100
    height: 100

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + "?v=" + Date.now() + Math.random(), false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: {
            const src = testRoot.readLocalFile("../services/AssistantService.qml");
            testRoot.assert(src.length > 500, "AssistantService.qml must be readable");

            const wd = /Timer \{\s*id: streamWatchdog[\s\S]*?\n    \}/.exec(src);
            testRoot.assert(wd, "streamWatchdog must exist");
            const m = /interval:\s*(\d+)/.exec(wd[0]);
            testRoot.assert(m && parseInt(m[1]) >= 120000,
                "the watchdog is an idle timeout and must tolerate long silent tool runs (>= 120 s)");

            // The stdout/stderr readers must re-arm it on every event.
            const stdoutBlock = /stdout: SplitParser \{[\s\S]*?id: streamProc|id: streamProc[\s\S]*?stderr: SplitParser/.exec(src);
            const streamBlock = /id: streamProc[\s\S]*?onExited/.exec(src);
            testRoot.assert(streamBlock, "streamProc block must exist");
            testRoot.assert(/streamWatchdog\.restart\(\)/.test(streamBlock[0]),
                "stream activity must re-arm the idle watchdog");
            const stdoutPart = /stdout: SplitParser[\s\S]*?stderr: SplitParser/.exec(streamBlock[0]);
            testRoot.assert(stdoutPart && /streamWatchdog\.restart\(\)/.test(stdoutPart[0]),
                "stdout events must re-arm the idle watchdog");

            // A stall is always explained, even when partial output exists.
            testRoot.assert(!/if \(!root\.activeStreamingContent\) \{\s*root\.activeStreamingContent = "⚠️ Request timed out/.test(wd[0]),
                "a timeout must be reported even when some content already streamed");
            testRoot.assert(/timed out/.test(wd[0]), "the timeout notice must remain");

            console.log("PASS: stream watchdog is an idle timeout");
            Qt.exit(0);
        }
    }
}
