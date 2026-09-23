import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitWidth: 320
    implicitHeight: mainLayout.implicitHeight + Theme.padLarge * 2

    property bool testMode: false
    property var testProviders: null
    property string testWarningLevel: "normal"
    property int activeProviderIndex: 0

    readonly property var providersList: {
        if (testMode && testProviders !== null) return testProviders;
        if (typeof AiTokenService !== "undefined" && AiTokenService.providers) return AiTokenService.providers;
        return [];
    }

    readonly property string warningLevel: {
        if (testMode) return testWarningLevel;
        if (typeof AiTokenService !== "undefined" && AiTokenService.warningLevel) return AiTokenService.warningLevel;
        return "normal";
    }

    readonly property bool isRefreshing: {
        if (typeof AiTokenService !== "undefined") return AiTokenService.isRefreshing;
        return false;
    }

    function getProviderShortName(p) {
        if (!p) return "";
        const pid = (p.provider_id || p.provider || "").toLowerCase();
        if (pid === "gemini") return "Gemini";
        if (pid === "opencode-go" || pid === "opencode") return "OpenCode";
        if (pid.indexOf("minimax") !== -1) return "MiniMax";
        if (pid.indexOf("xiaomi") !== -1 || pid.indexOf("mimo") !== -1) return "MiMo";
        if (pid.indexOf("deepseek") !== -1) return "DeepSeek";
        if (pid.indexOf("claude") !== -1 || pid.indexOf("anthropic") !== -1) return "Claude";
        if (pid.indexOf("openai") !== -1) return "OpenAI";
        return p.display_name || pid;
    }

    function getProviderIcon(p) {
        if (!p) return "auto_awesome";
        const pid = (p.provider_id || p.provider || "").toLowerCase();
        if (pid === "gemini") return "auto_awesome";
        if (pid.indexOf("opencode") !== -1) return "terminal";
        if (pid.indexOf("minimax") !== -1) return "bolt";
        if (pid.indexOf("xiaomi") !== -1 || pid.indexOf("mimo") !== -1) return "smartphone";
        if (pid.indexOf("deepseek") !== -1) return "psychology";
        return "token";
    }

    function syncActiveTab() {
        if (!root.providersList || root.providersList.length === 0) return;
        const lastId = (typeof AiTokenService !== "undefined" && AiTokenService.lastActiveProviderId)
            ? AiTokenService.lastActiveProviderId
            : "";
        if (lastId) {
            for (let i = 0; i < root.providersList.length; i++) {
                const pid = root.providersList[i].provider_id || root.providersList[i].provider;
                if (pid === lastId) {
                    root.activeProviderIndex = i;
                    return;
                }
            }
        }
        if (root.activeProviderIndex >= root.providersList.length) {
            root.activeProviderIndex = 0;
        }
    }

    onVisibleChanged: {
        if (visible) syncActiveTab();
    }

    onProvidersListChanged: {
        syncActiveTab();
    }

    readonly property var currentProvider: (root.providersList && root.providersList.length > activeProviderIndex)
        ? root.providersList[activeProviderIndex]
        : null

    property string selectedAccountIdentity: ""

    readonly property var activeAccount: {
        if (!currentProvider || !currentProvider.accounts) return null;
        const activeGemini = (typeof AiTokenService !== "undefined" && AiTokenService.activeGeminiEmail) ? AiTokenService.activeGeminiEmail.toLowerCase() : "";
        if (activeGemini && (currentProvider.provider_id === "gemini" || currentProvider.provider === "gemini")) {
            for (let i = 0; i < currentProvider.accounts.length; i++) {
                if (currentProvider.accounts[i].identity.toLowerCase() === activeGemini || currentProvider.accounts[i].id === activeGemini) {
                    return currentProvider.accounts[i];
                }
            }
        }
        for (let i = 0; i < currentProvider.accounts.length; i++) {
            if (currentProvider.accounts[i].is_active) return currentProvider.accounts[i];
        }
        return currentProvider.accounts.length > 0 ? currentProvider.accounts[0] : null;
    }

    readonly property var selectedAccount: {
        if (!currentProvider || !currentProvider.accounts || currentProvider.accounts.length === 0) return null;
        if (selectedAccountIdentity) {
            for (let i = 0; i < currentProvider.accounts.length; i++) {
                if (currentProvider.accounts[i].identity === selectedAccountIdentity || currentProvider.accounts[i].id === selectedAccountIdentity) {
                    return currentProvider.accounts[i];
                }
            }
        }
        return activeAccount;
    }

    readonly property var currentWindows: {
        if (selectedAccount && selectedAccount.windows && selectedAccount.windows.length > 0) {
            return selectedAccount.windows;
        }
        if (currentProvider && currentProvider.windows && currentProvider.windows.length > 0) {
            return currentProvider.windows;
        }
        return [];
    }

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: 0
        spacing: Theme.spaceMedium

        // Header: Title & Rescan
        RowLayout {
            Layout.fillWidth: true

            MaterialIcon {
                text: "auto_awesome"
                size: 20
                color: (root.warningLevel === "critical")
                    ? "#E05353"
                    : ((root.warningLevel === "warning") ? "#F59E0B" : Colors.primary)
            }

            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true

                Text {
                    text: "AI Token Quotas"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.Bold
                    color: Colors.m3onSurface
                }

                Text {
                    text: (root.warningLevel === "critical")
                        ? "Critical Quota Alert (>= 95%)"
                        : ((root.warningLevel === "warning")
                            ? "Quota Warning (>= 80%)"
                            : "All Quotas Healthy")
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: (root.warningLevel === "critical")
                        ? "#E05353"
                        : ((root.warningLevel === "warning") ? "#F59E0B" : Colors.m3onSurfaceVariant)
                }
            }

            // Rescan / Refresh Button
            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: rescanHover.containsMouse ? Colors.pillHover : Colors.surfaceContainerHighest
                border.color: Theme.borderSubtle
                border.width: 1

                MaterialIcon {
                    id: refreshIcon
                    anchors.centerIn: parent
                    text: "refresh"
                    size: 16
                    color: Colors.m3onSurface

                    RotationAnimation on rotation {
                        running: root.isRefreshing
                        from: 0
                        to: 360
                        duration: 800
                        loops: Animation.Infinite
                    }
                }

                MouseArea {
                    id: rescanHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof AiTokenService !== "undefined") {
                            AiTokenService.refresh(true);
                        }
                    }
                }
            }
        }

        // Horizontal Segmented Provider Tabs (Responsive Chip Bar for 2, 3, 4, 5+ providers)
        Flickable {
            id: providerFlickable
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            visible: root.providersList.length > 1
            contentWidth: providerTabRow.implicitWidth
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: providerTabRow
                spacing: 6

                Repeater {
                    model: root.providersList
                    delegate: Rectangle {
                        id: tabChip
                        required property var modelData
                        required property int index

                        readonly property bool isSelected: root.activeProviderIndex === index
                        readonly property bool hasWarning: {
                            for (let i = 0; i < (modelData.windows || []).length; i++) {
                                if (modelData.windows[i].used_percent >= (typeof Config !== "undefined" ? Config.aiWarningThreshold : 80)) {
                                    return true;
                                }
                            }
                            return false;
                        }

                        height: 28
                        implicitWidth: tabRow.implicitWidth + 18
                        radius: 14
                        color: isSelected
                            ? (hasWarning ? Qt.alpha("#F59E0B", 0.25) : Colors.primary)
                            : (tabHover.containsMouse ? Colors.pillHover : Colors.surfaceContainer)
                        border.color: isSelected
                            ? (hasWarning ? "#F59E0B" : Colors.primary)
                            : (hasWarning ? "#F59E0B" : Theme.borderSubtle)
                        border.width: 1

                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 5

                            MaterialIcon {
                                text: root.getProviderIcon(modelData)
                                size: 13
                                color: isSelected
                                    ? (hasWarning ? "#F59E0B" : Colors.textOnPrimary)
                                    : (tabHover.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant)
                            }

                            Text {
                                text: root.getProviderShortName(modelData)
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: isSelected ? Font.Bold : Font.Normal
                                color: isSelected
                                    ? (hasWarning ? "#F59E0B" : Colors.textOnPrimary)
                                    : Colors.m3onSurface
                            }

                            Rectangle {
                                visible: hasWarning
                                width: 6
                                height: 6
                                radius: 3
                                color: "#F59E0B"
                            }
                        }

                        MouseArea {
                            id: tabHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.activeProviderIndex = index;
                                const pid = modelData.provider_id || modelData.provider;
                                if (typeof AiTokenService !== "undefined" && pid) {
                                    AiTokenService.lastActiveProviderId = pid;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Provider Details & Identity
        Rectangle {
            Layout.fillWidth: true
            radius: Theme.radiusSmall
            color: Colors.surfaceContainer
            border.color: Theme.borderSubtle
            border.width: 1
            visible: root.currentProvider !== null
            implicitHeight: providerInfoCol.implicitHeight + 16

            ColumnLayout {
                id: providerInfoCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialIcon {
                        text: root.getProviderIcon(root.currentProvider)
                        size: 16
                        color: Colors.primary
                    }

                    Text {
                        text: root.currentProvider ? root.currentProvider.display_name : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Colors.m3onSurface
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: root.currentProvider && !!root.currentProvider.plan_type
                        height: 18
                        implicitWidth: planText.implicitWidth + 10
                        radius: 9
                        color: Qt.alpha(Colors.primary, 0.15)
                        border.color: Qt.alpha(Colors.primary, 0.3)
                        border.width: 1

                        Text {
                            id: planText
                            anchors.centerIn: parent
                            text: root.currentProvider ? (root.currentProvider.plan_type || "") : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Colors.primary
                        }
                    }
                }

                // Active Account Email in CLI session
                RowLayout {
                    visible: root.currentProvider && (root.currentProvider.account_email || root.currentProvider.account_name)
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: "#22C55E"
                    }

                    Text {
                        text: "Active in CLI: " + ((root.currentProvider && (root.currentProvider.provider_id === "gemini" || root.currentProvider.provider === "gemini") && typeof AiTokenService !== "undefined" && AiTokenService.activeGeminiEmail) ? AiTokenService.activeGeminiEmail : (root.currentProvider ? (root.currentProvider.account_email || root.currentProvider.account_name || "") : ""))
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Colors.m3onSurfaceVariant
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                // Gemini Account Switcher (if multiple accounts exist)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    visible: root.currentProvider && (root.currentProvider.provider_id === "gemini" || root.currentProvider.provider === "gemini") && root.currentProvider.accounts && root.currentProvider.accounts.length > 1

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.borderSubtle
                        opacity: 0.5
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Configured Accounts:"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurfaceVariant
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "Click to inspect"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Colors.m3onSurfaceVariant
                            opacity: 0.8
                        }
                    }

                    Repeater {
                        model: (root.currentProvider && root.currentProvider.accounts) ? root.currentProvider.accounts : []
                        delegate: Rectangle {
                            id: accRow
                            required property var modelData

                            readonly property bool isAccountActive: (typeof AiTokenService !== "undefined" && AiTokenService.activeGeminiEmail)
                                ? (modelData.identity.toLowerCase() === AiTokenService.activeGeminiEmail.toLowerCase() || modelData.id === AiTokenService.activeGeminiEmail)
                                : modelData.is_active

                            readonly property bool isSelected: root.selectedAccount
                                ? (root.selectedAccount.identity === modelData.identity || root.selectedAccount.id === modelData.id)
                                : isAccountActive

                            Layout.fillWidth: true
                            height: 28
                            radius: 6
                            color: isSelected
                                ? Qt.alpha(Colors.primary, 0.12)
                                : (accHover.containsMouse ? Colors.pillHover : "transparent")
                            border.color: isSelected ? Colors.primary : (isAccountActive ? Qt.alpha(Colors.primary, 0.3) : "transparent")
                            border.width: 1

                            // Row background click area (inspect account without switching)
                            MouseArea {
                                id: accHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedAccountIdentity = modelData.identity || modelData.id;
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6
                                z: 1

                                MaterialIcon {
                                    text: accRow.isAccountActive ? "check_circle" : "account_circle"
                                    size: 14
                                    color: accRow.isAccountActive ? "#22C55E" : Colors.m3onSurfaceVariant
                                }

                                Text {
                                    text: modelData.identity || modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: accRow.isAccountActive ? Font.Bold : (isSelected ? Font.DemiBold : Font.Normal)
                                    color: isSelected ? Colors.m3onSurface : (accRow.isAccountActive ? Colors.primary : Colors.m3onSurfaceVariant)
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: modelData.five_hour_remaining_percent !== null && modelData.five_hour_remaining_percent !== undefined
                                    text: Math.round(modelData.five_hour_remaining_percent) + "%" + ((modelData.weekly_remaining_percent !== null && modelData.weekly_remaining_percent !== undefined) ? (" · " + Math.round(modelData.weekly_remaining_percent) + "%") : "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: (modelData.five_hour_remaining_percent < 20)
                                        ? "#EF4444"
                                        : ((modelData.five_hour_remaining_percent <= 50) ? "#F59E0B" : "#22C55E")
                                }

                                // Status Badge: Active pill if active
                                Rectangle {
                                    visible: accRow.isAccountActive
                                    height: 18
                                    implicitWidth: activeLbl.implicitWidth + 10
                                    radius: 4
                                    color: Qt.alpha(Colors.primary, 0.15)
                                    border.color: Qt.alpha(Colors.primary, 0.35)
                                    border.width: 1

                                    Text {
                                        id: activeLbl
                                        anchors.centerIn: parent
                                        text: "Active"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: Colors.primary
                                    }
                                }

                                // Switch button if inactive
                                Rectangle {
                                    id: switchBtn
                                    visible: !accRow.isAccountActive
                                    height: 18
                                    implicitWidth: switchLbl.implicitWidth + 10
                                    radius: 4
                                    color: switchMouse.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                                    border.color: switchMouse.containsMouse ? Colors.primary : Theme.borderSubtle
                                    border.width: 1
                                    z: 10

                                    Text {
                                        id: switchLbl
                                        anchors.centerIn: parent
                                        text: "Switch"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                        color: switchMouse.containsMouse ? Colors.primary : Colors.m3onSurface
                                    }

                                    MouseArea {
                                        id: switchMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: (mouse) => {
                                            mouse.accepted = true;
                                            root.selectedAccountIdentity = modelData.identity || modelData.id;
                                            if (typeof AiTokenService !== "undefined") {
                                                AiTokenService.switchGeminiAccount(modelData.identity || modelData.id);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Quota Limit Progress Windows
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.currentWindows && root.currentWindows.length > 0

            Repeater {
                model: root.currentWindows
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 52
                    radius: Theme.radiusSmall
                    color: Colors.surfaceContainer
                    border.color: (modelData.remaining_percent < 20)
                        ? "#EF4444"
                        : ((modelData.remaining_percent <= 50) ? "#F59E0B" : Theme.borderSubtle)
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: {
                                    switch (modelData.label) {
                                        case "5h": return "5-Hour Rolling Window";
                                        case "weekly": return "Weekly Limit";
                                        case "monthly": return "Monthly Limit";
                                        default: return (modelData.label.charAt(0).toUpperCase() + modelData.label.slice(1)) + " Limit";
                                    }
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Colors.m3onSurface
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: Math.round(modelData.remaining_percent) + "% remaining"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: (modelData.remaining_percent < 20)
                                    ? "#EF4444"
                                    : ((modelData.remaining_percent <= 50) ? "#F59E0B" : "#22C55E")
                            }
                        }

                        // Progress Bar Container
                        Rectangle {
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: Colors.surfaceContainerHighest

                            Rectangle {
                                width: Math.max(6, Math.min(parent.width, parent.width * (modelData.remaining_percent / 100.0)))
                                height: parent.height
                                radius: 3
                                color: (modelData.remaining_percent < 20)
                                    ? "#EF4444"
                                    : ((modelData.remaining_percent <= 50) ? "#F59E0B" : "#22C55E")

                                Behavior on width {
                                    NumberAnimation { duration: Theme.animDurationNormal }
                                }
                            }
                        }

                        // Reset time
                        Text {
                            visible: modelData.reset_at !== null && modelData.reset_at !== ""
                            text: (modelData.reset_at && modelData.reset_at.indexOf("Total") !== -1)
                                ? modelData.reset_at
                                : ("Resets at: " + (modelData.reset_at ? modelData.reset_at.replace("T", " ").replace("Z", "") : ""))
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Colors.m3onSurfaceVariant
                        }
                    }
                }
            }
        }

        // Info card when provider has no window limits (e.g. MiniMax pay-as-you-go)
        Rectangle {
            Layout.fillWidth: true
            height: 48
            radius: Theme.radiusSmall
            color: Colors.surfaceContainer
            border.color: Theme.borderSubtle
            border.width: 1
            visible: root.currentProvider !== null && (!root.currentWindows || root.currentWindows.length === 0)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                MaterialIcon {
                    text: "check_circle"
                    size: 16
                    color: "#22C55E"
                }

                Text {
                    text: "Pay-as-you-go · No quota window restrictions"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                    Layout.fillWidth: true
                }
            }
        }

        // Empty state if no providers configured
        Rectangle {
            Layout.fillWidth: true
            height: 90
            radius: Theme.radiusSmall
            color: Colors.surfaceContainer
            border.color: Theme.borderSubtle
            border.width: 1
            visible: !root.providersList || root.providersList.length === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "cloud_off"
                    size: 24
                    color: Colors.m3onSurfaceVariant
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No configured AI models detected"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Run 'agy auth login' or configure OpenCode Go"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Colors.m3onSurfaceVariant
                }
            }
        }
    }
}
