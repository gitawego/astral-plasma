import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"
import "../../services"
import "../../services/ClockZones.js" as ClockZones

// World Clock: the cities shown under the local time in the clock popout.
//
// Two cards, no decoration: the list you are editing and the local clock it is
// measured against. Your own time zone is the system's — the shell reads it and
// never overrides it — so the second card states it and hands the change to the
// system's own Date & Time settings.
SettingsPage {
    id: root

    title: "World Clock"
    subtitle: "Remote cities shown under your local time in the clock popout"
    zones: [
        { id: "cities", label: "Cities", anchor: citiesHeader },
        { id: "local", label: "Local clock", anchor: localHeader }
    ]

    property bool testMode: false

    /// How many search hits are drawn at once.
    readonly property int maxResults: 40

    // The page is a dumb view: everything it renders arrives through these
    // properties, so it stays loadable in the offscreen harness (which has no
    // Quickshell singletons) for the settings contract tests.
    readonly property bool hasTimeService: typeof ClockZoneService !== "undefined" && ClockZoneService !== null

    /// The OS time zone, read from /etc/localtime — the one the clocks follow.
    property string systemZone: hasTimeService ? ClockZoneService.systemZone : ""
    /// The live rows: every configured city with its wall clock as of now.
    property var rows: hasTimeService ? ClockZoneService.rows : []
    /// Every zone the OS ships.
    property var availableZones: hasTimeService ? ClockZoneService.allZones : []
    /// The configured cities, in order.
    property var clockZones: (typeof Config !== "undefined" && Config && Config.clockTimeZones)
        ? Config.clockTimeZones : []

    readonly property int clockZoneCount: ClockZones.normalize(root.clockZones).length
    readonly property int clockZoneMax: ClockZones.MAX_ZONES
    readonly property bool clockCanAdd: ClockZones.canAdd(root.clockZones)
    readonly property string localTime: hasTimeService ? ClockZoneService.localTime : ""
    readonly property string localAbbr: hasTimeService ? ClockZoneService.referenceAbbr : ""

    // The search covers the WHOLE catalog, not just what is missing: a city you
    // already have must still be findable (it is shown as added), otherwise
    // searching for it looks like the database has never heard of it.
    // Matching covers the zone id AND the tz database's own names, so "beijing"
    // reaches Asia/Shanghai (described as "Beijing Time") and "china" both CN zones.
    readonly property var clockMatches: matchZones(root.availableZones, clockSearch.text)

    function matchZones(list, query) {
        if (root.hasTimeService) return ClockZoneService.matches(list, query);
        return ClockZones.filterZones(list, query);
    }

    /// "Country · description" where the database has one, else the region.
    function zoneSubtitle(zone) {
        if (root.hasTimeService) return ClockZoneService.subtitle(zone);
        return ClockZones.regionFromZoneId(zone);
    }

    Component.onCompleted: {
        if (!root.hasTimeService) return;
        // Re-read both: the zone database can be updated, and the system zone can
        // be changed in the system settings while the shell keeps running.
        ClockZoneService.ensureZonesLoaded();
        ClockZoneService.refreshSystemZone();
        ClockZoneService.pageOpen = true;
    }

    Component.onDestruction: {
        if (root.hasTimeService) ClockZoneService.pageOpen = false;
    }

    // =========================================================================
    // Cities
    // =========================================================================
    SectionHeader {
        id: citiesHeader
        title: "Cities"
        eyebrow: root.clockZoneCount + " of " + root.clockZoneMax
    }

    Item { height: Theme.spaceSmall }

    // One card per city, with the hub's own spacing between them: a run of
    // touching rows reads as a single block, which is what made this look like a
    // wall of text rather than a list of things you own.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSmall

        Repeater {
            model: root.rows

            delegate: CityCard {
                required property var modelData
                Layout.fillWidth: true
                zone: modelData
                onRemoveRequested: id => root.removeZone(id)
            }
        }
    }

    // The adder is its own card, so adding reads as a separate act from the list.
    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        implicitHeight: addCol.implicitHeight + Theme.padLarge * 2

        ColumnLayout {
            id: addCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            spacing: Theme.spaceSmall

            Text {
                Layout.fillWidth: true
                visible: root.clockZoneCount === 0
                wrapMode: Text.WordWrap
                text: "No cities yet — add one below."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurfaceVariant
            }

            ZoneSearchField {
                id: clockSearch
                Layout.fillWidth: true
                placeholder: "Add a city — search Beijing, Japan, America/…"
            }

            ZoneResults {
                Layout.fillWidth: true
                query: clockSearch.text
                model: root.clockMatches
                total: root.availableZones.length
                chosen: root.clockZones
                enabled: root.clockCanAdd
                emptyText: "Nothing matches that search."
                fullText: "All " + root.clockZoneMax + " slots are taken — remove a city first."
                onPicked: id => root.addZone(id)
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: !root.clockCanAdd && root.clockZoneCount > 0
        text: "All " + root.clockZoneMax + " slots are taken — remove a city to add another."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontLabelSmall
        color: Colors.m3onSurfaceVariant
    }

    Item { height: Theme.spaceMedium }

    // =========================================================================
    // The local clock the cities are measured against
    // =========================================================================
    SectionHeader {
        id: localHeader
        title: "Your Local Clock"
        eyebrow: root.systemZone.length > 0 ? root.systemZone : "detecting…"
    }

    Item { height: Theme.spaceSmall }

    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        implicitHeight: localRow.implicitHeight + Theme.padLarge * 2

        RowLayout {
            id: localRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            spacing: Theme.spaceMedium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: root.localTime + (root.localAbbr.length > 0 ? "  ·  " + root.localAbbr : "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "The reference for every city above. It is the system time zone; "
                        + "the shell reads it and never overrides it."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                }
            }

            PillButton {
                label: "Date & Time settings…"
                variant: "outlined"
                onClicked: root.openSystemTimeSettings()
            }
        }
    }

    Item { Layout.fillHeight: true }

    // --- behaviour (one write path each, so tests can call them) -------------
    function addZone(id) {
        if (testMode) return;
        if (typeof Config !== "undefined" && Config.addClockTimeZone) Config.addClockTimeZone(id);
    }

    function removeZone(id) {
        if (testMode) return;
        if (typeof Config !== "undefined" && Config.removeClockTimeZone) Config.removeClockTimeZone(id);
    }

    /** Hand the system time zone to the system's own settings dialog. */
    function openSystemTimeSettings() {
        if (!root.hasTimeService) return;
        ClockZoneService.openSystemTimeSettings();
    }

    // =========================================================================
    // Local components
    // =========================================================================
    // One city, at settings scale: name and where it is on the left, its wall
    // clock — the reason the row exists — on the right, and a quiet remove that
    // is always faintly present rather than hover-only.
    component CityCard: Rectangle {
        id: cityRow
        required property var zone
        signal removeRequested(string id)

        Layout.fillWidth: true
        implicitHeight: 56
        radius: Theme.radiusMedium
        color: cityHover.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer

        Behavior on color { ColorAnimation { duration: Theme.animDurationFast } }

        HoverHandler { id: cityHover }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            spacing: Theme.spaceMedium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: cityRow.zone.city
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: (cityRow.zone.abbr ? cityRow.zone.abbr + " · " : "")
                            + cityRow.zone.offsetLabel + "  ·  " + cityRow.zone.subtitle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: cityRow.zone.dayWord !== ""
                        text: cityRow.zone.dayWord
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        font.weight: Font.DemiBold
                        color: Colors.primary
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: cityRow.zone.time
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleSmall
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
            }

            Item {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                opacity: (cityHover.hovered || removeMouse.containsMouse) ? 1.0 : 0.45
                Behavior on opacity { NumberAnimation { duration: Theme.animDurationFast } }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "close"
                    size: 15
                    color: removeMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: removeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cityRow.removeRequested(cityRow.zone.id)
                }
            }
        }
    }

    // The search input mirrors FolderPathField's field: a surfaceContainer
    // rectangle, subtle border, focus ring in the accent, TextInput on the theme
    // font. No QtQuick.Controls — its style would override the theme typography.
    component ZoneSearchField: Rectangle {
        id: field
        property string placeholder: ""
        property alias text: input.text
        /// Introspection surface for tests.
        property alias input: input

        implicitHeight: 38
        radius: Theme.radiusMedium
        color: Colors.surfaceContainerHigh
        border.width: 1
        border.color: input.activeFocus ? Colors.primary : Theme.borderSubtle

        MaterialIcon {
            id: leadingIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.padMedium
            anchors.verticalCenter: parent.verticalCenter
            text: "search"
            size: 16
            color: Colors.m3onSurfaceVariant
        }

        TextInput {
            id: input
            anchors.left: leadingIcon.right
            anchors.leftMargin: Theme.spaceSmall
            anchors.right: parent.right
            anchors.rightMargin: Theme.padMedium
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBodySmall
            color: Colors.m3onSurface
            selectionColor: Colors.primary
            selectedTextColor: Colors.textOnPrimary
            selectByMouse: true
            clip: true
            verticalAlignment: TextInput.AlignVCenter

            Text {
                anchors.fill: parent
                visible: input.text.length === 0 && !input.activeFocus
                text: field.placeholder
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodySmall
                color: Colors.m3onSurfaceVariant
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    // Search hits: the shell's list-row archetype, clamped and scrollable so a
    // long result set never pushes the card around.
    component ZoneResults: Flickable {
        id: results
        property string query: ""
        property var model: []
        property int total: 0
        property var chosen: []
        property string emptyText: "No match."
        property string fullText: ""
        property bool enabled: true
        signal picked(string id)

        readonly property var shown: model.slice(0, root.maxResults)
        readonly property bool open: query.trim() !== ""

        implicitHeight: open ? Math.min(content.implicitHeight + 8, 216) : 0
        contentHeight: content.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: contentHeight > height
        visible: open

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMedium
            color: Colors.surfaceContainerHigh
            border.color: Theme.borderSubtle
            border.width: 1
            z: -1
        }

        Column {
            id: content
            x: Theme.padSmall / 2
            y: 4
            width: results.width - Theme.padSmall
            spacing: 0

            Text {
                width: content.width
                visible: !results.enabled
                text: results.fullText
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurfaceVariant
                leftPadding: Theme.padSmall
                topPadding: Theme.spaceSmall
                bottomPadding: Theme.spaceSmall
            }

            Repeater {
                model: results.shown

                delegate: ActionToggleItem {
                    required property var modelData
                    readonly property bool already: results.chosen.indexOf(modelData) !== -1

                    width: content.width
                    icon: already ? "check" : "public"
                    iconColor: already ? Colors.primary : Colors.m3onSurfaceVariant
                    label: ClockZones.cityFromZoneId(modelData) + " — " + root.zoneSubtitle(modelData)
                    checked: already
                    // An added city stays listed but is inert: nothing to add twice.
                    enabled: results.enabled && !already
                    onToggled: results.picked(modelData)
                }
            }

            Text {
                width: content.width
                visible: results.shown.length === 0
                text: results.emptyText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurfaceVariant
                leftPadding: Theme.padSmall
                topPadding: Theme.spaceSmall
                bottomPadding: Theme.spaceSmall
            }

            Text {
                width: content.width
                visible: results.model.length > results.shown.length
                text: "Showing " + results.shown.length + " of " + results.model.length
                    + " matches — keep typing to narrow it down."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurfaceVariant
                leftPadding: Theme.padSmall
                bottomPadding: Theme.spaceSmall
            }
        }
    }
}
