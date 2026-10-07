import QtQuick
import "../services/ClockZones.js" as ClockZones

// Time-zone logic: the pure model behind the shell's clocks.
Item {
    id: testRoot
    width: 400
    height: 400

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    function runTests() {
        console.log("RUNNING: Clock Zones");

        // --- cap, dedupe, blanks ---------------------------------------
        assert(ClockZones.MAX_ZONES === 3, "the rail is capped at three zones");
        var norm = ClockZones.normalize(["Asia/Tokyo", "", "Asia/Tokyo", "Europe/London", "Europe/Paris", "Europe/Berlin"]);
        assert(norm.length === 3, "normalize caps the list at three");
        assert(norm[0] === "Asia/Tokyo" && norm[1] === "Europe/London" && norm[2] === "Europe/Paris",
            "normalize drops blanks and duplicates, keeping order");

        // --- add / remove ----------------------------------------------
        var one = ClockZones.addZone([], "Asia/Tokyo");
        assert(one.length === 1 && one[0] === "Asia/Tokyo", "addZone appends");
        assert(ClockZones.addZone(one, "Asia/Tokyo").length === 1, "addZone ignores duplicates");
        assert(ClockZones.addZone(["a", "b", "c"], "d").length === 3, "addZone refuses past the cap");
        assert(ClockZones.canAdd(["a", "b"]) && !ClockZones.canAdd(["a", "b", "c"]), "canAdd tracks the cap");
        var removed = ClockZones.removeZone(["a", "b", "c"], "b");
        assert(removed.length === 2 && removed.indexOf("b") === -1, "removeZone drops exactly one zone");

        // --- the catalog comes from the OS, not a literal list ----------
        var listing = [
            "Africa/Abidjan",
            "America/New_York",
            "America/Argentina/Buenos_Aires",
            "Europe/Paris",
            "UTC",
            "posix/Europe/Paris",
            "right/Europe/Paris",
            "zone.tab",
            "iso3166.tab",
            "leapseconds",
            "tzdata.zi",
            "posixrules",
            "Factory",
            "localtime",
            ""
        ].join("\n");
        var zones = ClockZones.parseZoneList(listing);
        assert(zones.indexOf("Europe/Paris") !== -1, "real zones survive the filter");
        assert(zones.indexOf("posix/Europe/Paris") === -1, "the posix/ duplicate tree is dropped");
        assert(zones.indexOf("right/Europe/Paris") === -1, "the right/ duplicate tree is dropped");
        assert(zones.indexOf("zone.tab") === -1 && zones.indexOf("tzdata.zi") === -1,
            "database bookkeeping is not a zone");
        assert(zones.indexOf("localtime") === -1 && zones.indexOf("") === -1, "non-zones are dropped");
        assert(zones.indexOf("posixrules") === -1 && zones.indexOf("Factory") === -1,
            "the Factory pseudo-zone and posixrules are dropped");
        assert(zones.indexOf("UTC") !== -1, "root-level zones like UTC are real zones");
        assert(ClockZones.parseZoneList("UTC\nAmerica/New_York").join() === "America/New_York,UTC",
            "parseZoneList sorts the result");
        assert(ClockZones.parseZoneList(listing).length === ClockZones.parseZoneList(listing).length,
            "parseZoneList is deterministic");

        // --- the page searches the WHOLE catalog -------------------------
        // Regression: the pool used to exclude already-added cities, so typing
        // "bei" while Shanghai was on the list reported "nothing matches".
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../settings_gui/pages/TimePage.qml") + "?v=" + Date.now(), false);
        let pageSource = "";
        try { xhr.send(); pageSource = xhr.responseText || ""; } catch (e) { pageSource = ""; }
        assert(pageSource !== "", "the World Clock page source is readable");
        assert(pageSource.indexOf("matchZones(root.availableZones, clockSearch.text)") !== -1,
            "the search must cover the whole catalog, not only the missing cities");
        assert(pageSource.indexOf("availableForClock") === -1,
            "no already-added-excluded pool may feed the search");
        assert(pageSource.indexOf("component CityCard") !== -1,
            "each city must be its own card so the list has real gaps");

        // --- searching by the names people actually use ------------------
        // This is the reported bug: IANA has no Asia/Beijing; China is one zone,
        // and the database describes Asia/Shanghai as "Beijing Time".
        var zoneTab = [
            "# tzdb timezone descriptions",
            "CN\t+3114+12128\tAsia/Shanghai\tBeijing Time",
            "CN\t+4348+08735\tAsia/Urumqi\tXinjiang Time",
            "JP\t+353916+1394441\tAsia/Tokyo\tJapan",
            "US\t+404251-0740023\tAmerica/New_York\tEastern (most areas)"
        ].join("\n");
        var iso = ["CN\tChina", "JP\tJapan", "US\tUnited States"].join("\n");
        var described = ClockZones.parseZoneDescriptions(zoneTab);
        var countries = ClockZones.parseCountryNames(iso);

        assert(described["Asia/Shanghai"].country === "CN"
                && described["Asia/Shanghai"].comment === "Beijing Time",
            "zone.tab rows are parsed into country + description");
        assert(countries["CN"] === "China", "iso3166 rows are parsed into country names");
        assert(described["# tzdb timezone descriptions"] === undefined
                && Object.keys(described).length === 4,
            "comments and blanks are skipped");

        var asia = ["Asia/Shanghai", "Asia/Urumqi", "Asia/Tokyo", "America/New_York"];
        assert(ClockZones.filterZones(asia, "beijing", described, countries).join() === "Asia/Shanghai",
            "\"beijing\" must find Asia/Shanghai through its description");
        assert(ClockZones.filterZones(asia, "china", described, countries).length === 2,
            "\"china\" must find both CN zones through the country name");
        assert(ClockZones.filterZones(asia, "shanghai", described, countries).join() === "Asia/Shanghai",
            "the zone id itself still matches");
        assert(ClockZones.filterZones(asia, "america/", described, countries).join() === "America/New_York",
            "a region prefix still matches");
        assert(ClockZones.filterZones(asia, "atlantis", described, countries).length === 0,
            "an unknown name matches nothing");

        // Subtitles name the country and the database's description.
        assert(ClockZones.zoneSubtitle("Asia/Shanghai", described, countries) === "China · Beijing Time",
            "a described zone reads as country · description");
        assert(ClockZones.zoneSubtitle("Europe/Paris", described, countries) === "Europe",
            "an undescribed zone falls back to its region");

        // One batched read carries the list plus both name tables.
        var batched = "Atlantic/Canary\nAsia/Shanghai\n"
            + ClockZones.ZONE_TAB_MARK + "\n" + zoneTab + "\n"
            + ClockZones.ISO_MARK + "\n" + iso + "\n";
        var sources = ClockZones.parseZoneSources(batched);
        assert(sources.zones.join() === "Asia/Shanghai,Atlantic/Canary",
            "the zone list is split from the name tables and sorted");
        assert(sources.zoneTab.indexOf("Asia/Shanghai") !== -1, "zone.tab survives the split");
        assert(sources.iso3166.indexOf("China") !== -1, "iso3166 survives the split");

        // --- filtering ---------------------------------------------------
        var few = ["America/New_York", "America/Chicago", "Europe/Paris"];
        assert(ClockZones.filterZones(few, "").length === 3, "an empty query keeps everything");
        assert(ClockZones.filterZones(few, "new york").join() === "America/New_York",
            "spaces match underscores in the zone id");
        assert(ClockZones.filterZones(few, "America/").length === 2, "region prefix filtering works");
        assert(ClockZones.filterZones(few, "atlantis").length === 0, "no match yields nothing");

        // --- labels ------------------------------------------------------
        assert(ClockZones.cityFromZoneId("America/New_York") === "New York", "city from the zone id");
        assert(ClockZones.cityFromZoneId("UTC") === "UTC", "a root zone keeps its own name");
        assert(ClockZones.regionFromZoneId("America/New_York") === "America", "region from the zone id");
        assert(ClockZones.regionFromZoneId("UTC") === "", "a root zone has no region");

        // --- offset labels ----------------------------------------------
        assert(ClockZones.offsetLabel(0) === "=", "an identical clock reads as '='");
        assert(ClockZones.offsetLabel(480) === "+8h", "whole positive hours");
        assert(ClockZones.offsetLabel(-240) === "−4h", "whole negative hours use the minus sign");
        assert(ClockZones.offsetLabel(330) === "+5:30", "half-hour zones keep their minutes");
        assert(ClockZones.offsetLabel(-570) === "−9:30", "negative half-hour zones keep their minutes");

        // --- zone view: reference 20:57 at +120 -------------------------
        var ref = new Date(2026, 9, 6, 20, 57, 0);
        var ny = ClockZones.zoneView("America/New_York", ref, 120, -240, "EDT");
        assert(ny.city === "New York", "the row carries the city");
        assert(ny.time === "14:57", "New York is six hours behind the reference");
        assert(ny.offsetLabel === "−6h" && ny.dayWord === "", "same calendar day, negative offset");
        var tokyo = ClockZones.zoneView("Asia/Tokyo", ref, 120, 540, "JST");
        assert(tokyo.time === "03:57", "Tokyo is seven hours ahead of the reference");
        assert(tokyo.offsetLabel === "+7h" && tokyo.dayWord === "tomorrow",
            "Tokyo has already rolled into tomorrow");
        var la = ClockZones.zoneView("America/Los_Angeles", new Date(2026, 9, 6, 2, 30, 0), 120, -420, "PDT");
        assert(la.dayWord === "yesterday", "a zone behind can still be yesterday");

        // --- reference shift --------------------------------------------
        var moved = ClockZones.shiftDate(ref, 180);
        assert(moved.getHours() === 23, "shifting a Date moves its wall clock");
        assert(ClockZones.shiftDate(ref, 0).getTime() === ref.getTime(), "a zero shift is identity");

        // --- probe parsing ----------------------------------------------
        assert(ClockZones.offsetMinutesFromHhmm("+0530") === 330, "+0530 parses to 330 minutes");
        assert(ClockZones.offsetMinutesFromHhmm("-0400") === -240, "-0400 parses to -240 minutes");
        var parsed = ClockZones.parseOffsets("-0400|EDT\n+0900|JST\n");
        assert(parsed.length === 2, "one offset per non-empty line");
        assert(parsed[0].offsetMinutes === -240 && parsed[0].abbr === "EDT", "first zone parsed");
        assert(parsed[1].offsetMinutes === 540 && parsed[1].abbr === "JST", "second zone parsed");

        // --- system zone detection --------------------------------------
        assert(ClockZones.systemZoneFromLink("/usr/share/zoneinfo/Europe/Paris") === "Europe/Paris",
            "the /etc/localtime target names the system zone");
        assert(ClockZones.systemZoneFromLink("Europe/Paris") === "Europe/Paris",
            "a bare zone id passes through");
        assert(ClockZones.systemZoneFromLink("/usr/share/zoneinfo/posix/Europe/Paris") === "Europe/Paris",
            "the posix/ prefix is stripped");
        assert(ClockZones.systemZoneFromLink("") === "", "no link means no zone");

        // --- picker chunking --------------------------------------------
        var groups = ClockZones.chunk([1, 2, 3, 4, 5, 6, 7], 6);
        assert(groups.length === 2 && groups[0].length === 6 && groups[1].length === 1,
            "chunk splits into rows of six");
        assert(ClockZones.chunk([], 6).length === 0, "an empty catalog has no rows");

        // --- shell quoting ----------------------------------------------
        assert(ClockZones.shellQuote("America/New_York") === "'America/New_York'",
            "zone ids are shell-quoted for the probe");

        console.log("PASS: Clock Zones");
        Qt.exit(0);
    }
}
