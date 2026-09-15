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

        console.log("PASS: Tray Menu Integration Tests");
        Qt.exit(0);
    }
}
