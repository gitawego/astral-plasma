import QtQuick
import QtQuick.Layouts
import "../controls"
import "../../config"
import "../../theme"
import "../../components"
import "../../services"

// ============================================================================
// Updates & About
// ============================================================================
// One place to answer four questions: what am I running, is there a newer
// release, what changed, and how do I go back or leave.
//
// Every value comes from the daemon (`astral-plasma update status`), which is the
// only component allowed to decide that an update exists. The page never
// estimates progress, never shows a version it was not told, and never offers
// "Update" on an install the daemon would refuse (a package-manager install, a
// git checkout, or one with an update already staged).
SettingsPage {
    id: root

    title: "Updates & About"
    subtitle: "Version, release notes, rollback and removal"
    zones: [
        { id: "version", label: "Version", anchor: versionHeader },
        { id: "update", label: "Update", anchor: updateHeader },
        { id: "notes", label: "What's New", anchor: notesHeader },
        { id: "maintenance", label: "Maintenance", anchor: maintenanceHeader }
    ]

    property bool testMode: false
    property var testStatus: ({})
    property var testChangelog: []
    property int checkCalls: 0
    property int applyCalls: 0
    property int revertCalls: 0
    property int uninstallCalls: 0
    property bool armedUninstall: false

    // Introspection surface for the suite: the controls without finding ids.
    readonly property alias checkButton: checkButton
    readonly property alias applyButton: applyButton
    readonly property alias revertButton: revertButton
    readonly property alias uninstallButton: uninstallButton

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    readonly property var live: (typeof Updates !== "undefined") ? Updates : null

    readonly property var status: testMode ? (testStatus || ({})) : ({
        current_version: live ? live.currentVersion : "",
        channel: live ? live.channel : "stable",
        install_method: live ? live.installMethod : "",
        can_apply: live ? live.canApply : false,
        refuse_reason: live ? live.refuseReason : "",
        candidate: (live && live.updateAvailable) ? ({
            version: live.candidateVersion,
            highlights: live.highlights,
            size: live.candidateBytes
        }) : null,
        last_error: live ? live.lastError : "",
        rollback: (live && live.rollbackVersion !== "") ? ({
            version: live.rollbackVersion,
            reason: live.rollbackReason
        }) : null,
        restart_pending: live ? live.restartPending : "",
        last_seen_version: live ? live.lastSeenVersion : ""
    })

    readonly property var candidate: status.candidate || null
    readonly property string candidateVersion: candidate ? (candidate.version || "") : ""
    readonly property string currentVersion: status.current_version || ""
    readonly property string installMethod: status.install_method || ""
    readonly property string refuseReason: status.refuse_reason || ""
    readonly property string lastError: status.last_error || ""
    readonly property var rollback: status.rollback || null
    readonly property string restartPending: status.restart_pending || ""
    readonly property bool updateAvailable: candidateVersion !== ""
    readonly property bool canApply: status.can_apply === true
    readonly property bool applying: !testMode && live !== null ? live.applying : false

    readonly property var notes: testMode ? (testChangelog || []) : (live ? live.changelog : [])

    readonly property string sizeText: {
        if (!candidate || !candidate.size) return "";
        const mb = candidate.size / (1024 * 1024);
        return (mb >= 10 ? Math.round(mb) : Math.round(mb * 10) / 10) + " MiB";
    }

    readonly property string methodText: {
        switch (installMethod) {
        case "managed": return "Updated by the shell";
        case "package": return "Managed by your package manager";
        case "checkout": return "Git checkout";
        default: return "Unknown";
        }
    }

    // ------------------------------------------------------------------
    // Actions
    // ------------------------------------------------------------------
    function requestCheck() {
        if (testMode) { checkCalls += 1; return; }
        if (live) live.checkNow();
    }

    function requestApply() {
        if (testMode) { applyCalls += 1; return; }
        if (live) live.applyUpdate();
    }

    function requestRevert() {
        if (testMode) { revertCalls += 1; return; }
        if (live) live.revert();
    }

    function requestUninstall() {
        if (!armedUninstall) {
            // Removal deletes the install this window runs from: two presses,
            // never one. The same rule applies in tests, so the suite proves the
            // rule rather than a test-only shortcut.
            armedUninstall = true;
            disarmTimer.restart();
            return;
        }
        armedUninstall = false;
        if (testMode) { uninstallCalls += 1; return; }
        if (live) live.uninstall();
    }

    Timer {
        id: disarmTimer
        interval: 8000
        repeat: false
        onTriggered: root.armedUninstall = false
    }

    // ------------------------------------------------------------------
    // Colours: the same fallbacks every page uses, so this loads headless.
    // ------------------------------------------------------------------
    readonly property bool isDark: (typeof Colors !== "undefined" && Colors.isDarkMode !== undefined)
        ? Colors.isDarkMode
        : ((typeof Config !== "undefined" && Config.isDarkMode !== undefined) ? Config.isDarkMode : true)
    readonly property color onSurfaceColor: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : (isDark ? "#F3EDF6" : "#231917")
    readonly property color onSurfaceVariantColor: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : (isDark ? "#E1DBE7" : "#524340")
    readonly property color surfaceContainerColor: (typeof Colors !== "undefined" && Colors.surfaceContainer) ? Colors.surfaceContainer : (isDark ? "#1D1B20" : "#F2EDE7")
    readonly property color primaryColor: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#6B4FA0"
    readonly property color errorColor: (typeof Colors !== "undefined" && Colors.error) ? Colors.error : (isDark ? "#FFB4AB" : "#BA1A1A")
    readonly property color borderSubtleColor: (typeof Theme !== "undefined" && Theme.borderSubtle) ? Theme.borderSubtle : (isDark ? "#44464F" : "#D6CEC5")
    readonly property int radiusMediumVal: (typeof Theme !== "undefined" && Theme.radiusMedium) ? Theme.radiusMedium : 16
    readonly property int spaceMediumVal: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12
    readonly property int spaceSmallVal: (typeof Theme !== "undefined" && Theme.spaceSmall) ? Theme.spaceSmall : 8
    readonly property int padLargeVal: (typeof Theme !== "undefined" && Theme.padLarge) ? Theme.padLarge : 16
    readonly property string fontFamilyVal: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"

    spacing: root.spaceMediumVal

    // ------------------------------------------------------------------
    // Version
    // ------------------------------------------------------------------
    SectionHeader {
        id: versionHeader
        title: "Version"
        eyebrow: root.currentVersion !== "" ? "running · " + root.currentVersion : "version unknown"
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: versionLayout.implicitHeight + root.padLargeVal * 2
        radius: root.radiusMediumVal
        color: root.surfaceContainerColor
        border.color: root.borderSubtleColor
        border.width: 1

        ColumnLayout {
            id: versionLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padLargeVal
            spacing: root.spaceSmallVal

            Text {
                text: "Astral Plasma " + (root.currentVersion !== "" ? root.currentVersion : "—")
                font.family: root.fontFamilyVal
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontTitleMedium) ? Theme.fontTitleMedium : 20
                font.weight: Font.DemiBold
                color: root.onSurfaceColor
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.methodText + " · channel " + (root.status.channel || "stable")
                font.family: root.fontFamilyVal
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                color: root.onSurfaceVariantColor
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.lastError !== ""
                text: "Last check: " + root.lastError
                font.family: root.fontFamilyVal
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                color: root.errorColor
            }
        }
    }

    // ------------------------------------------------------------------
    // Update
    // ------------------------------------------------------------------
    SectionHeader {
        id: updateHeader
        title: "Update"
        eyebrow: {
            if (root.applying) return "applying";
            if (root.restartPending !== "") return "staged · " + root.restartPending;
            if (root.updateAvailable) return "available · " + root.candidateVersion;
            return "up to date";
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: updateLayout.implicitHeight + root.padLargeVal * 2
        radius: root.radiusMediumVal
        color: root.surfaceContainerColor
        border.color: root.updateAvailable ? Qt.alpha(root.primaryColor, 0.35) : root.borderSubtleColor
        border.width: 1

        ColumnLayout {
            id: updateLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padLargeVal
            spacing: root.spaceSmallVal

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: {
                    if (root.restartPending !== "") {
                        return "Version " + root.restartPending + " is downloaded and verified. It starts the next time the shell restarts.";
                    }
                    if (root.updateAvailable) {
                        return "Version " + root.candidateVersion + " is available" +
                            (root.sizeText !== "" ? " (" + root.sizeText + ")" : "") + ".";
                    }
                    return "This install is up to date.";
                }
                font.family: root.fontFamilyVal
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                font.weight: Font.DemiBold
                color: root.onSurfaceColor
            }

            // The daemon's own reason, shown verbatim: "your package manager owns
            // this install" is information, not an error to paraphrase.
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.refuseReason !== ""
                text: root.refuseReason
                font.family: root.fontFamilyVal
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                color: root.onSurfaceVariantColor
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !root.testMode && root.live !== null && root.live.applyError !== ""
                text: root.testMode || root.live === null ? "" : root.live.applyError
                font.family: root.fontFamilyVal
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                color: root.errorColor
            }

            RowLayout {
                spacing: root.spaceMediumVal
                Layout.topMargin: root.spaceSmallVal

                PillButton {
                    id: checkButton
                    label: "Check now"
                    iconText: "refresh"
                    accent: "neutral"
                    variant: "tonal"
                    active: false
                    onClicked: root.requestCheck()
                }

                PillButton {
                    id: applyButton
                    label: root.applying ? "Updating…" : "Update and restart"
                    iconText: "system_update"
                    accent: "primary"
                    variant: "filled"
                    active: root.updateAvailable && root.canApply && !root.applying
                    onClicked: root.requestApply()
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    // ------------------------------------------------------------------
    // What's New
    // ------------------------------------------------------------------
    SectionHeader {
        id: notesHeader
        title: "What's New"
        eyebrow: root.notes.length > 0 ? root.notes.length + " release(s)" : "no notes"
    }

    Repeater {
        model: root.notes
        delegate: Rectangle {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: noteLayout.implicitHeight + root.padLargeVal * 2
            radius: root.radiusMediumVal
            color: root.surfaceContainerColor
            border.color: root.borderSubtleColor
            border.width: 1

            ColumnLayout {
                id: noteLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.padLargeVal
                spacing: root.spaceSmallVal

                Text {
                    text: "Version " + (modelData.version || "") + " · " + (modelData.date || "")
                    font.family: root.fontFamilyVal
                    font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodyMedium) ? Theme.fontBodyMedium : 15
                    font.weight: Font.DemiBold
                    color: root.onSurfaceColor
                }

                Repeater {
                    model: modelData.highlights || []
                    delegate: Text {
                        required property var modelData
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "• " + modelData
                        font.family: root.fontFamilyVal
                        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                        color: root.onSurfaceVariantColor
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        visible: root.notes.length === 0
        text: "Release notes are compiled into this build."
        font.family: root.fontFamilyVal
        font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
        color: root.onSurfaceVariantColor
    }

    // ------------------------------------------------------------------
    // Maintenance
    // ------------------------------------------------------------------
    SectionHeader {
        id: maintenanceHeader
        title: "Maintenance"
        eyebrow: root.rollback !== null ? "rolled back" : "revert · remove"
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: maintenanceLayout.implicitHeight + root.padLargeVal * 2
        radius: root.radiusMediumVal
        color: root.surfaceContainerColor
        border.color: root.rollback !== null ? Qt.alpha(root.errorColor, 0.35) : root.borderSubtleColor
        border.width: 1

        ColumnLayout {
            id: maintenanceLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padLargeVal
            spacing: root.spaceSmallVal

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.rollback !== null
                text: root.rollback === null ? "" :
                    "Version " + (root.rollback.version || "the previous release") +
                    " did not start, so it was rolled back: " + (root.rollback.reason || "")
                font.family: root.fontFamilyVal
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                color: root.errorColor
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Reverting installs the previous version again. Uninstalling removes the shell, " +
                      "its bundle and its files; your settings are kept."
                font.family: root.fontFamilyVal
                font.pixelSize: (typeof Theme !== "undefined" && Theme.fontBodySmall) ? Theme.fontBodySmall : 13
                color: root.onSurfaceVariantColor
            }

            RowLayout {
                spacing: root.spaceMediumVal
                Layout.topMargin: root.spaceSmallVal

                PillButton {
                    id: revertButton
                    label: "Revert to previous version"
                    iconText: "history"
                    accent: "warning"
                    variant: "tonal"
                    active: root.installMethod === "managed"
                    onClicked: root.requestRevert()
                }

                Item { Layout.fillWidth: true }

                PillButton {
                    id: uninstallButton
                    label: root.armedUninstall ? "Press again to remove" : "Uninstall Astral Plasma"
                    iconText: "delete_forever"
                    accent: "error"
                    variant: root.armedUninstall ? "filled" : "tonal"
                    active: true
                    onClicked: root.requestUninstall()
                }
            }
        }
    }
}
