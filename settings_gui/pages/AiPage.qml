import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../components/QuotaMath.js" as QuotaMath
import "../controls"
import "../../services"
import "../../config"

/**
 * Page root is a plain Item, not the ColumnLayout.
 *
 * Dropdown lists are absolutely positioned overlays. Inside a ColumnLayout they
 * are laid out as siblings, so an open list paints straight over the sections
 * *below* it -- the Language picker and the auto-finalize switch were being
 * covered by the model list. An Item wrapper lets the layout and a
 * full-surface overlay layer coexist, with the overlay always on top.
 */
ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 16

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

    // --- Pi harness update card (injected in offscreen tests) ---
    // The Copilot runs on the user's own `pi` installation. Updating it is one
    // button instead of "leave the shell and remember a command", and the result
    // reports the real version movement (or pi's own output for its packages).
    property string testHarnessVersion: "1.0.0"
    property bool testHarnessInstalled: true
    property string testHarnessUpdateState: "idle"
    property string testHarnessUpdateMessage: ""
    property string testHarnessUpdateDetail: ""
    property int testUpdatePiRequests: 0
    property int testUpdatePackagesRequests: 0
    property int testRefreshCatalogsRequests: 0
    property int testCopyCommandRequests: 0

    readonly property string harnessVersion: testMode
        ? testHarnessVersion
        : ((typeof AssistantService !== "undefined" && AssistantService) ? AssistantService.harnessVersion : "")
    readonly property bool harnessInstalled: testMode
        ? testHarnessInstalled
        : ((typeof AssistantService !== "undefined" && AssistantService) ? AssistantService.harnessInstalled : false)
    readonly property string harnessUpdateState: testMode
        ? testHarnessUpdateState
        : ((typeof AssistantService !== "undefined" && AssistantService) ? AssistantService.harnessUpdateState : "idle")
    readonly property string harnessUpdateMessage: testMode
        ? testHarnessUpdateMessage
        : ((typeof AssistantService !== "undefined" && AssistantService) ? AssistantService.harnessUpdateMessage : "")
    readonly property string harnessUpdateDetail: testMode
        ? testHarnessUpdateDetail
        : ((typeof AssistantService !== "undefined" && AssistantService) ? AssistantService.harnessUpdateDetail : "")
    readonly property bool harnessUpdating: root.harnessUpdateState === "running"
    readonly property string harnessStatusText: root.harnessInstalled
        ? (root.harnessVersion !== "" ? ("pi " + root.harnessVersion + " installed") : "pi installed")
        : "pi is not installed"
    readonly property string harnessInstallCommand: "npm install -g @earendil-works/pi-coding-agent"

    /// One write path per button, so the page is testable without a daemon.
    function updatePi() {
        if (testMode) { testUpdatePiRequests += 1; return; }
        if (typeof AssistantService !== "undefined" && AssistantService) AssistantService.updatePi();
    }

    function updatePiPackages() {
        if (testMode) { testUpdatePackagesRequests += 1; return; }
        if (typeof AssistantService !== "undefined" && AssistantService) AssistantService.updatePiPackages();
    }

    function refreshPiModelCatalogs() {
        if (testMode) { testRefreshCatalogsRequests += 1; return; }
        if (typeof AssistantService !== "undefined" && AssistantService) AssistantService.refreshPiModelCatalogs();
    }

    function copyHarnessInstallCommand() {
        if (testMode) { testCopyCommandRequests += 1; return; }
        if (typeof AssistantService !== "undefined" && AssistantService) {
            AssistantService.copyToClipboard(root.harnessInstallCommand);
        }
    }

    /// Test / introspection surface for the card.
    property alias harnessStatusItem: harnessStatus
    property alias harnessHintItem: harnessHint
    property alias harnessResultItem: harnessResult
    property alias harnessDetailItem: harnessDetail
    property alias updatePiButtonItem: updatePiButton
    property alias updatePackagesButtonItem: updatePackagesButton
    property alias refreshCatalogsButtonItem: refreshCatalogsButton
    property alias harnessInstallButtonItem: harnessInstallButton

    // --- Desktop Agent Skills (astral-desktop-tools) ---
    property bool testSkillInstalled: false
    property var testSkillLocations: []
    property int testInstallSkillRequests: 0
    property int testUninstallSkillRequests: 0

    readonly property bool skillInstalled: testMode
        ? testSkillInstalled
        : ((typeof AiTokenService !== "undefined" && AiTokenService) ? AiTokenService.skillInstalled : false)
    readonly property var skillLocations: testMode
        ? testSkillLocations
        : ((typeof AiTokenService !== "undefined" && AiTokenService) ? AiTokenService.skillLocations : [])
    readonly property bool skillOperating: testMode
        ? false
        : ((typeof AiTokenService !== "undefined" && AiTokenService) ? AiTokenService.skillOperating : false)
    readonly property string skillStatusText: root.skillInstalled
        ? "astral-desktop-tools installed"
        : "astral-desktop-tools is not installed"

    function installSkill() {
        if (testMode) { testInstallSkillRequests += 1; return; }
        if (typeof AiTokenService !== "undefined" && AiTokenService) AiTokenService.installSkill("astral-desktop-tools");
    }

    function uninstallSkill() {
        if (testMode) { testUninstallSkillRequests += 1; return; }
        if (typeof AiTokenService !== "undefined" && AiTokenService) AiTokenService.uninstallSkill("astral-desktop-tools");
    }

    property alias skillsSetupGroupItem: skillsSetupGroup
    property alias skillStatusItem: skillStatus
    property alias skillHintItem: skillHint
    property alias installSkillButtonItem: installSkillButton
    property alias reinstallSkillButtonItem: reinstallSkillButton
    property alias uninstallSkillButtonItem: uninstallSkillButton

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


    readonly property alias voicePanelItem: skillsSetupGroup
    readonly property alias voiceModelRemoveItem: skillsSetupGroup

    /// Section anchors for deep links: "Settings > AI" sections land on their respective cards.
    function sectionY(name) {
        if (name === "skills" || name === "skill" || name === "setup" || name === "voice") {
            skillsSetupGroup.userOpen = true;
            return skillsSetupGroup.mapToItem(root, 0, 0).y;
        }
        if (name === "quotas" || name === "providers" || name === "quota") return quotasHeader.mapToItem(root, 0, 0).y;
        if (name === "copilot" || name === "harness" || name === "model") return copilotHeader.mapToItem(root, 0, 0).y;
        return undefined;
    }

    // --- Zone rail: what this page answers, with each zone's live state -----
    // Built from the same rules the runways render (`components/QuotaMath.js`), so
    // a summary and a bar cannot disagree.
    readonly property var quotaSummary: QuotaMath.summarize(
        root.providersList || [], root.warningThreshold, root.criticalThreshold, Date.now())
    /// The model the Copilot will use: the service's live selection when it is
    /// available, else the configured default. Never "undefined" - the rail is a
    /// status line, and a status line that prints a JavaScript artefact is a bug.
    readonly property string activeModelName: {
        const fromService = (typeof AssistantService !== "undefined" && AssistantService
            && AssistantService.selectedModelId) ? String(AssistantService.selectedModelId) : "";
        if (fromService !== "") return fromService;
        const configured = (typeof Config !== "undefined" && Config.assistantDefaultModel)
            ? String(Config.assistantDefaultModel) : "";
        return configured;
    }
    readonly property string copilotSummaryText: (root.harnessInstalled
            ? ("pi " + (root.harnessVersion !== "" ? root.harnessVersion : "installed"))
            : "pi missing")
        + " · " + (root.activeModelName !== "" ? root.activeModelName : "no model chosen")

    /// The quota posture in words (the rail's line and the zone eyebrow share it).
    readonly property string quotaSummaryStateWord: {
        switch (root.quotaSummary.state) {
            case "critical": return "needs attention";
            case "watch": return "getting tight";
            case "exhausted": return "windows spent";
            case "unknown": return "not reported yet";
            default: return "healthy";
        }
    }
    /// A rail pill was pressed: ask the host (the settings hub) to bring that
    /// zone into view.
    signal zoneRequested(string zoneId)

    /// Ask the settings hub to bring a zone into view.
    function jumpToZone(zone) {
        root.zoneRequested(zone);
    }

    // The page's identity and its state rail are rendered by the settings hub as a
    // *sticky* header (`stickyHeader`), so they stay visible while the zones scroll
    // - and the hub tells this page which zone is current (`currentSection`), so
    // the rail can highlight it.
    property string currentSection: ""

    function isZoneCurrent(zoneId) {
        return root.currentSection === zoneId;
    }
    readonly property var zones: [
        { id: "quotas", label: "Quotas" },
        { id: "copilot", label: "Copilot" },
        { id: "setup", label: "Skills" }
    ]

    property Component stickyHeader: Component {
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSmall

            Text {
                text: "AI & Agents"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontTitleLarge
                font.weight: Font.Bold
                color: Colors.m3onSurface
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Token quotas, coding harnesses, provider accounts, and agent skills"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodySmall
                color: Colors.m3onSurfaceVariant
            }

            // The rail: each zone's live state, and which one you are in.
            Flow {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                Repeater {
                    id: zoneRail
                    model: [
                        { id: "quotas", icon: "data_usage", label: root.quotaSummary.text },
                        { id: "copilot", icon: "psychology", label: root.copilotSummaryText },
                        { id: "setup", icon: "extension", label: root.skillInstalled ? "skills active" : "agent skills" }
                    ]

                    delegate: PillButton {
                        required property var modelData
                        iconText: modelData.icon
                        label: modelData.label
                        active: root.isZoneCurrent(modelData.id)
                        onClicked: root.jumpToZone(modelData.id)
                    }
                }
            }
        }
    }

    // --- QUOTAS ------------------------------------------------------------
    SectionHeader {
        id: quotasHeader
        Layout.topMargin: Theme.spaceSmall
        eyebrow: root.quotaSummary.count + " configured · " + root.quotaSummaryStateWord
        title: "Quotas"
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

        GridLayout {
            Layout.fillWidth: true
            // Two cards side by side when there is room, one when the settings
            // window is narrow: a quota row squeezed to 300px is unreadable.
            columns: width > 760 ? 2 : 1
            columnSpacing: Theme.spaceSmall

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                ThresholdRange {
                    id: thresholdRange
                    Layout.fillWidth: true
                    warning: root.warningThreshold
                    critical: root.criticalThreshold
                    onRangeModified: (warning, critical) => root.setThresholds(warning, critical)
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "The dock pill turns amber at " + Math.round(root.warningThreshold)
                        + "% used and rose at " + Math.round(root.criticalThreshold)
                        + "%. Drag a handle, or focus the control and press ←/→ (Shift for 5% steps)."
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                }
            }
            rowSpacing: Theme.spaceSmall
            Repeater {
                model: root.providersList
                delegate: ProviderQuotaCard {
                    required property var modelData
                    Layout.fillWidth: true
                    provider: modelData
                    warningThreshold: root.warningThreshold
                    criticalThreshold: root.criticalThreshold

                    // Accounts and sign-in belong to their provider, and stay collapsed
                    // until that provider needs the user (unavailable, or a new sign-in).
                    SetupGroup {
                        Layout.fillWidth: true
                        flat: true
                        title: "Accounts & sign-in"
                        summary: (modelData.accounts ? modelData.accounts.length : 0)
                            + ((modelData.accounts && modelData.accounts.length === 1) ? " account" : " accounts")
                            + (modelData.account_email ? " · active " + modelData.account_email : "")
                        state: modelData.is_available === false ? "attention" : "ok"
                        needsAttention: modelData.is_available === false

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

                    }
                }
            }
        }

    }


    // --- COPILOT -----------------------------------------------------------
    SectionHeader {
        id: copilotHeader
        Layout.topMargin: Theme.spaceSmall
        eyebrow: root.copilotSummaryText
        title: "Copilot"
    }

    // AI Copilot & Chat Configuration Card
    Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        implicitHeight: copilotCol.implicitHeight + Theme.padLarge * 2
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            id: copilotCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.padLarge
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialIcon {
                    text: "smart_toy"
                    size: 20
                    color: Colors.primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "AI Copilot & Assistant Configuration"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: "Default engine harness, provider, and model for system diagnostics and chat"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Colors.m3onSurfaceVariant
                    }
                }
            }

            // Harness Selection
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "Engine Harness"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                RowLayout {
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "pi", label: "Pi Agent (Default)", desc: "Autonomous agent harness with skills" },
                            { id: "hermes", label: "Hermes Agent", desc: "Local / research agent harness" }
                        ]

                        delegate: Rectangle {
                            implicitHeight: 36
                            implicitWidth: harnessTxt.implicitWidth + 24
                            radius: 8
                            readonly property bool isSelected: (typeof AssistantService !== "undefined") ? (AssistantService.selectedHarness === modelData.id) : (modelData.id === "pi")
                            color: isSelected ? Colors.m3primaryContainer : (harnessHover.containsMouse ? Colors.glassCardHover : Colors.glassCard)
                            border.width: 1
                            border.color: isSelected ? Colors.primary : Colors.glassBorderSpecular

                            Text {
                                id: harnessTxt
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: isSelected ? Font.Bold : Font.Normal
                                color: isSelected ? Colors.m3onPrimaryContainer : Colors.m3onSurface
                            }

                            MouseArea {
                                id: harnessHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof AssistantService !== "undefined") {
                                        AssistantService.selectedHarness = modelData.id;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Provider Selection
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "AI Provider"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: (typeof AssistantService !== "undefined" && AssistantService.availableProviders) ? AssistantService.availableProviders : []

                        delegate: Rectangle {
                            implicitHeight: 32
                            implicitWidth: provTxt.implicitWidth + 20
                            radius: 8
                            readonly property bool isSelected: (typeof AssistantService !== "undefined") ? (AssistantService.selectedProviderId === modelData.id) : (modelData.id === "opencode-go")
                            color: isSelected ? Colors.m3primaryContainer : (provHover.containsMouse ? Colors.glassCardHover : Colors.glassCard)
                            border.width: 1
                            border.color: isSelected ? Colors.primary : Colors.glassBorderSpecular

                            Text {
                                id: provTxt
                                anchors.centerIn: parent
                                text: modelData.name || modelData.id
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: isSelected ? Font.Bold : Font.Normal
                                color: isSelected ? Colors.m3onPrimaryContainer : Colors.m3onSurface
                            }

                            MouseArea {
                                id: provHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof AssistantService !== "undefined") {
                                        AssistantService.selectProvider(modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Model Selection
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                readonly property string currentProv: (typeof AssistantService !== "undefined") ? AssistantService.selectedProviderId : "opencode-go"
                readonly property var modelsList: (typeof AssistantService !== "undefined") ? AssistantService.getModelsForProvider(currentProv) : []

                Text {
                    text: "Active Model"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: parent.modelsList

                        delegate: Rectangle {
                            implicitHeight: 28
                            implicitWidth: modelTxt.implicitWidth + 16
                            radius: 6
                            readonly property bool isSelected: (typeof AssistantService !== "undefined") ? (AssistantService.selectedModelId === modelData) : false
                            color: isSelected ? Colors.primary : (modelHover.containsMouse ? Colors.glassCardHover : Colors.glassCard)
                            border.width: 1
                            border.color: isSelected ? Colors.primary : Colors.glassBorderSpecular

                            Text {
                                id: modelTxt
                                anchors.centerIn: parent
                                text: modelData
                                font.family: Theme.fontMonospace
                                font.pixelSize: 10
                                font.weight: isSelected ? Font.Bold : Font.Normal
                                color: isSelected ? Colors.textOnPrimary : Colors.m3onSurface
                            }

                            MouseArea {
                                id: modelHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (typeof AssistantService !== "undefined") {
                                        AssistantService.selectModel(modelData);
                                    }
                                }
                            }
                        }
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
                text: "Dock indicator & polling"

                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Colors.m3onSurface
            }

            // Dock Pill Display Mode

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderSubtle
                opacity: 0.4
            }

            // Warning thresholds: ONE control, because the relationship between
            // amber and rose is the information - two separate sliders can be
            // crossed without anything saying so.

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

    // --- DSH WEB APP -------------------------------------------------------
    SettingToggle {
        Layout.fillWidth: true
        Layout.topMargin: Theme.spaceSmall
        title: "DSH Web app icon"
        description: "Install a DeepSeek icon and desktop entry so the DSH web app window is not branded as Chrome, Edge or Firefox. Turning this off removes them."
        checked: root.testMode ? false : (typeof Config !== "undefined" ? Config.dshWebInstallDesktopIcon : true)
        onToggled: val => {
            if (root.testMode) return;
            if (typeof Config !== "undefined" && Config.setDshWebInstallDesktopIcon) {
                Config.setDshWebInstallDesktopIcon(val);
            }
        }
    }

    // Open the DSH web app straight from Settings.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 44
        radius: Theme.radiusMedium
        color: dshOpenHover.hovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.padLarge
            anchors.rightMargin: Theme.padLarge
            spacing: Theme.spaceSmall

            MaterialIcon {
                text: "language"
                size: 18
                color: Colors.primary
            }

            Text {
                Layout.fillWidth: true
                text: "Open DSH Web"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodyMedium
                font.weight: Font.DemiBold
                color: Colors.m3onSurface
            }

            Text {
                text: "browser / embedded"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurfaceVariant
            }
        }

        HoverHandler { id: dshOpenHover }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.testMode) return;
                if (typeof DshWebService !== "undefined") DshWebService.open();
            }
        }
    }


    // --- SETUP -------------------------------------------------------------
    SectionHeader {
        id: setupHeader
        Layout.topMargin: Theme.spaceSmall
        eyebrow: (root.harnessInstalled ? "engine ready" : "engine missing")
            + " · " + (root.skillInstalled ? "skills installed" : "skills available")
            + " · " + root.voiceSummaryText
        title: "Setup"
    }

    // Where authentication stands, with a pointer to the controls that stay next
    // to their provider (a sign-in happens where the provider is).
    SetupGroup {
        id: signInSetupGroup
        title: "Sign-ins"
        summary: root.quotaSummary.count === 0
            ? "no providers signed in"
            : (root.quotaSummary.count + (root.quotaSummary.count === 1 ? " provider · " : " providers · ")
                + (root.quotaSummary.state === "critical" ? "one needs attention" : "signed in"))
        state: root.quotaSummary.severity
        needsAttention: root.quotaSummary.state === "critical"

        RowLayout {
            Layout.fillWidth: true
            PillButton {
                label: "Open quotas"
                iconText: "arrow_upward"
                onClicked: root.jumpToZone("quotas")
            }
        }
    }


    // Pi harness - the engine behind the Copilot. A setup group: it states its own
    // condition in the header and opens itself only when it needs the user, so a
    // healthy machine does not show a permanently expanded update panel.
    SetupGroup {
        id: piSetupGroup
        title: "Pi harness"
        summary: root.harnessStatusText
        state: root.harnessInstalled ? "ok" : "attention"
        needsAttention: !root.harnessInstalled

        ColumnLayout {
            id: harnessCol
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                MaterialIcon {
                    text: root.harnessInstalled ? "smart_toy" : "extension_off"
                    size: 20
                    color: root.harnessInstalled ? Colors.primary : Colors.m3onSurfaceVariant
                }

                Text {
                    id: harnessStatus
                    Layout.fillWidth: true
                    text: root.harnessStatusText
                        + (root.harnessPath !== "" ? "  ·  " + root.harnessPath : "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }
            }

            Text {
                id: harnessHint
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.harnessInstalled
                    ? "The Copilot runs your own pi installation. Astral reports the version it finds; updating runs the same `pi update` your terminal would."
                    : "The Copilot needs the pi harness. Install it, then update it from here whenever a new version ships."
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Colors.m3onSurfaceVariant
                opacity: 0.85
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                PillButton {
                    id: updatePiButton
                    visible: root.harnessInstalled
                    label: root.harnessUpdating ? "Updating…" : "Update Pi"
                    variant: "filled"
                    // One update at a time: the daemon runs real commands.
                    enabled: !root.harnessUpdating
                    onClicked: root.updatePi()
                }

                PillButton {
                    id: updatePackagesButton
                    visible: root.harnessInstalled
                    label: "Update packages"
                    enabled: !root.harnessUpdating
                    onClicked: root.updatePiPackages()
                }

                PillButton {
                    id: refreshCatalogsButton
                    visible: root.harnessInstalled
                    label: "Refresh model catalogs"
                    enabled: !root.harnessUpdating
                    onClicked: root.refreshPiModelCatalogs()
                }

                PillButton {
                    id: harnessInstallButton
                    visible: !root.harnessInstalled
                    label: "Copy install command"
                    variant: "filled"
                    onClicked: root.copyHarnessInstallCommand()
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: !root.harnessInstalled
                    text: root.harnessInstallCommand
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Colors.m3onSurfaceVariant
                    opacity: 0.85
                }
            }

            Text {
                id: harnessResult
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.harnessUpdateMessage !== ""
                text: root.harnessUpdateMessage
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: root.harnessUpdateState === "failed"
                    ? Colors.error
                    : (root.harnessUpdating ? Colors.m3onSurfaceVariant : Colors.primary)
            }

            Text {
                id: harnessDetail
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.harnessUpdateDetail !== ""
                text: root.harnessUpdateDetail
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Colors.m3onSurfaceVariant
                opacity: 0.75
            }
        }
    }

    // =======================================================================
    // Desktop Agent Skills
    //
    // Provides autonomous desktop control & inspection tools to AI agents
    // (Antigravity, Agy, Claude Code, Cursor, Pi).
    // =======================================================================
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
    }

    SetupGroup {
        id: skillsSetupGroup
        title: "Desktop Agent Skills"
        summary: root.skillInstalled ? "astral-desktop-tools active" : "skills available"
        state: root.skillInstalled ? "ok" : "idle"
        needsAttention: false

        ColumnLayout {
            id: skillsCol
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                MaterialIcon {
                    text: root.skillInstalled ? "psychology" : "extension_off"
                    size: 20
                    color: root.skillInstalled ? Colors.primary : Colors.m3onSurfaceVariant
                }

                Text {
                    id: skillStatus
                    Layout.fillWidth: true
                    text: root.skillStatusText
                        + (root.skillLocations && root.skillLocations.length > 0 ? ("  ·  " + root.skillLocations.length + " target(s)") : "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyMedium
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }
            }

            Text {
                id: skillHint
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.skillInstalled
                    ? "Installed agent skill `astral-desktop-tools` allows autonomous coding assistants (Antigravity, Agy, Claude Code) to inspect windows, change workspaces, control notifications, and query system health."
                    : "The `astral-desktop-tools` skill teaches AI coding assistants how to inspect open windows, switch workspaces, and diagnose system crashes using Astral Plasma's native CLI."
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Colors.m3onSurfaceVariant
                opacity: 0.85
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                PillButton {
                    id: installSkillButton
                    visible: !root.skillInstalled
                    label: root.skillOperating ? "Installing…" : "Install Skill"
                    variant: "filled"
                    enabled: !root.skillOperating
                    onClicked: root.installSkill()
                }

                PillButton {
                    id: reinstallSkillButton
                    visible: root.skillInstalled
                    label: root.skillOperating ? "Updating…" : "Reinstall / Update"
                    enabled: !root.skillOperating
                    onClicked: root.installSkill()
                }

                PillButton {
                    id: uninstallSkillButton
                    visible: root.skillInstalled
                    label: root.skillOperating ? "Removing…" : "Uninstall Skill"
                    enabled: !root.skillOperating
                    onClicked: root.uninstallSkill()
                }
            }

            Repeater {
                model: root.skillLocations
                delegate: Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    text: "• " + modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                    opacity: 0.75
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.spaceExtraSmall
            }
        }
    }

    // Spacer
    Item {
        Layout.fillWidth: true
        height: 32
    }
}
