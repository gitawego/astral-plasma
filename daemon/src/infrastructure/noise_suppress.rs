//! Capture-side noise suppression (audit §3.3 evaluation).
//!
//! Verdict: the legacy `module-echo-cancel` path is deprecated (zero reference
//! samples without sink routing), and the evaluated replacement is a dedicated
//! capture-only filter such as `rnnoise` via PipeWire `filter-chain`. That
//! filter is operator-provisioned: the daemon never writes audio-graph config
//! or restarts PipeWire silently (D7). When `voice.noise_suppress` is on and a
//! suppression source is present, sessions capture from it; otherwise they
//! fall back to the default source, so dictation never breaks over it.
//!
//! On hosts with the `rnnoise` LADSPA plugin this composes with an
//! operator-installed `filter-chain` source node; where the plugin is absent
//! (like this host) the path reports unavailable and stays out of the way.

use std::process::Command;

/// Test seam / operator override: capture from this node when set, or disable
/// noise suppression for the session when empty.
pub const NOISE_SUPPRESS_SOURCE_ENV: &str = "ASTRAL_VOICE_NOISE_SUPPRESS_SOURCE";

/// Node name this shell documents for operator-provisioned suppression sources.
pub const NOISE_SUPPRESS_NODE_NAME: &str = "astral_noise_suppress";

/// Whether a `pactl list short sources` listing contains a suppression source.
///
/// Matches the documented node name exactly: a name merely containing it is
/// another application's node, not ours.
pub fn source_present(listing: &str) -> bool {
    listing.lines().any(|line| {
        line.split('\t').nth(1) == Some(NOISE_SUPPRESS_NODE_NAME)
            || std::env::var(NOISE_SUPPRESS_SOURCE_ENV)
                .ok()
                .filter(|n| !n.trim().is_empty())
                .is_some_and(|n| line.split('\t').nth(1) == Some(n.as_str()))
    })
}

/// Whether the `rnnoise` LADSPA plugin is installed.
///
/// Scans `LADSPA_PATH` plus the system library directories for
/// `librnnoise_ladspa.so`. Absent plugin means suppression cannot be hosted
/// here; the setting then documents intent while capture falls back.
pub fn rnnoise_available() -> bool {
    let mut dirs: Vec<String> = std::env::var("LADSPA_PATH")
        .map(|v| v.split(':').map(str::to_string).collect())
        .unwrap_or_default();
    dirs.push("/usr/lib/ladspa".to_string());
    dirs.push("/usr/lib64/ladspa".to_string());
    dirs.push("/usr/lib/x86_64-linux-gnu/ladspa".to_string());
    dirs.iter().any(|d| std::path::Path::new(d).join("librnnoise_ladspa.so").is_file())
}

/// Whether a suppression source is present right now, without mutating audio.
///
/// Used by `voice status`, which must never touch the audio graph.
pub fn source_available() -> bool {
    list_sources().is_some_and(|listing| source_present(&listing))
}

/// Resolves the PipeWire node a noise-suppressed session captures from.
///
/// Explicit override wins (empty disables); then the setting-gated documented
/// or override node when actually present; else `None` (default source).
/// Never loads modules, never writes config: provisioning is the operator's.
pub fn resolve_node(enabled: bool) -> Option<String> {
    if let Ok(explicit) = std::env::var(NOISE_SUPPRESS_SOURCE_ENV) {
        return if explicit.trim().is_empty() { None } else { Some(explicit) };
    }
    if !enabled {
        return None;
    }
    source_available().then(|| {
        std::env::var(NOISE_SUPPRESS_SOURCE_ENV)
            .ok()
            .filter(|n| !n.trim().is_empty())
            .unwrap_or_else(|| NOISE_SUPPRESS_NODE_NAME.to_string())
    })
}

fn list_sources() -> Option<String> {
    let output = Command::new("pactl")
        .args(["list", "short", "sources"])
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn listing_detects_the_documented_node() {
        let listing = "53\talsa_input.pci-0000_00_1f.3.analog-stereo\tPipeWire\ts16le 2ch 48000Hz\n\
                       60\tastral_noise_suppress\tPipeWire\ts16le 1ch 32000Hz\n";
        assert!(source_present(listing));
        assert!(!source_present(""));
        assert!(!source_present("60\tfoo_astral_noise_suppress\tPipeWire\ts16le 1ch\n"));
    }

    #[test]
    fn disabled_setting_resolves_to_the_default_source() {
        assert_eq!(resolve_node(false), None);
    }

    #[test]
    fn enabled_setting_without_a_node_falls_back() {
        // Hermetic: an empty override disables regardless of host audio graph,
        // so this holds with or without PipeWire and with or without nodes.
        std::env::set_var(NOISE_SUPPRESS_SOURCE_ENV, "");
        assert_eq!(resolve_node(true), None);
        std::env::remove_var(NOISE_SUPPRESS_SOURCE_ENV);
    }
}
