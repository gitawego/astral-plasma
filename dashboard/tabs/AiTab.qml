import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitWidth: 940
    implicitHeight: 410

    property bool testMode: false
    property var testProviders: null
    property string testWarningLevel: "normal"
    property int activeProviderIndex: 0
    property string selectedAccountIdentity: ""

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

    function formatTokenCount(n) {
        if (!n || n <= 0) return "0";
        if (n >= 1000000000) return (n / 1000000000).toFixed(1) + "B";
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M";
        if (n >= 1000) return (n / 1000).toFixed(1) + "k";
        return Math.round(n).toString();
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

    function getProviderDiscoverySource(p) {
        if (!p) return "Config";
        const pid = (p.provider_id || p.provider || "").toLowerCase();
        if (pid === "gemini") return "Antigravity Cockpit & Keyring";
        if (pid === "minimax-cn") return "Pi Agent (~/.pi/agent/auth.json)";
        if (pid === "opencode-go" || pid === "opencode") return "Pi / OpenCode (~/.config/opencode)";
        if (pid.indexOf("mimo") !== -1 || pid.indexOf("xiaomi") !== -1) return "OMP Agent (~/.omp/agent)";
        return "Local Agent Tool Scanner";
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
        spacing: Theme.spaceMedium

        // =====================================================================
        // 1. TOP OVERVIEW & ACTION BAR
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Title & Status
            RowLayout {
                spacing: 8
                MaterialIcon {
                    text: "auto_awesome"
                    size: 22
                    color: (root.warningLevel === "critical")
                        ? "#E05353"
                        : ((root.warningLevel === "warning") ? "#F59E0B" : Colors.primary)
                }

                ColumnLayout {
                    spacing: 1
                    Text {
                        text: "AI Quotas & Model Center"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontTitleSmall
                        font.weight: Font.Bold
                        color: Colors.m3onSurface
                        style: Text.Outline
                        styleColor: Colors.glassTextHalo
                    }
                    Text {
                        text: (root.providersList.length > 0)
                            ? (root.providersList.length + " Active Models Detected · " + (root.warningLevel === "normal" ? "All Limits Healthy" : (root.warningLevel === "warning" ? "Quota Warning (>= 80%)" : "Critical Quota Alert (>= 95%)")))
                            : "No AI Providers Detected"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: (root.warningLevel === "critical")
                            ? "#E05353"
                            : ((root.warningLevel === "warning") ? "#F59E0B" : Colors.m3onSurfaceVariant)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Active CLI Account Pill
            ActionPill {
                visible: !!(typeof AiTokenService !== "undefined" && AiTokenService.activeGeminiEmail)
                icon: "check_circle"
                text: "CLI: " + ((typeof AiTokenService !== "undefined" && AiTokenService.activeGeminiEmail) ? AiTokenService.activeGeminiEmail : "")
                variant: "active"
                pill: true
                interactive: false
                fontPixelSize: 10
                fixedHeight: 24
                paddingHorizontal: 10
            }

            // Lowest Constraint Pill
            ActionPill {
                visible: (typeof AiTokenService !== "undefined" && AiTokenService.lowestRemainingPercent !== undefined && root.providersList.length > 0)
                icon: "timelapse"
                text: "Lowest: " + Math.round((typeof AiTokenService !== "undefined" ? AiTokenService.lowestRemainingPercent : 100)) + "% Remaining"
                variant: ((typeof AiTokenService !== "undefined" && AiTokenService.lowestRemainingPercent < 20) ? "danger" : ((typeof AiTokenService !== "undefined" && AiTokenService.lowestRemainingPercent <= 50) ? "secondary" : "info"))
                pill: true
                interactive: false
                fontPixelSize: 10
                fixedHeight: 24
                paddingHorizontal: 10
            }

            // Token Cache Hit Rate Pill
            ActionPill {
                visible: (typeof AiTokenService !== "undefined" && AiTokenService.cacheHitRate > 0)
                icon: "bolt"
                text: "Cache Hit: " + Math.round((typeof AiTokenService !== "undefined" ? AiTokenService.cacheHitRate : 0)) + "% (" + root.formatTokenCount((typeof AiTokenService !== "undefined" && AiTokenService.totalCachedTokens) ? AiTokenService.totalCachedTokens : 0) + " saved)"
                variant: "active"
                pill: true
                interactive: false
                fontPixelSize: 10
                fixedHeight: 24
                paddingHorizontal: 10
            }

            // Force Refresh Button
            ActionPill {
                id: refreshActionBtn
                icon: "refresh"
                text: root.isRefreshing ? "Syncing..." : "Sync"
                variant: "secondary"
                fontPixelSize: 10
                fixedHeight: 24
                paddingHorizontal: 10
                onClicked: {
                    if (typeof AiTokenService !== "undefined") {
                        AiTokenService.refresh(true);
                    }
                }
            }

            // Manage in Settings Shortcut
            ActionPill {
                icon: "settings"
                text: "Manage"
                variant: "primary"
                fontPixelSize: 10
                fixedHeight: 24
                paddingHorizontal: 12
                onClicked: {
                    if (typeof Config !== "undefined") {
                        Config.openSettings("ai");
                    }
                }
            }
        }

        // =====================================================================
        // 2. RESPONSIVE PROVIDER CHIPS (Horizontal Segmented Tabs)
        // =====================================================================
        Row {
            Layout.fillWidth: true
            spacing: 8
            visible: root.providersList.length > 0

            Repeater {
                model: root.providersList
                delegate: Rectangle {
                    id: chipDelegate
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

                    height: 32
                    implicitWidth: chipRow.implicitWidth + 24
                    radius: Theme.radiusMedium
                    color: isSelected
                        ? (hasWarning ? Qt.alpha("#F59E0B", 0.28) : Qt.alpha(Colors.primary, 0.22))
                        : (chipHover.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.12) : Qt.rgba(1.0, 1.0, 1.0, 0.05))
                    border.color: isSelected
                        ? (hasWarning ? "#F59E0B" : Colors.primary)
                        : (chipHover.containsMouse ? Qt.alpha(Colors.glassBorderSpecular, 0.45) : Qt.rgba(1.0, 1.0, 1.0, 0.12))
                    border.width: isSelected ? 1.5 : 1

                    Behavior on color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }
                    Behavior on border.color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        ThemedIcon {
                            source: (typeof Config !== "undefined" && typeof Config.providerIconUrl === "function")
                                ? Config.providerIconUrl(modelData.provider_id || modelData.provider)
                                : ""
                            materialIcon: root.getProviderIcon(modelData)
                            size: 16
                            color: isSelected ? Colors.primary : Colors.m3onSurfaceVariant
                        }

                        Text {
                            text: root.getProviderShortName(modelData)
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: isSelected ? Font.Bold : Font.DemiBold
                            color: isSelected ? Colors.primary : Colors.m3onSurface
                        }

                        ActionPill {
                            visible: !!modelData.plan_type
                            text: modelData.plan_type || ""
                            variant: isSelected ? "active" : "secondary"
                            pill: true
                            interactive: false
                            fontPixelSize: 9
                            fixedHeight: 18
                            paddingHorizontal: 6
                        }

                        Rectangle {
                            visible: hasWarning
                            width: 7
                            height: 7
                            radius: 3.5
                            color: "#F59E0B"
                        }
                    }

                    MouseArea {
                        id: chipHover
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

        // =====================================================================
        // 3. MAIN DUAL-COLUMN BODY
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spaceMedium
            visible: root.currentProvider !== null

            // -----------------------------------------------------------------
            // LEFT COLUMN: Primary Provider Quota Details & Gauges (~58% width)
            // -----------------------------------------------------------------
            Card {
                Layout.fillWidth: true
                Layout.preferredWidth: 540
                Layout.minimumWidth: 460
                Layout.fillHeight: true
                radius: Theme.radiusGlassCard
                padding: 16

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 14

                    // Provider Header Bar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ThemedIcon {
                            source: (typeof Config !== "undefined" && typeof Config.providerIconUrl === "function" && root.currentProvider)
                                ? Config.providerIconUrl(root.currentProvider.provider_id || root.currentProvider.provider)
                                : ""
                            materialIcon: root.getProviderIcon(root.currentProvider)
                            size: 26
                            color: Colors.primary
                        }

                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true

                            Text {
                                text: root.currentProvider ? root.currentProvider.display_name : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontTitleSmall
                                font.weight: Font.Bold
                                color: Colors.m3onSurface
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                spacing: 6
                                Text {
                                    text: root.getProviderDiscoverySource(root.currentProvider)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Colors.m3onSurfaceVariant
                                }
                            }
                        }

                        ActionPill {
                            visible: root.currentProvider && !!root.currentProvider.plan_type
                            text: root.currentProvider ? (root.currentProvider.plan_type || "") : ""
                            variant: "active"
                            pill: true
                            interactive: false
                            fontPixelSize: 10
                            fixedHeight: 22
                            paddingHorizontal: 10
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.borderSubtle
                        opacity: 0.35
                    }

                    // Provider Cache Hit Rate Performance Row
                    RowLayout {
                        visible: root.currentProvider && root.currentProvider.cache_stats && root.currentProvider.cache_stats.total_prompt_tokens > 0
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            color: Qt.alpha("#10B981", 0.15)
                            border.color: Qt.alpha("#10B981", 0.35)
                            border.width: 1

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "bolt"
                                size: 14
                                color: "#10B981"
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Prompt Cache Efficiency"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: Colors.m3onSurface
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (root.currentProvider && root.currentProvider.cache_stats)
                                        ? (root.currentProvider.cache_stats.cache_hit_rate_percent.toFixed(1) + "% hit rate (" + root.formatTokenCount(root.currentProvider.cache_stats.cached_tokens) + " tokens saved)")
                                        : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: "#10B981"
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 4
                                radius: 2
                                color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : Qt.rgba(0.0, 0.0, 0.0, 0.06)

                                Rectangle {
                                    width: parent.width * Math.min(1.0, Math.max(0.0, (root.currentProvider && root.currentProvider.cache_stats) ? (root.currentProvider.cache_stats.cache_hit_rate_percent / 100.0) : 0.0))
                                    height: parent.height
                                    radius: 2
                                    color: "#10B981"

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: Theme.animExpressiveDefaultSpatial
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.curveExpressiveDefaultSpatial
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Quota Limit Windows (Rolling 5h, Weekly, Monthly)
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
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: Colors.m3onSurface
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: Math.round(modelData.remaining_percent) + "% remaining"
                                            + (modelData.used_percent !== undefined ? (" (" + Math.round(modelData.used_percent) + "% used)") : "")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: (modelData.remaining_percent < 20)
                                            ? "#EF4444"
                                            : ((modelData.remaining_percent <= 50) ? "#F59E0B" : Colors.primary)
                                    }
                                }

                                // Level Bar Gauge
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 8
                                    radius: 4
                                    color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                                        ? Qt.rgba(1.0, 1.0, 1.0, 0.08)
                                        : Qt.rgba(0.0, 0.0, 0.0, 0.06)

                                    Rectangle {
                                        width: Math.max(8, Math.min(parent.width, parent.width * (modelData.remaining_percent / 100.0)))
                                        height: parent.height
                                        radius: 4
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

                                // Reset Countdown
                                RowLayout {
                                    spacing: 4
                                    visible: modelData.reset_at !== null && modelData.reset_at !== ""

                                    MaterialIcon {
                                        text: "schedule"
                                        size: 12
                                        color: Colors.m3onSurfaceVariant
                                    }

                                    Text {
                                        text: root.formatResetTime(modelData.reset_at)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: Colors.m3onSurfaceVariant
                                    }
                                }
                            }
                        }
                    }

                    // Pay-as-you-go State
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.currentProvider !== null && (!root.currentWindows || root.currentWindows.length === 0)

                        MaterialIcon {
                            text: "verified"
                            size: 20
                            color: Colors.primary
                        }

                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Pay-as-you-go / On-Demand Access"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: Colors.m3onSurface
                            }
                            Text {
                                text: "No rolling quota window restrictions. Requests route directly to model endpoints."
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Colors.m3onSurfaceVariant
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // -----------------------------------------------------------------
            // RIGHT COLUMN: Account Management & Ecosystem Scanner (~42% width)
            // -----------------------------------------------------------------
            ColumnLayout {
                Layout.preferredWidth: 380
                Layout.minimumWidth: 340
                Layout.maximumWidth: 420
                Layout.fillWidth: false
                Layout.fillHeight: true
                spacing: Theme.spaceMedium

                // Card A: Multi-Account Management (if provider has accounts)
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusGlassCard
                    padding: 14
                    visible: root.currentProvider && root.currentProvider.accounts && root.currentProvider.accounts.length >= 1

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true

                            MaterialIcon {
                                text: "manage_accounts"
                                size: 16
                                color: Colors.primary
                            }

                            Text {
                                text: "Accounts (" + ((root.currentProvider && root.currentProvider.accounts) ? root.currentProvider.accounts.length : 0) + ")"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: Colors.m3onSurface
                            }

                            Item { Layout.fillWidth: true }

                            ActionPill {
                                text: "Settings"
                                icon: "settings"
                                variant: "secondary"
                                fontPixelSize: 9
                                fixedHeight: 20
                                paddingHorizontal: 8
                                onClicked: {
                                    if (typeof Config !== "undefined") {
                                        Config.openSettings("ai");
                                    }
                                }
                            }
                        }

                        // Accounts List
                        Repeater {
                            model: (root.currentProvider && root.currentProvider.accounts) ? root.currentProvider.accounts : []
                            delegate: Rectangle {
                                id: accItem
                                required property var modelData

                                readonly property bool isAccountActive: (typeof AiTokenService !== "undefined" && AiTokenService.activeGeminiEmail)
                                    ? (modelData.identity.toLowerCase() === AiTokenService.activeGeminiEmail.toLowerCase() || modelData.id === AiTokenService.activeGeminiEmail)
                                    : modelData.is_active

                                readonly property bool isSelected: root.selectedAccount
                                    ? (root.selectedAccount.identity === modelData.identity || root.selectedAccount.id === modelData.id)
                                    : isAccountActive

                                Layout.fillWidth: true
                                height: 32
                                radius: Theme.radiusSmall
                                color: isSelected
                                    ? Qt.alpha(Colors.primary, 0.14)
                                    : (accMouse.containsMouse ? Qt.rgba(1.0, 1.0, 1.0, 0.08) : Qt.rgba(1.0, 1.0, 1.0, 0.03))
                                border.color: isSelected
                                    ? Colors.primary
                                    : (isAccountActive ? Qt.alpha(Colors.primary, 0.4) : Qt.rgba(1.0, 1.0, 1.0, 0.10))
                                border.width: 1

                                MouseArea {
                                    id: accMouse
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

                                    MaterialIcon {
                                        text: accItem.isAccountActive ? "check_circle" : "account_circle"
                                        size: 15
                                        color: accItem.isAccountActive ? Colors.primary : Colors.m3onSurfaceVariant
                                    }

                                    Text {
                                        text: modelData.identity || modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        font.weight: accItem.isAccountActive ? Font.DemiBold : Font.Normal
                                        color: isSelected ? Colors.m3onSurface : (accItem.isAccountActive ? Colors.primary : Colors.m3onSurfaceVariant)
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: modelData.five_hour_remaining_percent !== null && modelData.five_hour_remaining_percent !== undefined
                                        text: Math.round(modelData.five_hour_remaining_percent) + "%"
                                            + ((modelData.weekly_remaining_percent !== null && modelData.weekly_remaining_percent !== undefined) ? (" · " + Math.round(modelData.weekly_remaining_percent) + "%") : "")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: (modelData.five_hour_remaining_percent < 20)
                                            ? "#EF4444"
                                            : ((modelData.five_hour_remaining_percent <= 50) ? "#F59E0B" : Colors.primary)
                                    }

                                    // Switch / Active pill
                                    Item {
                                        Layout.preferredWidth: 48
                                        Layout.preferredHeight: 20

                                        ActionPill {
                                            visible: accItem.isAccountActive
                                            anchors.fill: parent
                                            text: "Active"
                                            variant: "active"
                                            fontPixelSize: 9
                                            fontWeight: Font.Bold
                                            interactive: false
                                        }

                                        ActionPill {
                                            visible: !accItem.isAccountActive
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
                }

                // Card A2: Detailed Session Cache Analytics (when provider has cache_stats and no accounts)
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusGlassCard
                    padding: 14
                    visible: root.currentProvider && root.currentProvider.cache_stats && (!root.currentProvider.accounts || root.currentProvider.accounts.length === 0)

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true

                            MaterialIcon {
                                text: "bolt"
                                size: 16
                                color: "#10B981"
                            }

                            Text {
                                text: "Session Cache Breakdown"
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: Colors.m3onSurface
                            }

                            Item { Layout.fillWidth: true }

                            ActionPill {
                                text: (root.currentProvider && root.currentProvider.cache_stats)
                                    ? (root.currentProvider.cache_stats.cache_hit_rate_percent.toFixed(1) + "% Hit Rate")
                                    : "0% Hit Rate"
                                variant: "active"
                                fontPixelSize: 9
                                fixedHeight: 20
                                paddingHorizontal: 8
                                interactive: false
                            }
                        }

                        // 3-Metric Grid: Cached / Uncached / Output
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Cached Tokens
                            Rectangle {
                                Layout.fillWidth: true
                                height: 50
                                radius: 8
                                color: Qt.rgba(16/255, 185/255, 129/255, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(16/255, 185/255, 129/255, 0.3)

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text {
                                        text: (root.currentProvider && root.currentProvider.cache_stats)
                                            ? root.formatTokenCount(root.currentProvider.cache_stats.cached_tokens)
                                            : "0"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: "#10B981"
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: "Cached"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 9
                                        color: Colors.m3onSurfaceVariant
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }

                            // Uncached Input Tokens
                            Rectangle {
                                Layout.fillWidth: true
                                height: 50
                                radius: 8
                                color: Qt.rgba(245/255, 158/255, 11/255, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(245/255, 158/255, 11/255, 0.3)

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text {
                                        text: (root.currentProvider && root.currentProvider.cache_stats)
                                            ? root.formatTokenCount(root.currentProvider.cache_stats.uncached_input_tokens)
                                            : "0"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: "#F59E0B"
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: "Uncached"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 9
                                        color: Colors.m3onSurfaceVariant
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }

                            // Output Tokens
                            Rectangle {
                                Layout.fillWidth: true
                                height: 50
                                radius: 8
                                color: Qt.rgba(96/255, 165/255, 250/255, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(96/255, 165/255, 250/255, 0.3)

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text {
                                        text: (root.currentProvider && root.currentProvider.cache_stats)
                                            ? root.formatTokenCount(root.currentProvider.cache_stats.output_tokens)
                                            : "0"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: "Output"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 9
                                        color: Colors.m3onSurfaceVariant
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }
                        }

                        // Ratio Bar: Cached vs Uncached
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: Qt.rgba(245/255, 158/255, 11/255, 0.5)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: (root.currentProvider && root.currentProvider.cache_stats)
                                        ? Math.max(4, parent.width * Math.min(1.0, root.currentProvider.cache_stats.cache_hit_rate_percent / 100.0))
                                        : 0
                                    radius: 3
                                    color: "#10B981"
                                }
                            }

                            Text {
                                text: "Prompt Cache Ratio: " + ((root.currentProvider && root.currentProvider.cache_stats) ? root.currentProvider.cache_stats.cache_hit_rate_percent.toFixed(1) + "%" : "0%") + " hit efficiency"
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: 10
                                color: Colors.m3onSurfaceVariant
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Card B: Ecosystem & Scanners Status
                Card {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    radius: Theme.radiusGlassCard
                    padding: 14

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            MaterialIcon {
                                text: "radar"
                                size: 16
                                color: Colors.primary
                            }
                            Text {
                                text: "Agent Tool Scanners"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: Colors.m3onSurface
                            }
                        }

                        Text {
                            text: "Deterministic auto-discovery active across Pi Agent, Antigravity Cockpit, OpenCode, and OMP."
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Colors.m3onSurfaceVariant
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            ActionPill {
                                text: "pi: ~/.pi"
                                variant: "info"
                                fontPixelSize: 9
                                fixedHeight: 18
                                paddingHorizontal: 6
                                interactive: false
                            }

                            ActionPill {
                                text: "agy: cockpit"
                                variant: "info"
                                fontPixelSize: 9
                                fixedHeight: 18
                                paddingHorizontal: 6
                                interactive: false
                            }

                            ActionPill {
                                text: "opencode"
                                variant: "info"
                                fontPixelSize: 9
                                fixedHeight: 18
                                paddingHorizontal: 6
                                interactive: false
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // 4. EMPTY STATE (When no providers detected)
        // =====================================================================
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            radius: Theme.radiusGlassCard
            visible: !root.providersList || root.providersList.length === 0
            padding: 20

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "cloud_off"
                    size: 32
                    color: Colors.m3onSurfaceVariant
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No AI Providers or Coding Plans Detected"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: Colors.m3onSurface
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Authenticate in CLI agents ('agy auth login' / 'pi' / 'opencode') or configure credentials in Settings."
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                }

                ActionPill {
                    Layout.alignment: Qt.AlignHCenter
                    icon: "settings"
                    text: "Configure AI Providers"
                    variant: "primary"
                    fontPixelSize: 10
                    fixedHeight: 26
                    paddingHorizontal: 14
                    onClicked: {
                        if (typeof Config !== "undefined") {
                            Config.openSettings("ai");
                        }
                    }
                }
            }
        }
    }
}
