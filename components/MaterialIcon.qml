import QtQuick
import "../theme"

Item {
    id: root

    property string text: ""
    property string iconName: ""
    property color color: Colors.m3onSurface
    property int size: 18

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    // Map common material names to clean symbols/unicode or Nerd Font glyphs
    readonly property var symbolMap: ({
        "dashboard": "󰕮",
        "media": "󰝚",
        "queue_music": "󰝚",
        "performance": "󰓅",
        "speed": "󰓅",
        "workspaces": "󱂬",
        "grid_view": "󱂬",
        "laptop_mac": "󰌢",
        "computer": "󰌢",
        "wifi": "󰤨",
        "wifi_off": "󰤭",
        "bluetooth": "󰂯",
        "bluetooth_off": "󰂲",
        "volume_up": "󰕾",
        "volume_down": "󰖀",
        "volume_mute": "󰖁",
        "brightness": "󰃠",
        "brightness_6": "󰃠",
        "brightness_5": "󰃠",
        "brightness_7": "󰃠",
        "brightness_medium": "󰃠",
        "battery": "󰁹",
        "battery_charging": "󰂄",
        "battery_charging_full": "󰂄",
        "battery_alert": "󰂃",
        "battery_full": "󰁹",
        "language": "󰌌",
        "settings": "󰒓",
        "power": "󰐥",
        "power_settings_new": "󰐥",
        "search": "󰍉",
        "close": "󰅖",
        "play": "󰐊",
        "play_arrow": "󰐊",
        "pause": "󰏤",
        "prev": "󰒮",
        "skip_previous": "󰒮",
        "next": "󰒭",
        "skip_next": "󰒭",
        "arrow_drop_up": "▲",
        "expand_less": "󰅃",
        "expand_more": "󰅀",
        "info": "󰋽",
        "info_outline": "󰋽",
        "notifications": "󰂚",
        "notifications_active": "󰂚",
        "notifications_none": "󰂜",
        "spotify": "󰓇",
        "weather_clear": "󰖙",
        "weather_cloudy": "󰖐",
        "weather_rain": "󰖖",
        "calendar": "󰸗",
        "calendar_today": "󰸗",
        "calendar_month": "󰸗",
        "clock": "󰥔",
        "bedtime": "󰽥",
        "web_asset": "󰖯",
        "radio_button_unchecked": "󰄰",
        "circle": "󰝥",
        "navigation": "󰍎",
        "visibility": "󰈈",
        "chat": "󰭹",
        "music_note": "󰝚",
        "energy_savings_leaf": "󰌪",
        "eco": "󰌪",
        "balance": "󱡊",
        "rocket_launch": "󰓅",
        "desktop_windows": "󰍹",
        "headphones": "󰋋",
        "devices": "󰌢",
        "send": "󰒭",
        "history": "󰋚",
        "lan": "󰌘",
        "extension": "󰏖",
        "help": "󰋖",
        "speaker": "󰕾",
        "lock": "󰌾",
        "logout": "󰍃",
        "restart_alt": "󰑓",
        "terminal": "󰆍",
        "code": "󰅩",
        "folder": "󰉋",
        "movie": "󰿎",
        "sports_esports": "󰊴",
        "insights": "󰄧",
        "smart_toy": "󰚩",
        "palette": "󰏘",
        "window": "󰖯",
        "toll": "󰇂",
        "cloud": "󰅟",
        "keyboard": "󰌌",
        "system_update": "󰚰",
        "cast": "󱒃",
        "desktop": "󰍹",
        "translate": "󰗊",
        "fcitx": "󰌌",
        "rime": "󰗊",
        "push_pin": "󰐃",
        "pin": "󰐃",
        "keep_off": "󰐄",
        "unpin": "󰐄",
        "open_in_new": "󰏌",
        "launch": "󰏌",
        "picture_in_picture": "󰹩",
        "sync": "󰑓"
    })

    readonly property string displaySymbol: {
        if (symbolMap[text]) return symbolMap[text];
        if (text && text.length <= 2) return text;
        return text ? text.charAt(0).toUpperCase() : "";
    }

    Loader {
        anchors.fill: parent
        active: root.iconName !== ""
        sourceComponent: Image {
            source: root.iconName.startsWith("/") || root.iconName.startsWith("file:") 
                ? root.iconName 
                : "image://icon/" + root.iconName
            sourceSize.width: root.size
            sourceSize.height: root.size
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    Text {
        anchors.centerIn: parent
        width: root.size
        height: root.size
        visible: root.iconName === ""
        text: root.displaySymbol
        color: root.color
        font.pixelSize: root.size
        font.family: "JetBrainsMono Nerd Font Propo"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
