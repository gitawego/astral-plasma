import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"
import "../../config"
import "../../services"

/**
 * Settings surface for on-device and cloud speech-to-text voice dictation.
 *
 * Dedicated page for configuring speech recognition engines (whisper.cpp,
 * Sherpa-ONNX, Deepgram), downloading models, neural VAD, and microphone checks.
 */
SettingsPage {
    id: root
    spacing: Theme.spaceLarge
    width: parent ? parent.width : 600

    title: "Voice Dictation"
    subtitle: "Speech-to-text engines, on-device models & microphone settings"

    zones: [
        { id: "engine", label: "Speech Engine", anchor: engineCard },
        { id: "model", label: "Speech Model", anchor: modelCard },
        { id: "audio", label: "Audio & Mic", anchor: audioCard },
        { id: "preferences", label: "Preferences", anchor: preferencesCard }
    ]

    readonly property alias voiceModelRemoveItem: voiceModelRemoveItem
    readonly property alias voicePanelItem: root
    readonly property alias voiceModelListItem: modelList
    readonly property alias voiceLanguageListItem: languageList

    readonly property int padLargeVal: (typeof Theme !== "undefined" && Theme.padLarge !== undefined) ? Theme.padLarge : 16
    readonly property int padMediumVal: (typeof Theme !== "undefined" && Theme.padMedium !== undefined) ? Theme.padMedium : 12
    readonly property int padSmallVal: (typeof Theme !== "undefined" && Theme.padSmall !== undefined) ? Theme.padSmall : 8
    readonly property int spaceLargeVal: (typeof Theme !== "undefined" && Theme.spaceLarge !== undefined) ? Theme.spaceLarge : 16
    readonly property int spaceMediumVal: (typeof Theme !== "undefined" && Theme.spaceMedium !== undefined) ? Theme.spaceMedium : 12
    readonly property int spaceSmallVal: (typeof Theme !== "undefined" && Theme.spaceSmall !== undefined) ? Theme.spaceSmall : 8
    readonly property int spaceExtraSmallVal: (typeof Theme !== "undefined" && Theme.spaceExtraSmall !== undefined) ? Theme.spaceExtraSmall : 4
    readonly property int radiusMediumVal: (typeof Theme !== "undefined" && Theme.radiusMedium !== undefined) ? Theme.radiusMedium : 12
    readonly property int radiusSmallVal: (typeof Theme !== "undefined" && Theme.radiusSmall !== undefined) ? Theme.radiusSmall : 8
    readonly property int animDurationFast: (typeof Theme !== "undefined" && Theme.animExpressiveFastSpatial !== undefined) ? Theme.animExpressiveFastSpatial : 350

    property bool testMode: false
    property bool testVoiceEnabled: true
    property string testVoiceEngine: "whisper-cpp"
    property string testVoiceModel: "ggml-small"
    property string testVoiceLanguage: ""
    property bool testVoiceAutoFinalize: true
    property bool testVoiceEchoCancel: false
    property bool testVoiceNoiseSuppress: false
    property int testVoiceSilenceHangoverMs: 1200
    property int testVoiceMaxUtteranceSeconds: 30
    property var testVoiceStatus: null
    property real testVoiceModelInstallProgress: 0.0
    property bool testVoiceModelInstalling: false
    property bool testVoiceVadModelPresent: false
    property bool testVoiceVadInstalling: false
    property real testVoiceVadInstallProgress: 0.0
    property var testVoiceMicCheckResult: null
    property bool testVoiceMicChecking: false

    property bool modelMenuOpen: false
    property bool languageMenuOpen: false

    onModelMenuOpenChanged: if (modelMenuOpen) languageMenuOpen = false
    onLanguageMenuOpenChanged: if (languageMenuOpen) modelMenuOpen = false

    readonly property bool voiceEnabled: testMode ? testVoiceEnabled
        : ((typeof Config !== "undefined" && Config.voiceEnabled !== undefined) ? Config.voiceEnabled : true)
    readonly property string voiceEngine: testMode ? testVoiceEngine
        : ((typeof Config !== "undefined" && Config.voiceEngine) ? Config.voiceEngine : "whisper-cpp")
    readonly property string voiceModel: testMode ? testVoiceModel
        : ((typeof Config !== "undefined" && Config.voiceModel) ? Config.voiceModel : "ggml-small")
    readonly property string voiceLanguage: testMode ? testVoiceLanguage
        : ((typeof Config !== "undefined" && Config.voiceLanguage) ? Config.voiceLanguage : "")
    readonly property bool voiceAutoFinalize: testMode ? testVoiceAutoFinalize
        : ((typeof Config !== "undefined" && Config.voiceAutoFinalize !== undefined) ? Config.voiceAutoFinalize : true)
    readonly property bool voiceEchoCancel: testMode ? testVoiceEchoCancel
        : ((typeof Config !== "undefined" && Config.voiceEchoCancel !== undefined) ? Config.voiceEchoCancel : false)
    readonly property bool voiceNoiseSuppress: testMode ? testVoiceNoiseSuppress
        : ((typeof Config !== "undefined" && Config.voiceNoiseSuppress !== undefined) ? Config.voiceNoiseSuppress : false)

    readonly property int voiceSilenceHangoverMs: testMode ? testVoiceSilenceHangoverMs
        : ((typeof Config !== "undefined" && Config.voiceSilenceHangoverMs) ? Config.voiceSilenceHangoverMs : 1200)
    readonly property int voiceMaxUtteranceSeconds: testMode ? testVoiceMaxUtteranceSeconds
        : ((typeof Config !== "undefined" && Config.voiceMaxUtteranceSeconds) ? Config.voiceMaxUtteranceSeconds : 30)

    readonly property var voiceStatus: testMode ? testVoiceStatus
        : ((typeof AssistantService !== "undefined") ? AssistantService.voiceStatus : null)

    readonly property bool voiceStatusCurrent: voiceStatus !== null
        && (!voiceStatus.engine || voiceStatus.engine === root.voiceEngine)

    readonly property bool voiceEngineAvailable: voiceStatusCurrent && voiceStatus.engine_available === true

    readonly property bool voiceModelPresent: voiceStatusCurrent
        && (!voiceStatus.model || voiceStatus.model === root.voiceModel)
        && voiceStatus.model_present === true

    readonly property bool voiceReady: voiceStatusCurrent && voiceStatus.setup_complete === true
    readonly property real voiceModelInstallProgress: testMode ? testVoiceModelInstallProgress
        : ((typeof AssistantService !== "undefined") ? (AssistantService.voiceModelInstallProgress || 0) : 0)
    readonly property bool voiceModelInstalling: testMode ? testVoiceModelInstalling
        : ((typeof AssistantService !== "undefined") ? (AssistantService.voiceModelInstalling === true) : false)

    readonly property bool voiceVadModelPresent: testMode ? testVoiceVadModelPresent
        : ((voiceStatus !== null && voiceStatus.vad_model_present === true))
    readonly property bool voiceVadInstalling: testMode ? testVoiceVadInstalling
        : ((typeof AssistantService !== "undefined") ? (AssistantService.voiceVadInstalling === true) : false)
    readonly property real voiceVadInstallProgress: testMode ? testVoiceVadInstallProgress
        : ((typeof AssistantService !== "undefined") ? (AssistantService.voiceVadInstallProgress || 0) : 0)

    readonly property var voiceMicCheckResult: testMode ? testVoiceMicCheckResult
        : ((typeof AssistantService !== "undefined") ? AssistantService.voiceMicCheckResult : null)
    readonly property bool voiceMicChecking: testMode ? testVoiceMicChecking
        : ((typeof AssistantService !== "undefined") ? (AssistantService.voiceMicChecking === true) : false)
    readonly property string voiceMicCheckSummary: {
        if (voiceMicChecking) return "Listening… speak normally";
        if (!voiceMicCheckResult) return "Not tested yet";
        const verdict = voiceMicCheckResult.verdict || "silent";
        const peak = (typeof voiceMicCheckResult.peak_rms === "number")
            ? Math.round(voiceMicCheckResult.peak_rms * 100) + "%" : "?";
        if (verdict === "ok") return "OK · peak " + peak;
        if (verdict === "clipping") return "Clipping · peak " + peak;
        return "Silent · peak " + peak;
    }

    readonly property string voiceModelSizeLabel: {
        const models = (voiceStatus && voiceStatus.models_available) ? voiceStatus.models_available : [];
        for (let i = 0; i < models.length; i++) {
            if (models[i].id === voiceModel) return models[i].size_label;
        }
        return "";
    }

    readonly property var voiceModelOptions: {
        const models = (voiceStatus && voiceStatus.models_available) ? voiceStatus.models_available : [];
        if (models.length > 0) {
            return models.map(m => ({ "id": m.id, "label": m.display_name + "  ·  " + m.size_label }));
        }
        return [{ "id": "ggml-small", "label": "Small (balanced, default)" }];
    }

    readonly property string systemLocaleName: {
        try {
            const name = Qt.locale().name;
            return name && name !== "C" ? name : "your locale";
        } catch (e) {
            return "your locale";
        }
    }

    readonly property var voiceLanguageOptions: {
        const langs = (voiceStatus && voiceStatus.languages) ? voiceStatus.languages : [];
        const withDefault = [{ "code": "", "label": "System default (" + root.systemLocaleName + ")" }];
        if (langs.length > 0) return withDefault.concat(langs.map(l => ({ "code": l.code, "label": l.label })));
        return withDefault.concat([{ "code": "auto", "label": "Auto-detect" }]);
    }

    readonly property string voiceStatusSummary: {
        if (!voiceEnabled) return "Voice dictation is disabled";
        const eng = root.voiceEngine;
        if (!voiceStatusCurrent) return "Checking speech engine…";
        if (eng === "deepgram") {
            return voiceEngineAvailable ? "Ready · Deepgram live" : "Deepgram API key missing";
        }
        if (eng === "sherpa-onnx") {
            if (!voiceEngineAvailable) return "sherpa-onnx engine not installed";
            if (!voiceModelPresent) return "SenseVoice model not downloaded yet";
            if (!voiceReady) return "No microphone available";
            return "Ready · SenseVoice (Sherpa-ONNX)";
        }
        if (!voiceEngineAvailable) return "whisper.cpp engine not installed";
        if (!voiceModelPresent) return "Model " + voiceModel + " is not downloaded yet";
        if (!voiceReady) return "No microphone available";
        return "Ready · " + voiceModel;
    }

    readonly property string voiceInstallCommand: (voiceStatus && voiceStatus.engine_install_command)
                                                  ? voiceStatus.engine_install_command : ""

    readonly property string voiceEngineNotice: {
        const eng = root.voiceEngine;
        if (eng === "deepgram") {
            return "Deepgram requires an API key in ~/.config/astral-plasma/deepgram_api_key or ASTRAL_DEEPGRAM_KEY.";
        }
        if (eng === "sherpa-onnx") {
            return (voiceStatusCurrent && voiceInstallCommand.length > 0)
                ? "sherpa-onnx engine not installed. Run: " + voiceInstallCommand
                : "sherpa-onnx engine not installed. Install via pip install sherpa-onnx";
        }
        return (voiceStatusCurrent && voiceInstallCommand.length > 0)
            ? "whisper.cpp engine not installed. Run: " + voiceInstallCommand
            : "whisper.cpp engine not installed. Build it from https://github.com/ggml-org/whisper.cpp";
    }

    function setVoiceEnabled(enabled) {
        if (testMode) {
            testVoiceEnabled = enabled;
        } else if (typeof Config !== "undefined") {
            Config.setVoiceEnabled(enabled);
        }
    }

    function setVoiceEngine(id) {
        if (testMode) {
            testVoiceEngine = id;
            if (id === "sherpa-onnx") {
                testVoiceModel = "sherpa-sensevoice-small";
            } else if (id === "whisper-cpp" && (testVoiceModel === "sherpa-sensevoice-small" || testVoiceModel === "nova-3")) {
                testVoiceModel = "ggml-small";
            } else if (id === "deepgram") {
                testVoiceModel = "nova-3";
            }
        } else if (typeof Config !== "undefined") {
            Config.setVoiceEngine(id);
            if (typeof AssistantService !== "undefined") {
                const targetModel = (id === "sherpa-onnx") ? "sherpa-sensevoice-small" : (id === "deepgram" ? "nova-3" : "ggml-small");
                AssistantService.refreshVoiceStatus(id, targetModel);
            }
        }
    }

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

    function setVoiceAutoFinalize(enabled) {
        if (testMode) {
            testVoiceAutoFinalize = enabled;
        } else if (typeof Config !== "undefined") {
            Config.setVoiceAutoFinalize(enabled);
        }
    }

    function setVoiceEchoCancel(enabled) {
        if (testMode) {
            testVoiceEchoCancel = enabled;
        } else if (typeof Config !== "undefined") {
            Config.setVoiceEchoCancel(enabled);
        }
    }

    function setVoiceNoiseSuppress(enabled) {
        if (testMode) {
            testVoiceNoiseSuppress = enabled;
        } else if (typeof Config !== "undefined") {
            Config.setVoiceNoiseSuppress(enabled);
        }
    }

    function installVoiceModel() {
        if (!testMode && typeof AssistantService !== "undefined") {
            AssistantService.installVoiceModel(root.voiceModel);
        }
    }

    function removeVoiceModel() {
        if (!testMode && typeof AssistantService !== "undefined") {
            AssistantService.removeVoiceModel(root.voiceModel);
        }
    }

    function installVoiceVadModel() {
        if (!testMode && typeof AssistantService !== "undefined") {
            AssistantService.installVoiceVadModel();
        }
    }

    function runMicCheck() {
        if (!testMode && typeof AssistantService !== "undefined") {
            AssistantService.runMicCheck();
        }
    }

    function refreshVoiceStatus() {
        if (!testMode && typeof AssistantService !== "undefined") {
            AssistantService.refreshVoiceStatus(root.voiceEngine, root.voiceModel);
        }
    }

    function refreshVoiceReadiness() {
        root.refreshVoiceStatus();
    }

    Component.onCompleted: root.refreshVoiceReadiness()
    onVisibleChanged: if (visible) root.refreshVoiceReadiness()

    Connections {
        target: (typeof Config !== "undefined") ? Config : null

        function onSettingsVisibleChanged() {
            if (typeof Config === "undefined" || !Config.settingsVisible) return;
            root.refreshVoiceReadiness();
        }

        function onVoiceEngineChanged() {
            root.refreshVoiceReadiness();
        }

        function onVoiceModelChanged() {
            root.refreshVoiceReadiness();
        }
    }

    function sectionY(name) {
        if (name === "voice" || name === "setup" || name === "engine") return engineCard.mapToItem(root, 0, 0).y;
        if (name === "model") return modelCard.mapToItem(root, 0, 0).y;
        if (name === "audio" || name === "mic") return audioCard.mapToItem(root, 0, 0).y;
        if (name === "preferences" || name === "pref") return preferencesCard.mapToItem(root, 0, 0).y;
        return undefined;
    }

    // =======================================================================
    // Content Layout
    // =======================================================================

    // Master Status & Switch Card
    Rectangle {
        Layout.fillWidth: true
        height: 72
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.padLarge
            spacing: Theme.spaceMedium

            MaterialIcon {
                text: "mic"
                size: 28
                color: root.voiceEnabled ? Colors.primary : Colors.m3onSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Voice Dictation"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }

                Text {
                    text: root.voiceStatusSummary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                width: 48
                height: 26
                radius: 13
                color: root.voiceEnabled ? Colors.primary : Colors.surfaceContainerHighest
                border.color: root.voiceEnabled ? Colors.primary : Theme.borderSubtle
                border.width: 1

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.voiceEnabled ? parent.width - width - 3 : 3
                    color: root.voiceEnabled ? Colors.m3onPrimary : Colors.m3onSurfaceVariant

                    Behavior on x { NumberAnimation { duration: 150 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setVoiceEnabled(!root.voiceEnabled)
                }
            }
        }
    }

    // --- Card 1: Speech Engine -----------------------------------------------
    Rectangle {
        id: engineCard
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        implicitHeight: engineCol.implicitHeight + root.padLargeVal * 2
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            id: engineCol
            anchors.fill: parent
            anchors.margins: root.padLargeVal
            spacing: root.spaceMediumVal

            RowLayout {
                Layout.fillWidth: true
                spacing: root.spaceSmallVal

                MaterialIcon {
                    text: "settings_suggest"
                    size: 20
                    color: Colors.primary
                }

                Text {
                    text: "Speech Engine"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }
            }

            // Engine Notice if engine binary is missing
            Rectangle {
                Layout.fillWidth: true
                visible: root.voiceEnabled && !root.voiceEngineAvailable
                radius: Theme.radiusSmall
                color: Qt.alpha(Colors.warning, 0.12)
                border.color: Qt.alpha(Colors.warning, 0.35)
                border.width: 1
                implicitHeight: noticeText.implicitHeight + root.padMediumVal * 2

                Text {
                    id: noticeText
                    anchors.fill: parent
                    anchors.margins: Theme.padMedium
                    text: root.voiceEngineNotice
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.m3onSurface
                    wrapMode: Text.WordWrap
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                PillButton {
                    objectName: "voiceEngineWhisper"
                    label: "whisper.cpp"
                    active: root.voiceEngine === "whisper-cpp"
                    variant: root.voiceEngine === "whisper-cpp" ? "filled" : "outlined"
                    onClicked: root.setVoiceEngine("whisper-cpp")
                }

                PillButton {
                    objectName: "voiceEngineSherpa"
                    label: "Sherpa-ONNX"
                    active: root.voiceEngine === "sherpa-onnx"
                    variant: root.voiceEngine === "sherpa-onnx" ? "filled" : "outlined"
                    onClicked: root.setVoiceEngine("sherpa-onnx")
                }

                PillButton {
                    objectName: "voiceEngineDeepgram"
                    label: "Deepgram"
                    active: root.voiceEngine === "deepgram"
                    variant: root.voiceEngine === "deepgram" ? "filled" : "outlined"
                    onClicked: root.setVoiceEngine("deepgram")
                }
            }
        }
    }

    // --- Card 2: Speech Model ------------------------------------------------
    Rectangle {
        id: modelCard
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        implicitHeight: modelCol.implicitHeight + root.padLargeVal * 2
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            id: modelCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padLargeVal
            spacing: root.spaceMediumVal

            RowLayout {
                Layout.fillWidth: true
                spacing: root.spaceSmallVal

                MaterialIcon {
                    text: "model_training"
                    size: 20
                    color: Colors.primary
                }

                Text {
                    text: "Speech Model"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.spaceSmallVal

                // Model dropdown trigger
                Item {
                    id: modelDropdown
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36

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
                        color: modelHover.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                        border.width: 1
                        border.color: root.modelMenuOpen ? Colors.primary : Theme.borderSubtle

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padMedium
                            anchors.rightMargin: Theme.padMedium
                            spacing: Theme.spaceSmall

                            MaterialIcon {
                                text: "memory"
                                size: 16
                                color: Colors.secondary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelDropdown.currentLabel
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBodyMedium
                                color: Colors.m3onSurface
                                elide: Text.ElideRight
                            }

                            MaterialIcon {
                                text: "expand_more"
                                size: 16
                                color: Colors.m3onSurfaceVariant
                                rotation: root.modelMenuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: modelHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.languageMenuOpen = false;
                                root.modelMenuOpen = !root.modelMenuOpen;
                            }
                        }
                    }
                }

                // Download Button
                Rectangle {
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 36
                    radius: Theme.radiusSmall
                    color: root.voiceModelPresent ? Qt.alpha(Colors.primary, 0.15) : Qt.alpha(Colors.primary, 0.25)
                    border.color: Qt.alpha(Colors.primary, 0.45)
                    border.width: 1
                    enabled: root.voiceEnabled && !root.voiceModelPresent && !root.voiceModelInstalling

                    Text {
                        anchors.centerIn: parent
                        text: root.voiceModelInstalling
                            ? Math.round(root.voiceModelInstallProgress * 100) + "%"
                            : (root.voiceModelPresent ? "Downloaded" : "Download (" + root.voiceModelSizeLabel + ")")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        font.weight: Font.Medium
                        color: root.voiceModelPresent ? Colors.primary : Colors.m3onSurface
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.installVoiceModel()
                    }
                }

                // Delete Button
                Rectangle {
                    id: voiceModelRemoveItem
                    objectName: "voiceModelRemoveButton"
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: Theme.radiusSmall
                    color: removeHover.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                    border.color: Theme.borderSubtle
                    border.width: 1
                    visible: root.voiceModelPresent

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "delete"
                        size: 16
                        color: Colors.error
                    }

                    MouseArea {
                        id: removeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeVoiceModel()
                    }
                }
            }

            // Inline Model Options List (bounded & animated expansion)
            Rectangle {
                id: modelList
                objectName: "voiceModelList"
                Layout.fillWidth: true
                Layout.topMargin: root.spaceExtraSmallVal
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
                        duration: root.animDurationFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
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
                                        root.setVoiceModel(modelData.id);
                                        root.modelMenuOpen = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Language picker (within Speech Recognition card)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceExtraSmall

                Text {
                    text: "Transcription Language"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontLabelSmall
                    color: Colors.m3onSurfaceVariant
                }

                Item {
                    id: langDropdown
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36

                    readonly property var currentLabel: {
                        for (let i = 0; i < root.voiceLanguageOptions.length; i++) {
                            if (root.voiceLanguageOptions[i].code === root.voiceLanguage) {
                                return root.voiceLanguageOptions[i].label;
                            }
                        }
                        return root.voiceLanguage === "" ? "System default (" + root.systemLocaleName + ")" : root.voiceLanguage;
                    }

                    Rectangle {
                        id: languageTrigger
                        objectName: "voiceLanguageTrigger"
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: langHover.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                        border.width: 1
                        border.color: root.languageMenuOpen ? Colors.primary : Theme.borderSubtle

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.padMedium
                            anchors.rightMargin: Theme.padMedium
                            spacing: Theme.spaceSmall

                            MaterialIcon {
                                text: "translate"
                                size: 16
                                color: Colors.secondary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: langDropdown.currentLabel
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBodyMedium
                                color: Colors.m3onSurface
                                elide: Text.ElideRight
                            }

                            MaterialIcon {
                                text: "expand_more"
                                size: 16
                                color: Colors.m3onSurfaceVariant
                                rotation: root.languageMenuOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: langHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.modelMenuOpen = false;
                                root.languageMenuOpen = !root.languageMenuOpen;
                            }
                        }
                    }
                }

                // Inline Language Options (bounded & animated expansion)
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
                            duration: root.animDurationFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: (typeof Theme !== "undefined" && Theme.curveExpressiveFastSpatial) ? Theme.curveExpressiveFastSpatial : [0.42, 1.67, 0.21, 0.9, 1.0, 1.0]
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
                                    color: langItemHover.containsMouse ? Qt.alpha(Colors.primary, 0.12) : "transparent"
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
                                        id: langItemHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: root.voiceEnabled
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.setVoiceLanguage(modelData.code);
                                            root.languageMenuOpen = false;
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

    // --- Card 3: Audio & Microphone ------------------------------------------
    Rectangle {
        id: audioCard
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        implicitHeight: audioCol.implicitHeight + root.padLargeVal * 2
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            id: audioCol
            anchors.fill: parent
            anchors.margins: root.padLargeVal
            spacing: Theme.spaceMedium

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                MaterialIcon {
                    text: "graphic_eq"
                    size: 20
                    color: Colors.primary
                }

                Text {
                    text: "Audio & Microphone"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }
            }

            // Silero Neural VAD row
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                MaterialIcon {
                    text: "hearing"
                    size: 20
                    color: root.voiceVadModelPresent ? Colors.primary : Colors.m3onSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Neural Voice Activity Detection (Silero VAD)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: root.voiceVadModelPresent ? "Neural endpointing active (clean sentence boundaries)" : "Energy detector active (Silero model not installed)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                Rectangle {
                    id: voiceVadInstallButton
                    objectName: "voiceVadInstallButton"
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: 32
                    radius: Theme.radiusSmall
                    color: root.voiceVadModelPresent ? Qt.alpha(Colors.primary, 0.12) : Qt.alpha(Colors.primary, 0.22)
                    border.color: Qt.alpha(Colors.primary, 0.40)
                    border.width: 1
                    enabled: !root.voiceVadModelPresent && !root.voiceVadInstalling

                    Text {
                        anchors.centerIn: parent
                        text: root.voiceVadInstalling ? Math.round(root.voiceVadInstallProgress * 100) + "%" : (root.voiceVadModelPresent ? "Ready" : "Download")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: root.voiceVadModelPresent ? Colors.primary : Colors.m3onSurface
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.installVoiceVadModel()
                    }
                }
            }

            // Microphone Level Check row
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                MaterialIcon {
                    text: "mic_external_on"
                    size: 20
                    color: Colors.secondary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Microphone Check"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: root.voiceMicCheckSummary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                Rectangle {
                    id: voiceMicCheckButton
                    objectName: "voiceMicCheckButton"
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: 32
                    radius: Theme.radiusSmall
                    color: Colors.surfaceContainerHigh
                    border.color: Theme.borderSubtle
                    border.width: 1
                    enabled: !root.voiceMicChecking

                    Text {
                        anchors.centerIn: parent
                        text: root.voiceMicChecking ? "Listening…" : "Test (3 s)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Colors.m3onSurface
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.runMicCheck()
                    }
                }
            }

            // Echo cancellation toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Echo Cancellation"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: "Legacy loopback filter, defaults off to prevent microphone distortion."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                Rectangle {
                    id: voiceEchoCancelToggle
                    objectName: "voiceEchoCancelToggle"
                    width: 44
                    height: 24
                    radius: 12
                    color: root.voiceEchoCancel ? Colors.primary : Colors.surfaceContainerHighest
                    border.color: root.voiceEchoCancel ? Colors.primary : Theme.borderSubtle
                    border.width: 1

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.voiceEchoCancel ? parent.width - width - 3 : 3
                        color: root.voiceEchoCancel ? Colors.m3onPrimary : Colors.m3onSurfaceVariant
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setVoiceEchoCancel(!root.voiceEchoCancel)
                    }
                }
            }

            // Noise suppression toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Noise Suppression"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: "Uses PipeWire rnnoise plugin filter when provisioned by system."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                Rectangle {
                    id: voiceNoiseSuppressToggle
                    objectName: "voiceNoiseSuppressToggle"
                    width: 44
                    height: 24
                    radius: 12
                    color: root.voiceNoiseSuppress ? Colors.primary : Colors.surfaceContainerHighest
                    border.color: root.voiceNoiseSuppress ? Colors.primary : Theme.borderSubtle
                    border.width: 1

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.voiceNoiseSuppress ? parent.width - width - 3 : 3
                        color: root.voiceNoiseSuppress ? Colors.m3onPrimary : Colors.m3onSurfaceVariant
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setVoiceNoiseSuppress(!root.voiceNoiseSuppress)
                    }
                }
            }
        }
    }

    // --- Card 4: Preferences -------------------------------------------------
    Rectangle {
        id: preferencesCard
        Layout.fillWidth: true
        radius: Theme.radiusMedium
        color: Colors.surfaceContainer
        border.color: Theme.borderSubtle
        border.width: 1
        implicitHeight: prefCol.implicitHeight + root.padLargeVal * 2
        Layout.preferredHeight: implicitHeight

        ColumnLayout {
            id: prefCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.padLargeVal
            spacing: Theme.spaceMedium

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSmall

                MaterialIcon {
                    text: "tune"
                    size: 20
                    color: Colors.primary
                }

                Text {
                    text: "Dictation Preferences"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontTitleSmall
                    font.weight: Font.DemiBold
                    color: Colors.m3onSurface
                }
            }

            // Stop automatically after a pause
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceMedium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Stop automatically after a pause"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodyMedium
                        color: Colors.m3onSurface
                    }

                    Text {
                        text: "Finishes after " + root.voiceSilenceHangoverMs + " ms of silence, or at " + root.voiceMaxUtteranceSeconds + " s cap."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurfaceVariant
                    }
                }

                Rectangle {
                    id: voiceAutoFinalizeToggle
                    objectName: "voiceAutoFinalizeToggle"
                    width: 44
                    height: 24
                    radius: 12
                    color: root.voiceAutoFinalize ? Colors.primary : Colors.surfaceContainerHighest
                    border.color: root.voiceAutoFinalize ? Colors.primary : Theme.borderSubtle
                    border.width: 1

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.voiceAutoFinalize ? parent.width - width - 3 : 3
                        color: root.voiceAutoFinalize ? Colors.m3onPrimary : Colors.m3onSurfaceVariant
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setVoiceAutoFinalize(!root.voiceAutoFinalize)
                    }
                }
            }
        }
    }
}
