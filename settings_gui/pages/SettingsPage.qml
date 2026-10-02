import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"

// ============================================================================
// Settings page scaffold
// ============================================================================
// The settings hub pins a page's identity above the scroll area and highlights the
// zone the reader is in. A page opts in by making this scaffold its root:
//
//     SettingsPage {
//         title: "Network"
//         subtitle: "Interfaces, addresses, and per-network preferences"
//         zones: [
//             { id: "status",  label: "Status",  anchor: statusHeader },
//             { id: "wifi",    label: "Wi-Fi",    anchor: wifiHeader }
//         ]
//
//         ColumnLayout { …the page body… }
//     }
//
// `anchor` is any item in the page (usually a `SectionHeader`). The scaffold maps
// every anchor into page coordinates, so a page never hand-writes a `sectionY()`
// switch, and it builds the sticky header - title, subtitle and the state/zone
// rail - from the same declaration. Fewer than two zones means no rail: a single
// pill is decoration, not navigation.
//
// Pages whose root cannot be a layout (they host absolutely positioned overlays)
// keep their own root and forward six members; see `AiPage.qml`.
ColumnLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    /// `[{ id, label, anchor }]` in document order.
    property var zones: []
    /// The zone the hub's scroll-spy reports as current.
    property string currentSection: ""

    readonly property bool hasRail: root.zones.length >= 2

    /// A rail pill was pressed: ask the host to bring that zone into view.
    ///
    /// The page does not scroll itself - it cannot, the scroll area, its bounds
    /// and its motion belong to the settings hub - and it does not reach for a
    /// global to say so either. Writing `Config.settingsSection` from here was
    /// how the rail went dead: `Config` is not imported by this file, so a
    /// `typeof`-guarded write to it was a silent no-op (an unimported singleton
    /// is simply not in a component's scope). A signal cannot be silently
    /// ignored: the host either handles it or the test fails.
    signal zoneRequested(string zoneId)

    /// Is this zone the one the reader is in? One rule, shared by every page.
    function isZoneCurrent(zoneId) {
        return root.currentSection === zoneId;
    }

    /// Ask the hub to bring a zone into view (it scrolls smoothly).
    function jumpToZone(zoneId) {
        root.zoneRequested(zoneId);
    }

    /// Anchor of a zone in page coordinates - the hub's scroll target.
    function sectionY(name) {
        for (let i = 0; i < root.zones.length; ++i) {
            const zone = root.zones[i];
            if (zone && zone.id === name && zone.anchor) {
                return zone.anchor.mapToItem(root, 0, 0).y;
            }
        }
        return undefined;
    }

    /// The hub renders this above the flickable, so the header never scrolls away.
    property Component stickyHeader: Component {
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSmall

            Text {
                Layout.fillWidth: true
                visible: root.title !== ""
                text: root.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleLarge
                font.weight: Font.Bold
                color: Colors.m3onSurface
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

            Flow {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall
                visible: root.hasRail

                Repeater {
                    model: root.hasRail ? root.zones : []

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
}
