import QtQuick
import "../components"
import "../theme"
import "../config"

Item {
    id: testRoot
    width: 800
    height: 600

    property bool bottomPopoutVisible: false
    property string bottomPopoutMode: "default"
    property real popoutTargetY: 0
    property var activeTrayItem: null

    property int activateCalls: 0
    property string lastActivatedService: ""
    property string lastActivatedPath: ""

    property int contextMenuCalls: 0
    property string lastContextMenuService: ""

    function openBottomPopout(mode, targetY) {
        if (mode) testRoot.bottomPopoutMode = mode;
        if (targetY !== undefined) testRoot.popoutTargetY = targetY;
        testRoot.bottomPopoutVisible = true;
    }

    function closeBottomPopout() {
        testRoot.bottomPopoutVisible = false;
    }

    function activateTray(service, path) {
        testRoot.activateCalls++;
        testRoot.lastActivatedService = service;
        testRoot.lastActivatedPath = path;
    }

    function contextMenuTray(service, path) {
        testRoot.contextMenuCalls++;
        testRoot.lastContextMenuService = service;
    }

    // Simulated click handler matching UnifiedDock.qml
    function handleTrayClick(modelData, button, targetCenterY) {
        if (button === Qt.RightButton) {
            if (modelData.menuPath && modelData.menuPath.length > 0) {
                testRoot.activeTrayItem = modelData;
                openBottomPopout("tray", targetCenterY);
            } else {
                contextMenuTray(modelData.service, modelData.path);
            }
        } else {
            if (modelData.itemIsMenu && modelData.menuPath && modelData.menuPath.length > 0) {
                testRoot.activeTrayItem = modelData;
                openBottomPopout("tray", targetCenterY);
            } else {
                closeBottomPopout();
                activateTray(modelData.service, modelData.path);
            }
        }
    }

    // Simulated header click in FusedBottomPopout.qml
    function handlePopoutHeaderClick() {
        if (testRoot.activeTrayItem) {
            closeBottomPopout();
            activateTray(testRoot.activeTrayItem.service, testRoot.activeTrayItem.path);
        }
    }

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
        }
    }

    function runTests() {
        console.log("RUNNING: System Tray Click Activation & Round Box Tests");

        // 1. Spectacle Screen Recording Tray Item (has /MenuBar, itemIsMenu = false)
        const spectacleItem = {
            id: "spectacle",
            title: "Spectacle Recording",
            service: ":1.999",
            path: "/StatusNotifierItem",
            menuPath: "/MenuBar",
            itemIsMenu: false,
            rawIcon: "spectacle"
        };

        // Open drawer first (e.g. by hovering)
        openBottomPopout("tray", 700);
        assert(testRoot.bottomPopoutVisible === true, "Drawer initially open on hover");

        // Click on spectacle tray item with LeftButton
        handleTrayClick(spectacleItem, Qt.LeftButton, 700);
        assert(testRoot.activateCalls === 1, "Left click on recording tray item called activateTray");
        assert(testRoot.lastActivatedService === ":1.999", "Activated correct service");
        assert(testRoot.lastActivatedPath === "/StatusNotifierItem", "Activated correct path");
        assert(testRoot.bottomPopoutVisible === false, "Drawer closed when tray item was activated");

        // 2. Pure Menu Item (itemIsMenu = true, e.g. Dropbox-like applet)
        const pureMenuItem = {
            id: "pure-menu-app",
            title: "Pure Menu",
            service: ":1.888",
            path: "/StatusNotifierItem",
            menuPath: "/Menu",
            itemIsMenu: true,
            rawIcon: "application-menu"
        };

        handleTrayClick(pureMenuItem, Qt.LeftButton, 720);
        assert(testRoot.activateCalls === 1, "Left click on pure menu item does not call activateTray");
        assert(testRoot.bottomPopoutVisible === true, "Left click on pure menu item opened bottom popout");
        assert(testRoot.activeTrayItem.id === "pure-menu-app", "Active tray item set to pure menu item");

        // 3. Right-Click on standard tray item opens menu drawer
        handleTrayClick(spectacleItem, Qt.RightButton, 700);
        assert(testRoot.bottomPopoutVisible === true, "Right click opens popout drawer");
        assert(testRoot.activeTrayItem.id === "spectacle", "Active tray item set to spectacle");

        // 4. Click on Popout Header triggers activateTray and closes drawer
        handlePopoutHeaderClick();
        assert(testRoot.activateCalls === 2, "Clicking drawer header triggered activateTray");
        assert(testRoot.bottomPopoutVisible === false, "Clicking drawer header closed drawer");

        // 5. Verify Colors.glassCard Opacity in Dark Mode (subtle translucent liquid glass)
        if (typeof Colors !== "undefined" && Colors.glassCard !== undefined) {
            assert(Colors.glassCard.a > 0 && Colors.glassCard.a <= 0.35, "Colors.glassCard has subtle translucency, current: " + Colors.glassCard.a);
        }

        // 6. Verify Config.iconUrl resolution (when Config loaded)
        if (typeof Config !== "undefined" && Config.iconUrl !== undefined) {
            const emptyUrl = Config.iconUrl("");
            assert(emptyUrl === "", "Config.iconUrl('') must return empty string");
            const fileUrl = Config.iconUrl("/usr/share/icons/hicolor/scalable/apps/org.kde.spectacle.svg");
            assert(fileUrl.startsWith("file://"), "Config.iconUrl with direct path returns file:// URL");
        }

        console.log("PASS: System Tray Click Activation & Round Box Tests");
        Qt.exit(0);
    }
}
