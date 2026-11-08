import QtQuick
import "./AppHostPolicy.js" as Policy
import "./AppManifest.js" as Manifest

// ============================================================================
// AppHost — instantiate what the policy allows, and nothing else
// ============================================================================
// Deliberately plain QtQuick: no Quickshell import, no file I/O. The host receives
// already-loaded registry entries (identity, version, API window, entry root,
// payload directory) and:
//
//   1. validates each entry as a manifest (`AppManifest.validate`),
//   2. asks `AppHostPolicy.plan` what is loadable and in what order,
//   3. keeps one `Loader` per loadable app, **inactive**: a `Loader` that is never
//      activated costs a URL, not a component tree (P0 measured 11 inactive apps at
//      +1 ms, 11 instantiated at +65 ms),
//   4. activates on demand — `activate(id)` — and turns any failure into a
//      reported skip instead of an exception that reaches the shell.
//
// Nothing in this file may throw: a corrupt manifest, a missing payload, or QML
// that fails to compile are all data the host reports, not errors it propagates.
Item {
    id: root

    /// Registry entries: `{ id, version, kernelApi, enabled, blocked, requires,
    /// payloadDir, entry: { root } }`. Missing fields are refused, not guessed.
    property var entries: []

    /// The running platform's API window, e.g. `{ level: 1, floor: 1 }`.
    property var host: ({ level: 1, floor: 1 })

    /// Ids to activate at boot: the surfaces the shell owns and shows/hides itself
    /// (the overview). Everything else stays inactive until a surface asks for it,
    /// so startup does not grow with the installed app count.
    property var eager: []

    /// Shell-owned read model injected into every app instance (`ShellState`).
    property var state: null
    /// The intent bus apps use for actions (`IntentBus`).
    property var intents: null
    /// The window model (`SessionPort`), injected for surfaces that show windows.
    property var session: null
    /// The now-playing model (`MediaPort`), injected for media surfaces.
    property var media: null
    /// Desktops (`WorkspacesPort`), injected for workspace surfaces.
    property var workspaces: null
    /// Machine telemetry (`MetricsPort`), injected for performance surfaces.
    property var metrics: null

    /// Loadable entries, in dependency order.
    readonly property var loaded: plan.load
    /// `[{ id, state, reason }]` for everything that did not load.
    readonly property var skipped: plan.skipped
    /// Ids in load order (logs, assertions, the Apps page).
    readonly property var loadedIds: plan.load.map(function (entry) { return entry.id; })

    /// `tabId -> appId` for apps that declare `entry.dashboardTab`. The dashboard
    /// renders what the registry offers instead of a switch over known features.
    readonly property var tabProviders: collectTabProviders()

    signal appFailed(string id, string reason)
    signal appLoaded(string id)

    readonly property var plan: build()
    property var loaders: ({})
    /// Number of loaders registered. The plan (`loaded`) can update before the
    /// `Repeater` has created its delegates; a pane that mounts on `loadedIdschanged`
    /// alone can arrive one signal too early.
    readonly property int loaderCount: Object.keys(loaders).length
    /// Ids already reported through `appFailed`, so a loader error that surfaces
    /// twice (status change + activation) is not reported twice.
    property var reported: ({})

    function build() {
        const accepted = [];
        const rejected = [];
        const all = entries || [];
        for (let index = 0; index < all.length; index++) {
            const entry = all[index];
            const verdict = Manifest.validate(entry);
            if (verdict.ok && entry.runtime === "hosted") {
                // A hosted app is a separate process, not an item in this scene
                // graph. Not an error: it is simply not this host's job.
                rejected.push({
                    id: entry.id,
                    state: "hosted",
                    reason: "run as its own process, not embedded in the shell"
                });
            } else if (verdict.ok) {
                accepted.push(entry);
            } else {
                const id = (entry && typeof entry.id === "string") ? entry.id : "";
                rejected.push({ id: id, state: verdict.state, reason: verdict.reason });
            }
        }
        const decided = Policy.plan(accepted, host);
        // Validator refusals lead: "this manifest is corrupt" is the more
        // actionable line than "this app is disabled".
        return { load: decided.load, skipped: rejected.concat(decided.skipped) };
    }

    function collectTabProviders() {
        const providers = ({});
        const planned = loaded;
        for (let index = 0; index < planned.length; index++) {
            const entry = planned[index];
            const tab = entry.entry ? entry.entry.dashboardTab : "";
            if (typeof tab === "string" && tab.length > 0) {
                providers[tab] = entry.id;
            }
        }
        return providers;
    }

    /// The app id that provides `tabId`, or "" when no installed app does.
    function providerForTab(tabId) {
        return tabProviders[tabId] || "";
    }

    function sourceFor(entry) {
        const dir = entry && entry.payloadDir ? String(entry.payloadDir) : "";
        const rel = entry && entry.entry && entry.entry.root ? String(entry.entry.root) : "";
        if (!dir || !rel) {
            return "";
        }
        const base = dir.charAt(dir.length - 1) === "/" ? dir : dir + "/";
        return base + rel;
    }

    function reasonFor(id) {
        const all = skipped;
        for (let index = 0; index < all.length; index++) {
            if (all[index].id === id) {
                return all[index];
            }
        }
        return null;
    }

    function loaderFor(id) {
        return loaders[id] || null;
    }

    /// Hand the shell's state and bus to an instantiated app.
    ///
    /// Assignment is attempted, not required: an app that declares neither property
    /// is still valid (it may be pure presentation), so a missing property is not an
    /// error - a TypeError here would be. This is the only injection point, so the
    /// contract is one place: `property var shellState`, `property var intents`,
    /// `property var session`, `property var media`, `property var workspaces`.
    function inject(item) {
        if (!item) {
            return;
        }
        try {
            item.shellState = root.state;
        } catch (error) {
            // The app does not take a state object: fine.
        }
        try {
            item.intents = root.intents;
        } catch (error) {
            // The app does not take an intent bus: fine.
        }
        try {
            item.session = root.session;
        } catch (error) {
            // The app does not read the session: fine.
        }
        try {
            item.media = root.media;
        } catch (error) {
            // The app does not read media: fine.
        }
        try {
            item.workspaces = root.workspaces;
        } catch (error) {
            // The app does not read desktops: fine.
        }
        try {
            item.metrics = root.metrics;
        } catch (error) {
            // The app does not read telemetry: fine.
        }
    }

    /// The instantiated item for an app, or null when it is not active.
    function itemFor(id) {
        const loader = loaderFor(id);
        return loader ? loader.item : null;
    }

    /// Instantiate an app and parent it into `parentItem` — the way a host-owned
    /// surface (a dashboard pane) embeds an app's item without owning its code.
    ///
    /// Returns the item, or null (with `appFailed` emitted). Mounting twice moves the
    /// same item rather than creating a second instance.
    function mount(appId, parentItem) {
        const item = activate(appId);
        if (!item || !parentItem) {
            return item;
        }
        if (item.parent !== parentItem) {
            item.parent = parentItem;
        }
        item.anchors.fill = parentItem;
        return item;
    }

    function reportFailure(id, reason) {
        if (reported[id]) {
            return;
        }
        reported[id] = true;
        root.appFailed(id, reason);
    }

    /// Instantiate one app. Returns the item, or null (with `appFailed` emitted).
    ///
    /// A surface calls this when it actually needs the app; nothing is instantiated
    /// at boot, so the shell's startup cost does not grow with the number of
    /// installed apps.
    function activate(id) {
        const loader = loaderFor(id);
        if (!loader) {
            reportFailure(id, "not in the load plan");
            return null;
        }
        if (loader.status === Loader.Error) {
            reportFailure(id, "failed to load " + loader.source);
            return null;
        }
        loader.active = true;
        if (loader.status === Loader.Error) {
            reportFailure(id, "failed to load " + loader.source);
            return null;
        }
        if (loader.status === Loader.Ready) {
            inject(loader.item);
            root.appLoaded(id);
            return loader.item;
        }
        // Asynchronous or not ready yet: the surface waits for `appLoaded`.
        return loader.item;
    }

    Component.onCompleted: {
        const ids = root.eager || [];
        for (let index = 0; index < ids.length; index++) {
            root.activate(ids[index]);
        }
    }

    Repeater {
        model: root.loaded

        delegate: Loader {
            id: appLoader
            active: false
            asynchronous: false
            source: root.sourceFor(modelData)

            onStatusChanged: {
                if (status === Loader.Error) {
                    root.reportFailure(modelData.id, "failed to load " + source);
                } else if (status === Loader.Ready) {
                    root.inject(item);
                }
            }

            Component.onCompleted: {
                // A *copy*: assigning the same object back would not notify, and a pane
                // waiting for `loaderCount` would wait forever (that is exactly how the
                // workspaces pane ended up never mounting).
                const map = Object.assign({}, root.loaders);
                map[modelData.id] = appLoader;
                root.loaders = map;
            }
        }
    }
}
