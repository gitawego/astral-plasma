import QtQuick

Item {
    id: testRoot
    width: 800
    height: 600

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

    Component.onCompleted: {
        console.log("RUNNING: Clipboard & Notification Center Integration Tests");

        const clipServiceSrc = readLocalFile("../services/ClipboardService.qml");
        const notifServiceSrc = readLocalFile("../services/NotificationService.qml");
        const statusIconsSrc = readLocalFile("../dock/components/DockStatusIcons.qml");
        const fusedPopoutSrc = readLocalFile("../dock/popouts/FusedBottomPopout.qml");
        const settingsSrc = readLocalFile("../config/settings.json");

        // 1. ClipboardService contracts
        assert(clipServiceSrc.length > 200, "services/ClipboardService.qml must exist and be readable");
        assert(clipServiceSrc.indexOf("property var history") >= 0,
            "ClipboardService must expose `history` array");
        assert(clipServiceSrc.indexOf("property string currentText") >= 0,
            "ClipboardService must expose `currentText`");
        assert(clipServiceSrc.indexOf("function refresh()") >= 0,
            "ClipboardService must define `refresh()`");
        assert(clipServiceSrc.indexOf("function setClipboard(") >= 0,
            "ClipboardService must define `setClipboard(text)`");
        assert(clipServiceSrc.indexOf("function clearHistory()") >= 0,
            "ClipboardService must define `clearHistory()`");
        assert(clipServiceSrc.indexOf("org.kde.klipper") >= 0,
            "ClipboardService must integrate with KDE Klipper via DBus");

        // 2. NotificationService history contracts
        assert(notifServiceSrc.indexOf("property var history") >= 0,
            "NotificationService must declare `history` list");
        assert(notifServiceSrc.indexOf("property int unreadCount") >= 0,
            "NotificationService must declare `unreadCount`");
        assert(notifServiceSrc.indexOf("function clearHistory()") >= 0,
            "NotificationService must declare `clearHistory()`");
        assert(notifServiceSrc.indexOf("function removeHistoryItem(") >= 0,
            "NotificationService must declare `removeHistoryItem(index)`");
        assert(notifServiceSrc.indexOf("function markAllRead()") >= 0,
            "NotificationService must declare `markAllRead()`");

        // 3. DockStatusIcons trigger wiring
        assert(statusIconsSrc.indexOf("clipboardItem") >= 0,
            "DockStatusIcons.qml must declare `clipboardItem`");
        assert(statusIconsSrc.indexOf("notifBellItem") >= 0,
            "DockStatusIcons.qml must declare `notifBellItem`");
        assert(statusIconsSrc.indexOf("\"clipboard\"") >= 0,
            "DockStatusIcons.qml must trigger clipboard popout");
        assert(statusIconsSrc.indexOf("\"notifications\"") >= 0,
            "DockStatusIcons.qml must trigger notifications popout");
        assert(statusIconsSrc.indexOf("unreadCount") >= 0,
            "DockStatusIcons.qml must show notification unread indicator");

        assert(statusIconsSrc.indexOf("brightnessItem") >= 0,
            "DockStatusIcons.qml must declare `brightnessItem`");
        assert(statusIconsSrc.indexOf("kbItem") >= 0,
            "DockStatusIcons.qml must declare `kbItem`");
        assert(statusIconsSrc.indexOf("batteryItem") >= 0,
            "DockStatusIcons.qml must declare `batteryItem`");

        // 4. FusedBottomPopout presentation contracts
        assert(fusedPopoutSrc.indexOf("case \"clipboard\":") >= 0,
            "FusedBottomPopout.qml must support `clipboard` mode");
        assert(fusedPopoutSrc.indexOf("case \"notifications\":") >= 0,
            "FusedBottomPopout.qml must support `notifications` mode");
        assert(fusedPopoutSrc.indexOf("case \"brightness\":") >= 0,
            "FusedBottomPopout.qml must support `brightness` mode");
        assert(fusedPopoutSrc.indexOf("case \"kblayout\":") >= 0,
            "FusedBottomPopout.qml must support `kblayout` mode");
        assert(fusedPopoutSrc.indexOf("clipboardSection") >= 0,
            "FusedBottomPopout.qml must define `clipboardSection`");
        assert(fusedPopoutSrc.indexOf("notificationsSection") >= 0,
            "FusedBottomPopout.qml must define `notificationsSection`");
        assert(fusedPopoutSrc.indexOf("brightnessSection") >= 0,
            "FusedBottomPopout.qml must define `brightnessSection`");
        assert(fusedPopoutSrc.indexOf("kbLayoutSection") >= 0,
            "FusedBottomPopout.qml must define `kbLayoutSection`");

        // 5. Settings configuration contract
        assert(settingsSrc.indexOf("\"id\": \"clipboard\"") >= 0,
            "settings.json must configure clipboard statusIcon");
        assert(settingsSrc.indexOf("\"id\": \"notifications\"") >= 0,
            "settings.json must configure notifications statusIcon");
        assert(settingsSrc.indexOf("\"id\": \"brightness\"") >= 0,
            "settings.json must configure brightness statusIcon");
        assert(settingsSrc.indexOf("\"id\": \"kblayout\"") >= 0,
            "settings.json must configure kblayout statusIcon");

        console.log("PASS: Full Status Parity & Notification Center Integration Tests");
        Qt.exit(0);
    }
}
