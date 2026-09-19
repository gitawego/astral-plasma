import QtQuick
import "../theme"
import "../config"
import "../components"
import "../dashboard/tabs"

Item {
    id: testRoot
    width: 1280
    height: 800

    DashboardTab {
        id: dashTab
        visible: true
    }

    PerformanceTab {
        id: perfTab
        visible: false
    }

    WorkspacesTab {
        id: wsTab
        visible: false
    }

    Timer {
        interval: 100
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
        console.log("RUNNING: Dashboard Cards & Widgets Liquid Glass Tests");

        // ========================================================
        // 1. DashboardTab Cards & Elevation Verification
        // ========================================================
        assert(dashTab !== null, "DashboardTab must instantiate");

        // Media Card verification
        let mediaCard = dashTab.mediaCardItem;
        assert(mediaCard !== undefined && mediaCard !== null, "dashTab must expose mediaCardItem");
        assert(mediaCard.showShadow === true, "mediaCard must have showShadow enabled");
        assert(mediaCard.shadowItem !== undefined && mediaCard.shadowItem !== null, "mediaCard must have shadowItem");
        assert(mediaCard.showCaustic === true, "mediaCard must have showCaustic enabled");
        assert(mediaCard.causticItem !== undefined && mediaCard.causticItem !== null, "mediaCard must expose causticItem");

        // Visualizer switcher verification
        let vizBtn = dashTab.vizSwitcherItem;
        assert(vizBtn !== undefined && vizBtn !== null, "dashTab must expose vizSwitcherItem");
        assert(vizBtn.contactShadowItem !== undefined, "vizSwitcherItem must be a liquid glass button with contactShadowItem");

        // Calendar Widget verification (enlarged, aligned, uncropped)
        let calCard = dashTab.calendarCardItem;
        assert(calCard !== undefined && calCard !== null, "dashTab must expose calendarCardItem");
        let calWidget = dashTab.calWidgetItem;
        assert(calWidget !== undefined && calWidget !== null, "dashTab must expose calWidgetItem");
        assert(calWidget.cellWidth >= 40, "Calendar cellWidth must be enlarged to at least 40px (was 28px)");
        assert(calWidget.cellHeight >= 25, "Calendar cellHeight must be enlarged to at least 25px (was 23px)");
        assert(calWidget.colSpacing === calWidget.headerColSpacing, "Calendar header and day column spacing must be identical for alignment");
        assert(calWidget.fontSize >= 12, "Calendar font size must be at least 12px for readability");

        // ========================================================
        // 2. WorkspacesTab Liquid Glass Cards
        // ========================================================
        assert(wsTab !== null, "WorkspacesTab must instantiate");
        assert(wsTab.usesLiquidGlassCards === true, "WorkspacesTab must use liquid glass cards for delegates");

        // ========================================================
        // 3. PerformanceTab Liquid Glass Cards
        // ========================================================
        assert(perfTab !== null, "PerformanceTab must instantiate");
        let ramCard = perfTab.ramCardItem;
        assert(ramCard !== undefined && ramCard !== null, "perfTab must expose ramCardItem");
        assert(ramCard.showShadow === true, "ramCard must have showShadow enabled");

        console.log("PASS: Dashboard Cards & Widgets Liquid Glass Tests");
        Qt.exit(0);
    }
}
