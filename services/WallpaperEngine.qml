pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    property string currentWallpaper: ""
    property string previewWallpaper: ""
    readonly property string effectiveWallpaper: (previewWallpaper && previewWallpaper.length > 0) ? previewWallpaper : currentWallpaper
    readonly property bool isVideo: checkIsVideo(effectiveWallpaper)

    property var wallpapers: []
    property var categories: ["All"]
    property bool isLoading: false
    property string activeCategory: "All"

    function checkIsVideo(path) {
        if (!path || typeof path !== "string") return false;
        const low = path.toLowerCase();
        return low.endsWith(".mp4") || low.endsWith(".webm") || low.endsWith(".mkv") || low.endsWith(".mov");
    }

    function preview(path) {
        if (!path) return;
        previewWallpaper = path;
        if (typeof Config !== "undefined" && Config.daemonBin && !paletteProc.running) {
            paletteProc.command = [Config.daemonBin, "wallpaper", "palette", path];
            paletteProc.running = true;
        }
    }

    function stopPreview() {
        previewWallpaper = "";
        if (currentWallpaper && typeof Config !== "undefined" && Config.daemonBin && !paletteProc.running) {
            paletteProc.command = [Config.daemonBin, "wallpaper", "palette", currentWallpaper];
            paletteProc.running = true;
        }
    }

    function setMockWallpapers(list) {
        wallpapers = list || [];
        updateCategories();
    }

    function updateCategories() {
        let cats = { "All": true };
        for (let i = 0; i < wallpapers.length; i++) {
            if (wallpapers[i].category) {
                cats[wallpapers[i].category] = true;
            }
        }
        root.categories = Object.keys(cats);
    }

    function filterWallpapers(query, category) {
        const q = (query || "").trim().toLowerCase();
        const cat = (category && category !== "All") ? category.toLowerCase() : "";

        return wallpapers.filter(item => {
            if (cat && (!item.category || item.category.toLowerCase() !== cat)) {
                return false;
            }
            if (q) {
                const nameMatch = (item.name || "").toLowerCase().indexOf(q) !== -1;
                const pathMatch = (item.path || "").toLowerCase().indexOf(q) !== -1;
                if (!nameMatch && !pathMatch) return false;
            }
            return true;
        });
    }

    function setWallpaper(path) {
        if (!path) return;
        currentWallpaper = path;
        previewWallpaper = "";

        // Trigger daemon wallpaper set and palette extraction
        if (!setProc.running) {
            setProc.command = [Config.daemonBin, "wallpaper", "set", path];
            setProc.running = true;
        }

        if (!paletteProc.running) {
            paletteProc.command = [Config.daemonBin, "wallpaper", "palette", path];
            paletteProc.running = true;
        }
    }

    function reloadWallpapers() {
        if (!listProc.running) {
            isLoading = true;
            listProc.command = [Config.daemonBin, "wallpaper", "list"];
            listProc.running = true;
        }
    }

    Process {
        id: getProc
        command: [Config.daemonBin, "wallpaper", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text.trim());
                    if (data && data.path) {
                        root.currentWallpaper = data.path;
                    } else if (root.wallpapers.length > 0) {
                        root.currentWallpaper = root.wallpapers[0].path;
                    }
                } catch (e) {}
            }
        }
    }

    function deduplicateWallpapers(list) {
        if (!list || !Array.isArray(list)) return [];
        let seenNames = {};
        let result = [];
        for (let i = 0; i < list.length; i++) {
            let item = list[i];
            let name = (item.name || "").toLowerCase();
            if (name === "screenshot") continue;
            if (!seenNames[name]) {
                seenNames[name] = true;
                result.push(item);
            }
        }
        return result.length > 0 ? result : list;
    }

    Process {
        id: listProc
        command: [Config.daemonBin, "wallpaper", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoading = false;
                try {
                    const parsed = JSON.parse(this.text.trim());
                    if (Array.isArray(parsed)) {
                        root.wallpapers = root.deduplicateWallpapers(parsed);
                        root.updateCategories();
                        if (!root.currentWallpaper && root.wallpapers.length > 0) {
                            root.currentWallpaper = root.wallpapers[0].path;
                        }
                    }
                } catch (e) {
                    console.warn("[WallpaperEngine] Failed to parse wallpapers list:", e);
                }
            }
        }
    }

    /// A plasmashell restart rewrites its containment config from its own saved
    /// state, which silently reverts the wallpaper the user picked in the
    /// picker. The config is watched so the shell can put its own choice back
    /// instead of letting the desktop (and the picker) drift to a wallpaper the
    /// user never chose.
    FileView {
        id: plasmaConfigWatch
        path: {
            const home = Quickshell.env("HOME");
            return (home && home.length > 0)
                ? home + "/.config/plasma-org.kde.plasma.desktop-appletsrc"
                : "";
        }
        watchChanges: true
        onFileChanged: root.reconcileActiveWallpaper()
    }

    function reconcileActiveWallpaper() {
        if (typeof Config === "undefined" || !Config.daemonBin || reconcileProc.running) {
            return;
        }
        reconcileProc.command = [Config.daemonBin, "wallpaper", "reconcile"];
        reconcileProc.running = true;
    }

    Process {
        id: reconcileProc
        stdout: StdioCollector {
            onStreamFinished: {
                // Reconciliation may have re-applied the state's wallpaper, so
                // read the current one again instead of trusting the old value.
                getProc.running = true;
            }
        }
    }

    Process {
        id: setProc
    }

    Process {
        id: paletteProc
    }

    Component.onCompleted: {
        getProc.running = true;
        listProc.running = true;
        reconcileActiveWallpaper();
    }
}
