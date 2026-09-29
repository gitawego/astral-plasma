import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../components"

/**
 * Live voice-capture strip shown above the chat composer.
 *
 * Design contract (see `docs/VOICE-INPUT-SPEC.md` §9):
 *
 *  - **Tier 2 content card.** Built from `LiquidGlassCard`, never a bespoke
 *    translucent `Rectangle`. A second load-bearing glass layer would extinguish
 *    the Tier 1 compositor blur beneath it and read as milky plastic.
 *  - **Renders only real state.** The meter is measured RMS from the PCM the
 *    microphone actually delivered, the timer is real elapsed time, and the
 *    language is what the engine reported. There is no placeholder shimmer and
 *    no synthesized progress, because `AGENTS.md` §4 forbids fabricating content.
 *    An undetermined language shows as such rather than being guessed.
 *  - **Partial text is optional.** `whisper-cli` streams nothing before the file
 *    is done, so a level-only strip is the correct rendering, not a degraded
 *    one. The dual-`Text` cross-fade is present for adapters that do stream.
 *  - **Never clips live state.** Under height pressure the transcript elides;
 *    the meter and timer keep their size, because those carry the live signal.
 */
LiquidGlassCard {
    id: root

    /// Engine-reported state: "idle" | "recording" | "finalizing" | "failed".
    property string state: "idle"

    /// Measured audio level in [0.0, 1.0], straight from the capture stream.
    property real level: 0.0

    /// Real elapsed capture time in milliseconds.
    property int elapsedMs: 0

    /// Engine-reported language tag, or "und" when detection was inconclusive.
    property string detectedLanguage: ""

    /**
     * The language the in-flight session settled on, reported before the
     * transcript exists.
     *
     * Separate from `detectedLanguage` because they appear at different times.
     * `detectedLanguage` arrives with the transcript, by which point the strip
     * is already closing; this one arrives while the decode is still running, so
     * it is the only reading a user can actually see and correct.
     */
    property string pendingLanguage: ""

    /// The engine's probability for `pendingLanguage`, or -1 when it gave none.
    property real languageConfidence: -1

    /**
     * Whether the reading is too weak to be acted on.
     *
     * A detection and a guess are both "the engine answered"; only the
     * confidence separates them. whisper spreads its probability across 100
     * candidates, so anything under about a third is a tie, and transcribing a
     * tie is what turned English speech into Japanese-looking text.
     */
    readonly property bool languageIsUncertain: languageConfidence >= 0
        && languageConfidence < 0.35

    /// Live partial text, when the engine actually streams one.
    property string partialText: ""

    /// Why the feature is unavailable, when it is.
    property string setupMessage: ""

    /**
     * Non-fatal session warning, when one fired mid-capture (e.g. input
     * clipping from saturated ALSA gain).
     *
     * Unlike `setupMessage`/`emptyNotice` this is a *live* readout: it only
     * ever exists while capturing, never collapses the meter/timer/language
     * (a warning beside a live meter is information; beside a dead one it
     * would read as a broken microphone), and needs no dismiss — the next
     * `start` clears it at the backend.
     */
    property string warningMessage: ""

    /**
     * Why a session that ran produced nothing, when it did.
     *
     * Distinct from `setupMessage` on purpose. A setup gap is a persistent
     * configuration problem with a fix in Settings; a session that heard
     * nothing is a one-off outcome of this recording, and pointing the user at
     * Settings for it would be a lie about where the answer is.
     *
     * It exists at all because the alternative is the failure this whole
     * feature must not have: the microphone opens, the level meter moves, the
     * strip closes, and the composer is untouched with no explanation. Silence
     * is an honest outcome (AGENTS.md §4) but it has to be *reported*.
     */
    property string emptyNotice: ""

    /**
     * Emitted when the user dismisses the setup notice.
     *
     * Owned by the caller rather than cleared locally, so the dismissal survives
     * the next readiness probe instead of reappearing on every drawer open.
     */
    signal dismissRequested()

    /**
     * Emitted when the user dismisses an empty-outcome notice.
     *
     * A separate signal rather than a shared one because the two notices have
     * opposite lifetimes. A setup gap persists until it is genuinely fixed, so
     * its dismissal is remembered. An empty outcome is a fact about one finished
     * recording and is stale the moment the next one starts, so clearing it is
     * trivial and remembering it would be wrong.
     */
    signal dismissEmptyRequested()

    /**
     * Emitted when the user asks to correct a doubtful language reading.
     *
     * Owned by the caller because only it knows how to open the picker. There is
     * deliberately no inline list here: twenty locales in a 46 px strip would be
     * a worse control than the settings page the user is already familiar with.
     */
    signal correctLanguageRequested()

    readonly property bool isRecording: state === "recording"
    readonly property bool isFinalizing: state === "finalizing"
    readonly property bool isBusy: isRecording || isFinalizing

    /**
     * True only while audio is actually being captured.
     *
     * The level meter, the detected-language reading and the elapsed clock are
     * live *capture* readouts. Showing them next to a setup error made a failed
     * request look like a recording that had started and was hearing nothing --
     * a silent meter and a "0s" clock read as a broken microphone. When there is
     * a setup message and nothing is being captured, the strip is an explanation
     * and nothing else, so these collapse to zero width rather than lying.
     */
    readonly property bool isCapturing: isRecording || isFinalizing

    /** A gap notice is showing, so the strip is an explanation, not a session. */
    readonly property bool hasSetupMessage: setupMessage.length > 0 && !isCapturing

    /** A session ran and produced nothing, so the strip explains that outcome. */
    readonly property bool hasEmptyNotice: emptyNotice.length > 0 && !isCapturing

    /** A non-fatal warning fired mid-capture and the session is still live. */
    readonly property bool hasWarning: warningMessage.length > 0 && isCapturing

    /** Any explanation is showing, which collapses the capture readouts. */
    readonly property bool hasNotice: hasSetupMessage || hasEmptyNotice

    /** The notice text is the visible text, i.e. there is no live partial to show. */
    readonly property bool showingSetupMessage: hasNotice && partialText.length === 0

    /** Whether the notice points somewhere. Only a setup gap has a destination. */
    readonly property bool noticeNavigates: hasSetupMessage

    /**
     * The explanation to render, or "" when there is nothing to explain.
     *
     * Routed through the gated booleans rather than the raw properties: a
     * notice from a finished session must not keep showing while a new one is
     * live, or the strip reads as a stale error over live capture.
     */
    readonly property string noticeText: hasSetupMessage
        ? setupMessage
        : (hasEmptyNotice ? emptyNotice : "")

    /// Language shown to the user. "und" is reported honestly as undetermined.
    readonly property string languageLabel: {
        if (!detectedLanguage || detectedLanguage === "und")
            return "language not determined";
        return detectedLanguage;
    }

    /**
     * What the state readout says right now.
     *
     * The reading wins over "transcribing" as soon as there is one. The old
     * order -- always "transcribing" while finalizing -- meant the language
     * could never be displayed during the only window in which the user could
     * still act on it, so D8's promise was unimplementable as written. Showing
     * the reading over the status word is the better trade: the elapsed clock
     * and the level meter already say that work is happening.
     */
    readonly property string stateLabelText: {
        if (root.pendingLanguage.length > 0) {
            return root.languageIsUncertain
                ? root.pendingLanguage + " (unsure)"
                : root.pendingLanguage;
        }
        if (isFinalizing) return "transcribing";
        return languageLabel;
    }

    readonly property string elapsedLabel: {
        const total = Math.max(0, Math.floor(elapsedMs / 1000));
        const m = Math.floor(total / 60);
        const s = total % 60;
        return m > 0 ? (m + ":" + (s < 10 ? "0" : "") + s) : (s + "s");
    }

    // Component exposure for offscreen tests.
    readonly property alias meterItem: meter
    readonly property alias transcriptItem: transcriptText
    readonly property alias partialTextItem: partialTextB
    readonly property alias timerItem: timerText
    readonly property alias statusIconItem: statusIcon
    readonly property alias stateLabelItem: stateLabel
    readonly property alias languageHitItem: languageHit
    readonly property alias noticeActionItem: noticeAction
    readonly property alias noticeActionTextItem: noticeActionText

    accentGlint: (typeof Colors !== "undefined" && Colors.primary) ? Colors.primary : "#9bcbfb"
    // A resting container inside the composer keeps the specular hairlines and
    // drops the perimeter ring: a second 1px ring drawn inside the composer's
    // ring reads as a box in a box rather than a glass edge (LESSONS.md 9.1).
    showBorder: false
    showShadow: false
    showBottomRim: true
    padding: (typeof Theme !== "undefined" && Theme.padSmall !== undefined) ? Theme.padSmall : 8
    // Concentric curvature is a design-system invariant (DESIGN.md 9.4), so the
    // radius comes from the token with a literal fallback, matching the pattern
    // every other component in this shell uses.
    radius: (typeof Theme !== "undefined" && Theme.radiusGlassItem) ? Theme.radiusGlassItem : 12

    // Entrance uses the expressive spatial spring; opacity uses the effects curve.
    opacity: root.visible ? 1.0 : 0.0
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.animExpressiveDefaultEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.curveExpressiveDefaultEffects
        }
    }

    // The strip is itself the link into Settings (spec Q12): the whole notice
    // row navigates, so the pointer cursor, the hover lift on the destination
    // chip and the click target always agree. Declared before the row, so the
    // dismiss button's own MouseArea (a child of the row) stays on top and
    // keeps its clicks.
    property alias noticeLinkItem: noticeLink

    MouseArea {
        id: noticeLink
        anchors.fill: parent
        // Only a setup gap has a destination. A session that heard nothing is
        // an outcome of this recording, and offering "Settings > AI > Voice
        // input" for it would send the user somewhere that cannot fix it.
        visible: root.showingSetupMessage && root.noticeNavigates
        enabled: visible
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (typeof Config !== "undefined" && typeof Config.openSettings === "function") {
                // The chip promises "Settings > AI > Voice input": land on the
                // voice section, not at the top of a long AI page.
                Config.openSettings("ai", "voice");
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spaceSmall

        // Status glyph. Recording uses the error tone so the mic state is
        // unmistakable at a glance, matching the send button's stop affordance.
        //
        // Deliberately a plain `Item`, NOT a MaterialIcon. MaterialIcon derives
        // `implicitWidth` and `visible` from whether *it* has an icon of its own,
        // so using one as a slot for two conditional children collapsed the slot
        // to 0x0 and hid it entirely -- the glyph failed by silently vanishing.
        Item {
            id: statusIcon
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            implicitWidth: 18
            implicitHeight: 18

            // Vector-drawn Lucide `mic-vocal`: the icon font has no microphone
            // glyph, and the Material Design Icons range resolved to unrelated
            // shapes. Falls back to the equalizer glyph while actively
            // recording, which reads as "listening".
            MicVocalIcon {
                anchors.centerIn: parent
                width: 18
                height: 18
                size: 18
                // A setup gap is an error, not a muted microphone: showing the
                // mic here implied dictation was one click away, when in fact
                // the click produced this explanation instead.
                visible: !root.isRecording && !root.hasNotice
                color: Colors.primary

                Behavior on color {
                    ColorAnimation { duration: Theme.animExpressiveFastEffects }
                }
            }

            // Setup gap: a warning mark in the error tone, so the strip reads as
            // "this cannot run yet" rather than "listening to nothing".
            MaterialIcon {
                anchors.centerIn: parent
                width: 18
                height: 18
                size: 18
                visible: root.hasNotice && !root.isRecording
                iconName: "warning"
                color: Colors.m3error
            }

            MaterialIcon {
                anchors.centerIn: parent
                width: 18
                height: 18
                visible: root.isRecording
                iconName: "graphic_eq"
                size: 18
                color: Colors.m3error

                Behavior on color {
                    ColorAnimation { duration: Theme.animExpressiveFastEffects }
                }
            }
        }

        // Live level meter driven by measured RMS. Fixed height so it never
        // clips when the composer is under height pressure.
        //
        // Gated on `isRecording`, not `isCapturing`: during finalizing the
        // microphone has already been released, so any level on screen is a
        // frozen reading of audio that has stopped. A meter that stops moving
        // while the strip still claims to be working is the "dead microphone"
        // misread pointed the other way -- the language reading and the clock
        // are what legitimately stay up through the decode.
        Item {
            id: meter
            Layout.preferredWidth: root.isRecording ? 34 : 0
            Layout.minimumWidth: 0
            visible: root.isRecording
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignVCenter

            readonly property real normalized: Math.min(1.0, Math.max(0.0, root.level))

            Row {
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: 5

                    delegate: Rectangle {
                        readonly property real threshold: (index + 1) / 5
                        readonly property bool lit: meter.normalized >= threshold * 0.85
                        width: 4
                        height: 18
                        radius: 2
                        // The "off" state is a dim version of the "on" state
                        // rather than a neutral grey. Using a neutral made the
                        // meter read inverted on light backgrounds, where the
                        // unlit bars appeared darker than the lit ones.
                        color: lit ? Colors.primary : Qt.alpha(Colors.primary, 0.22)

                        // Growth tracks real audio with an expressive decay so
                        // the meter feels physical without lying about the level.
                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.animExpressiveFastEffects
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.curveExpressiveFastEffects
                            }
                        }
                    }
                }
            }
        }

        // Transcript / partial text. Elides rather than clips, and never
        // disturbs the composer's own text.
        Item {
            id: messageArea
            Layout.fillWidth: true
            Layout.preferredHeight: 18

            Text {
                id: transcriptText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.partialText.length > 0
                    ? root.partialText
                    : (root.hasWarning ? root.warningMessage : root.noticeText)
                visible: text.length > 0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                // A calm fact, not a link: the destination chip beside it is the
                // affordance, and the warning mark beside it is the severity.
                // Painting and underlining the whole sentence made a setup gap
                // read as one raw hyperlink. A live warning is the exception:
                // it borrows the error tone so it cannot be mistaken for a
                // transcript, and it never collapses the meter beside it.
                color: (root.hasWarning && root.partialText.length === 0)
                    ? Colors.m3error
                    : Colors.m3onSurface
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Alternating pair per AGENTS.md §7.3: cross-fade rather than jump.
            Text {
                id: partialTextA
                anchors.fill: parent
                text: root.partialText
                visible: false
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurface
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                id: partialTextB
                anchors.fill: parent
                text: root.partialText
                visible: root.partialText.length > 0
                opacity: 0.0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLabelSmall
                color: Colors.m3onSurface
                elide: Text.ElideRight
                maximumLineCount: 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animExpressiveDefaultEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.curveExpressiveDefaultEffects
                    }
                }
            }
        }

        // Destination of a setup notice. One object on the row is the way out:
        // a monospace path chip -- the shell's type for machine addresses, as
        // in the composer's model chip below -- with a chevron. This is what
        // replaced the underline that used to span the whole sentence, and it
        // is why `describeVoiceGap` messages carry the reason alone.
        Rectangle {
            id: noticeAction
            visible: root.showingSetupMessage && root.noticeNavigates
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: noticeActionRow.implicitWidth + 16
            radius: (typeof Theme !== "undefined" && Theme.radiusExtraSmall) ? Theme.radiusExtraSmall : 6
            color: Qt.alpha(Colors.primary, noticeLink.containsMouse ? 0.24 : 0.14)
            border.width: 1
            border.color: Qt.alpha(Colors.primary, noticeLink.containsMouse ? 0.65 : 0.38)

            Behavior on color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }
            Behavior on border.color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }

            RowLayout {
                id: noticeActionRow
                anchors.centerIn: parent
                spacing: Theme.spaceExtraSmall

                Text {
                    id: noticeActionText
                    text: "Settings › AI › Voice input"
                    font.family: Theme.fontMonospace
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: Colors.primary
                    elide: Text.ElideRight
                }

                MaterialIcon {
                    iconName: "chevron_right"
                    size: 12
                    color: Colors.primary
                }
            }
        }

        // Engine-reported language. Shown because silent auto-detection on a
        // short clip is unreliable, and a wrong guess with no visible reading is
        // indistinguishable from a recognition bug.
        Text {
            id: stateLabel
            Layout.preferredWidth: root.isCapturing ? Math.max(38, implicitWidth) : 0
            Layout.minimumWidth: 0
            visible: root.isCapturing
            Layout.alignment: Qt.AlignVCenter
            text: root.stateLabelText
            font.family: Theme.fontMonospace
            font.pixelSize: 10
            font.weight: Font.Medium
            // An uncertain reading is tinted with the error tone, because it is
            // the one case where the label is a warning rather than a fact.
            color: root.languageIsUncertain
                ? Colors.m3error
                : (root.detectedLanguage === "und" || root.detectedLanguage === "")
                    ? Colors.m3onSurfaceVariant
                    : Colors.secondary
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight

            // A doubtful reading is the one label worth clicking: it is the only
            // moment where the user has a correction to make and the audio to
            // re-record. Declared last so it sits above the row.
            MouseArea {
                id: languageHit
                anchors.fill: parent
                anchors.margins: -6
                visible: root.isCapturing && root.pendingLanguage.length > 0
                enabled: visible
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.correctLanguageRequested()
            }
        }

        // Real elapsed time. Fixed width so the layout does not jitter.
        Text {
            id: timerText
            Layout.preferredWidth: root.isCapturing ? 34 : 0
            Layout.minimumWidth: 0
            visible: root.isCapturing
            Layout.alignment: Qt.AlignVCenter
            text: root.elapsedLabel
            font.family: Theme.fontMonospace
            font.pixelSize: 10
            color: Colors.m3onSurfaceVariant
            horizontalAlignment: Text.AlignRight
        }

        // Dismiss. A permanent notice with no exit is a wall, not a pointer:
        // the user cannot clear it, so they learn to ignore the composer.
        // Only offered while there is something to dismiss.
        Rectangle {
            id: dismissButton
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignVCenter
            radius: 9
            // Offered for either notice. An empty outcome pins the strip open
            // until something clears it, so without an exit it becomes the very
            // wall this was added to avoid.
            visible: root.hasNotice
            color: dismissMouse.containsMouse ? Colors.glassCardHover : "transparent"

            Behavior on color { ColorAnimation { duration: Theme.animExpressiveFastEffects } }

            MaterialIcon {
                anchors.centerIn: parent
                iconName: "close"
                size: 12
                color: Colors.m3onSurfaceVariant
            }

            MouseArea {
                id: dismissMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.hasSetupMessage) root.dismissRequested();
                    else root.dismissEmptyRequested();
                }
            }
        }
    }
}
