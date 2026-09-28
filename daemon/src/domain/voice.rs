//! Voice input domain model.
//!
//! Everything in this module is **pure**: no I/O, no engine knowledge, no async.
//! It is the only part of the voice feature that is meaningful to unit-test on a
//! machine with no speech engine, no model and no microphone, which is exactly
//! what `docs/VOICE-INPUT-SPEC.md` §8 relies on.
//!
//! See `docs/VOICE-INPUT-SPEC.md` for the decision record behind these types.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

/// Which end of the PipeWire graph to record from.
///
/// This value object exists because the audio visualizer used to hardcode the
/// sink-monitor case inline. Adding microphone capture by generalising the
/// existing builder is the only sanctioned way to grow it -- adding a second,
/// parallel builder is the duplication trap this type exists to prevent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CaptureTarget {
    /// Record the monitor of the default output device (speakers/headphones).
    Sink,
    /// Record the default input device (microphone).
    Source,
}

impl CaptureTarget {
    /// The `pw-record --target` value for this target.
    pub fn target_token(self) -> &'static str {
        match self {
            CaptureTarget::Sink => "@DEFAULT_AUDIO_SINK@",
            CaptureTarget::Source => "@DEFAULT_AUDIO_SOURCE@",
        }
    }

    /// The `-P` stream properties, or `None` when PipeWire's default is correct.
    ///
    /// `pw-record` already defaults to source capture, so emitting an explicit
    /// `"stream.capture.sink": false` would be noise. Only the sink-monitor
    /// case needs the property, which is why this is an `Option`.
    pub fn stream_properties(self) -> Option<&'static str> {
        match self {
            CaptureTarget::Sink => Some("{\"stream.capture.sink\": true}"),
            CaptureTarget::Source => None,
        }
    }
}

/// Builds the `pw-record` argument vector for a capture target.
///
/// This is the single builder for **both** the visualizer (sink monitor) and
/// voice input (microphone). The `CaptureTarget::Sink` invocation with
/// `rate = 8000, latency_ms = 32` must stay byte-identical to the historical
/// `audio_visualizer::build_pw_record_args()` output; `daemon/tests/test_audio_visualizer.rs`
/// asserts that and is deliberately left unmodified as the non-regression proof.
pub fn pw_record_args(
    target: CaptureTarget,
    sample_rate: u32,
    channels: u16,
    latency_ms: u32,
) -> Vec<String> {
    let mut args: Vec<String> = Vec::with_capacity(15);
    // --raw: disables the AU container so stdout carries pure PCM frames.
    args.push("--raw".to_string());

    if let Some(props) = target.stream_properties() {
        args.push("-P".to_string());
        args.push(props.to_string());
    }

    args.push("--target".to_string());
    args.push(target.target_token().to_string());

    args.push("--latency".to_string());
    args.push(format!("{}ms", latency_ms));

    args.push("--rate".to_string());
    args.push(sample_rate.to_string());

    args.push("--channels".to_string());
    args.push(channels.to_string());

    // s16 == signed 16-bit little-endian, which is what whisper consumes natively.
    args.push("--format".to_string());
    args.push("s16".to_string());

    // "-" means stdout.
    args.push("-".to_string());
    args
}

// ---------------------------------------------------------------------------
// PCM / WAV
// ---------------------------------------------------------------------------

/// whisper's native capture format. Re-encoding is deliberately out of scope:
/// `pw-record` converts to this rate, so the daemon never resamples.
pub const SPEECH_SAMPLE_RATE: u32 = 16_000;
pub const SPEECH_CHANNELS: u16 = 1;
pub const SPEECH_BITS_PER_SAMPLE: u16 = 16;

/// Bytes per sample for signed 16-bit audio.
pub const SPEECH_BYTES_PER_SAMPLE: u16 = 2;

/// Canonical 44-byte RIFF/WAVE PCM header length.
pub const WAV_HEADER_LEN: usize = 44;

/// Describes the layout of a raw PCM buffer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PcmSpec {
    pub sample_rate: u32,
    pub channels: u16,
    pub bits_per_sample: u16,
}

impl PcmSpec {
    /// The 16 kHz mono s16 format used for speech capture.
    pub const fn speech() -> Self {
        Self {
            sample_rate: SPEECH_SAMPLE_RATE,
            channels: SPEECH_CHANNELS,
            bits_per_sample: SPEECH_BITS_PER_SAMPLE,
        }
    }

    /// Bytes per audio frame (all channels of one sample instant).
    pub const fn block_align(self) -> u16 {
        self.channels * (self.bits_per_sample / 8)
    }

    /// Bytes per second of audio.
    pub const fn byte_rate(self) -> u32 {
        self.sample_rate * self.block_align() as u32
    }

    /// Nanoseconds of audio represented by a PCM payload of `data_len` bytes.
    pub fn duration_ns(self, data_len: usize) -> u64 {
        let byte_rate = self.byte_rate();
        if byte_rate == 0 {
            return 0;
        }
        (data_len as u64 * 1_000_000_000) / byte_rate as u64
    }
}

impl Default for PcmSpec {
    fn default() -> Self {
        Self::speech()
    }
}

/// Builds the canonical 44-byte RIFF/WAVE PCM header for a payload of `data_len` bytes.
pub fn wav_header(spec: PcmSpec, data_len: u32) -> Vec<u8> {
    let mut h = Vec::with_capacity(WAV_HEADER_LEN);
    let block_align = spec.block_align();
    let byte_rate = spec.byte_rate();

    // "RIFF" + chunk size + "WAVE"
    h.extend_from_slice(b"RIFF");
    h.extend_from_slice(&(36u32 + data_len).to_le_bytes());
    h.extend_from_slice(b"WAVE");

    // "fmt " sub-chunk: PCM (format tag 1)
    h.extend_from_slice(b"fmt ");
    h.extend_from_slice(&16u32.to_le_bytes()); // PCM fmt chunk size
    h.extend_from_slice(&1u16.to_le_bytes()); // WAVE_FORMAT_PCM
    h.extend_from_slice(&spec.channels.to_le_bytes());
    h.extend_from_slice(&spec.sample_rate.to_le_bytes());
    h.extend_from_slice(&byte_rate.to_le_bytes());
    h.extend_from_slice(&block_align.to_le_bytes());
    h.extend_from_slice(&spec.bits_per_sample.to_le_bytes());

    // "data" sub-chunk
    h.extend_from_slice(b"data");
    h.extend_from_slice(&data_len.to_le_bytes());

    h
}

/// Wraps raw PCM in a WAV container.
pub fn wav_container(spec: PcmSpec, pcm: &[u8]) -> Vec<u8> {
    let mut out = wav_header(spec, pcm.len() as u32);
    out.extend_from_slice(pcm);
    out
}

/// Converts signed 16-bit little-endian PCM bytes to normalized `[-1.0, 1.0]` floats.
pub fn pcm_bytes_to_f32(bytes: &[u8]) -> Vec<f32> {
    bytes
        .chunks_exact(2)
        .map(|c| i16::from_le_bytes([c[0], c[1]]) as f32 / 32768.0)
        .collect()
}

/// AC root-mean-square of a sample frame.
///
/// The mean is removed first, so a constant or DC-offset signal reads as `0.0`
/// rather than as its own offset level. That matters for two reasons: a capture
/// device latching to a DC rail must not be mistaken for continuous speech, and
/// it mirrors the existing DC-latch guard in `AudioAnalyzer::calculate_rms`.
///
/// Non-finite samples are skipped rather than propagated, so one bad value can
/// never poison a level reading and silently break endpointing.
pub fn frame_rms(samples: &[f32]) -> f32 {
    let mut sum = 0.0f64;
    let mut n = 0usize;
    for s in samples {
        if s.is_finite() {
            sum += *s as f64;
            n += 1;
        }
    }
    if n == 0 {
        return 0.0;
    }
    let mean = (sum / n as f64) as f32;

    let mut acc = 0.0f64;
    let mut m = 0usize;
    for s in samples {
        if s.is_finite() {
            let d = s - mean;
            acc += (d * d) as f64;
            m += 1;
        }
    }
    if m == 0 {
        return 0.0;
    }
    (acc / m as f64).sqrt() as f32
}

// ---------------------------------------------------------------------------
// Adaptive silence detection (endpointing)
// ---------------------------------------------------------------------------

/// Number of frames averaged into the noise-floor estimate.
const FLOOR_WINDOW: usize = 48;
/// A frame counts as speech when its level rises this far above the floor.
/// Expressed as a ratio rather than an absolute threshold so the detector
/// tracks the room instead of assuming a fixed noise level.
pub const SILENCE_HEADROOM: f32 = 3.0;
/// Frames required before silence is judged at all. Without warm-up, the
/// leading quiet frames of an utterance would immediately look like its end.
pub const SILENCE_WARMUP_FRAMES: u32 = 25;
/// Floor must stay under this to be treated as a genuine quiet room.
const MAX_TRACKABLE_FLOOR: f32 = 0.05;

/// Outcome of feeding one frame to the detector.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SilenceDecision {
    /// RMS of the frame just pushed.
    pub level: f32,
    /// Current estimate of the room's quiet floor.
    pub floor: f32,
    /// Whether the frame was classified as speech.
    pub speaking: bool,
    /// Consecutive milliseconds of trailing silence.
    pub silent_for_ms: u64,
}

/// Adaptive endpointing detector.
///
/// whisper.cpp's bundled Silero VAD turned out to be unusable for this purpose:
/// the model asset is not published at the expected path (HTTP 404) and the
/// engine's `--vad` switch is an inference-time filter over a finished file, not
/// a live "has the user stopped talking" oracle. See `docs/VOICE-INPUT-SPEC.md`
/// D4 for the full reasoning.
///
/// This detector therefore tracks a rolling quiet floor and judges each frame
/// relative to it. It is a pure function of its input, so it is unit-tested
/// against synthetic speech, noise and DC-latch signals.
#[derive(Debug, Clone)]
pub struct SilenceDetector {
    floor_samples: Vec<f32>,
    floor_sum: f32,
    frames_seen: u32,
    silent_for_ms: u64,
    frame_ms: u64,
}

impl SilenceDetector {
    /// `frame_ms` is the wall-clock duration of one frame; `frame_len` its sample count.
    pub fn new(frame_len: usize, sample_rate: u32) -> Self {
        let frame_ms = if frame_len == 0 || sample_rate == 0 {
            0
        } else {
            (frame_len as u64 * 1000) / sample_rate as u64
        };
        Self {
            floor_samples: Vec::with_capacity(FLOOR_WINDOW),
            floor_sum: 0.0,
            frames_seen: 0,
            silent_for_ms: 0,
            frame_ms,
        }
    }

    /// Duration of one frame in milliseconds.
    pub fn frame_ms(&self) -> u64 {
        self.frame_ms
    }

    /// Current rolling quiet-floor estimate.
    pub fn floor(&self) -> f32 {
        if self.floor_samples.is_empty() {
            0.0
        } else {
            self.floor_sum / self.floor_samples.len() as f32
        }
    }

    /// Trailing silence accumulated so far.
    pub fn silent_for_ms(&self) -> u64 {
        self.silent_for_ms
    }

    /// Feeds one frame and reports what the detector concluded.
    pub fn push(&mut self, level: f32) -> SilenceDecision {
        let level = if level.is_finite() && level > 0.0 { level } else { 0.0 };
        self.frames_seen += 1;

        // Only near-quiet frames inform the floor. A loud room (floor at or above
        // MAX_TRACKABLE_FLOOR) is left alone rather than dragging the estimate up
        // until real speech is mistaken for the background. The boundary is
        // inclusive so a room sitting exactly on the limit is still trackable.
        if level <= MAX_TRACKABLE_FLOOR {
            self.floor_samples.push(level);
            self.floor_sum += level;
            if self.floor_samples.len() > FLOOR_WINDOW {
                let evicted = self.floor_samples.remove(0);
                self.floor_sum -= evicted;
            }
        }

        // During the first SILENCE_WARMUP_FRAMES the detector only learns the
        // room; it neither declares speech nor starts counting silence. This
        // keeps the constant's meaning exact and prevents the quiet opening of
        // an utterance from burning part of the hangover budget.
        let warmed_up = self.frames_seen > SILENCE_WARMUP_FRAMES;
        let speaking = warmed_up && level > self.floor() * SILENCE_HEADROOM;

        if speaking {
            self.silent_for_ms = 0;
        } else if warmed_up {
            self.silent_for_ms = self.silent_for_ms.saturating_add(self.frame_ms);
        } else {
            self.silent_for_ms = 0;
        }

        SilenceDecision {
            level,
            floor: self.floor(),
            speaking,
            silent_for_ms: self.silent_for_ms,
        }
    }
}

/// Whether a recording session should auto-finalize.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FinalizeReason {
    /// The user asked to stop, or pressed Enter. Always wins.
    Manual,
    /// Trailing silence exceeded the configured hangover.
    Silence,
    /// The utterance hit the hard cap.
    DurationCap,
}

/// Decides whether an utterance is complete.
///
/// `has_speech` guards against finalizing on a recording that never contained
/// speech, so an accidental mic click cannot produce a bogus transcript.
pub fn should_finalize(
    reason: FinalizeReason,
    elapsed_ms: u64,
    silent_for_ms: u64,
    has_speech: bool,
    silence_hangover_ms: u64,
    max_utterance_ms: u64,
) -> bool {
    if reason == FinalizeReason::Manual {
        return true;
    }
    if !has_speech {
        // Nothing was ever said; only the hard cap ends the wait.
        return elapsed_ms >= max_utterance_ms;
    }
    if max_utterance_ms > 0 && elapsed_ms >= max_utterance_ms {
        return true;
    }
    silence_hangover_ms > 0 && silent_for_ms >= silence_hangover_ms
}

// ---------------------------------------------------------------------------
// Language
// ---------------------------------------------------------------------------

/// Sentinel meaning "let the engine decide".
pub const LANGUAGE_AUTO: &str = "auto";
/// Sentinel meaning detection was inconclusive. Never replace this with a guess.
pub const LANGUAGE_UNDETERMINED: &str = "und";

/// Locales offered in the UI. Rendered from this list, so extending coverage is
/// a data change. Chinese is first because it is the hardest case here.
pub const SUPPORTED_LANGUAGES: &[(&str, &str)] = &[
    ("auto", "Auto-detect"),
    ("zh", "中文 (Chinese)"),
    ("en", "English"),
    ("fr", "Français (French)"),
    ("de", "Deutsch (German)"),
    ("it", "Italiano (Italian)"),
    ("es", "Español (Spanish)"),
    ("pt", "Português (Portuguese)"),
    ("ru", "Русский (Russian)"),
    ("ja", "日本語 (Japanese)"),
    ("ko", "한국어 (Korean)"),
    ("ar", "العربية (Arabic)"),
    ("hi", "हिन्दी (Hindi)"),
    ("nl", "Nederlands (Dutch)"),
    ("pl", "Polski (Polish)"),
    ("tr", "Türkçe (Turkish)"),
    ("uk", "Українська (Ukrainian)"),
    ("vi", "Tiếng Việt (Vietnamese)"),
    ("id", "Bahasa Indonesia"),
    ("th", "ไทย (Thai)"),
];

/// Normalizes a user- or engine-supplied language tag.
///
/// Collapses region variants to their base (`zh-CN`, `ZH_TW` -> `zh`), lowercases,
/// treats empty as auto-detect, and falls back to `auto` for tags outside
/// [`SUPPORTED_LANGUAGES`]. Passing an unknown tag straight to the engine would
/// surface as an opaque failure, so it is caught here instead.
pub fn normalize_language(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return LANGUAGE_AUTO.to_string();
    }
    if trimmed.eq_ignore_ascii_case(LANGUAGE_AUTO) {
        return LANGUAGE_AUTO.to_string();
    }

    // `zh-Hans`, `zh_CN`, `pt-BR` -> base subtag.
    let base = trimmed
        .split(['-', '_'])
        .next()
        .unwrap_or(trimmed)
        .trim()
        .to_ascii_lowercase();

    if base.is_empty() {
        return LANGUAGE_AUTO.to_string();
    }
    if is_supported_language(&base) {
        base
    } else {
        LANGUAGE_AUTO.to_string()
    }
}

/// Whether a normalized base subtag is in [`SUPPORTED_LANGUAGES`].
pub fn is_supported_language(base: &str) -> bool {
    let b = base.trim().to_ascii_lowercase();
    if b == LANGUAGE_AUTO {
        return true;
    }
    SUPPORTED_LANGUAGES.iter().any(|(code, _)| *code == b)
}

// ---------------------------------------------------------------------------
// Model catalog
// ---------------------------------------------------------------------------

/// Base URL the models are served from.
pub const MODEL_BASE_URL: &str = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main";

/// The Silero VAD asset whisper.cpp uses to drop non-speech before decoding.
///
/// It lives in its own public repository, not in the ASR model repo: upstream's
/// `models/download-vad-model.sh` downloads from `ggml-org/whisper-vad`. An
/// earlier attempt to fetch it from `ggml-org/whisper.cpp` saw HTTP 401 and
/// concluded "unreachable" - but Hugging Face answers 401 (not 404) for paths
/// an anonymous client may not see, and that path is not a public repo at all.
/// The asset is public, 885 KiB, and needs no credentials.
pub const VAD_MODEL_FILE: &str = "ggml-silero-v5.1.2.bin";
/// Verified by HTTP `HEAD`/download against [`VAD_MODEL_BASE_URL`].
pub const VAD_MODEL_SIZE_BYTES: u64 = 885_098;
/// Upstream's own source for the VAD asset.
pub const VAD_MODEL_BASE_URL: &str = "https://huggingface.co/ggml-org/whisper-vad/resolve/main";

/// Direct download URL for the VAD asset.
pub fn vad_model_url() -> String {
    format!("{VAD_MODEL_BASE_URL}/{VAD_MODEL_FILE}")
}

/// A downloadable speech model, as declared in the catalog.
///
/// Deliberately a const-friendly struct with `&'static str` fields so the catalog
/// itself can be a `const` slice rather than a lazily built `Vec`. The
/// serializable projection the settings UI consumes is [`ModelDescriptor`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ModelEntry {
    pub id: &'static str,
    pub display_name: &'static str,
    /// Size on disk, verified by HTTP HEAD against [`MODEL_BASE_URL`].
    pub size_bytes: u64,
}

impl ModelEntry {
    /// File name the model takes inside the models directory.
    pub fn file_name(&self) -> String {
        format!("{}.bin", self.id)
    }

    /// Direct download URL.
    pub fn url(&self) -> String {
        format!("{}/{}.bin", MODEL_BASE_URL, self.id)
    }

    /// Rough human-readable size, e.g. `1549 MiB`.
    pub fn size_label(&self) -> String {
        format_size(self.size_bytes)
    }

    /// Serializable projection for the settings UI.
    pub fn to_descriptor(&self) -> ModelDescriptor {
        ModelDescriptor {
            id: self.id.to_string(),
            display_name: self.display_name.to_string(),
            size_bytes: self.size_bytes,
            size_label: self.size_label(),
        }
    }
}

/// The serializable form of a [`ModelEntry`], as sent to the UI.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ModelDescriptor {
    pub id: String,
    pub display_name: String,
    pub size_bytes: u64,
    pub size_label: String,
}

/// Human-readable byte size, e.g. `1549 MiB`.
pub fn format_size(bytes: u64) -> String {
    const MIB: u64 = 1024 * 1024;
    const GIB: u64 = 1024 * 1024 * 1024;
    if bytes >= GIB {
        format!("{:.2} GiB", bytes as f64 / GIB as f64)
    } else if bytes >= MIB {
        format!("{} MiB", bytes / MIB)
    } else if bytes >= 1024 {
        format!("{} KiB", bytes / 1024)
    } else {
        format!("{} B", bytes)
    }
}

/// The default model: the largest tier that still runs near realtime on a CPU.
///
/// The engine ships CPU-only on every distribution we support, and the measured
/// cost is steep: on a 12th-gen i9, `ggml-large-v3-turbo` took ~26s to
/// transcribe a 4.9s clip while `ggml-small` took ~4s (near realtime). An
/// interactive dictation feature cannot default to the slowest catalog entry;
/// the large tiers stay one download away in the picker.
pub const DEFAULT_MODEL_ID: &str = "ggml-small";

/// Available models, cheapest first. Sizes verified 2026-09-27.
pub const MODEL_CATALOG: &[ModelEntry] = &[
    ModelEntry {
        id: "ggml-tiny",
        display_name: "Tiny (fastest, lowest quality)",
        size_bytes: 77_691_713,
    },
    ModelEntry {
        id: "ggml-base",
        display_name: "Base (low resource)",
        size_bytes: 147_951_465,
    },
    ModelEntry {
        id: DEFAULT_MODEL_ID,
        display_name: "Small (balanced, default)",
        size_bytes: 487_601_967,
    },
    ModelEntry {
        id: "ggml-large-v3-turbo-q5_0",
        display_name: "Large v3 Turbo (Q5, best size/quality)",
        size_bytes: 574_041_195,
    },
    ModelEntry {
        id: "ggml-medium",
        display_name: "Medium",
        size_bytes: 1_533_763_059,
    },
    ModelEntry {
        id: "ggml-large-v3-turbo",
        display_name: "Large v3 Turbo (highest accuracy, CPU-heavy)",
        size_bytes: 1_624_555_275,
    },
    ModelEntry {
        id: "ggml-large-v3",
        display_name: "Large v3 (highest quality)",
        size_bytes: 3_095_033_483,
    },
];

/// Looks a model up by id, falling back to [`DEFAULT_MODEL_ID`].
pub fn model_by_id(id: &str) -> &'static ModelEntry {
    MODEL_CATALOG
        .iter()
        .find(|m| m.id == id)
        .or_else(|| MODEL_CATALOG.iter().find(|m| m.id == DEFAULT_MODEL_ID))
        .expect("model catalog must contain the default model")
}

/// Every model as a serializable descriptor, for the settings UI.
pub fn model_descriptors() -> Vec<ModelDescriptor> {
    MODEL_CATALOG.iter().map(|m| m.to_descriptor()).collect()
}

/// Directory holding downloaded models: `$XDG_CACHE_HOME/astral-plasma/models`.
pub fn models_dir() -> PathBuf {
    crate::domain::branding::cache_dir().join("models")
}

/// Resolves a model's on-disk path. A zero-length file is reported as absent:
/// an interrupted download must not be mistaken for a usable model.
pub fn resolve_model_file(model_id: &str) -> Option<PathBuf> {
    let path = models_dir().join(model_by_id(model_id).file_name());
    match std::fs::metadata(&path) {
        Ok(meta) if meta.len() > 0 => Some(path),
        _ => None,
    }
}

/// Whether a model id names something in the catalog.
pub fn is_known_model(id: &str) -> bool {
    MODEL_CATALOG.iter().any(|m| m.id == id)
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

pub const DEFAULT_ENGINE: &str = "whisper-cpp";
pub const DEFAULT_MAX_UTTERANCE_SECS: u32 = 30;
pub const MIN_MAX_UTTERANCE_SECS: u32 = 5;
pub const MAX_MAX_UTTERANCE_SECS: u32 = 300;
pub const DEFAULT_SILENCE_HANGOVER_MS: u64 = 1200;
pub const MIN_SILENCE_HANGOVER_MS: u64 = 300;
pub const MAX_SILENCE_HANGOVER_MS: u64 = 5000;

/// Voice configuration, deserialized from the `voice` block of `settings.json`.
///
/// Field names are camelCase to match every other block in `settings.json`
/// (`pollIntervalMinutes`, `warningThresholdPercent`, ...). Without this the
/// daemon would silently fall back to defaults for every configured value.
///
/// Every field carries a serde default so an absent or partial block yields a
/// valid configuration instead of a startup failure, and out-of-range values are
/// clamped rather than rejected. A shell must always start.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct VoiceSettings {
    pub enabled: bool,
    pub engine: String,
    pub model: String,
    pub language: String,
    pub max_utterance_seconds: u32,
    pub silence_hangover_ms: u64,
    pub auto_finalize: bool,
    pub install_model_on_demand: bool,
}

impl Default for VoiceSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            engine: DEFAULT_ENGINE.to_string(),
            model: DEFAULT_MODEL_ID.to_string(),
            language: LANGUAGE_AUTO.to_string(),
            max_utterance_seconds: DEFAULT_MAX_UTTERANCE_SECS,
            silence_hangover_ms: DEFAULT_SILENCE_HANGOVER_MS,
            auto_finalize: true,
            install_model_on_demand: true,
        }
    }
}

impl VoiceSettings {
    /// Applies every documented clamp and fallback.
    pub fn sanitized(mut self) -> Self {
        if !is_known_model(&self.model) {
            self.model = DEFAULT_MODEL_ID.to_string();
        }
        if self.engine.trim().is_empty() {
            self.engine = DEFAULT_ENGINE.to_string();
        }
        self.language = normalize_language(&self.language);
        self.max_utterance_seconds = self
            .max_utterance_seconds
            .clamp(MIN_MAX_UTTERANCE_SECS, MAX_MAX_UTTERANCE_SECS);
        self.silence_hangover_ms = self
            .silence_hangover_ms
            .clamp(MIN_SILENCE_HANGOVER_MS, MAX_SILENCE_HANGOVER_MS);
        self
    }

    /// Hard cap on one utterance, in milliseconds.
    pub fn max_utterance_ms(&self) -> u64 {
        self.max_utterance_seconds as u64 * 1000
    }
}

// ---------------------------------------------------------------------------
// Events and results
// ---------------------------------------------------------------------------

/// Where a voice session currently is.
///
/// `Finalizing` is a distinct state rather than an overload of `Recording` so the
/// UI can show that the microphone has been released while the engine works, and
/// keep the send button honest about what is still possible.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VoiceState {
    Idle,
    Recording,
    Finalizing,
    Failed,
}

impl VoiceState {
    /// Whether the microphone is currently held open.
    pub fn is_capturing(self) -> bool {
        matches!(self, VoiceState::Recording)
    }
}

/// A finished transcription.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Transcript {
    pub text: String,
    /// Normalized language tag, [`LANGUAGE_AUTO`], or [`LANGUAGE_UNDETERMINED`].
    pub language: String,
    pub duration_ms: u64,
    pub engine: String,
    pub model: String,
}

impl Transcript {
    /// Whether the engine produced any words. An empty transcript is a real
    /// outcome (silence, noise) and must never be dressed up as content.
    pub fn is_empty(&self) -> bool {
        self.text.trim().is_empty()
    }
}

/// Everything a session needs to run.
#[derive(Debug, Clone, PartialEq)]
pub struct VoiceSessionConfig {
    pub capture: CaptureTarget,
    pub model: String,
    pub language: String,
    pub silence_hangover_ms: u64,
    pub max_utterance_ms: u64,
    pub auto_finalize: bool,
    /// Frame length pushed through the silence detector.
    pub frame_len: usize,
    pub sample_rate: u32,
}

impl VoiceSessionConfig {
    /// Derives a session config from settings, honouring `auto_finalize`.
    pub fn from_settings(settings: &VoiceSettings) -> Self {
        let frame_len = (SPEECH_SAMPLE_RATE as usize / 50).max(1); // 20 ms frames
        let mut cfg = Self {
            capture: CaptureTarget::Source,
            model: settings.model.clone(),
            language: normalize_language(&settings.language),
            silence_hangover_ms: if settings.auto_finalize {
                settings.silence_hangover_ms
            } else {
                0
            },
            max_utterance_ms: settings.max_utterance_ms(),
            auto_finalize: settings.auto_finalize,
            frame_len,
            sample_rate: SPEECH_SAMPLE_RATE,
        };
        if !is_known_model(&cfg.model) {
            cfg.model = DEFAULT_MODEL_ID.to_string();
        }
        cfg
    }
}

/// Events streamed from a voice session, one JSON object per line.
///
/// Adjacency-tagged to match `domain::assistant::AssistantEvent`, so the QML
/// `SplitParser` sees the same `{"type": ..., "payload": ...}` shape it already
/// parses for chat streaming.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum VoiceEvent {
    StateChanged { state: VoiceState },
    Level { rms: f32 },
    /// Install progress as a bare fraction (`{"type":"Progress","payload":0.42}`).
    ///
    /// A newtype on purpose: the UI reads `payload` as a number, so the value has
    /// to *be* the payload. Reusing `Level { rms }` for progress shipped an
    /// object (`{"rms":0.42}`) that no progress bar could read - which is how a
    /// 1.5 GiB download sat at 0% and then jumped to "downloaded".
    Progress(f32),
    Partial { text: String },
    /// Newtype rather than a struct variant so `payload` *is* the transcript
    /// object, letting the QML side read `payload.text` directly.
    Final(Transcript),
    Error { message: String, recoverable: bool },
}

impl VoiceEvent {
    /// Convenience constructor for a recoverable setup gap.
    pub fn setup_error(message: impl Into<String>) -> Self {
        VoiceEvent::Error {
            message: message.into(),
            recoverable: true,
        }
    }

    /// Convenience constructor for a session-ending failure.
    pub fn fatal_error(message: impl Into<String>) -> Self {
        VoiceEvent::Error {
            message: message.into(),
            recoverable: false,
        }
    }

    /// The transcript, if this is a `Final` event.
    pub fn as_final(&self) -> Option<&Transcript> {
        match self {
            VoiceEvent::Final(t) => Some(t),
            _ => None,
        }
    }

    /// Stable discriminator, used by tests and by the QML event switch.
    pub fn kind(&self) -> &'static str {
        match self {
            VoiceEvent::StateChanged { .. } => "StateChanged",
            VoiceEvent::Level { .. } => "Level",
            VoiceEvent::Progress(_) => "Progress",
            VoiceEvent::Partial { .. } => "Partial",
            VoiceEvent::Final(_) => "Final",
            VoiceEvent::Error { .. } => "Error",
        }
    }
}

/// Why a voice session cannot currently run.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SetupGap {
    /// No speech engine binary could be located.
    EngineMissing,
    /// The configured model has not been downloaded.
    ModelMissing,
    /// No capture device is available.
    NoAudioSource,
    /// Engine and model are both present.
    Ready,
}

impl SetupGap {
    /// Whether the user can fix this from the UI.
    pub fn is_recoverable(self) -> bool {
        !matches!(self, SetupGap::Ready)
    }
}

/// Classifies readiness from the three independent preconditions.
///
/// A missing engine is reported ahead of a missing model, because installing the
/// engine is the step the user has to take first -- telling them to download
/// 1.5 GiB for an engine that isn't there would be a dead end.
pub fn setup_gap_for(engine_available: bool, model_present: bool, has_audio_source: bool) -> SetupGap {
    if !engine_available {
        return SetupGap::EngineMissing;
    }
    if !has_audio_source {
        return SetupGap::NoAudioSource;
    }
    if !model_present {
        return SetupGap::ModelMissing;
    }
    SetupGap::Ready
}

/// What the engine binary can actually do, discovered by probing `--help`.
///
/// The exact `whisper-cpp` CLI surface could not be verified when this was
/// authored (the package is not installed and the host has no passwordless
/// `sudo`), so rather than hardcode a guessed flag list, the adapter probes the
/// installed build and emits only supported flags.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct EngineCapabilities {
    pub reads_stdin: bool,
    pub vad: bool,
    pub vad_model: bool,
    /// `-ac` / `--audio-ctx`: sizes the encoder window. Without it the engine
    /// encodes its full trained context (30s) for every clip, however short.
    pub audio_context: bool,
    /// `-bs` / `--beam-size`: beam width. Beam search multiplies the cost of
    /// every decoded token, which is how non-speech audio ran away.
    pub beam_search: bool,
    /// `-bo` / `--best-of`: sampling candidates per step.
    pub best_of: bool,
    /// `-nf` / `--no-fallback`: disables temperature-fallback retries.
    pub no_fallback: bool,
    pub language_auto: bool,
    pub output_json: bool,
    pub no_prints: bool,
    pub threads: bool,
    pub translate: bool,
}

/// The result of inspecting an engine installation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EngineProbe {
    pub engine_id: String,
    pub binary_path: Option<String>,
    pub version: Option<String>,
    pub capabilities: EngineCapabilities,
}

impl EngineProbe {
    /// A probe describing an installation that is not present.
    pub fn missing(engine_id: &str) -> Self {
        Self {
            engine_id: engine_id.to_string(),
            binary_path: None,
            version: None,
            capabilities: EngineCapabilities::default(),
        }
    }
}

/// Aggregate readiness, consumed by `voice status`, the doctor and the UI.
///
/// `setup_complete` is the single boolean the mic button derives its enabled
/// state from, so the button can never disagree with the diagnostics.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VoiceStatus {
    pub enabled: bool,
    pub engine: String,
    pub engine_available: bool,
    pub engine_path: Option<String>,
    pub engine_version: Option<String>,
    pub model: String,
    pub model_present: bool,
    pub model_path: Option<String>,
    pub model_size_bytes: u64,
    /// Whether the Silero VAD asset is installed. Optional, but it is what
    /// filters non-speech out of the audio before decoding.
    #[serde(default)]
    pub vad_model_present: bool,
    pub language: String,
    pub setup_complete: bool,
    pub gap: SetupGap,
    /// The distro-appropriate command that installs the engine, filled in only
    /// while the engine is missing. `None` means "no package we can name".
    #[serde(default)]
    pub engine_install_command: Option<String>,
    pub models_available: Vec<ModelDescriptor>,
    pub languages: Vec<LanguageOption>,
    pub capabilities: EngineCapabilities,
}

// ---------------------------------------------------------------------------
// Installing the engine
//
// "Run: sudo pacman -S whisper-cpp" is only true on Arch, and the suggestion is
// shown on whatever machine the shell is running on. A wrong one-liner is worse
// than none: it sends people to a package manager they do not have.
// ---------------------------------------------------------------------------

/// The package managers the shell can name a speech-engine package for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PackageManager {
    Pacman,
    Apt,
    Dnf,
    Zypper,
    Nix,
    Unknown,
}

impl PackageManager {
    /// The one-liner that installs the engine, or `None` for a distribution we
    /// cannot name a package for (the caller then points at the upstream
    /// build instead of inventing a command).
    pub fn engine_install_command(self) -> Option<&'static str> {
        match self {
            PackageManager::Pacman => Some("sudo pacman -S whisper-cpp"),
            PackageManager::Apt => Some("sudo apt install whisper.cpp"),
            PackageManager::Dnf => Some("sudo dnf install whisper-cpp"),
            PackageManager::Zypper => Some("sudo zypper install whisper-cpp"),
            PackageManager::Nix => Some("nix-shell -p whisper-cpp"),
            PackageManager::Unknown => None,
        }
    }
}

/// Which package manager a distribution uses, from the text of `/etc/os-release`.
///
/// Both `ID` and `ID_LIKE` are read, because derivatives inherit their family
/// rather than restating it (`ID=cachyos`, `ID_LIKE=arch`). `ID_LIKE` may list
/// several families; the first match in the table wins.
pub fn package_manager_for_os_release(os_release: &str) -> PackageManager {
    let mut families: Vec<String> = Vec::new();
    for line in os_release.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        if key != "ID" && key != "ID_LIKE" {
            continue;
        }
        let value = value.trim().trim_matches('"').to_ascii_lowercase();
        families.extend(value.split_whitespace().map(str::to_string));
    }

    let has = |ids: &[&str]| families.iter().any(|family| ids.contains(&family.as_str()));

    if has(&[
        "arch", "cachyos", "manjaro", "endeavouros", "garuda", "artix", "arcolinux",
    ]) {
        PackageManager::Pacman
    } else if has(&[
        "debian", "ubuntu", "pop", "linuxmint", "raspbian", "elementary", "zorin", "kali",
    ]) {
        PackageManager::Apt
    } else if has(&[
        "fedora", "rhel", "centos", "rocky", "almalinux", "ol", "amzn",
    ]) {
        PackageManager::Dnf
    } else if has(&[
        "opensuse",
        "opensuse-leap",
        "opensuse-tumbleweed",
        "sles",
        "suse",
        "sled",
    ]) {
        PackageManager::Zypper
    } else if has(&["nixos"]) {
        PackageManager::Nix
    } else {
        PackageManager::Unknown
    }
}

/// A language offered in the UI.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LanguageOption {
    pub code: String,
    pub label: String,
}

impl LanguageOption {
    /// The full supported set, for rendering the picker.
    pub fn all() -> Vec<Self> {
        SUPPORTED_LANGUAGES
            .iter()
            .map(|(code, label)| Self {
                code: code.to_string(),
                label: label.to_string(),
            })
            .collect()
    }
}

// ---------------------------------------------------------------------------
// Transcript insertion
// ---------------------------------------------------------------------------

/// Appends a finalized transcript to whatever the user has already typed.
///
/// Dictation must never destroy work in progress, so this appends rather than
/// assigns. The join respects what the user actually left at the cursor: a
/// trailing newline is preserved (they pressed Enter deliberately), any other
/// trailing whitespace collapses to a single separating space so the prompt
/// never gains a double space. Blank transcripts are dropped -- silence is not
/// content.
pub fn append_transcript(existing: &str, transcript: &str) -> String {
    let addition = transcript.trim();
    if addition.is_empty() {
        return existing.to_string();
    }
    let base = existing.trim_end();
    if base.is_empty() {
        return addition.to_string();
    }
    let raw_tail = &existing[base.len()..];
    if raw_tail.contains('\n') {
        format!("{}\n{}", base, addition)
    } else if base.chars().last().is_some_and(|c| !c.is_whitespace()) {
        format!("{} {}", base, addition)
    } else {
        format!("{}{}", base, addition)
    }
}

// ---------------------------------------------------------------------------
// Model download
// ---------------------------------------------------------------------------

/// Where a download should be written, and the final path it will occupy.
///
/// Downloads land on a `.part` sibling and are renamed on completion, so an
/// interrupted transfer can never be mistaken for a usable model.
pub fn staged_download_paths(dir: &Path, model_id: &str) -> (PathBuf, PathBuf) {
    let file_name = model_by_id(model_id).file_name();
    let final_path = dir.join(&file_name);
    let part_path = dir.join(format!("{}.part", file_name));
    (part_path, final_path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn visualizer_args_are_byte_identical() {
        // Pins the exact historical argv so the visualizer cannot regress.
        assert_eq!(
            pw_record_args(CaptureTarget::Sink, 8000, 1, 32),
            vec![
                "--raw",
                "-P",
                "{\"stream.capture.sink\": true}",
                "--target",
                "@DEFAULT_AUDIO_SINK@",
                "--latency",
                "32ms",
                "--rate",
                "8000",
                "--channels",
                "1",
                "--format",
                "s16",
                "-",
            ]
        );
    }

    #[test]
    fn source_args_omit_sink_property() {
        let args = pw_record_args(CaptureTarget::Source, SPEECH_SAMPLE_RATE, 1, 32);
        assert!(!args.iter().any(|a| a == "-P"), "source capture must not request sink monitor");
        assert!(!args.iter().any(|a| a.contains("stream.capture.sink")));
        let t = args.iter().position(|a| a == "--target").unwrap();
        assert_eq!(args[t + 1], "@DEFAULT_AUDIO_SOURCE@");
    }

    #[test]
    fn both_targets_share_format_contract() {
        for target in [CaptureTarget::Sink, CaptureTarget::Source] {
            let args = pw_record_args(target, SPEECH_SAMPLE_RATE, 1, 32);
            assert!(args.iter().any(|a| a == "--raw"));
            let f = args.iter().position(|a| a == "--format").unwrap();
            assert_eq!(args[f + 1], "s16", "whisper requires signed 16-bit PCM");
            assert_eq!(args.last().unwrap(), "-", "capture must stream to stdout");
        }
    }

    #[test]
    fn wav_header_is_canonical_44_bytes() {
        let h = wav_header(PcmSpec::speech(), 32000);
        assert_eq!(h.len(), WAV_HEADER_LEN);
        assert_eq!(&h[0..4], b"RIFF");
        assert_eq!(&h[8..12], b"WAVE");
        assert_eq!(&h[12..16], b"fmt ");
        assert_eq!(u32::from_le_bytes([h[16], h[17], h[18], h[19]]), 16);
        assert_eq!(u16::from_le_bytes([h[20], h[21]]), 1, "format tag must be PCM");
        assert_eq!(u16::from_le_bytes([h[22], h[23]]), 1, "channels");
        assert_eq!(u32::from_le_bytes([h[24], h[25], h[26], h[27]]), 16_000, "sample rate");
        assert_eq!(u32::from_le_bytes([h[28], h[29], h[30], h[31]]), 32_000, "byte rate");
        assert_eq!(u16::from_le_bytes([h[32], h[33]]), 2, "block align");
        assert_eq!(u16::from_le_bytes([h[34], h[35]]), 16, "bits per sample");
        assert_eq!(&h[36..40], b"data");
        assert_eq!(u32::from_le_bytes([h[40], h[41], h[42], h[43]]), 32000);
    }

    #[test]
    fn wav_container_round_trips() {
        let pcm: Vec<u8> = (0..64u16).map(|v| (v % 256) as u8).collect();
        let wav = wav_container(PcmSpec::speech(), &pcm);
        assert_eq!(wav.len(), WAV_HEADER_LEN + pcm.len());
        assert_eq!(&wav[WAV_HEADER_LEN..], &pcm[..]);
    }

    #[test]
    fn pcm_duration_matches_byte_rate() {
        let spec = PcmSpec::speech();
        // 1 second of 16 kHz mono s16 is 32,000 bytes.
        assert_eq!(spec.duration_ns(32_000), 1_000_000_000);
    }

    #[test]
    fn frame_rms_of_dc_latch_is_zero() {
        // A constant DC signal carries no acoustic energy. Mirrors the
        // visualizer's DC-latch guard, which exists for the same hardware.
        assert_eq!(frame_rms(&vec![-1.0f32; 320]), 0.0);
        assert_eq!(frame_rms(&[0.0; 320]), 0.0);
        assert_eq!(frame_rms(&[]), 0.0);
    }

    #[test]
    fn silence_detector_ignores_leading_silence_until_warmup() {
        let mut d = SilenceDetector::new(320, 16_000);
        for _ in 0..SILENCE_WARMUP_FRAMES {
            d.push(0.0005);
        }
        assert_eq!(d.silent_for_ms(), 0, "warm-up must not accumulate trailing silence");

        // Counting may only begin after warm-up, so the hangover is never
        // pre-paid by the quiet opening of an utterance.
        const TOTAL: u32 = 85;
        for _ in 0..(TOTAL - SILENCE_WARMUP_FRAMES) {
            d.push(0.0005);
        }
        let expected = (TOTAL - SILENCE_WARMUP_FRAMES) as u64 * d.frame_ms();
        assert_eq!(
            d.silent_for_ms(),
            expected,
            "silence must account for exactly the post-warm-up frames"
        );
    }

    #[test]
    fn silence_detector_finds_trailing_silence_after_speech() {
        let mut d = SilenceDetector::new(320, 16_000);
        assert_eq!(d.frame_ms(), 20);
        for _ in 0..30 {
            d.push(0.0004);
        }
        // 40 frames of loud speech, then quiet tail.
        for _ in 0..40 {
            let dec = d.push(0.30);
            assert!(dec.speaking, "loud frames must register as speech");
            assert_eq!(dec.silent_for_ms, 0);
        }
        let mut tail = 0;
        for _ in 0..80 {
            let dec = d.push(0.0004);
            if dec.silent_for_ms > 0 {
                tail = dec.silent_for_ms;
            }
        }
        assert!(tail >= 1200, "expected >=1200ms trailing silence, got {}", tail);
    }

    #[test]
    fn silence_detector_does_not_drift_in_a_loud_room() {
        // Constant moderate noise: the floor must not creep up until the signal
        // starts looking like silence.
        let mut d = SilenceDetector::new(320, 16_000);
        for _ in 0..400 {
            d.push(0.08);
        }
        assert!(d.floor() <= MAX_TRACKABLE_FLOOR, "floor must not absorb loud-room noise");
    }

    #[test]
    fn manual_stop_always_finalizes() {
        assert!(should_finalize(FinalizeReason::Manual, 0, 0, false, 1200, 30_000));
    }

    #[test]
    fn no_speech_waits_for_the_hard_cap() {
        assert!(!should_finalize(FinalizeReason::Silence, 1000, 5000, false, 1200, 30_000));
        assert!(should_finalize(FinalizeReason::Silence, 30_000, 5000, false, 1200, 30_000));
    }

    #[test]
    fn duration_cap_overrides_long_speech() {
        assert!(should_finalize(FinalizeReason::DurationCap, 30_000, 0, true, 1200, 30_000));
    }

    #[test]
    fn auto_finalize_disabled_by_zero_hangover() {
        assert!(!should_finalize(FinalizeReason::Silence, 5000, 9000, true, 0, 30_000));
    }

    #[test]
    fn language_normalization_table() {
        assert_eq!(normalize_language(""), "auto");
        assert_eq!(normalize_language("   "), "auto");
        assert_eq!(normalize_language("AUTO"), "auto");
        assert_eq!(normalize_language("zh-CN"), "zh");
        assert_eq!(normalize_language("ZH_TW"), "zh");
        assert_eq!(normalize_language("EN"), "en");
        assert_eq!(normalize_language("pt-BR"), "pt");
        assert_eq!(normalize_language("fr"), "fr");
        // Unknown tags fall back rather than reaching the engine and failing opaquely.
        assert_eq!(normalize_language("klingon"), "auto");
    }

    #[test]
    fn settings_clamp_out_of_range_values() {
        let s = VoiceSettings {
            max_utterance_seconds: 0,
            silence_hangover_ms: 99_999,
            model: "not-a-model".to_string(),
            language: "zh-Hans".to_string(),
            ..Default::default()
        }
        .sanitized();
        assert_eq!(s.max_utterance_seconds, MIN_MAX_UTTERANCE_SECS);
        assert_eq!(s.silence_hangover_ms, MAX_SILENCE_HANGOVER_MS);
        assert_eq!(s.model, DEFAULT_MODEL_ID);
        assert_eq!(s.language, "zh");
    }

    #[test]
    fn settings_survive_an_empty_json_block() {
        let s: VoiceSettings = serde_json::from_str("{}").expect("empty block must parse");
        assert_eq!(s, VoiceSettings::default());
    }

    #[test]
    fn settings_survive_a_partial_json_block() {
        let s: VoiceSettings = serde_json::from_str(r#"{"enabled": false, "language": "de"}"#).unwrap();
        assert!(!s.enabled);
        assert_eq!(s.language, "de");
        assert_eq!(s.model, DEFAULT_MODEL_ID);
    }

    #[test]
    fn model_catalog_is_internally_consistent() {
        assert!(!MODEL_CATALOG.is_empty());
        let mut seen = std::collections::HashSet::new();
        for m in MODEL_CATALOG {
            assert!(seen.insert(m.id), "duplicate model id {}", m.id);
            assert!(m.size_bytes > 0, "{} must declare a size", m.id);
            assert!(m.file_name().ends_with(".bin"), "{} must resolve to a .bin", m.id);
            assert!(m.url().starts_with(MODEL_BASE_URL), "{} must use the model host", m.id);
            assert!(!m.size_label().is_empty());
        }
        assert!(is_known_model(DEFAULT_MODEL_ID), "default model must be in the catalog");
    }

    #[test]
    fn model_lookup_falls_back_to_default() {
        assert_eq!(model_by_id("ggml-tiny").id, "ggml-tiny");
        assert_eq!(model_by_id("nope").id, DEFAULT_MODEL_ID);
    }

    #[test]
    fn event_json_matches_the_chat_streaming_shape() {
        let e = VoiceEvent::StateChanged { state: VoiceState::Recording };
        let json = serde_json::to_string(&e).unwrap();
        assert!(json.contains("\"type\":\"StateChanged\""));
        assert!(json.contains("\"payload\""), "adjacent tagging must nest under payload");

        let t = Transcript {
            text: "你好".to_string(),
            language: "zh".to_string(),
            duration_ms: 1200,
            engine: "whisper-cpp".to_string(),
            model: DEFAULT_MODEL_ID.to_string(),
        };
        let f = VoiceEvent::Final(t.clone());
        let back: VoiceEvent = serde_json::from_str(&serde_json::to_string(&f).unwrap()).unwrap();
        assert_eq!(back, f, "events must round-trip");
        assert_eq!(back.kind(), "Final");
    }

    #[test]
    fn recoverable_flag_distinguishes_setup_gaps_from_deaths() {
        let gap = VoiceEvent::setup_error("model missing");
        let dead = VoiceEvent::fatal_error("engine killed");
        match gap {
            VoiceEvent::Error { recoverable, .. } => assert!(recoverable),
            _ => panic!("expected Error"),
        }
        match dead {
            VoiceEvent::Error { recoverable, .. } => assert!(!recoverable),
            _ => panic!("expected Error"),
        }
    }

    #[test]
    fn append_transcript_never_truncates_typed_text() {
        assert_eq!(append_transcript("", "hello"), "hello");
        assert_eq!(append_transcript("typed", "hello"), "typed hello");
        assert_eq!(append_transcript("typed ", "hello"), "typed hello");
        // A deliberate trailing newline is the user's own Enter press, so it is
        // preserved rather than collapsed to a space.
        assert_eq!(append_transcript("typed\n", "hello"), "typed\nhello");
        assert_eq!(append_transcript("multi\nline", "hello"), "multi\nline hello");
        assert_eq!(append_transcript("代码", "测试"), "代码 测试");
        // Blank transcripts are dropped, not appended as whitespace.
        assert_eq!(append_transcript("typed", "   "), "typed");
        assert_eq!(append_transcript("typed", ""), "typed");
    }

    #[test]
    fn staged_download_uses_part_suffix() {
        let dir = Path::new("/tmp/models");
        let (part, finalp) = staged_download_paths(dir, DEFAULT_MODEL_ID);
        assert!(part.to_string_lossy().ends_with(".part"));
        assert!(!finalp.to_string_lossy().ends_with(".part"));
        assert_eq!(finalp.file_name().unwrap().to_string_lossy().to_string(),
            model_by_id(DEFAULT_MODEL_ID).file_name());
    }

    #[test]
    fn session_config_zeroes_hangover_when_auto_finalize_is_off() {
        let mut settings = VoiceSettings::default();
        settings.auto_finalize = false;
        let cfg = VoiceSessionConfig::from_settings(&settings);
        assert_eq!(cfg.silence_hangover_ms, 0);
        assert_eq!(cfg.capture, CaptureTarget::Source);
        assert_eq!(cfg.max_utterance_ms, 30_000);
    }
}
