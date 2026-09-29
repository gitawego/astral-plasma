//! PipeWire echo cancellation for voice capture.
//!
//! The most common dictation blocker on a desktop is the microphone hearing the
//! machine's own speakers: the engine then transcribes the playback (wrong
//! language, hallucinated words) or, once VAD filters it, nothing at all.
//! PipeWire's `module-echo-cancel` (WebRTC AEC3) subtracts the sink reference
//! from the capture, which cancels the playback while leaving the speaker's
//! owner untouched - a live voice is uncorrelated with the reference.
//!
//! Measured on a reporter's machine: the built-in microphone carried the music
//! at ~0.64 RMS full scale; the echo-cancelled source carried it at ~0.07,
//! a ~19 dB reduction. Default sink and source routing are unchanged by loading
//! the module.

use std::process::Command;
use std::time::Duration;

/// Node name of the virtual source the shell creates and captures from.
pub const AEC_SOURCE_NAME: &str = "astral_echo_cancel";

/// Node name of the companion sink. `module-echo-cancel` requires a playback
/// reference and exposes it as a sink; nothing routes to it by default.
pub const AEC_SINK_NAME: &str = "astral_echo_cancel_sink";

/// The `pactl load-module` argument vector.
pub fn load_args() -> Vec<String> {
    vec![
        "load-module".to_string(),
        "module-echo-cancel".to_string(),
        "aec_method=webrtc".to_string(),
        format!("source_name={AEC_SOURCE_NAME}"),
        format!("sink_name={AEC_SINK_NAME}"),
    ]
}

/// Whether a `pactl list short sources` listing contains our source.
///
/// The listing is tab-separated: `id<TAB>name<TAB>driver<TAB>spec`.
pub fn source_present(listing: &str) -> bool {
    listing
        .lines()
        .any(|line| line.split('\t').nth(1) == Some(AEC_SOURCE_NAME))
}

/// Ensures the echo-cancelled source exists and returns its node name.
///
/// Audit §3.3: the legacy `module-echo-cancel` path is deprecated — loading it
/// without routing desktop playback through its sink gives AEC zero reference
/// samples while adding blind AGC distortion. Returns `None` unless the caller
/// explicitly opted in via `echo_cancel: true` *and*
/// `ASTRAL_VOICE_AEC_ALLOW_LEGACY=1`. Tests and opt-in users set
/// `ASTRAL_VOICE_AEC_SOURCE` directly instead. Dictation never breaks over this.
pub fn ensure_source() -> Option<String> {
    if std::env::var("ASTRAL_VOICE_AEC_ALLOW_LEGACY").as_deref() != Ok("1") {
        return None;
    }
    if source_available() {
        return Some(AEC_SOURCE_NAME.to_string());
    }
    let output = Command::new("pactl").args(load_args()).output().ok()?;
    if !output.status.success() {
        return None;
    }
    // The node is published asynchronously; poll briefly.
    for _ in 0..20 {
        std::thread::sleep(Duration::from_millis(100));
        if source_available() {
            return Some(AEC_SOURCE_NAME.to_string());
        }
    }
    None
}

/// Whether the echo-cancelled source is currently present, without loading it.
///
/// Used by `voice status`, which must never mutate the audio graph.
pub fn source_available() -> bool {
    list_sources().is_some_and(|listing| source_present(&listing))
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
    fn listing_detects_the_source_by_node_name() {
        let listing = "53\talsa_input.pci-0000_00_1f.3.analog-stereo\tPipeWire\ts16le 2ch 48000Hz\n\
                       60\tastral_echo_cancel\tPipeWire\ts16le 1ch 32000Hz\n";
        assert!(source_present(listing));
    }

    #[test]
    fn listing_without_the_source_is_not_a_match() {
        let listing = "53\talsa_input.pci-0000_00_1f.3.analog-stereo\tPipeWire\ts16le 2ch 48000Hz\n\
                       54\talsa_output.usb-Jeecoo.monitor\tPipeWire\ts16le 2ch 48000Hz\n";
        assert!(!source_present(listing));
        assert!(!source_present(""));
        // A name that merely contains ours is not ours.
        assert!(!source_present("60\tfoo_astral_echo_cancel\tPipeWire\ts16le 1ch\n"));
    }

    #[test]
    fn load_args_name_the_module_and_both_nodes() {
        let args = load_args();
        assert_eq!(args.first().map(String::as_str), Some("load-module"));
        assert_eq!(args.get(1).map(String::as_str), Some("module-echo-cancel"));
        assert!(args.iter().any(|a| a == "aec_method=webrtc"));
        assert!(args.iter().any(|a| a == &format!("source_name={AEC_SOURCE_NAME}")));
        assert!(args.iter().any(|a| a == &format!("sink_name={AEC_SINK_NAME}")));
    }
}
