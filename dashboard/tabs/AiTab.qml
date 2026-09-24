import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../services"
import "../../config"

Item {
    id: root

    implicitWidth: 940
    implicitHeight: 310

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
        if (pid === "minimax-cn") return "Pi Agent Sessions";
        if (pid === "opencode-go" || pid === "opencode") return "OpenCode & Pi Sessions";
        if (pid.indexOf("mimo") !== -1 || pid.indexOf("xiaomi") !== -1) return "OMP Agent (~/.omp/agent)";
        return "Agent Tool Scanner";
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
        spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12

        // =====================================================================
        // 1. UNIFIED TOP NAVIGATION & TELEMETRY BAR (Hero Segmented Control)
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            implicitHeight: 36
            spacing: 10

            // Fluid Segmented Provider Capsule Bar
            Rectangle {
                implicitHeight: 34
                implicitWidth: providerChipsRow.implicitWidth + 8
                radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 17
                color: Qt.rgba(1, 1, 1, 0.05)
                border.width: 1
                border.color: (typeof Colors !== "undefined" && Colors.glassBorderSpecular) 
                    ? Qt.alpha(Colors.glassBorderSpecular, 0.25)
                    : Qt.rgba(1, 1, 1, 0.15)

                Row {
                    id: providerChipsRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    spacing: 4

                    Repeater {
                        model: root.providersList

                        Item {
                            id: chipDelegate
                            width: chipContent.implicitWidth + 20
                            height: 26

                            readonly property bool isSelected: index === root.activeProviderIndex
                            readonly property bool isHovered: chipMouse.containsMouse

                            Rectangle {
                                anchors.fill: parent
                                radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 13
                                color: isSelected 
                                    ? Qt.alpha(((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"), 0.22)
                                    : (isHovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent")
                                border.width: isSelected ? 1 : 0
                                border.color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"

                                Behavior on color { ColorAnimation { duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150 } }
                                Behavior on border.color { ColorAnimation { duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastEffects : 150 } }

                                RowLayout {
                                    id: chipContent
                                    anchors.centerIn: parent
                                    spacing: 6

                                    ThemedIcon {
                                        source: (typeof Config !== "undefined" && typeof Config.providerIconUrl === "function")
                                            ? Config.providerIconUrl(modelData.provider_id || modelData.provider)
                                            : ""
                                        materialIcon: root.getProviderIcon(modelData)
                                        size: 15
                                        color: isSelected 
                                            ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
                                            : ((typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#e3e3e3")
                                    }

                                    Text {
                                        text: root.getProviderShortName(modelData)
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 12
                                        font.weight: isSelected ? Font.Bold : Font.DemiBold
                                        color: isSelected 
                                            ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
                                            : ((typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#e3e3e3")
                                    }

                                    // Compact Plan Badge
                                    Rectangle {
                                        visible: !!modelData.plan_type
                                        implicitWidth: planText.implicitWidth + 8
                                        implicitHeight: 15
                                        radius: (typeof Theme !== "undefined" && Theme.radiusFull) ? Theme.radiusFull : 7
                                        color: isSelected 
                                            ? Qt.alpha(((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"), 0.25)
                                            : Qt.rgba(1, 1, 1, 0.08)

                                        Text {
                                            id: planText
                                            anchors.centerIn: parent
                                            text: modelData.plan_type ? modelData.plan_type.replace("Google AI ", "").replace(" Plan", "") : ""
                                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: isSelected 
                                                ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
                                                : ((typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0")
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: chipMouse
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

            Item { Layout.fillWidth: true }

            // Global Prompt Cache Hit Rate Pill
            ActionPill {
                visible: (typeof AiTokenService !== "undefined" && AiTokenService.cacheHitRate > 0)
                icon: "bolt"
                text: Math.round((typeof AiTokenService !== "undefined" ? AiTokenService.cacheHitRate : 0)) + "% Cache Hit (" + root.formatTokenCount((typeof AiTokenService !== "undefined" && AiTokenService.totalCachedTokens) ? AiTokenService.totalCachedTokens : 0) + " saved)"
                variant: "active"
                pill: true
                interactive: false
                fontPixelSize: 10
                fixedHeight: 26
                paddingHorizontal: 10
            }

            // Sync Refresh Button
            LiquidGlassButton {
                implicitWidth: 30
                implicitHeight: 30
                paddingHorizontal: 0
                paddingVertical: 0
                iconText: "refresh"
                iconSize: 15
                elevation: 2
                onClicked: {
                    if (typeof AiTokenService !== "undefined") {
                        AiTokenService.refresh(true);
                    }
                }
            }

            // AI Settings Button
            LiquidGlassButton {
                implicitWidth: 30
                implicitHeight: 30
                paddingHorizontal: 0
                paddingVertical: 0
                iconText: "settings"
                iconSize: 15
                elevation: 2
                onClicked: {
                    if (typeof Config !== "undefined") {
                        Config.dashboardVisible = false;
                        Config.openSettings("ai");
                    }
                }
            }
        }

        // =====================================================================
        // 2. MAIN BENTO GRID (Dual-Card Surface)
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: (typeof Theme !== "undefined" && Theme.spaceMedium) ? Theme.spaceMedium : 12
            visible: root.currentProvider !== null

            // -----------------------------------------------------------------
            // LEFT CARD: Primary Model Quota & Limits (~56% width)
            // -----------------------------------------------------------------
            Card {
                Layout.fillWidth: true
                Layout.preferredWidth: 520
                Layout.minimumWidth: 460
                Layout.fillHeight: true
                radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard) ? Theme.radiusGlassCard : 16
                padding: 16

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // Card Header: Provider Identity & Origin
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ThemedIcon {
                            source: (typeof Config !== "undefined" && typeof Config.providerIconUrl === "function" && root.currentProvider)
                                ? Config.providerIconUrl(root.currentProvider.provider_id || root.currentProvider.provider)
                                : ""
                            materialIcon: root.getProviderIcon(root.currentProvider)
                            size: 24
                            color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                        }

                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true

                            Text {
                                text: root.currentProvider ? root.currentProvider.display_name : ""
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                                style: Text.Outline
                                styleColor: Colors.glassTextHalo
                            }

                            Text {
                                text: root.getProviderDiscoverySource(root.currentProvider)
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: 10
                                color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                            }
                        }

                        // Plan Type Pill
                        ActionPill {
                            visible: !!(root.currentProvider && root.currentProvider.plan_type)
                            text: (root.currentProvider && root.currentProvider.plan_type) ? root.currentProvider.plan_type : ""
                            variant: "secondary"
                            fontPixelSize: 10
                            fixedHeight: 22
                            paddingHorizontal: 10
                            interactive: false
                        }
                    }

                    // Quota Limit Windows Repeater
                    Repeater {
                        model: root.currentWindows

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            // Top: Label & Remaining %
                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: {
                                        const l = (modelData.label || "").toLowerCase();
                                        if (l === "5h") return "5-Hour Rolling Limit";
                                        if (l === "weekly") return "Weekly Limit";
                                        if (l === "monthly") return "Monthly Limit";
                                        return modelData.label + " Limit";
                                    }
                                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: Math.round(modelData.remaining_percent) + "% Remaining"
                                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: (modelData.remaining_percent < 20)
                                        ? "#EF4444"
                                        : ((modelData.remaining_percent <= 50) ? "#F59E0B" : ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"))
                                }
                            }

                            // Middle: Sleek Rounded Level Bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 8
                                radius: 4
                                color: Qt.rgba(1, 1, 1, 0.08)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: Math.max(4, parent.width * Math.min(1.0, Math.max(0.0, modelData.remaining_percent / 100.0)))
                                    radius: 4
                                    color: (modelData.remaining_percent < 20)
                                        ? "#EF4444"
                                        : ((modelData.remaining_percent <= 50) ? "#F59E0B" : ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"))

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: (typeof Theme !== "undefined") ? Theme.animExpressiveFastSpatial : 350
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
                                        }
                                    }
                                }
                            }

                            // Bottom: Humanized Reset Time & Used %
                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: root.formatResetTime(modelData.reset_at)
                                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                    font.pixelSize: 10
                                    color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: Math.round(modelData.used_percent) + "% used"
                                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                    font.pixelSize: 10
                                    color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                                }
                            }
                        }
                    }

                    // Prompt Cache Efficiency Strip (when provider has cache_stats)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: root.currentProvider && root.currentProvider.cache_stats

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "Prompt Cache Efficiency"
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: (root.currentProvider && root.currentProvider.cache_stats)
                                    ? (root.currentProvider.cache_stats.cache_hit_rate_percent.toFixed(1) + "% Hit Rate")
                                    : ""
                                font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#10B981"
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: Qt.rgba(16/255, 185/255, 129/255, 0.15)

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
                            text: (root.currentProvider && root.currentProvider.cache_stats)
                                ? (root.formatTokenCount(root.currentProvider.cache_stats.cached_tokens) + " tokens saved from prompt cache")
                                : ""
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 10
                            color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // -----------------------------------------------------------------
            // RIGHT CARD: Contextual Intelligence Hub (~44% width)
            // -----------------------------------------------------------------
            Card {
                Layout.preferredWidth: 410
                Layout.minimumWidth: 360
                Layout.maximumWidth: 440
                Layout.fillWidth: false
                Layout.fillHeight: true
                radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard) ? Theme.radiusGlassCard : 16
                padding: 16

                // -------------------------------------------------------------
                // CASE A: Multi-Account Management (e.g. Gemini with 3 accounts)
                // -------------------------------------------------------------
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8
                    visible: root.currentProvider && root.currentProvider.accounts && root.currentProvider.accounts.length >= 1

                    // Header
                    RowLayout {
                        Layout.fillWidth: true

                        MaterialIcon {
                            text: "manage_accounts"
                            size: 18
                            color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                        }

                        Text {
                            text: "Connected Profiles"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                        }

                        ActionPill {
                            text: ((root.currentProvider && root.currentProvider.accounts) ? root.currentProvider.accounts.length : 0) + " Accounts"
                            variant: "info"
                            fontPixelSize: 9
                            fixedHeight: 20
                            paddingHorizontal: 8
                            interactive: false
                        }

                        Item { Layout.fillWidth: true }

                        ActionPill {
                            text: "Manage"
                            icon: "settings"
                            variant: "secondary"
                            fontPixelSize: 9
                            fixedHeight: 20
                            paddingHorizontal: 8
                            onClicked: {
                                if (typeof Config !== "undefined") {
                                    Config.dashboardVisible = false;
                                    Config.openSettings("ai");
                                }
                            }
                        }
                    }

                    // Accounts List
                    Repeater {
                        model: (root.currentProvider && root.currentProvider.accounts) ? root.currentProvider.accounts : []

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 36

                            readonly property bool isAccountActive: (typeof AiTokenService !== "undefined" && AiTokenService.activeGeminiEmail)
                                ? (modelData.identity.toLowerCase() === AiTokenService.activeGeminiEmail.toLowerCase() || modelData.id === AiTokenService.activeGeminiEmail)
                                : modelData.is_active
                            readonly property bool isHovered: accMouse.containsMouse

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: isAccountActive 
                                    ? Qt.alpha(((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"), 0.12)
                                    : (isHovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                                border.width: isAccountActive ? 1 : (isHovered ? 1 : 0)
                                border.color: isAccountActive 
                                    ? Qt.alpha(((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"), 0.35)
                                    : Qt.rgba(1, 1, 1, 0.12)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    // Profile Avatar Glyph
                                    Rectangle {
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: isAccountActive 
                                            ? Qt.alpha(((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"), 0.25)
                                            : Qt.rgba(1, 1, 1, 0.08)

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: isAccountActive ? "person" : "account_circle"
                                            size: 14
                                            color: isAccountActive 
                                                ? ((typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb")
                                                : ((typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0")
                                        }
                                    }

                                    // Identity Email
                                    Text {
                                        text: modelData.identity || modelData.id
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 11
                                        font.weight: isAccountActive ? Font.Bold : Font.Normal
                                        color: isAccountActive 
                                            ? ((typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF")
                                            : ((typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0")
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }

                                    // Quota Preview Badge
                                    Text {
                                        visible: modelData.five_hour_remaining_percent !== undefined
                                        text: Math.round(modelData.five_hour_remaining_percent || 0) + "% · " + Math.round(modelData.weekly_remaining_percent || 0) + "%"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                                    }

                                    // Status Badge / Action
                                    ActionPill {
                                        text: isAccountActive ? "Active" : "Switch"
                                        variant: isAccountActive ? "active" : (isHovered ? "primary" : "secondary")
                                        fontPixelSize: 9
                                        fixedHeight: 20
                                        paddingHorizontal: 8
                                        interactive: false
                                    }
                                }
                            }

                            MouseArea {
                                id: accMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedAccountIdentity = modelData.identity || modelData.id;
                                    if (typeof AiTokenService !== "undefined") {
                                        AiTokenService.switchGeminiAccount(modelData.identity || modelData.id);
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Discovery Telemetry Footer
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Discovered via"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 10
                            color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                        }

                        Text {
                            text: "● Antigravity Cockpit   ● Pi Agent   ● OpenCode"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }

                // -------------------------------------------------------------
                // CASE B: Prompt Cache Analytics (when no multiple accounts, e.g. MiniMax)
                // -------------------------------------------------------------
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
                    visible: root.currentProvider && (!root.currentProvider.accounts || root.currentProvider.accounts.length === 0)

                    // Header
                    RowLayout {
                        Layout.fillWidth: true

                        MaterialIcon {
                            text: "bolt"
                            size: 18
                            color: "#10B981"
                        }

                        Text {
                            text: "Session Cache Breakdown"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
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

                    // 3-Metric Hero Bento Grid
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Cached Tokens
                        Rectangle {
                            Layout.fillWidth: true
                            height: 60
                            radius: 10
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
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: "#10B981"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text {
                                    text: "Cached"
                                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                    font.pixelSize: 10
                                    color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        // Uncached Input Tokens
                        Rectangle {
                            Layout.fillWidth: true
                            height: 60
                            radius: 10
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
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: "#F59E0B"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text {
                                    text: "Uncached"
                                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                    font.pixelSize: 10
                                    color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }

                        // Output Tokens
                        Rectangle {
                            Layout.fillWidth: true
                            height: 60
                            radius: 10
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
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text {
                                    text: "Output"
                                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                                    font.pixelSize: 10
                                    color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }

                    // Dual-Tone Ratio Gauge
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle {
                            Layout.fillWidth: true
                            height: 8
                            radius: 4
                            color: Qt.rgba(245/255, 158/255, 11/255, 0.35)

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: (root.currentProvider && root.currentProvider.cache_stats)
                                    ? Math.max(4, parent.width * Math.min(1.0, root.currentProvider.cache_stats.cache_hit_rate_percent / 100.0))
                                    : 0
                                radius: 4
                                color: "#10B981"
                            }
                        }

                        Text {
                            text: "Prompt Cache Ratio: " + ((root.currentProvider && root.currentProvider.cache_stats) ? root.currentProvider.cache_stats.cache_hit_rate_percent.toFixed(1) + "%" : "0%") + " efficiency"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 10
                            color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Discovery Telemetry Footer
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Discovered via"
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 10
                            color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                        }

                        Text {
                            text: root.getProviderDiscoverySource(root.currentProvider)
                            font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // =====================================================================
        // 3. EMPTY STATE (When no providers detected)
        // =====================================================================
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            radius: (typeof Theme !== "undefined" && Theme.radiusGlassCard) ? Theme.radiusGlassCard : 16
            visible: !root.providersList || root.providersList.length === 0
            padding: 20

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "cloud_off"
                    size: 32
                    color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No AI Providers or Coding Plans Detected"
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: (typeof Colors !== "undefined" && Colors.m3onSurface) ? Colors.m3onSurface : "#FFFFFF"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Authenticate in CLI agents ('agy auth login' / 'pi' / 'opencode') or configure credentials in Settings."
                    font.family: (typeof Theme !== "undefined" && Theme.fontFamily) ? Theme.fontFamily : "sans-serif"
                    font.pixelSize: 11
                    color: (typeof Colors !== "undefined" && Colors.m3onSurfaceVariant) ? Colors.m3onSurfaceVariant : "#a0a0a0"
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
