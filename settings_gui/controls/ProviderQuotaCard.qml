import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../components/StateColor.js" as StateColor

// ============================================================================
// Provider quota card
// ============================================================================
// One provider's standing, in a shape any page can reuse: identity, availability,
// and one runway per rate-limit window. It is *display only* - a caller supplies
// the provider object and drops its own controls (sign-in, account switching) into
// the footer slot, which keeps authentication logic out of a quota card.
//
// Reused pieces: `QuotaRunway` for the windows, `StateColor` for the availability
// state, the shell's glass card conventions for the surface.
Rectangle {
    id: root

    /// The daemon's provider object: `display_name`, `provider_id` (or
    /// `provider`), `icon`, `plan_type`, `is_available`, `account_email`,
    /// `windows: [{ label, used_percent, remaining_percent, reset_at }]`.
    property var provider: null
    property real warningThreshold: 80
    property real criticalThreshold: 95
    /// Injectable clock, forwarded to the runways so the reset text is testable.
    property real now: Date.now()
    /// Compact windows (the grid variant).
    property bool compactRunways: true

    /// Caller-owned footer (sign-in, account lists, actions).
    default property alias footer: footerSlot.data

    readonly property string providerId: root.provider
        ? String(root.provider.provider_id || root.provider.provider || "") : ""
    readonly property string displayName: root.provider
        ? String(root.provider.display_name || root.providerId) : ""
    readonly property bool available: root.provider ? root.provider.is_available !== false : false
    readonly property string planType: root.provider && root.provider.plan_type
        ? String(root.provider.plan_type) : ""
    readonly property string identity: root.provider && root.provider.account_email
        ? String(root.provider.account_email) : ""
    readonly property var windows: (root.provider && root.provider.windows && root.provider.windows.length > 0)
        ? root.provider.windows : []

    /// Availability in the shell's shared state vocabulary: unreachable is
    /// `critical` (something is wrong), reachable is `ok`.
    /// Machine strings (account identifiers) use the mono face. The fallback keeps
    /// a card rendered outside the shell (harness, preview) in a real mono stack
    /// instead of the body face.
    readonly property string monoFamily: (typeof Theme !== "undefined" && Theme.fontMonospace)
        ? Theme.fontMonospace : "monospace"

    readonly property string severity: root.available ? "ok" : "critical"
    readonly property color stateColor: StateColor.colorFor(root.severity, Colors)
    readonly property string stateText: root.available ? "Active" : "Unavailable"

    Layout.fillWidth: true
    radius: Theme.radiusMedium
    color: Colors.surfaceContainer
    border.color: Theme.borderSubtle
    border.width: 1
    implicitHeight: card.implicitHeight + Theme.padLarge * 2

    /// Test / introspection surface.
    property alias nameItem: nameText
    property alias stateItem: stateTextItem
    property alias identityItem: identityText
    property alias runwayRepeaterItem: runwayRepeater
    property alias emptyItem: emptyWindows

    ColumnLayout {
        id: card
        anchors.fill: parent
        anchors.margins: Theme.padLarge
        spacing: Theme.spaceSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSmall

            ThemedIcon {
                source: (typeof Config !== "undefined" && typeof Config.providerIconUrl === "function")
                    ? Config.providerIconUrl(root.providerId) : ""
                materialIcon: (root.provider && root.provider.icon) || "auto_awesome"
                size: 20
                color: Colors.primary
            }

            Text {
                id: nameText
                text: root.displayName
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.Bold
                color: Colors.m3onSurface
                elide: Text.ElideRight
            }

            Rectangle {
                visible: root.planType !== ""
                height: 18
                implicitWidth: planText.implicitWidth + 10
                radius: 9
                color: Qt.alpha(Colors.primary, 0.15)
                border.color: Qt.alpha(Colors.primary, 0.3)
                border.width: 1

                Text {
                    id: planText
                    anchors.centerIn: parent
                    text: root.planType
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: Colors.primary
                }
            }

            Item { Layout.fillWidth: true }

            // Availability pill, through the shared state vocabulary.
            Rectangle {
                height: 20
                implicitWidth: stateTextItem.implicitWidth + 12
                radius: 10
                color: Qt.alpha(root.stateColor, 0.15)
                border.color: root.stateColor
                border.width: 1

                Text {
                    id: stateTextItem
                    anchors.centerIn: parent
                    text: root.stateText
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: root.stateColor
                }
            }
        }

        Text {
            id: identityText
            Layout.fillWidth: true
            visible: root.identity !== ""
            // Mono: an account is a machine identifier, not prose.
            text: root.identity
            font.family: root.monoFamily
            font.pixelSize: 11
            color: Colors.m3onSurfaceVariant
            elide: Text.ElideMiddle
        }

        // One runway per window: allowance and deadline on one axis.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                id: runwayRepeater
                model: root.windows

                delegate: QuotaRunway {
                    required property var modelData
                    Layout.fillWidth: true
                    remainingPercent: (modelData && modelData.remaining_percent !== undefined)
                        ? Number(modelData.remaining_percent) : -1
                    windowLabel: (modelData && modelData.label) ? String(modelData.label) : ""
                    resetAt: (modelData && modelData.reset_at) ? String(modelData.reset_at) : ""
                    warningThreshold: root.warningThreshold
                    criticalThreshold: root.criticalThreshold
                    now: root.now
                    compact: root.compactRunways
                }
            }

            // An empty state is direction, not mood: say what is missing.
            Text {
                id: emptyWindows
                Layout.fillWidth: true
                visible: root.windows.length === 0
                text: "No rate-limit window reported yet — waiting for the first poll."
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Colors.m3onSurfaceVariant
                opacity: 0.85
                wrapMode: Text.WordWrap
            }
        }

        ColumnLayout {
            id: footerSlot
            Layout.fillWidth: true
            spacing: Theme.spaceSmall
        }
    }
}
