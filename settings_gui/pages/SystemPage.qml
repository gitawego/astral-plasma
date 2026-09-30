import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"
import "../../services"

ColumnLayout {
    id: root

    property bool testMode: false
    property bool testInstalled: false
    property string testStatusText: ""
    property bool testDebugMode: false

    readonly property bool debugModeActive: testMode
        ? testDebugMode
        : ((typeof Config !== "undefined" && Config.debugMode !== undefined) ? Config.debugMode : false)

    readonly property bool isInstalled: testMode
        ? testInstalled
        : ((typeof Config !== "undefined" && Config.systemdServiceInstalled !== undefined) ? Config.systemdServiceInstalled : false)

    readonly property string statusText: testMode
        ? (testStatusText || (testInstalled ? "Installed" : "Not Installed"))
        : ((typeof Config !== "undefined" && Config.systemdServiceStatusText !== undefined) ? Config.systemdServiceStatusText : "Not Installed")

    readonly property color onSurfaceColor: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#231917"
    readonly property color onSurfaceVariantColor: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#524340"
    readonly property color surfaceContainerColor: (typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : "#F2EDE7"
    readonly property color primaryColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#6B4FA0"
    readonly property color errorContainerColor: (typeof Colors !== "undefined" && Colors.errorContainer) ? Colors.errorContainer : "#FFDAD6"
    readonly property color onErrorContainerColor: (typeof Colors !== "undefined" && Colors.onErrorContainer) ? Colors.onErrorContainer : "#410002"
    readonly property color borderSubtleColor: (typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : "#D6CEC5"

    readonly property int padLargeVal: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16
    readonly property int padMediumVal: (typeof Theme !== "undefined" && Theme.padMedium) ? Theme.padMedium : 12
    readonly property int radiusMediumVal: (typeof Theme !== "undefined" && Theme.radiusMedium) ? Theme.radiusMedium : 16
    readonly property int spaceMediumVal: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12
    readonly property int spaceSmallVal: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 8

    spacing: root.spaceMediumVal

    Text {
        text: "System & Services"
        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 21
        font.weight: Font.Bold
        color: root.onSurfaceColor
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
            anchors.fill: parent
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
            active: root.isInstalled
            activeColor: root.errorContainerColor
            activeTextColor: root.onErrorContainerColor
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

    Text {
        text: "Session"
        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 21
        font.weight: Font.Bold
        color: root.onSurfaceColor
    }

    Text {
        Layout.fillWidth: true
        text: "Leaving the shell restores the Plasma panels it replaced. Start it again with ./run.sh."
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
            active: true
            activeColor: root.errorContainerColor
            activeTextColor: root.onErrorContainerColor
            onClicked: {
                if (typeof Config !== "undefined" && Config.exitShell) {
                    Config.exitShell();
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

    Item { height: root.spaceMediumVal }

    Text {
        text: "Developer & Diagnostics"
        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 21
        font.weight: Font.Bold
        color: root.onSurfaceColor
    }

    SettingToggle {
        id: debugSettingToggle
        Layout.fillWidth: true
        title: "Debug Mode"
        description: "Freeze drawer auto-close on mouse exit and enable diagnostic inspection"
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

    // =========================================================================
    // Display refresh
    // =========================================================================
    // The shell's motion is budgeted at 30 fps, so the panel's refresh rate is a
    // power and heat choice: every client's per-frame work - including the
    // compositor's blend and blur of this shell's glass - scales with it. 60 Hz
    // is the shipped default; "Max" leaves the session exactly as it was found.
    Text {
        text: "Display Refresh"
        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 21
        font.weight: Font.Bold
        color: root.onSurfaceColor
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
