import QtQuick
import "../theme"

Item {
    id: testRoot
    width: 600
    height: 800

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
            throw new Error(msg);
        }
    }

    function readLocalFile(relativePath) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relativePath), false);
        xhr.send(null);
        return xhr.responseText;
    }

    function runTests() {
        console.log("RUNNING: Popout Drawer Padding and Concentric Clearance Tests");

        // 1. Source contracts on FusedBottomPopout.qml
        const popoutSrc = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        assert(popoutSrc.length > 1000, "FusedBottomPopout.qml must be readable");

        // Padding tokens definition contracts
        assert(/readonly\s+property\s+int\s+drawerOuterMargin:\s*\(typeof\s+Theme\s*!==\s*"undefined"\s*&&\s*Theme\.padMedium\)\s*\?\s*Theme\.padMedium\s*:\s*12/.test(popoutSrc),
            "FusedBottomPopout must define drawerOuterMargin tied to Theme.padMedium (fallback 12)");
        assert(/readonly\s+property\s+int\s+drawerInnerPadding:\s*\(typeof\s+Theme\s*!==\s*"undefined"\s*&&\s*Theme\.padLarge\)\s*\?\s*Theme\.padLarge\s*:\s*16/.test(popoutSrc),
            "FusedBottomPopout must define drawerInnerPadding tied to Theme.padLarge (fallback 16)");
        assert(/readonly\s+property\s+int\s+drawerTotalMargin:\s*drawerOuterMargin\s*\+\s*drawerInnerPadding/.test(popoutSrc),
            "FusedBottomPopout must define drawerTotalMargin as sum of outer margin and inner padding");

        // popCard height contract includes total margins on top and bottom
        assert(/implicitHeight:\s*root\.targetContentHeight\s*\+\s*root\.drawerTotalMargin\s*\*\s*2/.test(popoutSrc),
            "popCard.implicitHeight must include 2x drawerTotalMargin");

        // ghosttySurface anchors contract
        assert(/anchors\.fill:\s*contentLoader/.test(popoutSrc),
            "ghosttySurface must wrap contentLoader");
        assert(/anchors\.margins:\s*-root\.drawerInnerPadding/.test(popoutSrc),
            "ghosttySurface must expand by drawerInnerPadding around contentLoader");

        // contentLoader margin contract
        assert(/anchors\.margins:\s*root\.drawerTotalMargin/.test(popoutSrc),
            "contentLoader must be inset by drawerTotalMargin from popCard");

        // Battery / default popout width contract (at least 300px for generous breathing room)
        assert(/case\s*"battery":\s*\n\s*default:\s*return\s*300;/.test(popoutSrc),
            "Battery/default popout width must be 300px for generous breathing room");

        // Concentric geometry:
        // Outer margin = drawerTotalMargin - drawerInnerPadding = 12px.
        // Inner padding = drawerInnerPadding = 16px.
        const outerMarginMatch = popoutSrc.match(/drawerOuterMargin:[^\n]*?:\s*(\d+)/);
        const innerPaddingMatch = popoutSrc.match(/drawerInnerPadding:[^\n]*?:\s*(\d+)/);
        assert(outerMarginMatch && parseInt(outerMarginMatch[1]) >= 12,
            "drawerOuterMargin must be at least 12px");
        assert(innerPaddingMatch && parseInt(innerPaddingMatch[1]) >= 16,
            "drawerInnerPadding must be at least 16px");

        // Accent palette adaptation:
        // ghosttySurface background and border must follow Colors.drawerSubstrate
        assert(/Colors\.drawerSubstrate\b/.test(popoutSrc),
            "ghosttySurface must bind color to Colors.drawerSubstrate to follow active accent palette");
        assert(/Colors\.drawerSubstrateBorder\b/.test(popoutSrc),
            "ghosttySurface must bind border.color to Colors.drawerSubstrateBorder");

        // Verify Colors.qml defines drawerSubstrate tokens tied to root.primary
        const colorsSrc = readLocalFile("../theme/Colors.qml");
        assert(/readonly\s+property\s+color\s+drawerSubstrate:/.test(colorsSrc),
            "Colors.qml must define drawerSubstrate token");
        assert(/readonly\s+property\s+color\s+drawerSubstrateBorder:/.test(colorsSrc),
            "Colors.qml must define drawerSubstrateBorder token");
        assert(/drawerSubstrate:[^;]*?Qt\.alpha\(root\.primary/.test(colorsSrc),
            "Colors.drawerSubstrate must reactively tint with root.primary accent palette");

        console.log("PASS: Popout Drawer Padding and Concentric Clearance Tests passed!");
        Qt.exit(0);
    }
}
