pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
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
    property var availableHarnesses: [
        { "id": "pi", "name": "Pi Agent", "is_available": true, "version": "0.87.1", "is_default": true },
        { "id": "hermes", "name": "Hermes Agent", "is_available": false, "version": null, "is_default": false }
    ]
    property var discoveredSkills: []
    property var recentCrashes: []
    property var dismissedCrashIds: []
    property int crashesRevision: 0

    readonly property var activeCrashes: {
        let rev = crashesRevision;
        if (!recentCrashes || !Array.isArray(recentCrashes)) return [];
        let dismissed = dismissedCrashIds || [];
        return recentCrashes.filter(function(c) {
            return c && c.id && dismissed.indexOf(c.id) === -1;
        });
    }

    function dismissCrash(crashId) {
        if (!crashId) return;
        let list = (dismissedCrashIds || []).slice();
        if (list.indexOf(crashId) === -1) {
            list.push(crashId);
            dismissedCrashIds = list;
            crashesRevision++;
        }
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
            setModelProc.command = [daemonBin, "assistant", "set-model", selectedProviderId, modelId];
            setModelProc.running = true;
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
    }

    function loadActiveSession() {
        if (activeSessionProc.running) activeSessionProc.terminate();
        activeSessionProc.command = [daemonBin, "assistant", "active-session"];
        activeSessionProc.running = true;
    }

    function refreshSessions() {
        if (loadSessionsProc.running) loadSessionsProc.terminate();
        loadSessionsProc.command = [daemonBin, "assistant", "sessions"];
        loadSessionsProc.running = true;
    }

    function loadSession(id) {
        if (!id) return;
        if (getSessionProc.running) getSessionProc.terminate();
        getSessionProc.targetId = id;
        getSessionProc.command = [daemonBin, "assistant", "get-session", id];
        getSessionProc.running = true;
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
        if (deleteSessionProc.running) deleteSessionProc.terminate();
        deleteSessionProc.command = [daemonBin, "assistant", "delete-session", id];
        deleteSessionProc.running = true;

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
        if (saveSessionProc.running) saveSessionProc.terminate();
        saveSessionProc.command = [daemonBin, "assistant", "save-session", jsonPayload];
        saveSessionProc.running = true;
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
        if (streamProc.running) {
            streamProc.terminate();
        }
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

        streamProc.command = [daemonBin].concat(args);
        streamProc.running = true;
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
        toolExecProc.command = execArgs;
        toolExecProc.running = true;
    }

    property var pendingToolCall: null

    Process {
        id: toolExecProc
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
        statusProc.command = [daemonBin, "assistant", "status"];
        statusProc.running = true;
    }

    function refreshSkills() {
        skillsProc.command = [daemonBin, "assistant", "skills"];
        skillsProc.running = true;
    }

    function refreshCrashes() {
        crashesProc.command = [daemonBin, "assistant", "crashes", "5"];
        crashesProc.running = true;
    }

    Process {
        id: setModelProc
    }

    Process {
        id: statusProc
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
        stdout: StdioCollector {
            onStreamFinished: {
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
        stdout: StdioCollector {
            onStreamFinished: {
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
        property string targetId: ""
        stdout: StdioCollector {
            onStreamFinished: {
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
        stdout: StdioCollector {
            onStreamFinished: {
                root.refreshSessions();
            }
        }
    }

    Process {
        id: deleteSessionProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.refreshSessions();
            }
        }
    }

    Process {
        id: streamProc

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: chunk => {
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

    Timer {
        id: streamWatchdog
        interval: 60000 // 60s timeout
        repeat: false
        onTriggered: {
            if (root.isStreaming) {
                console.warn("[AssistantService] Stream timed out after 60s. Forcing finalize.");
                if (root.streamProc.running) {
                    root.streamProc.terminate();
                }
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
        copyClipProc.command = ["wl-copy", text];
        copyClipProc.running = true;
    }

    Process {
        id: copyClipProc
    }

    function pasteClipboardImage(callback) {
        clipProc.callback = callback;
        clipProc.command = ["sh", "-c", "if wl-paste -l 2>/dev/null | grep -q 'image/'; then out=\"/tmp/astral_clip_$(date +%s%N).png\"; wl-paste --type image/png > \"$out\" && echo \"$out\"; fi"];
        clipProc.running = true;
    }

    Process {
        id: clipProc
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
        mermaidRenderProc.command = ["node", script, code.trim()];
        mermaidRenderProc.running = true;
    }

    Process {
        id: mermaidRenderProc
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
