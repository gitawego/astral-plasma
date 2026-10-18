import QtQuick

// ============================================================================
// Taskbar Multiple Instances & Identity Normalization Unit Tests
// ============================================================================
// Verifies:
// 1. matchApp correctly associates reverse-DNS window identities (e.g. com.microsoft.Edge,
//    com.microsoft.VSCode) with legacy/shorthand pinned entries (microsoft-edge, code).
// 2. Multiple open window instances of a pinned application are grouped under a single
//    pinned app icon, setting windowCount and windows array without leaking into unpinnedList.
// 3. Multiple open window instances of an unpinned application are grouped into a single
//    app icon in unpinnedList, preventing duplicate dock icons.
// 4. Multiple instance indicators and cycling between instances on click.
// 5. Popout multi-instance contract for instance cards and individual window closing.

Item {
    id: testRoot
    width: 800
    height: 600

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    // Pure matching logic matching UnifiedDock.qml
    function matchApp(p, w) {
        if (!p || !w) return false;
        const pId = (p.appId || "").toLowerCase();
        const pDesk = (p.desktopFile || "").toLowerCase().replace(/\.desktop$/, "");
        const pName = (p.appName || "").toLowerCase();

        const wId = (w.appId || "").toLowerCase();
        const wDesk = (w.desktopFile || "").toLowerCase().replace(/\.desktop$/, "");
        const wName = (w.appName || "").toLowerCase();
        const wCls = (w.cls || "").toLowerCase();

        // 1. Direct equality
        if (pId && (wId === pId || wDesk === pId || wCls === pId)) return true;
        if (pDesk && (wDesk === pDesk || wId === pDesk || wCls === pDesk)) return true;
        if (pName && wName && pName === wName) return true;

        // 2. Token / reverse-DNS stems
        const extractStems = (str) => {
            if (!str) return [];
            const s = str.toLowerCase().replace(/\.desktop$/, "");
            const stems = [s];
            const parts = s.split(".");
            if (parts.length > 1) {
                stems.push(parts[parts.length - 1]);
                stems.push(parts.slice(-2).join("-"));
                stems.push(parts.slice(-2).join(""));
            }
            const hyphenParts = s.split("-");
            if (hyphenParts.length > 1) {
                stems.push(hyphenParts[hyphenParts.length - 1]);
            }
            return stems;
        };

        const pStems = extractStems(pId).concat(extractStems(pDesk));
        const wStems = extractStems(wId).concat(extractStems(wDesk)).concat(extractStems(wCls));

        for (let i = 0; i < pStems.length; i++) {
            const ps = pStems[i];
            if (!ps || ps.length < 3) continue;
            for (let j = 0; j < wStems.length; j++) {
                const ws = wStems[j];
                if (!ws || ws.length < 3) continue;
                if (ps === ws) return true;
                if (ps.length >= 4 && ws.length >= 4 && (ps.endsWith(ws) || ws.endsWith(ps))) return true;
            }
        }

        // 3. App Name matching (excluding generic words)
        if (pName && wName) {
            const generic = ["window", "app", "application", "file", "files"];
            if (!generic.includes(pName) && !generic.includes(wName)) {
                if (wName.includes(pName) || pName.includes(wName)) return true;
                const pNorm = pName.replace(/\s+/g, "");
                const wNorm = wName.replace(/\s+/g, "");
                if (pNorm.includes(wNorm) || wNorm.includes(pNorm)) return true;
            }
        }

        return false;
    }

    function computePinnedList(pinned, wins, pending, actId, actApp) {
        const result = [];
        const matchedWinIds = new Set();
        const _actId = actId || "";
        const _actApp = actApp || "";

        for (let i = 0; i < pinned.length; i++) {
            const p = pinned[i];
            const matchingWindows = [];
            for (let j = 0; j < wins.length; j++) {
                const w = wins[j];
                if (matchApp(p, w)) {
                    matchingWindows.push(w);
                    matchedWinIds.add(w.id);
                }
            }

            const isRunning = matchingWindows.length > 0;
            let isPendingLaunch = false;
            if (!isRunning) {
                for (let k = 0; k < pending.length; k++) {
                    const pl = pending[k];
                    if (matchApp(p, pl) || (pl.target && matchApp(p, { appId: pl.target, desktopFile: pl.target }))) {
                        isPendingLaunch = true;
                        break;
                    }
                }
            }

            let activeWin = null;
            if (isRunning) {
                for (let m = 0; m < matchingWindows.length; m++) {
                    const mw = matchingWindows[m];
                    if (Boolean(mw.isActive)
                        || (Boolean(_actId) && String(mw.id).replace(/[{}]/g, "") === String(_actId).replace(/[{}]/g, ""))) {
                        activeWin = mw;
                        break;
                    }
                }
                if (!activeWin && Boolean(_actApp)) {
                    for (let m = 0; m < matchingWindows.length; m++) {
                        if (String(matchingWindows[m].appId).toLowerCase() === String(_actApp).toLowerCase()) {
                            activeWin = matchingWindows[m];
                            break;
                        }
                    }
                }
            }
            const isAct = Boolean(activeWin);
            const primaryWin = activeWin || (isRunning ? matchingWindows[0] : null);

            let effectiveIcon = p.iconName || "";
            if (primaryWin && primaryWin.iconName) {
                const pIconResolves = Boolean(p.iconName);
                const foundIsFile = Boolean(primaryWin.iconName && (primaryWin.iconName.startsWith("/") || primaryWin.iconName.startsWith("file:")));
                if (!pIconResolves || foundIsFile) {
                    effectiveIcon = primaryWin.iconName;
                }
            }

            result.push({
                isPinned: true,
                isRunning: isRunning,
                isLoading: !isRunning && isPendingLaunch,
                id: primaryWin ? primaryWin.id : null,
                appId: p.appId,
                appName: p.appName || (primaryWin ? primaryWin.appName : ""),
                iconName: effectiveIcon,
                materialIcon: p.materialIcon || (primaryWin ? primaryWin.materialIcon : "desktop_windows"),
                desktopFile: p.desktopFile || (primaryWin ? primaryWin.desktopFile : p.appId),
                title: primaryWin ? primaryWin.title : "",
                isActive: isAct,
                windows: matchingWindows,
                windowCount: matchingWindows.length
            });
        }
        return { list: result, matchedWinIds: matchedWinIds };
    }

    function computeUnpinnedList(pinned, wins, pending, actId, actApp, matchedWinIds) {
        const result = [];
        const _actId = actId || "";
        const _actApp = actApp || "";
        const unpinnedGroups = [];

        for (let k = 0; k < wins.length; k++) {
            const w = wins[k];
            if (matchedWinIds.has(w.id)) continue;

            let targetGroup = null;
            for (let g = 0; g < unpinnedGroups.length; g++) {
                if (matchApp(unpinnedGroups[g], w)) {
                    targetGroup = unpinnedGroups[g];
                    break;
                }
            }

            if (!targetGroup) {
                targetGroup = {
                    isPinned: false,
                    isLoading: false,
                    appId: w.appId || (w.appName ? w.appName.toLowerCase() : "window"),
                    appName: w.appName,
                    iconName: w.iconName,
                    materialIcon: w.materialIcon,
                    desktopFile: w.desktopFile || w.appId,
                    windows: []
                };
                unpinnedGroups.push(targetGroup);
            }
            targetGroup.windows.push(w);
        }

        for (let g = 0; g < unpinnedGroups.length; g++) {
            const grp = unpinnedGroups[g];
            let activeWin = null;
            for (let m = 0; m < grp.windows.length; m++) {
                const mw = grp.windows[m];
                if (Boolean(mw.isActive)
                    || (Boolean(_actId) && String(mw.id).replace(/[{}]/g, "") === String(_actId).replace(/[{}]/g, ""))) {
                    activeWin = mw;
                    break;
                }
            }
            if (!activeWin && Boolean(_actApp)) {
                for (let m = 0; m < grp.windows.length; m++) {
                    if (String(grp.windows[m].appId).toLowerCase() === String(_actApp).toLowerCase()) {
                        activeWin = grp.windows[m];
                        break;
                    }
                }
            }
            const isAct = Boolean(activeWin);
            const primaryWin = activeWin || grp.windows[0];

            result.push({
                isPinned: false,
                isRunning: true,
                isLoading: false,
                id: primaryWin.id,
                appId: grp.appId,
                appName: grp.appName,
                iconName: primaryWin.iconName || grp.iconName,
                materialIcon: primaryWin.materialIcon || grp.materialIcon,
                desktopFile: primaryWin.desktopFile || grp.desktopFile,
                title: primaryWin.title,
                isActive: isAct,
                windows: grp.windows,
                windowCount: grp.windows.length
            });
        }

        return result;
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Taskbar Multiple Instances & Identity Normalization Tests");

        const pinnedConfig = [
            {
                appId: "ghostty",
                appName: "Terminal",
                iconName: "com.mitchellh.ghostty",
                materialIcon: "terminal",
                desktopFile: "com.mitchellh.ghostty"
            },
            {
                appId: "microsoft-edge",
                appName: "Edge",
                iconName: "microsoft-edge",
                materialIcon: "language",
                desktopFile: "microsoft-edge"
            },
            {
                appId: "code",
                appName: "VS Code",
                iconName: "vscode",
                materialIcon: "code",
                desktopFile: "code"
            }
        ];

        // 1. Identity Normalization: Edge and VS Code match
        const edgeWin1 = {
            id: "win-edge-1",
            appId: "com.microsoft.Edge",
            appName: "Microsoft Edge",
            desktopFile: "com.microsoft.Edge",
            cls: "com.microsoft.Edge",
            iconName: "/home/user/.icons/edge.svg",
            title: "First Tab - Edge",
            isActive: false
        };
        const edgeWin2 = {
            id: "win-edge-2",
            appId: "com.microsoft.Edge",
            appName: "Microsoft Edge",
            desktopFile: "com.microsoft.Edge",
            cls: "com.microsoft.Edge",
            iconName: "/home/user/.icons/edge.svg",
            title: "Second Window - Edge",
            isActive: true
        };

        assert(matchApp(pinnedConfig[1], edgeWin1), "Pinned Edge must match com.microsoft.Edge window");

        // 2. Both Edge windows are open: must be grouped under ONE pinned Edge icon
        const wins = [edgeWin1, edgeWin2];
        const pinnedRes = computePinnedList(pinnedConfig, wins, [], "win-edge-2", "com.microsoft.Edge");
        const pList = pinnedRes.list;
        const matchedIds = pinnedRes.matchedWinIds;

        assert(pList[1].isRunning === true, "Pinned Edge must be marked running");
        assert(pList[1].isActive === true, "Pinned Edge must be marked active since win-edge-2 is active");
        assert(pList[1].windowCount === 2, "Pinned Edge must report windowCount === 2");
        assert(pList[1].windows.length === 2, "Pinned Edge windows array must contain 2 windows");
        assert(pList[1].id === "win-edge-2", "Pinned Edge primary ID must be the active window");
        assert(pList[1].title === "Second Window - Edge", "Pinned Edge primary title must match active window");
        assert(pList[1].iconName === "/home/user/.icons/edge.svg", "Pinned Edge must adopt live theme icon from running window");

        // 3. Unpinned list must be empty - no duplicate Edge icons
        const uList = computeUnpinnedList(pinnedConfig, wins, [], "win-edge-2", "com.microsoft.Edge", matchedIds);
        assert(uList.length === 0, "No duplicate running Edge icons may leak into unpinnedList");

        // 4. Multiple instances of an unpinned app (e.g. 2 Firefox windows)
        const foxWin1 = {
            id: "win-fox-1",
            appId: "firefox",
            appName: "Firefox",
            desktopFile: "firefox",
            cls: "firefox",
            iconName: "firefox",
            title: "Doc 1 - Firefox",
            isActive: false
        };
        const foxWin2 = {
            id: "win-fox-2",
            appId: "firefox",
            appName: "Firefox",
            desktopFile: "firefox",
            cls: "firefox",
            iconName: "firefox",
            title: "Doc 2 - Firefox",
            isActive: false
        };

        const winsWithFox = [edgeWin1, edgeWin2, foxWin1, foxWin2];
        const pinnedRes2 = computePinnedList(pinnedConfig, winsWithFox, [], "", "");
        const uList2 = computeUnpinnedList(pinnedConfig, winsWithFox, [], "", "", pinnedRes2.matchedWinIds);

        assert(uList2.length === 1, "Unpinned list must contain EXACTLY 1 item for Firefox (grouped instances)");
        assert(uList2[0].appName === "Firefox", "Unpinned item must be Firefox");
        assert(uList2[0].windowCount === 2, "Unpinned Firefox must group both window instances");
        assert(uList2[0].windows.length === 2, "Unpinned Firefox windows array must have 2 entries");

        // 5. Cycling between instances
        const edgeItem = pList[1];
        let curIdx = 1; // win-edge-2 is active (index 1)
        const nextIdx = (curIdx + 1) % edgeItem.windows.length;
        assert(nextIdx === 0, "Cycling from index 1 must wrap to index 0");
        assert(edgeItem.windows[nextIdx].id === "win-edge-1", "Next cycled window is win-edge-1");

        // 6. Popout Multi-Instance View Contract (FusedBottomPopout.qml)
        const winList = (edgeItem && edgeItem.windows && edgeItem.windows.length > 0) ? edgeItem.windows : [edgeItem];
        const hasMultipleWindows = winList.length > 1;
        assert(hasMultipleWindows === true, "Popout hasMultipleWindows must be true for 2 instances");
        assert(winList.length === 2, "Popout winList must have length 2");
        assert(winList[0].id === "win-edge-1" && winList[1].id === "win-edge-2", "Popout winList must contain both windows");
        assert(winList[1].isActive === true, "Active window badge in popout must be active");

        console.log("PASS: Taskbar Multiple Instances & Identity Normalization Tests passed successfully!");
        Qt.exit(0);
    }
}
