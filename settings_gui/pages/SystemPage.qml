import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"
import "../../services"

SettingsPage {
    id: root

    title: "System & Services"
    subtitle: "User services, desktop integration, session exit, diagnostics and display"
    zones: [
        { id: "services", label: "Services", anchor: servicesHeader },
        { id: "desktop", label: "Desktop", anchor: desktopHeader },
        { id: "session", label: "Session", anchor: sessionHeader },
        { id: "developer", label: "Developer", anchor: developerHeader },
        { id: "logging", label: "Logging", anchor: loggingHeader },
        { id: "display", label: "Display", anchor: displayHeader }
    ]

    property bool testMode: false
    property bool testInstalled: false
    property string testStatusText: ""
    property bool testDesktopInstalled: false
    property string testDesktopStatusText: ""
    property bool testDebugMode: false
    // Verbosity of the diagnostic log. In test mode the page reports the value
    // the harness injected (the mock cannot write to Config).
    property string testLogLevel: "info"

    readonly property alias exitButton: exitShellButton

    readonly property bool debugModeActive: testMode
        ? testDebugMode
        : ((typeof Config !== "undefined" && Config.debugMode !== undefined) ? Config.debugMode : false)

    /// The level the picker shows and the logger applies ("off" ... "trace").
    readonly property string logLevelActive: testMode
        ? testLogLevel
        : ((typeof Config !== "undefined" && Config.logLevel !== undefined) ? Config.logLevel : "info")

    /// The levels a user can choose, quietest first. The same ladder lives in
    /// `services/Logging.js`; this is only the presentation order.
    readonly property var logLevelOptions: ["off", "error", "warn", "info", "debug", "trace"]

    /// The picker's write path. One function the pills call, so the behaviour is
    /// verifiable without clicking through rendered buttons.
    function selectLogLevel(level) {
        if (testMode) {
            testLogLevel = level;
            return;
        }
        if (typeof Config !== "undefined" && Config.setLogLevel) {
            Config.setLogLevel(level);
        }
    }

    readonly property bool isInstalled: testMode
        ? testInstalled
        : ((typeof Config !== "undefined" && Config.systemdServiceInstalled !== undefined) ? Config.systemdServiceInstalled : false)

    readonly property string statusText: testMode
        ? (testStatusText || (testInstalled ? "Installed" : "Not Installed"))
        : ((typeof Config !== "undefined" && Config.systemdServiceStatusText !== undefined) ? Config.systemdServiceStatusText : "Not Installed")

    readonly property bool isDesktopInstalled: testMode
        ? testDesktopInstalled
        : ((typeof Config !== "undefined" && Config.desktopIntegrationInstalled !== undefined) ? Config.desktopIntegrationInstalled : false)

    readonly property string desktopStatusText: testMode
        ? (testDesktopStatusText || (testDesktopInstalled ? "Installed" : "Not Installed"))
        : ((typeof Config !== "undefined" && Config.desktopIntegrationStatusText !== undefined) ? Config.desktopIntegrationStatusText : "Not Installed")

    readonly property bool isHyprland: (typeof DesktopSessionFacade !== "undefined" && DesktopSessionFacade.profile === "hyprland")

    /// The chosen refresh rate, in the same words the pills use.
    readonly property string refreshChoiceText: {
        if (typeof Config === "undefined" || Config.displayRefreshRate === undefined) return "";
        return (typeof Config.displayRefreshLabel === "function")
            ? Config.displayRefreshLabel(Config.displayRefreshRate)
            : ("" + Config.displayRefreshRate);
    }

    readonly property bool isDark: (typeof Colors !== "undefined" && Colors.isDarkMode !== undefined)
        ? Colors.isDarkMode
        : ((typeof Config !== "undefined" && Config.isDarkMode !== undefined) ? Config.isDarkMode : true)

    readonly property color onSurfaceColor: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : (isDark ? "#F3EDF6" : "#231917")
    readonly property color onSurfaceVariantColor: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : (isDark ? "#E1DBE7" : "#524340")
    readonly property color surfaceContainerColor: (typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : (isDark ? "#1D1B20" : "#F2EDE7")
    readonly property color primaryColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#6B4FA0"
    readonly property color errorColor: (typeof Colors !== "undefined" && Colors.error) ? Colors.error : (isDark ? "#FFB4AB" : "#BA1A1A")
    readonly property color errorContainerColor: (typeof Colors !== "undefined" && Colors.m3errorContainer) ? Colors.m3errorContainer : (isDark ? "#93000A" : "#FFDAD6")
    readonly property color onErrorContainerColor: (typeof Colors !== "undefined" && Colors.m3onErrorContainer) ? Colors.m3onErrorContainer : (isDark ? "#FFDAD6" : "#410002")
    readonly property color borderSubtleColor: (typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : (isDark ? "#44464F" : "#D6CEC5")

    readonly property int radiusMediumVal: (typeof Theme !== "undefined" && Theme.radiusMedium) ? Theme.radiusMedium : 16
    readonly property int spaceMediumVal: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12
    readonly property int spaceSmallVal: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 8
    readonly property int padLargeVal: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16

    spacing: root.spaceMediumVal

    SectionHeader {
        id: servicesHeader
        title: "System & Services"
        eyebrow: "service · " + root.statusText
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Astral Plasma respects user autonomy: systemd service files are never installed automatically without your explicit permission. You can choose whether to install or remove the Astral Plasma user service below."
        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
        color: root.onSurfaceVariantColor
    }

    // Status Card
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: statusLayout.implicitHeight + root.padLargeVal * 2
        radius: root.radiusMediumVal
        color: root.surfaceContainerColor
        border.color: root.isInstalled ? Qt.alpha(root.primaryColor, 0.3) : root.borderSubtleColor
        border.width: 1

        ColumnLayout {
            id: statusLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padLargeVal
            spacing: root.spaceSmallVal

            RowLayout {
                spacing: root.spaceMediumVal

                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: root.isInstalled ? "#4CAF50" : "#9E9E9E"
                }

                Text {
                    text: "Systemd Service Status: " + root.statusText
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                    font.weight: Font.DemiBold
                    color: root.onSurfaceColor
                }
            }

            Text {
                text: "Unit File: ~/.config/systemd/user/astral-plasma.service"
                font.family: "monospace"
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                color: root.onSurfaceVariantColor
            }
        }
    }

    // Action Buttons
    RowLayout {
        Layout.fillWidth: true
        spacing: root.spaceMediumVal

        PillButton {
            id: installBtn
            label: "Install Service"
            iconText: "add_circle"
            accent: "primary"
            variant: "tonal"
            active: !root.isInstalled
            onClicked: {
                if (typeof Config !== "undefined" && Config.installSystemdService) {
                    Config.installSystemdService();
                }
            }
        }

        PillButton {
            id: removeBtn
            label: "Remove Service"
            iconText: "delete"
            accent: "error"
            variant: "tonal"
            active: root.isInstalled
            onClicked: {
                if (typeof Config !== "undefined" && Config.removeSystemdService) {
                    Config.removeSystemdService();
                }
            }
        }

        Item { Layout.fillWidth: true }

        PillButton {
            label: "Refresh Status"
            iconText: "refresh"
            active: false
            onClicked: {
                if (typeof Config !== "undefined" && Config.checkSystemdServiceStatus) {
                    Config.checkSystemdServiceStatus();
                }
            }
        }
    }

    Item { height: root.spaceMediumVal }

    SectionHeader {
        id: desktopHeader
        title: "Desktop & Session Integration"
        eyebrow: "integration · " + root.desktopStatusText
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Astral Plasma respects user autonomy: desktop shortcuts (.desktop) and display manager Wayland session files are never installed automatically without your explicit permission. You can choose whether to register or remove them below."
        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
        color: root.onSurfaceVariantColor
    }

    // Desktop Integration Status Card
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: desktopStatusLayout.implicitHeight + root.padLargeVal * 2
        radius: root.radiusMediumVal
        color: root.surfaceContainerColor
        border.color: root.isDesktopInstalled ? Qt.alpha(root.primaryColor, 0.3) : root.borderSubtleColor
        border.width: 1

        ColumnLayout {
            id: desktopStatusLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padLargeVal
            spacing: root.spaceSmallVal

            RowLayout {
                spacing: root.spaceMediumVal

                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: root.isDesktopInstalled ? "#4CAF50" : (root.desktopStatusText === "Partially Installed" ? "#FF9800" : "#9E9E9E")
                }

                Text {
                    text: "Desktop Integration Status: " + root.desktopStatusText
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                    font.weight: Font.DemiBold
                    color: root.onSurfaceColor
                }
            }

            Text {
                text: "Wayland Sessions: ~/.local/share/wayland-sessions/ (KDE Plasma & Hyprland)"
                font.family: "monospace"
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                color: root.onSurfaceVariantColor
            }

            Text {
                text: "App Shortcuts: ~/.local/share/applications/ (Launcher, Dashboard, Settings, Wallpaper)"
                font.family: "monospace"
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                color: root.onSurfaceVariantColor
            }
        }
    }

    // Desktop Integration Action Buttons
    RowLayout {
        Layout.fillWidth: true
        spacing: root.spaceMediumVal

        PillButton {
            id: installDesktopBtn
            label: "Install Integration"
            iconText: "add_circle"
            accent: "primary"
            variant: "tonal"
            active: !root.isDesktopInstalled
            onClicked: {
                if (root.testMode) {
                    root.testDesktopInstalled = true;
                    root.testDesktopStatusText = "Installed";
                } else if (typeof Config !== "undefined" && Config.installDesktopIntegration) {
                    Config.installDesktopIntegration();
                }
            }
        }

        PillButton {
            id: removeDesktopBtn
            label: "Remove Integration"
            iconText: "delete"
            accent: "error"
            variant: "tonal"
            active: root.isDesktopInstalled
            onClicked: {
                if (root.testMode) {
                    root.testDesktopInstalled = false;
                    root.testDesktopStatusText = "Not Installed";
                } else if (typeof Config !== "undefined" && Config.removeDesktopIntegration) {
                    Config.removeDesktopIntegration();
                }
            }
        }

        Item { Layout.fillWidth: true }

        PillButton {
            label: "Refresh Status"
            iconText: "refresh"
            active: false
            onClicked: {
                if (typeof Config !== "undefined" && Config.checkDesktopIntegrationStatus) {
                    Config.checkDesktopIntegrationStatus();
                }
            }
        }
    }

    Item { height: root.spaceMediumVal }

    SectionHeader {
        id: sessionHeader
        title: "Session"
        eyebrow: root.isHyprland ? "hyprland session" : "plasma session"
    }

    Text {
        Layout.fillWidth: true
        text: root.isHyprland
            ? "Leaving the shell closes Astral Shell. Start it again with ./run.sh or your Hyprland configuration."
            : "Leaving the shell restores the Plasma panels it replaced. Start it again with ./run.sh."
        wrapMode: Text.WordWrap
        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
        color: root.onSurfaceVariantColor
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.spaceMediumVal

        PillButton {
            id: exitShellButton
            label: "Exit Astral Plasma"
            iconText: "exit_to_app"
            accent: "error"
            variant: "tonal"
            active: true
            onClicked: {
                if (typeof Config !== "undefined" && Config.exitShell) {
                    Config.exitShell();
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

    Item { height: root.spaceMediumVal }

    SectionHeader {
        id: developerHeader
        title: "Developer & Diagnostics"
        eyebrow: root.debugModeActive ? "debug mode on" : "debug mode off"
    }

    SettingToggle {
        id: debugSettingToggle
        Layout.fillWidth: true
        title: "Debug Mode"
        description: "Freeze drawer auto-close on mouse exit so the shell can be inspected while it is open"
        checked: root.debugModeActive
        onToggled: val => {
            if (root.testMode) {
                root.testDebugMode = val;
            } else if (typeof Config !== "undefined" && Config.setDebugMode) {
                Config.setDebugMode(val);
            }
        }
    }

    Item { height: root.spaceMediumVal }

    // === Log verbosity ====================================================
    // One level for the whole shell, per-category overrides underneath it. The
    // shipped default is "info": lifecycle events, warnings and errors are
    // visible, while the per-frame trails are off until somebody asks for them.
    SectionHeader {
        id: loggingHeader
        title: "Log Verbosity"
        eyebrow: "level: " + root.logLevelActive
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Messages at this level or louder are printed: off < error < warn < info < debug < trace. "
            + "\"info\" keeps lifecycle events, warnings and errors; per-frame traces (blur regions, commit pump) "
            + "belong to \"debug\". A single category can be raised on its own via \"logging.categories\" "
            + "in settings.json, or for one run with ASTRAL_PLASMA_LOG_CATEGORIES=blur=debug."
        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
        font.pixelSize: 13
        color: root.onSurfaceVariantColor
        opacity: 0.85
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.spaceSmallVal

        Repeater {
            model: root.logLevelOptions

            PillButton {
                required property var modelData
                label: modelData
                active: root.logLevelActive === modelData
                onClicked: root.selectLogLevel(modelData)
            }
        }

        Item { Layout.fillWidth: true }
    }

    Item { height: root.spaceMediumVal }

    // =========================================================================
    // Display refresh
    // =========================================================================
    // The shell's motion is budgeted at 30 fps, so the panel's refresh rate is a
    // power and heat choice: every client's per-frame work - including the
    // compositor's blend and blur of this shell's glass - scales with it. 60 Hz
    // is the shipped default; "Max" leaves the session exactly as it was found.
    SectionHeader {
        id: displayHeader
        title: "Display Refresh"
        eyebrow: root.refreshChoiceText === ""
            ? "session default"
            : ("chosen: " + root.refreshChoiceText)
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "The highest rate at your current resolution that does not exceed this choice. "
            + "Lower is cooler and quieter; the shell looks the same because its motion is capped. "
            + "The session's original mode is restored when the shell exits."
        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
        font.pixelSize: 13
        color: root.onSurfaceVariantColor
        opacity: 0.85
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: root.spaceSmallVal

        Repeater {
            model: (typeof Config !== "undefined" && Config.displayRefreshOptions)
                ? Config.displayRefreshOptions
                : ["60", "120", "144", "165", "max"]

            PillButton {
                required property var modelData
                label: (typeof Config !== "undefined" && Config.displayRefreshLabel)
                    ? Config.displayRefreshLabel(modelData)
                    : modelData
                active: (typeof Config !== "undefined" && Config)
                    ? ("" + Config.displayRefreshRate === "" + modelData)
                    : false
                onClicked: {
                    if (typeof Config !== "undefined" && Config.setDisplayRefreshRate) {
                        Config.setDisplayRefreshRate(modelData);
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        Text {
            text: {
                if (typeof DisplayService === "undefined" || !DisplayService) return "";
                if (DisplayService.applying) return "Applying...";
                return DisplayService.lastApplySucceeded
                    ? ("Active: " + DisplayService.lastApplied)
                    : (DisplayService.lastApplied === "" ? "" : "Apply failed");
            }
            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
            font.pixelSize: 12
            color: root.onSurfaceVariantColor
            opacity: 0.8
        }
    }
    Item { Layout.fillHeight: true }
}
