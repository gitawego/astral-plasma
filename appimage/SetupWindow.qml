import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../modules/Astral/Kernel/theme"

// First-run setup for the AppImage delivery. This is a normal desktop window,
// not a layer-shell takeover: the user can try the shell, install it as a login
// session, or close the AppImage without changing the running Plasma desktop.
FloatingWindow {
    id: root

    readonly property string payload: Quickshell.env("ASTRAL_APPIMAGE_PAYLOAD") || ""
    readonly property string daemon: Quickshell.env("ASTRAL_PLASMA_DAEMON")
        || (root.payload.length > 0 ? root.payload + "/usr/bin/astral-plasma" : "astral-plasma")
    readonly property color onSurface: (typeof Colors !== "undefined" && Colors.m3onSurface)
        ? Colors.m3onSurface : "#F3EDF6"
    readonly property color onSurfaceVariant: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant)
        ? Colors.m3onSurfaceVariant : "#E1DBE7"
    readonly property color primary: (typeof Colors !== "undefined" && Colors.primary)
        ? Colors.primary : "#CFBCFF"
    readonly property color errorColor: (typeof Colors !== "undefined" && Colors.error)
        ? Colors.error : "#FFB4AB"
    readonly property color panel: (typeof Colors !== "undefined" && Colors.glassPanelSubstrate)
        ? Colors.glassPanelSubstrate : "#E61D1B20"
    readonly property color border: (typeof Colors !== "undefined" && Colors.glassBorderSpecular)
        ? Colors.glassBorderSpecular : "#33FFFFFF"
    readonly property color cardSurface: (typeof Colors !== "undefined" && Colors.surfaceContainerHigh)
        ? Qt.alpha(Colors.surfaceContainerHigh, 0.90) : "#E61D1B20"

    property bool busy: false
    property bool installed: false
    property string message: ""

    visible: true
    title: "Astral Plasma Setup"
    color: "transparent"
    implicitWidth: 780
    implicitHeight: 660
    minimumSize: Qt.size(660, 600)

    function refresh() {
        if (!root.payload)
            return;
        statusProc.running = true;
    }

    function tryIt() {
        if (!root.payload)
            return;
        Quickshell.execDetached([root.daemon, "run"]);
        Qt.quit();
    }

    function installSession() {
        if (!root.payload || root.busy)
            return;
        root.busy = true;
        root.message = "Installing the AppImage payload...";
        installProc.running = true;
    }

    function removeInstall() {
        if (root.busy)
            return;
        root.busy = true;
        root.message = "Removing the AppImage install...";
        removeProc.running = true;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: statusProc
        command: [root.daemon, "appimage", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length === 0)
                    return;
                try {
                    root.installed = !!JSON.parse(text).installed;
                } catch (error) {
                    root.message = "Could not read the install status: " + error;
                }
            }
        }
    }

    Process {
        id: installProc
        command: [root.daemon, "appimage", "install", "--payload", root.payload, "--yes"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                const text = this.text.trim();
                if (text.length === 0) {
                    root.message = "Install did not return a result.";
                    return;
                }
                try {
                    const result = JSON.parse(text);
                    root.installed = !!result.installed;
                    root.message = root.installed
                        ? "Installed. Log out, then choose Astral Plasma (AppImage) at the login screen."
                        : "Install finished, but the session is not active.";
                } catch (error) {
                    root.message = "Install failed: " + error;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length > 0)
                    root.message = text.split("\n").pop();
            }
        }
    }

    Process {
        id: removeProc
        command: [root.daemon, "appimage", "uninstall", "--yes"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                root.installed = false;
                root.message = "Removed. Your settings and wallpapers were kept.";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                if (text.length > 0)
                    root.message = text.split("\n").pop();
            }
        }
    }

    component WizardButton: Rectangle {
        id: button

        property string label: ""
        property string tone: "primary"
        property bool filled: false
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + Theme.padLarge * 2
        implicitHeight: 40
        radius: Theme.radiusFull
        opacity: enabled ? 1.0 : 0.45
        color: {
            const base = button.tone === "error" ? root.errorColor
                : button.tone === "neutral" ? root.onSurface : root.primary;
            return button.filled ? base : Qt.alpha(base, 0.12);
        }
        border.width: 1
        border.color: {
            const base = button.tone === "error" ? root.errorColor
                : button.tone === "neutral" ? root.onSurface : root.primary;
            return button.filled ? "transparent" : Qt.alpha(base, 0.45);
        }

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBodyMedium
            font.weight: Font.DemiBold
            color: {
                if (!button.filled)
                    return button.tone === "error" ? root.errorColor
                        : button.tone === "neutral" ? root.onSurface : root.primary;
                return (typeof Colors !== "undefined" && Colors.isDarkMode) ? "#1D1B20" : "#FFFFFF";
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: button.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: root.panel
        border.width: 1
        border.color: root.border
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.padExtraLarge
            spacing: Theme.spaceLarge

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceLarge

                Rectangle {
                    width: 56
                    height: 56
                    radius: Theme.radiusMedium
                    color: Qt.alpha(root.primary, 0.16)
                    border.width: 1
                    border.color: Qt.alpha(root.primary, 0.35)
                    Text {
                        anchors.centerIn: parent
                        text: "✦"
                        font.pixelSize: 30
                        color: root.primary
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Astral Plasma"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontTitleLarge
                        font.weight: Font.DemiBold
                        color: root.onSurface
                    }
                    Text {
                        text: "A fluid desktop shell for KDE Plasma 6 and Hyprland"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: root.onSurfaceVariant
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Text {
                Layout.fillWidth: true
                text: "This AppImage can run without changing your desktop. If you like it, install it as a login session and choose it at the login screen. Plasma stays available as a fallback."
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                color: root.onSurfaceVariant
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(104, tryLayout.implicitHeight + Theme.padLarge * 2)
                Layout.minimumHeight: 104
                implicitHeight: Math.max(104, tryLayout.implicitHeight + Theme.padLarge * 2)
                radius: Theme.radiusMedium
                color: root.cardSurface
                border.width: 1
                border.color: Qt.alpha(root.onSurface, 0.16)

                RowLayout {
                    id: tryLayout
                    anchors.fill: parent
                    anchors.margins: Theme.padLarge
                    spacing: Theme.spaceMedium

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: "Try it now"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontTitleSmall
                            font.weight: Font.DemiBold
                            color: root.onSurface
                        }
                        Text {
                            text: "Starts the shell on this desktop. Your Plasma panels return when the shell exits."
                            wrapMode: Text.WordWrap
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBodySmall
                            color: root.onSurfaceVariant
                        }
                    }

                    WizardButton {
                        label: "Try"
                        enabled: !root.busy && root.payload.length > 0
                        onClicked: root.tryIt()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(108, installLayout.implicitHeight + Theme.padLarge * 2)
                Layout.minimumHeight: 108
                implicitHeight: Math.max(108, installLayout.implicitHeight + Theme.padLarge * 2)
                radius: Theme.radiusMedium
                color: root.installed ? Qt.tint(root.cardSurface, Qt.alpha(root.primary, 0.18)) : root.cardSurface
                border.width: 1
                border.color: root.installed ? Qt.alpha(root.primary, 0.45) : Qt.alpha(root.onSurface, 0.16)

                RowLayout {
                    id: installLayout
                    anchors.fill: parent
                    anchors.margins: Theme.padLarge
                    spacing: Theme.spaceMedium

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: root.installed ? "Installed at login" : "Install at login"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontTitleSmall
                            font.weight: Font.DemiBold
                            color: root.onSurface
                        }
                        Text {
                            text: root.installed
                                ? "Log out and choose Astral Plasma (AppImage) at the login screen."
                                : "Adds a session entry. It does not change your current session or your default desktop."
                            wrapMode: Text.WordWrap
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBodySmall
                            color: root.onSurfaceVariant
                        }
                    }

                    WizardButton {
                        label: root.installed ? "Remove" : "Install"
                        tone: root.installed ? "error" : "primary"
                        filled: !root.installed
                        enabled: !root.busy && root.payload.length > 0
                        onClicked: root.installed ? root.removeInstall() : root.installSession()
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                visible: root.message.length > 0
                Layout.minimumHeight: visible ? 52 : 0
                implicitHeight: visible ? Math.max(52, messageText.implicitHeight + Theme.padMedium * 2) : 0
                radius: Theme.radiusSmall
                color: Qt.alpha(root.primary, 0.06)
                border.width: 1
                border.color: Qt.alpha(root.primary, 0.18)
                Text {
                    id: messageText
                    anchors.fill: parent
                    anchors.margins: Theme.padMedium
                    text: root.message
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: root.onSurfaceVariant
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                Text {
                    Layout.fillWidth: true
                    text: root.busy ? "Working..." : "Nothing is installed until you choose Install."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: root.onSurfaceVariant
                }

                WizardButton {
                    label: "Close"
                    tone: "neutral"
                    onClicked: Qt.quit()
                }
            }
        }
    }
}
