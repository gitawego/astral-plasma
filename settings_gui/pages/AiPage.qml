import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

ColumnLayout {
    id: root

    property bool testMode: false
    property bool testAiEnabled: true
    property string testDockPillMode: "dynamic"
    property real testWarningThreshold: 80
    property real testCriticalThreshold: 95
    property int testPollInterval: 5
    property bool testGeminiMonthlyEnabled: true
    property real testGeminiMonthlyRemainingPercent: 85.0
    property int testGeminiMonthlyResetDay: 1
    property var testProviders: null
    property bool testIsAuthenticating: false
    property string testAuthenticatingEmail: ""

    readonly property bool isAuthenticating: testMode ? testIsAuthenticating : ((typeof AiTokenService !== "undefined") ? AiTokenService.isAuthenticating : false)
    readonly property string authenticatingEmail: testMode ? testAuthenticatingEmail : ((typeof AiTokenService !== "undefined") ? AiTokenService.authenticatingEmail : "")

    function cancelAuth() {
        if (testMode) {
            testIsAuthenticating = false;
            testAuthenticatingEmail = "";
        } else if (typeof AiTokenService !== "undefined") {
            AiTokenService.cancelLogin();
        }
    }

    readonly property bool aiEnabled: testMode ? testAiEnabled : ((typeof Config !== "undefined") ? Config.aiEnabled : true)
    readonly property string dockPillMode: testMode ? testDockPillMode : ((typeof Config !== "undefined") ? Config.aiDockPillMode : "dynamic")
    readonly property real warningThreshold: testMode ? testWarningThreshold : ((typeof Config !== "undefined") ? Config.aiWarningThreshold : 80)
    readonly property real criticalThreshold: testMode ? testCriticalThreshold : ((typeof Config !== "undefined") ? Config.aiCriticalThreshold : 95)
    readonly property int pollInterval: testMode ? testPollInterval : ((typeof Config !== "undefined") ? Config.aiPollIntervalMinutes : 5)
    readonly property bool geminiMonthlyEnabled: testMode ? testGeminiMonthlyEnabled : ((typeof Config !== "undefined" && Config.aiGeminiMonthlyEnabled !== undefined) ? Config.aiGeminiMonthlyEnabled : true)
    readonly property real geminiMonthlyRemainingPercent: testMode ? testGeminiMonthlyRemainingPercent : ((typeof Config !== "undefined" && Config.aiGeminiMonthlyRemainingPercent !== undefined) ? Config.aiGeminiMonthlyRemainingPercent : 85.0)
    readonly property int geminiMonthlyResetDay: testMode ? testGeminiMonthlyResetDay : ((typeof Config !== "undefined" && Config.aiGeminiMonthlyResetDay !== undefined) ? Config.aiGeminiMonthlyResetDay : 1)
    readonly property var providersList: {
        if (testMode && testProviders !== null) return testProviders;
        if (typeof AiTokenService !== "undefined" && AiTokenService.providers) return AiTokenService.providers;
        return [];
    }

    function setAiEnabled(v) {
        if (testMode) {
            testAiEnabled = v;
        } else if (typeof Config !== "undefined") {
            Config.setAiEnabled(v);
        }
    }

    function setDockPillMode(m) {
        if (testMode) {
            testDockPillMode = m;
        } else if (typeof Config !== "undefined") {
            Config.setAiDockPillMode(m);
        }
    }

    function setThresholds(warn, crit) {
        if (testMode) {
            testWarningThreshold = warn;
            testCriticalThreshold = crit;
        } else if (typeof Config !== "undefined") {
            Config.setAiThresholds(warn, crit);
        }
    }

    function setPollInterval(mins) {
        if (testMode) {
            testPollInterval = mins;
        } else if (typeof Config !== "undefined") {
            Config.setAiPollInterval(mins);
        }
    }

    function setGeminiMonthlyEnabled(v) {
        if (testMode) {
            testGeminiMonthlyEnabled = v;
        } else if (typeof Config !== "undefined") {
            Config.setAiGeminiMonthlyEnabled(v);
        }
    }

    function setGeminiMonthlyRemainingPercent(p) {
        if (testMode) {
            testGeminiMonthlyRemainingPercent = p;
        } else if (typeof Config !== "undefined") {
            Config.setAiGeminiMonthlyRemainingPercent(p);
        }
    }

    function setGeminiMonthlyResetDay(d) {
        if (testMode) {
            testGeminiMonthlyResetDay = d;
        } else if (typeof Config !== "undefined") {
            Config.setAiGeminiMonthlyResetDay(d);
        }
    }

    Layout.fillWidth: true
    spacing: 16

    // Header & Description
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
            text: "AI Token Plans"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontTitleLarge
            font.weight: Font.Bold
            color: Colors.m3onSurface
        }

        Text {
            text: "Auto-discovered coding plans, quotas, and theme warning thresholds"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBodySmall
            color: Colors.m3onSurfaceVariant
        }
    }

    // Master Integration Toggle Card
    Rectangle {
        Layout.fillWidth: true
        height: 64
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            spacing: Theme.spaceMedium

            MaterialIcon {
                text: "psychology"
                size: 26
                color: root.aiEnabled ? Colors.primary : Colors.m3onSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "AI Quota Tracking"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Text {
                    text: root.aiEnabled ? "Auto-discovering OpenCode, Gemini, Mimo & MiniMax" : "AI quota monitoring is disabled"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                }
            }

            // M3 Expressive Pill Switch
            Rectangle {
                width: 48
                height: 26
                radius: 13
                color: root.aiEnabled ? Colors.primary : Colors.surfaceContainerHighest
                border.color: root.aiEnabled ? Colors.primary : Theme.borderSubtle
                border.width: 1

                Behavior on color { ColorAnimation { duration: 150 } }

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    color: root.aiEnabled ? Colors.textOnPrimary : Colors.m3onSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.aiEnabled ? parent.width - width - 3 : 3

                    Behavior on x {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.setAiEnabled(!root.aiEnabled);
                    }
                }
            }
        }
    }

    // Preferences & Theme Integration Card
    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        implicitHeight: prefCol.implicitHeight + Theme.padLarge * 2
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            id: prefCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.padLarge
            spacing: 16

            Text {
                text: "Theme & Warning Configuration"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Colors.m3onSurface
            }

            // Dock Pill Display Mode
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "Left Dock Indicator"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                RowLayout {
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "dynamic", label: "Dynamic (Active / Warning)" },
                            { id: "always", label: "Always Visible" },
                            { id: "never", label: "Hidden" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            height: 32
                            implicitWidth: modeLabel.implicitWidth + 20
                            radius: 16
                            color: root.dockPillMode === modelData.id ? Colors.primary : Colors.surfaceContainerHighest
                            border.color: root.dockPillMode === modelData.id ? Colors.primary : Theme.borderSubtle
                            border.width: 1

                            Text {
                                id: modeLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: root.dockPillMode === modelData.id ? Font.Bold : Font.Normal
                                color: root.dockPillMode === modelData.id ? Colors.textOnPrimary : Colors.m3onSurface
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.setDockPillMode(modelData.id);
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderSubtle
                opacity: 0.4
            }

            // Warning Thresholds
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                // Warning Threshold (Amber)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Text {
                            text: "Amber Warning Threshold"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurface
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(root.warningThreshold) + "% used"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#F59E0B"
                        }
                    }

                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [70, 75, 80, 85]
                            delegate: Rectangle {
                                required property int modelData
                                height: 28
                                Layout.fillWidth: true
                                radius: 14
                                color: root.warningThreshold === modelData ? Qt.alpha("#F59E0B", 0.25) : Colors.surfaceContainerHighest
                                border.color: root.warningThreshold === modelData ? "#F59E0B" : Theme.borderSubtle
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData + "%"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: root.warningThreshold === modelData ? Font.Bold : Font.Normal
                                    color: root.warningThreshold === modelData ? "#F59E0B" : Colors.m3onSurface
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.setThresholds(modelData, root.criticalThreshold);
                                    }
                                }
                            }
                        }
                    }
                }

                // Critical Threshold (Rose)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Text {
                            text: "Rose Critical Threshold"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurface
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(root.criticalThreshold) + "% used"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: "#E05353"
                        }
                    }

                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [90, 93, 95, 98]
                            delegate: Rectangle {
                                required property int modelData
                                height: 28
                                Layout.fillWidth: true
                                radius: 14
                                color: root.criticalThreshold === modelData ? Qt.alpha("#E05353", 0.25) : Colors.surfaceContainerHighest
                                border.color: root.criticalThreshold === modelData ? "#E05353" : Theme.borderSubtle
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData + "%"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: root.criticalThreshold === modelData ? Font.Bold : Font.Normal
                                    color: root.criticalThreshold === modelData ? "#E05353" : Colors.m3onSurface
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.setThresholds(root.warningThreshold, modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderSubtle
                opacity: 0.4
            }

            // Polling Interval
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Text {
                        text: "Background Polling Cadence"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Colors.m3onSurface
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Every " + root.pollInterval + " minutes"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Colors.m3onSurfaceVariant
                    }
                }

                RowLayout {
                    spacing: 8
                    Repeater {
                        model: [1, 2, 5, 10, 15]
                        delegate: Rectangle {
                            required property int modelData
                            height: 28
                            implicitWidth: intervalText.implicitWidth + 20
                            radius: 14
                            color: root.pollInterval === modelData ? Colors.primary : Colors.surfaceContainerHighest
                            border.color: root.pollInterval === modelData ? Colors.primary : Theme.borderSubtle
                            border.width: 1

                            Text {
                                id: intervalText
                                anchors.centerIn: parent
                                text: modelData + "m"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: root.pollInterval === modelData ? Font.Bold : Font.Normal
                                color: root.pollInterval === modelData ? Colors.textOnPrimary : Colors.m3onSurface
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.setPollInterval(modelData);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Detected Providers & Quotas
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Configured Providers & Quotas"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Colors.m3onSurface
            }

            Item { Layout.fillWidth: true }

            PillButton {
                label: "Rescan All Models"
                iconText: "refresh"
                onClicked: {
                    if (typeof AiTokenService !== "undefined") {
                        AiTokenService.refresh(true);
                    }
                }
            }
        }

        Repeater {
            model: root.providersList
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                radius: Theme.radiusMedium
                color: Colors.surfaceContainer
                border.color: Theme.borderSubtle
                border.width: 1
                implicitHeight: cardContent.implicitHeight + 24

                ColumnLayout {
                    id: cardContent
                    anchors.fill: parent
                    anchors.margins: Theme.padLarge
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ThemedIcon {
                            source: (typeof Config !== "undefined" && typeof Config.providerIconUrl === "function") ? Config.providerIconUrl(modelData.provider_id || modelData.provider) : ""
                            materialIcon: modelData.icon || "auto_awesome"
                            size: 20
                            color: Colors.primary
                        }

                        Text {
                            text: modelData.display_name
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: Colors.m3onSurface
                        }

                        Rectangle {
                            visible: modelData.plan_type !== null && modelData.plan_type !== ""
                            height: 18
                            implicitWidth: planBadge.implicitWidth + 10
                            radius: 9
                            color: Qt.alpha(Colors.primary, 0.15)
                            border.color: Qt.alpha(Colors.primary, 0.3)
                            border.width: 1

                            Text {
                                id: planBadge
                                anchors.centerIn: parent
                                text: modelData.plan_type || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: Colors.primary
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Health badge
                        Rectangle {
                            height: 20
                            implicitWidth: stText.implicitWidth + 12
                            radius: 10
                            color: modelData.is_available ? Qt.alpha("#10B981", 0.15) : Qt.alpha("#E05353", 0.15)
                            border.color: modelData.is_available ? "#10B981" : "#E05353"
                            border.width: 1

                            Text {
                                id: stText
                                anchors.centerIn: parent
                                text: modelData.is_available ? "Active" : "Unavailable"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: modelData.is_available ? "#10B981" : "#E05353"
                            }
                        }
                    }

                    // Account identity
                    Text {
                        visible: modelData.account_email !== null && modelData.account_email !== ""
                        text: "Active in CLI: " + (modelData.account_email || "")
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Colors.m3onSurfaceVariant
                    }

                    // Configured Accounts Management (Gemini & Multi-Account Providers)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: (modelData.provider_id === "gemini" || modelData.provider === "gemini")

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.borderSubtle
                            opacity: 0.4
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Configured Accounts"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: Colors.m3onSurface
                            }

                            Item { Layout.fillWidth: true }

                            // Sign In with Google Button
                            Rectangle {
                                height: 28
                                implicitWidth: addBtnRow.implicitWidth + 20
                                radius: 14
                                color: (!root.isAuthenticating && addMouse.containsMouse) ? Qt.alpha(Colors.primary, 0.2) : Qt.alpha(Colors.primary, 0.1)
                                border.color: (!root.isAuthenticating && addMouse.containsMouse) ? Colors.primary : Qt.alpha(Colors.primary, 0.3)
                                border.width: 1

                                RowLayout {
                                    id: addBtnRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    MaterialIcon {
                                        text: root.isAuthenticating ? "sync" : "add"
                                        size: 15
                                        color: Colors.primary

                                        RotationAnimation on rotation {
                                            running: root.isAuthenticating
                                            from: 0
                                            to: 360
                                            duration: 1000
                                            loops: Animation.Infinite
                                        }
                                    }

                                    Text {
                                        text: root.isAuthenticating ? "Signing in..." : "Sign in with Google"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: Colors.primary
                                    }
                                }

                                MouseArea {
                                    id: addMouse
                                    anchors.fill: parent
                                    cursorShape: root.isAuthenticating ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    hoverEnabled: !root.isAuthenticating
                                    onClicked: {
                                        if (!root.isAuthenticating && typeof AiTokenService !== "undefined") {
                                            AiTokenService.loginGemini("");
                                        }
                                    }
                                }
                            }

                            // Prominent Cancel Button when authenticating
                            ActionPill {
                                id: headerCancelBtn
                                visible: root.isAuthenticating
                                text: "Cancel"
                                icon: "close"
                                iconSize: 13
                                variant: "danger"
                                fixedHeight: 28
                                pill: true
                                fontPixelSize: 11
                                fontWeight: Font.DemiBold
                                paddingHorizontal: 12
                                onClicked: {
                                    root.cancelAuth();
                                }
                            }
                        }

                        // Account Items Repeater
                        Repeater {
                            model: modelData.accounts || []
                            delegate: Rectangle {
                                id: accDelegate
                                required property var modelData
                                Layout.fillWidth: true
                                height: 46
                                radius: Theme.radiusSmall
                                color: modelData.is_active ? Qt.alpha(Colors.primary, 0.08) : (accRowHover.containsMouse ? Colors.pillHover : Colors.surfaceContainerHighest)
                                border.color: modelData.is_active ? Qt.alpha(Colors.primary, 0.3) : Theme.borderSubtle
                                border.width: 1

                                MouseArea {
                                    id: accRowHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    MaterialIcon {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: modelData.is_active ? "check_circle" : "account_circle"
                                        size: 18
                                        color: modelData.is_active ? "#10B981" : Colors.m3onSurfaceVariant
                                    }

                                    ColumnLayout {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 120
                                        Layout.maximumWidth: 99999
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.identity || modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: modelData.is_active ? Font.DemiBold : Font.Normal
                                            color: Colors.m3onSurface
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            visible: modelData.label && modelData.label !== modelData.identity
                                            text: modelData.label || ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Colors.m3onSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Flexible spacer ensuring rightmost button columns lock to consistent positions
                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    // Column 1: Active Badge / Switch Button (Uniform 64px width)
                                    ActionPill {
                                        Layout.preferredWidth: 64
                                        Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter
                                        fixedWidth: 64
                                        fixedHeight: 26
                                        pill: true
                                        variant: modelData.is_active ? "active" : "secondary"
                                        text: modelData.is_active ? "Active" : "Switch"
                                        interactive: !modelData.is_active && !root.isAuthenticating
                                        opacity: (!modelData.is_active && root.isAuthenticating) ? 0.45 : 1.0
                                        fontPixelSize: 11
                                        fontWeight: Font.DemiBold
                                        onClicked: {
                                            if (!modelData.is_active && !root.isAuthenticating && typeof AiTokenService !== "undefined") {
                                                AiTokenService.switchGeminiAccount(modelData.identity || modelData.id);
                                            }
                                        }
                                    }

                                    // Column 2: Re-auth / Cancel Button (Uniform 80px width)
                                    ActionPill {
                                        readonly property bool isThisAccountAuthenticating: root.isAuthenticating && (root.authenticatingEmail && (root.authenticatingEmail.toLowerCase() === (modelData.identity || "").toLowerCase() || root.authenticatingEmail === modelData.id))

                                        Layout.preferredWidth: 80
                                        Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter
                                        fixedWidth: 80
                                        fixedHeight: 26
                                        pill: true
                                        icon: isThisAccountAuthenticating ? "close" : "vpn_key"
                                        iconSize: isThisAccountAuthenticating ? 13 : 12
                                        text: isThisAccountAuthenticating ? "Cancel" : "Re-auth"
                                        variant: isThisAccountAuthenticating ? "danger" : "info"
                                        fontPixelSize: 11
                                        fontWeight: Font.DemiBold
                                        opacity: (root.isAuthenticating && !isThisAccountAuthenticating) ? 0.45 : 1.0
                                        interactive: !root.isAuthenticating || isThisAccountAuthenticating
                                        onClicked: {
                                            if (isThisAccountAuthenticating) {
                                                root.cancelAuth();
                                            } else if (!root.isAuthenticating && typeof AiTokenService !== "undefined") {
                                                AiTokenService.loginGemini(modelData.identity);
                                            }
                                        }
                                    }

                                    // Column 3: Remove Button (Uniform 82px width)
                                    ActionPill {
                                        Layout.preferredWidth: 82
                                        Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter
                                        fixedWidth: 82
                                        fixedHeight: 26
                                        pill: true
                                        icon: "delete_outline"
                                        iconSize: 13
                                        text: "Remove"
                                        variant: "danger"
                                        fontPixelSize: 11
                                        fontWeight: Font.DemiBold
                                        opacity: root.isAuthenticating ? 0.45 : 1.0
                                        interactive: !root.isAuthenticating
                                        onClicked: {
                                            if (!root.isAuthenticating && typeof AiTokenService !== "undefined") {
                                                AiTokenService.removeAccount("gemini", modelData.id || modelData.identity);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Windows progress list
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: modelData.windows && modelData.windows.length > 0

                        Repeater {
                            model: modelData.windows || []
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: {
                                            switch (modelData.label) {
                                                case "5h": return "5-Hour Rolling Limit";
                                                case "weekly": return "Weekly Limit";
                                                case "monthly": return "Monthly Limit";
                                                default: return modelData.label;
                                            }
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: Colors.m3onSurface
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: Math.round(modelData.remaining_percent) + "% remaining (" + Math.round(modelData.used_percent) + "% used)"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: (modelData.used_percent >= root.criticalThreshold)
                                            ? "#E05353"
                                            : ((modelData.used_percent >= root.warningThreshold) ? "#F59E0B" : Colors.primary)
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 6
                                    radius: 3
                                    color: Colors.surfaceContainerHighest

                                    Rectangle {
                                        width: Math.max(0, parent.width * (modelData.used_percent / 100.0))
                                        height: parent.height
                                        radius: 3
                                        color: (modelData.used_percent >= root.criticalThreshold)
                                            ? "#E05353"
                                            : ((modelData.used_percent >= root.warningThreshold) ? "#F59E0B" : Colors.primary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Spacer
    Item {
        Layout.fillWidth: true
        height: 32
    }
}
