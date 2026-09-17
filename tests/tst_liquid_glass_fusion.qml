import QtQuick
import "../theme"
import "../config"
import "../components"
import "../menus"
import "../notifications"
import "../shell"
import "../shell/launcher"

Item {
    id: testRoot
    width: 1920
    height: 1080

    // Component instances under test
    CornerFillet {
        id: filletTest
        orientation: "topLeft"
        cornerRadius: 24
    }

    MenuCard {
        id: menuCardTest
    }

    NotificationPopup {
        id: notifTest
        visible: true
    }

    UnifiedFrame {
        id: frameTest
        dockW: 64
        borderT: 14
        filletR: 24
        borderColor: Qt.rgba(1, 1, 1, 0.12)
        dropX: 600
        dropW: 720
        currentDropH: 300
        dropdownOffsetProgress: 0.0 // Initially closed
        currentPopW: 300
        popoutY: 600
        popoutHeight: 200
        popoutOffsetProgress: 0.0
        fusedProgress: 0.0
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
        console.log("RUNNING: Liquid Glass Non-Regression & Geometry Fusion Tests");

        // ========================================================
        // 1. Unified Glass Token Non-Regression Tests (when Colors loaded)
        // ========================================================
        if (typeof Colors !== "undefined" && Colors.glassSurface !== undefined) {
            assert(Colors.glassSurface !== undefined, "Colors.glassSurface must be defined");
            assert(Colors.glassBorderSurface !== undefined, "Colors.glassBorderSurface must be defined");
            assert(Colors.glassModalSurface !== undefined, "Colors.glassModalSurface must be defined");
            assert(Colors.glassDockSurface !== undefined, "Colors.glassDockSurface must be defined");
            assert(Colors.glassCard !== undefined, "Colors.glassCard must be defined");
            assert(Colors.glassBorderSpecular !== undefined, "Colors.glassBorderSpecular must be defined");

            // Verify surface tokens share identical base translucency
            assert(Colors.glassBorderSurface === Colors.glassSurface, "Border surface must share exact glassSurface token");
            assert(Colors.glassDockSurface === Colors.glassSurface, "Dock surface must share exact glassSurface token");
            assert(Colors.glassModalSurface === Colors.glassSurface, "Modal surface must share exact glassSurface token");

            // Verify glassCard is NOT opaque pitch-black (#141318 or #1e1b24)
            assert(Colors.glassCard.a < 0.99, "glassCard must be a translucent frosted glass plate");
            assert(filletTest.fillColor === Colors.glassSurface, "CornerFillet default fillColor must equal Colors.glassSurface");
            assert(menuCardTest.color === Colors.glassSurface, "MenuCard color must equal Colors.glassSurface");
            assert(notifTest.fusedPanel.fillColor === Colors.glassSurface, "NotificationPopup fillColor must equal Colors.glassSurface");
            assert(notifTest.fusedPanel.borderColor === Colors.glassBorderSpecular, "NotificationPopup borderColor must be specular");
        }

        // ========================================================
        // 2. CornerFillet Zero-Overlap & Translucency
        // ========================================================
        assert(filletTest.overlap === 0, "CornerFillet default overlap must be strictly 0 to prevent dark seams");
        assert(filletTest.fillColor.a < 0.99, "CornerFillet fillColor must be translucent liquid glass");

        // ========================================================
        // 3. MenuCard Flush Dock Fusion Non-Regression Tests
        // ========================================================
        assert(menuCardTest.topLeftRadius === 0, "MenuCard topLeftRadius must be 0 for flush dock attachment");
        assert(menuCardTest.bottomLeftRadius === 0, "MenuCard bottomLeftRadius must be 0 for flush dock attachment");
        assert(menuCardTest.border.width === 0, "MenuCard border.width must be 0 to prevent double stroke against dock");
        assert(menuCardTest.color.a < 0.99, "MenuCard must be translucent liquid glass");

        // ========================================================
        // 4. Notification Popup Liquid Glass Non-Regression Tests
        // ========================================================
        assert(notifTest.fusedPanel.fillet1.overlap === 0, "Notification fillet1 overlap must be 0");
        assert(notifTest.fusedPanel.fillet2.overlap === 0, "Notification fillet2 overlap must be 0");
        assert(notifTest.fusedPanel.fillColor.a < 0.99, "Notification panel must be translucent liquid glass");

        // ========================================================
        // 5. Border Geometry Partitioning (Zero Double-Translucency)
        // ========================================================
        // Closed Dropdown State:
        // Top border must start at dockW (64) and span to width - borderT (1920 - 14 = 1906)
        let topBorderLeftObj = frameTest.topBorderLeftItem;
        assert(topBorderLeftObj.x === 64, "Top border must start at dockW (64), NOT 0");
        assert(topBorderLeftObj.width === (1920 - 14 - 64), "Top border must span precisely between dockW and width - borderT");

        // Open Dropdown State:
        frameTest.dropdownOffsetProgress = 1.0;
        assert(topBorderLeftObj.width === (600 - 64), "When open, topBorderLeft must span from dockW to dropX without overlap");
        let topBorderRightObj = frameTest.topBorderRightItem;
        assert(topBorderRightObj.x === (600 + 720), "topBorderRight must start at dropX + dropW");
        assert(topBorderRightObj.width === (1920 - 14 - (600 + 720)), "topBorderRight must stop at width - borderT");

        // Central Dropdown Surface Envelope:
        let dashWrapperObj = frameTest.dashSurfaceWrapperItem;
        assert(dashWrapperObj.x === 600, "dashSurfaceWrapper must be at dropX (600)");
        assert(dashWrapperObj.width === 720, "dashSurfaceWrapper must have width dropW (720)");

        // Bottom Border:
        let bottomBorderObj = frameTest.bottomBorderItem;
        assert(bottomBorderObj.x === 64, "Bottom border must start at dockW (64), NOT 0");
        assert(bottomBorderObj.width === (1920 - 14 - 64), "Bottom border must span precisely between dockW and width - borderT");

        // ========================================================
        // 6. Corner Fusion & Perimeter Continuity Tests (6px Border Radius)
        // ========================================================
        let fTL = frameTest.innerFilletTLItem;
        let fTR = frameTest.innerFilletTRItem;
        let fBL = frameTest.innerFilletBLItem;
        let fBR = frameTest.innerFilletBRItem;

        // Verify 6px corner fillets are enabled with matching radius
        assert(fTL.visible === true, "innerFilletTL must be enabled with 6px radius");
        assert(fTR.visible === true, "innerFilletTR must be enabled with 6px radius");
        assert(fBL.visible === true, "innerFilletBL must be enabled with 6px radius");
        assert(fBR.visible === true, "innerFilletBR must be enabled with 6px radius");

        assert(fTL.cornerRadius === 6, "innerFilletTL cornerRadius must be 6");
        assert(fTR.cornerRadius === 6, "innerFilletTR cornerRadius must be 6");
        assert(fBL.cornerRadius === 6, "innerFilletBL cornerRadius must be 6");
        assert(fBR.cornerRadius === 6, "innerFilletBR cornerRadius must be 6");

        // Verify all 4 borders share the exact same liquid glass surface fill
        assert(frameTest.topBorderLeftItem.color === frameTest.glassFill, "topBorderLeft must match glassFill");
        assert(frameTest.rightBorderItem.color === frameTest.glassFill, "rightBorder must match glassFill");
        assert(frameTest.bottomBorderItem.color === frameTest.glassFill, "bottomBorder must match glassFill");

        // Verify specular lines meet flush with 6px corner fillets
        assert(frameTest.topBorderRightLimit === (1920 - frameTest.borderT - frameTest.cornerFilletR), "When no notification, top border specular line connects to TR fillet");
        assert(frameTest.rightBorderTopLimit === (frameTest.borderT + frameTest.cornerFilletR - 1), "When no notification, right border specular line starts flush at TR fillet");
        assert(frameTest.rightBorderBottomLimit === (1080 - (frameTest.borderT + frameTest.cornerFilletR - 1)), "Right border specular line connects flush to BR fillet");

        // ========================================================
        // 7. Notification Liquid Glass Theming Tests
        // ========================================================
        assert(notifTest.fusedPanel !== undefined, "NotificationPopup must expose fusedPanel");
        assert(notifTest.fusedPanel.attachEdge === "topRight", "Notification fusedPanel attachEdge must be topRight");
        assert(notifTest.borderRounding === 6, "Notification borderRounding must match Config (6)");
        if (typeof Colors !== "undefined" && Colors.glassSurface) {
            assert(notifTest.fusedPanel.fillColor === Colors.glassSurface, "Notification fillColor must match Colors.glassSurface");
            assert(notifTest.fusedPanel.borderColor === Colors.glassBorderSpecular, "Notification borderColor must match Colors.glassBorderSpecular");
        } else {
            assert(notifTest.fusedPanel.fillColor.a > 0, "Notification fillColor must have translucent alpha");
        }

        // Test expansion toggle
        let initialH = notifTest.height;
        notifTest.toggleExpanded();
        assert(notifTest.expanded === true, "toggleExpanded must set expanded to true");

        console.log("PASS: Liquid Glass Non-Regression & Geometry Fusion Tests");
        Qt.exit(0);
    }
}
