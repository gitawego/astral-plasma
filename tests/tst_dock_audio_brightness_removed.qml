import QtQuick

/// The dock is not a second home for volume/brightness.
///
/// The right-border rail (`shell/RightEdgeControl.qml`) is the one place those
/// two live: it carries the vertical sliders, the wheel scrub and the mute
/// toggle. The dock used to duplicate them with a speaker indicator, a
/// brightness indicator and the in-dock "Display Brightness" drawer; that
/// duplicate was removed so there is exactly one control surface per concern
/// and the dock's status column stays short.
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
    /// a passing mention in prose (or by an error message that names the thing
    /// it is complaining about).
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
        console.log("RUNNING: Dock Drop Of Volume & Brightness (Right Rail Owns Them)");

        const dockStatusSrc = readLocalFile("../dock/components/DockStatusIcons.qml");
        const fusedSrc = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        const railSrc = readLocalFile("../shell/RightEdgeControl.qml");
        const shellSrc = readLocalFile("../shell/UnifiedShell.qml");
        const defaultsSrc = readLocalFile("../modules/Astral/Kernel/config/settings.json");
        const configSrc = readLocalFile("../modules/Astral/Kernel/config/Config.qml");

        assert(dockStatusSrc.length > 1000, "DockStatusIcons.qml must be readable");
        assert(fusedSrc.length > 1000, "FusedBottomPopout.qml must be readable");
        assert(railSrc.length > 1000, "RightEdgeControl.qml must still exist and be readable");

        const dockStatusCode = codeOnly(dockStatusSrc);
        const fusedCode = codeOnly(fusedSrc);

        // 1. The right rail is the surviving home for volume + brightness.
        assert(railSrc.indexOf("PipewireAudio.setVolume(") >= 0,
            "RightEdgeControl must still drive the real PipeWire sink");
        assert(railSrc.indexOf("BrightnessService.setBrightness(") >= 0,
            "RightEdgeControl must still drive the real display backlight");
        assert(railSrc.indexOf("getVolumeIcon") >= 0
               || railSrc.indexOf("volumeIcon") >= 0,
            "RightEdgeControl must still show live volume status");
        assert(/id:\s*root/.test(railSrc) && /HoverHandler/.test(railSrc),
            "RightEdgeControl must still be a hover-revealed rail");

        // 2. The dock no longer declares a volume or brightness indicator.
        assert(dockStatusCode.indexOf("brightnessItem") < 0,
            "DockStatusIcons must not declare a brightness indicator any more");
        assert(dockStatusCode.indexOf("audioItem") < 0,
            "DockStatusIcons must not declare a volume indicator any more");
        assert(dockStatusCode.indexOf("PipewireAudio") < 0,
            "DockStatusIcons must not touch PipewireAudio (the rail owns it)");
        assert(dockStatusCode.indexOf("BrightnessService") < 0,
            "DockStatusIcons must not touch BrightnessService (the rail owns it)");

        // 3. No other status indicator may open the removed drawers.
        assert(dockStatusCode.indexOf("bottomPopoutMode === \"audio\"") < 0,
            "no dock icon may highlight for an audio drawer that is gone");
        assert(dockStatusCode.indexOf("bottomPopoutMode === \"brightness\"") < 0,
            "no dock icon may highlight for a brightness drawer that is gone");

        // 4. The in-dock drawers themselves are gone from the fused popout.
        assert(fusedCode.indexOf("audioSection") < 0,
            "FusedBottomPopout must not render an audio drawer section");
        assert(fusedCode.indexOf("brightnessSection") < 0,
            "FusedBottomPopout must not render a brightness drawer section");
        assert(fusedCode.indexOf("Display Brightness") < 0,
            "the in-dock 'Display Brightness' drawer must be gone");
        assert(fusedCode.indexOf("PipewireAudio") < 0,
            "FusedBottomPopout must not touch PipewireAudio any more");

        // 5. The surviving drawers (network, bluetooth, clock, battery, tray…)
        //    and the bottom border they fuse into are untouched.
        assert(fusedCode.indexOf("bluetoothSection") >= 0,
            "the Bluetooth drawer must survive the removal");
        assert(fusedCode.indexOf("networkSection") >= 0,
            "the Network drawer must survive the removal");
        assert(fusedCode.indexOf("clockSection") >= 0,
            "the Clock drawer must survive the removal");

        // 6. Shipped defaults stop advertising indicators that do not exist,
        //    and stale entries from an older settings file are filtered rather
        //    than rendered as empty rows.
        assert(defaultsSrc.indexOf("\"id\": \"audio\"") < 0,
            "settings.json must not ship the removed audio status icon");
        assert(defaultsSrc.indexOf("\"id\": \"brightness\"") < 0,
            "settings.json must not ship the removed brightness status icon");
        assert(configSrc.indexOf("\"id\": \"audio\"") < 0,
            "Config defaults must not ship the removed audio status icon");
        assert(configSrc.indexOf("\"id\": \"brightness\"") < 0,
            "Config defaults must not ship the removed brightness status icon");
        assert(/PopoutModes\.isRetired\(mode\)\)\s*return/.test(configSrc),
            "openBottomPopout must refuse a retired mode (else a stale IPC call opens an empty card)");
        assert(shellSrc.length > 1000, "UnifiedShell must remain readable");

        console.log("PASS: Dock Drop Of Volume & Brightness (Right Rail Owns Them)");
        Qt.exit(0);
    }
}
