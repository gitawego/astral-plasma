import QtQuick

/// A drawer belongs to the icon that has context for it.
///
/// The status group used to open the battery/status drawer just because the
/// pointer was somewhere over the pill. With the AI quota drawer already open,
/// moving onto the settings gear - an icon with no drawer of its own - left the
/// stale drawer on screen, because neither the group nor the gear changed it.
/// The contract now:
///
/// 1. The group background does not open a drawer by itself; each icon opens
///    its own drawer (battery, network, bluetooth, ...).
/// 2. The settings gear closes any open drawer on hover (and still closes on
///    click), so no contextless drawer survives the pointer.
Item {
    id: testRoot
    width: 400
    height: 600

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    /// Strips comments and string literals so prose cannot satisfy a contract.
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

    Component.onCompleted: {
        console.log("RUNNING: Status Group Hover Has No Contextless Drawer");

        const src = readLocalFile("../dock/components/DockStatusIcons.qml");
        assert(src.length > 1000, "DockStatusIcons.qml must be readable");
        const code = codeOnly(src);

        // 1. The group background must not open a drawer on its own.
        const groupStart = code.indexOf("id: groupHover");
        const groupEnd = code.indexOf("Column {", groupStart);
        assert(groupStart >= 0 && groupEnd > groupStart, "the group hover block must be locatable");
        const groupBlock = code.slice(groupStart, groupEnd);
        assert(groupBlock.indexOf("openBottomPopout(") >= 0,
            "the status pill still opens its status card away from the gear");
        assert(groupBlock.indexOf("settingsItem") >= 0,
            "the status pill must know when the pointer is over the gear");
        assert(/overSettings[\s\S]{0,200}closeBottomPopout\(\)/.test(groupBlock),
            "entering the pill over the settings gear must close the drawer instead of opening one");
        assert(groupBlock.indexOf("scheduleCloseBottomPopout(") >= 0,
            "leaving the status pill must still schedule the drawer closed");

        // 2. The settings gear closes the open drawer on hover, and never opens one.
        const settingsStart = code.indexOf("id: settingsItem");
        const settingsEnd = code.indexOf("id: pwrItem", settingsStart);
        assert(settingsStart >= 0 && settingsEnd > settingsStart,
            "the settings block must be locatable");
        const settingsBlock = code.slice(settingsStart, settingsEnd);
        assert(settingsBlock.indexOf("openBottomPopout(") < 0,
            "the settings gear must not open a drawer it has no context for");
        assert(/onEntered\s*:\s*[^;]*closeBottomPopout\(\)/.test(settingsBlock),
            "hovering the settings gear must close the open drawer");
        assert(/onClicked\s*:\s*[^}]*closeBottomPopout\(\)/.test(settingsBlock),
            "clicking the settings gear must still close the open drawer");

        console.log("PASS: Status Group Hover Has No Contextless Drawer");
        Qt.exit(0);
    }
}
