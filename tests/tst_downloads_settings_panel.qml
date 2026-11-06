import QtQuick
import "../dashboard/tabs/DownloadSettingsMath.js" as SettingsMath

/// Download settings inside the manager window.
///
/// The all-in-one Settings hub keeps the same controls, but a user already in
/// the download manager must be able to change the folder, default connections,
/// parallel count, speed cap, and border HUD without leaving the window. This
/// suite pins the panel's clamp rules and its wiring to the same Config setters
/// and engine push as Settings > Downloads.
Item {
    id: testRoot
    width: 900
    height: 800

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
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
        console.log("RUNNING: Download Settings In The Manager Window");

        // 1. Clamps mirror the settings page: the engine never sees 0/17.
        assert(SettingsMath.parts(99) === 16, "connections must clamp at 16");
        assert(SettingsMath.parts(0) === 1, "connections must clamp at 1");
        assert(SettingsMath.parts(8) === 8, "a valid connection count passes through");
        assert(SettingsMath.parallel(99) === 16, "parallel downloads must clamp at 16");
        assert(SettingsMath.parallel(0) === 1, "parallel downloads must clamp at 1");
        assert(SettingsMath.speedKbps(1234) === 1200, "speed must snap to 100 KiB/s steps");
        assert(SettingsMath.speedKbps(-5) === 0, "a negative cap is unlimited (0)");
        assert(SettingsMath.speedKbps(0) === 0, "zero is unlimited");

        // The signature equation and its labels must agree with the controls.
        assert(SettingsMath.capacity(5, 4) === 20, "5 parallel × 4 connections = 20");
        assert(SettingsMath.capacity(1, 1) === 1, "the floor is one connection");
        assert(SettingsMath.capacity(99, 99) === 256, "capacity uses the same clamps as the knobs");
        assert(SettingsMath.formatKbps(0) === "Unlimited", "0 reads as Unlimited");
        assert(SettingsMath.formatKbps(512) === "512 KiB/s", "sub-MiB caps read in KiB/s");
        assert(SettingsMath.formatKbps(2048) === "2 MiB/s", "whole MiB caps read cleanly");

        // 2. The panel is the same settings, not a parallel implementation.
        const panelSrc = readLocalFile("../dashboard/tabs/DownloadSettingsPanel.qml");
        for (const setter of ["setDownloadsDir", "setDownloadsSplit", "setDownloadsMaxConcurrent",
                              "setDownloadsSpeedLimit", "setDownloadsBorderEffect"]) {
            assert(panelSrc.indexOf("Config." + setter) >= 0,
                "the panel must use Config." + setter + " (the same setter as Settings)");
        }
        assert(panelSrc.indexOf("DownloadService.applyEngineSettings") >= 0,
            "engine-wide values must be pushed to the running aria2");
        assert(panelSrc.indexOf("FolderDialog") >= 0 && panelSrc.indexOf("TextInput") >= 0,
            "the destination must be an editable path with the native folder picker");
        assert(panelSrc.indexOf("capacity") >= 0 && panelSrc.indexOf("files at once") >= 0,
            "the panel must show the live capacity equation, not just three sliders");
        assert(panelSrc.indexOf("speedArea") >= 0 && panelSrc.indexOf("hudSwitch") >= 0,
            "speed and the border HUD need their own controls");

        // 3. The manager hosts it behind a header toggle; the drawer does not.
        const tabSrc = readLocalFile("../dashboard/tabs/DownloadsTab.qml");
        assert(/property bool settingsOpen/.test(tabSrc), "DownloadsTab must own the settings state");
        assert(/DownloadSettingsPanel\s*\{/.test(tabSrc), "the window must host the settings panel");
        assert(/visible:\s*root\.windowMode\s*&&\s*root\.settingsOpen/.test(tabSrc),
            "the settings panel belongs to the window, not the drawer");
        assert(/showTaskList:[\s\S]{0,160}!root\.settingsOpen/.test(tabSrc),
            "opening settings must hide the task list");

        const winSrc = readLocalFile("../shell/DownloadsWindow.qml");
        assert(/function openSettings\(\)/.test(winSrc), "the window must expose openSettings()");
        const shellSrc = readLocalFile("../shell.qml");
        assert(/target:\s*"downloads"[\s\S]{0,300}function settings\(\)/.test(shellSrc),
            "the downloads IPC must be able to open the settings panel");

        console.log("PASS: Download Settings In The Manager Window");
        Qt.exit(0);
    }
}
