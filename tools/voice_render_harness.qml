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
    height: 420
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
        property string voiceTranscript: ""
        property var voiceStatus: ({ "setup_complete": true })
        readonly property bool isVoiceRecording: voiceState === "recording"
        readonly property bool isVoiceBusy: voiceState === "recording" || voiceState === "finalizing"
        readonly property bool voiceReady: voiceStatus !== null && voiceStatus.setup_complete === true
        readonly property bool voiceMicUsable: voiceEnabled && voiceReady && !isVoiceBusy
        function startVoiceInput() {}
        function stopVoiceInput() {}
    }

    // --- State 1: idle, engine ready -----------------------------------
    VoiceBackend { id: v1 }
    ChatInputBar {
        id: bar1
        x: 30; y: 22
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
        voiceLanguage: "zh"
    }
    ChatInputBar {
        id: bar2
        x: 30; y: 120
        width: 460
        voice: v2
    }

    // --- State 3: finalizing (mic released) -----------------------------
    VoiceBackend {
        id: v3
        voiceState: "finalizing"
        voiceElapsedMs: 7400
        voiceLanguage: "zh"
    }
    ChatInputBar {
        id: bar3
        x: 30; y: 218
        width: 460
        voice: v3
    }

    // --- State 4: setup gap (engine missing, recoverable) ---------------
    VoiceBackend {
        id: v4
        voiceStatus: null
        voiceSetupMessage: "whisper.cpp is not installed"
    }
    ChatInputBar {
        id: bar4
        x: 30; y: 316
        width: 460
        voice: v4
    }

    // Self-describing labels, so each capture is legible on its own.
    Text {
        x: 30; y: 4
        text: "1 · IDLE — engine ready, mic armed"
        color: "#8ab4ff"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 102
        text: "2 · RECORDING — measured RMS 0.62 · detected zh · 7.4s"
        color: "#ff6b6b"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 200
        text: "3 · FINALIZING — mic released, engine working"
        color: "#ffd166"; font.pixelSize: 11; font.family: "monospace"
    }
    Text {
        x: 30; y: 298
        text: "4 · SETUP GAP — recoverable, inline notice"
        color: "#c58cff"; font.pixelSize: 11; font.family: "monospace"
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
            shot(bar4, "04-setup-gap.png");
        }
    }

    Timer {
        interval: 2600
        running: true
        repeat: false
        onTriggered: Qt.exit(0)
    }
}
