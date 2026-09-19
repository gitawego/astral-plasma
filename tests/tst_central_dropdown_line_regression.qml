import QtQuick
import QtQuick.Layouts
import "../theme"
import "../config"
import "../components"
import "../shell"
import "../dashboard/tabs"

Item {
    id: testRoot
    width: 1280
    height: 800

    CentralDropdown {
        id: dropdown
        dropX: 150
        dropW: 980
        visible: true
    }

    DashboardTab {
        id: dashTab
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
        console.log("RUNNING: CentralDropdown Anti-Regression & Liquid Glass Controls Tests");

        // ========================================================
        // 1. Anti-Regression: No Stray Horizontal Divider Lines
        // ========================================================
        assert(dropdown !== null, "CentralDropdown must instantiate");

        // Inspect children of the main layout in CentralDropdown
        let mainLayout = dropdown.layoutItem;
        assert(mainLayout !== undefined && mainLayout !== null, "CentralDropdown must expose layoutItem");

        let foundHorizontalDivider = false;
        for (let i = 0; i < mainLayout.children.length; i++) {
            let child = mainLayout.children[i];
            // Check if there is a 1px height rectangle divider line
            if (child.height === 1 || (child.Layout && child.Layout.preferredHeight === 1)) {
                if (child.color !== undefined && child.color !== "transparent") {
                    foundHorizontalDivider = true;
                    console.error("Found illegal horizontal divider in CentralDropdown layout at index " + i + ": height=" + child.height + " color=" + child.color);
                }
            }
        }
        assert(!foundHorizontalDivider, 
            "CRITICAL REGRESSION PREVENTED: CentralDropdown must NOT have a 1px horizontal separator line under the header tabs!");

        // ========================================================
        // 2. Settings Button must be LiquidGlassButton
        // ========================================================
        let settingsBtn = dropdown.settingsBtnItem;
        assert(settingsBtn !== undefined && settingsBtn !== null, "CentralDropdown must expose settingsBtnItem");
        assert(settingsBtn.contactShadowItem !== undefined, "settingsBtn must be a LiquidGlassButton with contactShadowItem");
        assert(settingsBtn.iconText === "settings" || settingsBtn.iconName === "settings", "settingsBtn icon must be settings");

        // ========================================================
        // 3. DashboardTab Media Controls must be LiquidGlassButtons
        // ========================================================
        assert(dashTab !== null, "DashboardTab must instantiate");
        let prevBtn = dashTab.mediaPrevBtnItem;
        let playBtn = dashTab.mediaPlayBtnItem;
        let nextBtn = dashTab.mediaNextBtnItem;

        assert(prevBtn !== undefined && prevBtn !== null, "dashTab must expose mediaPrevBtnItem");
        assert(playBtn !== undefined && playBtn !== null, "dashTab must expose mediaPlayBtnItem");
        assert(nextBtn !== undefined && nextBtn !== null, "dashTab must expose mediaNextBtnItem");

        assert(prevBtn.contactShadowItem !== undefined, "mediaPrevBtnItem must be a LiquidGlassButton");
        assert(playBtn.contactShadowItem !== undefined, "mediaPlayBtnItem must be a LiquidGlassButton");
        assert(nextBtn.contactShadowItem !== undefined, "mediaNextBtnItem must be a LiquidGlassButton");

        assert(playBtn.isPrimary === true, "mediaPlayBtnItem must have isPrimary=true for prominent liquid glass styling");

        // ========================================================
        // 4. Header Tabs Architecture (Tab Style)
        // ========================================================
        let tabRepeater = dropdown.tabRepeaterItem;
        assert(tabRepeater !== undefined && tabRepeater !== null, "CentralDropdown must expose tabRepeaterItem");
        assert(tabRepeater.count >= 4, "tabRepeater must contain at least 4 tabs");

        let slidingIndicator = dropdown.tabSlidingIndicatorItem;
        assert(slidingIndicator !== undefined && slidingIndicator !== null, "CentralDropdown must expose tabSlidingIndicatorItem");

        console.log("PASS: CentralDropdown Anti-Regression & Liquid Glass Controls Tests");
        Qt.exit(0);
    }
}
