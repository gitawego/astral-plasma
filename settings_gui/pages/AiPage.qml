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

    // Gemini Monthly Quota (Config-Driven) Card
    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        implicitHeight: geminiMonthlyCol.implicitHeight + Theme.padLarge * 2
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            id: geminiMonthlyCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.padLarge
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                MaterialIcon {
                    text: "calendar_month"
                    size: 24
                    color: root.geminiMonthlyEnabled ? Colors.primary : Colors.m3onSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Gemini Monthly Quota (Config-Driven)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: "Enables monthly quota tracking & schedule calculation for Google Gemini plans"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Colors.m3onSurfaceVariant
                    }
                }

                // Switch
                Rectangle {
                    width: 44
                    height: 24
                    radius: 12
                    color: root.geminiMonthlyEnabled ? Colors.primary : Colors.surfaceContainerHighest
                    border.color: root.geminiMonthlyEnabled ? Colors.primary : Theme.borderSubtle
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: root.geminiMonthlyEnabled ? Colors.textOnPrimary : Colors.m3onSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.geminiMonthlyEnabled ? parent.width - width - 3 : 3

                        Behavior on x {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.setGeminiMonthlyEnabled(!root.geminiMonthlyEnabled);
                        }
                    }
                }
            }

            // Controls visible when enabled
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 16
                visible: root.geminiMonthlyEnabled

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                    opacity: 0.4
                }

                // Default Remaining Quota
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Text {
                            text: "Default Remaining Quota"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurface
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(root.geminiMonthlyRemainingPercent) + "% remaining"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: ((100.0 - root.geminiMonthlyRemainingPercent) >= root.criticalThreshold)
                                ? "#E05353"
                                : (((100.0 - root.geminiMonthlyRemainingPercent) >= root.warningThreshold) ? "#F59E0B" : Colors.primary)
                        }
                    }

                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [50, 65, 75, 80, 85, 90, 95]
                            delegate: Rectangle {
                                required property int modelData
                                height: 28
                                Layout.fillWidth: true
                                radius: 14
                                color: Math.round(root.geminiMonthlyRemainingPercent) === modelData ? Colors.primary : Colors.surfaceContainerHighest
                                border.color: Math.round(root.geminiMonthlyRemainingPercent) === modelData ? Colors.primary : Theme.borderSubtle
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData + "%"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Math.round(root.geminiMonthlyRemainingPercent) === modelData ? Font.Bold : Font.Normal
                                    color: Math.round(root.geminiMonthlyRemainingPercent) === modelData ? Colors.textOnPrimary : Colors.m3onSurface
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.setGeminiMonthlyRemainingPercent(modelData);
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

                // Monthly Reset Day
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Text {
                            text: "Monthly Reset Day of Month"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurface
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "Day " + root.geminiMonthlyResetDay + " of every month"
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Colors.m3onSurfaceVariant
                        }
                    }

                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [
                                { day: 1, label: "1st" },
                                { day: 5, label: "5th" },
                                { day: 10, label: "10th" },
                                { day: 15, label: "15th" },
                                { day: 20, label: "20th" },
                                { day: 25, label: "25th" },
                                { day: 28, label: "28th" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                height: 28
                                Layout.fillWidth: true
                                radius: 14
                                color: root.geminiMonthlyResetDay === modelData.day ? Colors.primary : Colors.surfaceContainerHighest
                                border.color: root.geminiMonthlyResetDay === modelData.day ? Colors.primary : Theme.borderSubtle
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: root.geminiMonthlyResetDay === modelData.day ? Font.Bold : Font.Normal
                                    color: root.geminiMonthlyResetDay === modelData.day ? Colors.textOnPrimary : Colors.m3onSurface
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.setGeminiMonthlyResetDay(modelData.day);
                                    }
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
                                height: 26
                                implicitWidth: addBtnRow.implicitWidth + 16
                                radius: 13
                                color: addMouse.containsMouse ? Qt.alpha(Colors.primary, 0.2) : Qt.alpha(Colors.primary, 0.1)
                                border.color: addMouse.containsMouse ? Colors.primary : Qt.alpha(Colors.primary, 0.3)
                                border.width: 1

                                RowLayout {
                                    id: addBtnRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    MaterialIcon {
                                        text: (typeof AiTokenService !== "undefined" && AiTokenService.isAuthenticating) ? "sync" : "add"
                                        size: 14
                                        color: Colors.primary
                                    }

                                    Text {
                                        text: (typeof AiTokenService !== "undefined" && AiTokenService.isAuthenticating) ? "Signing in..." : "Sign in with Google"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: Colors.primary
                                    }
                                }

                                MouseArea {
                                    id: addMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: {
                                        if (typeof AiTokenService !== "undefined") {
                                            AiTokenService.loginGemini("");
                                        }
                                    }
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
                                height: 38
                                radius: 8
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
                                    spacing: 8

                                    MaterialIcon {
                                        text: modelData.is_active ? "check_circle" : "account_circle"
                                        size: 16
                                        color: modelData.is_active ? "#10B981" : Colors.m3onSurfaceVariant
                                    }

                                    ColumnLayout {
                                        spacing: 1
                                        Layout.fillWidth: true

                                        Text {
                                            text: modelData.identity || modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: modelData.is_active ? Font.Bold : Font.Normal
                                            color: Colors.m3onSurface
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: modelData.label && modelData.label !== modelData.identity
                                            text: modelData.label || ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 9
                                            color: Colors.m3onSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Active badge or Switch button
                                    // Active badge or Switch button
                                    ActionPill {
                                        visible: modelData.is_active
                                        text: "Active"
                                        variant: "active"
                                        pill: true
                                        interactive: false
                                        fontPixelSize: 9
                                        fontWeight: Font.Bold
                                        fixedHeight: 20
                                        paddingHorizontal: 8
                                    }

                                    ActionPill {
                                        visible: !modelData.is_active
                                        text: "Switch"
                                        variant: "secondary"
                                        pill: true
                                        fontPixelSize: 9
                                        fixedHeight: 20
                                        paddingHorizontal: 8
                                        onClicked: {
                                            if (typeof AiTokenService !== "undefined") {
                                                AiTokenService.switchGeminiAccount(modelData.identity || modelData.id);
                                            }
                                        }
                                    }

                                    // Re-auth button
                                    ActionPill {
                                        icon: "vpn_key"
                                        text: "Re-auth"
                                        variant: "info"
                                        pill: true
                                        fontPixelSize: 9
                                        fixedHeight: 20
                                        paddingHorizontal: 8
                                        spacing: 3
                                        onClicked: {
                                            if (typeof AiTokenService !== "undefined") {
                                                AiTokenService.loginGemini(modelData.identity);
                                            }
                                        }
                                    }

                                    // Remove button
                                    ActionPill {
                                        icon: "delete_outline"
                                        variant: "danger"
                                        pill: true
                                        fixedWidth: 20
                                        fixedHeight: 20
                                        iconSize: 13
                                        onClicked: {
                                            if (typeof AiTokenService !== "undefined") {
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
