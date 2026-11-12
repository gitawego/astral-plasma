import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import "../controls"
import "../../modules/Astral/Kernel/config"
import "../../modules/Astral/Kernel/theme"
import "../../modules/Astral/Kernel/components"
import "../../modules/Astral/Kernel/services"

// ============================================================================
// Apps
// ============================================================================
// Every app the desktop knows about, in one list: what it is, which version it runs,
// the API level it was built against, and whether it still fits this shell. Actions
// are the platform's own: enable/disable (the registry, reversibly) and remove (payload
// + record, with the data kept unless the user says otherwise).
//
// The list is the daemon's `app list --json` — no local copy of the truth, no
// optimistic patching. A failed action shows the daemon's own sentence.
SettingsPage {
    id: root

    icon: "grid_view"
    title: "Apps"
    subtitle: "Installed apps, their versions, and what they are allowed to do"

    property bool testMode: false
    /// Injected by the harness: the rows to render (the service cannot run there).
    property var testApps: []
    /// Injected by the harness: the artifact the consent card would describe.
    property var testPendingInstall: null

    /// What installing a file would mean. Nothing is installed until the user consents.
    readonly property var pendingInstall: testMode ? testPendingInstall : AppsService.pendingInstall

    /// A bundled app ships with the platform: it can be disabled, never removed, because
    /// the next reconcile would put it back and the button would have lied (spec C.32).
    function canRemove(app) {
        return !!app && app.preinstalled !== true;
    }


    readonly property var apps: testMode ? testApps : AppsService.apps
    readonly property string lastError: testMode ? "" : AppsService.lastError

    Component.onCompleted: if (!testMode) AppsService.refresh()
    // A page that is re-shown is not a page that has just been read: an app installed or
    // removed from anywhere else (a terminal, a file manager's "open with") must show up
    // when the user comes back to this list.
    onVisibleChanged: if (visible && !testMode) AppsService.refresh()

    function stateLabel(app) {
        if (!app.enabled) return "Disabled";
        if (!app.compatible) return "Incompatible";
        return "Enabled";
    }

    /// How the publisher is trusted, in the words the consent copy uses.
    function trustLabel(app) {
        switch (app.trust) {
        case "official": return "Official";
        case "verified": return "Verified";
        case "community": return "Community";
        default: return "Unknown publisher";
        }
    }

    function trustColor(app) {
        if (app.trust === "official") return Colors.primary;
        if (app.trust === "verified") return Colors.tertiary;
        return Colors.textOnSurfaceVariant;
    }

    /// What the app was granted, as a sentence a person can act on. This is the consent
    /// record, read back: grants live in the registry, not in the app's manifest.
    function permissionsLabel(app) {
        const granted = app.granted || [];
        const names = app.dbusNames || [];
        if (granted.length === 0 && names.length === 0) return "Asks for nothing";
        const parts = granted.slice();
        if (names.length > 0) parts.push(names.length + " DBus service" + (names.length === 1 ? "" : "s"));
        return parts.join(", ");
    }

    /// Every permission in words, plus what the sandbox will confine regardless.
    function consentSummary(pending) {
        if (!pending) return "";
        const summaries = pending.summaries || [];
        const names = pending.dbusNames || [];
        let text = summaries.length === 0
            ? "This app asks for no permissions."
            : "It will be allowed to " + summaries.join(", ") + ".";
        if (names.length > 0) {
            text += " It may talk to " + names.join(", ") + " through a filtered bus.";
        }
        if (pending.nativeFiles) {
            text += " It ships native libraries.";
        }
        text += " It runs sandboxed: no access to your files, home or network unless granted above.";
        return text;
    }

    function stateColor(app) {
        if (!app.enabled) return Colors.textOnSurfaceVariant;
        if (!app.compatible) return Colors.warning !== undefined ? Colors.warning : Colors.tertiary;
        return Colors.primary;
    }

    ColumnLayout {
        width: parent.width
        spacing: Theme.spaceMedium

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.padLarge

            ColumnLayout {
                spacing: 2
                Text {
                    text: "Installed apps"
                    color: Colors.textOnSurface
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
                Text {
                    text: root.apps.length + " installed · "
                        + (testMode ? root.apps.filter(function (a) { return a.enabled; }).length
                                    : AppsService.enabledCount) + " enabled"
                    color: Colors.textOnSurfaceVariant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }

            Item { Layout.fillWidth: true }

            ActionPill {
                text: "Install…"
                iconName: "add"
                fixedHeight: 28
                paddingHorizontal: 12
                fontPixelSize: 11
                onClicked: if (!root.testMode) installDialog.open()
            }

            ActionPill {
                text: "Refresh"
                iconName: "refresh"
                fixedHeight: 28
                paddingHorizontal: 12
                fontPixelSize: 11
                onClicked: if (!root.testMode) AppsService.refresh()
            }
        }

        // ---- consent -------------------------------------------------------
        // The card describes the artifact, not a manifest: publisher, version, API level
        // and every permission in words. Installing is a decision the user makes here,
        // with the file's own declarations in front of them.
        GlassCard {
            id: consentCard
            Layout.fillWidth: true
            implicitHeight: consentColumn.implicitHeight + Theme.padLarge * 2
            radius: Theme.radiusMedium
            visible: root.pendingInstall !== null

            ColumnLayout {
                id: consentColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Theme.padMedium
                spacing: Theme.spaceSmall

                Text {
                    text: "Install " + (root.pendingInstall ? (root.pendingInstall.name || root.pendingInstall.id) : "")
                    color: Colors.textOnSurface
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Text {
                    Layout.fillWidth: true
                    text: root.pendingInstall
                        ? root.trustLabel(root.pendingInstall) + " · " + (root.pendingInstall.publisher || "unknown publisher")
                          + " · " + root.pendingInstall.version + " · API " + root.pendingInstall.kernelApi
                        : ""
                    color: Colors.textOnSurfaceVariant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: root.consentSummary(root.pendingInstall)
                    color: (root.pendingInstall && (root.pendingInstall.permissions || []).length > 0)
                        ? Colors.textOnSurface : Colors.textOnSurfaceVariant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    spacing: Theme.spaceSmall
                    ActionPill {
                        text: "Install"
                        fixedHeight: 26
                        paddingHorizontal: 12
                        fontPixelSize: 10
                        onClicked: {
                            if (root.testMode || !root.pendingInstall) return;
                            AppsService.install(root.pendingInstall.path);
                        }
                    }
                    ActionPill {
                        text: "Cancel"
                        variant: "secondary"
                        fixedHeight: 26
                        paddingHorizontal: 12
                        fontPixelSize: 10
                        onClicked: {
                            if (root.testMode) return;
                            AppsService.pendingInstall = null;
                        }
                    }
                }
            }
        }

        FileDialog {
            id: installDialog
            title: "Install an Astral app"
            nameFilters: ["Astral apps (*.astralapp)"]
            onAccepted: AppsService.inspect(selectedFile)
        }

        Rectangle {
            id: listHeader
            Layout.fillWidth: true
            height: 1
            color: Colors.outline
            opacity: 0.18
        }

        Text {
            visible: root.lastError.length > 0
            Layout.fillWidth: true
            text: root.lastError
            color: Colors.error !== undefined ? Colors.error : Colors.tertiary
            font.family: Theme.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.apps

            delegate: GlassCard {
                id: row
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 88
                radius: Theme.radiusMedium

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.padMedium
                    spacing: Theme.spaceMedium

                    MaterialIcon {
                        // Bundled apps read as part of the desktop; installed ones as add-ons.
                        iconName: modelData.preinstalled ? "inventory_2" : "extension"
                        size: 20
                        color: Colors.primary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: modelData.name || modelData.id
                            color: Colors.textOnSurface
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            // Identity, version, and the API it was built against: the
                            // numbers a user needs to judge an app.
                            text: modelData.version + " · API " + modelData.kernelApi
                                + (modelData.preinstalled ? " · bundled" : "")
                                + (modelData.compatible ? "" : " · " + (modelData.reason || "incompatible"))
                            color: modelData.compatible ? Colors.textOnSurfaceVariant
                                                        : (Colors.warning !== undefined ? Colors.warning : Colors.tertiary)
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            // The consent record, read back: what this app may do.
                            text: root.permissionsLabel(modelData)
                            color: Colors.textOnSurfaceVariant
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // Who published it: the first thing a person can judge an app by, sized
                    // as a hairline capsule so it reads as a label rather than a button.
                    // The tint is the colour at low opacity rather than a mixed value, so a
                    // palette role can be a color or a string and both work.
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredHeight: 16
                        Layout.preferredWidth: trustText.implicitWidth + 14
                        visible: modelData.trust !== undefined && modelData.trust !== ""

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: root.trustColor(modelData)
                            opacity: 0.16
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: "transparent"
                            border.width: 1
                            border.color: root.trustColor(modelData)
                            opacity: 0.38
                        }
                        Text {
                            id: trustText
                            anchors.centerIn: parent
                            text: root.trustLabel(modelData)
                            color: root.trustColor(modelData)
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Medium
                        }
                    }

                    Text {
                        text: root.stateLabel(modelData)
                        color: root.stateColor(modelData)
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    ActionPill {
                        text: modelData.enabled ? "Disable" : "Enable"
                        fixedHeight: 26
                        paddingHorizontal: 10
                        fontPixelSize: 10
                        onClicked: {
                            if (!root.testMode) {
                                AppsService.setEnabled(modelData.id, !modelData.enabled);
                            }
                        }
                    }

                    ActionPill {
                        text: "Remove"
                        visible: root.canRemove(modelData)
                        variant: "secondary"
                        fixedHeight: 26
                        paddingHorizontal: 10
                        fontPixelSize: 10
                        onClicked: {
                            if (!root.testMode) {
                                AppsService.remove(modelData.id, false);
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: root.apps.length === 0
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceMedium
            text: "No apps installed yet."
            color: Colors.textOnSurfaceVariant
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }
    }
}
