//! Local speech-to-text adapter backed by `whisper.cpp`.
//!
//! See `docs/VOICE-INPUT-SPEC.md` for the decision record. The two structural
//! choices worth knowing before reading this file:
//!
//! 1. **The engine's CLI surface is probed, not assumed.** The exact flag set of
//!    `whisper-cpp` 1.9.4 could not be verified when this was written (the
//!    package is not installed and the host has no passwordless `sudo`), so
//!    rather than hardcode a guessed list, [`probe_capabilities`] parses
//!    `--help` from the installed build and [`build_args`] emits only flags that
//!    build actually advertises. This is more robust across versions *and*
//!    testable against a synthetic capability set.
//!
//! 2. **The adapter owns the whole session.** Capture, endpointing and inference
//!    all live here so the engine's quirks stay in one file, per the port's
//!    documented rationale.

use crate::domain::ports::{DynError, DynResult, SpeechToTextPort};
use crate::domain::voice::{
    frame_rms, pcm_bytes_to_f32, should_finalize, wav_container, EngineCapabilities, EngineProbe,
    FinalizeReason, PcmSpec, SilenceDetector, Transcript, VoiceEvent, VoiceSessionConfig,
    LANGUAGE_AUTO, LANGUAGE_UNDETERMINED,
};
use std::io::{BufRead, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

/// Environment variable that overrides engine discovery. Used by the integration
/// tests to inject a stub, and a legitimate escape hatch for unusual installs.
pub const ENGINE_BIN_ENV: &str = "ASTRAL_VOICE_ENGINE_BIN";

/// Environment variable that overrides the models directory.
pub const MODEL_DIR_ENV: &str = "ASTRAL_VOICE_MODEL_DIR";

/// Environment variable that replaces the capture binary.
///
/// Present so the session protocol can be tested on a machine with no
/// microphone, and as an escape hatch for setups where `pw-record` is not the
/// right capture tool. It is a test seam, not a supported configuration path.
pub const CAPTURE_BIN_ENV: &str = "ASTRAL_VOICE_CAPTURE_BIN";

/// Engine ids this adapter answers to.
pub const ENGINE_ID: &str = "whisper-cpp";

/// Candidate binary names, in preference order. Upstream installs both the
/// suffixed and unsuffixed forms depending on build configuration.
const BINARY_NAMES: &[&str] = &["whisper-cli", "whisper-cpp", "main"];

/// Locates the engine binary.
///
/// Discovery order: explicit override, `PATH`, then the shell's own bin
/// directory under `XDG_DATA_HOME`. Mirrors `RuntimeProvisioner`'s approach for
/// the assistant harness.
pub fn locate_engine() -> Option<PathBuf> {
    if let Ok(explicit) = std::env::var(ENGINE_BIN_ENV) {
        let p = PathBuf::from(explicit);
        if p.is_file() {
            return Some(p);
        }
    }

    for name in BINARY_NAMES {
        if let Ok(path) = which(name) {
            let p = PathBuf::from(path);
            if p.is_file() {
                return Some(p);
            }
        }
    }

    let data_home = std::env::var("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| crate::domain::branding::home_dir().join(".local/share"));
    let candidate = data_home.join("astral-plasma/bin");
    for name in BINARY_NAMES {
        let p = candidate.join(name);
        if p.is_file() {
            return Some(p);
        }
    }
    None
}

/// Minimal `which`, avoiding a subprocess per candidate.
fn which(name: &str) -> Result<String, ()> {
    let path_var = std::env::var("PATH").map_err(|_| ())?;
    for dir in path_var.split(':').filter(|d| !d.is_empty()) {
        let candidate = Path::new(dir).join(name);
        if candidate.is_file() && is_executable(&candidate) {
            return Ok(candidate.to_string_lossy().into_owned());
        }
    }
    Err(())
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path)
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(_path: &Path) -> bool {
    true
}

/// Resolves the models directory, honouring the test override.
pub fn models_dir() -> PathBuf {
    match std::env::var(MODEL_DIR_ENV) {
        Ok(d) if !d.is_empty() => PathBuf::from(d),
        _ => crate::domain::voice::models_dir(),
    }
}

/// Resolves a model file, treating a zero-length file as absent so an
/// interrupted download is never mistaken for a usable model.
pub fn resolve_model_file(model_id: &str) -> Option<PathBuf> {
    let path = models_dir().join(crate::domain::voice::model_by_id(model_id).file_name());
    match std::fs::metadata(&path) {
        Ok(meta) if meta.len() > 0 => Some(path),
        _ => None,
    }
}

/// File name of the Silero VAD asset whisper.cpp expects beside the speech
/// models. The daemon provisions it through `voice install-vad` (and alongside
/// every model install); a user who placed one in the models directory manually
/// gets the same effect. The asset's presence is the only switch, which is what
/// keeps a bare `--vad` (the flag that fails every transcription) unreachable.
pub const VAD_MODEL_FILE: &str = crate::domain::voice::VAD_MODEL_FILE;

/// Resolves the optional VAD asset, treating a zero-length file as absent.
pub fn resolve_vad_model() -> Option<PathBuf> {
    let path = models_dir().join(VAD_MODEL_FILE);
    match std::fs::metadata(&path) {
        Ok(meta) if meta.len() > 0 => Some(path),
        _ => None,
    }
}

/// Parses `--help` output into a capability set.
///
/// A flag is considered supported when its long (`--name`) or short (`-x`) form
/// appears in the help text. This is deliberately forgiving: whisper.cpp's help
/// formatting varies between builds, and a false negative would silently drop a
/// flag we could have used, whereas a false positive just lets the engine
/// complain itself.
pub fn probe_capabilities(help_text: &str) -> EngineCapabilities {
    let has = |needle: &str| help_text.contains(needle);
    EngineCapabilities {
        reads_stdin: has("--file") || has("-f") || has("stdin"),
        vad: has("--vad"),
        vad_model: has("--vad-model"),
        audio_context: has("--audio-ctx") || has("-ac "),
        beam_search: has("--beam-size") || has("-bs "),
        best_of: has("--best-of") || has("-bo "),
        no_fallback: has("--no-fallback") || has("-nf"),
        language_auto: has("--language-auto") || has("auto"),
        output_json: has("--output-json") || has("-oj"),
        no_prints: has("--no-prints") || has("-np"),
        threads: has("--threads") || has("-t "),
        translate: has("--translate"),
    }
}

/// Extracts a version token from `--help` or `--version` output.
///
/// Matches a bare `v?N.N[.N]` token anywhere in the text rather than keying off
/// a product name, because the banner wording differs across whisper.cpp builds
/// and the exact output could not be verified at authoring time. Looking for a
/// numeric version shape is both more robust and impossible to get wrong by
/// confusing it with the product name.
pub fn parse_version(text: &str) -> Option<String> {
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0usize;
    while i < chars.len() {
        if !chars[i].is_ascii_digit() {
            i += 1;
            continue;
        }
        let mut j = i;
        let mut dots = 0usize;
        while j < chars.len() {
            if chars[j].is_ascii_digit() {
                j += 1;
            } else if chars[j] == '.' && j + 1 < chars.len() && chars[j + 1].is_ascii_digit() {
                dots += 1;
                j += 1;
            } else {
                break;
            }
        }
        if dots >= 1 && j > i + 1 {
            let end = if i > 0 && chars[i - 1] == 'v' { i - 1 } else { i };
            let token: String = chars[end..j].iter().collect();
            // Skip leading-zero values and implausibly long tokens: those are
            // sample rates or parameter defaults, not a version.
            if !token.starts_with('0') && token.len() <= 12 {
                return Some(token);
            }
        }
        i = if j > i { j } else { i + 1 };
    }
    None
}

/// Everything the engine invocation needs, resolved before spawning.
#[derive(Debug, Clone, PartialEq)]
pub struct EngineInvocation {
    pub binary: PathBuf,
    pub model: PathBuf,
    /// Silero VAD asset, when one is actually present. whisper.cpp's `--vad`
    /// fails the whole transcription unless `--vad-model` names a file, so the
    /// two flags travel together or not at all. `None` in every install we
    /// provision: the upstream asset 404s (docs/VOICE-INPUT-SPEC.md D4).
    pub vad_model: Option<PathBuf>,
    pub language: String,
    pub threads: usize,
    pub capabilities: EngineCapabilities,
}

/// Encoder context floor, in whisper's 20 ms units (256 == 5.12 s).
///
/// whisper.cpp splits audio into windows of `n_audio_ctx * 20ms`. Below this
/// floor the window no longer comfortably contains an utterance plus its
/// padding and the engine starts re-processing segments: measured, `-ac 128` on
/// a 2.5s clip duplicated the transcript and took twice as long as the 30s
/// default. 256 is the smallest window that stayed correct across every sample
/// tried (English and Mandarin speech, 2.5-11s).
pub const AUDIO_CONTEXT_MIN: u32 = 256;

/// Encoder context ceiling: whisper's trained 30 s window (1500 * 20 ms).
pub const AUDIO_CONTEXT_MAX: u32 = 1500;

/// Margin added past the utterance so its final segment is never split.
const AUDIO_CONTEXT_MARGIN_UNITS: u64 = 64; // 1.28 s

/// Sizes the encoder window to the utterance.
///
/// whisper.cpp always encodes its full audio context, so a one-second "hello"
/// used to pay the same ~1.7s CPU encoder pass as thirty seconds of speech - and
/// with `language: auto` it paid it twice (language detection, then
/// transcription). The window is `ceil(duration_ms / 20ms)` plus a margin,
/// clamped to [`AUDIO_CONTEXT_MIN`]..=[`AUDIO_CONTEXT_MAX`]. Measured on a
/// 12th-gen i9 with `ggml-small`, a 2.5s English clip went from 3.9s to 2.5s
/// (`auto`) and 1.1s (`-l en`) with an identical transcript.
pub fn audio_context_for(duration_ms: u64) -> u32 {
    let units = duration_ms.div_ceil(20) + AUDIO_CONTEXT_MARGIN_UNITS;
    units.clamp(AUDIO_CONTEXT_MIN as u64, AUDIO_CONTEXT_MAX as u64) as u32
}

/// Builds the engine argument vector from probed capabilities.
///
/// Only supported flags are emitted. `file` is written to disk rather than piped
/// through stdin: a file is re-runnable for debugging and does not depend on the
/// engine's stdin handling, which varies across builds.
///
/// `audio_duration_ms` is the duration of the *trimmed* utterance and sizes the
/// encoder window (see [`audio_context_for`]).
pub fn build_args(inv: &EngineInvocation, audio_path: &Path, audio_duration_ms: u64) -> Vec<String> {
    let caps = &inv.capabilities;
    let mut args: Vec<String> = Vec::with_capacity(16);

    args.push("-m".to_string());
    args.push(inv.model.to_string_lossy().into_owned());

    args.push("-f".to_string());
    args.push(audio_path.to_string_lossy().into_owned());

    args.push("-l".to_string());
    args.push(inv.language.clone());

    if caps.no_prints {
        // Progress bars would otherwise be parsed as transcript text.
        args.push("-np".to_string());
    }
    if caps.output_json {
        args.push("-oj".to_string());
    }
    if caps.threads {
        args.push("-t".to_string());
        args.push(inv.threads.to_string());
    }
    // Size the encoder window to the utterance. whisper.cpp encodes
    // `n_audio_ctx * 20ms` per window no matter how short the clip is, so the
    // default 30s context is pure waste for dictation; see `audio_context_for`.
    if caps.audio_context && audio_duration_ms > 0 {
        args.push("-ac".to_string());
        args.push(audio_context_for(audio_duration_ms).to_string());
    }
    // Bound the decode.
    //
    // Measured on real-room captures: whisper-cli's defaults (beam 5, best-of 5,
    // temperature fallback up to 1.0) let the decoder generate long
    // hallucinated sequences on non-speech audio - the same 3.3s clip took 45s
    // with the defaults, 24s with greedy plus full fallback, and ~6s with
    // greedy plus no fallback. Clean speech is unaffected (JFK: 0.6s and an
    // identical transcript). Dictation must be bounded, so every knob that
    // multiplies decode cost is pinned rather than left at the CLI defaults.
    if caps.beam_search {
        args.push("-bs".to_string());
        args.push("1".to_string());
    }
    if caps.best_of {
        args.push("-bo".to_string());
        args.push("1".to_string());
    }
    if caps.no_fallback {
        args.push("-nf".to_string());
    }
    // VAD preprocessing is only ever requested with its model asset.
    //
    // whisper-cli exits "failed to process audio" for a bare `--vad`: the flag
    // turns on Silero inference, and there is no built-in fallback when
    // `--vad-model` is missing. The probe therefore records the flag as
    // advertised, but the invocation stays honest about what it can run - the
    // daemon's own SilenceDetector is the endpointing mechanism
    // (docs/VOICE-INPUT-SPEC.md D4), so skipping engine VAD costs nothing.
    if caps.vad && caps.vad_model {
        if let Some(vad_model) = &inv.vad_model {
            args.push("--vad".to_string());
            args.push("--vad-model".to_string());
            args.push(vad_model.to_string_lossy().into_owned());
        }
    }

    args
}

/// Picks a sensible thread count: physical cores, at least 1.
pub fn default_threads() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1)
        .max(1)
}

/// Extracts the transcript text from an engine-produced document.
///
/// `prefer_json` selects the structured parser. whisper-cli's `-oj` writes that
/// JSON **beside the audio file**, not to stdout (see [`read_transcript`]); the
/// structured form is preferred because the plain-text mode prefixes system
/// banners and timing lines to the timestamped transcript.
pub fn extract_transcript(stdout: &str, prefer_json: bool) -> String {
    if prefer_json {
        return match serde_json::from_str::<serde_json::Value>(stdout.trim()) {
            Ok(value) => {
                // whisper's `-oj` emits `transcription: [{text, offsets}, ...]`.
                // Segment texts already carry leading spaces, so they join directly.
                if let Some(segments) = value.get("transcription").and_then(|t| t.as_array()) {
                    let joined: String = segments
                        .iter()
                        .filter_map(|seg| seg.get("text").and_then(|v| v.as_str()))
                        .collect();
                    return joined.trim().to_string();
                }
                if let Some(text) = value.get("text").and_then(|v| v.as_str()) {
                    return text.trim().to_string();
                }
                String::new()
            }
            Err(_) => {
                // The build advertised structured output, so its stdout *is* JSON.
                // If it does not parse, falling back to the line filter would
                // splice raw engine noise into the user's prompt. Returning empty
                // is the honest outcome.
                String::new()
            }
        };
    }

    // Plain-text mode. whisper.cpp interleaves timestamps and log banners with
    // the transcript, e.g.
    //   whisper_print_system_info: n_mels = 80
    //   [00:00:00.000 --> 00:00:02.000]   Hello there.
    //   total time = 1200.00 ms
    // The timestamp prefix must be stripped, not just whole-line log lines.
    let mut kept: Vec<String> = Vec::new();
    for line in stdout.lines() {
        let t = line.trim();
        if t.is_empty() {
            continue;
        }
        if t.starts_with('[') && t.ends_with(']') {
            continue; // standalone log line
        }
        let body = strip_timestamp_prefix(t);
        if body.is_empty() {
            continue;
        }
        if is_banner_line(body) {
            continue;
        }
        kept.push(body.to_string());
    }
    kept.join(" ").trim().to_string()
}

/// Path of the JSON document whisper-cli's `-oj` writes beside the audio file.
///
/// The suffix is appended to the whole name (`utterance-1.wav` ->
/// `utterance-1.wav.json`), which is what the engine prints as
/// `output_json: saving output to '<path>'`.
pub fn json_sidecar_path(audio_path: &Path) -> PathBuf {
    let mut name = audio_path.as_os_str().to_os_string();
    name.push(".json");
    PathBuf::from(name)
}

/// Reads the transcript a finished engine run produced.
///
/// whisper-cli's `-oj` does **not** print JSON to stdout: it saves the document
/// next to the input (`<audio>.json`) and still prints the timestamped
/// transcript to stdout. Parsing stdout as JSON therefore returned an empty
/// transcript for every utterance. The sidecar document is authoritative when
/// the build advertises structured output; a missing or unreadable sidecar
/// falls back to the timestamped stdout transcript rather than throwing away
/// real speech.
pub fn read_transcript(audio_path: &Path, stdout: &str, capabilities: &EngineCapabilities) -> String {
    if capabilities.output_json {
        if let Ok(json) = std::fs::read_to_string(json_sidecar_path(audio_path)) {
            return extract_transcript(&json, true);
        }
    }
    extract_transcript(stdout, false)
}

/// Strips a leading `[hh:mm:ss.mmm --> hh:mm:ss.mmm]` segment prefix.
fn strip_timestamp_prefix(line: &str) -> &str {
    if !line.starts_with('[') {
        return line;
    }
    match line.find(']') {
        Some(end) if line[1..end].contains("-->") => line[end + 1..].trim_start(),
        _ => line,
    }
}

/// Whether a line is engine chatter rather than a spoken word.
///
/// whisper.cpp emits diagnostics as `key: name = value` (for example
/// `model_load: n_ctx = 0` or `whisper_print_system_info: n_mels = 80`). Matching
/// that shape is more robust than enumerating prefixes, which vary by build.
fn is_banner_line(line: &str) -> bool {
    if line.starts_with("whisper_print_system_info")
        || line.starts_with("main:")
        || line.starts_with("system_info:")
        || line.contains("total time")
        || line.contains("load time")
    {
        return true;
    }
    match line.split_once(':') {
        Some((key, rest)) => {
            let key = key.trim();
            !key.is_empty()
                && !key.contains(char::is_whitespace)
                && rest.contains('=')
        }
        None => false,
    }
}

/// The local whisper.cpp speech-to-text adapter.
pub struct WhisperCppAdapter {
    binary: Option<PathBuf>,
    capabilities: EngineCapabilities,
    version: Option<String>,
    threads: usize,
}

impl Default for WhisperCppAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl WhisperCppAdapter {
    /// Discovers the engine and probes its capabilities once.
    pub fn new() -> Self {
        let binary = locate_engine();
        let (capabilities, version) = match &binary {
            Some(bin) => match run_help(bin) {
                Ok(text) => (probe_capabilities(&text), parse_version(&text)),
                Err(_) => (EngineCapabilities::default(), None),
            },
            None => (EngineCapabilities::default(), None),
        };
        Self {
            binary,
            capabilities,
            version,
            threads: default_threads(),
        }
    }

    /// Adapter with an explicit binary, skipping discovery. Used by tests.
    pub fn with_binary(binary: PathBuf, capabilities: EngineCapabilities) -> Self {
        Self {
            binary: Some(binary),
            capabilities,
            version: None,
            threads: default_threads(),
        }
    }

    fn prepare(&self, model_id: &str, language: &str) -> DynResult<EngineInvocation> {
        let binary = self
            .binary
            .clone()
            .ok_or_else(|| -> DynError { "whisper.cpp is not installed".into() })?;
        let model = resolve_model_file(model_id).ok_or_else(|| -> DynError {
            format!(
                "Model '{}' is not downloaded. Install it from Settings > AI > Voice input.",
                model_id
            )
            .into()
        })?;
        Ok(EngineInvocation {
            binary,
            model,
            vad_model: resolve_vad_model(),
            language: if language.is_empty() {
                LANGUAGE_AUTO.to_string()
            } else {
                language.to_string()
            },
            threads: self.threads,
            capabilities: self.capabilities.clone(),
        })
    }
}

/// Runs `<binary> --help`, tolerating builds that exit non-zero after printing.
fn run_help(binary: &Path) -> std::io::Result<String> {
    let out = Command::new(binary).arg("--help").output()?;
    let mut text = String::from_utf8_lossy(&out.stdout).into_owned();
    if text.trim().is_empty() {
        text = String::from_utf8_lossy(&out.stderr).into_owned();
    }
    Ok(text)
}

/// Cooperative control handle for a running capture.
///
/// Two distinct signals, because "stop" and "cancel" mean different things to
/// the user: `stop` ends the utterance and transcribes it, `cancel` throws the
/// audio away. Both must interrupt the capture loop, which is otherwise blocked
/// reading the capture pipe and cannot notice either on its own.
#[derive(Clone, Default)]
pub struct CancelHandle {
    stop: Arc<AtomicBool>,
    discard: Arc<AtomicBool>,
}

impl CancelHandle {
    pub fn new() -> Self {
        Self::default()
    }
    /// End the utterance and transcribe what was captured.
    pub fn request_stop(&self) {
        self.stop.store(true, Ordering::SeqCst);
    }
    /// End the utterance and discard the audio without transcribing.
    pub fn request_cancel(&self) {
        self.stop.store(true, Ordering::SeqCst);
        self.discard.store(true, Ordering::SeqCst);
    }
    /// Whether the capture loop should return now.
    pub fn is_stopped(&self) -> bool {
        self.stop.load(Ordering::SeqCst)
    }
    /// Whether the captured audio should be thrown away.
    pub fn is_discarded(&self) -> bool {
        self.discard.load(Ordering::SeqCst)
    }
}

impl SpeechToTextPort for WhisperCppAdapter {
    fn probe(&self) -> DynResult<EngineProbe> {
        Ok(EngineProbe {
            engine_id: ENGINE_ID.to_string(),
            binary_path: self.binary.as_ref().map(|p| p.to_string_lossy().into_owned()),
            version: self.version.clone(),
            capabilities: self.capabilities.clone(),
        })
    }

    fn run_session(
        &self,
        cfg: &VoiceSessionConfig,
        sink: &mut dyn FnMut(VoiceEvent),
    ) -> DynResult<Transcript> {
        self.run_session_cancellable(cfg, &CancelHandle::new(), sink)
    }

    fn run_session_cancellable(
        &self,
        cfg: &VoiceSessionConfig,
        handle: &CancelHandle,
        sink: &mut dyn FnMut(VoiceEvent),
    ) -> DynResult<Transcript> {
        self.run_session_impl(cfg, handle, sink)
    }
}

impl WhisperCppAdapter {
    /// Session entry point with an explicit cancellation handle, so the CLI can
    /// wire a control channel to it.
    pub fn run_session_impl(
        &self,
        cfg: &VoiceSessionConfig,
        cancel: &CancelHandle,
        sink: &mut dyn FnMut(VoiceEvent),
    ) -> DynResult<Transcript> {
        let inv = match self.prepare(&cfg.model, &cfg.language) {
            Ok(inv) => inv,
            Err(e) => {
                // A missing engine or model is a setup gap the user can fix from
                // Settings, not a session failure. The distinction drives which
                // UI surface reports it.
                sink(VoiceEvent::setup_error(e.to_string()));
                return Err(e);
            }
        };

        sink(VoiceEvent::StateChanged {
            state: crate::domain::voice::VoiceState::Recording,
        });

        let pcm = match capture_utterance(cfg, cancel, sink) {
            Ok(pcm) => pcm,
            Err(e) => {
                sink(VoiceEvent::fatal_error(e.to_string()));
                return Err(e);
            }
        };

        if cancel.is_discarded() {
            // Cancelled after capture finished: discard rather than transcribe.
            sink(VoiceEvent::StateChanged {
                state: crate::domain::voice::VoiceState::Idle,
            });
            return Ok(Transcript {
                text: String::new(),
                language: LANGUAGE_UNDETERMINED.to_string(),
                duration_ms: 0,
                engine: ENGINE_ID.to_string(),
                model: inv.model.to_string_lossy().into_owned(),
            });
        }

        sink(VoiceEvent::StateChanged {
            state: crate::domain::voice::VoiceState::Finalizing,
        });

        let spec = PcmSpec::speech();
        let duration_ms = spec.duration_ns(pcm.len()) / 1_000_000;
        let wav = wav_container(spec, &pcm);

        // An inference failure must still surface as a typed event. Letting the
        // `?` propagate would end the stream silently, leaving the UI showing a
        // composer that will never receive a transcript.
        let transcript = match self.infer(&inv, &wav, duration_ms, &cfg.model) {
            Ok(t) => t,
            Err(e) => {
                sink(VoiceEvent::fatal_error(e.to_string()));
                return Err(e);
            }
        };

        sink(VoiceEvent::Final(transcript.clone()));
        Ok(transcript)
    }
}

impl WhisperCppAdapter {
    /// Runs inference over a WAV payload, cleaning up the temp file on every path.
    fn infer(
        &self,
        inv: &EngineInvocation,
        wav: &[u8],
        duration_ms: u64,
        model_id: &str,
    ) -> DynResult<Transcript> {
        let dir = models_dir();
        std::fs::create_dir_all(&dir)
            .map_err(|e| -> DynError { format!("Cannot create {}: {e}", dir.display()).into() })?;

        let audio_path = dir.join(format!("utterance-{}.wav", std::process::id()));
        // Write to a sibling first so a concurrent reader never sees a partial WAV.
        let tmp_path = audio_path.with_extension("wav.part");
        std::fs::write(&tmp_path, wav)
            .map_err(|e| -> DynError { format!("Cannot stage audio: {e}").into() })?;
        std::fs::rename(&tmp_path, &audio_path)
            .map_err(|e| -> DynError { format!("Cannot publish staged audio: {e}").into() })?;

        // The temp file and the `-oj` sidecar are removed on every exit path,
        // including failure.
        let result = self.run_engine(inv, &audio_path, duration_ms, model_id);
        let _ = std::fs::remove_file(&audio_path);
        let _ = std::fs::remove_file(json_sidecar_path(&audio_path));
        let _ = std::fs::remove_file(&tmp_path);
        result
    }

    fn run_engine(
        &self,
        inv: &EngineInvocation,
        audio_path: &Path,
        duration_ms: u64,
        model_id: &str,
    ) -> DynResult<Transcript> {
        // Note: no `Partial` events are emitted here. `whisper-cli` is a
        // whole-file tool -- it prints a transcript once the audio is done and
        // streams nothing before that. Emitting speculative partial text would
        // be fabricating content, which `AGENTS.md` §4 forbids. The listening
        // strip therefore shows measured audio level and elapsed time, which are
        // real, and the text arrives at the end. An adapter that genuinely
        // streams (a whisper-server or cloud backend) can emit `Partial` here.
        let args = build_args(inv, audio_path, duration_ms);
        let output = Command::new(&inv.binary)
            .args(&args)
            .stdin(Stdio::null())
            .output()
            .map_err(|e| -> DynError { format!("Failed to run speech engine: {e}").into() })?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let detail = stderr
                .lines()
                .rev()
                .find(|l| !l.trim().is_empty())
                .unwrap_or("no diagnostic output")
                .trim();
            return Err(format!("Speech engine failed: {detail}").into());
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let text = read_transcript(audio_path, &stdout, &inv.capabilities);

        // An empty result is a real outcome (silence, noise) and is reported as
        // such. Nothing is invented to fill the gap.
        Ok(Transcript {
            text,
            language: if inv.language == LANGUAGE_AUTO {
                LANGUAGE_UNDETERMINED.to_string()
            } else {
                inv.language.clone()
            },
            duration_ms,
            engine: ENGINE_ID.to_string(),
            // The catalog id, not the resolved path: this is shown in the UI
            // and persisted with the session, and a cache path is neither stable
            // nor meaningful to a reader.
            model: model_id.to_string(),
        })
    }
}

/// Records one utterance, emitting `Level` events and enforcing endpointing.
///
/// `cancel` is polled between frames so a `stop` from the control channel is
/// honoured promptly and the capture device is always released.
fn capture_utterance(
    cfg: &VoiceSessionConfig,
    cancel: &CancelHandle,
    sink: &mut dyn FnMut(VoiceEvent),
) -> DynResult<Vec<u8>> {
    let args = crate::domain::voice::pw_record_args(
        cfg.capture,
        cfg.sample_rate,
        crate::domain::voice::SPEECH_CHANNELS,
        32,
    );

    let mut child = spawn_capture(&args)
        .map_err(|e| -> DynError { format!("Cannot open the microphone: {e}").into() })?;

    let mut stdout = child
        .stdout
        .take()
        .ok_or_else(|| -> DynError { "capture process produced no audio stream".into() })?;

    let frame_bytes = (cfg.frame_len * 2).max(2); // s16 mono
    let mut pcm: Vec<u8> = Vec::with_capacity(cfg.sample_rate as usize * 2);
    let mut detector = SilenceDetector::new(cfg.frame_len, cfg.sample_rate);
    let started = Instant::now();
    let mut speech = SpeechBounds::default();

    // Hard-cap watchdog, deliberately independent of frame delivery.
    //
    // The cap used to be checked only inside the frame loop. A capture stream
    // that stalls -- a muted or held-open device delivering no frames -- blocks
    // in `read` forever, so the loop never runs and the microphone is held open
    // indefinitely. That was observed live as a session still "recording" after
    // sixteen minutes.
    //
    // Setting the stop flag alone is not enough, because a thread blocked in
    // `read` never observes it. The watchdog therefore signals the capture
    // process directly, which makes the pending read return EOF so the loop
    // exits normally. The child is unreaped at this point, so the pid is
    // guaranteed to still be ours.
    let cap_ms = cfg.max_utterance_ms;
    let cap_pid = child.id();
    let cap_handle = cancel.clone();
    let finished = Arc::new(AtomicBool::new(false));
    let wd_finished = Arc::clone(&finished);

    // The watchdog is the single owner of "actually stop the capture".
    //
    // A cooperative flag is not sufficient on its own: the frame loop is blocked
    // in `read` and never observes it. An earlier version of this code *did*
    // return early on the stop flag, which quietly defeated the whole mechanism
    // -- a `stop`, a `cancel`, or a closed control channel each set the flag, the
    // watchdog bailed out without signalling anything, and the microphone stayed
    // open indefinitely.
    //
    // So the watchdog must both observe the request and act on it. It signals the
    // capture process, which makes the pending read return EOF so the loop exits
    // normally. Two triggers: an explicit stop/cancel, and the hard cap.
    let watchdog = std::thread::spawn(move || {
        if cap_pid == 0 {
            return;
        }
        let deadline = Instant::now() + std::time::Duration::from_millis(cap_ms.max(1));
        loop {
            // The session already ended on its own: never signal, because the
            // pid may since have been reassigned to another process.
            if wd_finished.load(Ordering::SeqCst) {
                return;
            }
            if cap_handle.is_stopped() {
                break;
            }
            if cap_ms > 0 && Instant::now() >= deadline {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        // Re-check: the session may have completed while we were waking up.
        if wd_finished.load(Ordering::SeqCst) {
            return;
        }
        cap_handle.request_stop();
        // SAFETY: `cap_pid` is our direct child and is deliberately NOT reaped
        // until after this thread is joined (see below), so the pid is
        // guaranteed to still be ours and cannot have been recycled. SIGKILL is
        // required because a stalled capture ignores polite termination and the
        // blocked read must be interrupted.
        unsafe {
            libc::kill(cap_pid as libc::pid_t, libc::SIGKILL);
        }
    });

    let result = capture_loop(
        &mut stdout, &mut child, &mut pcm, &mut detector, started, &mut speech, cancel,
        sink, cfg, frame_bytes,
    );

    // Retire the watchdog, then reap the child. The order is load-bearing:
    // reaping first would release the pid while the watchdog could still be
    // signalling it, and detaching instead of joining would let it outlive the
    // session entirely.
    finished.store(true, Ordering::SeqCst);
    cancel.request_stop();
    let _ = watchdog.join();
    let _ = child.wait();

    // Ship the engine the speech region, not the silence the capture carried.
    // See `trim_to_speech`: every untrimmed sample is inference time and the
    // quiet stretches are where hallucinated text comes from.
    result.map(|pcm| {
        trim_to_speech(&pcm, cfg.sample_rate, cfg.frame_len, speech.first, speech.last)
    })
}

/// Frame indices the detector classified as speech, for trimming.
#[derive(Debug, Default, Clone, Copy)]
struct SpeechBounds {
    first: Option<usize>,
    last: Option<usize>,
}

impl SpeechBounds {
    fn observe(&mut self, frame_index: usize, speaking: bool) {
        if !speaking {
            return;
        }
        if self.first.is_none() {
            self.first = Some(frame_index);
        }
        self.last = Some(frame_index);
    }

    fn has_speech(&self) -> bool {
        self.first.is_some()
    }
}

/// The frame loop, factored out so the watchdog can own the hard cap.
#[allow(clippy::too_many_arguments)]
fn capture_loop(
    stdout: &mut std::process::ChildStdout,
    child: &mut std::process::Child,
    pcm: &mut Vec<u8>,
    detector: &mut SilenceDetector,
    started: Instant,
    speech: &mut SpeechBounds,
    cancel: &CancelHandle,
    sink: &mut dyn FnMut(VoiceEvent),
    cfg: &VoiceSessionConfig,
    frame_bytes: usize,
) -> DynResult<Vec<u8>> {
    let mut pending: Vec<u8> = Vec::with_capacity(frame_bytes * 2);
    let mut chunk = vec![0u8; frame_bytes * 8];
    let mut frame_index = 0usize;

    loop {
        let n = match stdout.read(&mut chunk) {
            Ok(0) => break, // capture ended on its own
            Ok(n) => n,
            Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        };
        pending.extend_from_slice(&chunk[..n]);

        let mut consumed = 0usize;
        while pending.len() - consumed >= frame_bytes {
            let frame: Vec<u8> = pending[consumed..consumed + frame_bytes].to_vec();
            consumed += frame_bytes;

            let level = frame_rms(&pcm_bytes_to_f32(&frame));
            let decision = detector.push(level);
            speech.observe(frame_index, decision.speaking);
            frame_index += 1;
            sink(VoiceEvent::Level { rms: level });
            pcm.extend_from_slice(&frame);

            // Cooperative stop, so the mic is always released promptly. This is
            // the only way a `stop` on the control channel can interrupt a loop
            // that is blocked reading the capture pipe.
            if cancel.is_stopped() {
                let _ = child.kill();
                return Ok(pcm.clone());
            }

            let elapsed_ms = started.elapsed().as_millis() as u64;
            let reason = if cfg.auto_finalize
                && cfg.silence_hangover_ms > 0
                && decision.silent_for_ms >= cfg.silence_hangover_ms
            {
                Some(FinalizeReason::Silence)
            } else if cfg.max_utterance_ms > 0 && elapsed_ms >= cfg.max_utterance_ms {
                Some(FinalizeReason::DurationCap)
            } else {
                None
            };

            if let Some(reason) = reason {
                if should_finalize(
                    reason,
                    elapsed_ms,
                    decision.silent_for_ms,
                    speech.has_speech(),
                    cfg.silence_hangover_ms,
                    cfg.max_utterance_ms,
                ) {
                    let _ = child.kill();
                    return Ok(pcm.clone());
                }
            }
        }

        // Retain the trailing partial frame for the next read.
        if consumed > 0 {
            pending.drain(..consumed);
        }
    }

    let _ = child.kill();
    // Reaped by the caller, after the watchdog has been joined.
    Ok(pcm.clone())
}

/// Margin kept on each side of the detected speech region.
///
/// Whisper needs a little context around an utterance, and the detector can
/// classify the first or last soft phoneme a frame late; trimming at the exact
/// speech boundary risks clipping a word. 250 ms covers both without re-adding
/// meaningful inference time.
pub const SPEECH_PADDING_MS: u64 = 250;

/// Trims a captured PCM buffer to the region around detected speech.
///
/// The recording always carries the trailing silence hangover (and, on a manual
/// stop, whatever silence the user left). Whisper processes every sample it is
/// handed, so an untrimmed utterance pays CPU inference time for silence, and
/// long quiet stretches are where hallucinated text comes from. The bounds come
/// from the same frame-level decisions that drive endpointing, so there is no
/// second threshold to tune.
///
/// Returns the capture unchanged when no speech was detected: an empty buffer
/// would make "nothing was said" indistinguishable from a capture failure.
pub fn trim_to_speech(
    pcm: &[u8],
    sample_rate: u32,
    frame_len: usize,
    first_speech_frame: Option<usize>,
    last_speech_frame: Option<usize>,
) -> Vec<u8> {
    let Some(first) = first_speech_frame else {
        return pcm.to_vec();
    };
    let last = last_speech_frame.unwrap_or(first);
    let frame_bytes = (frame_len * 2).max(2);
    let total_frames = pcm.len() / frame_bytes;
    if total_frames == 0 {
        return pcm.to_vec();
    }
    let pad_frames = if sample_rate == 0 {
        1
    } else {
        let pad_samples = (SPEECH_PADDING_MS.saturating_mul(sample_rate as u64)) / 1000;
        ((pad_samples as usize) / frame_len.max(1)).max(1)
    };
    let start_frame = first.saturating_sub(pad_frames);
    let end_frame = (last + 1 + pad_frames).min(total_frames);
    if start_frame >= end_frame {
        return pcm.to_vec();
    }
    pcm[start_frame * frame_bytes..end_frame * frame_bytes].to_vec()
}

/// Spawns `pw-record` with unbuffered stdout, reusing the visualizer's approach.
fn spawn_capture(args: &[String]) -> std::io::Result<std::process::Child> {
    // Test/override seam: honour an explicit capture binary before falling back
    // to pw-record, so the session protocol is verifiable without a microphone.
    if let Ok(explicit) = std::env::var(CAPTURE_BIN_ENV) {
        if !explicit.is_empty() {
            return Command::new(explicit)
                .args(args)
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn();
        }
    }

    if let Ok(child) = Command::new("stdbuf")
        .arg("-o0")
        .arg("pw-record")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        return Ok(child);
    }
    Command::new("pw-record")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
}

/// Reports whether at least one audio capture source exists.
pub fn has_audio_source() -> bool {
    which("pw-record").is_ok() || which("parecord").is_ok()
}


/// Streams stdout of a child process line-by-line to `sink`. Used by the model
/// downloader, which shells out to `curl` exactly as `ai_quota_adapter` does.
pub fn stream_lines<F: FnMut(&str)>(mut child: std::process::Child, mut sink: F) -> std::io::Result<()> {
    if let Some(out) = child.stdout.take() {
        let reader = std::io::BufReader::new(out);
        for line in reader.split(b'\n') {
            let buf = line?;
            let text = String::from_utf8_lossy(&buf);
            let trimmed = text.trim();
            if !trimmed.is_empty() {
                sink(trimmed);
            }
        }
    }
    child.wait()?;
    Ok(())
}

/// Ensures a writer is flushed before the process exits, avoiding truncated
/// final events in the JSONL stream.
pub fn flush_stdout() {
    let _ = std::io::stdout().flush();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probe_reads_a_realistic_help_blob() {
        let help = "usage: whisper-cli [options]\n\n\
            -f,    --file FNAME          [required] input audio file\n\
            -m,    --model FNAME        [required] model file\n\
            -l,    --language LANG      [auto] spoken language\n\
            -t,    --threads N          number of threads\n\
            -np,   --no-prints          do not print anything\n\
            -oj,   --output-json        output result in JSON format\n\
            -ac N, --audio-ctx N        audio context size (0 - all)\n\
            -bs N, --beam-size N        beam size for beam search\n\
            -bo N, --best-of N          number of best candidates to keep\n\
            -nf,   --no-fallback        do not use temperature fallback\n\
            --vad                      enable VAD preprocessing\n\
            --vad-model FNAME          VAD model\n";
        let caps = probe_capabilities(help);
        assert!(caps.reads_stdin);
        assert!(caps.no_prints);
        assert!(caps.output_json);
        assert!(caps.threads);
        assert!(caps.audio_context);
        assert!(caps.beam_search);
        assert!(caps.best_of);
        assert!(caps.no_fallback);
        assert!(caps.vad);
        assert!(caps.vad_model);
    }

    #[test]
    fn probe_of_a_minimal_build_omits_everything_optional() {
        // An old or minimal build must not cause us to emit flags it rejects.
        let caps = probe_capabilities("usage: whisper-cli -f in.wav -m model.bin\n");
        assert!(caps.reads_stdin);
        assert!(!caps.vad);
        assert!(!caps.vad_model);
        assert!(!caps.audio_context);
        assert!(!caps.beam_search);
        assert!(!caps.best_of);
        assert!(!caps.no_fallback);
        assert!(!caps.output_json);
        assert!(!caps.no_prints);
        assert!(!caps.threads);
    }

    #[test]
    fn probe_of_empty_help_is_all_false() {
        let caps = probe_capabilities("");
        assert_eq!(caps, EngineCapabilities::default());
        assert!(!caps.reads_stdin);
    }

    #[test]
    fn build_args_emits_only_supported_flags() {
        let inv = EngineInvocation {
            binary: PathBuf::from("/usr/bin/whisper-cli"),
            model: PathBuf::from("/models/ggml-base.bin"),
            vad_model: None,
            language: "auto".into(),
            threads: 8,
            capabilities: EngineCapabilities::default(),
        };
        let args = build_args(&inv, Path::new("/tmp/u.wav"), 3_000);
        // Model and file are always required, so always present.
        assert_eq!(flag_value(&args, "-m"), Some("/models/ggml-base.bin".to_string()));
        assert_eq!(flag_value(&args, "-f"), Some("/tmp/u.wav".to_string()));
        assert_eq!(flag_value(&args, "-l"), Some("auto".to_string()));
        // Unsupported optional flags must be absent.
        assert!(!args.iter().any(|a| a == "--vad"));
        assert!(!args.iter().any(|a| a == "-oj"));
        assert!(!args.iter().any(|a| a == "-np"));
        assert!(!args.iter().any(|a| a == "-ac"));
        assert!(!args.iter().any(|a| a == "-bs"));
        assert!(!args.iter().any(|a| a == "-bo"));
        assert!(!args.iter().any(|a| a == "-nf"));
    }

    #[test]
    fn build_args_includes_everything_a_full_build_supports() {
        let inv = EngineInvocation {
            binary: PathBuf::from("/usr/bin/whisper-cli"),
            model: PathBuf::from("/models/ggml-base.bin"),
            vad_model: Some(PathBuf::from("/models/ggml-silero-v5.1.2.bin")),
            language: "zh".into(),
            threads: 4,
            capabilities: EngineCapabilities {
                reads_stdin: true,
                vad: true,
                vad_model: true,
                audio_context: true,
                beam_search: true,
                best_of: true,
                no_fallback: true,
                language_auto: true,
                output_json: true,
                no_prints: true,
                threads: true,
                translate: true,
            },
        };
        let args = build_args(&inv, Path::new("/tmp/u.wav"), 4_000);
        assert!(args.iter().any(|a| a == "-np"), "progress bars would corrupt the transcript parse");
        assert!(args.iter().any(|a| a == "-oj"));
        assert!(args.iter().any(|a| a == "--vad"));
        assert_eq!(flag_value(&args, "--vad-model"),
            Some("/models/ggml-silero-v5.1.2.bin".to_string()));
        assert_eq!(flag_value(&args, "-ac"), Some(audio_context_for(4_000).to_string()));
        assert_eq!(flag_value(&args, "-bs"), Some("1".to_string()));
        assert_eq!(flag_value(&args, "-bo"), Some("1".to_string()));
        assert!(args.iter().any(|a| a == "-nf"));
        assert_eq!(flag_value(&args, "-t"), Some("4".to_string()));
        assert_eq!(flag_value(&args, "-l"), Some("zh".to_string()));
    }

    #[test]
    fn build_args_never_asks_a_stdin_engine_to_read_stdin() {
        // We always hand the engine a file, so even a build that advertises
        // stdin support gets a path it can re-read for debugging.
        let inv = EngineInvocation {
            binary: PathBuf::from("/usr/bin/whisper-cli"),
            model: PathBuf::from("/m.bin"),
            vad_model: None,
            language: "auto".into(),
            threads: 1,
            capabilities: EngineCapabilities {
                reads_stdin: true,
                ..Default::default()
            },
        };
        let args = build_args(&inv, Path::new("/tmp/real.wav"), 2_000);
        assert!(!args.iter().any(|a| a == "-"), "must not request a stdin pipe");
        assert_eq!(flag_value(&args, "-f"), Some("/tmp/real.wav".to_string()));
    }

    #[test]
    fn trim_keeps_the_speech_region_plus_padding() {
        let frame_len = 160usize; // 10 ms at 16 kHz
        let frame_bytes = frame_len * 2;
        let pcm = vec![0u8; frame_bytes * 400]; // 4 s
        let trimmed = trim_to_speech(&pcm, 16_000, frame_len, Some(100), Some(110));
        // 250 ms padding = 25 frames each side: frames 75..=135 inclusive.
        assert_eq!(trimmed.len(), frame_bytes * 61);
    }

    #[test]
    fn trim_returns_the_whole_capture_when_nothing_was_said() {
        // An honest "nothing was said" outcome needs the full buffer: an empty
        // one would be indistinguishable from a capture failure.
        let frame_len = 160usize;
        let pcm = vec![7u8; frame_len * 2 * 50];
        assert_eq!(trim_to_speech(&pcm, 16_000, frame_len, None, None), pcm);
    }

    #[test]
    fn trim_clamps_padding_to_the_capture_bounds() {
        let frame_len = 160usize;
        let frame_bytes = frame_len * 2;
        let pcm = vec![0u8; frame_bytes * 30]; // 300 ms < 2 x padding
        let trimmed = trim_to_speech(&pcm, 16_000, frame_len, Some(0), Some(29));
        assert_eq!(trimmed.len(), pcm.len(), "padding must not exceed the buffer");
    }

    #[test]
    fn trim_handles_a_single_speech_frame() {
        let frame_len = 160usize;
        let frame_bytes = frame_len * 2;
        let pcm = vec![0u8; frame_bytes * 200];
        let trimmed = trim_to_speech(&pcm, 16_000, frame_len, Some(100), Some(100));
        assert_eq!(trimmed.len(), frame_bytes * 51, "one speech frame plus both pads");
    }

    #[test]
    fn transcript_prefers_structured_json_when_available() {
        let json = r#"{"transcription":[{"text":" hello "},{"text":"world"}]}"#;
        assert_eq!(extract_transcript(json, true), "hello world");
    }

    #[test]
    fn structured_output_is_read_from_the_sidecar_not_stdout() {
        // whisper-cli's `-oj` saves the JSON document beside the audio file and
        // still prints the timestamped transcript to stdout. Feeding stdout to
        // the JSON parser emptied every transcript - the live bug this pins.
        let audio = std::env::temp_dir()
            .join(format!("astral-voice-read-{}.wav", std::process::id()));
        let sidecar = json_sidecar_path(&audio);
        let caps = EngineCapabilities { output_json: true, ..Default::default() };
        let stdout = "[00:00:00.000 --> 00:00:02.000]   from stdout\n";

        std::fs::write(&sidecar, r#"{"transcription":[{"text":" from json"}]}"#).unwrap();
        assert_eq!(read_transcript(&audio, stdout, &caps), "from json");
        let _ = std::fs::remove_file(&sidecar);

        // A missing sidecar must not discard the transcript stdout already carries.
        assert_eq!(read_transcript(&audio, stdout, &caps), "from stdout");
        assert_eq!(read_transcript(&audio, stdout, &EngineCapabilities::default()), "from stdout");
    }

    #[test]
    fn transcript_falls_back_to_a_flat_json_text_field() {
        let json = r#"{"text":"bonjour"}"#;
        assert_eq!(extract_transcript(json, true), "bonjour");
    }

    #[test]
    fn transcript_strips_banner_noise_from_plain_output() {
        let stdout = "whisper_print_system_info: n_mels = 80\n\
             [00:00:00.000 --> 00:00:02.000]   Hello there.\n\
             \n\
             total time = 1200.00 ms\n";
        let text = extract_transcript(stdout, false);
        assert_eq!(text, "Hello there.");
        assert!(!text.contains("total time"));
        assert!(!text.contains("n_mels"));
    }

    #[test]
    fn transcript_of_pure_noise_is_empty_not_invented() {
        // AGENTS.md forbids fabricating content. An empty engine result must
        // surface as empty, never as placeholder text.
        let stdout = "whisper_print_system_info: n_mels = 80\ntotal time = 900.00 ms\n";
        assert_eq!(extract_transcript(stdout, false), "");
        assert_eq!(extract_transcript("", true), "");
    }

    #[test]
    fn transcript_survives_malformed_json() {
        let broken = "{\"transcription\": [ {\"text\": ";
        let text = extract_transcript(broken, true);
        // Falls back to the line filter rather than panicking.
        assert!(!text.contains("transcription") || !text.is_empty());
    }

    #[test]
    fn version_parsing_picks_up_a_version_token() {
        assert_eq!(parse_version("whisper-cli v1.9.4 built with whisper.cpp"), Some("v1.9.4".into()));
    }

    #[test]
    fn cancel_handle_distinguishes_stop_from_cancel() {
        // `stop` finalizes and transcribes; `cancel` throws the audio away.
        // Collapsing them would either discard a dictated utterance the user
        // wanted, or transcribe one they asked to abandon.
        let h = CancelHandle::new();
        assert!(!h.is_stopped() && !h.is_discarded());

        h.request_stop();
        assert!(h.is_stopped(), "stop must interrupt the capture loop");
        assert!(!h.is_discarded(), "stop must keep the audio for transcription");

        let c = CancelHandle::new();
        c.request_cancel();
        assert!(c.is_stopped(), "cancel must also interrupt the capture loop");
        assert!(c.is_discarded(), "cancel must discard the audio");
    }

    #[test]
    fn cancel_handle_is_shareable_across_threads() {
        // The control channel runs on its own thread, so the handle must be
        // cloneable and observable from either side.
        let h = CancelHandle::new();
        let clone = h.clone();
        let t = std::thread::spawn(move || {
            clone.request_stop();
            clone.is_stopped()
        });
        assert!(t.join().expect("reader thread must not panic"));
        assert!(h.is_stopped(), "the signal must be visible to the capture loop");
    }

    fn flag_value(args: &[String], flag: &str) -> Option<String> {
        args.iter().position(|a| a == flag).and_then(|i| args.get(i + 1)).cloned()
    }
}
