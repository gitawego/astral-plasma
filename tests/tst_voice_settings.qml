import QtQuick
import "../theme"
import "../components"
import "../config"
import "../settings_gui/pages"

/**
 * Settings surface for voice input.
 *
 * The page takes `testMode` seams, mirroring the existing pages, so the whole
 * panel is exercisable offscreen without a daemon, an engine or a model.
 */
Item {
    id: testRoot
    width: 900
    height: 1400

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    /** A complete status, as `voice status` would report on a working machine. */
    function readyStatus() {
        return {
            "enabled": true,
            "engine": "whisper-cpp",
            "engine_available": true,
            "engine_path": "/usr/bin/whisper-cli",
            "engine_version": "1.9.4",
            "model": "ggml-small",
            "model_present": true,
            "model_path": "/home/u/.cache/astral-plasma/models/ggml-small.bin",
            "model_size_bytes": 487601967,
            "vad_model_present": false,
            "language": "auto",
            "setup_complete": true,
            "gap": "ready",
            "models_available": [
                { "id": "ggml-tiny", "display_name": "Tiny", "size_bytes": 77691713, "size_label": "74 MiB" },
                { "id": "ggml-base", "display_name": "Base", "size_bytes": 147951465, "size_label": "141 MiB" },
                { "id": "ggml-small", "display_name": "Small (balanced, default)", "size_bytes": 487601967, "size_label": "465 MiB" }
            ],
            "languages": [
                { "code": "auto", "label": "Auto-detect" },
                { "code": "zh", "label": "中文 (Chinese)" },
                { "code": "en", "label": "English" },
                { "code": "fr", "label": "Français (French)" },
                { "code": "de", "label": "Deutsch (German)" },
                { "code": "it", "label": "Italiano (Italian)" },
                { "code": "es", "label": "Español (Spanish)" }
            ]
        };
    }

    VoicePage {
        id: page
        width: parent.width
        testMode: true
        testVoiceEnabled: true
        testVoiceStatus: testRoot.readyStatus()
    }

    function runTests() {
        console.log("Running tst_voice_settings.qml test suite...");

        // ------------------------------------------------------------------
        // 1. Defaults
        // ------------------------------------------------------------------
        assert(page.voiceEnabled === true, "voice must default to enabled");
        assert(page.voiceEngine === "whisper-cpp", "default engine must be whisper.cpp");
        page.setVoiceEngine("sherpa-onnx");
        assert(page.voiceEngine === "sherpa-onnx", "engine must switch to sherpa-onnx");
        assert(page.voiceModel === "sherpa-sensevoice-small", "switching to sherpa-onnx must update model default");
        page.setVoiceEngine("whisper-cpp");
        assert(page.voiceEngine === "whisper-cpp", "engine must restore to whisper-cpp");
        assert(page.voiceModel === "ggml-small", "restoring to whisper-cpp must restore model default");
        assert(page.voiceModel === "ggml-small", "default model must be the CPU-interactive tier");
        // Empty is "follow the system locale". The reported failure was English
        // speech transcribed as Japanese, which happened because `auto` was the
        // default and whisper's auto-detect is an ungated argmax. `auto` is now
        // something a user chooses, not something they inherit.
        assert(page.testVoiceLanguage === "", "the default language must be the system locale, not auto");
        assert(page.voiceAutoFinalize === true, "auto-finalize must default on");
        assert(page.voiceEchoCancel === false,
            "echo cancellation defaults off (audit §3.3): blind AEC distorts the mic");
        page.setVoiceEchoCancel(true);
        assert(page.voiceEchoCancel === true, "the echo-cancellation toggle must be writable");
        page.setVoiceEchoCancel(false);
        assert(page.voiceEchoCancel === false, "the toggle must restore");
        assert(page.voiceNoiseSuppress === false,
            "noise suppression defaults off: its node is operator-provisioned");
        page.setVoiceNoiseSuppress(true);
        assert(page.voiceNoiseSuppress === true, "the noise-suppression toggle must be writable");
        page.setVoiceNoiseSuppress(false);
        assert(page.voiceNoiseSuppress === false, "the toggle must restore");
        assert(page.voiceSilenceHangoverMs === 1200, "default hangover must match the daemon");
        assert(page.voiceMaxUtteranceSeconds === 30, "default cap must match the daemon");

        // ------------------------------------------------------------------
        // 2. Options are driven by the daemon's catalog, not hardcoded (D1)
        // ------------------------------------------------------------------
        assert(page.voiceModelOptions.length === 3,
            "model options must come from the daemon catalog, got: " + page.voiceModelOptions.length);
        assert(page.voiceModelOptions[0].id === "ggml-tiny", "model options must preserve catalog order");
        assert(page.voiceModelOptions[0].label.indexOf("74 MiB") !== -1,
            "model options must carry the human-readable size, got: " + page.voiceModelOptions[0].label);

        // "System default" must be the first entry: it is the shipped default,
        // and a picker whose first row is "Auto-detect" is inviting the failure
        // above back.
        const codes = page.voiceLanguageOptions.map(l => l.code);
        assert(codes[0] === "",
            "the first language option must be the system default, got: " + codes[0]);
        assert(page.voiceLanguageOptions[0].label.indexOf("System default") === 0,
            "the system default must be labelled, not left blank: a blank control "
                + "reads as a bug rather than a default, got: " + page.voiceLanguageOptions[0].label);
        const langCodes = codes;
        for (const required of ["auto", "zh", "en", "fr", "de", "it", "es"]) {
            assert(langCodes.indexOf(required) !== -1,
                "the language picker must offer " + required + ", got: " + langCodes.join(","));
        }
        assert(page.voiceModelSizeLabel === "465 MiB",
            "the selected model's size must resolve, got: " + page.voiceModelSizeLabel);

        // ------------------------------------------------------------------
        // 3. Readiness derivation
        // ------------------------------------------------------------------
        assert(page.voiceEngineAvailable === true, "engine availability must be read from status");
        assert(page.voiceModelPresent === true, "model presence must be read from status");
        assert(page.voiceReady === true, "a complete status must be ready");
        assert(page.voiceStatusSummary === "Ready · ggml-small",
            "the summary must be specific, got: " + page.voiceStatusSummary);

        // Missing engine
        const s = testRoot.readyStatus();
        s.engine_available = false;
        s.model_present = false;
        s.setup_complete = false;
        s.gap = "engine_missing";
        page.testVoiceStatus = s;
        assert(page.voiceEngineAvailable === false, "a missing engine must be detected");
        assert(page.voiceStatusSummary === "whisper.cpp engine not installed",
            "a missing engine must be named, got: " + page.voiceStatusSummary);

        // Engine present, model missing -- must not claim readiness
        const s2 = testRoot.readyStatus();
        s2.model_present = false;
        s2.setup_complete = false;
        s2.gap = "model_missing";
        page.testVoiceStatus = s2;
        assert(page.voiceModelPresent === false, "a missing model must be detected");
        assert(page.voiceReady === false, "a missing model must not report ready");
        assert(page.voiceStatusSummary === "Model ggml-small is not downloaded yet",
            "a missing model must be named, got: " + page.voiceStatusSummary);

        // No microphone
        const s3 = testRoot.readyStatus();
        s3.setup_complete = false;
        s3.gap = "no_audio_source";
        page.testVoiceStatus = s3;
        assert(page.voiceReady === false, "no microphone must not report ready");
        assert(page.voiceStatusSummary === "No microphone available",
            "a missing microphone must be named, got: " + page.voiceStatusSummary);

        // Disabled feature
        page.testVoiceStatus = testRoot.readyStatus();
        page.testVoiceEnabled = false;
        assert(page.voiceStatusSummary === "Voice dictation is disabled",
            "a disabled feature must say so, got: " + page.voiceStatusSummary);
        page.testVoiceEnabled = true;

        // No status yet -- must not claim readiness or crash
        page.testVoiceStatus = null;
        assert(page.voiceReady === false, "an unknown status must not report ready");
        assert(page.voiceStatusSummary === "Checking speech engine…",
            "an unknown status must say it is still checking, got: " + page.voiceStatusSummary);
        // With no status there is nothing to pick from; a sane fallback must exist.
        assert(page.voiceModelOptions.length >= 1, "model options must never be empty");
        assert(page.voiceLanguageOptions.length >= 1, "language options must never be empty");
        page.testVoiceStatus = testRoot.readyStatus();

        // ------------------------------------------------------------------
        // 4. Download button state follows model presence (D7: never silent)
        // ------------------------------------------------------------------
        const noModel = testRoot.readyStatus();
        noModel.model_present = false;
        noModel.setup_complete = false;
        page.testVoiceStatus = noModel;
        page.testVoiceModelInstalling = false;
        page.testVoiceModelInstallProgress = 0.0;
        assert(page.voiceModelInstalling === false, "no download may run unless requested");
        assert(page.voiceModelInstallProgress === 0.0, "progress must start at zero, never faked");

        page.testVoiceModelInstalling = true;
        page.testVoiceModelInstallProgress = 0.42;
        assert(Math.abs(page.voiceModelInstallProgress - 0.42) < 1e-6,
            "download progress must be reported, not animated");
        page.testVoiceModelInstalling = false;
        page.testVoiceModelInstallProgress = 0.0;
        page.testVoiceStatus = testRoot.readyStatus();

        // ------------------------------------------------------------------
        // 4b. VAD asset row follows the same explicit-install contract (D7)
        // ------------------------------------------------------------------
        page.testVoiceVadModelPresent = false;
        page.testVoiceVadInstalling = false;
        page.testVoiceVadInstallProgress = 0.0;
        assert(page.voiceVadModelPresent === false,
            "neural VAD must report absent until downloaded, never assumed");
        assert(page.voiceVadInstalling === false, "no VAD download may run unless requested");
        page.testVoiceVadInstalling = true;
        page.testVoiceVadInstallProgress = 0.5;
        assert(Math.abs(page.voiceVadInstallProgress - 0.5) < 1e-6,
            "VAD progress must be reported, not animated");
        page.testVoiceVadModelPresent = true;
        assert(page.voiceVadModelPresent === true, "a downloaded VAD asset must read as present");
        page.testVoiceVadInstalling = false;
        page.testVoiceVadInstallProgress = 0.0;
        page.testVoiceVadModelPresent = false;

        // ------------------------------------------------------------------
        // 4c. Device-only mic check: statistics, never audio
        // ------------------------------------------------------------------
        page.testVoiceMicCheckResult = null;
        page.testVoiceMicChecking = false;
        assert(page.voiceMicCheckSummary === "Not tested yet",
            "an unrun check must say so, not invent a result");
        page.testVoiceMicChecking = true;
        assert(page.voiceMicCheckSummary === "Listening… speak normally",
            "the check must ask for speech while listening");
        page.testVoiceMicChecking = false;
        page.testVoiceMicCheckResult = { "verdict": "ok", "peak_rms": 0.25 };
        assert(page.voiceMicCheckSummary === "OK · peak 25%",
            "an ok check must report the peak: " + page.voiceMicCheckSummary);
        page.testVoiceMicCheckResult = { "verdict": "clipping", "peak_rms": 0.99 };
        assert(page.voiceMicCheckSummary.indexOf("Clipping") === 0,
            "saturation must be named: " + page.voiceMicCheckSummary);
        page.testVoiceMicCheckResult = { "verdict": "silent", "peak_rms": 0.0 };
        assert(page.voiceMicCheckSummary.indexOf("Silent") === 0,
            "silence must be named: " + page.voiceMicCheckSummary);
        page.testVoiceMicCheckResult = null;

        // ------------------------------------------------------------------
        // 5. Dropdowns are mutually exclusive
        // ------------------------------------------------------------------
        assert(page.modelMenuOpen === false, "no dropdown starts open");
        assert(page.languageMenuOpen === false, "no dropdown starts open");
        page.modelMenuOpen = true;
        assert(page.languageMenuOpen === false, "only one dropdown may be open at a time");
        page.testVoiceStatus = testRoot.readyStatus();

        // A downloaded model must be removable, and the control must only exist
        // while there is something to remove.
        assert(page.voiceModelRemoveItem !== undefined, "VoicePage must offer removing a downloaded model");
        page.testVoiceStatus = { engine_available: true, model_present: true, setup_complete: true, gap: "" };
        assert(page.voiceModelPresent === true, "the seam must drive model presence");
        assert(page.voiceModelRemoveItem.visible === true, "the remove control shows for a present model");
        page.testVoiceStatus = { engine_available: true, model_present: false, setup_complete: false, gap: "model_missing" };
        assert(page.voiceModelRemoveItem.visible === false, "no remove control without a model");
        page.testVoiceStatus = null;

        // The install one-liner must come from the daemon, which knows the
        // distribution. A hardcoded `pacman` line is a dead end everywhere else.
        page.testVoiceStatus = { engine_available: false, engine_install_command: "sudo dnf install whisper-cpp" };
        assert(page.voiceEngineNotice.indexOf("sudo dnf install whisper-cpp") >= 0,
            "the engine notice must show the command the daemon reported, got: " + page.voiceEngineNotice);
        page.testVoiceStatus = { engine_available: false, engine_install_command: "" };
        assert(page.voiceEngineNotice.indexOf("github.com/ggml-org/whisper.cpp") >= 0,
            "an unknown distribution must get the upstream build, got: " + page.voiceEngineNotice);
        page.testVoiceStatus = null;

        // ------------------------------------------------------------------
        // 5b. Cross-engine stale status isolation & engine notice accuracy
        // ------------------------------------------------------------------
        // Switching to Sherpa-ONNX while status still holds a previous Deepgram
        // report must not leak Deepgram's notice or status summary into the view.
        page.setVoiceEngine("sherpa-onnx");
        page.testVoiceStatus = {
            engine: "deepgram",
            engine_available: false,
            model_present: true,
            setup_complete: false,
            gap: "engine_missing"
        };
        assert(page.voiceStatusCurrent === false,
            "a status for deepgram must not be considered current when sherpa-onnx is selected");
        assert(page.voiceModelPresent === false,
            "deepgram's cloud model presence must not mark local sherpa-sensevoice-small as downloaded");
        assert(page.voiceEngineNotice.indexOf("Deepgram") === -1,
            "sherpa-onnx view must never display Deepgram notices, got: " + page.voiceEngineNotice);
        assert(page.voiceEngineNotice.indexOf("sherpa-onnx") !== -1,
            "sherpa-onnx view must display sherpa-onnx notices, got: " + page.voiceEngineNotice);
        assert(page.voiceStatusSummary === "Checking speech engine…",
            "stale cross-engine status must show checking rather than wrong engine summary, got: " + page.voiceStatusSummary);

        // When sherpa status arrives with missing engine:
        page.testVoiceStatus = {
            engine: "sherpa-onnx",
            engine_available: false,
            model: "sherpa-sensevoice-small",
            model_present: false,
            setup_complete: false,
            gap: "engine_missing",
            engine_install_command: "pip install sherpa-onnx"
        };
        assert(page.voiceStatusCurrent === true, "matching engine status must be current");
        assert(page.voiceEngineAvailable === false, "sherpa engine must be detected as missing");
        assert(page.voiceStatusSummary === "sherpa-onnx engine not installed",
            "missing sherpa engine must be named honestly, got: " + page.voiceStatusSummary);
        assert(page.voiceEngineNotice.indexOf("pip install sherpa-onnx") !== -1,
            "notice must display pip install command, got: " + page.voiceEngineNotice);

        // Switching to Deepgram:
        page.setVoiceEngine("deepgram");
        page.testVoiceStatus = {
            engine: "deepgram",
            engine_available: false,
            model_present: true,
            setup_complete: false,
            gap: "engine_missing"
        };
        assert(page.voiceStatusCurrent === true, "deepgram status must be current");
        assert(page.voiceStatusSummary === "Deepgram API key missing",
            "missing key must be reported, got: " + page.voiceStatusSummary);
        assert(page.voiceEngineNotice.indexOf("deepgram") !== -1 || page.voiceEngineNotice.indexOf("Deepgram") !== -1,
            "deepgram notice must name deepgram key, got: " + page.voiceEngineNotice);

        // Restore to whisper-cpp
        page.setVoiceEngine("whisper-cpp");
        page.testVoiceStatus = null;

        // ------------------------------------------------------------------
        // 6. Source contracts
        // ------------------------------------------------------------------
        const pageSrc = readLocalFile("../settings_gui/pages/VoicePage.qml");
        assert(/Speech Engine/.test(pageSrc) || /Voice Dictation/.test(pageSrc), "the Voice page must contain a Speech Engine section");
        assert(/property bool voiceEnabled/.test(pageSrc), "VoicePage must expose voiceEnabled");
        assert(/Config\.setVoiceModel\(/.test(pageSrc), "VoicePage must persist the model choice");
        assert(/Config\.setVoiceLanguage\(/.test(pageSrc), "VoicePage must persist the language choice");
        assert(/Config\.setVoiceAutoFinalize\(/.test(pageSrc), "VoicePage must persist auto-finalize");
        assert(/setVoiceEngine\(/.test(pageSrc), "VoicePage must support switching speech engine");
        assert(/voiceEngineSherpa/.test(pageSrc), "VoicePage must include sherpa-onnx engine option");
        assert(/installVoiceModel\(/.test(pageSrc), "VoicePage must trigger the explicit download");
        assert(/voiceVadInstallButton/.test(pageSrc),
            "VoicePage must offer the explicit VAD asset download beside the model row");
        assert(/installVoiceVadModel\(\)/.test(pageSrc),
            "VoicePage must trigger the VAD download through AssistantService");
        assert(/voiceMicCheckButton/.test(pageSrc),
            "VoicePage must offer the device-only microphone check");
        assert(/runMicCheck\(\)/.test(pageSrc),
            "VoicePage must trigger the mic check through AssistantService");
        assert(/voiceEchoCancelToggle/.test(pageSrc),
            "the voice section must render the echo-cancellation toggle");
        assert(/voiceNoiseSuppressToggle/.test(pageSrc),
            "the voice section must render the noise-suppression toggle");
        assert(/function setVoiceEchoCancel\(/.test(pageSrc),
            "VoicePage must persist the echo-cancellation choice");
        assert(/function setVoiceNoiseSuppress\(/.test(pageSrc),
            "VoicePage must persist the noise-suppression choice");
        // Voice belongs to the assistant, so it lives in the Voice page rather
        // than an un-themed dialog.
        assert(!/ComboBox/.test(pageSrc), "QtQuick.Controls is not imported in this shell; do not use ComboBox");

        // NexusHub loads pages through a Loader, so the page is constructed
        // already visible: `visible` never *changes* on first show and
        // onVisibleChanged never fires. A status cached when the shell started
        // (before whisper.cpp was installed) must therefore not survive the
        // page being opened - readiness is re-read on construction, and again
        // whenever the settings window is shown while the page stays loaded.
        const probeIdx = pageSrc.indexOf("Component.onCompleted");
        assert(probeIdx !== -1, "VoicePage must re-probe voice readiness when it is constructed");
        const visibleIdx = pageSrc.indexOf("onVisibleChanged", probeIdx);
        assert(visibleIdx !== -1, "VoicePage must keep its onVisibleChanged re-probe hook");
        const probeChunk = pageSrc.substring(probeIdx, visibleIdx);
        assert(/refreshVoiceReadiness\(\)/.test(probeChunk) || /refreshVoiceStatus\(\)/.test(probeChunk),
            "VoicePage construction must probe voice readiness");
        assert(!/voiceStatus\s*===\s*null/.test(probeChunk),
            "the construction probe must run unconditionally: the page loads already-visible, "
            + "so onVisibleChanged cannot be the only first-show hook");
        assert(/onSettingsVisibleChanged/.test(pageSrc),
            "VoicePage must re-probe when the settings window is shown again while the page stays instantiated");
        // No hardcoded model list: options must be data-driven.
        const hardcodedCatalog = /models_available:\s*\[/.test(pageSrc);
        assert(!hardcodedCatalog, "the model catalog must come from the daemon, not a hardcoded list");

        const configSrc = readLocalFile("../config/Config.qml");
        assert(/function setVoiceEngine\(engineId\)\s*\{\s*updateSettings\(/.test(configSrc),
            "Config.qml must use updateSettings for setVoiceEngine to ensure reactive binding updates");

        const shellSrc = readLocalFile("../shell.qml");
        assert(/function toggleVoice\(\)/.test(shellSrc), "shell.qml must expose a voice.toggle IPC action");
        assert(/function stopVoice\(\)/.test(shellSrc), "shell.qml must expose voice stop over IPC");

        const serviceSrc = readLocalFile("../services/AssistantService.qml");
        assert(/voiceModelInstallProgress/.test(serviceSrc), "AssistantService must track install progress");
        assert(/installVoiceModel/.test(serviceSrc), "AssistantService must expose installVoiceModel");
        assert(/installVoiceVadModel/.test(serviceSrc), "AssistantService must expose installVoiceVadModel");
        assert(/runMicCheck/.test(serviceSrc), "AssistantService must expose runMicCheck");
        assert(/voice", "install-vad-model"/.test(serviceSrc),
            "the VAD installer must drive the daemon's install-vad-model subcommand");

        console.log("PASS: tst_voice_settings");
        Qt.exit(0);
    }
}
