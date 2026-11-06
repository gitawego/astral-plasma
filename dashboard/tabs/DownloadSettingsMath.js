.pragma library

// Pure clamp rules for the download settings panel.
//
// The same bounds as Settings > Downloads; kept here so the panel and its
// offscreen test do not have to instantiate Theme/Colors-driven controls.

function clampInt(value, lo, hi, fallback) {
    const n = Number(value);
    return Math.max(lo, Math.min(hi, Math.round(isNaN(n) ? fallback : n)));
}

function parts(value) {
    return clampInt(value, 1, 16, 4);
}

function parallel(value) {
    return clampInt(value, 1, 16, 5);
}

/// 100 KiB/s steps: the engine only ever receives a value the slider could show.
function speedKbps(value) {
    return Math.round(clampInt(value, 0, 10000, 0) / 100) * 100;
}

/// What the two connection knobs add up to: parallel files × parts per file.
/// The panel's live readout is this equation, so it can never disagree with
/// the sliders next to it.
function capacity(parallel, parts) {
    return clampInt(parallel, 1, 16, 5) * clampInt(parts, 1, 16, 4);
}

/// Human cap for the live readout. 0 is aria2's "no limit".
function formatKbps(kbps) {
    const v = Math.max(0, Math.round(Number(kbps) || 0));
    if (v <= 0) return "Unlimited";
    if (v >= 1024) {
        const mib = v / 1024;
        return (mib % 1 === 0 ? mib.toFixed(0) : mib.toFixed(1)) + " MiB/s";
    }
    return v + " KiB/s";
}
