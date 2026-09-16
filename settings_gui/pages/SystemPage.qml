import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"

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
        text: "Caelestia respects user autonomy: systemd service files are never installed automatically without your explicit permission. You can choose whether to install or remove the Caelestia user service below."
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
                text: "Unit File: ~/.config/systemd/user/caelestia.service"
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

    Item { Layout.fillHeight: true }
}
