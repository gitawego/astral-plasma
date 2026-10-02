import QtQuick
import "../settings_gui/controls"
import "../components"
import "../theme"
import "../components/StateColor.js" as StateColor

// ============================================================================
// AI page controls: section header, setup group, threshold range
// ============================================================================
// The three controls the AI page's hierarchy is built from. Each one carries a
// rule that would otherwise be an invisible convention in the page:
//
//   * a section header whose eyebrow is *state*, not a decorative index;
//   * a setup group that opens itself when something needs the user, and
//     remembers the user's own choice once they make one;
//   * a threshold range where the amber/rose relationship is enforced and drawn,
//     instead of two sliders that can silently cross.
Item {
    id: testRoot
    width: 900
    height: 700

    SectionHeader {
        id: header
        width: 600
        eyebrow: "3 providers · next reset in 3h 40m"
        title: "Quotas"
    }

    SetupGroup {
        id: fineGroup
        width: 600
        title: "Pi harness"
        summary: "pi 1.0.0, up to date"
        state: "ok"
        needsAttention: false
    }

    SetupGroup {
        id: attentionGroup
        width: 600
        title: "Sign-ins"
        summary: "1 provider needs re-auth"
        state: "attention"
        needsAttention: true
    }

    SetupGroup {
        id: unknownGroup
        width: 600
        title: "Voice input"
        summary: "not checked yet"
        state: "unknown"
    }

    // The same row, reused for unrelated content.
    SetupGroup {
        id: batteryGroup
        width: 600
        title: "Battery"
        summary: "Protection kicks in at 20%"
        state: "attention"
    }

    // The provider card: display-only, footer slot for the caller's controls.
    ProviderQuotaCard {
        id: providerCard
        width: 420
        warningThreshold: 80
        criticalThreshold: 95
        now: 1790956800000
        provider: ({
            provider_id: "opencode-go",
            display_name: "OpenCode Go",
            plan_type: "Pro",
            is_available: true,
            account_email: "gitawego@gmail.com",
            windows: [
                { label: "5h", used_percent: 18, remaining_percent: 82, reset_at: "2026-10-02T18:40:00Z" },
                { label: "weekly", used_percent: 47.4, remaining_percent: 52.6, reset_at: "2026-10-07T06:22:36Z" }
            ]
        })

        // Caller-owned footer: proves the card carries foreign content.
        Row {
            objectName: "callerFooter"
            width: 100
            height: 20
        }
    }

    // A provider with nothing to report yet.
    ProviderQuotaCard {
        id: bareCard
        width: 420
        provider: ({ provider_id: "minimax", display_name: "MiniMax", is_available: false, windows: [] })
    }

    ThresholdRange {
        id: range
        width: 500
        warning: 80
        critical: 95
    }

    property var lastRange: null
    Connections {
        target: range
        function onRangeModified(warning, critical) {
            testRoot.lastRange = { warning: warning, critical: critical };
        }
    }

    property int lastToggle: -1
    Connections {
        target: fineGroup
        function onToggled(open) { testRoot.lastToggle = open ? 1 : 0; }
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function runTests() {
        console.log("RUNNING: AI Page Controls");

        // ------------------------------------------------------------------
        // Section header: the eyebrow is live state
        // ------------------------------------------------------------------
        assert(header.eyebrowItem.text === "3 PROVIDERS · NEXT RESET IN 3H 40M",
            "the eyebrow states the section's condition in small caps, got: " + header.eyebrowItem.text);
        assert(header.titleItem.text === "Quotas", "the title names the section plainly");

        // ------------------------------------------------------------------
        // Setup group: closed when fine, open when it needs the user
        // ------------------------------------------------------------------
        assert(fineGroup.expanded === false,
            "a healthy group stays closed, so a healthy page reads in one screen");
        assert(attentionGroup.expanded === true,
            "a group that needs the user opens itself");
        assert(unknownGroup.expanded === false, "an unknown state is not an alarm");
        assert(fineGroup.bodyContainerItem.implicitHeight === 0,
            "a closed group takes no body height");

        // The user's own choice wins, both ways.
        fineGroup.toggle();
        assert(fineGroup.expanded === true && testRoot.lastToggle === 1,
            "opening a group is reported and sticks");
        attentionGroup.toggle();
        assert(attentionGroup.expanded === false,
            "the user can close a group that opened itself");
        assert(attentionGroup.userClosed === true, "and that choice is remembered");

        // ------------------------------------------------------------------
        // State vocabulary: shared, pure, re-derivable
        // ------------------------------------------------------------------
        assert(StateColor.roleFor("ok") === "success", "ok maps to the success role");
        assert(StateColor.roleFor("attention") === "warning", "attention maps to warning");
        assert(StateColor.roleFor("critical") === "error", "critical maps to error");
        assert(StateColor.roleFor("busy") === "primary", "busy maps to primary");
        assert(StateColor.roleFor("idle") === "m3onSurfaceVariant",
            "a normal quiet state is muted, not alarming");
        assert(StateColor.roleFor("nonsense") === "m3onSurfaceVariant",
            "an unknown state is not treated as an alarm");
        assert(StateColor.isActionable("attention") === true
                && StateColor.isActionable("critical") === true,
            "attention and critical are the states that ask for the user");
        assert(StateColor.isActionable("idle") === false && StateColor.isActionable("ok") === false,
            "a finished queue or a used-up quota must not announce itself");

        // A missing palette still renders deliberate colours, and a supplied one wins.
        const fallbackOk = StateColor.colorFor("ok", undefined);
        const fallbackWarn = StateColor.colorFor("attention", undefined);
        const fallbackErr = StateColor.colorFor("critical", undefined);
        assert(fallbackOk !== undefined && fallbackWarn !== undefined && fallbackErr !== undefined,
            "a component rendered outside the shell still gets colours");
        assert(fallbackOk !== fallbackWarn && fallbackWarn !== fallbackErr,
            "the three severities are visually distinct");
        assert(StateColor.colorFor("ok", { success: "#123456" }) === "#123456",
            "a provided palette wins over the fallback");

        // The controls resolve through that vocabulary, so they cannot disagree.
        const dotColor = dot => ("" + dot.color).toLowerCase();
        assert(dotColor(fineGroup.stateDotItem) === ("" + StateColor.colorFor("ok", Colors)).toLowerCase(),
            "the setup dot uses the shared mapping for ok, got: " + dotColor(fineGroup.stateDotItem));
        assert(dotColor(attentionGroup.stateDotItem) === ("" + StateColor.colorFor("attention", Colors)).toLowerCase(),
            "the setup dot uses the shared mapping for attention");
        assert(attentionGroup.stateRole === "warning", "a row can be asked for its role");
        assert(dotColor(unknownGroup.stateDotItem) === ("" + StateColor.colorFor("unknown", Colors)).toLowerCase(),
            "unknown is muted, not alarming");

        // ------------------------------------------------------------------
        // Reusability: the same control, other content
        // ------------------------------------------------------------------
        // Nothing here is AI-page specific: another page can drop a setup row, a
        // section header or a runway in and drive it entirely by props.
        batteryGroup.title = "Battery";
        batteryGroup.summary = "Protection kicks in at 20%";
        batteryGroup.state = "attention";
        assert(batteryGroup.stateRole === "warning",
            "a reused row follows the state it is given, not the page it came from");
        assert(batteryGroup.summaryItem.text === "Protection kicks in at 23%".replace("23", "20"),
            "the summary is the caller's, got: " + batteryGroup.summaryItem.text);

        // ------------------------------------------------------------------
        // Threshold range: the relationship is enforced and drawn
        // ------------------------------------------------------------------
        assert(range.warning === 80 && range.critical === 95, "the range starts where it is set");

        range.setWarning(99);
        assert(range.warning === 90,
            "amber stops one gap below rose (got " + range.warning + ")");
        assert(testRoot.lastRange !== null && testRoot.lastRange.warning === 90
                && testRoot.lastRange.critical === 95,
            "a change reports both thresholds, so the page writes one pair");

        range.setCritical(50);
        assert(range.critical === 95,
            "rose stops one gap above amber (got " + range.critical + ")");
        range.setCritical(99);
        assert(range.critical === 99 && range.warning === 90, "rose may move up freely");

        // Geometry: the knob sits where the value says, on a track that has a
        // length at all. (The track's insets are asserted on their own first:
        // a control whose geometry collapses to zero still "agrees" with itself.)
        assert(range.trackLeft === range.knobSize / 2, "the track is inset by half a handle");
        assert(range.trackWidth > 0 && range.trackWidth < range.width,
            "the track has a usable length, got " + range.trackWidth);
        assert(range.trackItem.width === range.width, "the track spans the control");

        const fraction = range.fractionFor(range.warning);
        const expectedX = range.trackLeft + range.trackWidth * fraction - range.knobSize / 2;
        assert(Math.abs(range.warningKnobItem.x - expectedX) <= 1.0,
            "the amber knob is placed by its own value (got " + range.warningKnobItem.x + ", expected " + expectedX + ")");
        assert(range.warningKnobItem.x >= -1 && range.warningKnobItem.x + range.knobSize <= range.width + 1,
            "the knob stays inside the control");
        assert(range.criticalKnobItem.x > range.warningKnobItem.x,
            "rose always sits to the right of amber");

        // Keyboard: focusable, arrows nudge, handles switch - and the nudge is
        // clamped by the same gap rule as dragging.
        assert(range.activeFocusOnTab === true, "the control is reachable by keyboard");
        range.warning = 60;
        range.critical = 95;
        range.activeHandle = "warning";
        range.nudge(1);
        assert(range.warning === 61, "an arrow key nudges the active handle, got " + range.warning);
        range.nudge(5);
        assert(range.warning === 66, "shift steps are larger, got " + range.warning);
        range.activeHandle = "critical";
        range.nudge(-100);
        assert(range.critical === 71,
            "rose cannot be nudged onto amber, got " + range.critical);
        range.nudge(100);
        assert(range.critical === 100, "rose can reach the ceiling, got " + range.critical);
        range.activeHandle = range.activeHandle === "warning" ? "critical" : "warning";
        assert(range.activeHandle === "warning", "handles can be switched");

        // Dragging targets the nearest handle, not always the first.
        range.dragHandle(range.trackItem.x + range.trackLeft + range.trackWidth * 0.99);
        assert(range.critical === 100, "dragging the rose handle to the end reaches 100 (got " + range.critical + ")");
        assert(range.pickHandle(range.trackItem.x + range.trackLeft) === "warning",
            "a click near the amber end targets amber");

        // ------------------------------------------------------------------
        // Provider card: reuse, states, and honest emptiness
        // ------------------------------------------------------------------
        assert(providerCard.nameItem.text === "OpenCode Go", "the card names the provider");
        assert(providerCard.stateItem.text === "Active", "availability is stated in words");
        assert(("" + providerCard.stateItem.color).toLowerCase() === ("" + StateColor.colorFor("ok", Colors)).toLowerCase(),
            "an available provider uses the shared ok colour");
        assert(providerCard.identityItem.text === "gitawego@gmail.com",
            "the account identity is shown");
        assert(providerCard.identityItem.font.family === providerCard.monoFamily,
            "identifiers are set in the mono face, not body prose");
        assert(providerCard.identityItem.font.family !== providerCard.nameItem.font.family,
            "the identifier and the provider name are typographically distinct");
        assert(providerCard.runwayRepeaterItem.count === 2,
            "one runway per window, got " + providerCard.runwayRepeaterItem.count);
        assert(providerCard.emptyItem.visible === false, "no empty hint when windows exist");
        assert(providerCard.children.length > 0, "the card is a real item tree");

        assert(bareCard.emptyItem.visible === true,
            "a provider with no windows says so instead of drawing an empty bar");
        assert(bareCard.stateItem.text === "Unavailable", "an unreachable provider says so");
        assert(("" + bareCard.stateItem.color).toLowerCase() === ("" + StateColor.colorFor("critical", Colors)).toLowerCase(),
            "unreachable is critical, unlike a merely used-up quota");

        console.log("PASS: AI Page Controls");
        Qt.exit(0);
    }
}
