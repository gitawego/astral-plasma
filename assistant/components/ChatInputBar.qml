import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "../../theme"
import "../../components"
import "../../services"

Rectangle {
    id: root

    property var stagedFiles: []
    property alias stagedImages: root.stagedFiles

    function isImageFile(path) {
        if (!path) return false;
        return /\.(png|jpg|jpeg|webp|svg|gif|bmp)$/i.test(path);
    }

    function getFileExtension(path) {
        if (!path) return "FILE";
        let parts = path.split(".");
        if (parts.length > 1) {
            return parts[parts.length - 1].toUpperCase().substring(0, 4);
        }
        return "FILE";
    }

    function getFileName(path) {
        if (!path) return "";
        let parts = path.split("/");
        return parts[parts.length - 1];
    }

    function stageFile(filePath) {
        if (!filePath) return;
        let p = String(filePath).trim();
        if (p.startsWith("file://")) p = p.substring(7);
        let copy = stagedFiles.slice();
        if (copy.indexOf(p) === -1) {
            copy.push(p);
            stagedFiles = copy;
        }
    }

    function stageImage(imgPath) {
        stageFile(imgPath);
    }

    function unstageFile(index) {
        let copy = stagedFiles.slice();
        copy.splice(index, 1);
        stagedFiles = copy;
    }

    function unstageImage(index) {
        unstageFile(index);
    }

    function openNativeFileDialog() {
        nativeFileDialog.open();
    }

    // Height budget. The listening strip is counted *inside* the clamp rather
    // than added on top, so a listening composer can never push the fixed
    // controls off-screen on a short display (AGENTS.md 7.2). The transcript
    // elides when the budget is tight; the meter and timer keep their size,
    // because those carry the live state.
    /**
     * The voice backend. Defaults to the AssistantService singleton, but is
     * injectable so the component's own gating logic is testable headlessly --
     * `services/` has no qmldir, so the singleton is only resolvable as a
     * registered type inside the running shell, not in an offscreen test.
     */
    property var voice: (typeof AssistantService !== "undefined") ? AssistantService : null

    readonly property bool voiceEnabled: voice !== null ? !!voice.voiceEnabled : false
    readonly property bool voiceRecording: voice !== null ? !!voice.isVoiceRecording : false
    readonly property bool voiceBusy: voice !== null ? !!voice.isVoiceBusy : false
    readonly property bool voiceReady: voice !== null ? !!voice.voiceReady : false
    readonly property bool voiceMicUsable: voice !== null ? !!voice.voiceMicUsable : false
    readonly property string voiceState: voice !== null ? voice.voiceState : "idle"
    readonly property string voiceSetupMessage: voice !== null ? (voice.voiceSetupMessage || "") : ""
    /**
     * Why the last session produced nothing.
     *
     * Kept beside the setup message rather than inside it, because the two send
     * the user to different places: a setup gap is fixed in Settings, whereas
     * "that recording heard nothing" is a fact about one recording and is
     * already over. Conflating them would send the user to a settings page
     * that cannot help.
     */
    readonly property string voiceEmptyNotice: voice !== null ? (voice.voiceEmptyNotice || "") : ""
    /** Non-fatal mid-capture warning (e.g. clipping); live-only, no dismiss. */
    readonly property string voiceWarning: voice !== null ? (voice.voiceWarning || "") : ""
    readonly property real voiceLevel: voice !== null ? (voice.voiceLevel || 0) : 0
    readonly property int voiceElapsedMs: voice !== null ? (voice.voiceElapsedMs || 0) : 0
    readonly property string voiceLanguage: voice !== null ? (voice.voiceLanguage || "") : ""
    /**
     * The language the in-flight session settled on, and how sure the engine
     * was. Both arrive before the transcript, so a wrong reading is correctable
     * while it still costs nothing but a click.
     */
    readonly property string voiceDetectedLanguage: voice !== null ? (voice.voiceDetectedLanguage || "") : ""
    readonly property real voiceLanguageConfidence: voice !== null ? (voice.voiceLanguageConfidence || -1) : -1
    readonly property string voicePartialText: voice !== null ? (voice.voicePartialText || "") : ""

    // The strip stays up for a notice as well as for a live session. Without
    // the notice term it vanished the instant `Final` arrived carrying no
    // words, which is exactly when the user needs an explanation.
    readonly property bool showVoiceStrip: voiceEnabled
        && (voiceBusy || voiceSetupMessage.length > 0 || voiceEmptyNotice.length > 0)
    readonly property int voiceStripHeight: showVoiceStrip ? 46 : 0

    implicitHeight: Math.min(
        190,
        Math.max(46, inputField.contentHeight + 20)
            + (stagedFiles.length > 0 ? 56 : 0)
            + root.voiceStripHeight
    )
    radius: 12
    color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.10, 0.11, 0.16, 0.65) : Qt.rgba(0.94, 0.95, 0.98, 0.70)
    border.width: 1
    border.color: inputField.activeFocus ? Colors.primary : Colors.glassBorderSpecular

    signal submitMessage(string text, var images)
    signal requestOpenImagePicker()

    function focusInput() {
        inputField.forceActiveFocus();
    }

    readonly property bool isStreaming: (typeof AssistantService !== "undefined") ? AssistantService.isStreaming : false
    readonly property bool showSkillPopup: inputField.text.startsWith("/") && !inputField.text.includes(" ")

    // Native System File Explorer (Non-Modal to avoid layer-shell input freezes)
    FileDialog {
        id: nativeFileDialog
        title: "Select Files to Attach"
        fileMode: FileDialog.OpenFiles
        modality: Qt.NonModal
        nameFilters: [
            "All files (*)",
            "Images (*.png *.jpg *.jpeg *.webp *.svg *.gif *.bmp)",
            "Code & Config (*.rs *.py *.js *.ts *.qml *.json *.toml *.yaml *.yml *.sh *.css *.html *.md *.txt)",
            "Documents (*.pdf *.csv *.log *.doc *.docx)"
        ]
        onAccepted: {
            for (let i = 0; i < selectedFiles.length; i++) {
                root.stageFile(selectedFiles[i]);
            }
        }
    }

    DropArea {
        anchors.fill: parent
        onDropped: drop => {
            if (drop.hasUrls) {
                for (let i = 0; i < drop.urls.length; i++) {
                    let u = drop.urls[i].toString();
                    if (u.startsWith("file://")) u = u.substring(7);
                    root.stageFile(u);
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 6

        // 1. Staged Files Thumbnail / Chip Strip (Visible when files are attached)
        Item {
            id: stagedStrip
            Layout.fillWidth: true
            implicitHeight: root.stagedFiles.length > 0 ? 50 : 0
            visible: root.stagedFiles.length > 0

            Flickable {
                anchors.fill: parent
                contentWidth: stagedRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: stagedRow
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: root.stagedFiles

                        delegate: Rectangle {
                            id: thumbCard
                            readonly property bool isImg: root.isImageFile(modelData)
                            width: isImg ? 48 : Math.min(180, Math.max(80, fileLabelRow.implicitWidth + 28))
                            height: 44
                            radius: 8
                            color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.12, 0.14, 0.20, 0.85) : Colors.glassCard
                            border.width: 1
                            border.color: Colors.glassBorderSpecular
                            clip: true

                            // Image thumbnail preview
                            Image {
                                visible: thumbCard.isImg
                                anchors.fill: parent
                                anchors.margins: 2
                                source: thumbCard.isImg ? (String(modelData).startsWith("file://") ? String(modelData) : ("file://" + String(modelData))) : ""
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                            }

                            // Non-image file badge with extension chip
                            RowLayout {
                                id: fileLabelRow
                                visible: !thumbCard.isImg
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 20
                                spacing: 6

                                Rectangle {
                                    implicitWidth: 26
                                    implicitHeight: 20
                                    radius: 4
                                    color: Qt.alpha(Colors.primary, 0.20)
                                    border.width: 1
                                    border.color: Qt.alpha(Colors.primary, 0.40)

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.getFileExtension(modelData)
                                        font.family: Theme.fontMonospace
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: Colors.primary
                                    }
                                }

                                Text {
                                    text: root.getFileName(modelData)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Colors.m3onSurface
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }

                            // Dismiss (x) button
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 3
                                width: 16
                                height: 16
                                radius: 8
                                color: Qt.rgba(0, 0, 0, 0.70)
                                z: 10

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    iconName: "close"
                                    size: 11
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.unstageFile(index)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 1b. Voice Listening Strip (Tier 2 liquid glass content card)
        Item {
            id: voiceStripHolder
            Layout.fillWidth: true
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            implicitHeight: root.voiceStripHeight
            visible: root.showVoiceStrip

            VoiceListeningStrip {
                id: voiceStrip
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.height - 2

                state: root.voiceState
                level: root.voiceLevel
                elapsedMs: root.voiceElapsedMs
                detectedLanguage: root.voiceLanguage
                pendingLanguage: root.voiceDetectedLanguage
                languageConfidence: root.voiceLanguageConfidence
                partialText: root.voicePartialText
                setupMessage: root.voiceSetupMessage
                emptyNotice: root.voiceEmptyNotice
                warningMessage: root.voiceWarning

                // One click from a doubtful reading to the place that changes
                // it. D8 promised a "one-glance override" and there was none;
                // this is the smallest honest version of it -- it does not
                // re-render the audio, it takes the user to the picker.
                onCorrectLanguageRequested: {
                    if (typeof Config !== "undefined" && typeof Config.openSettings === "function")
                        Config.openSettings("ai", "voice");
                }

                // Routed through the backend so the dismissal is scoped to the
                // current gap: a *different* problem later still surfaces.
                onDismissRequested: root.voice.dismissVoiceSetupNotice()
                onDismissEmptyRequested: root.voice.dismissVoiceEmptyNotice()

                // Spring entrance so the strip grows organically rather than
                // snapping, per DESIGN.md 2.
                y: 0
                Behavior on y {
                    NumberAnimation {
                        duration: Theme.animExpressiveFastSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveFastSpatial
                    }
                }
            }
        }

        // 2. Input Row
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            // Attachment Button (Native System File Uploader)
            Rectangle {
                id: attachButton
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                implicitWidth: 32
                implicitHeight: 32
                radius: 8
                scale: attachMouse.pressed ? 0.94 : (attachMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                color: attachMouse.containsMouse ? Colors.glassCardHover : "transparent"
                border.width: 1
                border.color: Colors.glassBorderSpecular

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: "attach_file"
                    size: 16
                    color: attachMouse.containsMouse ? Colors.primary : Colors.m3onSurfaceVariant
                }

                MouseArea {
                    id: attachMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.requestOpenImagePicker();
                    }
                }
            }


            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: inputField.implicitHeight
                clip: true

                TextEdit {
                    id: inputField
                    anchors.fill: parent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodySmall
                    color: Colors.m3onSurface
                    selectionColor: Colors.primary
                    selectedTextColor: Colors.m3onPrimary
                    wrapMode: TextEdit.Wrap
                    verticalAlignment: TextEdit.AlignVCenter

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !inputField.text && root.stagedImages.length === 0
                        opacity: inputField.activeFocus ? 0.6 : 0.9
                        text: "Ask Copilot, paste image, or type '/' for skills..."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontBodySmall
                        color: Colors.m3onSurfaceVariant
                    }

                    function doSubmit(event) {
                        if (event.modifiers & Qt.ShiftModifier) {
                            event.accepted = false;
                        } else {
                            event.accepted = true;
                            if (inputField.text.trim().length > 0 || root.stagedImages.length > 0) {
                                root.submitMessage(inputField.text, root.stagedImages);
                                inputField.text = "";
                                root.stagedImages = [];
                            }
                        }
                    }

                    Keys.onReturnPressed: function(event) { doSubmit(event); }
                    Keys.onEnterPressed: function(event) { doSubmit(event); }
                    Keys.onEscapePressed: {
                        if (typeof Config !== "undefined") Config.closeAssistant();
                    }

                    // Clipboard Paste (Ctrl+V) Image Ingestion
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                            if (typeof AssistantService !== "undefined" && typeof AssistantService.pasteClipboardImage === "function") {
                                AssistantService.pasteClipboardImage(function(path) {
                                    if (path && path.length > 0) {
                                        root.stageImage(path);
                                    }
                                });
                            }
                        }
                    }
                }
            }

            // Microphone Button
            //
            // Visible but disabled when voice is not set up. A mic icon that
            // simply disappears is undiscoverable: a user who never sees it
            // will never go looking for it in Settings.
            Rectangle {
                id: micButton
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                implicitWidth: 32
                implicitHeight: 32
                radius: 8

                readonly property bool serviceReady: root.voiceEnabled
                readonly property bool recording: root.voiceRecording
                readonly property bool finalizing: root.voiceState === "finalizing"
                readonly property bool usable: root.voiceMicUsable
                readonly property bool setupGap: root.voice !== null
                    && root.voice.voiceStatus !== null
                    && root.voice.voiceStatus.setup_complete === false

                /**
                 * Hover text. When voice is not ready it says what is missing and
                 * that a click opens the fix, so the button is never a dead
                 * control.
                 */
                readonly property string tooltipText: {
                    if (!serviceReady) return "";
                    if (recording) return "Stop dictation";
                    if (finalizing) return "Transcribing...";
                    if (usable) return "Dictate (click to record, then stop to transcribe)";
                    if (root.voice === null || root.voice.voiceStatus === null) return "Checking voice engine...";
                    const gap = root.voice.voiceStatus.gap;
                    if (gap === "engine_missing") return "whisper.cpp is not installed - click to open Settings > AI";
                    if (gap === "model_missing") return "Speech model not downloaded - click to open Settings > AI";
                    if (gap === "no_audio_source") return "No microphone found - click to open Settings > AI";
                    return "Voice input unavailable - click for details";
                }

                visible: serviceReady

                scale: micMouse.pressed ? 0.94 : (micMouse.containsMouse && usable ? 1.05 : 1.0)
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animExpressiveFastSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveFastSpatial
                    }
                }

                color: recording
                    ? (micMouse.containsMouse ? Qt.alpha(Colors.m3error, 0.35) : Qt.alpha(Colors.m3error, 0.20))
                    : (usable && micMouse.containsMouse ? Qt.alpha(Colors.primary, 0.18) : "transparent")

                border.width: 1
                border.color: recording
                    ? Colors.m3error
                    : (setupGap ? Qt.alpha(Colors.m3error, 0.45) : Colors.glassBorderSpecular)

                Behavior on color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }
                Behavior on border.color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }

                // Vector-drawn Lucide `mic-vocal`. The icon font has no
                // microphone glyph, and the Material Design Icons range resolved
                // to unrelated shapes rather than a missing-glyph box.
                MicVocalIcon {
                    id: micGlyph
                    anchors.centerIn: parent
                    visible: !micButton.recording
                    size: 16
                    color: micButton.usable ? Colors.primary : Colors.m3onSurfaceVariant
                    opacity: micButton.usable ? 1.0 : 0.5

                    Behavior on color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: micButton.recording
                    iconName: "stop"
                    size: 16
                    color: Colors.m3error
                }

                // Explains the state on hover. A dimmed icon with no explanation
                // is indistinguishable from a broken shell.
                Rectangle {
                    id: micTooltip
                    visible: micMouse.containsMouse && micButton.tooltipText.length > 0
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(260, tipLabel.implicitWidth + 18)
                    height: tipLabel.implicitHeight + 10
                    radius: Theme.radiusExtraSmall
                    color: (typeof Colors !== "undefined" && Colors.isDarkMode)
                        ? Qt.rgba(0.10, 0.12, 0.17, 0.95)
                        : Qt.rgba(0.96, 0.97, 1.0, 0.95)
                    border.width: 1
                    border.color: Colors.glassBorderSpecular
                    z: 400

                    Text {
                        id: tipLabel
                        anchors.centerIn: parent
                        width: Math.min(240, implicitWidth)
                        text: micButton.tooltipText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontLabelSmall
                        color: Colors.m3onSurface
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Honest state: a busy mic must not look clickable, and an
                // unconfigured one must lead somewhere useful rather than
                // silently swallowing the click.
                MouseArea {
                    id: micMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    // Enabled whenever the feature is on: ready toggles
                    // recording, unready opens the page that fixes the gap. A
                    // hard-disabled button is what made this look broken.
                    enabled: micButton.serviceReady
                    cursorShape: micButton.serviceReady ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (root.voice === null) return;
                        if (micButton.recording) {
                            root.voice.stopVoiceInput();
                        } else if (micButton.usable) {
                            root.voice.startVoiceInput();
                            inputField.forceActiveFocus();
                        } else {
                            // Not configured. Answer the click in place: the
                            // composer strip names the missing piece and links
                            // into the page that installs it. Jumping straight to
                            // Settings would move the user away from the
                            // explanation before they had read it.
                            root.voice.showVoiceSetupNotice();
                        }
                    }
                }
            }

            // Model Indicator Chip
            Rectangle {
                implicitHeight: 24
                implicitWidth: chipRow.implicitWidth + 12
                radius: 6
                color: Colors.glassCardHover
                border.width: 1
                border.color: Colors.glassBorderSpecular
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialIcon {
                        iconName: "memory"
                        size: 12
                        color: Colors.secondary
                    }

                    Text {
                        text: ((typeof AssistantService !== "undefined") ? AssistantService.selectedModelId : "") || "auto"
                        font.family: Theme.fontMonospace
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: Colors.m3onSurfaceVariant
                        elide: Text.ElideRight
                        Layout.maximumWidth: 110
                    }
                }
            }

            // Action Button: Send or Stop
            Rectangle {
                id: sendButton
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                implicitWidth: 32
                implicitHeight: 32
                radius: 8
                readonly property bool hasContent: inputField.text.trim().length > 0 || root.stagedImages.length > 0
                readonly property bool isStreaming: root.isStreaming

                scale: sendMouse.pressed ? 0.94 : (sendMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                color: isStreaming 
                    ? (sendMouse.containsMouse ? Qt.alpha(Colors.m3error, 0.35) : Qt.alpha(Colors.m3error, 0.20))
                    : (hasContent 
                        ? (sendMouse.containsMouse ? Qt.alpha(Colors.primary, 0.32) : Qt.alpha(Colors.primary, 0.18))
                        : (sendMouse.containsMouse ? Colors.glassCardHover : "transparent"))

                border.width: 1
                border.color: isStreaming 
                    ? Colors.m3error 
                    : (hasContent ? Colors.primary : Colors.glassBorderSpecular)

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                MaterialIcon {
                    anchors.centerIn: parent
                    iconName: sendButton.isStreaming ? "stop" : "send"
                    size: 16
                    color: sendButton.isStreaming 
                        ? Colors.m3error 
                        : (sendButton.hasContent 
                            ? Colors.primary 
                            : Colors.m3onSurfaceVariant)
                }

                MouseArea {
                    id: sendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (sendButton.isStreaming) {
                            if (typeof AssistantService !== "undefined") AssistantService.stopStreaming();
                        } else if (sendButton.hasContent) {
                            root.submitMessage(inputField.text, root.stagedImages);
                            inputField.text = "";
                            root.stagedImages = [];
                        } else {
                            inputField.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }

    // Dictation lands here, and nowhere else.
    //
    // The transcript is APPENDED to whatever the user has already typed and is
    // never submitted. Two reasons, both load-bearing:
    //   1. Data loss: a half-written prompt must survive a dictation result.
    //   2. Safety: a transcript becomes a prompt, a prompt can produce a
    //      ToolCallProposal for sudo/rm/systemctl, and assess_safety only shows
    //      a confirmation card. A recognition error must never reach a
    //      tool-execution gate unattended (docs/VOICE-INPUT-SPEC.md D5).
    Connections {
        target: root.voice

        function onVoiceTranscriptChanged() {
            const addition = root.voice ? root.voice.voiceTranscript : "";
            if (!addition || addition.trim().length === 0) {
                // Silence is not content: clear it without touching the field.
                if (root.voice) root.voice.voiceTranscript = "";
                return;
            }
            inputField.text = root.appendTranscript(inputField.text, addition);
            inputField.cursorPosition = inputField.text.length;
            if (root.voice) root.voice.voiceTranscript = "";
            // Deliberately no submitMessage() call here.
        }
    }

    /**
     * Appends a transcript without ever truncating typed text.
     *
     * Mirrors `domain::voice::append_transcript` so the QML and Rust sides agree
     * on the join semantics, including preserving a deliberate trailing newline.
     */
    function appendTranscript(existing, addition) {
        const extra = (addition || "").trim();
        if (extra.length === 0) return existing;
        const base = existing.replace(/\s+$/, "");
        if (base.length === 0) return extra;
        if (/\n$/.test(existing)) return base + "\n" + extra;
        return base + " " + extra;
    }

    property alias inputText: inputField.text
    readonly property alias micButtonItem: micButton
    // Exposed so the click routing can be exercised: emitting `clicked()` runs the
    // real onClicked handler rather than a re-implementation of it.
    readonly property alias micMouseItem: micMouse
    readonly property alias voiceStripItem: voiceStrip
    readonly property alias voiceStripHolderItem: voiceStripHolder
    readonly property alias attachButtonItem: attachButton
    readonly property alias sendButtonItem: sendButton

    // Skill Autocomplete Popup Modal
    Rectangle {
        id: skillPopup
        visible: root.showSkillPopup && filteredSkills.length > 0
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: Math.min(220, skillCol.implicitHeight + 16)
        radius: 10
        color: (typeof Colors !== "undefined" && Colors.isDarkMode) ? Qt.rgba(0.10, 0.11, 0.16, 0.85) : Qt.rgba(0.96, 0.97, 1.0, 0.90)
        border.width: 1
        border.color: Colors.glassBorderSpecular
        clip: true

        readonly property string query: inputField.text.substring(1).toLowerCase()
        readonly property var allSkills: {
            const src = (typeof AssistantService !== "undefined") ? AssistantService.discoveredSkills : [];
            // Guarded: the list is empty until the async skills scan lands, and a
            // null intermediate would throw on every keystroke of a "/".
            return Array.isArray(src) ? src : [];
        }
        readonly property var filteredSkills: {
            if (!query) return allSkills.slice(0, 5);
            return allSkills.filter(s => s.name.toLowerCase().includes(query) || s.description.toLowerCase().includes(query)).slice(0, 5);
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentHeight: skillCol.implicitHeight
            clip: true

            ColumnLayout {
                id: skillCol
                width: parent.width
                spacing: 4

                Repeater {
                    model: skillPopup.filteredSkills

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 6
                        color: skillMouse.containsMouse ? Qt.alpha(Colors.primary, 0.16) : "transparent"
                        border.width: skillMouse.containsMouse ? 1 : 0
                        border.color: skillMouse.containsMouse ? Qt.alpha(Colors.primary, 0.35) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            MaterialIcon {
                                iconName: "bolt"
                                size: 14
                                color: Colors.primary
                            }

                            Text {
                                text: "/" + modelData.name
                                font.family: Theme.fontMonospace
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: Colors.m3onSurface
                            }

                            Text {
                                text: modelData.description
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Colors.m3onSurfaceVariant
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: skillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                inputField.text = "/" + modelData.name + " ";
                                inputField.cursorPosition = inputField.text.length;
                                inputField.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }
    }
}
