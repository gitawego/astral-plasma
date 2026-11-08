pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "InputMethods.js" as InputMethods

/// The session's input methods / keyboard layouts, read from the owner.
///
/// The dock used to hardcode `["US"]` and ask KDE to switch layouts. On a
/// fcitx5 session that is the wrong service: the added methods (Rime, Pinyin,
/// ...) live in fcitx5's input-method group, the KDE layout list only holds the
/// base layout, and `switchToNextLayout` is a no-op with one layout. This
/// singleton reads fcitx5 first (its configured group, current method, and the
/// method's own compact label), falls back to KDE's `getLayoutsList`, and
/// exposes one list + switch/settings API to the drawer and the dock icon.
///
/// Everything is ground truth from the running framework: no layout names,
/// badges, or counts are written in QML. If neither framework answers, the list
/// stays empty and the dock hides the icon instead of showing a dead "US".
Singleton {
    id: root

    /// "fcitx5", "kde", or "none".
    property string framework: "none"
    /// [{ id, name, badge, icon, language, addon, keyboard, enabled }]
    property var items: []
    property int currentIndex: -1
    property string currentId: ""
    property string currentName: ""
    /// Compact glyph for the dock icon, taken from the active method.
    property string badge: ""

    /// A refresh requested while another was in flight (drawer opened, timer
    /// ticked, switch confirmed) must not be dropped - it re-runs when the
    /// current chain finishes so the drawer never opens on a stale active row.
    property bool refreshPending: false

    readonly property bool available: items.length > 0
    readonly property bool canSwitch: items.length > 1
    readonly property string title: framework === "kde" ? "Keyboard Layouts" : "Input Methods"
    readonly property string settingsLabel: framework === "fcitx5"
        ? "fcitx5 Settings"
        : (framework === "kde" ? "Keyboard Settings" : "Input Method Settings")

    function setUnavailable() {
        root.framework = "none";
        root.items = [];
        root.currentIndex = -1;
        root.currentId = "";
        root.currentName = "";
        root.badge = "";
    }

    function applyCurrent(id) {
        root.currentId = id ? String(id) : "";
        root.currentIndex = InputMethods.activeIndex(root.items, root.currentId);
        if (root.currentIndex >= 0) {
            const item = root.items[root.currentIndex];
            root.currentName = item.name;
            root.badge = item.badge;
        } else if (root.items.length > 0) {
            // The framework answered with a list but no current method: show the
            // first glyph so the icon is not blank, but mark no row active.
            root.currentName = "";
            root.badge = root.items[0].badge;
        } else {
            root.currentName = "";
            root.badge = "";
        }
    }

    function applyCurrentIndex(index) {
        if (index >= 0 && index < root.items.length) {
            root.applyCurrent(root.items[index].id);
        } else {
            root.applyCurrent("");
        }
    }

    function refresh() {
        if (probeFcitx.running || fcitxGroupInfo.running || fcitxCurrent.running
                || kdeLayouts.running || kdeCurrent.running) {
            root.refreshPending = true;
            return;
        }
        probeFcitx.running = true;
    }

    function finishRefresh() {
        if (root.refreshPending) {
            root.refreshPending = false;
            root.refresh();
        }
    }

    function nextLayout() {
        if (root.items.length < 2) return;
        const next = (root.currentIndex + 1) % root.items.length;
        root.setLayout(next < 0 ? 0 : next);
    }

    function setLayout(index) {
        if (!(index >= 0 && index < root.items.length)) return;
        const item = root.items[index];
        if (root.framework === "fcitx5") {
            setFcitxIM.command = ["busctl", "--user", "call", "org.fcitx.Fcitx5", "/controller",
                "org.fcitx.Fcitx.Controller1", "SetCurrentIM", "s", item.id];
            setFcitxIM.running = true;
            // Immediate feedback; the refresh below confirms it against the daemon.
            root.applyCurrent(item.id);
        } else if (root.framework === "kde") {
            setKdeLayout.command = ["busctl", "--user", "call", "org.kde.keyboard", "/Layouts",
                "org.kde.KeyboardLayouts", "setLayout", "u", String(index)];
            setKdeLayout.running = true;
            root.applyCurrentIndex(index);
        }
    }

    function openSettings() {
        if (root.framework === "fcitx5") {
            settingsProc.command = ["busctl", "--user", "call", "org.fcitx.Fcitx5", "/controller",
                "org.fcitx.Fcitx.Controller1", "Configure"];
            settingsProc.running = true;
        } else if (root.framework === "kde") {
            Quickshell.execDetached(["kcmshell6", "kcm_keyboard"]);
        }
    }

    // --- fcitx5 ---------------------------------------------------------

    Process {
        id: probeFcitx
        command: ["busctl", "--user", "call", "org.fcitx.Fcitx5", "/controller",
            "org.fcitx.Fcitx.Controller1", "CurrentInputMethodGroup", "--json=short"]
        stdout: StdioCollector { id: probeFcitxOut }
        onExited: (code, status) => {
            const group = code === 0 ? InputMethods.parseFcitx5Current(probeFcitxOut.text) : "";
            if (group === "") {
                kdeLayouts.running = true;
                return;
            }
            root.framework = "fcitx5";
            fcitxGroupInfo.command = ["busctl", "--user", "call", "org.fcitx.Fcitx5", "/controller",
                "org.fcitx.Fcitx.Controller1", "FullInputMethodGroupInfo", "s", group, "--json=short"];
            fcitxGroupInfo.running = true;
        }
    }

    Process {
        id: fcitxGroupInfo
        stdout: StdioCollector { id: fcitxGroupOut }
        onExited: (code, status) => {
            const parsed = code === 0 ? InputMethods.parseFcitx5GroupInfo(fcitxGroupOut.text)
                                      : { items: [] };
            if (!parsed || parsed.items.length === 0) {
                // fcitx5 answered but its group is empty: let KDE have a turn.
                root.framework = "none";
                root.items = [];
                kdeLayouts.running = true;
                return;
            }
            root.items = parsed.items;
            fcitxCurrent.running = true;
        }
    }

    Process {
        id: fcitxCurrent
        command: ["busctl", "--user", "call", "org.fcitx.Fcitx5", "/controller",
            "org.fcitx.Fcitx.Controller1", "CurrentInputMethod", "--json=short"]
        stdout: StdioCollector { id: fcitxCurrentOut }
        onExited: (code, status) => {
            root.applyCurrent(code === 0 ? InputMethods.parseFcitx5Current(fcitxCurrentOut.text) : "");
            root.finishRefresh();
        }
    }

    Process {
        id: setFcitxIM
        onExited: (code, status) => {
            confirmTimer.restart();
        }
    }

    Process {
        id: settingsProc
        onExited: (code, status) => {
            // `Configure` is a no-op when the daemon cannot spawn its config
            // tool; fall back to the documented binary so the entry still works.
            if (code !== 0) Quickshell.execDetached(["fcitx5-configtool"]);
        }
    }

    // --- KDE keyboard layouts (fallback) --------------------------------

    Process {
        id: kdeLayouts
        command: ["busctl", "--user", "call", "org.kde.keyboard", "/Layouts",
            "org.kde.KeyboardLayouts", "getLayoutsList", "--json=short"]
        stdout: StdioCollector { id: kdeLayoutsOut }
        onExited: (code, status) => {
            const parsed = code === 0 ? InputMethods.parseKdeLayouts(kdeLayoutsOut.text) : [];
            if (parsed.length === 0) {
                root.setUnavailable();
                root.finishRefresh();
                return;
            }
            root.framework = "kde";
            root.items = parsed;
            kdeCurrent.running = true;
        }
    }

    Process {
        id: kdeCurrent
        command: ["busctl", "--user", "call", "org.kde.keyboard", "/Layouts",
            "org.kde.KeyboardLayouts", "getLayout", "--json=short"]
        stdout: StdioCollector { id: kdeCurrentOut }
        onExited: (code, status) => {
            root.applyCurrentIndex(code === 0 ? InputMethods.parseKdeCurrent(kdeCurrentOut.text) : -1);
            root.finishRefresh();
        }
    }

    Process {
        id: setKdeLayout
        onExited: (code, status) => {
            confirmTimer.restart();
        }
    }

    // Switching is asynchronous; re-read the framework's answer shortly after
    // the call so the list never keeps an optimistic state that did not happen.
    Timer {
        id: confirmTimer
        interval: 150
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
