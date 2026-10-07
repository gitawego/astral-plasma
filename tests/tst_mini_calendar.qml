import QtQuick
import "../dock/popouts"
import "../theme"

Item {
    id: testRoot
    width: 400
    height: 400

    MiniCalendar {
        id: calendar
        currentDate: new Date(2026, 9, 6) // October 6, 2026 (Month is 0-indexed, 9 = Oct)
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    function runTests() {
        console.log("RUNNING: MiniCalendar Component Unit Tests");

        // October 2026 verification
        const cells = calendar.monthCells;
        assert(cells.length > 0, "monthCells must not be empty");
        assert(cells.length % 7 === 0, "monthCells length must be multiple of 7, got " + cells.length);

        // Find today's cell (Oct 6)
        let foundToday = false;
        let currentMonthCount = 0;
        for (let i = 0; i < cells.length; i++) {
            const c = cells[i];
            if (c.isCurrentMonth) {
                currentMonthCount++;
            }
            if (c.isToday) {
                assert(c.day === 6, "Today's day must be 6, got " + c.day);
                assert(c.isCurrentMonth === true, "Today must be within current month");
                foundToday = true;
            }
        }

        assert(foundToday, "Today (Oct 6) must be identified in monthCells");
        assert(currentMonthCount === 31, "October has 31 days, found " + currentMonthCount);

        // Test month navigation: next month (November 2026 has 30 days)
        calendar.viewDate = new Date(2026, 10, 1); // November
        const novCells = calendar.monthCells;
        assert(novCells.length % 7 === 0, "November monthCells length must be multiple of 7");
        let novCount = 0;
        for (let j = 0; j < novCells.length; j++) {
            if (novCells[j].isCurrentMonth) novCount++;
        }
        assert(novCount === 30, "November has 30 days, found " + novCount);

        console.log("PASS: MiniCalendar Component Unit Tests passed!");
        Qt.exit(0);
    }
}
