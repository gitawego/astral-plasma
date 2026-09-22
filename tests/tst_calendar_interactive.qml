import QtQuick
import "../theme"
import "../config"
import "../components"
import "../dashboard/tabs"

// ============================================================================
// Calendar Interactivity Contract
// ============================================================================
// Clicking a dashboard date must open the system's default calendar
// application (data-driven via the XDG MIME database, never a hardcoded
// application name). This suite pins:
//
//   1. Pure date math: every grid cell maps to the correct YYYY-MM-DD,
//      including leading/trailing overflow days with year rollover,
//      verified against JS Date ground truth.
//   2. Click plumbing: openDateForCell records the date and emits
//      dateClicked (testMode suppresses the real daemon launch).
//   3. Source contract: cells carry a hover-enabled MouseArea with a
//      pointing-hand cursor, accessible name, Theme motion tokens for the
//      hover halo, and no hardcoded calendar application names.
Item {
    id: testRoot
    width: 1280
    height: 800

    DashboardTab {
        id: dashTab
        testMode: true
        visible: true
    }

    property string receivedIso: ""
    property int receivedCount: 0

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

    function pad(n) {
        return (n < 10 ? "0" : "") + n;
    }

    function isoOfDate(d) {
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Calendar Interactivity Tests");

        // --------------------------------------------------------
        // 1. Widget exposes the interactive API
        // --------------------------------------------------------
        let calWidget = dashTab.calWidgetItem;
        assert(calWidget !== undefined && calWidget !== null, "dashTab must expose calWidgetItem");
        assert(typeof calWidget.isoForCell === "function", "calWidget must expose isoForCell(cellIndex)");
        assert(typeof calWidget.dateForCell === "function", "calWidget must expose dateForCell(cellIndex)");
        assert(typeof calWidget.openDateForCell === "function", "calWidget must expose openDateForCell(cellIndex)");

        // Geometry regression guard (must not shrink while adding interactivity)
        assert(calWidget.cellWidth >= 40, "Calendar cellWidth must stay >= 40px");
        assert(calWidget.cellHeight >= 25, "Calendar cellHeight must stay >= 25px");

        // --------------------------------------------------------
        // 2. Every cell matches JS Date ground truth
        // --------------------------------------------------------
        let total = calWidget.totalCells;
        assert(total === 35 || total === 42, "totalCells must be 35 or 42, got " + total);
        for (let i = 0; i < total; i++) {
            let expected = new Date(calWidget.currYear, calWidget.currMonth, 1 - calWidget.startOffset + i);
            let want = isoOfDate(expected);
            let got = calWidget.isoForCell(i);
            assert(got === want, "cell " + i + " ISO must be " + want + ", got " + got);
            let parts = calWidget.dateForCell(i);
            assert(parts.month >= 1 && parts.month <= 12, "cell " + i + " month must be 1-12");
            assert(parts.day >= 1 && parts.day <= 31, "cell " + i + " day must be 1-31");
            assert(parts.year + "-" + pad(parts.month) + "-" + pad(parts.day) === got,
                "cell " + i + " dateForCell/isoForCell must agree");
        }

        // Today cell resolves to today
        let todayIdx = calWidget.startOffset + calWidget.currDay - 1;
        assert(isoOfDate(new Date()) === calWidget.isoForCell(todayIdx),
            "today cell ISO must equal today's date");

        // --------------------------------------------------------
        // 3. Click plumbing: records date + emits signal, no launch
        // --------------------------------------------------------
        calWidget.dateClicked.connect(function (iso) {
            testRoot.receivedIso = iso;
            testRoot.receivedCount++;
        });
        calWidget.openDateForCell(todayIdx);
        let wantToday = calWidget.isoForCell(todayIdx);
        assert(calWidget.lastClickedDate === wantToday,
            "openDateForCell must record lastClickedDate " + wantToday + ", got " + calWidget.lastClickedDate);
        assert(testRoot.receivedCount === 1, "dateClicked must fire exactly once");
        assert(testRoot.receivedIso === wantToday, "dateClicked payload must be " + wantToday);

        // Overflow click still resolves (prev-month cell when present)
        if (calWidget.startOffset > 0) {
            calWidget.openDateForCell(0);
            assert(calWidget.lastClickedDate === calWidget.isoForCell(0),
                "overflow prev-month click must record its own ISO");
            assert(testRoot.receivedCount === 2, "second click must emit again");
        }

        // --------------------------------------------------------
        // 4. Source contract: interactive cells, motion tokens, no
        //    hardcoded calendar application names
        // --------------------------------------------------------
        const dashSrc = readLocalFile("../dashboard/tabs/DashboardTab.qml");
        assert(dashSrc.length > 1000, "DashboardTab.qml source must be readable");
        assert(/MouseArea\s*\{/.test(dashSrc), "calendar cells must contain a MouseArea");
        assert(/cursorShape:\s*Qt\.PointingHandCursor/.test(dashSrc),
            "calendar MouseArea must use Qt.PointingHandCursor");
        assert(/hoverEnabled:\s*true/.test(dashSrc), "calendar MouseArea must set hoverEnabled");
        assert(/onClicked:\s*calWidget\.openDateForCell\(index\)/.test(dashSrc),
            "calendar click must route through calWidget.openDateForCell(index)");
        assert(/Accessible\.name/.test(dashSrc), "calendar cells must expose an Accessible.name");
        assert(/Theme\.animExpressiveFastEffects/.test(dashSrc),
            "calendar hover halo must use Theme.animExpressiveFastEffects (no hardcoded durations)");
        assert(/Theme\.curveExpressiveFastEffects/.test(dashSrc),
            "calendar hover halo must use Theme.curveExpressiveFastEffects");
        assert(/WindowService\.openCalendar\(iso\)/.test(dashSrc),
            "calendar click must call WindowService.openCalendar(iso)");

        const forbidden = ["korganizer", "kalendar", "gnome-calendar", "gnome_calendar",
                           "merkuro", "evolution --component=calendar", "outlook"];
        for (let f = 0; f < forbidden.length; f++) {
            assert(dashSrc.toLowerCase().indexOf(forbidden[f]) < 0,
                "DashboardTab.qml must not hardcode calendar app '" + forbidden[f] + "'");
        }

        const wsSrc = readLocalFile("../services/WindowService.qml");
        assert(wsSrc.length > 500, "WindowService.qml source must be readable");
        assert(/function openCalendar\(isoDate\)/.test(wsSrc),
            "WindowService must expose openCalendar(isoDate)");
        assert(/"calendar",\s*"open"/.test(wsSrc),
            "WindowService.openCalendar must invoke the daemon 'calendar open' command");
        for (let g = 0; g < forbidden.length; g++) {
            assert(wsSrc.toLowerCase().indexOf(forbidden[g]) < 0,
                "WindowService.qml must not hardcode calendar app '" + forbidden[g] + "'");
        }

        console.log("PASS: Calendar Interactivity Tests (" + total + " cells verified against JS Date)");
        Qt.exit(0);
    }
}
