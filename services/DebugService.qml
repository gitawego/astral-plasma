pragma Singleton

import QtQuick
import "../config"

Item {
    id: root

    // Master debug state strictly gated by Config.debugMode
    readonly property bool active: (typeof Config !== "undefined") ? Config.debugMode : false
    readonly property bool freezeAutoClose: active

    function log(category, message) {
        if (active) {
            console.log("[DEBUG:" + category + "] " + message);
        }
    }
}
