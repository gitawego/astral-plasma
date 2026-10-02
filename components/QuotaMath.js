.pragma library

// ============================================================================
// Quota math
// ============================================================================
// The rules behind a rate-limit window, in one shared place: what state a window
// is in, how long the window is, where its roll-over sits, and how to say the time
// left. `QuotaRunway` renders them; the AI page's zone rail, a dock pill or a tab
// badge can summarise with the same functions - so a summary and a bar can never
// disagree about what "82% left" means.
//
// Pure, and asserted by `tests/tst_quota_runway.qml`.
//
// Window lengths come from the *label the daemon emits* (`5h`, `weekly`,
// `monthly`): a kind we cannot size gets no marker rather than an invented one.

/// Window length in minutes, 0 when the label is not one we can size.
function windowMinutesFor(label) {
    switch (label) {
        case "5h": return 300;
        case "daily": return 1440;
        case "weekly": return 10080;
        case "monthly": return 43200;
        default: return 0;
    }
}

/// ISO-8601 to epoch ms, or -1 when it cannot be read.
function parseMs(iso) {
    if (!iso) return -1;
    const parsed = Date.parse(String(iso));
    return isNaN(parsed) ? -1 : parsed;
}

/// State of one window: "unknown" | "exhausted" | "critical" | "watch" | "ok".
///
/// Running out is its own state (`exhausted`), never `critical`: the colour that
/// means "something is wrong" must not be spent on "the quota is used up", which
/// is a normal condition of a rate limit.
function stateFor(remainingPercent, warningThreshold, criticalThreshold) {
    if (remainingPercent < 0) return "unknown";
    if (remainingPercent <= 0) return "exhausted";
    const used = 100 - remainingPercent;
    if (used >= criticalThreshold) return "critical";
    if (used >= warningThreshold) return "watch";
    return "ok";
}

/// Severity in `StateColor`'s vocabulary: an exhausted window is `idle` (quiet),
/// a watched one is `attention`, a critical one is `critical`.
function severityFor(state) {
    switch (state) {
        case "watch": return "attention";
        case "exhausted": return "idle";
        case "ok": return "ok";
        case "critical": return "critical";
        default: return "unknown";
    }
}

/// The least healthy state among several windows.
function worstState(states) {
    const rank = { "unknown": 0, "ok": 1, "exhausted": 2, "watch": 3, "critical": 4 };
    let worst = "ok";
    if (!states || !states.length) return "unknown";
    for (let i = 0; i < states.length; ++i) {
        if ((rank[states[i]] || 0) > (rank[worst] || 0)) worst = states[i];
    }
    return worst;
}

/// How far through the window we are, 0..1. 0 means "no marker": unknown reset,
/// a window kind we cannot size, or a reset so far out it cannot belong to this
/// window (data drift - clamping would draw a confident lie).
function markerFractionFor(resetAt, nowMs, label) {
    const windowMinutes = windowMinutesFor(label);
    if (windowMinutes <= 0) return 0;
    const resetMs = parseMs(resetAt);
    if (resetMs < 0) return 0;
    const minutesLeft = (resetMs - nowMs) / 60000;
    if (minutesLeft <= 0) return 1;
    if (minutesLeft >= windowMinutes) return 0;
    return Math.max(0, Math.min(1, 1 - minutesLeft / windowMinutes));
}

/// Minutes as the interface says them ("resets in 2h 40m").
function formatMinutes(minutes) {
    if (minutes <= 0) return "resetting now";
    if (minutes < 60) return "resets in " + minutes + "m";
    if (minutes < 24 * 60) {
        const hours = Math.floor(minutes / 60);
        const rest = minutes % 60;
        return "resets in " + hours + "h" + (rest > 0 ? " " + rest + "m" : "");
    }
    const days = Math.floor(minutes / (24 * 60));
    const hours = Math.floor((minutes % (24 * 60)) / 60);
    return "resets in " + days + "d" + (hours > 0 ? " " + hours + "h" : "");
}

/// Time until a window rolls over, in the interface's voice.
function resetTextFor(resetAt, nowMs) {
    const resetMs = parseMs(resetAt);
    if (resetMs < 0) return "";
    return formatMinutes(Math.floor((resetMs - nowMs) / 60000));
}

/// The soonest roll-over across every window, as `{ text, minutes }`.
///
/// Windows already rolling over are skipped: "next reset" means the next one the
/// user is waiting for, not a deadline that has already passed.
function nextReset(windows, nowMs) {
    let earliestMs = -1;
    const list = windows || [];
    for (let i = 0; i < list.length; ++i) {
        const resetMs = parseMs(list[i] && list[i].reset_at);
        if (resetMs < 0 || resetMs <= nowMs) continue;
        if (earliestMs < 0 || resetMs < earliestMs) earliestMs = resetMs;
    }
    if (earliestMs < 0) return { text: "", minutes: -1 };
    const minutes = Math.floor((earliestMs - nowMs) / 60000);
    return { text: formatMinutes(minutes), minutes: minutes };
}

/// One line describing a provider list: count, worst state, next roll-over.
///
/// `providers` is the daemon's provider array; each entry may carry `windows`.
function summarize(providers, warningThreshold, criticalThreshold, nowMs) {
    const list = providers || [];
    if (list.length === 0) {
        return { count: 0, state: "unknown", severity: "unknown", text: "no providers signed in" };
    }
    const windows = [];
    const states = [];
    for (let i = 0; i < list.length; ++i) {
        const provider = list[i] || {};
        // An unreachable provider is a real problem, not a quiet one.
        if (provider.is_available === false) states.push("critical");
        const providerWindows = provider.windows || [];
        for (let w = 0; w < providerWindows.length; ++w) {
            windows.push(providerWindows[w]);
            states.push(stateFor(
                providerWindows[w] && providerWindows[w].remaining_percent !== undefined
                    ? Number(providerWindows[w].remaining_percent) : -1,
                warningThreshold,
                criticalThreshold
            ));
        }
    }
    const state = worstState(states);
    const next = nextReset(windows, nowMs);
    const plural = list.length === 1 ? " provider" : " providers";
    const stateWord = state === "critical" ? "needs attention"
        : (state === "watch" ? "getting tight" : (state === "exhausted" ? "windows spent" : "healthy"));
    return {
        count: list.length,
        state: state,
        severity: severityFor(state),
        text: list.length + plural + " · " + stateWord + (next.text !== "" ? " · next " + next.text : "")
    };
}
