import QtQuick
import Quickshell
import Quickshell.Io

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

    /// `~/.local/share/astral-plasma/apps.json` (or the package's, for a preview).
    property string registryPath: ""
    /// Directory holding `<id>/manifest.json` + payloads.
    property string appsRoot: ""

    /// `[{ id, state, reason }]` for problems found while reading.
    readonly property var errors: collectErrors()
    /// Merged entries, ready for `AppHost.entries`.
    readonly property var entries: collectEntries()

    readonly property string registryText: registryReader.text()

    readonly property var records: {
        try {
            const parsed = JSON.parse(root.registryText);
            return (parsed && Array.isArray(parsed.apps)) ? parsed.apps : [];
        } catch (error) {
            return [];
        }
    }

    function collectErrors() {
        const problems = [];
        if (registryText.length > 0 && records.length === 0) {
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

    function payloadDir(id) {
        const base = root.appsRoot.charAt(root.appsRoot.length - 1) === "/"
            ? root.appsRoot : root.appsRoot + "/";
        return base + id + "/payload/";
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
        const base = root.appsRoot.charAt(root.appsRoot.length - 1) === "/"
            ? root.appsRoot : root.appsRoot + "/";
        return base + id + "/manifest.json";
    }

    property var manifestReaders: ({})
    property Component manifestFactory: FileView {
        blockLoading: true
        printErrors: false
    }

    property FileView registryReader: FileView {
        path: root.registryPath
        blockLoading: true
        printErrors: false
    }
}
