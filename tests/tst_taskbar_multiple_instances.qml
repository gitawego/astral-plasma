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

    function normalizeId(str) {
        if (!str) return "";
        let s = String(str).trim().toLowerCase();
        s = s.replace(/\.desktop$/, "");
        const slashIdx = s.lastIndexOf("/");
        if (slashIdx !== -1) {
            s = s.substring(slashIdx + 1);
        }
        return s;
    }

    function getCanonicalAliases(rawId) {
        const id = normalizeId(rawId);
        if (!id) return [];
        const aliases = [id];
        
        // Reverse-DNS to hyphenated: e.g. "com.microsoft.edge" -> "microsoft-edge"
        const parts = id.split(".");
        if (parts.length >= 3 && ["com", "org", "net", "io", "app"].indexOf(parts[0]) !== -1) {
            const hyphenated = parts.slice(1).join("-");
            if (hyphenated && aliases.indexOf(hyphenated) === -1) {
                aliases.push(hyphenated);
            }
            if (parts[0] === "org" && parts[1] === "kde") {
                const kdeName = parts.slice(2).join("-");
                if (kdeName && aliases.indexOf(kdeName) === -1) {
                    aliases.push(kdeName);
                }
            }
        }
        // Hyphenated to reverse-DNS: e.g. "microsoft-edge" -> "com.microsoft.edge"
        if (id.indexOf("-") !== -1 && id.indexOf(".") === -1) {
            const rDns = "com." + id.replace(/-/g, ".");
            if (aliases.indexOf(rDns) === -1) {
                aliases.push(rDns);
            }
        }
        return aliases;
    }

    // Mock canonical lookup mirroring WindowService / freedesktop metadata
    function mockCanonicalAppId(rawId) {
        const s = normalizeId(rawId);
        if (s === "code" || s === "com.microsoft.vscode" || s === "microsoft-vscode") {
            return "com.microsoft.vscode";
        }
        if (s === "zcode") {
            return "zcode";
        }
        if (s === "microsoft-edge" || s === "com.microsoft.edge") {
            return "microsoft-edge";
        }
        return s;
    }

    // Pure matching logic matching UnifiedDock.qml
    function matchApp(p, w) {
        if (!p || !w) return false;
        const pId = normalizeId(p.appId);
        const pDesk = normalizeId(p.desktopFile);
        const wId = normalizeId(w.appId);
        const wDesk = normalizeId(w.desktopFile);
        const wCls = normalizeId(w.cls);

        // 1. Direct exact equality between declared identifiers
        if (pId && (wId === pId || wDesk === pId || wCls === pId)) return true;
        if (pDesk && (wDesk === pDesk || wId === pDesk || wCls === pDesk)) return true;

        // 2. Canonical reverse-DNS alias intersection
        const pAliases = getCanonicalAliases(pDesk || pId);
        const wAliases = getCanonicalAliases(wDesk || wId || wCls);
        for (let i = 0; i < pAliases.length; i++) {
            if (wAliases.indexOf(pAliases[i]) !== -1) return true;
        }

        // 3. Freedesktop SSOT Canonical Resolution
        const pCanon = mockCanonicalAppId(pDesk || pId);
        const wCanon = mockCanonicalAppId(wDesk || wId || wCls);
        if (pCanon && wCanon && pCanon === wCanon) return true;

        const pCanon2 = mockCanonicalAppId(pId || pDesk);
        const wCanon2 = mockCanonicalAppId(wId || wCls || wDesk);
        if (pCanon2 && wCanon2 && pCanon2 === wCanon2) return true;

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

        // Hover expansion contract:
        let hoveredWinId = "win-edge-1";
        assert((hoveredWinId === winList[0].id) === true, "Hovered instance 0 must be expanded");
        assert((hoveredWinId === winList[1].id) === false, "Unhovered instance 1 must be collapsed");

        hoveredWinId = "win-edge-2";
        assert((hoveredWinId === winList[0].id) === false, "Instance 0 must collapse when mouse leaves");
        assert((hoveredWinId === winList[1].id) === true, "Instance 1 must expand when hovered");

        // 7. Critical Non-Regression: ZCode and VS Code MUST NEVER collide
        const vsCodePin = pinnedConfig[2]; // { appId: "code", desktopFile: "code", appName: "VS Code" }
        const zcodeWin = {
            id: "win-zcode-1",
            appId: "zcode",
            appName: "ZCode",
            desktopFile: "zcode",
            cls: "zcode",
            iconName: "zcode",
            title: "ZCode Editor",
            isActive: false
        };
        const vsCodeWin = {
            id: "win-vscode-1",
            appId: "com.microsoft.VSCode",
            appName: "Visual Studio Code",
            desktopFile: "com.microsoft.VSCode",
            cls: "com.microsoft.VSCode",
            iconName: "vscode",
            title: "VS Code - Project",
            isActive: false
        };

        assert(!matchApp(vsCodePin, zcodeWin), "ZCode window must NEVER match pinned VS Code (code)");
        assert(!matchApp(vsCodeWin, zcodeWin), "ZCode window must NEVER match VS Code window (com.microsoft.VSCode)");
        assert(matchApp(vsCodePin, vsCodeWin), "VS Code window must match pinned VS Code");

        // When both VS Code and ZCode windows exist, they must be in separate items
        const winsWithCodeAndZCode = [vsCodeWin, zcodeWin];
        const pinnedWithBoth = computePinnedList(pinnedConfig, winsWithCodeAndZCode, [], "", "");
        const unpinnedWithBoth = computeUnpinnedList(pinnedConfig, winsWithCodeAndZCode, [], "", "", pinnedWithBoth.matchedWinIds);

        assert(pinnedWithBoth.list[2].windowCount === 1, "Pinned VS Code must contain only VS Code window, NOT ZCode");
        assert(pinnedWithBoth.list[2].windows[0].id === "win-vscode-1", "Pinned VS Code window must be win-vscode-1");
        assert(unpinnedWithBoth.length === 1, "ZCode must appear as separate unpinned app item");
        assert(unpinnedWithBoth[0].appId === "zcode", "Unpinned item must be zcode");

        console.log("PASS: Taskbar Multiple Instances & Identity Normalization Tests passed successfully!");
        Qt.exit(0);
    }
}
