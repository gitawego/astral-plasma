pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "ClockZones.js" as ClockZones

// Time-zone service for the shell's clocks.
//
// Three jobs, all cheap:
//   * know the OS time zone (read, never guessed) and the user's chosen zone
//   * enumerate the real /usr/share/zoneinfo set on demand (no hard-coded list)
//   * probe UTC offsets in ONE batched `date` call, only while a clock is shown
Singleton {
    id: root

    // --- Your time zone -------------------------------------------------
    /// The zone the OS is set to (from /etc/localtime), never hard-coded.
    property string systemZone: ""
    /// The zone the clocks display: always the system's. The shell reads it and
    /// never overrides it, so the world clock is measured against what the machine
    /// actually runs on.
    readonly property string referenceZone: root.systemZone

    property int systemOffsetMinutes: 0
    property int referenceOffsetMinutes: 0
    property string referenceAbbr: ""
    /// How far the chosen zone is from the OS clock; the shell shifts by this.
    readonly property int referenceDeltaMinutes: root.referenceOffsetMinutes - root.systemOffsetMinutes

/** A Date whose wall clock is the reference ("your") time. */
    function clockDate(base) {
        return ClockZones.shiftDate(base || new Date(), root.referenceDeltaMinutes);
    }

    // --- The city catalog (real tz database, loaded on demand) -----------
    property var allZones: []
    property bool zonesLoaded: false
    /// zone id -> { country, comment } from zone.tab, and code -> country name.
    property var zoneDescriptions: ({})
    property var countryNames: ({})

    Process {
        id: zoneListProc
        stdout: StdioCollector {
            onStreamFinished: {
                // One read carries the zone list plus the database's own names,
                // which is how "beijing" can reach Asia/Shanghai.
                const sources = ClockZones.parseZoneSources(this.text);
                root.allZones = sources.zones;
                root.zoneDescriptions = ClockZones.parseZoneDescriptions(sources.zoneTab);
                root.countryNames = ClockZones.parseCountryNames(sources.iso3166);
                root.zonesLoaded = true;
            }
        }
    }

    Process {
        id: systemZoneProc
        stdout: StdioCollector {
            onStreamFinished: {
                var zone = ClockZones.systemZoneFromLink(this.text);
                if (zone.indexOf("/") === -1 && this.text.trim().indexOf("/") !== -1) zone = ClockZones.systemZoneFromLink(this.text);
                root.systemZone = zone;
                if (root.active) root.refresh();
            }
        }
    }

/** Enumerate the tz database once; call from a settings page that needs it. */
    function ensureZonesLoaded() {
        if (root.zonesLoaded || zoneListProc.running) return;
        // -type l too: several zones (UTC, GMT, ...) ship as symlinks. zone.tab
        // and iso3166.tab are appended after markers: they are not zones, but they
        // carry the names people actually search for.
        zoneListProc.command = ["sh", "-c",
            "find /usr/share/zoneinfo -type f -o -type l 2>/dev/null; "
            + "echo '" + ClockZones.ZONE_TAB_MARK + "'; cat /usr/share/zoneinfo/zone.tab 2>/dev/null; "
            + "echo '" + ClockZones.ISO_MARK + "'; cat /usr/share/zoneinfo/iso3166.tab 2>/dev/null"];
        zoneListProc.running = true;
    }

    function ensureSystemZone() {
        if (root.systemZone.length > 0 || systemZoneProc.running) return;
        root.refreshSystemZone();
    }

    /** Re-read /etc/localtime. The system zone can change while the shell runs
     *  (KDE's Date & Time settings), so a page that shows it must ask again. */
    function refreshSystemZone() {
        systemZoneProc.running = false;
        systemZoneProc.command = ["sh", "-c", "readlink -f /etc/localtime 2>/dev/null || timedatectl show -p Timezone --value 2>/dev/null"];
        systemZoneProc.running = true;
    }

    // --- World clock rail ------------------------------------------------
    /// The configured cities (deduped, capped at three).
    readonly property var zones: ClockZones.normalize(
        (typeof Config !== "undefined" && Config.clockTimeZones) ? Config.clockTimeZones : [])
    readonly property bool canAdd: ClockZones.canAdd(root.zones)
    readonly property int maxZones: ClockZones.MAX_ZONES
    /// Cities not already on the rail, for the pickers.
    readonly property var availableZones: root.allZones.filter(
        zone => root.zones.indexOf(zone) === -1)

    /// Set while a clock surface (the popout) is on screen.
    property bool active: false
    /// Set while the Time & Date page is open, so it shows live times too.
    property bool pageOpen: false
    /// True when any surface needs offsets.
    readonly property bool observed: root.active || root.pageOpen
    /// Row view-models, one per configured city, live:
    /// { id, city, subtitle, time, abbr, offsetLabel, dayWord, known }.
    property var rows: []
    /// Probed UTC offsets, keyed by zone id, so a reorder never mismatches.
    property var zoneOffsets: ({})
    property bool referenceKnown: false
    /// The reference wall clock, HH:mm, refreshed by the same one-second tick.
    property string localTime: ""

    Process {
        id: probeProc
        command: ["sh", "-c", ""]
        stdout: StdioCollector {
            onStreamFinished: root.applyProbe(this.text)
        }
    }

    // Offsets drift only at DST changes, so probe them rarely...
    Timer {
        id: refreshTimer
        interval: 30000
        repeat: true
        running: root.observed
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // ...but the wall clock is derived from them every second, so a displayed
    // minute is never stale (a clock that is up to 30s behind is a broken clock).
    Timer {
        id: tickTimer
        interval: 1000
        repeat: true
        running: root.observed
        onTriggered: root.rebuild()
    }

    onZonesChanged: {
        // The list updates the instant a city is added or removed; the time
        // arrives with the next probe (moments later) and reads "—" until then.
        root.rebuild();
        root.refresh();
    }
    onActiveChanged: root.observed ? root.refresh() : (root.rows = [])
    onPageOpenChanged: root.pageOpen ? root.refresh() : (root.active ? root.refresh() : (root.rows = []))

    Component.onCompleted: root.ensureSystemZone()

/** One `date` call for the reference zone and every rail zone. */
    function refresh() {
        var now = new Date();
        root.systemOffsetMinutes = -now.getTimezoneOffset();
        if (!root.observed) {
            root.rows = [];
            root.zoneOffsets = ({});
            return;
        }
        var zones = root.zones;
        if (root.referenceZone.length === 0 && zones.length === 0) {
            root.referenceOffsetMinutes = root.systemOffsetMinutes;
            root.rows = [];
            return;
        }
        var parts = [];
        parts.push("TZ=" + ClockZones.shellQuote(root.referenceZone) + " date '+%z|%Z'");
        for (var i = 0; i < zones.length; i++) {
            parts.push("TZ=" + ClockZones.shellQuote(zones[i]) + " date '+%z|%Z'");
        }
        probeProc.running = false;
        probeProc.command = ["sh", "-c", parts.join("; ")];
        probeProc.running = true;
    }

    function applyProbe(text) {
        if (!root.observed) return;
        var offsets = ClockZones.parseOffsets(text);
        var ref = offsets[0] || { offsetMinutes: root.systemOffsetMinutes, abbr: "" };
        root.referenceOffsetMinutes = ref.offsetMinutes;
        root.referenceAbbr = ref.abbr;
        root.referenceKnown = offsets.length > 0;

        var found = ({});
        for (var i = 0; i < root.zones.length; i++) {
            if (offsets[i + 1]) found[root.zones[i]] = offsets[i + 1];
        }
        root.zoneOffsets = found;
        root.rebuild();
    }

    /** Every configured city, with its wall clock as of now. Cheap: <= 3 rows. */
    function rebuild() {
        var now = new Date();
        root.localTime = ClockZones.formatClock(now);
        var refOffset = root.referenceKnown ? root.referenceOffsetMinutes : -now.getTimezoneOffset();
        var built = [];
        for (var i = 0; i < root.zones.length; i++) {
            var id = root.zones[i];
            var probed = root.zoneOffsets[id];
            var view = ClockZones.zoneView(id, now, refOffset,
                probed ? probed.offsetMinutes : refOffset,
                probed ? probed.abbr : "");
            view.subtitle = root.subtitle(id);
            view.known = !!probed;
            if (!view.known) view.time = "—";
            built.push(view);
        }
        root.rows = built;
    }

    /** "Country · description" for a zone, for list rows. */
    function subtitle(zone) {
        return ClockZones.zoneSubtitle(zone, root.zoneDescriptions, root.countryNames);
    }

    /** Zones matching a query by id, description or country. */
    function matches(list, query) {
        return ClockZones.filterZones(list, query, root.zoneDescriptions, root.countryNames);
    }

    /// Open the system's Date & Time settings — the sanctioned owner of the system
    /// time zone. The shell never sets it behind the user's back.
    function openSystemTimeSettings() {
        systemSettingsProc.running = false;
        systemSettingsProc.command = ["kcmshell6", "kcm_clock"];
        systemSettingsProc.running = true;
    }

    Process { id: systemSettingsProc }

    function addZone(id) { Config.addClockTimeZone(id); }
    function removeZone(id) { Config.removeClockTimeZone(id); }

}
