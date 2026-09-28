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

    AiPage {
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
        assert(page.voiceModel === "ggml-small", "default model must be the CPU-interactive tier");
        assert(page.voiceLanguage === "auto", "default language must be auto-detect");
        assert(page.voiceAutoFinalize === true, "auto-finalize must default on");
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

        const langCodes = page.voiceLanguageOptions.map(l => l.code);
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
        // 5. Dropdowns are mutually exclusive
        // ------------------------------------------------------------------
        assert(page.modelMenuOpen === false, "no dropdown starts open");
        assert(page.languageMenuOpen === false, "no dropdown starts open");
        page.modelMenuOpen = true;
        assert(page.languageMenuOpen === false, "only one dropdown may be open at a time");
        page.testVoiceStatus = testRoot.readyStatus();

        // ------------------------------------------------------------------
        // 6. Source contracts
        // ------------------------------------------------------------------
        const pageSrc = readLocalFile("../settings_gui/pages/AiPage.qml");
        assert(/Voice Input/.test(pageSrc), "the AI page must contain a Voice Input section");
        assert(/property bool voiceEnabled/.test(pageSrc), "AiPage must expose voiceEnabled");
        assert(/Config\.setVoiceModel\(/.test(pageSrc), "AiPage must persist the model choice");
        assert(/Config\.setVoiceLanguage\(/.test(pageSrc), "AiPage must persist the language choice");
        assert(/Config\.setVoiceAutoFinalize\(/.test(pageSrc), "AiPage must persist auto-finalize");
        assert(/installVoiceModel\(/.test(pageSrc), "AiPage must trigger the explicit download");
        // Voice belongs to the assistant, so it lives in the AI page rather
        // than a new page of its own (AGENTS.md 6).
        assert(!/ComboBox/.test(pageSrc), "QtQuick.Controls is not imported in this shell; do not use ComboBox");

        // NexusHub loads pages through a Loader, so the page is constructed
        // already visible: `visible` never *changes* on first show and
        // onVisibleChanged never fires. A status cached when the shell started
        // (before whisper.cpp was installed) must therefore not survive the
        // page being opened - readiness is re-read on construction, and again
        // whenever the settings window is shown while the page stays loaded.
        const probeIdx = pageSrc.indexOf("Component.onCompleted");
        assert(probeIdx !== -1, "AiPage must re-probe voice readiness when it is constructed");
        const visibleIdx = pageSrc.indexOf("onVisibleChanged", probeIdx);
        assert(visibleIdx !== -1, "AiPage must keep its onVisibleChanged re-probe hook");
        const probeChunk = pageSrc.substring(probeIdx, visibleIdx);
        assert(/refreshVoiceReadiness\(\)/.test(probeChunk) || /refreshVoiceStatus\(\)/.test(probeChunk),
            "AiPage construction must probe voice readiness");
        assert(!/voiceStatus\s*===\s*null/.test(probeChunk),
            "the construction probe must run unconditionally: the page loads already-visible, "
            + "so onVisibleChanged cannot be the only first-show hook");
        assert(/onSettingsVisibleChanged/.test(pageSrc),
            "AiPage must re-probe when the settings window is shown again while the page stays instantiated");
        // No hardcoded model list: options must be data-driven.
        const hardcodedCatalog = /models_available:\s*\[/.test(pageSrc);
        assert(!hardcodedCatalog, "the model catalog must come from the daemon, not a hardcoded list");

        const shellSrc = readLocalFile("../shell.qml");
        assert(/function toggleVoice\(\)/.test(shellSrc), "shell.qml must expose a voice.toggle IPC action");
        assert(/function stopVoice\(\)/.test(shellSrc), "shell.qml must expose voice stop over IPC");

        const serviceSrc = readLocalFile("../services/AssistantService.qml");
        assert(/voiceModelInstallProgress/.test(serviceSrc), "AssistantService must track install progress");
        assert(/installVoiceModel/.test(serviceSrc), "AssistantService must expose installVoiceModel");

        console.log("PASS: tst_voice_settings");
        Qt.exit(0);
    }
}
