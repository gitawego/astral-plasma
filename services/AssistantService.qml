pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "PiUpdateMessage.js" as PiUpdateMessage
import "../services"

Singleton {
    id: root

    property var messages: [
        {
            "id": "welcome",
            "role": "assistant",
            "content": "Hello! I am your **Astral Plasma System Copilot**. I can help you inspect system logs, monitor and kill runaway processes, fix audio/display glitches, and optimize packages.\n\nType a question or pick a diagnostic action below to start.",
            "tool_calls": [],
            "isStreaming": false,
            "timestamp": Date.now()
        }
    ]

    property bool isStreaming: false
    onIsStreamingChanged: {
        if (typeof AiActivityService !== "undefined") {
            if (isStreaming) {
                AiActivityService.applyActivity({
                    agent: selectedHarness || "astral-copilot",
                    model: selectedModelId || "mimo-v2.6-flash",
                    display_name: selectedModelId || "Astral Copilot",
                    is_active: true,
                    intensity: 1.0,
                    rate: 1.0,
                    tokens: 1.0
                });
            } else {
                AiActivityService.applyActivity({
                    agent: selectedHarness || "astral-copilot",
                    model: selectedModelId || "mimo-v2.6-flash",
                    display_name: selectedModelId || "Astral Copilot",
                    is_active: false,
                    intensity: 0.0,
                    rate: 0.0,
                    tokens: 0.0
                });
            }
        }
    }
    property string activeStreamingContent: ""
    property var activeToolProposals: []
    property int messagesRevision: 0
    property var sessions: []
    property string activeSessionId: ""
    property string activeSessionTitle: "New Chat"
    property string selectedHarness: (typeof Config !== "undefined" && Config.assistantHarness) ? Config.assistantHarness : "pi"
    property string selectedProviderId: (typeof Config !== "undefined" && Config.assistantDefaultProvider) ? Config.assistantDefaultProvider : "opencode-go"
    property string selectedModelId: (typeof Config !== "undefined" && Config.assistantDefaultModel) ? Config.assistantDefaultModel : "mimo-v2.6-flash"
    property var availableProviders: [
        { "id": "opencode-go", "name": "OpenCode Go", "models": ["mimo-v2.6-flash", "mimo-v2.6-pro", "deepseek-v4-flash", "qwen3.8-flash"] },
        { "id": "gemini", "name": "Google Gemini", "models": ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"] },
        { "id": "claude", "name": "Anthropic Claude", "models": ["claude-3-7-sonnet", "claude-3-5-sonnet", "claude-3-5-haiku"] },
        { "id": "deepseek", "name": "DeepSeek", "models": ["deepseek-chat", "deepseek-reasoner"] },
        { "id": "openai", "name": "OpenAI", "models": ["gpt-4o", "gpt-4o-mini", "o3-mini"] },
        { "id": "minimax-cn", "name": "MiniMax CN", "models": ["MiniMax-M2.7", "MiniMax-M3"] },
        { "id": "ollama", "name": "Local Ollama", "models": ["llama3.2", "mistral", "deepseek-r1"] }
    ]
    // Fallback shown until the daemon reports: the harness version is *probed*
    // there (`pi --version`), so this list must never carry one - a hardcoded
    // version lies about the user's installation the moment pi is upgraded.
    property var availableHarnesses: [
        { "id": "pi", "name": "Pi Agent", "is_available": true, "version": "", "is_default": true },
        { "id": "hermes", "name": "Hermes Agent", "is_available": false, "version": null, "is_default": false }
    ]
    property var discoveredSkills: []
    property var recentCrashes: []
    property var dismissedCrashIds: []
    property int crashesRevision: 0

    // -----------------------------------------------------------------------
    // Voice input
    //
    // Transport is a one-shot `voice session` child process: control lines go
    // down stdin, VoiceEvent JSONL comes up stdout, and the process exits when
    // the utterance finalises -- which is what releases the microphone. See
    // docs/VOICE-INPUT-SPEC.md D3.
    //
    // A dictation transcript is NEVER auto-sent. It is appended to the composer
    // for review, because a recognition error must not be able to reach a tool
    // execution gate unattended (D5).
    // -----------------------------------------------------------------------

    /** "idle" | "recording" | "finalizing" | "failed" -- mirrors VoiceState. */
    property string voiceState: "idle"
    /** Measured audio level in [0.0, 1.0], straight from the capture stream. */
    property real voiceLevel: 0.0
    /** Real elapsed capture time in ms, driven by a local timer. */
    property int voiceElapsedMs: 0
    /** Engine-reported language tag, or "und" when undetermined. */
    property string voiceLanguage: ""
    /** Live partial text, only ever set from a real Partial event. */
    property string voicePartialText: ""
    /** The most recent finalized transcript, awaiting insertion into the composer. */
    property string voiceTranscript: ""
    /**
     * Why a session that ran produced no text, or "" when the last one did.
     *
     * This exists because the empty case used to be invisible. `voiceTranscript`
     * was already `""` when a `Final` carried no words, so assigning it emitted
     * no change signal, the composer's `onVoiceTranscriptChanged` never ran,
     * and the user was left with a microphone that visibly worked and a
     * composer that silently did not. An honest outcome still has to be said
     * out loud.
     */
    property string voiceEmptyNotice: ""
    /** Whether the last session's capture contained speech, as the engine saw it. */
    property bool voiceSpeechDetected: true
    /**
     * The language the in-flight session settled on, reported before the
     * transcript. Empty when the language is pinned rather than detected, in
     * which case there is nothing to show and nothing to override.
     */
    property string voiceDetectedLanguage: ""
    /**
     * The engine's own probability for `voiceDetectedLanguage`, or -1 when it
     * gave none.
     *
     * Carried through rather than collapsed into a boolean so the UI can say
     * *how* sure it was. A detection at 0.9 and one at 0.11 are both "the engine
     * guessed", and the second is the one worth overriding.
     */
    property real voiceLanguageConfidence: -1
    /**
     * A session-scoped language override, or "" for the configured default.
     *
     * Passed to `voice session --lang` and never persisted (D9): dictating in a
     * second language for one prompt must not reconfigure the shell. This
     * property used to exist with no reader and no writer, and a test asserted
     * only that the declaration was there.
     */
    property string voiceLanguageOverride: ""
    /** Model download progress in [0.0, 1.0], and whether a download is running. */
    property real voiceModelInstallProgress: 0.0
    property bool voiceModelInstalling: false
    /** Silero VAD asset download progress in [0.0, 1.0], and whether it runs. */
    property real voiceVadInstallProgress: 0.0
    property bool voiceVadInstalling: false
    /** Latest device-only mic-check report, or null when never run. */
    property var voiceMicCheckResult: null
    property bool voiceMicChecking: false
    /** A setup gap the user can fix, shown inline beside the mic button. */
    property string voiceSetupMessage: ""
    /**
     * Non-fatal session warning (e.g. input clipping). Never fails the session;
     * shown in the listening strip while recording continues.
     */
    property string voiceWarning: ""
    /** Readiness from `voice status`; null until probed. */
    property var voiceStatus: null
    /**
     * True between spawning the session process and successfully sending
     * `start`. Cleared as soon as the command is written, and reset on exit so a
     * relaunch always re-arms the handshake.
     */
    property bool voiceAwaitingStart: false
    /**
     * The setup gap the user has explicitly dismissed.
     *
     * Recorded rather than simply cleared, so the notice does not reappear on
     * the next `refreshVoiceStatus()` (which runs every time the drawer opens).
     * A *different* gap still surfaces, because that is new information the user
     * has not seen yet.
     */
    property string voiceDismissedGap: ""

    readonly property bool isVoiceRecording: voiceState === "recording"
    readonly property bool isVoiceBusy: voiceState === "recording" || voiceState === "finalizing"
    readonly property bool voiceEnabled: (typeof Config !== "undefined") ? !!Config.voiceEnabled : true
    /** Single source of truth for the mic button, so it cannot disagree with diagnostics. */
    readonly property bool voiceReady: voiceStatus !== null && voiceStatus.setup_complete === true
    readonly property bool voiceMicUsable: voiceEnabled && voiceReady && !isVoiceBusy

    readonly property var activeCrashes: {
        let rev = crashesRevision;
        if (!recentCrashes || !Array.isArray(recentCrashes)) return [];
        let dismissed = dismissedCrashIds || [];
        let filtered = recentCrashes.filter(function(c) {
            return c && c.id && dismissed.indexOf(c.id) === -1;
        });

        let deduped = [];
        let seen = {};
        for (let i = 0; i < filtered.length; i++) {
            let c = filtered[i];
            let key = (c.process_name && c.process_name !== "system") ? c.process_name : (c.summary || c.id);
            if (seen[key] !== undefined) {
                let existing = deduped[seen[key]];
                existing.count = (existing.count || 1) + (c.count || 1);
                continue;
            }
            let copy = Object.assign({}, c);
            if (!copy.count) copy.count = 1;
            seen[key] = deduped.length;
            deduped.push(copy);
        }
        return deduped;
    }

    function dismissCrash(crashId) {
        if (!crashId) return;
        let list = (dismissedCrashIds || []).slice();
        if (list.indexOf(crashId) === -1) {
            list.push(crashId);
        }
        // Also dismiss all other crashes with the same process_name
        let targetProcess = "";
        for (let i = 0; i < recentCrashes.length; i++) {
            if (recentCrashes[i] && recentCrashes[i].id === crashId) {
                targetProcess = recentCrashes[i].process_name;
                break;
            }
        }
        if (targetProcess && targetProcess !== "system") {
            for (let i = 0; i < recentCrashes.length; i++) {
                let c = recentCrashes[i];
                if (c && c.id && c.process_name === targetProcess) {
                    if (list.indexOf(c.id) === -1) {
                        list.push(c.id);
                    }
                }
            }
        }
        dismissedCrashIds = list;
        crashesRevision++;
    }

    function dismissAllCrashes() {
        if (!recentCrashes || recentCrashes.length === 0) return;
        let list = (dismissedCrashIds || []).slice();
        for (let i = 0; i < recentCrashes.length; i++) {
            let id = recentCrashes[i].id;
            if (id && list.indexOf(id) === -1) {
                list.push(id);
            }
        }
        dismissedCrashIds = list;
        crashesRevision++;
    }

    property var unnotifiedCrashes: []

    function getModelsForProvider(providerId) {
        if (!providerId) return [];
        for (let i = 0; i < availableProviders.length; i++) {
            if (availableProviders[i].id === providerId) {
                return availableProviders[i].models || [];
            }
        }
        return [];
    }

    function getProviderDisplayName(providerId) {
        if (!providerId) return "Default Provider";
        for (let i = 0; i < availableProviders.length; i++) {
            if (availableProviders[i].id === providerId) {
                return availableProviders[i].name || providerId;
            }
        }
        return providerId.toUpperCase();
    }

    function selectProvider(providerId) {
        if (!providerId) return;
        selectedProviderId = providerId;
        if (typeof Config !== "undefined") {
            Config.assistantDefaultProvider = providerId;
        }
        let models = getModelsForProvider(providerId);
        if (models.length > 0) {
            // Keep current model if valid for this provider, else switch to first
            if (models.indexOf(selectedModelId) === -1) {
                selectModel(models[0]);
            } else {
                selectModel(selectedModelId);
            }
        }
    }

    function selectModel(modelId) {
        if (!modelId) return;
        selectedModelId = modelId;
        if (typeof Config !== "undefined") {
            Config.assistantDefaultModel = modelId;
        }
        if (selectedProviderId) {
            runProc(setModelProc, [daemonBin, "assistant", "set-model", selectedProviderId, modelId]);
        }
    }

    readonly property string daemonBin: {
        if (typeof Config !== "undefined" && Config.daemonBin) return Config.daemonBin;
        return Qt.resolvedUrl("../bin/astral-plasma").toString().replace("file://", "");
    }

    Component.onCompleted: {
        refreshStatus();
        refreshSkills();
        refreshCrashes();
        loadActiveSession();
        refreshSessions();
        refreshVoiceStatus();
    }

    // Pure decoders for the session's JSONL events. The payload shapes are
    // typed (`Level` is `{"rms": x}`, `Partial` is `{"text": s}`), and
    // reading them as bare values is silently wrong in JavaScript.
    VoiceEventCodec {
        id: voiceEventCodec
    }

    // -----------------------------------------------------------------------
    // Voice input: use cases
    // -----------------------------------------------------------------------

    /**
     * Maps a setup gap to a specific, actionable message.
     *
     * A generic "voice unavailable" would leave the user with nothing to do, so
     * each gap names the actual missing piece. The way *out* is deliberately not
     * part of the sentence: the composer's notice renders the destination as its
     * own chip, so a message ending in "— Settings › AI › Voice input" would
     * only duplicate it.
     */
    function describeVoiceGap(status) {
        if (!status || status.setup_complete === true) return "";
        switch (status.gap) {
        case "engine_missing":
            // Name the *engine*: the model can be downloaded while the engine is
            // still missing, and "whisper.cpp is not installed" read as if the
            // speech model were the problem.
            return "whisper.cpp engine not installed";
        case "model_missing":
            return "Speech model " + (status.model || "") + " is not downloaded";
        case "no_audio_source":
            return "No microphone found — check your audio input device";
        default:
            return "Voice input is unavailable";
        }
    }

    /**
     * Dismisses the current setup notice.
     *
     * A permanent, non-dismissible notice is a wall rather than a pointer: the
     * user cannot get it out of the way, so they learn to ignore the composer.
     * Dismissal is scoped to the specific gap so a *new* problem still surfaces.
     */
    function dismissVoiceSetupNotice() {
        root.voiceDismissedGap = (root.voiceStatus && root.voiceStatus.gap) ? root.voiceStatus.gap : "";
        root.voiceSetupMessage = "";
    }

    /**
     * Re-surfaces the setup notice, undoing a dismissal.
     *
     * This is what the mic button does when voice is not set up. The notice is
     * dismissed per-gap, so a user who closed it once would otherwise click the
     * mic and get no explanation at all -- which is indistinguishable from a
     * broken button. Clicking the control is an explicit request to be told
     * again, so the answer belongs right where they clicked: the strip names the
     * missing piece and is itself a link into the page that installs it.
     */
    function showVoiceSetupNotice() {
        root.voiceDismissedGap = "";
        root.voiceSetupMessage = root.describeVoiceGap(root.voiceStatus);
    }

    /** Whether the current gap has already been dismissed by the user. */
    readonly property bool voiceSetupDismissed: voiceDismissedGap !== ""
        && voiceStatus !== null
        && voiceStatus.gap === voiceDismissedGap

    /**
     * A mic click, routed by state.
     *
     * Ready    -> toggle recording.
     * Not ready -> say what is missing, in the composer. Never a no-op, and
     * never a navigation: a shortcut or a click must first *answer*, because a
     * jump to another page hides the explanation behind a page change the user
     * did not ask for. The notice it raises is itself the link into Settings.
     */
    function toggleVoiceInput() {
        // `isVoiceRecording` is the declared name. The unqualified
        // `voiceRecording` never existed, so this threw a ReferenceError and the
        // whole function -- including the not-ready branch below -- never ran.
        if (isVoiceRecording) {
            stopVoiceInput();
            return;
        }
        if (voiceMicUsable) {
            startVoiceInput();
            return;
        }
        showVoiceSetupNotice();
    }

    /**
     * Cancels a one-shot daemon probe so a fresh one can start immediately.
     *
     * `Quickshell.Io.Process` has no `terminate()`; clearing `running` is how a
     * process is stopped. Calling the missing method threw a TypeError that
     * aborted the caller, so a restart while a probe was in flight silently did
     * nothing at all -- the status never updated and the gap went stale.
     *
     * `discardOutput` is marked because a stopped process still finishes its
     * output stream, and that stream is truncated mid-line. Parsing it would
     * either throw a spurious parse error or, worse, apply a half-written
     * payload.
     *
     * The two collector kinds need different guards, and conflating them breaks
     * the feature. A `SplitParser` emits chunks *while the process is still
     * running*, so `running` is the normal case there and must not be tested --
     * doing so silently discarded every event the status probe and the chat
     * stream produced, and voice looked permanently unconfigured. A
     * `StdioCollector` emits once at the end, so it additionally tests `running`:
     * cancelling without restarting leaves `running` false, and restarting re-arms
     * the flag immediately, so only `running` catches the superseded case.
     */
    function cancelProc(proc) {
        if (proc.running) {
            proc.discardOutput = true;
            proc.running = false;
        }
    }

    /** Arms a probe: its output is meaningful again from here on. */
    function runProc(proc, command) {
        proc.discardOutput = false;
        proc.command = command;
        proc.running = true;
    }

    /** Probes engine and model readiness. Cheap; safe to call often. */
    function refreshVoiceStatus() {
        cancelProc(voiceStatusProc);
        runProc(voiceStatusProc, [daemonBin, "voice", "status"]);
    }

    /** Downloads a speech model, reporting progress through voiceInstallProgress. */
    function installVoiceModel(modelId) {
        cancelProc(voiceInstallProc);
        voiceModelInstallProgress = 0.0;
        voiceModelInstalling = true;
        const id = modelId || (voiceStatus ? voiceStatus.model : "");
        if (!id) {
            voiceModelInstalling = false;
            return;
        }
        runProc(voiceInstallProc, [daemonBin, "voice", "install-model", id]);
    }

    /** Deletes a downloaded model so the row can go back to offering a download. */
    function removeVoiceModel(modelId) {
        if (voiceInstallProc.running) return;
        const id = modelId || (voiceStatus ? voiceStatus.model : "");
        if (!id) return;
        runProc(voiceRemoveProc, [daemonBin, "voice", "remove-model", id]);
    }

    /** Downloads the Silero VAD asset; absence only costs accuracy, never readiness. */
    function installVoiceVadModel() {
        cancelProc(voiceVadInstallProc);
        voiceVadInstallProgress = 0.0;
        voiceVadInstalling = true;
        runProc(voiceVadInstallProc, [daemonBin, "voice", "install-vad-model"]);
    }

    /** Runs the 3-second device-only microphone check; audio never leaves the device. */
    function runMicCheck() {
        cancelProc(voiceMicCheckProc);
        voiceMicChecking = true;
        runProc(voiceMicCheckProc, [daemonBin, "voice", "mic-check", "--secs", "3"]);
    }

    /** Starts capture. No-op unless the engine and model are both present. */
    function startVoiceInput() {
        if (!voiceMicUsable) return;
        if (voiceSessionProc.running) return;

        voiceState = "recording";
        voiceLevel = 0.0;
        voiceElapsedMs = 0;
        voiceLanguage = "";
        voiceDetectedLanguage = "";
        voiceLanguageConfidence = -1;
        voicePartialText = "";
        voiceSetupMessage = "";
        voiceWarning = "";
        voiceTranscript = "";
        // A stale notice from the previous session must not survive into this
        // one, or it would greet the user the moment they clicked the mic.
        voiceEmptyNotice = "";
        voiceAwaitingStart = true;
        voiceElapsedTimer.restart();

        // The override is per-session (D9): it is read here, passed once, and
        // never written back to settings. Passing it as an argument rather than
        // mutating the settings block is what keeps that guarantee structural.
        const command = root.voiceLanguageOverride.trim().length > 0
            ? [daemonBin, "voice", "session", "--lang", root.voiceLanguageOverride.trim()]
            : [daemonBin, "voice", "session"];
        runProc(voiceSessionProc, command);
        // The daemon deliberately waits for an explicit `start` before opening
        // the microphone, so spawning the process is not enough -- the pipe does
        // not exist yet. The `voiceAwaitingStart` handshake inside the Process
        // below sends the command as soon as it can actually be written.
    }

    /** Finalizes capture and transcribes. */
    function stopVoiceInput() {
        if (voiceSessionProc.running) {
            voiceSessionProc.write("stop\n");
        }
    }

    /**
     * Sets a session-scoped language override, or clears it.
     *
     * Applies to sessions started from now on and is deliberately not
     * persisted: a user who dictates one prompt in another language has not
     * reconfigured their shell (D9). The persisted default lives in
     * `voice.language` in `settings.json`, changed through Settings.
     */
    function setVoiceLanguageOverride(language) {
        voiceLanguageOverride = language ? String(language).trim() : "";
    }

    /** Clears the session-scoped override and returns to the configured default. */
    function clearVoiceLanguageOverride() {
        voiceLanguageOverride = "";
    }

    /**
     * Clears an empty-outcome notice.
     *
     * Not remembered, unlike the setup-gap dismissal: an empty outcome is a fact
     * about one finished recording, so it is stale the moment the next one
     * starts. Persisting it would reopen a complaint the user already answered.
     */
    function dismissVoiceEmptyNotice() {
        voiceEmptyNotice = "";
    }

    /** Aborts capture, discarding audio without transcribing. */
    function cancelVoiceInput() {        if (voiceSessionProc.running) {
            voiceSessionProc.write("cancel\n");
        }
        voiceState = "idle";
        voiceElapsedTimer.stop();
    }

    /**
     * Appends a finalized transcript to the composer.
     *
     * Returns the merged text so the caller can assign it. The caller is
     * responsible for keeping focus in the field; this never submits.
     */
    function appendVoiceTranscript(existing, addition) {
        const extra = (addition || "").trim();
        if (extra.length === 0) return existing;
        const base = existing ? existing.replace(/\s+$/, "") : "";
        if (base.length === 0) return extra;
        return /\n$/.test(existing) ? (base + "\n" + extra) : (base + " " + extra);
    }

    function loadActiveSession() {
        cancelProc(activeSessionProc);
        runProc(activeSessionProc, [daemonBin, "assistant", "active-session"]);
    }

    function refreshSessions() {
        cancelProc(loadSessionsProc);
        runProc(loadSessionsProc, [daemonBin, "assistant", "sessions"]);
    }

    function loadSession(id) {
        if (!id) return;
        // Idempotent per id. At startup the active-session probe and the
        // sessions list independently decide to load the same session, and they
        // share one process slot: the second call supersedes the first mid-flight,
        // the superseded stream is dropped, and the run that replaces it can
        // finish with no output at all -- so the chat history silently failed to
        // load. Re-requesting the session already being fetched is a no-op.
        if (getSessionProc.running && getSessionProc.targetId === id) return;
        cancelProc(getSessionProc);
        getSessionProc.targetId = id;
        runProc(getSessionProc, [daemonBin, "assistant", "get-session", id]);
    }

    function createNewSession() {
        if (isStreaming) {
            stopStreaming();
        }
        let newId = "session_" + Date.now();
        activeSessionId = newId;
        activeSessionTitle = "New Chat";
        messages = [
            {
                "id": "welcome_" + Date.now(),
                "role": "assistant",
                "content": "Hello! I am your **Astral Plasma System Copilot**. I can help you inspect system logs, monitor and kill runaway processes, fix audio/display glitches, and optimize packages.\n\nType a question or pick a diagnostic action below to start.",
                "tool_calls": [],
                "images": [],
                "files": [],
                "isStreaming": false,
                "timestamp": Date.now()
            }
        ];
        messagesRevision++;
        persistActiveSession();
    }

    function deleteSession(id) {
        if (!id) return;
        cancelProc(deleteSessionProc);
        runProc(deleteSessionProc, [daemonBin, "assistant", "delete-session", id]);

        let filtered = sessions.filter(function(s) { return s.id !== id; });
        sessions = filtered;

        if (activeSessionId === id) {
            if (sessions.length > 0) {
                loadSession(sessions[0].id);
            } else {
                createNewSession();
            }
        }
    }

    function persistActiveSession() {
        if (!activeSessionId) {
            activeSessionId = "session_" + Date.now();
        }

        // Derive title from first user prompt if still default
        let derivedTitle = activeSessionTitle;
        if (!derivedTitle || derivedTitle === "New Chat" || derivedTitle.trim().length === 0) {
            for (let i = 0; i < messages.length; i++) {
                if (messages[i].role === "user" && messages[i].content) {
                    let firstLine = messages[i].content.trim().split("\n")[0];
                    if (firstLine.length > 36) {
                        derivedTitle = firstLine.substring(0, 36) + "...";
                    } else {
                        derivedTitle = firstLine;
                    }
                    activeSessionTitle = derivedTitle;
                    break;
                }
            }
        }

        let sessionObj = {
            "id": activeSessionId,
            "title": derivedTitle || "New Chat",
            "created_at": Date.now(),
            "updated_at": Date.now(),
            "provider": selectedProviderId,
            "model": selectedModelId,
            "harness": selectedHarness,
            "messages": messages
        };

        let jsonPayload = JSON.stringify(sessionObj);
        cancelProc(saveSessionProc);
        runProc(saveSessionProc, [daemonBin, "assistant", "save-session", jsonPayload]);
    }

    function clearChat() {
        if (isStreaming) {
            stopStreaming();
        }
        messages = [
            {
                "id": "welcome_" + Date.now(),
                "role": "assistant",
                "content": "Chat cleared. What can I help you inspect or configure?",
                "tool_calls": [],
                "images": [],
                "files": [],
                "isStreaming": false,
                "timestamp": Date.now()
            }
        ];
        messagesRevision++;
        persistActiveSession();
    }

    function stopStreaming() {
        streamWatchdog.stop();
        cancelProc(streamProc);
        finalizeAssistantTurn();
    }

    function sendMessage(promptText, attachedImages) {
        if (!promptText || promptText.trim().length === 0) return;

        // If a previous stream is still marked active, safely preempt it
        if (isStreaming) {
            stopStreaming();
        }

        let trimmed = promptText.trim();
        let imagesList = (attachedImages && attachedImages.length > 0) ? attachedImages.slice() : [];

        let userMsg = {
            "id": "user_" + Date.now(),
            "role": "user",
            "content": trimmed,
            "images": imagesList,
            "tool_calls": [],
            "isStreaming": false,
            "timestamp": Date.now()
        };

        let currentList = messages.slice();
        currentList.push(userMsg);

        // Add assistant placeholder
        let assistantMsgId = "asst_" + Date.now();
        let assistantMsg = {
            "id": assistantMsgId,
            "role": "assistant",
            "content": "",
            "tool_calls": [],
            "isStreaming": true,
            "timestamp": Date.now()
        };
        currentList.push(assistantMsg);
        messages = currentList;
        messagesRevision++;
        persistActiveSession();

        isStreaming = true;
        activeStreamingContent = "";
        activeToolProposals = [];
        streamWatchdog.restart();

        // If images attached, pass @<path> for multimodal processing by Pi
        let effectivePrompt = trimmed;
        for (let i = 0; i < imagesList.length; i++) {
            let imgP = String(imagesList[i]).startsWith("file://") ? String(imagesList[i]).substring(7) : String(imagesList[i]);
            if (!effectivePrompt.includes("@" + imgP)) {
                effectivePrompt += " @" + imgP;
            }
        }

        // Build CLI args
        let args = ["assistant", "chat", "--prompt", effectivePrompt];
        if (selectedHarness) {
            args.push("--harness");
            args.push(selectedHarness);
        }
        if (selectedProviderId) {
            args.push("--provider");
            args.push(selectedProviderId);
        }
        if (selectedModelId) {
            args.push("--model");
            args.push(selectedModelId);
        }

        runProc(streamProc, [daemonBin].concat(args));
    }

    function diagnoseCrash(crashItem) {
        if (!crashItem) return;
        Config.openAssistant();
        let prompt = "Diagnose this crash: Application '" + crashItem.process_name +
                     "' terminated with signal " + (crashItem.signal || "unknown") +
                     ". Recent log: " + (crashItem.summary || crashItem.log_snippet || "");
        if (crashItem.id) {
            dismissCrash(crashItem.id);
        }
        sendMessage(prompt);
    }

    function approveToolCall(toolCall) {
        if (!toolCall || !toolCall.command) return;

        // Remove from active proposals
        let filtered = activeToolProposals.filter(function(tc) { return tc.id !== toolCall.id; });
        activeToolProposals = filtered;

        // Execute command via daemon
        let execArgs = [daemonBin, "assistant", "exec", toolCall.command];
        if (toolCall.requires_sudo) {
            execArgs.push("--sudo");
        }

        pendingToolCall = toolCall;
        runProc(toolExecProc, execArgs);
    }

    property var pendingToolCall: null

    Process {
        id: toolExecProc
        property bool discardOutput: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let res = JSON.parse(this.text.trim());
                    let cmd = root.pendingToolCall ? root.pendingToolCall.command : "command";
                    let outputText = "Command executed (`" + cmd + "`):\n```\n" + (res.stdout || res.stderr || "No output") + "\n```";
                    let currentList = root.messages.slice();
                    currentList.push({
                        "id": "tool_" + Date.now(),
                        "role": "tool",
                        "content": outputText,
                        "tool_calls": [],
                        "isStreaming": false,
                        "timestamp": Date.now()
                    });
                    root.messages = currentList;
                } catch (e) {
                    console.warn("[AssistantService] Failed to parse exec output:", e);
                }
            }
        }
    }

    function denyToolCall(toolCall) {
        if (!toolCall) return;
        let filtered = activeToolProposals.filter(function(tc) { return tc.id !== toolCall.id; });
        activeToolProposals = filtered;

        let currentList = messages.slice();
        currentList.push({
            "id": "denied_" + Date.now(),
            "role": "system",
            "content": "Execution of `" + toolCall.command + "` was denied by user.",
            "tool_calls": [],
            "isStreaming": false,
            "timestamp": Date.now()
        });
        messages = currentList;
    }

    function refreshStatus() {
        runProc(statusProc, [daemonBin, "assistant", "status"]);
    }

    // -----------------------------------------------------------------------
    // Harness updates (Settings -> AI -> Pi Harness)
    //
    // The Copilot runs on the user's own pi installation, so "update it" is the
    // same `pi update` their terminal would run - run by the daemon, reported
    // back as a version before/after plus pi's own output. The shell never
    // installs a fixed version: it reports what happened.
    // -----------------------------------------------------------------------

    /** The `pi` harness entry as the daemon reports it. */
    readonly property var piHarness: {
        const list = root.availableHarnesses;
        if (!list || !Array.isArray(list)) return null;
        for (let i = 0; i < list.length; ++i) {
            if (list[i] && list[i].id === "pi") return list[i];
        }
        return null;
    }
    /** Installed harness version ("1.0.0"), empty until the daemon reports. */
    readonly property string harnessVersion: (root.piHarness && root.piHarness.version)
        ? String(root.piHarness.version) : ""
    readonly property bool harnessInstalled: root.piHarness ? Boolean(root.piHarness.is_available) : false
    readonly property string harnessPath: (root.piHarness && root.piHarness.path)
        ? String(root.piHarness.path) : ""

    /** "idle" | "running" | "done" | "failed" */
    property string harnessUpdateState: "idle"
    /** "pi" | "extensions" | "models" - which update the message describes. */
    property string harnessUpdateTarget: ""
    property string harnessUpdateMessage: ""
    /** pi's own output, shown as the detail line. */
    property string harnessUpdateDetail: ""

    /** Human line for one update report (see services/PiUpdateMessage.js). */
    function describeHarnessUpdate(report) {
        return PiUpdateMessage.describe(report);
    }

    /** Last non-empty line of pi's output, for the detail under the message. */
    function harnessOutputTail(output) {
        return PiUpdateMessage.tail(output);
    }

    /** Update the harness, its packages, or its model catalogs. */
    function updateHarness(target) {
        if (harnessUpdateProc.running) return;
        const which = target || "pi";
        const argv = [daemonBin, "assistant", "update-pi"];
        if (which === "extensions") argv.push("--extensions");
        else if (which === "models") argv.push("--models");
        root.harnessUpdateTarget = which;
        root.harnessUpdateState = "running";
        root.harnessUpdateMessage = "";
        root.harnessUpdateDetail = "";
        runProc(harnessUpdateProc, argv);
    }

    /** Convenience wrappers for the three buttons. */
    function updatePi() { updateHarness("pi"); }
    function updatePiPackages() { updateHarness("extensions"); }
    function refreshPiModelCatalogs() { updateHarness("models"); }

    Process {
        id: harnessUpdateProc
        property bool discardOutput: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.discardOutput) return;
                const text = this.text.trim();
                if (text.length === 0) return;
                try {
                    const report = JSON.parse(text);
                    root.harnessUpdateState = "done";
                    root.harnessUpdateMessage = root.describeHarnessUpdate(report);
                    root.harnessUpdateDetail = root.harnessOutputTail(report.output);
                    // The version the daemon probed after the update is the truth
                    // from here on.
                    refreshStatus();
                } catch (e) {
                    root.harnessUpdateState = "failed";
                    root.harnessUpdateMessage = text;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = this.text.trim();
                if (err && root.harnessUpdateState === "running") {
                    root.harnessUpdateState = "failed";
                    root.harnessUpdateMessage = err;
                    root.harnessUpdateDetail = "";
                }
            }
        }
    }

    function refreshSkills() {
        runProc(skillsProc, [daemonBin, "assistant", "skills"]);
    }

    function refreshCrashes() {
        runProc(crashesProc, [daemonBin, "assistant", "crashes", "5"]);
    }

    Process {
        id: setModelProc
        property bool discardOutput: false
    }

    Process {
        id: statusProc
        property bool discardOutput: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let obj = JSON.parse(this.text.trim());
                    if (obj.harnesses) {
                        root.availableHarnesses = obj.harnesses;
                    }
                    if (obj.providers && Array.isArray(obj.providers) && obj.providers.length > 0) {
                        root.availableProviders = obj.providers;
                    }
                    if (obj.default_provider && (!Config.assistantDefaultProvider || root.selectedProviderId === "gemini")) {
                        root.selectedProviderId = obj.default_provider;
                    }
                    if (obj.default_model && (!Config.assistantDefaultModel || root.selectedModelId === "gemini-2.5-flash")) {
                        root.selectedModelId = obj.default_model;
                    }
                } catch (e) {
                    console.warn("[AssistantService] Failed to parse status:", e);
                }
            }
        }
    }

    Process {
        id: skillsProc
        property bool discardOutput: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let list = JSON.parse(this.text.trim());
                    if (Array.isArray(list)) {
                        root.discoveredSkills = list;
                    }
                } catch (e) {
                    console.warn("[AssistantService] Failed to parse skills:", e);
                }
            }
        }
    }

    Process {
        id: crashesProc
        property bool discardOutput: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let list = JSON.parse(this.text.trim());
                    if (Array.isArray(list)) {
                        root.recentCrashes = list;
                        root.crashesRevision++;
                    }
                } catch (e) {
                    console.warn("[AssistantService] Failed to parse crashes:", e);
                }
            }
        }
    }

    Process {
        id: activeSessionProc
        property bool discardOutput: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (activeSessionProc.discardOutput || activeSessionProc.running) return;
                try {
                    let obj = JSON.parse(this.text.trim());
                    if (obj && obj.active_session_id) {
                        root.loadSession(obj.active_session_id);
                    } else {
                        root.refreshSessions();
                    }
                } catch (e) {
                    console.warn("[AssistantService] Failed to parse active session:", e);
                }
            }
        }
    }

    Process {
        id: loadSessionsProc
        property bool discardOutput: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (loadSessionsProc.discardOutput || loadSessionsProc.running) return;
                try {
                    let list = JSON.parse(this.text.trim());
                    if (Array.isArray(list)) {
                        root.sessions = list;
                        if (!root.activeSessionId && list.length > 0) {
                            root.loadSession(list[0].id);
                        }
                    }
                } catch (e) {
                    console.warn("[AssistantService] Failed to parse sessions list:", e);
                }
            }
        }
    }

    Process {
        id: getSessionProc
        property bool discardOutput: false
        property string targetId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (getSessionProc.discardOutput || getSessionProc.running) return;
                try {
                    let session = JSON.parse(this.text.trim());
                    if (session && session.id) {
                        root.activeSessionId = session.id;
                        root.activeSessionTitle = session.title || "Chat";
                        if (session.messages && Array.isArray(session.messages)) {
                            root.messages = session.messages;
                            root.messagesRevision++;
                        }
                        if (session.provider) {
                            root.selectedProviderId = session.provider;
                        }
                        if (session.model) {
                            root.selectedModelId = session.model;
                        }
                        root.refreshSessions();
                    }
                } catch (e) {
                    console.warn("[AssistantService] Failed to load session content:", e);
                }
            }
        }
    }

    Process {
        id: saveSessionProc
        property bool discardOutput: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (saveSessionProc.discardOutput || saveSessionProc.running) return;
                root.refreshSessions();
            }
        }
    }

    Process {
        id: deleteSessionProc
        property bool discardOutput: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (deleteSessionProc.discardOutput || deleteSessionProc.running) return;
                root.refreshSessions();
            }
        }
    }

    Process {
        id: streamProc
        property bool discardOutput: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: chunk => {
                if (streamProc.discardOutput) return;   // cancelled: output is truncated
                let line = chunk.trim();
                if (!line) return;
                try {
                    let ev = JSON.parse(line);
                    if (ev.type === "TextChunk") {
                        root.activeStreamingContent += ev.payload;
                        root.updateAssistantStreamContent(root.activeStreamingContent);
                    } else if (ev.type === "ToolProposal") {
                        let props = root.activeToolProposals.slice();
                        props.push(ev.payload);
                        root.activeToolProposals = props;
                    } else if (ev.type === "TurnCompleted") {
                        root.finalizeAssistantTurn();
                    } else if (ev.type === "Error") {
                        root.activeStreamingContent += "\n\n⚠️ Error: " + ev.payload;
                        root.updateAssistantStreamContent(root.activeStreamingContent);
                        root.finalizeAssistantTurn();
                    }
                } catch (e) {
                    // Raw string fallback
                    root.activeStreamingContent += line + "\n";
                    root.updateAssistantStreamContent(root.activeStreamingContent);
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: chunk => {
                let line = chunk.trim();
                if (!line) return;
                console.warn("[AssistantService stream stderr]:", line);
                if (!root.activeStreamingContent) {
                    root.activeStreamingContent = "⚠️ " + line;
                    root.updateAssistantStreamContent(root.activeStreamingContent);
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (root.isStreaming) {
                if (!root.activeStreamingContent) {
                    root.activeStreamingContent = "⚠️ Assistant exited (code " + exitCode + ").";
                }
                root.finalizeAssistantTurn();
            }
        }
    }

    // -----------------------------------------------------------------------
    // Voice input: status probe
    // -----------------------------------------------------------------------

    Process {
        id: voiceStatusProc
        property bool discardOutput: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: chunk => {
                if (voiceStatusProc.discardOutput) return;   // cancelled: output is truncated
                const line = chunk.trim();
                if (!line) return;
                try {
                    const parsed = JSON.parse(line);
                    root.voiceStatus = parsed;
                    // The probe reports state; it never raises a notice.
                    //
                    // An unsolicited "whisper.cpp is not installed" banner in the
                    // composer is noise about a feature the user has not asked for
                    // yet, and it came back every time the drawer opened. The mic
                    // button already carries the same information in its dimmed
                    // state and its hover tooltip, so the explanation is available
                    // on demand and is shown in context the moment the user
                    // actually clicks the mic. See showVoiceSetupNotice().
                    if (parsed.setup_complete === true) {
                        // Setup became complete (engine installed, model
                        // downloaded), so any outstanding notice and its
                        // dismissal are now moot.
                        root.voiceSetupMessage = "";
                        root.voiceDismissedGap = "";
                    }
                } catch (e) {
                    console.warn("[AssistantService] voice status parse failed:", e);
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: chunk => console.warn("[AssistantService voice stderr]:", chunk.trim())
        }
    }

    // -----------------------------------------------------------------------
    // Voice input: model download
    // -----------------------------------------------------------------------

    Process {
        id: voiceInstallProc
        property bool discardOutput: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: chunk => {
                if (voiceInstallProc.discardOutput) return;   // cancelled: output is truncated
                const line = chunk.trim();
                if (!line) return;
                try {
                    const ev = JSON.parse(line);
                    // Progress arrives as a bare fraction; the daemon sends
                    // {"type":"Progress","payload":0.42}.
                    if (ev.type === "Progress" && typeof ev.payload === "number") {
                        root.voiceModelInstallProgress = Math.max(0, Math.min(1, ev.payload));
                        return;
                    }
                    root.voiceModelInstalling = false;
                    if (ev.success === true) {
                        root.voiceModelInstallProgress = 1.0;
                        root.voiceSetupMessage = "";
                        root.refreshVoiceStatus();
                    } else if (ev.error) {
                        root.voiceSetupMessage = ev.error;
                    }
                } catch (e) {
                    console.warn("[AssistantService] voice install parse failed:", e);
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: chunk => console.warn("[AssistantService voice install stderr]:", chunk.trim())
        }

        onExited: (exitCode, exitStatus) => {
            root.voiceModelInstalling = false;
            // Always re-probe: a download may have succeeded, or failed, and the
            // mic button must reflect reality either way.
            root.refreshVoiceStatus();
        }
    }

    // VAD asset download: the same JSONL contract as the model installer
    // (Progress fractions, then a final {"success":...}). Absence only costs
    // accuracy, so a failure warns rather than breaking readiness.
    Process {
        id: voiceVadInstallProc
        property bool discardOutput: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: chunk => {
                if (voiceVadInstallProc.discardOutput) return;
                const line = chunk.trim();
                if (!line) return;
                try {
                    const ev = JSON.parse(line);
                    if (ev.type === "Progress" && typeof ev.payload === "number") {
                        root.voiceVadInstallProgress = Math.max(0, Math.min(1, ev.payload));
                        return;
                    }
                    root.voiceVadInstalling = false;
                    if (ev.success === true) {
                        root.voiceVadInstallProgress = 1.0;
                        root.refreshVoiceStatus();
                    } else if (ev.error) {
                        console.warn("[AssistantService] VAD install failed:", ev.error);
                    }
                } catch (e) {
                    console.warn("[AssistantService] vad install parse failed:", e);
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: chunk => console.warn("[AssistantService vad install stderr]:", chunk.trim())
        }

        onExited: (exitCode, exitStatus) => {
            root.voiceVadInstalling = false;
            root.refreshVoiceStatus();
        }
    }

    // Device-only mic check: one JSON report line, never audio.
    Process {
        id: voiceMicCheckProc
        property bool discardOutput: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: chunk => {
                if (voiceMicCheckProc.discardOutput) return;
                const line = chunk.trim();
                if (!line) return;
                try {
                    const report = JSON.parse(line);
                    if (report && report.verdict) {
                        root.voiceMicCheckResult = report;
                    }
                } catch (e) {
                    console.warn("[AssistantService] mic check parse failed:", e);
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: chunk => console.warn("[AssistantService mic check stderr]:", chunk.trim())
        }

        onExited: (exitCode, exitStatus) => {
            root.voiceMicChecking = false;
            root.refreshVoiceStatus();
        }
    }

    // Removing a model: the same JSON contract as the installer, minus progress.
    Process {
        id: voiceRemoveProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: chunk => {
                const line = chunk.trim();
                if (!line) return;
                try {
                    const ev = JSON.parse(line);
                    if (ev.success !== true && ev.error) {
                        root.voiceSetupMessage = ev.error;
                    }
                } catch (e) {
                    console.warn("[AssistantService] voice remove parse failed:", e);
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: chunk => console.warn("[AssistantService voice remove stderr]:", chunk.trim())
        }

        onExited: (exitCode, exitStatus) => root.refreshVoiceStatus()
    }

    // -----------------------------------------------------------------------
    // Voice input: capture session
    // -----------------------------------------------------------------------

    Process {
        id: voiceSessionProc
        property bool discardOutput: false

        // The control channel only exists once the process is up, so the `start`
        // command is sent from a running-change handler rather than inline after
        // `running = true`. Without this the daemon blocks forever waiting for a
        // command that was never delivered, the microphone is never opened, and
        // the UI still shows "recording" from its own timer.
        onRunningChanged: {
            if (running && root.voiceAwaitingStart) {
                root.voiceAwaitingStart = false;
                write("start\n");
            }
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: chunk => {
                const line = chunk.trim();
                if (!line) return;
                let ev;
                try {
                    ev = JSON.parse(line);
                } catch (e) {
                    // Ignore non-JSON noise rather than corrupting state.
                    console.warn("[AssistantService] voice event parse failed:", e);
                    return;
                }

                if (ev.type === "StateChanged") {
                    root.voiceState = ev.payload.state;
                    // The microphone is released the moment capture ends, so the
                    // level must die with it. Leaving the last live reading on
                    // screen while the engine works is a dead meter under a strip
                    // that still claims to be recording.
                    if (ev.payload.state === "finalizing") {
                        root.voiceLevel = 0.0;
                    }
                    if (ev.payload.state === "idle" || ev.payload.state === "failed") {
                        voiceElapsedTimer.stop();
                        root.voiceLevel = 0.0;
                    }
                } else if (ev.type === "Level") {
                    // Measured RMS from the real capture stream.
                    root.voiceLevel = voiceEventCodec.level(ev);
                } else if (ev.type === "Partial") {
                    root.voicePartialText = voiceEventCodec.partial(ev);
                } else if (ev.type === "Warning") {
                    // Non-fatal: the session continues. Cleared on next start.
                    root.voiceWarning = (ev.payload && ev.payload.message) || "Audio input warning";
                } else if (ev.type === "Detected") {
                    // The reading arrives before the decode, so it is on screen
                    // while the transcript is still being produced. That is the
                    // whole point: with a fused `-l auto` pass there was nothing
                    // to show here, and by the time the language could be read
                    // the wrong text was already written and the strip closed.
                    root.voiceDetectedLanguage = ev.payload.language || "";
                    root.voiceLanguageConfidence = typeof ev.payload.confidence === "number"
                        ? ev.payload.confidence
                        : -1;
                } else if (ev.type === "Final") {                    // `payload` is the transcript object itself.
                    //
                    // The empty case is handled here, explicitly, rather than
                    // left to the composer's change handler. Assigning `""` to
                    // `voiceTranscript` when it is already `""` emits no change
                    // signal, so `onVoiceTranscriptChanged` never ran and a
                    // session that heard nothing ended with the microphone
                    // visibly working and the composer silently untouched. An
                    // honest outcome still has to be reported.
                    const text = ev.payload.text || "";
                    root.voiceSpeechDetected = ev.payload.speech_detected !== false;
                    if (text.trim().length > 0) {
                        root.voiceTranscript = text;
                        root.voiceEmptyNotice = "";
                    } else {
                        root.voiceTranscript = "";
                        // Two different problems, and the distinction decides
                        // where the user's attention should go.
                        //
                        // Both are kept short on purpose: the strip is 46 px and
                        // the text elides, so a long sentence loses exactly the
                        // actionable end. The first version read "…check the
                        // microphone, or tr…" in the rendered proof.
                        root.voiceEmptyNotice = root.voiceSpeechDetected
                            ? "Heard you, but got no words - try again or use a larger model"
                            : "No speech detected - check your microphone, then try again";
                    }
                    root.voiceLanguage = ev.payload.language || "und";
                    root.voicePartialText = "";
                    root.voiceState = "idle";
                    voiceElapsedTimer.stop();
                    root.voiceLevel = 0.0;
                } else if (ev.type === "Error") {
                    root.voiceState = "failed";
                    voiceElapsedTimer.stop();
                    root.voiceLevel = 0.0;
                    if (ev.payload && ev.payload.recoverable === true) {
                        // A setup gap is user-fixable, so it lives in the
                        // persistent inline notice rather than a transient banner.
                        root.voiceSetupMessage = ev.payload.message || "Voice input is unavailable";
                    } else {
                        root.voiceSetupMessage = "";
                        root.reportVoiceCrash(ev.payload ? ev.payload.message : "Voice engine failed");
                    }
                    root.refreshVoiceStatus();
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: chunk => console.warn("[AssistantService voice session stderr]:", chunk.trim())
        }

        onExited: (exitCode, exitStatus) => {
            // The process exiting always means the microphone has been released.
            voiceElapsedTimer.stop();
            root.voiceLevel = 0.0;
            // Re-arm the start handshake for the next session.
            root.voiceAwaitingStart = false;
            if (root.voiceState === "recording" || root.voiceState === "finalizing") {
                // Exited mid-session without a Final: surface it rather than
                // leaving the composer looking like it is still listening.
                if (root.voiceState === "recording") {
                    root.voiceState = "idle";
                } else {
                    root.voiceState = "failed";
                }
            }
        }
    }

    Timer {
        id: voiceElapsedTimer
        interval: 100
        repeat: true
        onTriggered: root.voiceElapsedMs += 100
    }

    /**
     * Surfaces a genuine engine death through the existing crash carousel.
     *
     * Reuses `recentCrashes` rather than introducing a second error surface, so
     * the user sees runtime deaths in one place. A setup gap deliberately does
     * NOT come here: install instructions belong in the persistent inline
     * notice beside the mic button, not in a transient carousel.
     */
    function reportVoiceCrash(message) {
        const text = message || "Voice engine failed";
        const now = Date.now();
        const entry = {
            "id": "voice_" + now,
            "process_name": "whisper.cpp",
            "signal": null,
            "timestamp_ms": now,
            "summary": "Voice transcription failed: " + text,
            "log_snippet": text,
            "count": 1
        };
        const list = (root.recentCrashes || []).slice();
        // Deduplicate by summary so a retry loop cannot flood the carousel.
        const existing = list.findIndex(c => c.summary === entry.summary);
        if (existing >= 0) {
            const merged = list.slice();
            merged[existing] = Object.assign({}, merged[existing], { count: (merged[existing].count || 1) + 1 });
            root.recentCrashes = merged;
        } else {
            list.unshift(entry);
            root.recentCrashes = list.slice(0, 5);
        }
        root.crashesRevision++;
    }

    Timer {
        id: streamWatchdog
        interval: 60000 // 60s timeout
        repeat: false
        onTriggered: {
            if (root.isStreaming) {
                console.warn("[AssistantService] Stream timed out after 60s. Forcing finalize.");
                cancelProc(streamProc);
                if (!root.activeStreamingContent) {
                    root.activeStreamingContent = "⚠️ Request timed out. Please check your network connection or model settings.";
                }
                root.finalizeAssistantTurn();
            }
        }
    }

    function updateAssistantStreamContent(text) {
        if (messages.length === 0) return;
        let lastIdx = messages.length - 1;
        if (messages[lastIdx].role === "assistant") {
            let updated = Object.assign({}, messages[lastIdx], {
                "content": text,
                "tool_calls": activeToolProposals
            });
            let copy = messages.slice();
            copy[lastIdx] = updated;
            messages = copy;
            messagesRevision++;
        }
    }

    function finalizeAssistantTurn() {
        streamWatchdog.stop();
        root.isStreaming = false;
        if (messages.length === 0) return;
        let lastIdx = messages.length - 1;
        if (messages[lastIdx].role === "assistant") {
            let updated = Object.assign({}, messages[lastIdx], {
                "content": root.activeStreamingContent || "No response received.",
                "tool_calls": activeToolProposals,
                "isStreaming": false
            });
            let copy = messages.slice();
            copy[lastIdx] = updated;
            messages = copy;
            messagesRevision++;
            persistActiveSession();
        }
    }

    // Clipboard & Mermaid Rendering
    function copyToClipboard(text) {
        if (!text) return;
        runProc(copyClipProc, ["wl-copy", text]);
    }

    Process {
        id: copyClipProc
        property bool discardOutput: false
    }

    function pasteClipboardImage(callback) {
        clipProc.callback = callback;
        runProc(clipProc, ["sh", "-c", "if wl-paste -l 2>/dev/null | grep -q 'image/'; then out=\"/tmp/astral_clip_$(date +%s%N).png\"; wl-paste --type image/png > \"$out\" && echo \"$out\"; fi"]);
    }

    Process {
        id: clipProc
        property bool discardOutput: false
        property var callback: null
        stdout: StdioCollector {
            onDataChanged: {
                const p = data.trim();
                if (p.length > 0 && typeof clipProc.callback === "function") {
                    clipProc.callback(p);
                    clipProc.callback = null;
                }
            }
        }
    }

    property var mermaidCallbacks: ({})
    property int mermaidReqId: 0

    function renderMermaid(code, callback) {
        if (!code) return;
        const reqId = "req_" + (++mermaidReqId);
        mermaidCallbacks[reqId] = callback;

        const script = Qt.resolvedUrl("../scripts/render_mermaid.mjs").toString().replace("file://", "");
        mermaidRenderProc.currentReqId = reqId;
        runProc(mermaidRenderProc, ["node", script, code.trim()]);
    }

    Process {
        id: mermaidRenderProc
        property bool discardOutput: false
        property string currentReqId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const reqId = mermaidRenderProc.currentReqId;
                const cb = root.mermaidCallbacks[reqId];
                if (typeof cb === "function") {
                    try {
                        const raw = String(this.text || "").trim();
                        const parsed = JSON.parse(raw);
                        cb(parsed);
                    } catch (e) {
                        cb({ success: false, error: "JSON parse error: " + e });
                    }
                    delete root.mermaidCallbacks[reqId];
                }
            }
        }
    }

    // Periodic crash monitor timer
    Timer {
        interval: 15000
        repeat: true
        running: (typeof Config !== "undefined") ? Config.assistantAutoProactiveCrash : true
        onTriggered: {
            root.refreshCrashes();
        }
    }
}
