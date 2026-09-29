import QtQuick
import QtQuick.Window
import "../theme"
import "../components"
import "../assistant/components"

/**
 * Visual proof harness for the voice input UI.
 *
 * Renders `ChatInputBar` over a real desktop capture so translucency, curvature
 * and contrast are judged against busy content rather than an empty screen
 * (AGENTS.md 6.4). Each state is grabbed to its own PNG.
 *
 *   qml tools/voice_render_harness.qml
 *
 * Writes to /tmp/voice-proof/.
 */
Window {
    id: win
    width: 520
    height: 950
    visible: true
    color: "#101014"

    property string outDir: "/tmp/voice-proof"

    // Real desktop content, cropped to a busy region so the glass has something
    // to actually refract.
    Image {
        anchors.fill: parent
        source: "file:///tmp/screen.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
    }

    /** Stand-in for AssistantService, exposing exactly what the composer reads. */
    component VoiceBackend: QtObject {
        property bool voiceEnabled: true
        property string voiceState: "idle"
        property real voiceLevel: 0.0
        property int voiceElapsedMs: 0
        property string voiceLanguage: ""
        property string voicePartialText: ""
        property string voiceSetupMessage: ""
        property string voiceEmptyNotice: ""
        property string voiceWarning: ""
        property string voiceTranscript: ""
        property string voiceDetectedLanguage: ""
        property real voiceLanguageConfidence: -1
        property var voiceStatus: ({ "setup_complete": true })
        readonly property bool isVoiceRecording: voiceState === "recording"
        readonly property bool isVoiceBusy: voiceState === "recording" || voiceState === "finalizing"
        readonly property bool voiceReady: voiceStatus !== null && voiceStatus.setup_complete === true
        readonly property bool voiceMicUsable: voiceEnabled && voiceReady && !isVoiceBusy
        function startVoiceInput() {}
        function stopVoiceInput() {}
        function dismissVoiceSetupNotice() {}
        function dismissVoiceEmptyNotice() {}
    }

    // --- State 1: idle, engine ready -----------------------------------
    VoiceBackend { id: v1 }
    ChatInputBar {
        id: bar1
        x: 30; y: 26
        width: 460
        voice: v1
        inputText: "Explain the PipeWire latency in this system"
    }

    // --- State 2: recording, measured level, detected language ---------
    VoiceBackend {
        id: v2
        voiceState: "recording"
        voiceLevel: 0.62
        voiceElapsedMs: 7400
        // No language here on purpose. The service clears it at session start
        // because detection has not happened yet, and a proof that shows a state
        // the product cannot reach is worse than no proof at all.
    }
    ChatInputBar {
        id: bar2
        x: 30; y: 140
        width: 460
        voice: v2
    }

    // --- State 3: finalizing (mic released) -----------------------------
    VoiceBackend {
        id: v3
        voiceState: "finalizing"
        voiceLevel: 0.62
        voiceElapsedMs: 7400
        // Still no reading: the detection pass has not reported yet. The strip
        // says "transcribing" here, honestly.
    }
    ChatInputBar {
        id: bar3
        x: 30; y: 252
        width: 460
        voice: v3
    }

    // --- State 4: a *confident* reading, shown while the decode runs ------
    // The whole point of the two-pass protocol: this is on screen before the
    // transcript exists, so it is the only reading the user can act on.
    VoiceBackend {
        id: v4
        voiceState: "finalizing"
        voiceElapsedMs: 7400
        voiceDetectedLanguage: "zh"
        voiceLanguageConfidence: 0.93
    }
    ChatInputBar {
        id: bar4
        x: 30; y: 364
        width: 460
        voice: v4
    }

    // --- State 5: a *doubtful* reading, marked as one --------------------
    // The reported failure, made visible: p = 0.08 is a tie between a hundred
    // languages, and it must not be presented as a fact.
    VoiceBackend {
        id: v5
        voiceState: "finalizing"
        voiceElapsedMs: 1400
        voiceDetectedLanguage: "ja"
        voiceLanguageConfidence: 0.084
    }
    ChatInputBar {
        id: bar5
        x: 30; y: 476
        width: 460
        voice: v5
    }

    // --- State 6: a session that produced nothing, and said so ------------
    VoiceBackend {
        id: v6
        voiceState: "idle"
        voiceEmptyNotice: "No speech detected - check your microphone, then try again"
    }
    ChatInputBar {
        id: bar6
        x: 30; y: 588
        width: 460
        voice: v6
    }

    // --- State 7: setup gap (engine missing, recoverable) -----------------
    VoiceBackend {
        id: v7
        voiceStatus: null
        voiceSetupMessage: "whisper.cpp is not installed"
    }
    ChatInputBar {
        id: bar7
        x: 30; y: 700
        width: 460
        voice: v7
    }

    // --- State 8: clipping warning mid-capture (non-fatal) -----------------
    // The gain guard fired at 0.5 s but the session continues: error-toned
    // warning text beside a LIVE meter, timer and language readout — never a
    // collapsed "dead microphone" row, and gone with the next start.
    VoiceBackend {
        id: v8
        voiceState: "recording"
        voiceLevel: 0.71
        voiceElapsedMs: 2300
        voiceWarning: "Microphone input is clipping (68% of samples at the rails). Lower the mic boost, then try again."
    }
    ChatInputBar {
        id: bar8
        x: 30; y: 812
        width: 460
        voice: v8
    }

    // Self-describing labels, so each capture is legible on its own.
    Text {
        x: 30; y: 8
        text: "1 · IDLE — engine ready, mic armed"
        color: "#8ab4ff"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 116
        text: "2 · RECORDING — measured RMS 0.62 · 7.4s · no reading yet"
        color: "#ff6b6b"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 228
        text: "3 · FINALIZING — mic released, engine working"
        color: "#ffd166"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 340
        text: "4 · CONFIDENT READING — zh (p=0.93) shown before the text exists"
        color: "#8ab4ff"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 452
        text: "5 · DOUBTFUL READING — ja (p=0.08) marked unsure, one click to fix"
        color: "#ff9f6b"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 564
        text: "6 · NO SPEECH DETECTED — reported, not swallowed"
        color: "#ff6b6b"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 676
        text: "7 · SETUP GAP — recoverable, links into Settings"
        color: "#c58cff"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 788
        text: "8 · CLIPPING WARNING — live meter kept, error tone, non-fatal"
        color: "#ff6b6b"; font.pixelSize: 11; font.family: "monospace"
    }

    function shot(item, name) {
        item.grabToImage(function(res) {
            res.saveToFile(outDir + "/" + name);
            console.log("saved " + name);
        });
    }

    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: {
            shot(win.contentItem, "00-all-states.png");
            shot(bar1, "01-idle.png");
            shot(bar2, "02-recording.png");
            shot(bar3, "03-finalizing.png");
            shot(bar4, "04-language-confident.png");
            shot(bar5, "05-language-doubtful.png");
            shot(bar6, "06-no-speech-notice.png");
            shot(bar7, "07-setup-gap.png");
            shot(bar8, "08-clipping-warning.png");
        }
    }

    Timer {
        interval: 2600
        running: true
        repeat: false
        onTriggered: Qt.exit(0)
    }
}
