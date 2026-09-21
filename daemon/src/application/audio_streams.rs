//! Which applications are actually producing audio right now.
//!
//! MPRIS playback state is a *claim*: a browser media session keeps reporting
//! `Playing` for a background tab, a muted video, or a page that has long been
//! closed, and the Wine MPRIS bridge can only report what it last saw. The
//! physical audio stream is the ground truth - an application that owns an
//! uncorked, unmuted sink input is the one making sound.
//!
//! The shell uses this to decide which player is *really* playing, so a stale
//! browser session can never outrank the music the user is listening to.

use crate::domain::ports::DynResult;
use std::process::Command;

/// An application producing audio on a sink.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioStream {
    /// `application.name`, e.g. "NetEase Cloud Music" or "Microsoft Edge".
    pub name: String,
    /// `application.process.binary`, e.g. "wine-preloader" or "msedge".
    pub binary: String,
}

/// Parse `pactl list sink-inputs`.
///
/// A stream only counts when it is neither corked (paused by the client) nor
/// muted: everything else is a session that *looks* active while producing no
/// sound.
pub fn parse_audible_streams(output: &str) -> Vec<AudioStream> {
    let mut streams: Vec<AudioStream> = Vec::new();
    let mut current: Option<AudioStream> = None;
    let mut corked = false;
    let mut muted = false;

    let mut flush = |stream: &mut Option<AudioStream>, corked: &mut bool, muted: &mut bool, out: &mut Vec<AudioStream>| {
        if let Some(stream) = stream.take() {
            if !*corked && !*muted && (!stream.name.is_empty() || !stream.binary.is_empty()) {
                out.push(stream);
            }
        }
        *corked = false;
        *muted = false;
    };

    for line in output.lines() {
        let line = line.trim();
        if line.starts_with("Sink Input #") {
            flush(&mut current, &mut corked, &mut muted, &mut streams);
            current = Some(AudioStream {
                name: String::new(),
                binary: String::new(),
            });
            continue;
        }
        // Properties are `key = "value"`, but the state flags are `Key: value`.
        let (key, value) = if let Some((key, value)) = line.split_once('=') {
            (key.trim(), value.trim().trim_matches('"'))
        } else if let Some((key, value)) = line.split_once(':') {
            (key.trim(), value.trim())
        } else {
            continue;
        };
        match key {
            "Corked" => corked = value.eq_ignore_ascii_case("yes"),
            "Mute" => muted = value.eq_ignore_ascii_case("yes"),
            "application.name" => {
                if let Some(stream) = current.as_mut() {
                    stream.name = value.to_string();
                }
            }
            "application.process.binary" => {
                if let Some(stream) = current.as_mut() {
                    stream.binary = value.to_string();
                }
            }
            _ => {}
        }
    }
    flush(&mut current, &mut corked, &mut muted, &mut streams);

    streams
}

/// Ask the sound server which applications are producing audio.
pub fn audible_streams() -> DynResult<Vec<AudioStream>> {
    let output = Command::new("pactl")
        .args(["list", "sink-inputs"])
        .output()?;
    if !output.status.success() {
        return Err(format!(
            "pactl exited with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        )
        .into());
    }
    Ok(parse_audible_streams(&String::from_utf8_lossy(&output.stdout)))
}

/// Whether a stream belongs to the given player identity or bus name.
///
/// Matching is deliberately generic - a normalized containment either way, so
/// "Microsoft Edge" matches `msedge` and "NetEase Cloud Music (Wine)" matches
/// "NetEase Cloud Music" without any per-application table.
pub fn stream_matches_player(stream: &AudioStream, identity: &str, bus_name: &str) -> bool {
    let candidates = [
        normalize(&stream.name),
        normalize(&stream.binary),
    ];
    let players = [normalize(identity), normalize(bus_name)];

    for candidate in candidates.iter().filter(|c| c.len() >= 3) {
        for player in players.iter().filter(|p| p.len() >= 3) {
            if candidate.contains(player.as_str()) || player.contains(candidate.as_str()) {
                return true;
            }
        }
    }
    false
}

/// Whether some application other than this player owns the sound.
///
/// Used to pause the Wine MPRIS bridge when the audio belongs to something else
/// (a video, a game). Unlike asking the other MPRIS players, this cannot be
/// fooled by a browser session that merely claims `Playing`.
pub fn another_app_owns_audio(streams: &[AudioStream], identity: &str, bus_name: &str) -> bool {
    !streams.is_empty()
        && !streams
            .iter()
            .any(|stream| stream_matches_player(stream, identity, bus_name))
}

/// Lowercase, alphanumerics only: `wine-preloader` -> `winepreloader`.
fn normalize(value: &str) -> String {
    value
        .chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(|c| c.to_lowercase())
        .collect()
}
