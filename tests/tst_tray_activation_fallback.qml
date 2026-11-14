import QtQuick
import "../modules/Astral/Kernel/services/TrayActivation.js" as TrayActivation

// Open-like tray menu actions get a generic raise fallback: find the tray
// item's window and activate it after the app's dbusmenu click. Quit/Disable
// actions must never pull a window forward, and matching must not hard-code an
// application identity.
Item {
    id: testRoot

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
        console.log("RUNNING: Tray Activation Fallback Tests");

        assert(TrayActivation.opensWindow("Open Telegram") === true, "Open is an open-like action");
        assert(TrayActivation.opensWindow("Show window") === true, "Show is an open-like action");
        assert(TrayActivation.opensWindow("Bring to Front") === true, "Bring is an open-like action");
        assert(TrayActivation.opensWindow("Quit Telegram") === false, "Quit must not raise a window");
        assert(TrayActivation.opensWindow("Disable notifications") === false, "Disable must not raise a window");

        const windows = [
            { id: "t1", appId: "org.telegram.desktop", appName: "Telegram", desktopFile: "org.telegram.desktop", title: "Telegram (275270)" },
            { id: "v1", appId: "com.microsoft.VSCode", appName: "Code", desktopFile: "code", title: "README.md - Visual Studio Code" }
        ];
        const telegramTray = { id: "TelegramDesktop", title: "TelegramDesktop", service: ":1.327512" };
        const match = TrayActivation.windowForTray(telegramTray, windows);
        assert(match !== null && match.id === "t1", "TelegramDesktop tray item maps to the Telegram window");

        const musicTray = { id: "cloudmusic", title: "NetEase", service: ":1.323" };
        assert(TrayActivation.windowForTray(musicTray, windows) === null,
            "unrelated tray items do not steal another app's window");

        assert(TrayActivation.windowForTray({ id: "TelegramDesktop" }, []) === null,
            "no windows means no activation");
        assert(TrayActivation.windowForTray(null, windows) === null,
            "no tray item means no activation");

        console.log("PASS: Tray Activation Fallback Tests");
        Qt.exit(0);
    }
}
