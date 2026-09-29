import QtQuick
import "../theme"
import "../components"
import "../config"
import "../services"
import "../assistant"
import "../assistant/components"

/**
 * Voice input UI contracts.
 *
 * Headless and engine-free: every assertion runs without whisper.cpp, a
 * downloaded model or a microphone, because the properties under test are driven
 * directly through `ChatInputBar.voice`.
 *
 * That injection seam matters: `services/` ships no qmldir, so `AssistantService`
 * resolves as a registered type only inside the running shell, never in an
 * offscreen test. The composer therefore takes its voice backend as a property
 * rather than hard-wiring the singleton, which also decouples it properly.
 *
 * The safety assertion (a transcript must never auto-send) is the important one.
 * See `docs/VOICE-INPUT-SPEC.md` section 8.6.
 */
Item {
    id: testRoot
    width: 1200
    height: 900

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

    /** A stand-in for AssistantService, exposing exactly what the composer reads. */
    QtObject {
        id: fakeVoice
        property bool voiceEnabled: true
        property string voiceState: "idle"
        property real voiceLevel: 0.0
        property int voiceElapsedMs: 0
        property string voiceLanguage: ""
        property string voicePartialText: ""
        property string voiceSetupMessage: ""
        property string voiceEmptyNotice: ""
        property string voiceTranscript: ""
        property var voiceStatus: null
        property int startCount: 0
        property int stopCount: 0
        property int showNoticeCount: 0
        property int dismissNoticeCount: 0

        readonly property bool isVoiceRecording: voiceState === "recording"
        readonly property bool isVoiceBusy: voiceState === "recording" || voiceState === "finalizing"
        readonly property bool voiceReady: voiceStatus !== null && voiceStatus.setup_complete === true
        readonly property bool voiceMicUsable: voiceEnabled && voiceReady && !isVoiceBusy

        function startVoiceInput() { startCount++; voiceState = "recording"; }
        function stopVoiceInput() { stopCount++; voiceState = "idle"; }
        // Mirrors AssistantService.showVoiceSetupNotice(): the notice is
        // dismissed per-gap, so re-showing must clear that dismissal first.
        function showVoiceSetupNotice() { showNoticeCount++; }
        function dismissVoiceSetupNotice() { dismissNoticeCount++; }
    }

    // The exact decoder AssistantService uses for session events. Imported
    // directly so the payload shapes are exercised for real, not scraped.
    VoiceEventCodec {
        id: voiceCodec
    }

    // Scoping probe for the bug class the source contract below forbids.
    // A child id is a lexical capture, not a property of the root object, so
    // `root.childId` is undefined inside nested handlers while the bare id
    // resolves. The probe executes the rule instead of asserting it in prose.
    Item {
        id: scopeProbe
        property var viaRoot: undefined
        property var viaBareId: undefined

        QtObject {
            id: scopeProbeNested
            signal fired()
            Component.onCompleted: fired()
            onFired: {
                scopeProbe.viaRoot = scopeProbe.probeTimer;
                scopeProbe.viaBareId = probeTimer;
            }
        }

        Timer { id: probeTimer; interval: 100000; running: false }
    }

    property int submitCount: 0
    property string lastSubmitted: ""

    // Drives the frame-separated strip-width measurements. Widths in a
    // RowLayout are assigned during polish, so a state change and its
    // measurement cannot happen in the same tick.
    property string readoutPhase: ""

    // Exactly one composer: a transcript is consumed once, so a second composer
    // would race for it and mask the safety check.
    ChatInputBar {
        id: bar
        width: 460
        stagedFiles: []
        voice: fakeVoice
        onSubmitMessage: function(text, images) {
            testRoot.submitCount++;
            testRoot.lastSubmitted = text;
        }
    }

    // A strip driven directly, independent of any daemon.
    VoiceListeningStrip {
        id: strip
        width: 420
        height: 44
        state: "idle"
        level: 0.0
        elapsedMs: 0
        detectedLanguage: ""
    }

    // Fires once a frame has passed since the last state change.
    Timer {
        interval: 90
        repeat: false
        running: testRoot.readoutPhase !== ""
        onTriggered: measureStripWidths()
    }

    function measureStripWidths() {
        const phase = testRoot.readoutPhase;
        testRoot.readoutPhase = "";

        if (phase === "notice") {
            // Nothing is being captured, so every live readout is hidden. This is
            // the assertion that matters: the readouts are what made a failed
            // request look like a dead microphone. The exact laid-out width is
            // not asserted here because a headless harness does not run the real
            // layout -- the width contract is asserted from source instead (a Text
            // clamps back to its implicitWidth unless the minimum is dropped).
            assert(strip.isCapturing === false, "an idle strip must not claim to be capturing");
            assert(strip.hasSetupMessage === true, "a setup message on an idle strip is a notice");
            for (const readout of ["meterItem", "timerItem", "stateLabelItem"]) {
                assert(strip[readout].visible === false,
                    readout + " must be hidden when nothing is being captured, it reports nothing");
            }
            assert(strip.statusIconItem.visible === true,
                "the status slot stays: a warning mark replaces the mic in the error state");
            assert(strip.transcriptItem.visible === true, "the explanation must be visible");

            strip.state = "recording";
            strip.setupMessage = "";
            testRoot.readoutPhase = "recording";
            return;
        }

        if (phase === "recording") {
            // A real session keeps its live feedback.
            assert(strip.isCapturing === true, "a recording strip must report capturing");
            for (const readout of ["meterItem", "timerItem", "stateLabelItem"]) {
                assert(strip[readout].visible === true,
                    readout + " must be present while recording, got: " + strip[readout].visible);
            }
            assert(strip.meterItem.height === 18,
                "the level meter must keep a fixed height while live, got: " + strip.meterItem.height);
            assert(strip.meterItem.width === 34,
                "the meter must return while recording, got: " + strip.meterItem.width);
            assert(strip.timerItem.width === 34,
                "the clock must return while recording, got: " + strip.timerItem.width);
            assert(strip.timerItem.width <= 40,
                "the timer must stay narrow so the row does not reflow, got: " + strip.timerItem.width);
            assert(strip.stateLabelItem.width > 0,
                "the language reading must return while recording, got: " + strip.stateLabelItem.width);

            // Transcription runs after capture stops, so the readout must name
            // the work in progress. "language not determined" during a long
            // inference read as a hang.
            strip.state = "finalizing";
            assert(strip.isCapturing === true,
                "finalizing is still a live session: the strip must not collapse to a notice");
            assert(strip.stateLabelItem.text === "transcribing",
                "the finalizing readout must say the engine is running, got: " + strip.stateLabelItem.text);

            strip.state = "idle";
            testRoot.readoutPhase = "done";
            return;
        }

        console.log("PASS: tst_voice_input");
        Qt.exit(0);
    }

    function runTests() {
        console.log("Running tst_voice_input.qml test suite...");

        // ------------------------------------------------------------------
        // 0. Session-event decoding: payload shapes are typed, not guessed
        // ------------------------------------------------------------------
        // `VoiceEvent::Level { rms }` serialises as
        // `{"type":"Level","payload":{"rms":0.42}}`. Reading the payload as
        // the number is silent in JavaScript (`Math.min(1, obj)` is NaN),
        // which is how a live microphone rendered as a dead level meter.
        const near = (a, b) => Math.abs(a - b) < 1e-9;
        assert(near(voiceCodec.level({ "type": "Level", "payload": { "rms": 0.42 } }), 0.42),
            "a Level event's rms must come out of the payload object");
        assert(near(voiceCodec.level({ "type": "Level", "payload": { "rms": 0.0 } }), 0.0),
            "silence must decode to zero, not NaN");
        assert(near(voiceCodec.level({ "type": "Level", "payload": { "rms": 2.0 } }), 1.0),
            "levels above full scale must clamp");
        assert(near(voiceCodec.level({ "type": "Level", "payload": { "rms": -0.5 } }), 0.0),
            "negative levels must clamp to zero");
        // A bare number was the original (wrong) assumption; it must still be
        // accepted rather than regressing the other direction.
        assert(near(voiceCodec.level({ "type": "Level", "payload": 0.5 }), 0.5),
            "a bare numeric payload must still decode");
        // Malformed payloads are silence, never NaN: NaN would poison the meter
        // and every value derived from it.
        for (const bad of [null, { "type": "Level" }, { "type": "Level", "payload": {} },
                           { "type": "Level", "payload": { "rms": "loud" } }]) {
            const decoded = voiceCodec.level(bad);
            assert(near(decoded, 0.0), "a malformed Level event must decode to silence, got " + decoded);
        }

        // `Partial { text }` is also a struct payload, so the same class of bug
        // existed for streaming engines: assigning the payload object to the
        // strip's string produced "[object Object]" instead of words.
        assert(voiceCodec.partial({ "type": "Partial", "payload": { "text": "hel" } }) === "hel",
            "a Partial event's text must come out of the payload object");
        assert(voiceCodec.partial({ "type": "Partial", "payload": "legacy" }) === "legacy",
            "a bare string payload must still decode");
        for (const bad of [null, { "type": "Partial" }, { "type": "Partial", "payload": {} }]) {
            assert(voiceCodec.partial(bad) === "", "a malformed Partial event must decode to an empty string");
        }

        // ------------------------------------------------------------------
        // 0b. Child ids are lexical, not root properties
        // ------------------------------------------------------------------
        // The voice session's handlers used `root.voiceElapsedTimer`, which is
        // always undefined: every stop() threw, so the timer reset, the state
        // reconcile and the start handshake on exit were all skipped. The same
        // mistake existed for the chat stream watchdog (`root.streamProc`).
        assert(scopeProbe.viaRoot === undefined,
            "root.<childId> must be undefined inside nested handlers; that is why the contract below exists");
        assert(scopeProbe.viaBareId !== undefined && scopeProbe.viaBareId !== null,
            "a child id resolves lexically inside nested handlers");

        // ------------------------------------------------------------------
        // 1. Transcript append semantics (mirrors domain::voice::append_transcript)
        // ------------------------------------------------------------------
        assert(bar.appendTranscript("", "hello") === "hello", "empty composer yields the transcript");
        assert(bar.appendTranscript("typed", "hello") === "typed hello", "typed text must be preserved with a space");
        assert(bar.appendTranscript("typed ", "hello") === "typed hello", "trailing space must not double up");
        assert(bar.appendTranscript("typed\n", "hello") === "typed\nhello", "a deliberate newline must be preserved");
        assert(bar.appendTranscript("line1\nline2", "hello") === "line1\nline2 hello", "mid-text newline must survive");
        assert(bar.appendTranscript("keep", "   ") === "keep", "a blank transcript must not be appended");
        assert(bar.appendTranscript("keep", "") === "keep", "an empty transcript must not be appended");
        assert(bar.appendTranscript("代码", "测试") === "代码 测试", "CJK append must work");
        assert(bar.appendTranscript("a", "b") === "a b", "append must never clobber");

        testSafetyThenStrip();
    }

    function testSafetyThenStrip() {
        // ------------------------------------------------------------------
        // 2. SAFETY: a dictation transcript must never auto-send
        // ------------------------------------------------------------------
        testRoot.submitCount = 0;
        fakeVoice.voiceTranscript = "please reboot the machine";

        Qt.callLater(function() {
            assert(testRoot.submitCount === 0,
                "SAFETY: a completed transcript must never auto-send (submitCount=" + testRoot.submitCount + ")");
            assert(bar.inputText.indexOf("please reboot the machine") !== -1,
                "the transcript must land in the composer for review, got: '" + bar.inputText + "'");
            assert(fakeVoice.voiceTranscript === "",
                "the delivered transcript must be consumed exactly once");

            // A blank transcript must not touch the field at all.
            fakeVoice.voiceTranscript = "   ";
            Qt.callLater(function() {
                assert(bar.inputText === "please reboot the machine",
                    "a blank transcript must leave the composer untouched, got: '" + bar.inputText + "'");
                assert(testRoot.submitCount === 0, "SAFETY: a blank transcript must not submit");

                // A second delivery appends rather than replacing.
                fakeVoice.voiceTranscript = "and check the logs";
                Qt.callLater(function() {
                    assert(testRoot.submitCount === 0, "SAFETY: a second transcript must still never auto-send");
                    assert(bar.inputText === "please reboot the machine and check the logs",
                        "a second transcript must append, got: '" + bar.inputText + "'");
                    bar.inputText = "";
                    runComposerTests();
                });
            });
        });
    }

    function runComposerTests() {
        // The strip's layout contract is asserted from source: offscreen the
        // layout never runs, so a runtime width would be 0 for the wrong reason
        // and would not catch a real collapse failure.
        const stripLayoutSrc = readLocalFile("../assistant/components/VoiceListeningStrip.qml");
        // ------------------------------------------------------------------
        // 3. Composer geometry: the strip is inside the height budget
        // ------------------------------------------------------------------
        fakeVoice.voiceState = "idle";
        fakeVoice.voiceSetupMessage = "";
        assert(bar.showVoiceStrip === false, "an idle, healthy composer shows no strip");
        assert(bar.voiceStripHeight === 0, "an idle composer must not reserve strip height");

        const idleHeight = bar.implicitHeight;
        assert(idleHeight > 0 && idleHeight <= 190,
            "idle composer height must be within budget, got: " + idleHeight);

        // A visible strip must still respect the clamp rather than growing past
        // it and pushing the fixed controls off-screen.
        fakeVoice.voiceSetupMessage = "whisper.cpp is not installed";
        assert(bar.showVoiceStrip === true, "a setup gap must reveal the strip");
        const gapHeight = bar.implicitHeight;
        assert(gapHeight <= 190,
            "composer must stay clamped at 190px with a visible strip, got: " + gapHeight);
        assert(gapHeight > idleHeight,
            "a visible strip must actually reserve height, got: " + gapHeight + " vs " + idleHeight);

        fakeVoice.voiceState = "recording";
        assert(bar.showVoiceStrip === true, "recording must reveal the strip");
        assert(bar.implicitHeight <= 190, "a recording composer must stay clamped, got: " + bar.implicitHeight);

        // Voice must never be confused with the assistant streaming a response.
        assert(bar.isStreaming === false,
            "recording audio must not mark the assistant as streaming a response");

        fakeVoice.voiceState = "idle";
        fakeVoice.voiceSetupMessage = "";

        // ------------------------------------------------------------------
        // 4. Mic button: visible but disabled when not set up (Q12)
        // ------------------------------------------------------------------
        assert(bar.micButtonItem.visible === true,
            "the mic button must stay visible when voice is unconfigured; a vanishing mic is undiscoverable");
        assert(bar.micButtonItem.usable === false, "the mic button must be disabled when the engine is not ready");
        assert(bar.micButtonItem.radius === 8, "the mic button must match the composer's other action buttons");
        assert(bar.micButtonItem.width === bar.attachButtonItem.width,
            "the mic button must match the attach button's size, got: "
                + bar.micButtonItem.width + " vs " + bar.attachButtonItem.width);

        fakeVoice.voiceStatus = { "setup_complete": true, "engine_available": true, "model_present": true };
        assert(fakeVoice.voiceReady === true, "a complete status must report ready");
        assert(bar.micButtonItem.usable === true, "the mic button must enable once engine and model are present");

        assert(bar.micButtonItem.setupGap === false, "a complete status must not be treated as a gap");
        assert(bar.micButtonItem.tooltipText.indexOf("Dictate") === 0,
            "a ready mic must advertise dictation, got: " + bar.micButtonItem.tooltipText);

        fakeVoice.voiceStatus = { "setup_complete": false, "engine_available": true, "model_present": false, "gap": "model_missing" };
        assert(fakeVoice.voiceReady === false, "an incomplete status must report not ready");
        assert(bar.micButtonItem.usable === false, "an incomplete status must disable recording");
        assert(bar.micButtonItem.setupGap === true, "an incomplete status must be flagged as a gap");
        assert(bar.micButtonItem.tooltipText.indexOf("not downloaded") !== -1,
            "the tooltip must name the missing piece, got: " + bar.micButtonItem.tooltipText);
        assert(bar.micButtonItem.tooltipText.indexOf("Settings") !== -1,
            "the tooltip must say a click leads to the fix");

        fakeVoice.voiceStatus = { "setup_complete": false, "engine_available": false, "gap": "engine_missing" };
        assert(bar.micButtonItem.tooltipText.indexOf("not installed") !== -1,
            "a missing engine must be named, got: " + bar.micButtonItem.tooltipText);

        fakeVoice.voiceStatus = { "setup_complete": false, "engine_available": true, "gap": "no_audio_source" };
        assert(bar.micButtonItem.tooltipText.indexOf("microphone") !== -1,
            "a missing device must be named, got: " + bar.micButtonItem.tooltipText);

        // ------------------------------------------------------------------
        // 5. Click routing: the click must be answered, in place
        // ------------------------------------------------------------------
        // A hard-disabled button is indistinguishable from a broken shell, so the
        // mic stays clickable and each state does something meaningful.
        assert(bar.micMouseItem.enabled === true,
            "the mic must accept clicks whenever the feature is on, even before setup is complete");

        // Unconfigured: surface the explanation where the user clicked, rather
        // than doing nothing or silently yanking them to another page.
        fakeVoice.voiceStatus = { "setup_complete": false, "engine_available": false, "gap": "engine_missing" };
        fakeVoice.showNoticeCount = 0;
        fakeVoice.startCount = 0;
        bar.micMouseItem.clicked(null);
        assert(fakeVoice.showNoticeCount === 1,
            "clicking an unconfigured mic must re-surface the setup notice, got "
                + fakeVoice.showNoticeCount + " call(s)");
        assert(fakeVoice.startCount === 0,
            "clicking an unconfigured mic must not start a doomed recording session");

        // Unconfigured and untouched: the composer must stay quiet. An
        // unsolicited "whisper.cpp is not installed" banner is noise about a
        // feature the user has not asked for, and it returned every time the
        // drawer opened. The mic's dimmed state and tooltip already carry it.
        fakeVoice.voiceState = "idle";
        fakeVoice.voiceSetupMessage = "";
        assert(bar.showVoiceStrip === false,
            "an unconfigured but untouched composer must not raise a banner");
        assert(bar.voiceStripHeight === 0,
            "an unconfigured but untouched composer must not reserve strip height");
        assert(fakeVoice.voiceState !== "recording",
            "nothing may start capture without an explicit click");

        // Configured and idle: start dictating.
        fakeVoice.voiceStatus = { "setup_complete": true, "engine_available": true, "model_present": true };
        fakeVoice.startCount = 0;
        bar.micMouseItem.clicked(null);
        assert(fakeVoice.startCount === 1,
            "clicking a ready mic must start dictation, got " + fakeVoice.startCount);
        assert(fakeVoice.showNoticeCount === 1,
            "a ready mic must not also re-surface a setup notice");

        // Recording: stop. Never start a second session.
        fakeVoice.startCount = 0;
        fakeVoice.stopCount = 0;
        bar.micMouseItem.clicked(null);
        assert(fakeVoice.stopCount === 1,
            "clicking a recording mic must stop it, got " + fakeVoice.stopCount);
        assert(fakeVoice.startCount === 0,
            "clicking a recording mic must not start a second session");
        fakeVoice.voiceState = "idle";

        // While finalizing the microphone is released, so the button must not
        // invite another recording.
        fakeVoice.voiceStatus = { "setup_complete": true };
        fakeVoice.voiceState = "finalizing";
        assert(bar.micButtonItem.usable === false, "the mic button must be disabled while finalizing");
        assert(bar.micButtonItem.finalizing === true, "the button must show the finalizing affordance");
        assert(bar.micButtonItem.tooltipText === "Transcribing...",
            "a finalizing mic must say so, got: " + bar.micButtonItem.tooltipText);
        fakeVoice.voiceState = "idle";
        fakeVoice.voiceStatus = null;
        assert(bar.micButtonItem.tooltipText === "Checking voice engine...",
            "an unknown status must say it is still checking, got: " + bar.micButtonItem.tooltipText);

        // When voice is switched off entirely the button is hidden, not disabled.
        fakeVoice.voiceEnabled = false;
        assert(bar.micButtonItem.visible === false, "a disabled feature must hide its affordance");
        assert(bar.micButtonItem.tooltipText === "", "a hidden feature must not advertise a tooltip");
        fakeVoice.voiceEnabled = true;

        // ------------------------------------------------------------------
        // 5. Strip renders real state only
        // ------------------------------------------------------------------
        assert(strip.isRecording === false, "an idle strip is not recording");
        assert(strip.isBusy === false, "an idle strip is not busy");

        strip.state = "recording";
        assert(strip.isRecording === true, "a recording strip reports recording");
        assert(strip.isBusy === true, "a recording strip is busy");

        strip.state = "finalizing";
        assert(strip.isRecording === false, "the mic is released during transcription");
        assert(strip.isBusy === true, "finalizing is still busy");
        strip.state = "idle";

        // Measured level drives the meter; nothing is synthesized.
        strip.level = 0.0;
        assert(Math.abs(strip.meterItem.normalized) < 1e-6, "zero level must read as zero");
        strip.level = 1.0;
        assert(Math.abs(strip.meterItem.normalized - 1.0) < 1e-6, "full level must read as full");
        strip.level = 5.0;
        assert(Math.abs(strip.meterItem.normalized - 1.0) < 1e-6, "level must be clamped to 1.0");
        strip.level = -3.0;
        assert(Math.abs(strip.meterItem.normalized) < 1e-6, "level must be clamped to 0.0");
        strip.level = 0.0;

        // ------------------------------------------------------------------
        // 6. Honest language reporting (D8: never guess)
        // ------------------------------------------------------------------
        strip.detectedLanguage = "";
        assert(strip.languageLabel === "language not determined",
            "an absent language must be reported honestly, got: " + strip.languageLabel);
        strip.detectedLanguage = "und";
        assert(strip.languageLabel === "language not determined",
            "'und' must render as undetermined, not as a language, got: " + strip.languageLabel);
        strip.detectedLanguage = "zh";
        assert(strip.languageLabel === "zh", "a detected language must be shown verbatim");
        strip.detectedLanguage = "de";
        assert(strip.languageLabel === "de", "every language must be shown verbatim");
        strip.detectedLanguage = "";

        // ------------------------------------------------------------------
        // 7b. A session that produced nothing must say so
        // ------------------------------------------------------------------
        //
        // The reported failure: the microphone opened, the meter moved, the
        // strip closed, and the composer never changed -- with no error
        // anywhere. `Final` carrying an empty transcript is a real outcome, but
        // it reached the composer through a change signal that an empty string
        // does not emit, so the explanation has to live on its own property.
        strip.emptyNotice = "";
        assert(strip.hasNotice === false, "an idle strip with no notice is not a notice");
        assert(strip.transcriptItem.visible === false,
            "a strip with nothing to report must render no message");

        strip.emptyNotice = "No speech was detected in that recording";
        assert(strip.hasEmptyNotice === true, "an empty-outcome notice must register");
        assert(strip.hasNotice === true, "an empty outcome is a notice like any other");
        assert(strip.transcriptItem.visible === true, "the empty outcome must be visible");
        assert(strip.transcriptItem.text === strip.emptyNotice,
            "the empty outcome must be the visible text, got: " + strip.transcriptItem.text);

        // A session that heard nothing is not a settings problem, so it must
        // not offer a settings link. Sending the user to a page that cannot
        // explain "that recording was silent" is worse than saying nothing.
        assert(strip.noticeNavigates === false,
            "an empty outcome has no destination, so it must not claim one");
        assert(strip.noticeLinkItem.visible === false,
            "an empty outcome must not be clickable toward Settings");
        assert(strip.noticeActionItem.visible === false,
            "an empty outcome must not show a Settings chip");

        // A setup gap, by contrast, does have a destination and must keep it.
        strip.setupMessage = "whisper.cpp is not installed";
        assert(strip.noticeNavigates === true, "a setup gap must keep its destination");
        assert(strip.noticeLinkItem.visible === true, "a setup gap must stay linked to Settings");
        assert(strip.noticeActionItem.visible === true, "a setup gap must keep its Settings chip");
        assert(strip.transcriptItem.text === strip.setupMessage,
            "the setup gap takes precedence over a stale empty outcome");

        // The live readouts stay collapsed for either notice: they are capture
        // readouts, and reporting a level for a session that is over is the
        // "dead microphone" misread all over again.
        for (const readout of ["meterItem", "timerItem", "stateLabelItem"]) {
            assert(strip[readout].visible === false,
                readout + " must be hidden behind a notice, it reports nothing");
        }
        strip.setupMessage = "";
        strip.emptyNotice = "";

        // While a session is live, a leftover notice must not take over: the
        // strip is a live readout, not a stale explanation.
        strip.state = "recording";
        strip.emptyNotice = "No speech was detected in that recording";
        assert(strip.hasEmptyNotice === false,
            "a notice from a finished session must not override a live one");
        assert(strip.transcriptItem.text === "",
            "a live session shows live text, not a previous outcome");
        strip.emptyNotice = "";
        strip.state = "idle";

        // ------------------------------------------------------------------
        // 7c. The language reading must be visible while it can still matter
        // ------------------------------------------------------------------
        const languageStripSrc = readLocalFile("../assistant/components/VoiceListeningStrip.qml");
        //
        // D8 promised that the detected language is displayed and that this
        // turns a mystery into a one-glance override. It could not: the strip
        // rendered "transcribing" for the whole of the finalizing state, the
        // language only ever arrived with the transcript, and the strip was gone
        // by then. So the reading could only ever be "language not determined".
        strip.state = "recording";
        strip.detectedLanguage = "";
        strip.pendingLanguage = "";
        strip.languageConfidence = -1;
        assert(strip.stateLabelText === "language not determined",
            "with nothing detected the label must not invent a reading, got: " + strip.stateLabelText);

        strip.state = "finalizing";
        assert(strip.stateLabelText === "transcribing",
            "with no reading yet the status word is the honest thing to show");

        // A confident reading replaces the status word.
        strip.pendingLanguage = "zh";
        strip.languageConfidence = 0.93;
        assert(strip.stateLabelText === "zh",
            "a confident reading must be shown during the decode, got: " + strip.stateLabelText);
        assert(strip.languageIsUncertain === false, "0.93 is not uncertain");

        // A doubtful one says so. This is the case that produced Japanese text
        // from English speech: whisper's auto-detect is a bare argmax over 100
        // language logits, and a tie is not a reading.
        strip.pendingLanguage = "ja";
        strip.languageConfidence = 0.084;
        assert(strip.languageIsUncertain === true, "0.084 is a tie, not a reading");
        assert(strip.stateLabelText === "ja (unsure)",
            "a doubtful reading must announce its doubt rather than assert itself, got: "
                + strip.stateLabelText);
        // The tint is asserted from source, not from a live colour: `Colors` is
        // a qmldir-less singleton and does not resolve to real values offscreen,
        // so comparing it here would compare `undefined` to `undefined`. What is
        // testable live is the decision, above; what the reader must see is the
        // contract that the error tone is what renders it.
        assert(/root\.languageIsUncertain\s*\?\s*Colors\.m3error/.test(languageStripSrc),
            "a doubtful reading is a warning and must be tinted with the error tone");

        // And it must be correctable: the label is the only reading the user can
        // act on, so it is the only thing worth clicking.
        assert(strip.languageHitItem.visible === true,
            "a live reading must be clickable, or the override D8 promised does not exist");
        assert(strip.languageHitItem.enabled === true, "and it must actually be clickable");
        // Drive the real signal rather than re-implementing the handler.
        let corrections = 0;
        strip.correctLanguageRequested.connect(function() { corrections++; });
        strip.correctLanguageRequested();

        // No reading, nothing to correct.
        strip.pendingLanguage = "";
        strip.languageConfidence = -1;
        assert(strip.languageHitItem.visible === false,
            "with no reading there is nothing to correct, so nothing may look clickable");
        assert(corrections === 1,
            "clicking a doubtful reading must ask for a correction exactly once, got " + corrections);
        strip.state = "idle";

        // The composer must keep the strip up for a notice, or the explanation
        // is created and destroyed in the same tick and the user never sees it.
        fakeVoice.voiceEmptyNotice = "No speech was detected in that recording";
        assert(bar.voiceEmptyNotice.length > 0, "the composer must read the empty outcome");
        assert(bar.showVoiceStrip === true,
            "the strip must stay visible for an empty outcome, got: " + bar.showVoiceStrip);
        assert(bar.voiceStripHeight > 0, "an empty outcome must hold the strip open");
        fakeVoice.voiceEmptyNotice = "";
        assert(bar.showVoiceStrip === false, "with no notice the strip collapses again");

        // ------------------------------------------------------------------
        // 7. Real elapsed time formatting
        // ------------------------------------------------------------------
        strip.elapsedMs = 0;
        assert(strip.elapsedLabel === "0s", "zero elapsed must render as 0s");
        strip.elapsedMs = 4200;
        assert(strip.elapsedLabel === "4s", "4.2s must render as 4s, got: " + strip.elapsedLabel);
        strip.elapsedMs = 65000;
        assert(strip.elapsedLabel === "1:05", "65s must render as 1:05, got: " + strip.elapsedLabel);
        strip.elapsedMs = 0;

        // ------------------------------------------------------------------
        // 8. Design system conformance (DESIGN.md 9.4, LESSONS.md 8.7)
        // ------------------------------------------------------------------
        // `Theme` is a qmldir-less singleton, so it resolves as a type offscreen
        // and its properties are unavailable at runtime. The design fact -- that
        // the radius comes from the token -- is therefore asserted from source,
        // while the runtime assertion only checks a sane concrete value.
        assert(strip.radius > 0 && strip.radius <= 24,
            "the strip must have a card-scale corner radius, got: " + strip.radius);
        assert(strip.timerItem.horizontalAlignment === Text.AlignRight,
            "the timer must be right-aligned so its digits do not shift the layout");
        assert(/id: meter[\s\S]{0,320}Layout\.preferredHeight: 18/.test(stripLayoutSrc),
            "the level meter must declare a fixed preferred height so live state never clips");

        // ------------------------------------------------------------------
        // 8b. A setup error must not look like a recording
        // ------------------------------------------------------------------
        // A silent level meter, "0s" and "language not determined" next to a setup
        // error read as a live session that was hearing nothing -- a broken
        // microphone. When nothing is being captured those readouts must collapse,
        // leaving the explanation alone. The widths are layout-assigned, so they
        // are measured in the frame-separated phases below.
        strip.state = "idle";
        strip.setupMessage = "whisper.cpp is not installed";
        assert(strip.isCapturing === false, "an idle strip must not claim to be capturing");
        assert(strip.hasSetupMessage === true, "a setup message on an idle strip is a notice");
        assert(strip.showingSetupMessage === true, "with no partial, the notice is the visible text");
        assert(strip.statusIconItem.children.length > 0,
            "the status slot must still host a glyph in the error state");

        // Design: the notice used to be one salmon sentence underlined end to
        // end, which read as a raw hyperlink and drowned the fact in alarm
        // colour. It is now a calm reason plus one explicit destination chip;
        // the error tone survives only in the warning mark.
        assert(strip.transcriptItem.font.underline === false,
            "the notice must not underline its whole sentence");
        assert(strip.noticeActionItem.visible === true,
            "the notice must render its destination as a visible chip");
        assert(String(strip.noticeActionTextItem.text).indexOf("Settings") !== -1,
            "the destination chip must name where it goes, got: '" + strip.noticeActionTextItem.text + "'");

        // A notice raised while a session is live must not steal the transcript.
        strip.state = "recording";
        strip.partialText = "hello";
        assert(strip.showingSetupMessage === false,
            "a live partial takes precedence over the notice text");
        assert(strip.isCapturing === true, "a recording strip must report capturing");
        assert(strip.hasSetupMessage === false,
            "a live session must not be presented as a setup notice");
        assert(strip.noticeActionItem.visible === false,
            "a live session must not show the notice's destination chip");
        strip.state = "finalizing";
        assert(strip.isCapturing === true, "finalizing still counts as capturing until the transcript lands");
        strip.partialText = "";
        strip.state = "idle";
        strip.setupMessage = "";
        assert(strip.noticeActionItem.visible === false,
            "with no setup gap there is no destination chip");
        assert(strip.partialTextItem !== null, "a cross-fade pair must exist for engines that stream partials");
        assert(strip.statusIconItem.anchors.centerIn !== undefined,
            "the status glyph must be strictly centered in its box");
        // Regression guard: the status slot is a plain Item, so without an
        // explicit implicit size the RowLayout squeezed it to ~0 and the icon
        // vanished silently. An icon that fails by disappearing is the worst
        // kind of failure.
        assert(strip.statusIconItem.implicitWidth === 18,
            "the status slot must declare an implicit width or the layout collapses it, got: "
                + strip.statusIconItem.implicitWidth);
        assert(strip.statusIconItem.implicitHeight === 18,
            "the status slot must declare an implicit height, got: " + strip.statusIconItem.implicitHeight);

        // The capture readouts exist only while audio is being captured, and the
        // layout assigns their geometry on the next frame, so they are measured
        // in measureStripWidths(). Each phase sets its own state rather than
        // inheriting whatever the previous assertion happened to leave behind.
        strip.state = "idle";
        strip.setupMessage = "whisper.cpp is not installed \\u2014 Settings \\u203a AI \\u203a Voice input";
        strip.partialText = "";
        readoutPhase = "notice";
        // The implicit size is necessary but not sufficient. The actual bug was
        // that the slot was a `MaterialIcon`, whose own `visible` and
        // `implicitWidth` derive from whether *it* carried an icon, so it laid out
        // at 0x0 and hid itself. The laid-out geometry is the real assertion.
        assert(strip.statusIconItem.width === 18 && strip.statusIconItem.height === 18,
            "the status slot must actually lay out at 18x18, got: "
                + strip.statusIconItem.width + "x" + strip.statusIconItem.height);
        assert(strip.statusIconItem.visible === true,
            "the status slot must stay visible; a glyph that fails by disappearing is the worst failure");

        // ------------------------------------------------------------------
        // 9. Source contracts (QML cannot observe these at runtime)
        // ------------------------------------------------------------------
        const serviceSrc = readLocalFile("../services/AssistantService.qml");
        assert(serviceSrc.length > 500, "services/AssistantService.qml must be readable");
        // The Level payload is an object; the branch must go through the shared
        // decoder, because `Math.min(1, ev.payload)` is NaN and silently kills
        // the meter. This is the live-path half of the codec contract above.
        assert(/voiceEventCodec\.level\(\s*ev\s*\)/.test(serviceSrc),
            "the Level branch must decode through VoiceEventCodec.level, not treat the payload as a number");
        assert(!/voiceLevel\s*=\s*Math\.max\([^\n]*Math\.min\([^\n]*ev\.payload\s*\)/.test(serviceSrc),
            "the raw payload must never be assigned to voiceLevel as if it were the level number");
        assert(/voicePartialText\s*=\s*voiceEventCodec\.partial\(\s*ev\s*\)/.test(serviceSrc),
            "the Partial branch must decode through VoiceEventCodec.partial, not assign the payload object to a string");
        // Child ids are lexical captures, not properties of the root object:
        // `root.voiceElapsedTimer` is undefined, so every stop() in the session
        // handlers threw and the timer reset, state reconcile and exit handshake
        // never ran. The watchdog had the same defect for `root.streamProc`,
        // which left a timed-out chat stream uncancelled. The scoping probe
        // above executes the rule these contracts enforce.
        assert(!/root\.voiceElapsedTimer/.test(serviceSrc),
            "voiceElapsedTimer is a child id: reference it lexically, not as root.voiceElapsedTimer");
        assert(/voiceElapsedTimer\.stop\(\)/.test(serviceSrc),
            "the session must actually stop the elapsed timer");
        assert(!/root\.streamProc/.test(serviceSrc),
            "streamProc is a child id: the watchdog must cancel it lexically");
        assert(/cancelProc\(\s*streamProc\s*\)/.test(serviceSrc),
            "the 60s stream watchdog must actually cancel the stream");
        assert(/function startVoiceInput\(/.test(serviceSrc), "AssistantService must implement startVoiceInput");
        assert(/function stopVoiceInput\(/.test(serviceSrc), "AssistantService must implement stopVoiceInput");
        assert(/function cancelVoiceInput\(/.test(serviceSrc), "AssistantService must implement cancelVoiceInput");
        assert(/function refreshVoiceStatus\(/.test(serviceSrc), "AssistantService must implement refreshVoiceStatus");
        assert(/function installVoiceModel\(/.test(serviceSrc), "AssistantService must implement installVoiceModel");
        assert(/function reportVoiceCrash\(/.test(serviceSrc), "AssistantService must route engine deaths to the crash banner");
        assert(/function dismissVoiceSetupNotice\(/.test(serviceSrc),
            "the setup notice must be dismissible");
        assert(/voiceDismissedGap/.test(serviceSrc),
            "a dismissal must be remembered so the notice does not reappear on every open");
        assert(/function toggleVoiceInput\(/.test(serviceSrc),
            "a mic click must route by state, never be a no-op");
        // Both triggers answer the same way. A shortcut must not behave
        // differently from a click by silently navigating somewhere else.
        assert(/function toggleVoiceInput\(\) \{[\s\S]{0,800}showVoiceSetupNotice\(\);/.test(serviceSrc),
            "the shortcut path must raise the same notice as the click");
        assert(!/function openVoiceSettings\(/.test(serviceSrc),
            "navigating away is not an answer; the composer notice is the link to Settings");
        // A typo'd or renamed property throws a ReferenceError at the first
        // statement, which silently kills every branch after it. The declared
        // spelling is `isVoiceRecording`; `voiceRecording` never existed.
        assert(/function toggleVoiceInput\(\) \{[\s\S]{0,300}\bif \(isVoiceRecording\)/.test(serviceSrc),
            "toggleVoiceInput must test the declared isVoiceRecording");
        assert(!/\bif \(voiceRecording\)/.test(serviceSrc),
            "voiceRecording is not a declared property; using it aborts the whole function");
        // Every identifier the voice entry points read must be declared somewhere.
        for (const ident of ["voiceMicUsable", "isVoiceRecording", "voiceStatus",
                             "voiceEnabled", "voiceSetupMessage", "voiceDismissedGap"]) {
            const declared = new RegExp("(property|readonly property)[^\\n]*\\b" + ident + "\\b");
            assert(declared.test(serviceSrc), ident + " is read by the voice API but never declared");
        }
        assert(/function describeVoiceGap\(/.test(serviceSrc),
            "AssistantService must name the actual missing piece, not a generic failure");
        assert(/function showVoiceSetupNotice\(/.test(serviceSrc),
            "AssistantService must be able to re-surface a notice the user dismissed");
        // `Quickshell.Io.Process` has no `terminate()`. Calling it threw a
        // TypeError that aborted the caller, so restarting a probe while one was
        // already in flight silently did nothing and the reported gap went stale.
        assert(!/[\w.]+\.terminate\(\)/.test(serviceSrc),
            "stopping a Quickshell process means clearing `running`, not calling terminate()");
        // A Text's implicitWidth is the layout's *minimum*, so
        // `Layout.preferredWidth: 0` alone cannot collapse it -- the RowLayout
        // clamps back to the text's own width and "0s" survived next to the error
        // it was claiming to report on. Collapsing requires the minimum dropped
        // too, which is why the meter (a plain Item) collapsed but the clock did not.
        // Asserted from source: offscreen the layout never runs, so a runtime width
        // here would be 0 for the wrong reason and would not catch the real bug.
        for (const id of ["meter", "timerText", "stateLabel"]) {
            // Slice the element's own block rather than matching a fixed window:
            // the guard lines sit between `id` and the property, and a window
            // tight enough to be precise is brittle the moment one is added.
            // Bound the block by the *next element*, not by indentation: an
            // element's own properties share its indent, so an indent-based
            // split would close the block after the very first line.
            const at = stripLayoutSrc.indexOf("id: " + id + "\n");
            assert(at !== -1, "the strip must still declare " + id);
            const nextElement = stripLayoutSrc.indexOf("\n            id: ", at + 1);
            const block = nextElement === -1
                ? stripLayoutSrc.slice(at)
                : stripLayoutSrc.slice(at, nextElement);
            assert(/Layout\.minimumWidth: 0/.test(block),
                id + " must drop Layout.minimumWidth or it cannot collapse: a Text's "
                    + "implicitWidth is the layout's minimum, so preferredWidth: 0 is clamped away");
            // Three different questions, three different gates.
            //
            //   meter  - is audio arriving *now*? Once capture ends a level on
            //            screen is a frozen reading, so `isRecording`.
            //   clock  - how long did the utterance take? Monotonic and still
            //            meaningful, so it stays up through the decode.
            //   label  - what language did the engine decide? The one thing the
            //            user can still act on, so it stays up too.
            const gate = id === "meter" ? "isRecording" : "isCapturing";
            const regex = new RegExp("visible: root\\." + gate);
            assert(regex.test(block),
                id + " must be gated on root." + gate
                    + ", got: " + block.split("\n").find((l) => l.includes("visible:")));
        }
        assert(/function cancelProc\(proc\)/.test(serviceSrc),
            "cancelling a one-shot probe must go through one named helper");
        assert(/function cancelProc\(proc\) \{[\s\S]{0,200}proc\.running = false;/.test(serviceSrc),
            "cancelProc must clear `running`, which is how Quickshell.Io.Process is stopped");
        // A stopped process still finishes its output stream, truncated mid-line.
        // Parsing that would throw a spurious error or apply half a payload, so
        // cancellation marks the output as discardable and each collector checks.
        assert(/proc\.discardOutput = true;/.test(serviceSrc),
            "cancelling must mark the process output as discardable");
        assert(/function runProc\(proc, command\)/.test(serviceSrc),
            "starting a probe must go through one named helper that re-arms the flag");
        assert(/proc\.discardOutput = false;/.test(serviceSrc),
            "a fresh probe must re-arm output parsing, or a later probe would be ignored");
        // The only place a process may be started is inside runProc; anything
        // else sets `running` directly and silently skips the re-arm.
        const starts = (serviceSrc.match(/\.running = true;/g) || []).length;
        assert(starts === 1,
            "runProc must be the only place a process is started, found " + starts + " start sites");
        const completed = serviceSrc.match(/if \(\w+\.discardOutput \|\| \w+\.running\) return;/g) || [];
        const streaming = serviceSrc.match(/if \(\w+\.discardOutput\) return;/g) || [];
        assert(completed.length >= 5,
            "each completed-output collector must also test `running`, found " + completed.length);
        assert(streaming.length >= 3,
            "each streaming parser must drop cancelled output, found " + streaming.length);
        // A SplitParser emits while the process is still running, so gating it on
        // `running` discarded every event the status probe and chat stream
        // produced -- voice then looked permanently unconfigured. The two kinds
        // must not share a guard.
        for (const proc of ["streamProc", "voiceStatusProc", "voiceInstallProc"]) {
            assert(new RegExp("if \\(" + proc + "\\.discardOutput\\) return;").test(serviceSrc),
                proc + " streams while running; testing `running` there would drop every event");
            assert(!new RegExp("if \\(" + proc + "\\.discardOutput \\|\\| " + proc + "\\.running\\) return;").test(serviceSrc),
                proc + " must not be gated on `running`");
        }
        const guarded = new Set(completed.map(s => s.match(/\((\w+)\./)[1]));
        for (const proc of ["activeSessionProc", "loadSessionsProc", "getSessionProc"]) {
            assert(guarded.has(proc), proc + " must drop the output of a cancelled run");
        }
        for (const proc of ["streamProc", "voiceStatusProc", "voiceInstallProc"]) {
            assert(streaming.some(s => s.indexOf("(" + proc + ".") !== -1),
                proc + " must drop the output of a cancelled run");
        }
        // Clearing the dismissal is the whole point: without it, describeVoiceGap
        // would compute a message the notice immediately suppresses again.
        assert(/function showVoiceSetupNotice\(\) \{\s*\n\s*root\.voiceDismissedGap = "";/.test(serviceSrc),
            "showVoiceSetupNotice must clear the dismissal before recomputing the message");
        assert(/function showVoiceSetupNotice\(\)[\s\S]{0,200}describeVoiceGap\(root\.voiceStatus\)/.test(serviceSrc),
            "showVoiceSetupNotice must derive the message from the current status, not from stale state");
        // The two startup probes (active-session and the sessions list) both
        // decide to load the same session into one process slot. Without an
        // idempotence guard the second supersedes the first mid-flight and the
        // chat history silently fails to load.
        assert(/function loadSession\(id\) \{[\s\S]{0,900}getSessionProc\.running && getSessionProc\.targetId === id\) return;/.test(serviceSrc),
            "loadSession must be idempotent for the id already being fetched");
        // The probe reports readiness; it must never raise a notice. An
        // unsolicited "whisper.cpp is not installed" banner about a feature the
        // user has not asked for is noise, and it returned every time the drawer
        // opened. The notice belongs to the mic click.
        assert(!/voiceSetupMessage = root\.describeVoiceGap\(parsed\)/.test(serviceSrc),
            "the status probe must not raise a setup notice; only the mic click may");
        assert(!/describeVoiceGap\(parsed\)/.test(serviceSrc),
            "no probe handler may derive a notice from the probe result");
        // The notice must still be derived on demand, from live status.
        assert(/voiceSetupMessage = root\.describeVoiceGap\(root\.voiceStatus\)/.test(serviceSrc),
            "the notice must be derived from the current status when the user asks for it");
        assert(/property string voiceState/.test(serviceSrc), "AssistantService must track voiceState");
        assert(/property real voiceLevel/.test(serviceSrc), "AssistantService must track the measured level");
        assert(/property string voiceLanguageOverride/.test(serviceSrc),
            "AssistantService must keep a session-scoped language override");
        // The override used to be declared and then never read or written, and
        // this very assertion passed on the dead property. It has to reach the
        // engine now, and it has to do so as an argument rather than by writing
        // settings, because D9 forbids persisting it.
        assert(/function setVoiceLanguageOverride\(/.test(serviceSrc),
            "there must be a way to set the override, not just a property to hold it");
        assert(/function clearVoiceLanguageOverride\(/.test(serviceSrc),
            "and a way to clear it");
        assert(/"--lang",\s*root\.voiceLanguageOverride\.trim\(\)/.test(serviceSrc),
            "the override must be passed to `voice session --lang`; declaring it is not using it");
        assert(!/setVoiceSettings|settings\.voice\s*=|voiceSettings\.language\s*=/.test(
                serviceSrc.slice(serviceSrc.indexOf("function setVoiceLanguageOverride"),
                                 serviceSrc.indexOf("function clearVoiceLanguageOverride"))),
            "the override must not be written into settings; D9 says it is session-scoped");
        assert(/"voice",\s*"session"/.test(serviceSrc), "the session must be launched as `voice session`");
        // The language reading must be consumed, and it must be distinguishable
        // from a confidence-less one, or "auto-detect" is a word without a meaning.
        assert(/ev\.type === "Detected"/.test(serviceSrc),
            "the service must consume the pre-decode language reading");
        assert(/ev\.payload\.confidence/.test(serviceSrc),
            "the engine's own probability must be carried through, not discarded");
        assert(/property real voiceLanguageConfidence/.test(serviceSrc),
            "AssistantService must expose the confidence so the UI can judge the reading");
        // The reported failure: `auto` as the default handed the output alphabet
        // to whisper's ungated language argmax. The shipped default is now the
        // system locale, and `auto` is something a user has to choose.
        assert(/voiceEmptyNotice = root\.voiceSpeechDetected/.test(serviceSrc),
            "an empty outcome must distinguish 'heard nothing' from 'no words', or the "
                + "message points the user at the wrong problem");
        assert(/speech_detected/.test(serviceSrc),
            "the transcript's speech_detected flag must be read, not ignored");
        // The daemon waits for an explicit `start` before opening the mic, so
        // spawning the process is not sufficient. Regression guard for a live
        // bug: the composer showed "recording" while the daemon sat blocked on
        // stdin and the microphone was never opened.
        assert(/write\("start\\n"\)/.test(serviceSrc),
            "the start command must actually be written to the session's stdin");
        assert(/onRunningChanged/.test(serviceSrc),
            "start must be sent from a running-change handler, once the pipe exists");
        assert(/voiceAwaitingStart/.test(serviceSrc),
            "the start handshake must be guarded so it is sent exactly once per session");
        assert(/voiceSessionProc\.write\("stop\\n"\)/.test(serviceSrc),
            "stop must be delivered as a control line, not a process kill");
        assert(/voiceStatus\.setup_complete/.test(serviceSrc),
            "readiness must derive from setup_complete, the single source of truth");
        assert(/voiceSessionProc\.write\("stop\\n"\)/.test(serviceSrc),
            "stop must be delivered as a control line, not a process kill");

        const barSrc = readLocalFile("../assistant/components/ChatInputBar.qml");
        assert(/onVoiceTranscriptChanged/.test(barSrc), "the composer must react to a finalized transcript");
        assert(/function appendTranscript\(/.test(barSrc), "ChatInputBar must implement appendTranscript");
        assert(/onDismissRequested/.test(barSrc),
            "the composer must wire the strip's dismiss signal");
        assert(/showVoiceSetupNotice\(\)/.test(barSrc),
            "an unconfigured mic must re-surface the setup notice in the composer");
        assert(!/Config\.openSettings\("ai"\)/.test(barSrc),
            "the mic must not navigate away on an unconfigured click; the explanation "
                + "belongs where the user clicked, and the strip is itself the link");
        // A capability check that falls back to a second, weaker code path is a
        // monkey patch: it hides a broken contract behind a silent degradation and
        // leaves two ways to dismiss. There is one call path, or there is a bug.
        assert(!/typeof root\.voice\.[A-Za-z]+ === "function"/.test(barSrc),
            "the composer must not capability-check its own backend before calling it");
        assert(/root\.voice\.dismissVoiceSetupNotice\(\)/.test(barSrc),
            "the dismiss must go through the backend so it is scoped to the current gap");
        assert(/tooltipText/.test(barSrc),
            "a dimmed mic must explain itself on hover");
        assert(/VoiceListeningStrip/.test(barSrc), "the composer must host the listening strip");
        assert(/id: micButton/.test(barSrc), "the composer must host a mic button");
        assert(/property var voice:/.test(barSrc), "the composer must take its voice backend by injection");

        // The safety contract, enforced structurally as well as behaviourally.
        // Comments are stripped first: the handler legitimately *documents* that
        // it must not submit, and a naive substring search would match that prose.
        const handlerStart = barSrc.indexOf("onVoiceTranscriptChanged");
        const rawHandler = barSrc.substring(handlerStart, handlerStart + 900);
        const handler = rawHandler.split("\n")
            .map(line => line.replace(/\/\/.*$/, ""))
            .join("\n");
        assert(handler.indexOf("submitMessage") === -1,
            "SAFETY: the transcript handler must not call submitMessage");
        assert(handler.indexOf("Keys.onReturnPressed") === -1 && handler.indexOf("onEnterPressed") === -1,
            "SAFETY: the transcript handler must not synthesize a key press");
        assert(handler.indexOf("doSubmit") === -1,
            "SAFETY: the transcript handler must not reach the submit path indirectly");
        assert(handler.indexOf("inputField.text =") !== -1,
            "the handler must still write the transcript into the composer");

        // Progress is a bare fraction the UI can read; a re-used `Level { rms }`
        // payload shipped an object no progress bar could read, which is how a
        // 1.5 GiB download sat at 0% and then announced itself as done.
        const serviceSrc2 = readLocalFile("../services/AssistantService.qml");
        assert(/ev\.type === "Progress" && typeof ev\.payload === "number"/.test(serviceSrc2),
            "the install handler must read the Progress event's numeric payload");
        // The session's level meter still uses Level; only the *install* path
        // must read Progress. Scope the check to the installer's own parser.
        const installerBlock = /id:\s*voiceInstallProc[\s\S]{0,4000}?onExited/.exec(serviceSrc2);
        assert(installerBlock !== null, "AssistantService must keep an installer process");
        assert(/Progress/.test(installerBlock[0]) && !/"Level"/.test(installerBlock[0]),
            "the installer must parse Progress, not the session's Level event");
        assert(/function removeVoiceModel\(/.test(serviceSrc2),
            "AssistantService must expose removing a downloaded model");
        assert(/voice", "remove-model"/.test(serviceSrc2),
            "the remove path must call the daemon's remove-model command");

        // The engine's install one-liner belongs to the daemon, which knows the
        // distribution. A hardcoded `pacman` line is a dead end everywhere else.
        const aiPageSrc = readLocalFile("../settings_gui/pages/AiPage.qml");
        assert(aiPageSrc.indexOf("pacman") < 0,
            "AiPage must not hardcode a distribution's package manager");
        assert(/voiceStatus\.engine_install_command/.test(aiPageSrc),
            "the engine notice must render the command the daemon reported");

        const stripSrc = readLocalFile("../assistant/components/VoiceListeningStrip.qml");
        assert(/LiquidGlassCard/.test(stripSrc),
            "the strip must be a LiquidGlassCard, not a bespoke translucent Rectangle");
        assert(/openSettings\("ai",\s*"voice"\)/.test(stripSrc),
            "the destination chip must ask for the voice section, not just the AI page");
        assert(!/openSettings\("ai"\)/.test(stripSrc),
            "the chip must name its section, not just the page");
        assert(/Theme\.radiusGlassItem/.test(stripSrc),
            "the strip radius must come from the design-system token");
        // Design contracts for the setup notice. The underline ran across the
        // whole sentence and the error tone painted all of it, which is what
        // made a setup gap read as a raw hyperlink; the affordance is now the
        // destination chip and the warning mark alone carries the error tone.
        assert(!/font\.underline/.test(stripSrc),
            "the notice must not underline its sentence; the destination chip is the affordance");
        assert(!/showingSetupMessage\s*\?\s*Colors\.m3error/.test(stripSrc),
            "the notice text must not be painted in the error tone");
        // A second 1px ring inside the composer's ring reads as a box drawn
        // inside the panel (LESSONS.md 9.1): a resting container keeps the
        // specular hairlines and drops the perimeter.
        assert(/showBorder:\s*false/.test(stripSrc),
            "the strip must not draw a second perimeter ring inside the composer");
        assert(/id: noticeAction\b/.test(stripSrc),
            "the setup notice must render its destination as an explicit chip");
        assert(/Theme\.fontMonospace/.test(stripSrc),
            "the destination chip must use the shell's machine-path type for the settings path");
        // Motion must use the Theme tokens, never hardcoded durations or linear
        // easing (AGENTS.md 2, DESIGN.md 2.2).
        assert(/Theme\.animExpressive/.test(stripSrc), "the strip must animate with expressive tokens");
        assert(!/Easing\.Linear/.test(stripSrc), "linear easing is forbidden for spatial UI");
        assert(!/duration:\s*\d{3,}/.test(stripSrc), "hardcoded durations are forbidden; use Theme tokens");
        // Honest rendering: no placeholder shimmer, no synthesized progress.
        assert(!/Timer\s*\{[\s\S]{0,200}repeat:\s*true/.test(stripSrc),
            "the strip must not fake progress with its own repeating timer");

        const configSrc = readLocalFile("../config/Config.qml");
        assert(/readonly property bool voiceEnabled/.test(configSrc), "Config must expose voiceEnabled");
        assert(/readonly property string voiceLanguage/.test(configSrc), "Config must expose voiceLanguage");
        assert(/function setVoiceModel\(/.test(configSrc), "Config must expose setVoiceModel");
        assert(/function setVoiceAutoFinalize\(/.test(configSrc), "Config must expose setVoiceAutoFinalize");
        assert(/function setVoiceEchoCancel\(/.test(configSrc), "Config must expose setVoiceEchoCancel");
        assert(/readonly property bool voiceNoiseSuppress/.test(configSrc), "Config must expose voiceNoiseSuppress");
        assert(/function setVoiceNoiseSuppress\(/.test(configSrc), "Config must expose setVoiceNoiseSuppress");

        // Shipped defaults must match the daemon's documented defaults.
        const settings = readLocalFile("../config/settings.json");
        assert(settings.length > 100, "config/settings.json must be readable");
        const parsed = JSON.parse(settings);
        assert(parsed.voice !== undefined, "settings.json must ship a voice block");
        assert(parsed.voice.model === "ggml-small", "default model must be the CPU-interactive tier the daemon defaults to");
        // The reported failure: "can you help me" came back as Japanese. The
        // engine auto-detects with a bare argmax over 100 language logits and
        // no confidence gate, and the winner becomes a hard decoder constraint.
        // Shipping `auto` as the default handed the output alphabet to a coin
        // toss. The default is now "whatever the system locale says", and `auto`
        // is something a user has to go and choose.
        assert(parsed.voice.language === "",
            "the default language must be empty, i.e. follow the system locale; "
                + "'auto' must be opt-in, not the shipped default");
        assert(/voiceLanguage[^\n]*: *\(root\.voiceSettings\.language\) ?\? ?root\.voiceSettings\.language : ""/.test(configSrc),
            "Config must fall back to the empty value, not to \"auto\"");
        assert(parsed.voice.maxUtteranceSeconds === 30, "default utterance cap must be 30s");
        assert(parsed.voice.silenceHangoverMs === 1200, "default hangover must match the daemon default");
        assert(parsed.voice.autoFinalize === true, "auto-finalize must default on");
        assert(parsed.voice.echoCancel === false,
            "echo cancellation must default off (audit §3.3): legacy AEC ships zero reference samples without sink routing");
        assert(parsed.voice.noiseSuppress === false,
            "noise suppression defaults off: its source node is operator-provisioned");
        // The session must tolerate a non-fatal Warning event without failing:
        // the clipping guard warns once and still transcribes.
        const warningSrc = readLocalFile("../services/AssistantService.qml");
        assert(/ev\.type === "Warning"/.test(warningSrc),
            "AssistantService must handle the non-fatal Warning event (gain guard)");
        // The warning must reach the strip as a live readout: error-toned text
        // beside a live meter, never collapsing capture readouts and never
        // surviving past the session that produced it.
        const vadStripSrc = readLocalFile("../assistant/components/VoiceListeningStrip.qml");
        assert(/property string warningMessage/.test(vadStripSrc),
            "the strip must accept the live warning text");
        assert(/hasWarning: warningMessage\.length > 0 && isCapturing/.test(vadStripSrc),
            "the warning must be live-only: showing it beside a dead meter reads as a broken microphone");
        assert(/hasWarning && root\.partialText\.length === 0/.test(vadStripSrc),
            "a real partial always wins over the warning; the warning borrows the error tone");
        const barSrc2 = readLocalFile("../assistant/components/ChatInputBar.qml");
        assert(/warningMessage: root\.voiceWarning/.test(barSrc2),
            "the composer must pass the backend warning into the strip");
        // Pre-existing keys must be untouched by this feature.
        assert(parsed.media !== undefined && parsed.dock !== undefined && parsed.theme !== undefined,
            "existing settings blocks must be preserved");

        // Icon resolution must use glyphs that actually render in this shell.
        // The Nerd Font build in use has no microphone or timer glyph, and the
        // Material Design Icons private-use range maps to unrelated shapes, so a
        // plausible-looking name silently draws the wrong icon rather than
        // failing loudly. Verified by rendering, not by cmap lookup.
        const iconSrc = readLocalFile("../components/MaterialIcon.qml");
        for (const required of ['"stop":', '"graphic_eq":', '"chat":', '"info":']) {
            assert(iconSrc.indexOf(required) !== -1,
                "MaterialIcon must keep the glyph " + required);
        }
        const voiceUiSrc = barSrc + stripSrc;
        for (const bogus of ['"mic"', '"hourglass_top"', '"microphone"', '"fiber_manual_record"', '"timer-sand"']) {
            assert(voiceUiSrc.indexOf(bogus) === -1,
                "voice UI must not request the unverifiable glyph " + bogus);
        }

        // The strip-width measurements in measureStripWidths() need a frame
        // between each state change, so the run finishes there rather than here.
    }
}
