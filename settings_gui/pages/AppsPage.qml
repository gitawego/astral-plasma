import QtQuick
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

    title: "Apps"
    subtitle: "Installed apps, their versions, and what they are allowed to do"
    zones: [
        { id: "apps", label: "Installed", anchor: listHeader }
    ]

    property bool testMode: false
    /// Injected by the harness: the rows to render (the service cannot run there).
    property var testApps: []

    readonly property var apps: testMode ? testApps : AppsService.apps
    readonly property string lastError: testMode ? "" : AppsService.lastError

    Component.onCompleted: if (!testMode) AppsService.refresh()

    function stateLabel(app) {
        if (!app.enabled) return "Disabled";
        if (!app.compatible) return "Incompatible";
        return "Enabled";
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
                text: "Refresh"
                iconName: "refresh"
                fixedHeight: 28
                paddingHorizontal: 12
                fontPixelSize: 11
                onClicked: if (!root.testMode) AppsService.refresh()
            }
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
                implicitHeight: 74
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
                            // Identity, version, and the API it was built against: the three
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
