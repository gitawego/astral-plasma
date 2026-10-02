.pragma library

// ============================================================================
// Dashboard tab policy
// ============================================================================
// Which tabs the central dashboard renders is a setting, and one tab has a hard
// dependency: the Downloads tab cannot do anything without the aria2 engine. The
// policy lives here - pure functions, no QML types - so the dashboard, the
// settings page and the tests all decide the same way.
//
// The engine-dependent tab is named once, in ARIA_TAB_ID: adding another
// dependent tab means adding it here (and nowhere else).

/// The tab that needs the download engine.
var ARIA_TAB_ID = "downloads";

/// Shipped order and chrome of the dashboard tabs.
///
/// Used when the settings document has no list at all (an older file, a
/// hand-written one): the tabs the dashboard has always shown.
var DEFAULT_TABS = [
    { id: "dashboard", label: "Dashboard", icon: "dashboard" },
    { id: "media", label: "Media", icon: "media" },
    { id: "performance", label: "Performance", icon: "performance" },
    { id: "workspaces", label: "Workspaces", icon: "workspaces" },
    { id: "downloads", label: "Downloads", icon: "download" },
    { id: "ai", label: "AI Quotas", icon: "auto_awesome" }
];

/// Tabs whose setting is not explicitly off.
///
/// A missing `enabled` flag means on: a settings file written before tabs were
/// configurable must not end up with a hidden dashboard.
function enabledTabs(tabs) {
    if (!tabs || !Array.isArray(tabs)) {
        return DEFAULT_TABS.slice();
    }
    return tabs.filter(function (tab) {
        return !!tab && tab.id && tab.enabled !== false;
    });
}

/// Tabs the dashboard can actually render.
///
/// The download tab is dropped while the engine is missing, whatever the setting
/// says: an unreachable tab that only ever shows an install banner is worse than
/// a tab the user can turn on once they installed the engine.
function availableTabs(tabs, ariaAvailable) {
    if (!tabs || !Array.isArray(tabs)) {
        tabs = DEFAULT_TABS;
    }
    if (ariaAvailable) {
        return tabs.slice();
    }
    return tabs.filter(function (tab) {
        return !!tab && tab.id !== ARIA_TAB_ID;
    });
}

/// Why a tab cannot be switched on here, or `null` when it can.
///
/// A machine-readable reason ("aria-missing"), not a sentence: the settings page
/// owns the wording and the actions (install now, or copy the command).
function enableBlockedReason(tabId, ariaAvailable) {
    if (tabId === ARIA_TAB_ID && !ariaAvailable) {
        return "aria-missing";
    }
    return null;
}

/// The tab to show for a configured `activeId`.
///
/// The selected tab can vanish underneath the user - they disabled it, or the
/// engine disappeared - and a view left pointing at a tab it does not render
/// shows content with no way back to it.
function fallbackActiveTab(tabs, activeId) {
    if (tabs && Array.isArray(tabs)) {
        for (var i = 0; i < tabs.length; ++i) {
            if (tabs[i] && tabs[i].id === activeId) {
                return activeId;
            }
        }
        if (tabs.length > 0 && tabs[0] && tabs[0].id) {
            return tabs[0].id;
        }
    }
    return "dashboard";
}

/// Reconcile a stored tab list with the one this build ships.
///
/// The settings merge replaces arrays wholesale, so a user file written before a
/// tab existed would *never* grow it: the dashboard would keep the old set, and
/// a tab added later could not be enabled because its toggle never appears. The
/// user's own order and on/off choices win; entries this build does not know are
/// kept as they are; tabs the build added are appended with the shipped default.
function reconcileTabs(stored, shipped) {
    const shippedList = (shipped && Array.isArray(shipped)) ? shipped : DEFAULT_TABS;
    if (!stored || !Array.isArray(stored) || stored.length === 0) {
        return shippedList.slice();
    }

    const result = [];
    const seen = {};
    stored.forEach(function (tab) {
        if (!tab || !tab.id) {
            return;
        }
        const fresh = shippedList.filter(function (s) { return s.id === tab.id; })[0];
        result.push({
            id: tab.id,
            label: tab.label || (fresh ? fresh.label : tab.id),
            icon: tab.icon || (fresh ? fresh.icon : undefined),
            enabled: tab.enabled !== false
        });
        seen[tab.id] = true;
    });

    shippedList.forEach(function (tab) {
        if (seen[tab.id]) {
            return;
        }
        result.push({
            id: tab.id,
            label: tab.label,
            icon: tab.icon,
            enabled: tab.enabled !== false
        });
    });

    return result;
}
