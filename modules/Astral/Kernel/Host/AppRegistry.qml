import QtQuick
import Quickshell
import Quickshell.Io
import "AppHostPolicy.js" as Policy

// ============================================================================
// AppRegistry — read what is installed, and merge it with each app's manifest
// ============================================================================
// The daemon owns `apps.json` (one writer). This is the reader: for every recorded
// app it loads `<appsRoot>/<id>/manifest.json`, merges the registry's state
// (`enabled`, `pinned`, `blocked`, grants) over it, and hands `AppHost` entries it
// can validate and plan.
//
// Two things it deliberately does not do:
//
//  * **write** anything — the daemon is the single writer, so a crash here cannot
//    corrupt the registry;
//  * **fail** — a missing registry is an empty desktop state, and a manifest that
//    is missing or corrupt becomes one skipped row with a reason, never an error
//    that reaches the shell. `errors` carries them for the Apps page and the logs.
//
// `FileView` is read with `text()` + `JSON.parse`: `data()` returns an empty object
// for these files (docs/APPS-PLATFORM-SPEC.md C.7), so the text is the contract.
QtObject {
    id: root

    /// `~/.local/share/astral-plasma/apps.json`. When empty the bundled index is
    /// used instead: a checkout or a fresh package has no registry yet, and the
    /// desktop must still boot with its shipped apps.
    property string registryPath: ""
    /// Directory holding `<id>/manifest.json` + `payload/` (installed apps).
    property string appsRoot: ""
    /// Directory holding `<dir>/manifest.json` + `index.json` (bundled apps).
    property string bundledRoot: ""

    readonly property bool bundled: registryPath.length === 0 || appsRoot.length === 0

    /// Where the daemon records app state, also in bundled mode: a bundled app can be
    /// disabled, pinned or have a version blocked, and the host must honour that.
    property string statePath: ""

    /// `[{ id, state, reason }]` for problems found while reading.
    readonly property var errors: collectErrors()
    /// Merged entries, ready for `AppHost.entries`.
    readonly property var entries: collectEntries()

    readonly property string registryText: registryReader.text()

    /// The parsed registry, refreshed when the file changes (never parsed inside a
    /// binding: reading and re-reading it there produced a binding loop the moment the
    /// watcher existed).
    property var stateSnapshot: ({})

    Component.onCompleted: root.adoptState()

    function adoptState() {
        try {
            const parsed = JSON.parse(stateReader.text());
            root.stateSnapshot = (parsed && typeof parsed === "object") ? parsed : ({});
        } catch (error) {
            root.stateSnapshot = ({});
        }
    }

    /// Apps the user removed on purpose. A bundled app is synthesised into the plan when
    /// it has no record, so without this a removal would be cosmetic: the row disappeared
    /// from Settings while the surface kept mounting.
    readonly property var removedIds: {
        const removed = root.stateSnapshot ? root.stateSnapshot.removed : null;
        return Array.isArray(removed) ? removed : [];
    }

    /// Installed records, or one synthetic record per bundled app. Both are
    /// `{ id, enabled, blocked, pinned }`, so everything downstream is one path.
    readonly property var records: {
        if (root.bundled) {
            const recorded = root.recordedById;
            const removed = root.removedIds;
            return Policy.withoutRemoved(root.bundledIndex, removed).map(function (app) {
                const record = recorded[app.id];
                return {
                    id: app.id,
                    // A bundled app is enabled unless the user disabled it.
                    enabled: record ? record.enabled !== false : true,
                    blocked: record && Array.isArray(record.blocked) ? record.blocked : [],
                    pinned: record ? !!record.pinned : false,
                    dir: app.dir
                };
            });
        }
        // Same snapshot as the bundled path, so a live registry change reaches the plan
        // whichever way the app list is sourced.
        const parsed = root.stateSnapshot;
        return (parsed && Array.isArray(parsed.apps)) ? parsed.apps : [];
    }

    /// The daemon's records, by id (empty when there is no registry yet).
    readonly property var recordedById: {
        const byId = ({});
        const parsed = root.stateSnapshot;
        const apps = (parsed && Array.isArray(parsed.apps)) ? parsed.apps : [];
        for (let index = 0; index < apps.length; index++) {
            if (apps[index] && typeof apps[index].id === "string") {
                byId[apps[index].id] = apps[index];
            }
        }
        return byId;
    }

    property FileView stateReader: FileView {
        path: root.statePath
        blockLoading: true
        printErrors: false
        // Enabling, disabling or removing an app rewrites this file. Without a watch the
        // plan kept the state it read at startup, so a removal only took effect after a
        // restart — which reads exactly like "the button does nothing".
        watchChanges: true
        // `fileChanged` only announces the change: `text()` still returns the old contents
        // until `reload()` re-reads them, and only then does `loaded` fire. Enabling,
        // disabling or removing an app rewrote this file while nothing upstream re-read it,
        // so the plan kept its startup state and a removal looked like a dead button.
        onFileChanged: stateReader.reload()
        onLoaded: root.adoptState()
    }



    readonly property var bundledIndex: {
        try {
            const parsed = JSON.parse(indexReader.text());
            return (parsed && Array.isArray(parsed.apps)) ? parsed.apps : [];
        } catch (error) {
            return [];
        }
    }

    function collectErrors() {
        const problems = [];
        if (root.bundled) {
            if (bundledIndex.length === 0) {
                problems.push({ id: "", state: "invalid", reason: "the bundled apps index is missing" });
            }
        } else if (registryText.length > 0 && records.length === 0) {
            problems.push({ id: "", state: "invalid", reason: "apps.json is not readable JSON" });
        }
        const all = records;
        for (let index = 0; index < all.length; index++) {
            const record = all[index];
            if (!record || typeof record.id !== "string") {
                problems.push({ id: "", state: "invalid", reason: "apps.json has an entry without an id" });
                continue;
            }
            if (manifestText(record.id).length === 0) {
                problems.push({
                    id: record.id,
                    state: "invalid",
                    reason: "manifest.json is missing or unreadable"
                });
            }
        }
        return problems;
    }

    /// Is this app on? The same records the plan is built from, so a shell surface that
    /// represents an app can ask without a second parser or a second singleton.
    function isEnabled(appId) {
        const all = root.records;
        for (let index = 0; index < all.length; index++) {
            if (all[index] && all[index].id === appId) return all[index].enabled !== false;
        }
        return false;
    }

    function collectEntries() {
        const merged = [];
        const all = records;
        for (let index = 0; index < all.length; index++) {
            const record = all[index];
            if (!record || typeof record.id !== "string") {
                continue;
            }
            let manifest = null;
            try {
                manifest = JSON.parse(manifestText(record.id));
            } catch (error) {
                manifest = null;
            }
            if (!manifest || typeof manifest !== "object") {
                // Reported through `errors`; the host never sees a half-manifest.
                continue;
            }
            // Registry state wins over the manifest for the fields the daemon owns.
            manifest.enabled = record.enabled === undefined ? true : !!record.enabled;
            manifest.blocked = Array.isArray(record.blocked) ? record.blocked : [];
            manifest.pinned = !!record.pinned;
            manifest.payloadDir = root.payloadDir(manifest.id);
            merged.push(manifest);
        }
        return merged;
    }

    function base(dir) {
        return dir.charAt(dir.length - 1) === "/" ? dir : dir + "/";
    }

    function dirFor(id) {
        const all = bundledIndex;
        for (let index = 0; index < all.length; index++) {
            if (all[index].id === id) {
                return all[index].dir;
            }
        }
        return id;
    }

    function payloadDir(id) {
        if (root.bundled) {
            return base(bundledRoot) + dirFor(id) + "/";
        }
        return base(root.appsRoot) + id + "/payload/";
    }

    /// Manifest text for one app, read synchronously.
    ///
    /// One `FileView` per app, created on demand: a desktop with twenty apps reads
    /// twenty small files at boot, which is cheaper than keeping a file watcher per
    /// app on a path that only changes when the daemon installs something.
    function manifestText(id) {
        const view = manifestReaders[id];
        if (view) {
            return view.text();
        }
        const created = manifestFactory.createObject(root, {
            path: manifestPath(id)
        });
        if (!created) {
            return "";
        }
        manifestReaders[id] = created;
        return created.text();
    }

    function manifestPath(id) {
        if (root.bundled) {
            return base(bundledRoot) + dirFor(id) + "/manifest.json";
        }
        return base(root.appsRoot) + id + "/manifest.json";
    }

    property var manifestReaders: ({})
    property Component manifestFactory: FileView {
        blockLoading: true
        printErrors: false
    }

    property FileView indexReader: FileView {
        path: root.bundled ? base(root.bundledRoot) + "index.json" : ""
        blockLoading: true
        printErrors: false
    }

    property FileView registryReader: FileView {
        path: root.registryPath
        blockLoading: true
        printErrors: false
    }
}
