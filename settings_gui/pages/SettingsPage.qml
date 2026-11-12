// ============================================================================
// Settings page scaffold — Atlas
// ============================================================================
// A page has one identity and, when it has more than one part, a tab bar. Tabs
// switch content; they never scroll the reader to an anchor. The old `zones`
// rail is kept only as a compatibility path for a page that has not been
// migrated yet.
//     SettingsPage {
//         title: "Dock & Layout"
//         icon: "dashboard"
//         tabs: [
//             { id: "dock", label: "Dock", icon: "dashboard", component: dockTab },
//             { id: "tray", label: "Tray", icon: "tray", component: trayTab }
//         ]
//         property Component dockTab: Component { ColumnLayout { … } }
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
    /// Legacy: `[{ id, label, anchor }]` for a page not migrated to tabs.
    property var zones: []
    /// The legacy scroll-spy value.
    property string currentSection: ""
    readonly property bool hasTabs: root.tabs.length > 0
    /// Legacy: the old zone rail. Kept so an unmigrated page still works.
    readonly property bool hasRail: !root.hasTabs && root.zones.length >= 2
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

            // Legacy zone rail, only for a page not migrated yet.
            Flow {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall
                visible: !root.hasTabs && root.zones.length >= 2

                Repeater {
                    model: !root.hasTabs && root.zones.length >= 2 ? root.zones : []

                    delegate: PillButton {
                        required property var modelData

                        label: modelData.label
                        active: root.isZoneCurrent(modelData.id)
                        onClicked: root.jumpToZone(modelData.id)
                    }

                }

            }

        }

    }

    /// Legacy zone navigation, kept for a page that still declares `zones`.
    signal zoneRequested(string zoneId)

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

    /// A tab can disappear with the state it described (Wi-Fi off, no app
    /// streams). The body is chosen by `currentTab`, so an invalid id would show
    /// nothing at all; fall back to the first tab that still exists.
    function ensureCurrentTab() {
        if (!root.hasTabs)
            return ;

        for (let index = 0; index < root.tabs.length; ++index) {
            if (root.tabs[index] && root.tabs[index].id === root.currentTab)
                return ;

        }
        root.currentTab = root.tabs[0].id;
    }

    function isZoneCurrent(zoneId) {
        return root.currentSection === zoneId;
    }

    function jumpToZone(zoneId) {
        root.zoneRequested(zoneId);
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
    // A migrated page has no direct visual children: its tabs own the content.
    Loader {
        id: tabLoader

        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.hasTabComponents
        sourceComponent: root.activeTab && root.activeTab.component ? root.activeTab.component : null
    }

}
