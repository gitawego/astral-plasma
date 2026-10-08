import QtQuick
import QtQuick.Layouts
import "../components"
import "../dashboard/tabs"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    MediaTab {
        id: testMediaTab
        width: 680
        visible: false
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error("FAIL: " + msg);
        }
    }

    function readLocalFile(path) {
        let xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(path), false);
        xhr.send();
        return xhr.responseText;
    }

    function runTests() {
        console.log("RUNNING: Media Seek & Progress Unit Tests");

        // 1. MediaTab Source Contract Verification
        const mediaSrc = readLocalFile("../dashboard/tabs/MediaTab.qml");
        assert(/enabled:\s*\(typeof MprisMedia !== "undefined"\)\s*&&\s*MprisMedia\.canSeek/.test(mediaSrc),
               "MediaTab sliderMouse must be gated with MprisMedia.canSeek");
        assert(/isDragging/.test(mediaSrc),
               "MediaTab sliderMouse must track isDragging state for smooth scrubbing");
        assert(/onReleased:/.test(mediaSrc),
               "MediaTab must commit seek onReleased rather than spamming DBus on every pixel");
        assert(!/text:\s*\{[^}]*style:\s*Text\.Outline[^}]*\}/.test(mediaSrc),
               "MediaTab must not place style: Text.Outline inside text function body");

        // 2. DashboardTab Source Contract Verification
        const dashSrc = readLocalFile("../dashboard/tabs/DashboardTab.qml");
        assert(/MprisMedia\.seekTo\(/.test(dashSrc),
               "DashboardTab must call MprisMedia.seekTo() instead of assigning to readonly MprisMedia.position");
        assert(!/MprisMedia\.position\s*=\s*ratio/.test(dashSrc),
               "DashboardTab must NOT assign to readonly MprisMedia.position");
        assert(/enabled:\s*\(typeof MprisMedia !== "undefined"\)\s*&&\s*MprisMedia\.canSeek/.test(dashSrc),
               "DashboardTab seek MouseArea must be gated with MprisMedia.canSeek");

        // 3. MprisMedia.qml Source Contract Verification
        const mprisSrc = readLocalFile("../services/MprisMedia.qml");
        assert(/function seekTo\(fraction\)\s*\{[\s\S]*?if\s*\(!canSeek\)\s*return;/.test(mprisSrc),
               "MprisMedia.seekTo must immediately return if !canSeek (no fake position mutation)");

        // 4. Mock Seek Logic Verification
        const mockSeekService = {
            length: 200,
            currentPosition: 50,
            canSeek: false,
            lastSeekCall: -1,
            seekTo: function(fraction) {
                if (!this.canSeek) return;
                let frac = Math.max(0.0, Math.min(1.0, fraction));
                this.currentPosition = frac * this.length;
                this.lastSeekCall = this.currentPosition;
            }
        };

        // When canSeek is false (e.g. NetEase Cloud Music Wine):
        mockSeekService.seekTo(0.8);
        assert(mockSeekService.currentPosition === 50,
               "When canSeek is false, seekTo must NOT fabricate position (currentPosition must remain 50)");
        assert(mockSeekService.lastSeekCall === -1,
               "When canSeek is false, no seek command should be dispatched");

        // When canSeek is true (e.g. native MPRIS player):
        mockSeekService.canSeek = true;
        mockSeekService.seekTo(0.8);
        assert(mockSeekService.currentPosition === 160,
               "When canSeek is true, currentPosition must update to 160");
        assert(mockSeekService.lastSeekCall === 160,
               "When canSeek is true, seek command must be dispatched with target seconds");

        console.log("PASS: Media seek & progress tests passed successfully!");
        Qt.exit(0);
    }
}
