// ============================================================================
// Settings page scaffold
// ============================================================================
// A page has one identity and one of two shapes:
//   * **sections** (the default): a vertical stack. `zones` names the section
//     anchors so a deep link can scroll to one; no in-page navigation strip is
//     drawn. Most settings pages are short enough to read by scrolling.
//   * **tabs**: only for a page whose content genuinely runs several viewports.
//     Tabs switch the body; they never scroll the reader to an anchor.
//     SettingsPage {
//         title: "AI & Agents"
//         icon: "psychology"
//         tabs: [
//             { id: "quotas", label: "Quotas", icon: "performance" },
//             { id: "copilot", label: "Copilot", icon: "psychology" }
//         ]
//         property string currentTab: "quotas"
//     }

import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/theme"
import "../controls"
import QtQuick
import QtQuick.Layouts

// A page whose tabs have no `component` (Skills) keeps one body and reacts to
// `currentTab` itself; this is for a page that already owns a single stateful
// surface and only needs the tab strip.
ColumnLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    /// Material Symbols name for the page identity.
    property string icon: ""
    /// `[{ id, label, icon, component? }]`.
    property var tabs: []
    /// The active tab id. Pages with stateful content bind to this.
    property string currentTab: ""
    /// Section anchors for a vertical page: `[{ id, label, anchor }]`. The hub
    /// scrolls a deep link to one; the page draws no rail for them.
    property var zones: []
    /// The section the hub's scroll-spy reports as current.
    property string currentSection: ""
    readonly property bool hasTabs: root.tabs.length > 0
    readonly property bool hasTabComponents: root.hasTabs && root.tabs.some(function(tab) {
        return tab && tab.component !== undefined && tab.component !== null;
    })
    readonly property var activeTab: {
        for (let index = 0; index < root.tabs.length; ++index) {
            if (root.tabs[index] && root.tabs[index].id === root.currentTab)
                return root.tabs[index];

        }
        return root.tabs.length > 0 ? root.tabs[0] : null;
    }
    /// Introspection for the active tab body.
    readonly property var tabContentItem: tabLoader.item
    /// The page header, rendered by the hub above the scroll area.
    property Component stickyHeader

    function selectTab(tabId) {
        if (!tabId)
            return ;

        for (let index = 0; index < root.tabs.length; ++index) {
            if (root.tabs[index] && root.tabs[index].id === tabId) {
                root.currentTab = tabId;
                return ;
            }
        }
    }

    /// A page may compute its tab list from live state. If the active tab
    /// disappears, the body would have no `currentTab` to show; fall back to the
    /// first tab that still exists.
    function ensureCurrentTab() {
        if (!root.hasTabs)
            return ;

        for (let index = 0; index < root.tabs.length; ++index) {
            if (root.tabs[index] && root.tabs[index].id === root.currentTab)
                return ;

        }
        root.currentTab = root.tabs[0].id;
    }

    /// Is this section the one the hub's scroll-spy reports? Section pages may
    /// use it to refine the active card; there is no rail to highlight.
    function isZoneCurrent(zoneId) {
        return root.currentSection === zoneId;
    }

    function sectionY(name) {
        for (let i = 0; i < root.zones.length; ++i) {
            const zone = root.zones[i];
            if (zone && zone.id === name && zone.anchor)
                return zone.anchor.mapToItem(root, 0, 0).y;

        }
        return undefined;
    }

    onTabsChanged: root.ensureCurrentTab()
    Component.onCompleted: root.ensureCurrentTab()

    // A tabs page has no direct visual children: its tabs own the content.
    Loader {
        id: tabLoader

        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.hasTabComponents
        sourceComponent: root.activeTab && root.activeTab.component ? root.activeTab.component : null
    }

    stickyHeader: Component {
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                Rectangle {
                    visible: root.icon !== ""
                    width: 38
                    height: 38
                    radius: Theme.radiusSmall
                    color: Qt.alpha(Colors.primary, 0.14)
                    border.width: 1
                    border.color: Qt.alpha(Colors.primary, 0.24)

                    MaterialIcon {
                        anchors.centerIn: parent
                        iconName: root.icon
                        size: 20
                        color: Colors.primary
                    }

                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        visible: root.title !== ""
                        text: root.title
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontTitleLarge
                        font.weight: Font.Bold
                        color: Colors.m3onSurface
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.subtitle !== ""
                        wrapMode: Text.WordWrap
                        text: root.subtitle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Colors.m3onSurfaceVariant
                    }

                }

            }

            // Atlas tabs: icon + label, one accent underline, no scroll pills.
            SettingsTabBar {
                Layout.fillWidth: true
                visible: root.hasTabs
                tabs: root.tabs
                currentTab: root.currentTab
                onSelected: (tabId) => {
                    return root.selectTab(tabId);
                }
            }

        }

    }

}
