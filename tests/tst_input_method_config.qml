import QtQuick
import "../modules/Astral/Kernel/services/InputMethods.js" as InputMethods

/// The dock's input-method drawer must be configuration, not a constant.
///
/// It used to read `KbLayoutService`, whose `layouts` was hardcoded to `["US"]`
/// and which only asked KDE for the current index. With fcitx5 (the documented
/// IME switcher) that meant: the drawer showed "US", the "Switch" button called
/// KDE's `switchToNextLayout` (a no-op with one layout), the user's added
/// methods (e.g. Rime) never appeared, and there was no way into the IME's
/// settings. This suite pins the config-driven contract:
///
/// 1. The pure parser turns the real fcitx5 / KDE DBus payloads into items.
/// 2. The badge (dock glyph) comes from each method's own label.
/// 3. The service queries fcitx5 first, KDE second, and can open settings.
/// 4. The drawer renders that list and the settings entry, with no "US".
Item {
    id: testRoot
    width: 600
    height: 800

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function codeOnly(src) {
        let out = "";
        let i = 0;
        const n = src.length;
        while (i < n) {
            const c = src[i];
            const d = src[i + 1];
            if (c === "/" && d === "/") {
                while (i < n && src[i] !== "\n") i++;
            } else if (c === "/" && d === "*") {
                i += 2;
                while (i < n && !(src[i] === "*" && src[i + 1] === "/")) i++;
                i += 2;
            } else if (c === "\"" || c === "'") {
                const quote = c;
                i++;
                while (i < n && src[i] !== quote) {
                    if (src[i] === "\\") i++;
                    i++;
                }
                i++;
            } else {
                out += c;
                i++;
            }
        }
        return out;
    }

    /// Removes comments but keeps string literals, so prose cannot satisfy a
    /// "does not hardcode X" check while the actual literal still can fail it.
    function stripComments(src) {
        let out = "";
        let i = 0;
        const n = src.length;
        while (i < n) {
            const c = src[i];
            const d = src[i + 1];
            if (c === "/" && d === "/") {
                while (i < n && src[i] !== "\n") i++;
            } else if (c === "/" && d === "*") {
                i += 2;
                while (i < n && !(src[i] === "*" && src[i + 1] === "/")) i++;
                i += 2;
            } else if (c === "\"" || c === "'") {
                const quote = c;
                out += c;
                i++;
                while (i < n && src[i] !== quote) {
                    out += src[i];
                    if (src[i] === "\\") { i++; out += src[i]; }
                    i++;
                }
                out += quote;
                i++;
            } else {
                out += c;
                i++;
            }
        }
        return out;
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

    Component.onCompleted: {
        console.log("RUNNING: Input Method Drawer Is Configuration Driven");

        // -------------------------------------------------------------
        // 1. fcitx5 group payload -> items
        // Real output of:
        //   busctl --user call org.fcitx.Fcitx5 /controller \
        //     org.fcitx.Fcitx.Controller1 FullInputMethodGroupInfo s Default --json=short
        // -------------------------------------------------------------
        const fcitxGroup = '{"type":"sssa{sv}a(sssssssbsa{sv})","data":["Default","rime","us",{},['
            + '["keyboard-us","Keyboard - English (US)","","input-keyboard","en","en","keyboard",true,"",{}],'
            + '["rime","Rime","","fcitx-rime","ㄓ","zh","rime",true,"",{}]]]}';
        const group = InputMethods.parseFcitx5GroupInfo(fcitxGroup);
        assert(group !== null, "a valid fcitx5 group payload must parse");
        assert(group.items.length === 2, "both configured methods must be listed, got " + group.items.length);
        assert(group.items[0].id === "keyboard-us", "the first item id must be keyboard-us");
        assert(group.items[0].name === "Keyboard - English (US)", "the first item name must be the configured name");
        assert(group.items[0].badge === "EN", "the keyboard badge must come from its label, got " + group.items[0].badge);
        assert(group.items[1].id === "rime", "the second item id must be rime");
        assert(group.items[1].name === "Rime", "the second item name must be Rime");
        assert(group.items[1].badge === "ㄓ", "the Rime badge must keep its native label, got " + group.items[1].badge);
        assert(group.items[1].icon === "fcitx-rime", "the item icon must come from the payload");

        // Current method payload
        assert(InputMethods.parseFcitx5Current('{"type":"s","data":["rime"]}') === "rime",
            "the current method must parse from CurrentInputMethod");
        assert(InputMethods.parseFcitx5Current("") === "", "an empty current payload must not invent a method");

        // -------------------------------------------------------------
        // 2. KDE layouts payload -> items (fallback when no fcitx5)
        // -------------------------------------------------------------
        const kdeLayouts = '{"type":"a(sss)","data":[[["us","","English (US)"],["de","","German"]]]}';
        const kde = InputMethods.parseKdeLayouts(kdeLayouts);
        assert(kde.length === 2, "KDE layouts must parse into items, got " + kde.length);
        assert(kde[0].id === "us" && kde[0].name === "English (US)", "KDE layout id/name must be preserved");
        assert(kde[1].badge === "DE", "the KDE badge must derive from the layout id");

        // -------------------------------------------------------------
        // 3. Badges never fabricate a language
        // -------------------------------------------------------------
        assert(InputMethods.badgeFor("", "keyboard-gb") === "GB", "an empty label must fall back to the id suffix");
        assert(InputMethods.badgeFor("", "custom") === "CU", "an unknown id must fall back to its first two characters");
        assert(InputMethods.badgeFor("zh", "anything") === "ZH", "a language label must be uppercased");

        // -------------------------------------------------------------
        // 4. Active index resolution
        // -------------------------------------------------------------
        assert(InputMethods.activeIndex(group.items, "rime") === 1, "the active index must follow the current id");
        assert(InputMethods.activeIndex(group.items, "missing") === -1, "an unknown current id must not select a row");

        // -------------------------------------------------------------
        // 5. Malformed payloads degrade to "no items", never to a fake list
        // -------------------------------------------------------------
        assert(InputMethods.parseFcitx5GroupInfo("not json").items.length === 0,
            "malformed fcitx5 output must yield no items");
        assert(InputMethods.parseFcitx5GroupInfo('{"data":[]}').items.length === 0,
            "a payload without an item list must yield no items");
        assert(InputMethods.parseKdeLayouts("{}").length === 0,
            "malformed KDE output must yield no items");

        // -------------------------------------------------------------
        // 6. Service contract: real sources, not a constant
        // -------------------------------------------------------------
        const serviceSrc = readLocalFile("../modules/Astral/Kernel/services/InputMethodService.qml");
        assert(serviceSrc.length > 1000, "InputMethodService.qml must exist");
        // The DBus method names are string literals inside command arrays, so
        // these checks run on the raw source.
        assert(serviceSrc.indexOf("FullInputMethodGroupInfo") >= 0,
            "the service must read the configured fcitx5 group");
        assert(serviceSrc.indexOf("SetCurrentIM") >= 0,
            "the service must switch the fcitx5 input method");
        assert(serviceSrc.indexOf("getLayoutsList") >= 0,
            "the service must read KDE's configured layouts");
        assert(serviceSrc.indexOf("Configure") >= 0,
            "the service must open the IME's own settings");
        const serviceCode = stripComments(serviceSrc);
        assert(serviceCode.indexOf("layouts: [") < 0,
            "the service must not hardcode a layout list");
        assert(serviceCode.indexOf("\"US\"") < 0,
            "the service must not hardcode US");

        // -------------------------------------------------------------
        // 7. Drawer contract: list + settings, no hardcoded Switch card
        // -------------------------------------------------------------
        const fusedSrc = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        const fusedCode = codeOnly(fusedSrc);
        const listSrc = readLocalFile("../modules/Astral/Kernel/components/InputMethodList.qml");
        const listCode = codeOnly(listSrc);
        assert(fusedCode.indexOf("InputMethodList") >= 0,
            "the drawer must render the shared input-method list");
        assert(fusedCode.indexOf("KbLayoutService") < 0,
            "the drawer must not use the retired KbLayoutService");
        assert(listCode.indexOf("InputMethodService.items") >= 0,
            "the list must render the configured input methods");
        assert(listCode.indexOf("InputMethodService.setLayout") >= 0,
            "clicking a method must switch to it");
        assert(listCode.indexOf("InputMethodService.openSettings") >= 0,
            "the list must offer the IME settings entry");

        const dockSrc = readLocalFile("../dock/components/DockStatusIcons.qml");
        const dockCode = codeOnly(dockSrc);
        assert(dockCode.indexOf("InputMethodService.badge") >= 0,
            "the dock icon must show the active method's own badge");
        assert(dockCode.indexOf("KbLayoutService") < 0,
            "the dock icon must not use the retired KbLayoutService");

        console.log("PASS: Input Method Drawer Is Configuration Driven");
        Qt.exit(0);
    }
}
