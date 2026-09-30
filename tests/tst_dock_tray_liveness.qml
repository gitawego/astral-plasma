import QtQuick

// ============================================================================
// Dock taskbar + tray liveness contracts
// ============================================================================
// Two regressions the dock must never repeat:
//
// 1. A running application was drawn with a generic glyph because the daemon
//    only trusted `_NET_WM_ICON` for window classes ending in `.exe`. Proton and
//    Steam games run as `steam_app_default`, so the game sat in the taskbar as an
//    anonymous box while the user hunted for "an app that is running but not
//    shown".
// 2. The tray was a snapshot: the daemon queried the StatusNotifierWatcher once
//    at startup and after a tray click, so any icon that appeared later (Steam, a
//    download manager, a game) stayed invisible in the dock until an unrelated
//    click happened to refresh it.
Item {
    id: testRoot
    width: 800
    height: 600

    property string windowIconsSource: ""
    property string trayAdapterSource: ""
    property string trayPortSource: ""
    property string watchEventsSource: ""
    property string dockSource: ""

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function assert(cond, msg) {
        if (!cond) {
            console.log("FAIL: " + msg);
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    function slice(text, from, to) {
        const start = text.indexOf(from);
        if (start < 0) return "";
        const end = to ? text.indexOf(to, start) : -1;
        return end < 0 ? text.substring(start) : text.substring(start, end);
    }

    Component.onCompleted: {
        windowIconsSource = readLocalFile("../daemon/src/infrastructure/window_icons.rs");
        trayAdapterSource = readLocalFile("../daemon/src/infrastructure/tray_adapter.rs");
        trayPortSource = readLocalFile("../daemon/src/domain/ports.rs");
        watchEventsSource = readLocalFile("../daemon/src/application/watch_events.rs");
        dockSource = readLocalFile("../shell/UnifiedDock.qml");

        // ---------------------------------------------------------------- 1 ---
        // The icon gate judges whether the resolved icon is drawable, never the
        // shape of the window class.
        const gate = slice(windowIconsSource, "pub fn should_extract_window_icon", "\n}\n");
        assert(gate.length > 0, "window_icons.rs must expose should_extract_window_icon");
        assert(
            gate.indexOf("ends_with(\".exe\")") < 0,
            "the extraction gate must not key off a `.exe` class suffix: Proton/Steam games run as steam_app_default"
        );
        assert(
            gate.indexOf("theme_icon_exists") >= 0,
            "the gate must ask whether the icon theme can draw the resolved name"
        );
        assert(
            windowIconsSource.indexOf("pub fn theme_icon_exists_in") >= 0,
            "the icon-theme lookup must stay testable against explicit roots"
        );
        assert(
            windowIconsSource.indexOf("pub fn theme_icon_exists(") >= 0,
            "production lookups must go through the memoized icon-theme index"
        );

        // ---------------------------------------------------------------- 2 ---
        // The tray is a live list: cheap registration poll, full query only when
        // the set changed, and the pushed list stays the comparison baseline.
        assert(
            trayAdapterSource.indexOf("pub fn split_registration") >= 0,
            "the registration split must be shared by the query and the poll or their identities drift"
        );
        assert(
            trayAdapterSource.indexOf("fn registered_item_keys") >= 0,
            "the tray port must expose a cheap registration read"
        );
        const trayPort = slice(trayPortSource, "pub trait TrayPort", "\n}");
        assert(
            trayPort.indexOf("fn query_tray") >= 0 && trayPort.indexOf("fn registered_item_keys") >= 0,
            "the tray port trait must carry both the query and the registration read"
        );
        assert(
            watchEventsSource.indexOf("TRAY_REGISTRATION_POLL") >= 0 &&
                watchEventsSource.indexOf("refresh_tray_if_registrations_changed") >= 0,
            "the watcher must poll registrations and re-push the tray when they change"
        );
        assert(
            slice(watchEventsSource, "async fn refresh_tray(", "async fn refresh_tray_if").indexOf(
                "tray_registered_keys = tray_item_keys") >= 0,
            "every push must re-baseline the registration keys it reflects"
        );
        assert(
            watchEventsSource.indexOf("TRAY_REGISTRATION_POLL: Duration") >= 0,
            "the registration poll interval must be a named constant"
        );
        assert(
            watchEventsSource.indexOf("tray_registered_keys") >= 0 &&
                watchEventsSource.indexOf("pub fn tray_registrations_changed") >= 0,
            "change detection must compare normalized registration sets"
        );

        // ---------------------------------------------------------------- 3 ---
        // The dock renders every tray item the daemon pushes - no hidden status
        // filter, no silent cap - so an icon that is running is an icon visible.
        assert(
            dockSource.indexOf("model: WindowService.tray") >= 0,
            "the dock tray must be driven by the pushed tray list"
        );
        assert(
            dockSource.indexOf("visible: WindowService.tray.length > 0") >= 0,
            "the tray must render whenever the daemon reports items"
        );
        assert(
            dockSource.indexOf("source: Config.iconUrl(modelData.rawIcon)") >= 0 &&
                dockSource.indexOf("materialIcon: modelData.materialIcon") >= 0,
            "tray glyphs must chain the raw icon, its URL and the material fallback"
        );
        assert(
            dockSource.indexOf("visible: !imBadgeText.visible") >= 0,
            "an input method keeps its badge instead of a duplicate glyph"
        );

        console.log("PASS: dock taskbar + tray liveness contracts");
        Qt.exit(0);
    }
}
