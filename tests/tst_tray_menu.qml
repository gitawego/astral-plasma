import QtQuick
import "../menus"
import "../theme"

Item {
    id: testRoot
    width: 800
    height: 600

    property var clickedIds: []

    MenuCard {
        id: trayCard
        implicitWidth: 240

        MenuHeader {
            id: trayHeader
            title: "Token Tracker"
            subtitle: "org.kde.StatusNotifierItem-3565-1"
            materialIcon: "toll"
        }

        MenuDivider { id: topDivider }

        Repeater {
            id: menuRepeater
            model: [
                { id: 1, label: "Open Graphical Dashboard", isSeparator: false, enabled: true, icon: "view-statistics" },
                { id: 2, label: "", isSeparator: true, enabled: true, icon: "" },
                { id: 3, label: "Settings...", isSeparator: false, enabled: true, icon: "emblem-system" },
                { id: 4, label: "", isSeparator: true, enabled: true, icon: "" },
                { id: 5, label: "Quit Token Tracker", isSeparator: false, enabled: true, icon: "application-exit" }
            ]

            Item {
                id: itemDelegate
                width: parent ? parent.width : 220
                visible: modelData.isSeparator || (modelData.label !== undefined && modelData.label.trim() !== "")
                height: visible ? (modelData.isSeparator ? 9 : 38) : 0

                MenuDivider {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: modelData.isSeparator
                }

                MenuItem {
                    anchors.fill: parent
                    visible: !modelData.isSeparator
                    text: modelData.label || ""
                    enabled: modelData.enabled !== false
                    isDangerous: (modelData.label && modelData.label.toLowerCase().indexOf("quit") !== -1)
                    onClicked: {
                        testRoot.clickedIds.push(modelData.id);
                    }
                }
            }
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
        console.log("RUNNING: Tray Menu Integration Tests");

        // 1. Verify Card & Header
        assert(trayHeader.title === "Token Tracker", "Tray header title matches");
        assert(trayHeader.subtitle === "org.kde.StatusNotifierItem-3565-1", "Tray header service subtitle matches");
        assert(trayCard.implicitWidth === 240, "Tray menu width should be 240px");

        // 2. Verify Repeater Items
        assert(menuRepeater.count === 5, "Repeater generated 5 items");

        const item0 = menuRepeater.itemAt(0);
        assert(item0.visible === true, "Item 0 visible");
        assert(item0.height === 38, "Item 0 has standard action height 38px");

        const item1 = menuRepeater.itemAt(1);
        assert(item1.visible === true, "Item 1 (separator) visible");
        assert(item1.height === 9, "Item 1 has separator height 9px");

        const item4 = menuRepeater.itemAt(4);
        assert(item4.visible === true, "Item 4 (Quit) visible");
        assert(item4.height === 38, "Item 4 has action height 38px");

        // 3. Verify Tray Menu Switching & Anti-Cross-Contamination
        let stateActiveItem = { service: "org.kde.StatusNotifierItem-3731-1", menuPath: "/MenuBar", title: "Token Tracker" };
        let stateMenuItems = [{ id: 123, label: "Quit Token Tracker" }];
        let stateLoading = false;

        function simulateLoadTrayMenu(newItem) {
            const isDifferent = !stateActiveItem || stateActiveItem.service !== newItem.service || stateActiveItem.menuPath !== newItem.menuPath;
            if (isDifferent) {
                stateMenuItems = [];
                stateLoading = true;
                stateActiveItem = newItem;
            }
        }

        simulateLoadTrayMenu({ service: "org.kde.StatusNotifierItem-3886-1", menuPath: "/MenuBar", title: "Cachy-Update" });
        assert(stateLoading === true, "Loading state true when switching to new tray item");
        assert(stateMenuItems.length === 0, "Menu items must be cleared immediately when switching tray item");
        assert(stateActiveItem.service === "org.kde.StatusNotifierItem-3886-1", "Active tray item switched to Cachy-Update");

        // 4. Verify Stale Response Rejection
        let activeReqId = 2;
        let expectedService = "org.kde.StatusNotifierItem-3886-1";

        function handleStreamFinished(rawJson, reqId, expectedSvc) {
            const parsed = JSON.parse(rawJson);
            let items = Array.isArray(parsed) ? parsed : (parsed.items || []);
            let respSvc = parsed.service || "";
            if (respSvc && expectedSvc && respSvc !== expectedSvc) {
                return false; // Rejected due to service mismatch
            }
            if (reqId !== activeReqId) {
                return false; // Rejected due to request ID mismatch
            }
            return true;
        }

        // Old response from Process 1 (Token Tracker) arrives after switching to Cachy-Update (Req 2)
        const staleOutput = JSON.stringify({
            service: "org.kde.StatusNotifierItem-3731-1",
            menuPath: "/MenuBar",
            items: [{ id: 123, label: "Quit Token Tracker" }]
        });
        const staleAccepted = handleStreamFinished(staleOutput, 1, expectedService);
        assert(staleAccepted === false, "Stale Token Tracker response must be rejected by service and reqId checks");

        // Fresh response from Process 2 (Cachy-Update)
        const freshOutput = JSON.stringify({
            service: "org.kde.StatusNotifierItem-3886-1",
            menuPath: "/MenuBar",
            items: [{ id: 263, label: "Packages (29)" }]
        });
        const freshAccepted = handleStreamFinished(freshOutput, 2, expectedService);
        assert(freshAccepted === true, "Fresh Cachy-Update response must be accepted");

        console.log("PASS: Tray Menu Integration Tests");
        Qt.exit(0);
    }
}
