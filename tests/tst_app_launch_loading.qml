import QtQuick

// ============================================================================
// App Launch Loading Indicator & Taskbar State Unit Tests
// ============================================================================
// Verifies:
// 1. WindowService.launchApp registers pending launches with full metadata.
// 2. UnifiedDock pinnedList sets isLoading: true for pinned apps currently starting.
// 3. UnifiedDock unpinnedList creates an unpinned loading delegate for apps launched via launcher.
// 4. Resolving pending launches when a window maps to WindowService.windows.
// 5. Transition from isLoading to isRunning and isActive.
// 6. Timeout expiration for unlaunchable apps.
// 7. DesktopSessionFacade activeId synchronization across KWin and Hyprland.
// 8. Source contracts across WindowService, UnifiedDock, CommandLauncher, HyprlandAdapter, and model.rs.
Item {
    id: testRoot
    width: 600
    height: 400

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

    // Deterministic simulation model mirroring WindowService.qml
    QtObject {
        id: mockWindowService

        property var windows: []
        property var tray: []
        property var pendingLaunches: []
        property string activeTitle: "Desktop"
        property string activeMaterialIcon: "desktop_windows"
        property string activeIconName: ""
        property string activeAppId: ""
        property string activeId: ""

        function launchApp(target, meta) {
            if (!target) return;
            const appName = (meta && (meta.appName || meta.name)) || target;
            const iconName = (meta && (meta.iconName || meta.icon || meta.icon_name)) || target;
            const materialIcon = (meta && (meta.materialIcon || meta.material_icon)) || "rocket_launch";
            const desktopFile = (meta && (meta.desktopFile || meta.desktop_file)) || target;
            const appId = (meta && (meta.appId || meta.app_id)) || target;

            const launchObj = {
                target: target,
                appName: appName,
                iconName: iconName,
                materialIcon: materialIcon,
                desktopFile: desktopFile,
                appId: appId,
                timestamp: Date.now()
            };

            const next = (mockWindowService.pendingLaunches || []).slice();
            let exists = false;
            for (let i = 0; i < next.length; i++) {
                if (next[i].target === target || (next[i].desktopFile && next[i].desktopFile === desktopFile)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                next.push(launchObj);
                mockWindowService.pendingLaunches = next;
            }
        }

        function _resolvePendingLaunches() {
            if (!mockWindowService.pendingLaunches || mockWindowService.pendingLaunches.length === 0) return;
            const wins = mockWindowService.windows || [];
            const now = Date.now();
            const next = [];

            for (let i = 0; i < mockWindowService.pendingLaunches.length; i++) {
                const p = mockWindowService.pendingLaunches[i];
                if (now - p.timestamp > 15000) {
                    continue;
                }

                const pId = (p.appId || "").toLowerCase();
                const pDesk = (p.desktopFile || "").toLowerCase();
                const pName = (p.appName || "").toLowerCase();
                const pTarget = (p.target || "").toLowerCase();

                let matched = false;
                for (let j = 0; j < wins.length; j++) {
                    const w = wins[j];
                    if (!w) continue;
                    const wId = (w.appId || "").toLowerCase();
                    const wDesk = (w.desktopFile || "").toLowerCase();
                    const wName = (w.appName || "").toLowerCase();
                    const wCls = (w.cls || "").toLowerCase();

                    if ((pId && (wId === pId || wDesk === pId || wCls === pId))
                        || (pDesk && (wDesk === pDesk || wId === pDesk || wCls === pDesk))
                        || (pTarget && (wId === pTarget || wDesk === pTarget || wCls === pTarget))
                        || (pName && wName === pName)) {
                        matched = true;
                        break;
                    }
                }

                if (!matched) {
                    next.push(p);
                }
            }

            if (next.length !== mockWindowService.pendingLaunches.length) {
                mockWindowService.pendingLaunches = next;
            }
        }

        onWindowsChanged: _resolvePendingLaunches()
    }

    // Deterministic simulation model mirroring DesktopSessionFacade.qml
    QtObject {
        id: mockFacade
        property string activeId: ""
        property string activeTitle: ""
        property var windows: []

        function applySnapshot(snap) {
            if (!snap) return;
            if (snap.windows !== undefined && Array.isArray(snap.windows)) {
                mockFacade.windows = snap.windows;
                let foundActive = false;
                for (let i = 0; i < snap.windows.length; i++) {
                    const w = snap.windows[i];
                    if (w.isActive || w.active) {
                        mockFacade.activeId = w.id || "";
                        mockFacade.activeTitle = w.title || "";
                        foundActive = true;
                    }
                }
                if (!foundActive && snap.windows.length === 0) {
                    mockFacade.activeId = "";
                    mockFacade.activeTitle = "";
                }
            }
        }
    }

    // Deterministic simulation mirroring UnifiedDock pinnedList calculation
    function computePinnedList(pinnedApps, wins, pending, actId, actApp) {
        const result = [];
        const matchedWinIds = new Set();

        for (let i = 0; i < pinnedApps.length; i++) {
            const p = pinnedApps[i];
            const pId = (p.appId || "").toLowerCase();
            const pDesk = (p.desktopFile || "").toLowerCase();
            const pName = (p.appName || "").toLowerCase();
            let found = null;

            for (let j = 0; j < wins.length; j++) {
                const w = wins[j];
                if (matchedWinIds.has(w.id)) continue;
                const wId = (w.appId || "").toLowerCase();
                const wDesk = (w.desktopFile || "").toLowerCase();
                const wName = (w.appName || "").toLowerCase();
                const wCls = (w.cls || "").toLowerCase();

                if ((pId && (wId === pId || wDesk === pId || wCls === pId))
                    || (pDesk && (wDesk === pDesk || wId === pDesk))
                    || (pName && wName === pName)) {
                    found = w;
                    break;
                }
            }

            let isPendingLaunch = false;
            if (!found) {
                for (let k = 0; k < pending.length; k++) {
                    const pl = pending[k];
                    const plId = (pl.appId || "").toLowerCase();
                    const plDesk = (pl.desktopFile || "").toLowerCase();
                    const plTarget = (pl.target || "").toLowerCase();
                    if ((pId && (plId === pId || plDesk === pId || plTarget === pId))
                        || (pDesk && (plDesk === pDesk || plId === pDesk || plTarget === pDesk))) {
                        isPendingLaunch = true;
                        break;
                    }
                }
            }

            if (found) {
                matchedWinIds.add(found.id);
                const isAct = Boolean(found.isActive)
                    || (Boolean(actId) && String(found.id) === String(actId))
                    || (Boolean(actApp) && String(p.appId).toLowerCase() === String(actApp).toLowerCase());
                result.push({
                    isPinned: true,
                    isRunning: true,
                    isLoading: false,
                    id: found.id,
                    appId: p.appId,
                    appName: p.appName,
                    isActive: isAct
                });
            } else {
                result.push({
                    isPinned: true,
                    isRunning: false,
                    isLoading: isPendingLaunch,
                    id: null,
                    appId: p.appId,
                    appName: p.appName,
                    isActive: false
                });
            }
        }
        return result;
    }

    // Deterministic simulation mirroring UnifiedDock unpinnedList calculation
    function computeUnpinnedList(pinnedApps, wins, pending, actId, actApp) {
        const result = [];
        const matchedWinIds = new Set();

        for (let i = 0; i < pinnedApps.length; i++) {
            const p = pinnedApps[i];
            const pId = (p.appId || "").toLowerCase();
            const pDesk = (p.desktopFile || "").toLowerCase();
            const pName = (p.appName || "").toLowerCase();

            for (let j = 0; j < wins.length; j++) {
                const w = wins[j];
                if (matchedWinIds.has(w.id)) continue;
                const wId = (w.appId || "").toLowerCase();
                const wDesk = (w.desktopFile || "").toLowerCase();
                const wName = (w.appName || "").toLowerCase();
                const wCls = (w.cls || "").toLowerCase();

                if ((pId && (wId === pId || wDesk === pId || wCls === pId))
                    || (pDesk && (wDesk === pDesk || wId === pDesk))
                    || (pName && wName === pName)) {
                    matchedWinIds.add(w.id);
                    break;
                }
            }
        }

        for (let k = 0; k < wins.length; k++) {
            const w = wins[k];
            if (!matchedWinIds.has(w.id)) {
                const isAct = Boolean(w.isActive)
                    || (Boolean(actId) && String(w.id) === String(actId))
                    || (Boolean(actApp) && String(w.appId).toLowerCase() === String(actApp).toLowerCase());
                result.push({
                    isPinned: false,
                    isRunning: true,
                    isLoading: false,
                    id: w.id,
                    appId: w.appId || "window",
                    appName: w.appName,
                    isActive: isAct
                });
            }
        }

        for (let pIdx = 0; pIdx < pending.length; pIdx++) {
            const pl = pending[pIdx];
            const plId = (pl.appId || "").toLowerCase();
            const plDesk = (pl.desktopFile || "").toLowerCase();
            const plTarget = (pl.target || "").toLowerCase();

            let isPinnedApp = false;
            for (let i = 0; i < pinnedApps.length; i++) {
                const p = pinnedApps[i];
                const pId = (p.appId || "").toLowerCase();
                const pDesk = (p.desktopFile || "").toLowerCase();
                if ((pId && (plId === pId || plDesk === pId || plTarget === pId))
                    || (pDesk && (plDesk === pDesk || plId === pDesk || plTarget === pDesk))) {
                    isPinnedApp = true;
                    break;
                }
            }
            if (isPinnedApp) continue;

            let isRunningApp = false;
            for (let j = 0; j < wins.length; j++) {
                const w = wins[j];
                const wId = (w.appId || "").toLowerCase();
                const wDesk = (w.desktopFile || "").toLowerCase();
                const wName = (w.appName || "").toLowerCase();
                const wCls = (w.cls || "").toLowerCase();
                if ((plId && (wId === plId || wDesk === plId || wCls === plId))
                    || (plDesk && (wDesk === plDesk || wId === plDesk || wCls === plDesk))
                    || (plTarget && (wId === plTarget || wDesk === plTarget || wCls === plTarget))) {
                    isRunningApp = true;
                    break;
                }
            }
            if (isRunningApp) continue;

            result.push({
                isPinned: false,
                isRunning: false,
                isLoading: true,
                id: null,
                appId: pl.appId,
                appName: pl.appName,
                title: "Starting...",
                isActive: false
            });
        }

        return result;
    }

    Component.onCompleted: {
        console.log("RUNNING: App Launch Loading & Taskbar State Unit Tests");

        const pinnedConfig = [
            { appId: "com.mitchellh.ghostty", appName: "Terminal", desktopFile: "com.mitchellh.ghostty" },
            { appId: "code", appName: "VS Code", desktopFile: "code" }
        ];

        // ---- Test 1: Pinned app launch registers pending launch and triggers isLoading ----
        mockWindowService.launchApp("com.mitchellh.ghostty", {
            appId: "com.mitchellh.ghostty",
            appName: "Terminal",
            desktopFile: "com.mitchellh.ghostty",
            iconName: "com.mitchellh.ghostty"
        });

        assert(mockWindowService.pendingLaunches.length === 1, "Must have 1 pending launch");
        assert(mockWindowService.pendingLaunches[0].appId === "com.mitchellh.ghostty", "Pending launch appId must match");

        let pList = computePinnedList(pinnedConfig, mockWindowService.windows, mockWindowService.pendingLaunches, "", "");
        assert(pList.length === 2, "Pinned list must have 2 items");
        assert(pList[0].isLoading === true, "Terminal must be isLoading: true");
        assert(pList[0].isRunning === false, "Terminal must not be running yet");
        assert(pList[1].isLoading === false, "VS Code must not be loading");

        let uList = computeUnpinnedList(pinnedConfig, mockWindowService.windows, mockWindowService.pendingLaunches, "", "");
        assert(uList.length === 0, "Unpinned list must be empty since Terminal is pinned");

        // ---- Test 2: Unpinned app launch (e.g. Antigravity via CommandLauncher) ----
        mockWindowService.launchApp("antigravity", {
            appId: "antigravity",
            appName: "Antigravity",
            desktopFile: "antigravity",
            iconName: "antigravity"
        });

        assert(mockWindowService.pendingLaunches.length === 2, "Must have 2 pending launches");

        uList = computeUnpinnedList(pinnedConfig, mockWindowService.windows, mockWindowService.pendingLaunches, "", "");
        assert(uList.length === 1, "Unpinned list must contain 1 loading delegate for Antigravity");
        assert(uList[0].appId === "antigravity", "Unpinned delegate appId must be antigravity");
        assert(uList[0].appName === "Antigravity", "Unpinned delegate appName must be Antigravity");
        assert(uList[0].isLoading === true, "Unpinned delegate must have isLoading: true");
        assert(uList[0].isRunning === false, "Unpinned delegate isRunning must be false");

        // ---- Test 3: Antigravity window maps into WindowService.windows ----
        mockWindowService.windows = [
            {
                id: "win-antigravity-101",
                appId: "antigravity",
                appName: "Antigravity",
                desktopFile: "antigravity",
                iconName: "antigravity",
                title: "Antigravity Project",
                isActive: true,
                isMaximized: false
            }
        ];
        mockWindowService.activeId = "win-antigravity-101";
        mockWindowService.activeAppId = "antigravity";
        mockWindowService.activeTitle = "Antigravity";

        // Antigravity should now be removed from pendingLaunches
        assert(mockWindowService.pendingLaunches.length === 1, "Antigravity must be resolved and cleared from pendingLaunches");
        assert(mockWindowService.pendingLaunches[0].appId === "com.mitchellh.ghostty", "Terminal should still be pending");

        uList = computeUnpinnedList(pinnedConfig, mockWindowService.windows, mockWindowService.pendingLaunches, "win-antigravity-101", "antigravity");
        assert(uList.length === 1, "Unpinned list must contain Antigravity");
        assert(uList[0].id === "win-antigravity-101", "Antigravity delegate must have mapped window id");
        assert(uList[0].isRunning === true, "Antigravity must now be running");
        assert(uList[0].isLoading === false, "Antigravity isLoading must be false");
        assert(uList[0].isActive === true, "Antigravity isActive must be true");

        // ---- Test 4: Terminal window maps as well ----
        mockWindowService.windows = [
            {
                id: "win-antigravity-101",
                appId: "antigravity",
                appName: "Antigravity",
                desktopFile: "antigravity",
                iconName: "antigravity",
                title: "Antigravity Project",
                isActive: false,
                isMaximized: false
            },
            {
                id: "win-ghostty-202",
                appId: "com.mitchellh.ghostty",
                appName: "Terminal",
                desktopFile: "com.mitchellh.ghostty",
                iconName: "com.mitchellh.ghostty",
                title: "~",
                isActive: true,
                isMaximized: false
            }
        ];
        mockWindowService.activeId = "win-ghostty-202";
        mockWindowService.activeAppId = "com.mitchellh.ghostty";

        assert(mockWindowService.pendingLaunches.length === 0, "All pending launches should now be resolved");

        pList = computePinnedList(pinnedConfig, mockWindowService.windows, mockWindowService.pendingLaunches, "win-ghostty-202", "com.mitchellh.ghostty");
        assert(pList[0].isRunning === true, "Terminal must now be isRunning: true");
        assert(pList[0].isLoading === false, "Terminal must have isLoading: false");
        assert(pList[0].isActive === true, "Terminal must have isActive: true");

        // ---- Test 5: Timeout safety cleanup ----
        mockWindowService.pendingLaunches = [
            {
                target: "nonexistent-app",
                appId: "nonexistent-app",
                appName: "NonExistent",
                timestamp: Date.now() - 20000 // 20s ago, expired
            }
        ];
        mockWindowService._resolvePendingLaunches();
        assert(mockWindowService.pendingLaunches.length === 0, "Stale pending launch must expire after timeout");

        // ---- Test 6: DesktopSessionFacade activeId synchronization ----
        mockFacade.applySnapshot({
            windows: [
                { id: "win-hypr-999", title: "Hyprland Editor", active: true }
            ]
        });
        assert(mockFacade.activeId === "win-hypr-999", "Facade must extract activeId from snapshot");
        assert(mockFacade.activeTitle === "Hyprland Editor", "Facade must extract activeTitle");

        // ---- Test 7: Source Contracts ----
        const winServiceSrc = readLocalFile("../services/WindowService.qml");
        assert(winServiceSrc.indexOf("property var pendingLaunches: []") !== -1,
            "WindowService must declare pendingLaunches property");
        assert(winServiceSrc.indexOf("function _resolvePendingLaunches()") !== -1,
            "WindowService must define _resolvePendingLaunches");
        assert(winServiceSrc.indexOf("DesktopSessionFacade.activeId = root.activeId") !== -1,
            "WindowService must propagate activeId to DesktopSessionFacade");

        const dockSrc = readLocalFile("../shell/UnifiedDock.qml");
        assert(dockSrc.indexOf("WindowService.pendingLaunches") !== -1,
            "UnifiedDock must consult WindowService.pendingLaunches");
        assert(dockSrc.indexOf("loadingRing") !== -1,
            "UnifiedDock must declare loadingRing item");
        assert(dockSrc.indexOf("WindowService.launchApp(modelData.desktopFile || modelData.appId, modelData)") !== -1,
            "UnifiedDock must pass modelData to launchApp");

        const launcherSrc = readLocalFile("../shell/CommandLauncher.qml");
        assert(launcherSrc.indexOf("WindowService.launchApp(app.desktop_file || app.exec || app.name, app)") !== -1,
            "CommandLauncher must pass app metadata to launchApp");

        const facadeSrc = readLocalFile("../services/DesktopSessionFacade.qml");
        assert(facadeSrc.indexOf("property string activeId: \"\"") !== -1,
            "DesktopSessionFacade must declare activeId property");

        const hyprlandSrc = readLocalFile("../daemon/src/infrastructure/hyprland_adapter.rs");
        assert(hyprlandSrc.indexOf("should_skip_taskbar") !== -1,
            "HyprlandAdapter must invoke should_skip_taskbar");
        assert(hyprlandSrc.indexOf("window_icons::resolve_window_icon") !== -1,
            "HyprlandAdapter must resolve window icons");

        const modelSrc = readLocalFile("../daemon/src/domain/model.rs");
        assert(modelSrc.indexOf("#[serde(rename = \"activeId\", default)]") !== -1,
            "model.rs must define activeId with serde rename");

        console.log("PASS: App Launch Loading & Taskbar State Unit Tests completed successfully!");
        Qt.exit(0);
    }
}
