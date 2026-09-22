import QtQuick
import "../settings_gui/pages"

// ============================================================================
// Calendar App Picker Contract (Settings > Dashboard & Widgets)
// ============================================================================
// The user must be able to pick which calendar app a dashboard date click
// opens, defaulting to the system's XDG MIME default. This suite pins:
//
//   1. Picker model: "System default" (`id === ""`) is always the first row,
//      installed options from the daemon append after it.
//   2. Pick plumbing: selectCalendarApp records the pick, trims it to ""
//      for the system default, and emits calendarAppPicked (testMode
//      suppresses the real settings write).
//   3. Source contract: options load via the daemon's `calendar resolve`,
//      selection persists through Config.setCalendarApp, Theme motion tokens
//      for row transitions, and no hardcoded calendar application names.
Item {
    id: testRoot
    width: 900
    height: 700

    DashboardPage {
        id: page
        testMode: true
        visible: true
    }

    property int pickedCount: 0
    property string pickedId: ""

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Calendar App Picker Tests");

        // --------------------------------------------------------
        // 1. Picker API and model
        // --------------------------------------------------------
        assert(typeof page.selectCalendarApp === "function",
            "page must expose selectCalendarApp(desktopId)");
        assert(typeof page.calendarPickerOptions !== "undefined",
            "page must expose calendarPickerOptions");

        let opts = page.calendarPickerOptions;
        assert(opts.length === 1, "only the system default row before options load, got " + opts.length);
        assert(opts[0].id === "", "first row must be the system default (''), got '" + opts[0].id + "'");
        assert(opts[0].name === "System default", "first row must be labelled 'System default'");

        // Injected daemon options append after the system default row
        page.calendarOptions = [
            { id: "a-cal.desktop", name: "A Cal" },
            { id: "b-cal.desktop", name: "B Cal" }
        ];
        opts = page.calendarPickerOptions;
        assert(opts.length === 3, "2 injected options + system default, got " + opts.length);
        assert(opts[1].id === "a-cal.desktop" && opts[1].name === "A Cal",
            "option 1 must pass through the daemon id/name");
        assert(opts[2].id === "b-cal.desktop" && opts[2].name === "B Cal",
            "option 2 must pass through the daemon id/name");

        // Subtitle surfaces the daemon-reported system default
        page.systemDefaultLabel = "A Cal";
        assert(page.calendarPickerOptions[0].subtitle.indexOf("A Cal") >= 0,
            "system default row must show the daemon-reported default");

        // --------------------------------------------------------
        // 2. Pick plumbing: records, trims, emits; no settings write
        // --------------------------------------------------------
        page.calendarAppPicked.connect(function (id) {
            testRoot.pickedId = id;
            testRoot.pickedCount++;
        });

        page.selectCalendarApp("b-cal.desktop");
        assert(page.lastPickedId === "b-cal.desktop",
            "selectCalendarApp must record the pick, got '" + page.lastPickedId + "'");
        assert(testRoot.pickedCount === 1, "calendarAppPicked must fire exactly once");
        assert(testRoot.pickedId === "b-cal.desktop", "calendarAppPicked payload must be the id");

        page.selectCalendarApp("  ");
        assert(page.lastPickedId === "", "blank pick must normalize to system default ('')");
        assert(testRoot.pickedCount === 2, "second pick must emit again");
        assert(testRoot.pickedId === "", "blank pick payload must be '' (system default)");

        // --------------------------------------------------------
        // 3. Source contract: daemon-driven options, Config persistence,
        //    motion tokens, no hardcoded calendar application names
        // --------------------------------------------------------
        const forbidden = ["korganizer", "kalendar", "gnome-calendar", "gnome_calendar",
                           "merkuro", "evolution --component=calendar", "outlook"];

        const pageSrc = readLocalFile("../settings_gui/pages/DashboardPage.qml");
        assert(pageSrc.length > 1000, "DashboardPage.qml source must be readable");
        assert(/source:\s*root\.testMode\s*\?\s*""\s*:\s*"CalendarAppResolver\.qml"/.test(pageSrc),
            "page must load the resolver only outside testMode (offscreen harness has no Quickshell plugin)");
        assert(/import Quickshell/.test(pageSrc) === false,
            "DashboardPage must not import Quickshell (keeps it instantiable under qml6)");
        assert(/Config\.setCalendarApp/.test(pageSrc),
            "selection must persist through Config.setCalendarApp");
        assert(/root\.selectCalendarApp\(calRow\.modelData\.id\)/.test(pageSrc),
            "row click must route through selectCalendarApp(modelData.id)");
        assert(/cursorShape:\s*Qt\.PointingHandCursor/.test(pageSrc),
            "picker rows must use Qt.PointingHandCursor");
        assert(/hoverEnabled:\s*true/.test(pageSrc), "picker rows must set hoverEnabled");
        assert(/Accessible\.name/.test(pageSrc), "picker rows must expose an Accessible.name");
        assert(/Theme\.animDurationFast/.test(pageSrc),
            "row transitions must use Theme.animDurationFast (no hardcoded durations)");
        assert(/property bool testMode:\s*false/.test(pageSrc),
            "page must gate real daemon/config side effects behind testMode");

        const resolverSrc = readLocalFile("../settings_gui/pages/CalendarAppResolver.qml");
        assert(resolverSrc.length > 500, "CalendarAppResolver.qml source must be readable");
        assert(/"calendar",\s*"resolve"/.test(resolverSrc),
            "resolver must run the daemon 'calendar resolve' command");

        const cfgSrc = readLocalFile("../config/Config.qml");
        assert(cfgSrc.length > 1000, "Config.qml source must be readable");
        assert(/"calendarApp":\s*""/.test(cfgSrc),
            "shipped default must be empty (follow the system default)");
        assert(/function setCalendarApp\(desktopId\)/.test(cfgSrc),
            "Config must expose setCalendarApp(desktopId)");
        assert(/cfg\.dashboard\.calendarApp\s*=/.test(cfgSrc),
            "setCalendarApp must write dashboard.calendarApp");

        const sources = [
            { name: "DashboardPage.qml", text: pageSrc },
            { name: "CalendarAppResolver.qml", text: resolverSrc },
            { name: "Config.qml", text: cfgSrc }
        ];
        for (let f = 0; f < forbidden.length; f++) {
            for (let s = 0; s < sources.length; s++) {
                assert(sources[s].text.toLowerCase().indexOf(forbidden[f]) < 0,
                    sources[s].name + " must not hardcode calendar app '" + forbidden[f] + "'");
            }
        }

        console.log("PASS: Calendar App Picker Tests (model, pick plumbing, source contract)");
        Qt.exit(0);
    }
}
