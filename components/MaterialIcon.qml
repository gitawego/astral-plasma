import QtQuick
import "../theme"
import "../config"

Item {
    id: root

    property string text: ""
    property string iconName: ""
    property color color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#F3EDF6"
    property int size: 18

    readonly property string iconKey: root.text !== "" ? root.text : root.iconName
    readonly property bool hasIcon: displaySymbol !== "" || resolvedIconUrl !== ""
    visible: hasIcon
    implicitWidth: hasIcon ? size : 0
    implicitHeight: hasIcon ? size : 0
    width: hasIcon ? size : 0
    height: hasIcon ? size : 0

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
        "dark_mode": "󰖔",
        "bedtime": "󰖔",
        "nightlight": "󰖔",
        "light_mode": "󰖙",
        "wb_sunny": "󰖙",
        "sunny": "󰖙",
        "contrast": "󰃠",
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
        "shuffle": "󰒝",
        "repeat": "󰑖",
        "repeat_one": "󰑗",
        "arrow_drop_up": "▲",
        "arrow_drop_down": "▼",
        "swap_horiz": "󰁯",
        "expand_less": "󰅃",
        "expand_more": "󰅀",
        // NOTE: no microphone glyph is mapped here on purpose.
        //
        // The Material Design Icons private-use codepoints for `microphone` and
        // `timer-sand` are absent from the JetBrains Mono Nerd Font build this
        // shell ships, and adding them anyway renders the *wrong* shapes (a
        // factory silhouette and a pair of bars) rather than a missing-glyph box.
        // That was verified by rendering the component, not by checking that the
        // codepoint exists in the cmap -- presence is not identity.
        //
        // Voice input therefore uses the vector-drawn `MicVocalIcon` (Lucide),
        // not a font glyph. Do not "fix" this by pasting in Material Symbols
        // names either: QtQuick.Controls and the Material Symbols font are not
        // part of this shell.
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
        "graphic_eq": "󰺢",
        "equalizer": "󰺢",
        "waveform": "󱑽",
        "album": "󰀥",
        "disc": "󰀥",
        "energy_savings_leaf": "󰌪",
        "eco": "󰌪",
        "balance": "󱡊",
        "rocket_launch": "󰓅",
        "desktop_windows": "󰍹",
        "headphones": "󰋋",
        "devices": "󰌢",
        "attach_file": "󰁦",
        "attachment": "󰁦",
        "image": "󰋩",
        "photo": "󰋩",
        "content_copy": "󰆏",
        "copy": "󰆏",
        "schema": "󰅩",
        "visibility_off": "󰈉",
        "send": "󰒭",
        "history": "󰋚",
        "lan": "󰌘",
        "extension": "󰏖",
        "help": "󰋖",
        "speaker": "󰓃",
        "lock": "󰌾",
        "logout": "󰍃",
        "exit_to_app": "󰈆",
        "exit": "󰈆",
        "quit": "󰈆",
        "restart_alt": "󰑓",
        "terminal": "󰆍",
        "code": "󰅩",
        "folder": "󰉋",
        "folder_open": "󰉋",
        "file_open": "󰏌",
        "movie": "󰿎",
        "sports_esports": "󰊴",
        "insights": "󰄧",
        "smart_toy": "󰚩",
        "auto_awesome": "󰄧",
        "psychology": "󰧑",
        "brain": "󰧑",
        "token": "\uf51e",
        "tokens": "\uf51e",
        "spark": "󰄧",
        "sparkles": "󰄧",
        "tune": "󰔡",
        "cloud_off": "󰅟",
        "memory": "󰍛",
        "palette": "󰏘",
        "window": "󰖯",
        "toll": "\uf51e",
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
        "sync": "󰑓",
        "refresh": "󰑐",
        "drag_indicator": "󰇙",
        "drag_handle": "󰍜",
        "network_wifi": "󰤨",
        "network_wifi_3_bar": "󰤥",
        "network_wifi_2_bar": "󰤢",
        "network_wifi_1_bar": "󰤟",
        "wifi_strength_4": "󰤨",
        "wifi_strength_3": "󰤥",
        "wifi_strength_2": "󰤢",
        "wifi_strength_1": "󰤟",
        "wifi_strength_0": "󰤯",
        "check": "󰄬",
        "done": "󰄬",
        "chevron_right": "󰅂",
        "navigate_next": "󰅂",
        "chevron_left": "󰅁",
        "navigate_before": "󰅁",
        "arrow_back": "󰁍",
        "arrow_forward": "󰁔",
        "arrow_upward": "󰁝",
        "arrow_up": "󰁝",
        "arrow_downward": "󰁅",
        "arrow_down": "󰁅",
        "stop": "󰓛",
        "radio_button_checked": "󰗌",
        "radio_button_unchecked": "󰄰",
        "check_box": "󰄲",
        "check_box_outline_blank": "󰄱",
        "add": "󰐕",
        "plus": "󰐕",
        "remove": "󰐖",
        "minus": "󰐖",
        "delete": "󰆴",
        "delete_outline": "󰆴",
        "trash": "󰆴",
        "vpn_key": "󰌆",
        "key": "󰌆",
        "check_circle": "󰄳",
        "check_circle_outline": "󰄳",
        "content_paste": "󰆒",
        "select_all": "󰒆",
        "delete_sweep": "󰗩",
        "download": "󰇚",
        "cloud_download": "󰅢",
        "file_download": "󰥥",
        "link": "󰌷",
        "task_alt": "󰗠",
        "account_circle": "󰀉",
        "person": "󰀄",
        "user": "󰀄",
        "manage_accounts": "󰀋",
        "edit": "󰏫",
        "warning": "󰀦",
        "error": "󰅚"
    })

    readonly property string displaySymbol: {
        let key = iconKey;
        if (symbolMap[key]) return symbolMap[key];
        if (key && key.length <= 2) return key;
        if (key && (key.startsWith("wifi") || key.startsWith("network_wifi"))) return "󰤨";
        if (key && (key.includes("refresh") || key.includes("sync"))) return "󰑓";
        if (key && key.includes("download")) return "󰇚";
        if (key && key.includes("link")) return "󰌷";
        if (key && (key === "task_alt" || key.includes("task_done"))) return "󰗠";
        if (key && key.includes("drag")) return "󰇙";
        if (key && (key.includes("psychology") || key.includes("brain") || key === "ai")) return "󰧑";
        if (key && (key.includes("spark") || key.includes("auto_awesome"))) return "󰄧";
        if (key && (key.includes("token") || key.includes("toll") || key.includes("coin"))) return "\uf51e";
        if (key && (key === "add" || key.includes("plus"))) return "󰐕";
        if (key && (key.includes("key") || key.includes("vpn_key"))) return "󰌆";
        if (key && (key.includes("delete") || key.includes("trash"))) return "󰆴";
        if (key && (key.includes("check_circle") || key === "check")) return "󰄳";
        if (key && (key.includes("account") || key.includes("person") || key.includes("user"))) return "󰀉";
        if (key && (key.includes("arrow_up") || key === "arrow_upward")) return "󰁝";
        if (key && (key.includes("arrow_down") || key === "arrow_downward")) return "󰁅";
        if (key && (key === "stop" || key.includes("stop"))) return "󰓛";
        if (key && (key === "send" || key.includes("send"))) return "󰒭";
        if (key && (key.includes("attach") || key.includes("clip"))) return "󰁦";
        if (key && (key.includes("image") || key.includes("photo") || key.includes("picture"))) return "󰋩";
        if (key && (key.includes("copy"))) return "󰆏";
        if (key && (key === "schema" || key.includes("diagram"))) return "󰅩";
        if (key && (key.includes("equalizer") || key.includes("graphic_eq"))) return "󰺢";
        if (key && key.includes("speaker")) return "󰓃";
        if (key && (key.includes("exit") || key.includes("leave") || key === "quit")) return "󰈆";
        return "";
    }

    readonly property string resolvedIconUrl: (root.iconName !== "" && typeof Config !== "undefined" && typeof Config.iconUrl === "function") ? Config.iconUrl(root.iconName) : ""

    Loader {
        anchors.fill: parent
        active: root.resolvedIconUrl !== ""
        sourceComponent: Image {
            source: root.resolvedIconUrl
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
        visible: root.resolvedIconUrl === ""
        text: root.displaySymbol
        color: root.color
        font.pixelSize: root.size
        font.family: "JetBrainsMono Nerd Font Propo"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
