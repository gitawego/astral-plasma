import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitWidth: 320
    implicitHeight: (mainLayout.implicitHeight || 0) + ((typeof Theme !== "undefined" && Theme.padLarge !== undefined) ? Theme.padLarge : 16) * 2

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
        if (pid === "zcode" || pid.indexOf("zcode") !== -1) return "ZCode";
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
        if (pid.indexOf("zcode") !== -1) return "code";
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

    Connections {
        target: (typeof AiTokenService !== "undefined") ? AiTokenService : null
        function onLastActiveProviderIdChanged() {
            root.syncActiveTab();
        }
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

    function formatResetTime(resetAtStr) {
        if (!resetAtStr || resetAtStr === "") return "";
        if (resetAtStr.indexOf("Total") !== -1 || resetAtStr.indexOf("in ") === 0) {
            return resetAtStr;
        }
        try {
            const targetMs = Date.parse(resetAtStr);
            if (isNaN(targetMs)) {
                return "Resets at " + resetAtStr.replace("T", " ").replace("Z", "").split(".")[0];
            }
            const diffSec = Math.floor((targetMs - Date.now()) / 1000);
            if (diffSec <= 0) return "Resetting soon";
            if (diffSec < 60) return "Resets in " + diffSec + "s";
            if (diffSec < 3600) return "Resets in " + Math.floor(diffSec / 60) + "m";
            if (diffSec < 86400) {
                const h = Math.floor(diffSec / 3600);
                const m = Math.floor((diffSec % 3600) / 60);
                return "Resets in " + h + "h " + (m < 10 ? "0" : "") + m + "m";
            }
            const d = Math.floor(diffSec / 86400);
            const remH = Math.floor((diffSec % 86400) / 3600);
            const targetDate = new Date(targetMs);
            const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
            const monthStr = months[targetDate.getMonth()];
            const dayStr = targetDate.getDate();
            const timeStr = (targetDate.getHours() < 10 ? "0" : "") + targetDate.getHours() + ":" + (targetDate.getMinutes() < 10 ? "0" : "") + targetDate.getMinutes();
            return "Resets in " + d + "d " + remH + "h (" + monthStr + " " + dayStr + ", " + timeStr + ")";
        } catch (e) {
            return "Resets at " + resetAtStr.replace("T", " ").replace("Z", "").split(".")[0];
        }
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
                color: rescanHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.16) : Qt.rgba(1.0, 1.0, 1.0, 0.06)
                border.color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular)
                    ? Qt.alpha(Colors.glassBorderSpecular, 0.25)
                    : Qt.rgba(1.0, 1.0, 1.0, 0.12)
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
                            ? (hasWarning ? Qt.alpha("#F59E0B", 0.30) : Colors.primary)
                            : (tabHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.14) : Qt.rgba(1.0, 1.0, 1.0, 0.06))
                        border.color: isSelected
                            ? (hasWarning ? "#F59E0B" : Colors.primary)
                            : (tabHover.containsMouse ? Qt.alpha(Colors.glassBorderSpecular, 0.40) : Qt.rgba(1.0, 1.0, 1.0, 0.12))
                        border.width: 1

                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 5

                            ThemedIcon {
                                source: (typeof Config !== "undefined" && typeof Config.providerIconUrl === "function") ? Config.providerIconUrl(modelData.provider_id || modelData.provider) : ""
                                materialIcon: root.getProviderIcon(modelData)
                                size: 14
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

        // =====================================================================
        // Unified Provider Card: Combines Brand, Plan, Account, and Quotas
        // =====================================================================
        Rectangle {
            id: providerCard
            Layout.fillWidth: true
            radius: Theme.radiusMedium
            color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                ? Qt.rgba(1.0, 1.0, 1.0, 0.05)
                : Qt.rgba(0.0, 0.0, 0.0, 0.04)
            border.color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular)
                ? Qt.alpha(Colors.glassBorderSpecular, Colors.isDarkMode ? 0.25 : 0.40)
                : Qt.rgba(1.0, 1.0, 1.0, 0.15)
            border.width: 1
            visible: root.currentProvider !== null
            implicitHeight: providerCardCol.implicitHeight + 24

            ColumnLayout {
                id: providerCardCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                // 1. Provider Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ThemedIcon {
                        source: (typeof Config !== "undefined" && typeof Config.providerIconUrl === "function" && root.currentProvider) ? Config.providerIconUrl(root.currentProvider.provider_id || root.currentProvider.provider) : ""
                        materialIcon: root.getProviderIcon(root.currentProvider)
                        size: 20
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

                    ActionPill {
                        visible: root.currentProvider && !!root.currentProvider.plan_type
                        text: root.currentProvider ? (root.currentProvider.plan_type || "") : ""
                        variant: "active"
                        pill: true
                        interactive: false
                        fontPixelSize: 10
                        fixedHeight: 18
                        paddingHorizontal: 8
                    }
                }

                // 2. Active Account Email in CLI session
                RowLayout {
                    visible: root.currentProvider && (root.currentProvider.account_email || root.currentProvider.account_name)
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: "#10B981"
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

                // 3. Gemini Account Switcher & Manager
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.currentProvider && (root.currentProvider.provider_id === "gemini" || root.currentProvider.provider === "gemini") && root.currentProvider.accounts && root.currentProvider.accounts.length >= 1

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.borderSubtle
                        opacity: 0.35
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Configured Accounts:"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Colors.m3onSurfaceVariant
                        }

                        Item { Layout.fillWidth: true }

                        // Manage in Settings button
                        ActionPill {
                            icon: "settings"
                            text: "Manage"
                            variant: "secondary"
                            fontPixelSize: 9
                            fixedHeight: 20
                            paddingHorizontal: 8
                            spacing: 3
                            onClicked: {
                                if (typeof Config !== "undefined") {
                                    Config.activeSettingsPage = "ai";
                                    Config.settingsVisible = true;
                                }
                            }
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
                                : (accHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : "transparent")
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
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 5
                                z: 1

                                MaterialIcon {
                                    text: accRow.isAccountActive ? "check_circle" : "account_circle"
                                    size: 14
                                    color: accRow.isAccountActive ? Colors.primary : Colors.m3onSurfaceVariant
                                    Layout.preferredWidth: 14
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: modelData.identity || modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: accRow.isAccountActive ? Font.DemiBold : Font.Normal
                                    color: isSelected ? Colors.m3onSurface : (accRow.isAccountActive ? Colors.primary : Colors.m3onSurfaceVariant)
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: modelData.five_hour_remaining_percent !== null && modelData.five_hour_remaining_percent !== undefined
                                    text: Math.round(modelData.five_hour_remaining_percent) + "%"
                                        + ((modelData.weekly_remaining_percent !== null && modelData.weekly_remaining_percent !== undefined) ? (" · " + Math.round(modelData.weekly_remaining_percent) + "%") : "")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: 82
                                    Layout.alignment: Qt.AlignVCenter
                                    color: (modelData.five_hour_remaining_percent < 20)
                                        ? "#EF4444"
                                        : ((modelData.five_hour_remaining_percent <= 50) ? "#F59E0B" : Colors.primary)
                                }

                                // Status Badge / Switch Button: Fixed width 46px container for strict tabular alignment
                                Item {
                                    Layout.preferredWidth: 46
                                    Layout.preferredHeight: 18
                                    Layout.alignment: Qt.AlignVCenter

                                    // Active pill if active
                                    ActionPill {
                                        visible: accRow.isAccountActive
                                        anchors.fill: parent
                                        text: "Active"
                                        variant: "active"
                                        fontPixelSize: 9
                                        fontWeight: Font.Bold
                                        interactive: false
                                    }

                                    // Switch button if inactive
                                    ActionPill {
                                        id: switchBtn
                                        visible: !accRow.isAccountActive
                                        anchors.fill: parent
                                        text: "Switch"
                                        variant: "secondary"
                                        fontPixelSize: 9
                                        onClicked: {
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

                // 4. Subtle Hairline Divider before Quotas
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                    opacity: 0.35
                    visible: root.currentWindows && root.currentWindows.length > 0
                }

                // 5. Quota Limit Progress Rows (Clean, Organic, No Black Boxes!)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.currentWindows && root.currentWindows.length > 0

                    Repeater {
                        model: root.currentWindows
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: {
                                        switch (modelData.label) {
                                            case "5h": return "5-Hour Rolling Limit";
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
                                        : ((modelData.remaining_percent <= 50) ? "#F59E0B" : Colors.primary)
                                }
                            }

                            // Sleek Level Bar Container
                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                                    ? Qt.rgba(1.0, 1.0, 1.0, 0.08)
                                    : Qt.rgba(0.0, 0.0, 0.0, 0.06)

                                Rectangle {
                                    width: Math.max(6, Math.min(parent.width, parent.width * (modelData.remaining_percent / 100.0)))
                                    height: parent.height
                                    radius: 3
                                    color: (modelData.remaining_percent < 20)
                                        ? "#EF4444"
                                        : ((modelData.remaining_percent <= 50) ? "#F59E0B" : Colors.primary)

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: Theme.animExpressiveDefaultSpatial
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                                        }
                                    }
                                }
                            }

                            // Humanized Reset Countdown
                            Text {
                                visible: modelData.reset_at !== null && modelData.reset_at !== ""
                                text: root.formatResetTime(modelData.reset_at)
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Colors.m3onSurfaceVariant
                            }
                        }
                    }
                }

                // 6. Pay-as-you-go State (When provider has no quota limits)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.currentProvider !== null && (!root.currentWindows || root.currentWindows.length === 0)

                    MaterialIcon {
                        text: "verified"
                        size: 16
                        color: Colors.primary
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
        }

        // Empty state if no providers configured
        Rectangle {
            Layout.fillWidth: true
            height: 90
            radius: Theme.radiusMedium
            color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                ? Qt.rgba(1.0, 1.0, 1.0, 0.05)
                : Qt.rgba(0.0, 0.0, 0.0, 0.04)
            border.color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular)
                ? Qt.alpha(Colors.glassBorderSpecular, 0.25)
                : Qt.rgba(1.0, 1.0, 1.0, 0.15)
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
