import QtQuick
import "../config"
import "../dashboard/tabs"
import "../settings_gui/pages"
import "../settings_gui/controls"

// ============================================================================
// Configurable System-Host Avatar & Durable Image Import Contract
// ============================================================================
// The dashboard system-host card avatar (and the media tab avatar) must be
// configurable, and every configured image must be copied into the app config
// dir (~/.config/astral-plasma/) so the setting survives deletion of the
// original source file. This suite pins the QML side of the feature; the
// path pipeline and the real copy/removal round-trip are covered by the Rust
// suite (`daemon/tests/test_avatar_import.rs`) behind the daemon's
// `config import-image` / `config forget-image` commands:
//
//   1. AvatarPathField (dumb control): trimmed commits, reset-to-default,
//      stored-path sync into the input - all under the offscreen qml6
//      harness (no Quickshell plugin, per this repo's established rule).
//   2. DashboardPage: instantiates with the new avatar cards (FileDialog
//      included) in testMode; both Config setters are gated behind testMode.
//   3. DashboardTab rendering: "" resolves to the bundled default art, an
//      absolute path to a file:// URL, and the live Image.source follows
//      Config.hostAvatar.
//   4. Source contracts: Config exposes setHostAvatar + the daemon import/
//      forget wiring + load-time migration; shipped defaults carry the key.
//
// NOTE: under plain `qml6` the Config singleton is registered but inert
// (Quickshell's plugin is not loadable offscreen), so runtime Config reads
// evaluate to undefined here - which is exactly why the harness-shaped
// assertions below stay conditional and the Config wiring is pinned on the
// source level instead.
Item {
    id: testRoot
    width: 1280
    height: 800

    DashboardTab {
        id: dashTab
        visible: false
    }

    DashboardPage {
        id: page
        testMode: true
        visible: false
    }

    property int pickCount: 0
    property string lastPicked: ""
    property int bgPickCount: 0
    property string lastBgHex: ""
    property real lastBgOpacity: -1

    AvatarPathField {
        id: field
        title: "System Host Card Avatar"
        description: "test"
        placeholder: "Default (Dino)"
        interactive: true
        onPathPicked: p => {
            testRoot.lastPicked = p;
            testRoot.pickCount++;
        }
    }

    AvatarPathField {
        id: fieldBg
        showBgOptions: true
        onBgStylePicked: (hex, op) => {
            testRoot.lastBgHex = hex;
            testRoot.lastBgOpacity = op;
            testRoot.bgPickCount++;
        }
    }

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

    Timer {
        interval: 150
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: Configurable Host Avatar & Durable Import Tests");

        // --------------------------------------------------------
        // 1. AvatarPathField runtime contract (dumb control, qml6-safe)
        // --------------------------------------------------------
        assert(field !== null, "AvatarPathField must instantiate under qml6");
        assert(field.interactive === true, "AvatarPathField must default to interactive");
        assert(field.inputField !== undefined && field.inputField !== null,
            "AvatarPathField must expose its input field");

        // Commit trims: one normalization point for input, browse and reset.
        field.commit("   /home/hlu/Downloads/f37dc4896efd8857f7929d3af23adab4.png   ");
        assert(testRoot.pickCount === 1, "commit must emit pathPicked exactly once");
        assert(testRoot.lastPicked === "/home/hlu/Downloads/f37dc4896efd8857f7929d3af23adab4.png",
            "commit must trim the path, got '" + testRoot.lastPicked + "'");

        // Stored path syncs into the input when the user is not typing.
        field.inputField.text = "user-typing";
        field.path = "/home/u/.config/astral-plasma/host-avatar.png";
        assert(field.inputField.text === "/home/u/.config/astral-plasma/host-avatar.png",
            "a stored path change must sync into the unfocused input, got '" + field.inputField.text + "'");

        // Reset clears the input and reports "" (bundled default).
        field.resetPath();
        assert(testRoot.pickCount === 2, "resetPath must emit pathPicked");
        assert(testRoot.lastPicked === "", "resetPath must commit '' (default art)");
        assert(field.inputField.text === "", "resetPath must clear the input");

        // --------------------------------------------------------
        // 2. DashboardPage instantiates with the new avatar cards
        // --------------------------------------------------------
        assert(page !== null, "DashboardPage must instantiate in testMode with AvatarPathField cards");
        assert(page.testMode === true, "the page instance must run in testMode (suppresses Config side effects)");

        // --------------------------------------------------------
        // 3. DashboardTab rendering: resolution + live Image binding
        // --------------------------------------------------------
        assert(dashTab !== null, "DashboardTab must instantiate");
        assert(typeof dashTab.resolveAvatarSource === "function", "DashboardTab must expose resolveAvatarSource()");
        assert(dashTab.resolveAvatarSource("").endsWith("theme/assets/dino.png"),
            "empty config must fall back to the bundled default art");
        assert(dashTab.resolveAvatarSource("  ").endsWith("theme/assets/dino.png"),
            "a blank config must fall back to the bundled default art");
        assert(dashTab.resolveAvatarSource("/home/hlu/pics/gojo.png") === "file:///home/hlu/pics/gojo.png",
            "an absolute path must normalize to a file:// URL");
        assert(dashTab.resolveAvatarSource("file:///home/hlu/pics/gojo.png") === "file:///home/hlu/pics/gojo.png",
            "a file:// URL must pass through unchanged");
        assert(dashTab.resolveAvatarSource(undefined) === dashTab.resolveAvatarSource(""),
            "an undefined Config value must resolve like the default (inert singleton in harness)");

        const configured = (typeof Config !== "undefined") ? Config.hostAvatar : "";
        assert(dashTab.hostAvatarSource === dashTab.resolveAvatarSource(configured || ""),
            "hostAvatarSource must track Config.hostAvatar");
        assert(dashTab.hostAvatarImageItem !== undefined && dashTab.hostAvatarImageItem !== null,
            "DashboardTab must expose hostAvatarImageItem for verification");
        // Generic circular avatar treatment - must hold for ANY image the
        // user configures:
        //   - CONTAIN + CENTER: the whole image is always visible,
        //     letterboxed and centered (PreserveAspectFit) - the shell never
        //     crops or reframes; picking a correctly sized image is the
        //     user's choice;
        //   - the artwork is masked to a TRUE circle via the repo's
        //     maskSource pattern (Rectangle.clip only clips to the bounding
        //     box, which let square image corners leak over the card);
        //   - a single image, no blur/backdrop layers, no cover framing.
        assert(typeof dashTab.avatarFrame === "undefined",
            "cover framing must be gone - contain + center is the contract");
        assert(dashTab.hostAvatarImageItem.fillMode === Image.PreserveAspectFit,
            "host avatar must contain the full image (PreserveAspectFit), got fillMode="
            + dashTab.hostAvatarImageItem.fillMode);
        assert(dashTab.hostAvatarImageItem.parent === dashTab.hostAvatarArtItem,
            "artwork must live inside the circle-masked item");
        assert(dashTab.hostAvatarImageItem.width === dashTab.hostAvatarCircle.width
            && dashTab.hostAvatarImageItem.height === dashTab.hostAvatarCircle.height
            && dashTab.hostAvatarImageItem.x === 0 && dashTab.hostAvatarImageItem.y === 0,
            "artwork must fill the circle box (contain + center does the rest)");

        assert(dashTab.hostAvatarArtItem.layer && dashTab.hostAvatarArtItem.layer.effect,
            "artwork layer must carry the circle-mask effect");
        assert(dashTab.hostAvatarMaskItem.radius === dashTab.hostAvatarMaskItem.width / 2,
            "mask must be a true circle (radius = width/2)");
        const tabSrc = readLocalFile("../dashboard/tabs/DashboardTab.qml");
        assert(tabSrc.length > 1000, "DashboardTab.qml source must be readable");
        assert(/maskEnabled:\s*true/.test(tabSrc) && /maskSource:\s*avatarMask/.test(tabSrc),
            "avatar artwork must be masked via the repo maskSource circle pattern");
        const siblings = dashTab.hostAvatarCircle.children;
        assert(siblings.indexOf(dashTab.hostAvatarArtItem) >= 0
            && siblings.indexOf(dashTab.hostAvatarBorderItem) > siblings.indexOf(dashTab.hostAvatarArtItem),
            "inner border must be stacked above the artwork (crisp circle edge)");
        assert(dashTab.hostAvatarBorderItem.border.width === 1,
            "inner border must stay a 1px hairline");

        // --------------------------------------------------------
        // 3b. Configurable circle background (color + transparency)
        //     Default: white @ 0.2, exactly as specified.
        // --------------------------------------------------------
        assert(typeof dashTab.resolveAvatarBg === "function", "DashboardTab must expose resolveAvatarBg()");
        assert(dashTab.resolveAvatarBg("#ffffff", 0.2) == Qt.rgba(1, 1, 1, 0.2),
            "resolveAvatarBg must apply color + opacity");
        assert(dashTab.resolveAvatarBg("ff0000", 0.2) == Qt.rgba(1, 0, 0, 0.2),
            "resolveAvatarBg must accept hex without #");
        assert(dashTab.resolveAvatarBg("#00ff00", 1.5) == Qt.rgba(0, 1, 0, 1),
            "opacity above 1 must clamp to 1");
        assert(dashTab.resolveAvatarBg("#000000", -0.5) == Qt.rgba(0, 0, 0, 0),
            "opacity below 0 must clamp to 0");
        assert(dashTab.resolveAvatarBg("#000000", "junk") == Qt.rgba(0, 0, 0, 0.2),
            "NaN opacity must fall back to 0.2");
        assert(dashTab.resolveAvatarBg("not-a-color", 0.2) == Qt.rgba(1, 1, 1, 0.2),
            "invalid color must fall back to white");
        assert(dashTab.resolveAvatarBg(undefined, undefined) == Qt.rgba(1, 1, 1, 0.2),
            "missing values must resolve to the default white @ 0.2");
        // Harness Config is inert -> circle must show the shipped default.
        assert(dashTab.hostAvatarCircle.color == Qt.rgba(1, 1, 1, 0.2),
            "circle background must bind resolveAvatarBg (default white @ 0.2)");

        // Control: background options hidden by default, visible when enabled;
        // commits normalize to #rrggbb hex + clamped opacity.
        assert(field.showBgOptions === false && field.bgOptionsRow.visible === false,
            "background options must stay hidden unless enabled");
        assert(fieldBg.showBgOptions === true && fieldBg.bgOptionsRow.visible === true,
            "enabled instance must show the background options");
        assert(String(fieldBg.bgColor) === "#ffffff",
            "bgColor must default to white");
        assert(Math.abs(fieldBg.bgOpacity - 0.2) < 0.0001, "bgOpacity must default to 0.2");

        fieldBg.commitBg("#FF336699", 0.5);
        assert(testRoot.bgPickCount === 1 && testRoot.lastBgHex === "#336699",
            "commitBg must strip alpha and emit #rrggbb, got '" + testRoot.lastBgHex + "'");
        assert(Math.abs(testRoot.lastBgOpacity - 0.5) < 0.0001, "commitBg must pass the opacity through");
        fieldBg.commitBg("bogus", 1.7);
        assert(testRoot.lastBgHex === "#ffffff", "commitBg must fall back to white on garbage input");
        assert(testRoot.lastBgOpacity === 1, "commitBg must clamp opacity to 1");
        fieldBg.commitBg("#aabbcc", -3);
        assert(testRoot.lastBgHex === "#aabbcc" && testRoot.lastBgOpacity === 0,
            "commitBg must keep a valid hex and clamp opacity to 0");

        const imgSrc = dashTab.hostAvatarImageItem.source.toString();
        if (!configured) {
            assert(imgSrc.endsWith("theme/assets/dino.png"),
                "with no configured avatar the Image must show the bundled default art, got '" + imgSrc + "'");
        } else {
            assert(imgSrc === dashTab.resolveAvatarSource(configured),
                "with a configured avatar the Image must show it, got '" + imgSrc + "'");
        }

        // --------------------------------------------------------
        // 4. Source contracts (Config, DashboardPage, AvatarPathField,
        //    shipped defaults)
        // --------------------------------------------------------
        const cfgSrc = readLocalFile("../config/Config.qml");
        assert(cfgSrc.length > 1000, "Config.qml source must be readable");
        assert(/readonly\s+property\s+string\s+hostAvatar:/.test(cfgSrc), "Config must expose the hostAvatar getter");
        assert(/function\s+setHostAvatar\(/.test(cfgSrc), "Config must expose setHostAvatar()");
        assert(/function\s+setMediaAvatar\(/.test(cfgSrc), "Config must keep setMediaAvatar()");
        assert(/function\s+setDashboardAvatar\(/.test(cfgSrc),
            "both setters must share the durable setDashboardAvatar pipeline");
        assert(/"config",\s*"import-image"/.test(cfgSrc),
            "imports must go through the daemon's tested `config import-image`");
        assert(/"config",\s*"forget-image"/.test(cfgSrc),
            "resets must go through the ownership-guarded `config forget-image`");
        assert(/function\s+migrateAvatarPaths\(/.test(cfgSrc), "Config must expose migrateAvatarPaths()");
        assert(/root\.migrateAvatarPaths\(\)/.test(cfgSrc),
            "applySettings must run the one-time avatar migration (durable import of pre-existing paths)");
        assert(/readonly\s+property\s+var\s+dashboardAvatarFields/.test(cfgSrc),
            "the avatar field table must be declarative (key + kind per slot)");
        assert(/"key":\s*"hostAvatar",\s*"kind":\s*"host"/.test(cfgSrc),
            "hostAvatar must map to the 'host' import kind");
        assert(/"key":\s*"mediaAvatar",\s*"kind":\s*"media"/.test(cfgSrc),
            "mediaAvatar must map to the 'media' import kind");
        assert(/avatarProcComponent/.test(cfgSrc),
            "each avatar op must spawn its own process (migration and setters never queue behind each other)");
        assert(/"hostAvatar":\s*""/.test(cfgSrc),
            "defaultSettings must declare hostAvatar \"\" so the key survives deep-merge");

        const shipped = readLocalFile("../config/settings.json");
        let shippedCfg = null;
        try { shippedCfg = JSON.parse(shipped); } catch (e) {}
        assert(shippedCfg !== null, "shipped settings.json must stay valid JSON");
        assert(shippedCfg.dashboard && shippedCfg.dashboard.hostAvatar === "",
            "shipped defaults must declare dashboard.hostAvatar");

        const pageSrc = readLocalFile("../settings_gui/pages/DashboardPage.qml");
        assert(pageSrc.length > 1000, "DashboardPage.qml source must be readable");
        assert(/import Quickshell/.test(pageSrc) === false,
            "DashboardPage must not import Quickshell (keeps it instantiable under qml6)");
        assert(/Config\.setHostAvatar/.test(pageSrc), "page must persist the host avatar via Config.setHostAvatar");
        assert(/Config\.setMediaAvatar/.test(pageSrc), "page must keep persisting the media avatar via Config.setMediaAvatar");
        assert(/onPathPicked:\s*p\s*=>\s*\{\s*if\s*\(\s*!root\.testMode[^}]*Config\.setHostAvatar/.test(pageSrc),
            "setHostAvatar must stay gated behind testMode");
        assert(/onPathPicked:\s*p\s*=>\s*\{\s*if\s*\(\s*!root\.testMode[^}]*Config\.setMediaAvatar/.test(pageSrc),
            "setMediaAvatar must stay gated behind testMode");
        const fieldUses = pageSrc.split("AvatarPathField").length - 1;
        assert(fieldUses >= 2,
            "page must render both avatar cards through AvatarPathField (found " + fieldUses + " occurrences)");
        assert(/interactive:\s*!root\.testMode/.test(pageSrc),
            "the native file dialog must be disabled in testMode");

        const fieldSrc = readLocalFile("../settings_gui/controls/AvatarPathField.qml");
        assert(fieldSrc.length > 500, "AvatarPathField.qml source must be readable");
        assert(/import Quickshell/.test(fieldSrc) === false,
            "AvatarPathField must not import Quickshell (kept instantiable under qml6)");
        assert(/FileDialog/.test(fieldSrc), "AvatarPathField must offer a Browse… FileDialog");
        assert(/nameFilters/.test(fieldSrc), "FileDialog must expose image/media nameFilters");
        assert(/signal\s+pathPicked/.test(fieldSrc), "AvatarPathField must emit pathPicked");
        assert(/property\s+bool\s+interactive/.test(fieldSrc),
            "AvatarPathField must gate the dialog behind interactive (testMode)");
        assert(/fileDlg\.open\(\)/.test(fieldSrc), "Browse must open the dialog");
        assert(/Accessible\.name/.test(fieldSrc), "buttons must expose an Accessible.name");
        assert(/ColorDialog/.test(fieldSrc), "AvatarPathField must offer a color picker (ColorDialog)");
        assert(/selectedColor/.test(fieldSrc), "ColorDialog must read the picked selectedColor");
        assert(/SettingSlider/.test(fieldSrc), "transparency must reuse the existing SettingSlider");
        assert(/signal\s+bgStylePicked/.test(fieldSrc), "AvatarPathField must emit bgStylePicked");
        assert(/property\s+bool\s+showBgOptions/.test(fieldSrc),
            "background options must be opt-in (showBgOptions)");
        assert(/Qt\.alpha\(field\.bgColor, field\.bgOpacity\)/.test(fieldSrc),
            "the swatch must preview color + transparency together");
        assert(/property\s+alias\s+bgOptionsRow/.test(fieldSrc),
            "bg options row must be exposed for tests");

        assert(/function\s+setHostAvatarBgColor\(/.test(cfgSrc),
            "Config must expose setHostAvatarBgColor()");
        assert(/function\s+setHostAvatarBgOpacity\(/.test(cfgSrc),
            "Config must expose setHostAvatarBgOpacity()");
        assert(/readonly\s+property\s+string\s+hostAvatarBg:/.test(cfgSrc),
            "Config must expose the hostAvatarBg getter");
        assert(/readonly\s+property\s+real\s+hostAvatarBgOpacity:/.test(cfgSrc),
            "Config must expose the hostAvatarBgOpacity getter");
        assert(/"hostAvatarBg":\s*"#ffffff"/.test(cfgSrc),
            "defaultSettings must declare hostAvatarBg #ffffff");
        assert(/"hostAvatarBgOpacity":\s*0\.2/.test(cfgSrc),
            "defaultSettings must declare hostAvatarBgOpacity 0.2");
        assert(shippedCfg.dashboard.hostAvatarBg === "#ffffff",
            "shipped defaults must declare dashboard.hostAvatarBg #ffffff");
        assert(shippedCfg.dashboard.hostAvatarBgOpacity === 0.2,
            "shipped defaults must declare dashboard.hostAvatarBgOpacity 0.2");

        assert(/function\s+resolveAvatarBg\(/.test(tabSrc),
            "DashboardTab must expose resolveAvatarBg()");
        assert(/hostAvatarBackgroundColor/.test(tabSrc),
            "the circle color must flow through hostAvatarBackgroundColor");
        assert(/showBgOptions:\s*true/.test(pageSrc),
            "the host avatar card must enable the background options");
        assert((pageSrc.match(/showBgOptions:\s*true/g) || []).length === 1,
            "only the host avatar card enables background options (media keeps its own component)");
        assert(/onBgStylePicked:\s*\([^)]*\)\s*=>\s*\{\s*if\s*\(\s*!root\.testMode[^}]*Config\.setHostAvatarBgColor/.test(pageSrc),
            "bg color commits must stay gated behind testMode");
        assert(/Config\.setHostAvatarBgOpacity/.test(pageSrc),
            "page must persist the opacity via Config.setHostAvatarBgOpacity");

        console.log("PASS: Configurable host avatar (control runtime, rendering, durable-import source contracts)");
        Qt.exit(0);
    }
}
