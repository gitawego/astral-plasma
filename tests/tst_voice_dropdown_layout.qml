import QtQuick
import "../theme"
import "../components"
import "../config"
import "../settings_gui/pages"

/**
 * Regression guard: the speech-model and language dropdown lists must never
 * paint over the controls that follow them.
 *
 * Both lists used to be absolutely positioned popups (`anchors.top: parent.bottom`
 * inside the trigger's own `Item`), so opening the model list covered the Language
 * picker and the auto-finalize switch. They are now direct children of their
 * group's ColumnLayout, which grows to fit the list.
 *
 * The invariant asserted here is deliberately stronger and more general than
 * "the two known controls stay visible": while a list is open, *no* visible item
 * anywhere in the page may intersect the list's rectangle, except the list's own
 * subtree and its ancestors. Reintroducing an overlay popup fails this test
 * regardless of what it happens to cover.
 *
 * Note on `height`: once closed, a QML layout drops the item from the layout but
 * the item keeps its last assigned height. The meaningful measure of "did the
 * panel shrink again" is therefore the *position* of the following control, not
 * the list's own `height` -- both are asserted where it matters.
 */
Item {
    id: testRoot
    width: 900
    height: 1600

    readonly property var status: ({
        "enabled": true,
        "engine_available": false,
        "engine_path": null,
        "model": "ggml-large-v3-turbo",
        "model_present": false,
        "setup_complete": false,
        "gap": "engine_missing",
        "models_available": [
            { "id": "ggml-tiny", "display_name": "Tiny", "size_bytes": 77691713, "size_label": "74 MiB" },
            { "id": "ggml-base", "display_name": "Base", "size_bytes": 147951465, "size_label": "141 MiB" },
            { "id": "ggml-large-v3-turbo", "display_name": "Large v3 Turbo (default)", "size_bytes": 1624555275, "size_label": "1549 MiB" }
        ],
        "languages": [
            { "code": "auto", "label": "Auto-detect" },
            { "code": "zh", "label": "Chinese" },
            { "code": "en", "label": "English" },
            { "code": "fr", "label": "French" }
        ]
    })

    VoicePage {
        id: page
        width: parent.width
        height: parent.height
        testMode: true
        testVoiceStatus: testRoot.status
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    function findByName(obj, name) {
        if (!obj) return null;
        if (obj.objectName === name) return obj;
        const kids = obj.children || [];
        for (let i = 0; i < kids.length; i++) {
            const hit = findByName(kids[i], name);
            if (hit) return hit;
        }
        return null;
    }

    function isAncestorOf(candidate, node) {
        let p = node.parent;
        while (p) {
            if (p === candidate) return true;
            p = p.parent;
        }
        return false;
    }

    /** Rectangle of `item` expressed in the page's coordinate space. */
    function rectInPage(item) {
        const tl = item.mapToItem(page, 0, 0);
        return { x: tl.x, y: tl.y, w: item.width, h: item.height };
    }

    function overlaps(a, b) {
        return a.x < b.x + b.w && b.x < a.x + a.w
            && a.y < b.y + b.h && b.y < a.y + a.h;
    }

    function assertListCoversNothing(list, label) {
        const lr = rectInPage(list);
        assert(list.visible, label + ": the list must be visible while open");
        assert(lr.h > 0, label + ": the open list must actually occupy space");

        const offenders = [];
        const stack = [page];
        while (stack.length > 0) {
            const node = stack.pop();
            const kids = node.children || [];
            for (let i = 0; i < kids.length; i++) stack.push(kids[i]);

            if (node === list || node === page) continue;
            if (isAncestorOf(node, list)) continue;   // an ancestor legitimately encloses it
            if (isAncestorOf(list, node)) continue;   // the list's own subtree
            if (!node.visible || node.width <= 0 || node.height <= 0) continue;

            if (overlaps(rectInPage(node), lr)) {
                offenders.push(node.objectName || node.toString().split("(")[0]);
            }
        }
        assert(offenders.length === 0,
            label + ": the open list paints over unrelated controls -> " + offenders.join(", "));
    }

    // The list height is animated (Theme.animExpressiveFastSpatial = 350ms), so
    // geometry is only settled after the transition has finished.
    Timer {
        interval: 150
        running: true
        repeat: false
        onTriggered: startModel()
    }

    function startModel() {
        const list = findByName(page, "voiceModelList");
        const trigger = findByName(page, "voiceModelTrigger");
        const langTrigger = findByName(page, "voiceLanguageTrigger");
        const langList = findByName(page, "voiceLanguageList");

        assert(list, "the model dropdown list must be reachable");
        assert(trigger, "the model dropdown trigger must be reachable");
        assert(langTrigger, "the language dropdown trigger must be reachable");
        assert(langList, "the language dropdown list must be reachable");

        // Closed: both lists take up no room in the layout.
        assert(rectInPage(list).h === 0, "the model list must be collapsed while closed");
        assert(rectInPage(langList).h === 0, "the language list must be collapsed while closed");

        restingLanguageY = rectInPage(langTrigger).y;
        page.modelMenuOpen = true;
    }

    property real restingLanguageY: 0

    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: checkModelOpen()
    }

    function checkModelOpen() {
        const list = findByName(page, "voiceModelList");
        const trigger = findByName(page, "voiceModelTrigger");
        const langTrigger = findByName(page, "voiceLanguageTrigger");

        // The list begins below its own trigger.
        const lr = rectInPage(list);
        const tr = rectInPage(trigger);
        assert(lr.y >= tr.y + tr.h - 0.5,
            "the model list must start below its trigger, not overlap it");

        // The actual defect: the Language picker used to be covered.
        const lt = rectInPage(langTrigger);
        assert(lt.y >= lr.y + lr.h - 0.5,
            "the Language picker must be pushed below the model list, not covered by it "
            + "(pickerY=" + lt.y.toFixed(1) + ", listBottom=" + (lr.y + lr.h).toFixed(1) + ")");
        assert(lt.y > restingLanguageY,
            "opening the model list must push the rest of the panel down, not float over it");

        assertListCoversNothing(list, "model list");

        page.modelMenuOpen = false;
        page.languageMenuOpen = true;
    }

    Timer {
        interval: 1800
        running: true
        repeat: false
        onTriggered: checkLanguageOpen()
    }

    function checkLanguageOpen() {
        const list = findByName(page, "voiceLanguageList");
        const trigger = findByName(page, "voiceLanguageTrigger");
        const modelList = findByName(page, "voiceModelList");

        // Closing one list must hand its space back.
        assert(!modelList.visible, "closing the model list must hide it again");

        const lr = rectInPage(list);
        const tr = rectInPage(trigger);
        assert(lr.y >= tr.y + tr.h - 0.5,
            "the language list must start below its trigger, not overlap it");
        assert(lr.h > 0, "the language list must occupy height while open");

        assertListCoversNothing(list, "language list");

        console.log("PASS: tst_voice_dropdown_layout");
        Qt.exit(0);
    }
}
