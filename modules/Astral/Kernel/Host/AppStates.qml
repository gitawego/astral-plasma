pragma Singleton

import QtQuick

// ============================================================================
// AppStates — "is this app on?", for shell surfaces that represent an app
// ============================================================================
// `AppRegistry` decides what the host mounts, but some surfaces are the shell's own: the
// dock's AI pill, a drawer that belongs to an app, a shortcut. Those have no host to ask,
// and they used to ignore the registry entirely — disabling the AI Quotas app left its pill
// on the dock and its drawer still opening (reported as "the disable of an app does
// nothing").
//
// This singleton is the narrow read model for that question. It holds no file handle: the
// shell feeds it from the registry (`AppRegistry.records`, the same records the load plan is
// built from), because a kernel singleton must stay importable by the offscreen test runner,
// which has no Quickshell plugin (spec C.14).
QtObject {
    id: root

    /// `[{ id, enabled, … }]`, as the registry describes them.
    property var entries: []

    /// Bumped on every change, so a `Connections` block reacts without polling.
    property int revision: 0

    readonly property var byId: {
        const index = ({});
        const list = root.entries || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] && typeof list[i].id === "string") index[list[i].id] = list[i];
        }
        return index;
    }

    /// Ids the user disabled, in registry order.
    readonly property var disabled: {
        const ids = [];
        const list = root.entries || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] && typeof list[i].id === "string" && list[i].enabled === false) ids.push(list[i].id);
        }
        return ids;
    }

    /// True unless the user disabled this app. An unknown id is enabled: the platform's
    /// default for a bundled app with no record yet.
    function isEnabled(appId) {
        const entry = root.byId[String(appId)];
        if (!entry) return true;
        return entry.enabled !== false;
    }

    /// Called by the shell whenever the registry changes.
    function adopt(newEntries) {
        root.entries = Array.isArray(newEntries) ? newEntries : [];
        root.revision++;
    }
}
