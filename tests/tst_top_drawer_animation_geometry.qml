import QtQuick
import "../shell"
import "../theme"
import "../config"

Item {
    id: root
    width: 1920
    height: 1080

    UnifiedFrame {
        id: frame
        dockW: 64
        borderT: 14
        filletR: 20
        borderColor: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) ? Colors.glassBorderSpecular : Qt.rgba(1, 1, 1, 0.12)
        dropX: 600
        dropW: 720
        currentDropH: 0
        dropdownOffsetProgress: 0.0
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

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
    }

    function runTests() {
        console.log("RUNNING: Top Drawer Animation Geometry & Non-Regression Tests");

        let wrapper = frame.dashSurfaceWrapperItem;
        assert(wrapper !== undefined, "dashSurfaceWrapperItem must be exposed by UnifiedFrame");

        let maxRadiusSum = frame.filletR + frame.modalRadius;

        // 1. Closed state
        frame.dropdownOffsetProgress = 0.0;
        frame.currentDropH = 0;
        assert(wrapper.height >= frame.borderT, "dashSurfaceWrapper height must be at least borderT");
        assert(wrapper.extH === 0, "When closed, extH must be 0");
        assert(wrapper.currentFilletR === 0, "When closed, currentFilletR must be 0");
        assert(wrapper.currentModalR === 0, "When closed, currentModalR must be 0");

        // 2. Early animation frame (currentDropH = 5px, inside top border)
        frame.dropdownOffsetProgress = 0.01;
        frame.currentDropH = 5;
        assert(wrapper.height === frame.borderT, "While currentDropH <= borderT, wrapper height must equal borderT (14)");
        assert(wrapper.extH === 0, "extH must be clamped to 0 when currentDropH <= borderT");
        assert(wrapper.currentFilletR === 0, "currentFilletR must be 0 when extH == 0");
        assert(wrapper.currentModalR === 0, "currentModalR must be 0 when extH == 0");

        // 3. Early emergence frame (currentDropH = 20px, extH = 6px < maxRadiusSum)
        frame.dropdownOffsetProgress = 0.05;
        frame.currentDropH = 20;
        assert(wrapper.height === 20, "Wrapper height must track currentDropH");
        assert(wrapper.extH === 6, "extH must be 6 (20 - 14)");
        assert(wrapper.k > 0 && wrapper.k < 1.0, "k must interpolate smoothly between 0 and 1");
        assert(wrapper.currentFilletR + wrapper.currentModalR <= wrapper.extH + 0.001,
               "Radii sum must NEVER exceed extH during early animation (prevents arc collision)");

        // 4. Mid animation frame (currentDropH = 14 + maxRadiusSum / 2)
        frame.dropdownOffsetProgress = 0.1;
        frame.currentDropH = 14 + maxRadiusSum / 2;
        assert(Math.abs(wrapper.k - 0.5) < 0.01, "k must be 0.5 at half maxRadiusSum");
        assert(wrapper.currentFilletR + wrapper.currentModalR <= wrapper.extH + 0.001,
               "Radii sum must match extH when k <= 1");

        // 5. Full radius threshold (currentDropH = 14 + maxRadiusSum)
        frame.dropdownOffsetProgress = 0.15;
        frame.currentDropH = 14 + maxRadiusSum;
        assert(wrapper.extH === maxRadiusSum, "extH must equal maxRadiusSum");
        assert(wrapper.k === 1.0, "k must reach 1.0 at extH = maxRadiusSum");
        assert(wrapper.currentFilletR === frame.filletR, "currentFilletR must reach full filletR (20)");
        assert(wrapper.currentModalR === frame.modalRadius, "currentModalR must reach full modalRadius (32)");

        // 6. Fully open state (currentDropH = 520px)
        frame.dropdownOffsetProgress = 1.0;
        frame.currentDropH = 520;
        assert(wrapper.height === 520, "Wrapper height must be 520");
        assert(wrapper.extH === 506, "extH must be 506");
        assert(wrapper.k === 1.0, "k must be 1.0");
        assert(wrapper.currentFilletR === frame.filletR, "Full filletR must be preserved");
        assert(wrapper.currentModalR === frame.modalRadius, "Full modalRadius must be preserved");

        console.log("PASS: Top Drawer Animation Geometry Tests passed!");
        Qt.exit(0);
    }
}
