import QtQuick

/// The battery drawer owns power profiles; the dock must not open it twice.
///
/// `DockStatusIcons` used to declare a second, standalone "Power Profile"
/// indicator right below the battery one. Both opened the same fused drawer
/// (`FusedBottomPopout` renders one section for modes "battery" and "default"),
/// and the standalone icon's left click only re-requested the mode the status
/// pill's hover already opened - so it looked like a duplicate that did nothing.
/// It was also absent from the Settings list and had no visibility guard, so it
/// survived turning the battery indicator off.
///
/// Contract now: exactly one indicator opens the battery/profile drawer, and
/// that indicator keeps the quick-switch gesture (middle click = cycle profile)
/// that the removed icon used to provide.
Item {
    id: testRoot
    width: 800
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    /// Strips comments and string literals so a contract cannot be satisfied by
    /// a passing mention in prose.
    function codeOnly(src) {
        let out = "";
        let i = 0;
        const n = src.length;
        while (i < n) {
            const c = src[i];
            const d = src[i + 1];
            if (c === "/" && d === "/") {
                while (i < n && src[i] !== "\n") i++;
            } else if (c === "/" && d === "*") {
                i += 2;
                while (i < n && !(src[i] === "*" && src[i + 1] === "/")) i++;
                i += 2;
            } else if (c === "\"" || c === "'") {
                const quote = c;
                i++;
                while (i < n && src[i] !== quote) {
                    if (src[i] === "\\") i++;
                    i++;
                }
                i++;
            } else {
                out += c;
                i++;
            }
        }
        return out;
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    function countOccurrences(haystack, needle) {
        let count = 0;
        let at = haystack.indexOf(needle);
        while (at !== -1) {
            count++;
            at = haystack.indexOf(needle, at + needle.length);
        }
        return count;
    }

    Component.onCompleted: {
        console.log("RUNNING: Dock Power Profile Has A Single Entry");

        const dockSrc = readLocalFile("../dock/components/DockStatusIcons.qml");
        const fusedSrc = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        const powerSrc = readLocalFile("../services/PowerService.qml");
        assert(dockSrc.length > 1000, "DockStatusIcons.qml must be readable");
        assert(fusedSrc.length > 1000, "FusedBottomPopout.qml must be readable");
        assert(powerSrc.length > 1000, "PowerService.qml must be readable");

        const dockCode = codeOnly(dockSrc);
        const fusedCode = codeOnly(fusedSrc);

        // 1. No second battery/profile entry icon.
        assert(dockCode.indexOf("profileItem") < 0,
            "DockStatusIcons must not declare a standalone profile indicator");
        assert(countOccurrences(dockCode, "id: batteryItem") === 1,
            "DockStatusIcons must declare exactly one battery indicator");

        // 2. The surviving battery indicator owns the whole battery/profile contract.
        const batteryStart = dockCode.indexOf("id: batteryItem");
        const batteryEnd = dockCode.indexOf("id: aiItem", batteryStart);
        assert(batteryStart >= 0 && batteryEnd > batteryStart,
            "the battery indicator block must be locatable");
        const batteryBlock = dockCode.slice(batteryStart, batteryEnd);
        // The drawer mode is a string literal, so check it on the raw source
        // between the same two markers.
        const rawBatteryStart = dockSrc.indexOf("id: batteryItem");
        const rawBatteryEnd = dockSrc.indexOf("id: aiItem", rawBatteryStart);
        const rawBatteryBlock = dockSrc.slice(rawBatteryStart, rawBatteryEnd);
        assert(rawBatteryBlock.indexOf("openBottomPopout(\"battery\"") >= 0,
            "the battery indicator must still open the battery drawer");
        assert(batteryBlock.indexOf("PowerService.cycleProfile()") >= 0,
            "the battery indicator must keep middle-click profile cycling");
        assert(/acceptedButtons\s*:\s*Qt\.LeftButton\s*\|\s*Qt\.MiddleButton/.test(batteryBlock),
            "the battery indicator must accept both left and middle clicks");

        // 2b. Removing the always-visible profile icon must not strand desktops:
        // the battery slot stays reachable when only power profiles exist.
        assert(powerSrc.indexOf("property bool hasPowerProfiles") >= 0,
            "PowerService must expose whether a power-profile backend answered");
        assert(/hasPowerProfiles\s*=\s*true/.test(powerSrc),
            "PowerService must mark profiles available when powerprofilesctl answers");
        assert(batteryBlock.indexOf("PowerService.hasPowerProfiles") >= 0,
            "the battery indicator must stay visible for profile-only desktops");

        // 3. The drawer itself still offers all three profiles.
        for (const id of ["power-saver", "balanced", "performance"]) {
            assert(fusedSrc.indexOf("\"" + id + "\"") >= 0,
                "the battery drawer must still offer the '" + id + "' profile");
        }
        assert(fusedCode.indexOf("PowerService.setProfile") >= 0,
            "the battery drawer must still apply a selected profile");

        console.log("PASS: Dock Power Profile Has A Single Entry");
        Qt.exit(0);
    }
}
