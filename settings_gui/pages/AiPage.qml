import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
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


    readonly property alias voicePanelItem: voicePanel
    readonly property alias voiceModelRemoveItem: voiceModelRemove

    /// Section anchors for deep links: the Copilot's setup notice says
    /// "Settings > AI > Voice input" and must land on the voice section instead
    /// of leaving the reader at the top of the page.
    function sectionY(name) {
        // The voice panel is nested inside its own card, so its own `y` is
        // relative to that card: map it into the page's space, which is what the
        // settings hub scrolls.
        if (name === "voice") return voicePanel.mapToItem(root, 0, 0).y;
        return undefined;
    }

    // --- Voice input test seams (mirroring the existing pattern) -----------
    property bool testVoiceEnabled: true
    property string testVoiceModel: "ggml-small"
    property string testVoiceLanguage: "auto"
    property bool testVoiceAutoFinalize: true
    property int testVoiceSilenceHangoverMs: 1200
    property int testVoiceMaxUtteranceSeconds: 30
    property var testVoiceStatus: null
    property real testVoiceModelInstallProgress: 0.0
    property bool testVoiceModelInstalling: false

    /** Which voice dropdown is open. Mutually exclusive by construction. */
    property bool modelMenuOpen: false
    property bool languageMenuOpen: false

    readonly property bool voiceEnabled: testMode ? testVoiceEnabled
        : ((typeof Config !== "undefined" && Config.voiceEnabled !== undefined) ? Config.voiceEnabled : true)
    readonly property string voiceModel: testMode ? testVoiceModel
        : ((typeof Config !== "undefined" && Config.voiceModel) ? Config.voiceModel : "ggml-small")
    readonly property string voiceLanguage: testMode ? testVoiceLanguage
        : ((typeof Config !== "undefined" && Config.voiceLanguage) ? Config.voiceLanguage : "auto")
    readonly property bool voiceAutoFinalize: testMode ? testVoiceAutoFinalize
        : ((typeof Config !== "undefined" && Config.voiceAutoFinalize !== undefined) ? Config.voiceAutoFinalize : true)
    readonly property int voiceSilenceHangoverMs: testMode ? testVoiceSilenceHangoverMs
        : ((typeof Config !== "undefined" && Config.voiceSilenceHangoverMs) ? Config.voiceSilenceHangoverMs : 1200)
    readonly property int voiceMaxUtteranceSeconds: testMode ? testVoiceMaxUtteranceSeconds
        : ((typeof Config !== "undefined" && Config.voiceMaxUtteranceSeconds) ? Config.voiceMaxUtteranceSeconds : 30)

    /** Live status from `voice status`, or the test seam. */
    readonly property var voiceStatus: testMode ? testVoiceStatus
        : ((typeof AssistantService !== "undefined") ? AssistantService.voiceStatus : null)

    readonly property bool voiceEngineAvailable: voiceStatus !== null && voiceStatus.engine_available === true
    readonly property bool voiceModelPresent: voiceStatus !== null && voiceStatus.model_present === true
    readonly property bool voiceReady: voiceStatus !== null && voiceStatus.setup_complete === true
    readonly property real voiceModelInstallProgress: testMode ? testVoiceModelInstallProgress
        : ((typeof AssistantService !== "undefined") ? (AssistantService.voiceModelInstallProgress || 0) : 0)
    readonly property bool voiceModelInstalling: testMode ? testVoiceModelInstalling
        : ((typeof AssistantService !== "undefined") ? (AssistantService.voiceModelInstalling === true) : false)

    readonly property string voiceModelSizeLabel: {
        const models = (voiceStatus && voiceStatus.models_available) ? voiceStatus.models_available : [];
        for (let i = 0; i < models.length; i++) {
            if (models[i].id === voiceModel) return models[i].size_label;
        }
        return "";
    }

    /** Options come from the daemon's catalog, so adding a model is a data change. */
    readonly property var voiceModelOptions: {
        const models = (voiceStatus && voiceStatus.models_available) ? voiceStatus.models_available : [];
        if (models.length > 0) {
            return models.map(m => ({ "id": m.id, "label": m.display_name + "  \u00b7  " + m.size_label }));
        }
        return [{ "id": "ggml-small", "label": "Small (balanced, default)" }];
    }

    readonly property var voiceLanguageOptions: {
        const langs = (voiceStatus && voiceStatus.languages) ? voiceStatus.languages : [];
        if (langs.length > 0) return langs.map(l => ({ "code": l.code, "label": l.label }));
        return [{ "code": "auto", "label": "Auto-detect" }];
    }

    /** Honest, specific status text -- never a generic "ready". */
    readonly property string voiceStatusSummary: {
        if (!voiceEnabled) return "Voice dictation is disabled";
        if (voiceStatus === null) return "Checking speech engine\u2026";
        if (!voiceEngineAvailable) return "whisper.cpp engine not installed";
        if (!voiceModelPresent) return "Model " + voiceModel + " is not downloaded yet";
        if (!voiceReady) return "No microphone available";
        return "Ready \u00b7 " + voiceModel;
    }

    /**
     * The command that installs the engine on *this* machine, as reported by the
     * daemon. Empty when the distribution is not one we can name a package for.
     */
    readonly property string voiceInstallCommand: (voiceStatus && voiceStatus.engine_install_command)
                                                  ? voiceStatus.engine_install_command : ""

    /** What to tell someone whose engine is missing: a command they can run, or
     *  the upstream build if we do not know their package manager. */
    readonly property string voiceEngineNotice: voiceInstallCommand.length > 0
        ? "whisper.cpp engine not installed. Run: " + voiceInstallCommand
        : "whisper.cpp engine not installed. Build it from https://github.com/ggml-org/whisper.cpp"

    function setVoiceModel(id) {
        if (testMode) {
            testVoiceModel = id;
        } else if (typeof Config !== "undefined") {
            Config.setVoiceModel(id);
        }
    }

    function setVoiceLanguage(code) {
        if (testMode) {
            testVoiceLanguage = code;
        } else if (typeof Config !== "undefined") {
            Config.setVoiceLanguage(code);
        }
    }

    function setVoiceAutoFinalize(v) {
        if (testMode) {
            testVoiceAutoFinalize = v;
        } else if (typeof Config !== "undefined") {
            Config.setVoiceAutoFinalize(v);
        }
    }

    /**
     * Re-probes voice readiness.
     *
     * NexusHub loads pages through a Loader, so this page is constructed
     * *already visible*: `visible` never changes on the first show and
     * `onVisibleChanged` alone would never fire. The probe is cheap and the
     * engine can be installed while the shell runs, so readiness is re-read
     * whenever the page is constructed or the settings window is shown again -
     * never trusted from a status cached when the shell started.
     */
    function refreshVoiceReadiness() {
        if (testMode) return;
        if (typeof AssistantService !== "undefined" && typeof AssistantService.refreshVoiceStatus === "function") {
            AssistantService.refreshVoiceStatus();
        }
    }

    Component.onCompleted: refreshVoiceReadiness()

    onVisibleChanged: if (visible) refreshVoiceReadiness()

    // The window can be closed and re-opened while the Loader keeps this page
    // instantiated, so page visibility is not the only "the user is looking at
    // it" edge: re-probe when the settings surface comes up as well.
    Connections {
        target: (typeof Config !== "undefined") ? Config : null

        function onSettingsVisibleChanged() {
            if (typeof Config === "undefined" || !Config.settingsVisible) return;
            root.refreshVoiceReadiness();
        }
    }

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

    // =======================================================================
    // Voice Input
    //
    // Lives inside the AI page rather than in a page of its own: voice is a
    // feature *of the assistant*, and AGENTS.md 6 warns specifically against
    // adding surface that does not match the existing design language.
    //
    // Provisioning is detect-then-offer (D7): nothing is installed or downloaded
    // without an explicit click, because silently pulling 1.5 GiB is hostile.
    // =======================================================================
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
    }

    Text {
        text: "Voice Input"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontTitleLarge
        font.weight: Font.Bold
        color: Colors.m3onSurface
        Layout.leftMargin: Theme.padSmall
        Layout.topMargin: Theme.spaceSmall
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.padSmall
        text: "Dictate prompts in the assistant composer. Transcription runs locally on this machine; audio never leaves it."
        font.family: Theme.fontFamily
        font.pixelSize: 11
        color: Colors.m3onSurfaceVariant
        wrapMode: Text.WordWrap
    }

    // Master toggle
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
                text: "mic"
                size: 26
                color: root.voiceEnabled ? Colors.primary : Colors.m3onSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Voice Dictation"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Text {
                    text: root.voiceStatusSummary
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Colors.m3onSurfaceVariant
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                width: 48
                height: 26
                radius: 13
                color: root.voiceEnabled ? Colors.primary : Colors.surfaceContainerHighest
                border.color: root.voiceEnabled ? Colors.primary : Theme.borderSubtle
                border.width: 1

                Behavior on color { ColorAnimation { duration: 150 } }

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    color: root.voiceEnabled ? Colors.textOnPrimary : Colors.m3onSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.voiceEnabled ? parent.width - width - 3 : 3

                    Behavior on x {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.testMode) {
                            root.testVoiceEnabled = !root.testVoiceEnabled;
                        } else if (typeof Config !== "undefined") {
                            Config.setVoiceEnabled(!root.voiceEnabled);
                        }
                        if (typeof AssistantService !== "undefined") AssistantService.refreshVoiceStatus();
                    }
                }
            }
        }
    }

    // Setup panel: engine, model, languages, endpointing.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: voicePanel.implicitHeight + Theme.padLarge * 2
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        visible: root.voiceEnabled

        ColumnLayout {
            id: voicePanel
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: Theme.spaceMedium

            // --- Engine + model readiness -------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                MaterialIcon {
                    text: root.voiceReady ? "check_circle" : "info"
                    size: 16
                    color: root.voiceReady ? Colors.primary : Colors.m3onSurfaceVariant
                }

                Text {
                    Layout.fillWidth: true
                    text: root.voiceStatusSummary
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Colors.m3onSurface
                    wrapMode: Text.WordWrap
                }
            }

            // --- Install engine (only when missing) -----------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.radiusSmall
                color: Qt.alpha(Colors.m3error, 0.10)
                border.color: Qt.alpha(Colors.m3error, 0.35)
                border.width: 1
                visible: root.voiceEnabled && !root.voiceEngineAvailable

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.padMedium
                    anchors.rightMargin: Theme.padSmall
                    spacing: Theme.spaceSmall

                    Text {
                        Layout.fillWidth: true
                        text: root.voiceEngineNotice
                        font.family: Theme.fontMonospace
                        font.pixelSize: 10
                        color: Colors.m3onSurface
                        elide: Text.ElideRight
                    }
                }
            }

            // --- Model picker --------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceExtraSmall

                Text {
                    text: "Speech model"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSmall

                    // Dropdown built from the project's own idiom (a rounded
                    // trigger plus a list that expands the panel inline), because
                    // QtQuick.Controls is not imported anywhere in this shell.
                    Item {
                        id: modelDropdown
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32

                        readonly property var currentLabel: {
                            for (let i = 0; i < root.voiceModelOptions.length; i++) {
                                if (root.voiceModelOptions[i].id === root.voiceModel) {
                                    return root.voiceModelOptions[i].label;
                                }
                            }
                            return root.voiceModel;
                        }

                        Rectangle {
                            id: modelTrigger
                            objectName: "voiceModelTrigger"
                            anchors.fill: parent
                            radius: Theme.radiusSmall
                            color: modelTriggerHover.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainer
                            border.width: 1
                            border.color: root.modelMenuOpen ? Colors.primary : Theme.borderSubtle

                            Behavior on color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.padSmall
                                anchors.rightMargin: Theme.padSmall
                                spacing: Theme.spaceExtraSmall

                                MaterialIcon {
                                    text: "memory"
                                    size: 14
                                    color: Colors.secondary
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelDropdown.currentLabel
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Colors.m3onSurface
                                    elide: Text.ElideRight
                                }

                                MaterialIcon {
                                    text: "expand_more"
                                    size: 14
                                    color: Colors.m3onSurfaceVariant
                                    rotation: root.modelMenuOpen ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: Theme.animExpressiveFastEffects } }
                                }
                            }

                            MouseArea {
                                id: modelTriggerHover
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.voiceEnabled
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.languageMenuOpen = false;
                                    root.modelMenuOpen = !root.modelMenuOpen;
                                }
                            }
                        }

                    }

                    Rectangle {
                        Layout.preferredWidth: 132
                        Layout.preferredHeight: 32
                        radius: Theme.radiusSmall
                        color: root.voiceModelPresent ? Qt.alpha(Colors.primary, 0.14) : Qt.alpha(Colors.primary, 0.20)
                        border.color: Qt.alpha(Colors.primary, 0.40)
                        border.width: 1
                        enabled: root.voiceEnabled && !root.voiceModelPresent && !root.voiceModelInstalling

                        Text {
                            anchors.centerIn: parent
                            text: root.voiceModelInstalling
                                ? Math.round(root.voiceModelInstallProgress * 100) + "%"
                                : (root.voiceModelPresent ? "Downloaded" : "Download (" + root.voiceModelSizeLabel + ")")
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: root.voiceModelPresent ? Colors.primary : Colors.m3onSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.enabled
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (typeof AssistantService !== "undefined") {
                                    AssistantService.installVoiceModel(root.voiceModel);
                                }
                            }
                        }
                    }

                    // Remove: only offered once a model is actually on disk, so
                    // the row never shows a destructive control for a download
                    // that has not happened.
                    Rectangle {
                        id: voiceModelRemove
                        visible: root.voiceModelPresent
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: Theme.radiusSmall
                        color: removeHover.containsMouse ? Qt.alpha(Colors.m3error, 0.18) : "transparent"
                        border.width: 1
                        border.color: removeHover.containsMouse ? Qt.alpha(Colors.m3error, 0.45) : Colors.glassBorderSpecular
                        enabled: root.voiceEnabled && root.voiceModelPresent && !root.voiceModelInstalling

                        MaterialIcon {
                            anchors.centerIn: parent
                            iconName: "delete"
                            size: 16
                            color: removeHover.containsMouse ? Colors.m3error : Colors.m3onSurfaceVariant
                        }

                        MouseArea {
                            id: removeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: parent.enabled
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (typeof AssistantService !== "undefined") {
                                    AssistantService.removeVoiceModel(root.voiceModel);
                                }
                            }
                        }
                    }
                }

                // Expands INLINE rather than overlaying.
                //
                // As an absolutely positioned popup this painted straight over the
                // sections below it -- the Language picker and the auto-finalize
                // switch were covered by the model list. Growing the panel instead
                // makes overlap structurally impossible, and follows the
                // content-driven-height rule in docs/LESSONS.md 7.1.
                Rectangle {
                    id: modelList
                    objectName: "voiceModelList"
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spaceExtraSmall
                    Layout.preferredHeight: root.modelMenuOpen
                        ? Math.min(240, modelListCol.implicitHeight + 12) : 0
                    visible: root.modelMenuOpen
                    clip: true
                    radius: Theme.radiusSmall
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.10, 0.12, 0.17, 0.95) : Qt.rgba(0.96, 0.97, 1.0, 0.95)
                    border.width: 1
                    border.color: Colors.glassBorderSpecular

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: Theme.animExpressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveExpressiveFastSpatial
                        }
                    }

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 6
                        contentHeight: modelListCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: modelListCol
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: root.voiceModelOptions

                                delegate: Rectangle {
                                    width: modelListCol.width
                                    height: 28
                                    radius: Theme.radiusSmall
                                    color: modelItemHover.containsMouse ? Qt.alpha(Colors.primary, 0.12) : "transparent"
                                    border.width: modelData.id === root.voiceModel ? 1 : 0
                                    border.color: Colors.primary

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.padSmall
                                        anchors.rightMargin: Theme.padSmall
                                        spacing: Theme.spaceExtraSmall

                                        MaterialIcon {
                                            text: modelData.id === root.voiceModel ? "check" : "memory"
                                            size: 14
                                            color: modelData.id === root.voiceModel ? Colors.primary : Colors.secondary
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: modelData.id === root.voiceModel ? Font.DemiBold : Font.Normal
                                            color: Colors.m3onSurface
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: modelItemHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: root.voiceEnabled
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.testMode) {
                                                root.testVoiceModel = modelData.id;
                                            } else if (typeof Config !== "undefined") {
                                                Config.setVoiceModel(modelData.id);
                                            }
                                            root.modelMenuOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- Language picker -----------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceExtraSmall

                Text {
                    text: "Language"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                }

                Text {
                    Layout.fillWidth: true
                    text: "Auto-detect is unreliable on short clips. The detected language is shown while you speak, so you can override it."
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Colors.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }

                // Language dropdown, same idiom as the model picker. ~20
                // locales is far too many for a segmented control, and this
                // keeps the page free of QtQuick.Controls. The list is capped
                // and scrolls; see languageList below.
                Item {
                    id: languageDropdown
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32

                    readonly property string currentLabel: {
                        for (let i = 0; i < root.voiceLanguageOptions.length; i++) {
                            if (root.voiceLanguageOptions[i].code === root.voiceLanguage) {
                                return root.voiceLanguageOptions[i].label;
                            }
                        }
                        return root.voiceLanguage;
                    }

                    Rectangle {
                        id: languageTrigger
                        objectName: "voiceLanguageTrigger"
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: languageTriggerHover.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainer
                        border.width: 1
                        border.color: root.languageMenuOpen ? Colors.primary : Theme.borderSubtle

                        Behavior on color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padSmall
                            anchors.rightMargin: Theme.padSmall
                            spacing: Theme.spaceExtraSmall

                            MaterialIcon {
                                text: "translate"
                                size: 14
                                color: Colors.primary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: languageDropdown.currentLabel
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Colors.m3onSurface
                                elide: Text.ElideRight
                            }

                            MaterialIcon {
                                text: "expand_more"
                                size: 14
                                color: Colors.m3onSurfaceVariant
                                rotation: root.languageMenuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Theme.animExpressiveFastEffects } }
                            }
                        }

                        MouseArea {
                            id: languageTriggerHover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.voiceEnabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.modelMenuOpen = false;
                                root.languageMenuOpen = !root.languageMenuOpen;
                            }
                        }
                    }

                }

                // Inline expansion, same reason as the model list above.
                Rectangle {
                    id: languageList
                    objectName: "voiceLanguageList"
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spaceExtraSmall
                    Layout.preferredHeight: root.languageMenuOpen
                        ? Math.min(280, languageListCol.implicitHeight + 12) : 0
                    visible: root.languageMenuOpen
                    clip: true
                    radius: Theme.radiusSmall
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.10, 0.12, 0.17, 0.95) : Qt.rgba(0.96, 0.97, 1.0, 0.95)
                    border.width: 1
                    border.color: Colors.glassBorderSpecular

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: Theme.animExpressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.curveExpressiveFastSpatial
                        }
                    }

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 6
                        contentHeight: languageListCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: languageListCol
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: root.voiceLanguageOptions

                                delegate: Rectangle {
                                    width: languageListCol.width
                                    height: 28
                                    radius: Theme.radiusSmall
                                    color: languageItemHover.containsMouse ? Qt.alpha(Colors.primary, 0.12) : "transparent"
                                    border.width: modelData.code === root.voiceLanguage ? 1 : 0
                                    border.color: Colors.primary

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.padSmall
                                        anchors.rightMargin: Theme.padSmall
                                        spacing: Theme.spaceExtraSmall

                                        MaterialIcon {
                                            text: modelData.code === root.voiceLanguage ? "check" : "translate"
                                            size: 14
                                            color: modelData.code === root.voiceLanguage ? Colors.primary : Colors.m3onSurfaceVariant
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.weight: modelData.code === root.voiceLanguage ? Font.DemiBold : Font.Normal
                                            color: Colors.m3onSurface
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: languageItemHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: root.voiceEnabled
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.testMode) {
                                                root.testVoiceLanguage = modelData.code;
                                            } else if (typeof Config !== "undefined") {
                                                Config.setVoiceLanguage(modelData.code);
                                            }
                                            root.languageMenuOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }


            // --- Endpointing ---------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSmall

                    Text {
                        Layout.fillWidth: true
                        text: "Stop automatically after a pause"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Colors.m3onSurface
                    }

                    Rectangle {
                        width: 40
                        height: 22
                        radius: 11
                        color: root.voiceAutoFinalize ? Colors.primary : Colors.surfaceContainerHighest
                        border.color: root.voiceAutoFinalize ? Colors.primary : Theme.borderSubtle
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 16
                            height: 16
                            radius: 8
                            color: root.voiceAutoFinalize ? Colors.textOnPrimary : Colors.m3onSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.voiceAutoFinalize ? parent.width - width - 3 : 3

                            Behavior on x {
                                NumberAnimation { duration: Theme.animExpressiveFastSpatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveExpressiveFastSpatial }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.testMode) {
                                    root.testVoiceAutoFinalize = !root.testVoiceAutoFinalize;
                                } else if (typeof Config !== "undefined") {
                                    Config.setVoiceAutoFinalize(!root.voiceAutoFinalize);
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.voiceAutoFinalize
                        ? "Finishes after " + root.voiceSilenceHangoverMs + " ms of silence, or at " + root.voiceMaxUtteranceSeconds + " s, whichever comes first. Stopping manually always works."
                        : "Only the stop button ends a recording. Maximum " + root.voiceMaxUtteranceSeconds + " s."
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Colors.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }

            Item { Layout.preferredHeight: 1 }
        }
    }

    // Spacer
    Item {
        Layout.fillWidth: true
        height: 32
    }
}
