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

/// How PCM reaches the session.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptureBackend {
    /// `pw-record` subprocess (default): tested, stub-injectable, works
    /// wherever PipeWire's CLI tools exist.
    PwRecord,
    /// In-process capture via the system audio API (`cpal`): zero subprocess
    /// overhead and the prerequisite for true streaming partials. Explicit
    /// opt-in until it matches the subprocess path's field record.
    Native,
}

/// Selects the capture backend from an explicit request string.
///
/// `"native"` opts into in-process capture; anything else (including empty)
/// keeps the `pw-record` subprocess path. Unknown values never enable an
/// experimental path by accident.
pub fn select_capture_backend(requested: &str) -> CaptureBackend {
    if requested.trim().eq_ignore_ascii_case("native") {
        CaptureBackend::Native
    } else {
        CaptureBackend::PwRecord
    }
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
    /// For `CaptureTarget::Sink`, `stream.capture.sink=true` is strictly required
    /// so that PipeWire links to the sink monitor (speakers/headphones output)
    /// instead of falling back to physical microphone capture.
    pub fn stream_properties(self) -> Option<&'static str> {
        match self {
            CaptureTarget::Sink => Some("stream.capture.sink=true"),
            CaptureTarget::Source => None,
        }
    }
}

/// Builds the `pw-record` argument vector for a capture target.
///
/// This is the single builder for **both** the visualizer (sink monitor) and
/// voice input (microphone). The `CaptureTarget::Sink` invocation with
/// `rate = 8000, latency_ms = 32` binds the sink monitor via `stream.capture.sink=true`.
pub fn pw_record_args(
    target: CaptureTarget,
    sample_rate: u32,
    channels: u16,
    latency_ms: u32,
) -> Vec<String> {
    pw_record_args_for_target(
        target.target_token(),
        target.stream_properties(),
        sample_rate,
        channels,
        latency_ms,
    )
}

/// Same contract as [`pw_record_args`], but for an explicit PipeWire node.
///
/// Used for the echo-cancelled source, whose node name is not one of the
/// `@DEFAULT_...@` tokens. The node is captured as-is; no semantics are
/// forced on it.
pub fn pw_record_args_for_node(
    node: &str,
    sample_rate: u32,
    channels: u16,
    latency_ms: u32,
) -> Vec<String> {
    pw_record_args_for_target(node, None, sample_rate, channels, latency_ms)
}

/// The single `pw-record` argument builder both entry points share.
fn pw_record_args_for_target(
    target: &str,
    properties: Option<&str>,
    sample_rate: u32,
    channels: u16,
    latency_ms: u32,
) -> Vec<String> {
    let mut args: Vec<String> = Vec::with_capacity(15);
    // --raw: disables the AU container so stdout carries pure PCM frames.
    args.push("--raw".to_string());

    if let Some(props) = properties {
        args.push("-P".to_string());
        args.push(props.to_string());
    }

    args.push("--target".to_string());
    args.push(target.to_string());

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
// Input health & gain staging (audit §1.1)
// ---------------------------------------------------------------------------

/// Sample magnitude at or above which a sample counts as hard-clipped.
///
/// Normalized `[-1.0, 1.0]` floats: `32767 / 32768 ≈ 0.99997`. Using 0.99 keeps
/// the detector robust to float rounding while still catching ADC saturation.
pub const CLIPPING_THRESHOLD: f32 = 0.99;
/// Clipping ratio above which the session warns the user.
///
/// Per `docs/VOICE-INPUT-AUDIT.md` §4.1: if more than 2% of samples in the
/// opening window sit at the rails, the ALSA analog gain is saturating the ADC
/// (e.g. +60 dB on ALC256) and formants are destroyed before any model runs.
pub const CLIPPING_WARN_RATIO: f32 = 0.02;
/// Opening window inspected for clipping, in milliseconds.
pub const CLIPPING_WINDOW_MS: u64 = 500;

/// Fraction of finite samples at or above [`CLIPPING_THRESHOLD`].
///
/// Pure: operates on normalized floats so both the capture loop (live PCM) and
/// unit tests (synthetic signals) share one definition. Non-finite samples are
/// ignored, never counted as clipped.
pub fn clipping_ratio(samples: &[f32]) -> f32 {
    let mut clipped = 0usize;
    let mut n = 0usize;
    for s in samples {
        if !s.is_finite() {
            continue;
        }
        n += 1;
        if s.abs() >= CLIPPING_THRESHOLD {
            clipped += 1;
        }
    }
    if n == 0 {
        return 0.0;
    }
    clipped as f32 / n as f32
}

/// Human-readable remediation for a saturated input.
///
/// Warn-only by design (D7): the daemon never rewrites ALSA controls silently.
/// The doctor check and the session warning both render this text.
pub fn clipping_advice(ratio: f32) -> String {
    format!(
        "Microphone input is clipping ({:.0}% of samples at the rails). Lower the mic boost in alsamixer / system settings (e.g. `amixer -c 1 sset 'Internal Mic Boost' 1`), then try again.",
        (ratio * 100.0).clamp(0.0, 100.0)
    )
}

/// Outcome of a device-only microphone check (`voice mic-check`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MicVerdict {
    /// Usable signal observed.
    Ok,
    /// Nothing above the room anchor: muted, wrong device, or dead mic.
    Silent,
    /// ADC saturation: gain staging must be fixed before dictation can work.
    Clipping,
}

/// A device-only microphone check report.
///
/// Stays on the device by construction: it carries statistics, never audio.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MicCheck {
    pub backend: String,
    pub device: String,
    pub secs_requested: u64,
    pub secs_captured: f32,
    pub frames: u64,
    pub peak_rms: f32,
    pub clipping_ratio: f32,
    pub verdict: MicVerdict,
    pub advice: String,
}

/// Judges a mic-check recording from its peak level and clipping ratio.
///
/// Pure so the thresholds are unit-tested, not discoverable only through a
/// microphone. Silence is judged against the same anchor the activity gate
/// uses; clipping against the session guardrail.
pub fn mic_verdict(peak_rms: f32, clipping_ratio: f32) -> (MicVerdict, String) {
    if !peak_rms.is_finite() || !clipping_ratio.is_finite() {
        return (
            MicVerdict::Silent,
            "Microphone check produced no measurable signal. Check the input device and permissions.".to_string(),
        );
    }
    if clipping_ratio >= CLIPPING_WARN_RATIO {
        return (MicVerdict::Clipping, clipping_advice(clipping_ratio));
    }
    if peak_rms < SPEECH_ACTIVITY_ANCHOR {
        return (
            MicVerdict::Silent,
            "Microphone heard nothing above the room floor. Unmute it, raise the capture level, or pick another input.".to_string(),
        );
    }
    (
        MicVerdict::Ok,
        format!(
            "Microphone OK: peak {:.0}% of full scale, no clipping.",
            (peak_rms * 100.0).clamp(0.0, 100.0)
        ),
    )
}

// ---------------------------------------------------------------------------
// Neural VAD gate (audit §1.2 / §4.2)
// ---------------------------------------------------------------------------

/// Speech probability above which a frame counts as speech.
///
/// Audit §4.2: energy thresholds cannot separate unvoiced consonants from fan
/// noise (30 dB speech dynamic range). The neural VAD reports a phoneme
/// probability per frame; `p > 0.5` is the speech gate. This is the single
/// decision point both the sidecar VAD and a future in-process VAD share.
pub const VAD_SPEECH_PROB_THRESHOLD: f32 = 0.5;
/// Silero VAD model provisioned alongside the STT weights.
pub const VAD_MODEL_ID: &str = "silero-v5.1.2";
/// Upstream location of the VAD model asset.
pub const VAD_MODEL_URL: &str =
    "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin";
/// Size of the VAD asset on disk, verified 2026-09-29.
pub const VAD_MODEL_SIZE_BYTES: u64 = 885_098;

/// Whether a VAD speech probability counts as speech.
///
/// Non-finite probabilities are never speech: one bad score must not open the
/// gate for a whole utterance.
pub fn vad_is_speech(prob: f32) -> bool {
    prob.is_finite() && prob > VAD_SPEECH_PROB_THRESHOLD
}

/// File name of the VAD model inside the models directory.
pub fn vad_model_file_name() -> String {
    format!("ggml-{}.bin", VAD_MODEL_ID)
}

/// Resolves the VAD model file, treating a zero-length file as absent.
pub fn resolve_vad_model_file() -> Option<PathBuf> {
    let path = models_dir().join(vad_model_file_name());
    match std::fs::metadata(&path) {
        Ok(meta) if meta.len() > 0 => Some(path),
        _ => None,
    }
}

/// One neural speech segment, in seconds.
///
/// `whisper-vad-speech-segments` prints timestamps in centiseconds
/// (`Speech segment 0: start = 7.00, end = 54.00`); this is the parsed,
/// seconds-denominated form the trim logic consumes.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct VadSegment {
    pub start_s: f32,
    pub end_s: f32,
}

/// Parses `whisper-vad-speech-segments` stdout into speech segments.
///
/// Lines that do not match the `Speech segment N: start = X, end = Y` shape
/// (log banners, `Detected N speech segments:` summaries) are skipped, and an
/// end before its start is clamped rather than admitted. Empty output — the
/// honest answer for silence — yields no segments.
pub fn parse_vad_segments(output: &str) -> Vec<VadSegment> {
    let mut segments = Vec::new();
    for line in output.lines() {
        let t = line.trim();
        // Shape: `Speech segment 0: start = 7.00, end = 54.00`. Anything else
        // (log banners, `Detected N speech segments:` summaries) is skipped.
        let Some((_, rest)) = t.split_once("start") else {
            continue;
        };
        let Some((start_raw, end_raw)) = rest.split_once("end") else {
            continue;
        };
        let start_cs: Option<f32> = start_raw
            .split('=')
            .nth(1)
            .and_then(|v| v.trim().trim_end_matches(',').parse::<f32>().ok());
        let end_cs: Option<f32> = end_raw
            .split('=')
            .nth(1)
            .and_then(|v| v.trim().parse::<f32>().ok());
        match (start_cs, end_cs) {
            (Some(s), Some(e)) if s.is_finite() && e.is_finite() && e >= 0.0 && s >= 0.0 => {
                let (start_s, end_s) = (s / 100.0, e.max(s) / 100.0);
                if end_s > start_s {
                    segments.push(VadSegment { start_s, end_s });
                }
            }
            _ => continue,
        }
    }
    segments
}

/// Converts neural segments to frame bounds over a capture of `total_frames`.
///
/// Returns the unpadded union span as `(first_frame, last_frame_inclusive)`,
/// ready to hand to `trim_to_speech`, which applies the single standard
/// padding margin. `None` means no usable segment — the caller reports
/// no-speech rather than transcribing.
pub fn vad_segments_to_frames(
    segments: &[VadSegment],
    sample_rate: u32,
    frame_len: usize,
    total_frames: usize,
) -> Option<(usize, usize)> {
    if segments.is_empty() || frame_len == 0 || sample_rate == 0 || total_frames == 0 {
        return None;
    }
    let frame_ms = (frame_len as u64 * 1000) / sample_rate as u64;
    if frame_ms == 0 {
        return None;
    }
    let mut first = usize::MAX;
    let mut last = 0usize;
    let mut any = false;
    for seg in segments {
        if !seg.start_s.is_finite() || !seg.end_s.is_finite() || seg.end_s <= seg.start_s {
            continue;
        }
        let s = ((seg.start_s * 1000.0) as u64 / frame_ms) as usize;
        let e = (((seg.end_s * 1000.0) as u64) / frame_ms) as usize;
        first = first.min(s);
        last = last.max(e);
        any = true;
    }
    if !any || last < first {
        return None;
    }
    Some((first.min(total_frames.saturating_sub(1)), last.min(total_frames.saturating_sub(1))))
}

// ---------------------------------------------------------------------------
// Adaptive silence detection (endpointing)
// ---------------------------------------------------------------------------

/// Highest level a *constant* signal may have and still be read as the room.
///
/// This is not a speech threshold. It is the dividing line the previous
/// implementation already drew at 0.05 and drew correctly: a steady signal at
/// or below it is a room, a steady signal above it is speech or an event. What
/// was wrong was not this constant but that admitted frames were *averaged*,
/// which let ordinary dictation drag the estimate up with them.
const FLOOR_ADMIT_CEILING: f32 = 0.05;
/// Samples needed before the room estimate stops being bootstrapped.
///
/// While starved, a frame at or below [`FLOOR_ADMIT_CEILING`] is admitted even
/// if it looks like speech, because there is no measurement yet and refusing to
/// take one leaves the detector with nothing to judge against.
const MIN_FLOOR_SAMPLES: usize = 5;
/// Frames retained for the room estimate (2 s at 20 ms frames).
const FLOOR_WINDOW: usize = 100;
/// Quantile of those frames used as the floor.
///
/// A *low quantile*, not a mean. That single change is the fix for the
/// truncation users were seeing: the old estimator averaged every frame below
/// the admission ceiling, and normal dictation sits just under it, so the floor
/// climbed to the speech level and `level > floor * 3` could never be satisfied
/// again. A low quantile is robust to that, because speech is a minority of any
/// window shorter than a continuous utterance, and it still rises in a quiet
/// room, because there every frame *is* background.
const FLOOR_QUANTILE: f32 = 0.20;
/// A frame counts as speech when its level rises this far above the room.
/// Expressed as a ratio rather than an absolute threshold so the detector
/// tracks the room instead of assuming a fixed noise level.
pub const SILENCE_HEADROOM: f32 = 3.0;
/// The looser ratio used to decide whether a session contained speech at all.
///
/// This is a recall test, not a precision one. `has_speech` gates whether the
/// engine runs; a false negative costs the user their whole utterance, while a
/// false positive costs one inference that returns nothing. The bar is
/// therefore deliberately low: whisper transcribes speech sitting at 1.5x the
/// noise floor perfectly well, so refusing to even try it is the wrong call.
pub const SPEECH_ACTIVITY_HEADROOM: f32 = 1.5;
/// Absolute floor for the activity test, in RMS.
///
/// The room ratio alone is not enough there: before anything is measured the
/// floor is zero, which would make any signal at all count as speech. A truly
/// quiet room sits far below this, so it never does.
const SPEECH_ACTIVITY_ANCHOR: f32 = 0.005;
/// Speech activity, at the loose ratio above, required before a session counts
/// as having contained speech. 120 ms is long enough to exclude a click and
/// short enough that a single word still registers.
pub const MIN_SPEECH_MS: u64 = 120;
/// How long the loudest recent level takes to fall by ~63%, in milliseconds.
///
/// A decaying peak, not an all-time maximum. It is the half of the threshold
/// that follows the *utterance*, which is what keeps a long stretch of speech
/// tracked and a single transient from dominating for the rest of the session.
const PEAK_DECAY_MS: u64 = 1500;
/// Frames required before *trailing silence* is judged at all.
///
/// This gates only the silence accumulator, never speech classification.
/// Gating classification here is what previously discarded the first 500 ms of
/// any utterance that began the moment the microphone opened.
pub const SILENCE_WARMUP_FRAMES: u32 = 25;

/// Outcome of feeding one frame to the detector.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SilenceDecision {
    /// RMS of the frame just pushed.
    pub level: f32,
    /// Current estimate of the room's quiet floor.
    pub floor: f32,
    /// Whether the frame was classified as speech. Drives endpointing.
    pub speaking: bool,
    /// Whether the frame carried speech energy worth transcribing, judged at
    /// the looser [`SPEECH_ACTIVITY_HEADROOM`]. Drives the has-speech verdict
    /// and the trim bounds, so a frame that is real speech but fell short of
    /// the endpointing bar is still handed to the engine.
    pub active: bool,
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
/// This detector estimates the room as a low quantile of the frames that were
/// not themselves speech, and keeps a decaying peak for the current utterance.
/// A frame is speech when it clears either estimate, so both a quiet room with
/// a loud speaker and a loud room with a loud speaker are handled by the same
/// two numbers rather than by a single adaptive average that either tracks the
/// room too slowly or absorbs the speech.
///
/// It is a pure function of its input, so it is unit-tested against synthetic
/// speech, noise and DC-latch signals at the levels real microphones produce.
#[derive(Debug, Clone)]
pub struct SilenceDetector {
    /// Recent frames admitted as room measurements.
    floor_samples: Vec<f32>,
    frames_seen: u32,
    /// Loudest level seen recently, decaying. Seeded from the level in hand
    /// when no room has been measured yet, so an utterance that begins before
    /// the lead-in ends is still tracked.
    peak: f32,
    /// Milliseconds of trailing silence.
    silent_for_ms: u64,
    /// Milliseconds of [`SPEECH_ACTIVITY_HEADROOM`] activity so far.
    active_ms: u64,
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
            frames_seen: 0,
            peak: 0.0,
            silent_for_ms: 0,
            active_ms: 0,
            frame_ms,
        }
    }

    /// Duration of one frame in milliseconds.
    pub fn frame_ms(&self) -> u64 {
        self.frame_ms
    }

    /// Current estimate of the room's quiet floor.
    ///
    /// A low quantile of the frames that were admitted as room measurements.
    /// Before anything is admitted this is `0.0`, meaning "unmeasured" rather
    /// than "silent"; the thresholds do not rely on it alone for that reason.
    pub fn floor(&self) -> f32 {
        if self.floor_samples.is_empty() {
            return 0.0;
        }
        let mut sorted = self.floor_samples.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let idx = (((sorted.len() - 1) as f32) * FLOOR_QUANTILE).round() as usize;
        sorted[idx.min(sorted.len() - 1)]
    }

    /// Loudest recent level, decayed. Drives the peak-relative half of the
    /// threshold, so a single transient cannot pin the detector.
    pub fn peak(&self) -> f32 {
        self.peak
    }

    /// Trailing silence accumulated so far.
    pub fn silent_for_ms(&self) -> u64 {
        self.silent_for_ms
    }

    /// Whether this session has contained enough speech to be worth sending to
    /// the engine.
    ///
    /// Deliberately a *cumulative* verdict rather than "some frame was loud":
    /// a single-frame test made a whole utterance depend on one 20 ms window,
    /// and a fragment of speech at a modest level is still worth transcribing.
    pub fn has_speech(&self) -> bool {
        self.active_ms >= MIN_SPEECH_MS
    }

    /// Feeds one frame and reports what the detector concluded.
    pub fn push(&mut self, level: f32) -> SilenceDecision {
        let level = if level.is_finite() && level > 0.0 { level } else { 0.0 };
        self.frames_seen += 1;

        // Follow the utterance with a decaying peak and the room with a low
        // quantile; a frame is speech if it clears either. Requiring both would
        // mean an unmeasured room could veto real speech, and a measured one
        // could veto a quiet word.
        if level > self.peak {
            self.peak = level;
        } else {
            self.peak -= self.peak * (self.frame_ms as f32) / (PEAK_DECAY_MS as f32);
        }

        let floor = self.floor();
        let speaking_threshold = (self.peak / SILENCE_HEADROOM).max(floor * SILENCE_HEADROOM);
        let activity_threshold = (self.peak / SPEECH_ACTIVITY_HEADROOM)
            .max(floor * SPEECH_ACTIVITY_HEADROOM)
            .max(SPEECH_ACTIVITY_ANCHOR);

        let speaking = level > speaking_threshold;
        let active = level > activity_threshold;

        // Only non-speech frames may inform the room estimate. This is the
        // property that keeps a long utterance from dragging the floor up until
        // the detector latches off mid-sentence. While the estimate is still
        // starved there is nothing to protect it with, so a frame low enough to
        // plausibly be the room is admitted anyway.
        let starved = self.floor_samples.len() < MIN_FLOOR_SAMPLES;
        if !speaking || (starved && level <= FLOOR_ADMIT_CEILING) {
            self.floor_samples.push(level);
            if self.floor_samples.len() > FLOOR_WINDOW {
                self.floor_samples.remove(0);
            }
        }

        if active {
            self.active_ms = self.active_ms.saturating_add(self.frame_ms);
        }

        // Warm-up gates only the silence accumulator, so the leading quiet
        // frames of a session cannot be mistaken for its end. It deliberately
        // does not gate `speaking`: doing so discarded the first 500 ms of any
        // utterance that began the moment the microphone opened.
        if speaking {
            self.silent_for_ms = 0;
        } else if self.frames_seen > SILENCE_WARMUP_FRAMES {
            self.silent_for_ms = self.silent_for_ms.saturating_add(self.frame_ms);
        } else {
            self.silent_for_ms = 0;
        }

        SilenceDecision {
            level,
            floor,
            speaking,
            active,
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

/// Resolves a locale string such as `de_DE.UTF-8@euro` to `de`.
///
/// Unknown or unsupported tags yield `None` rather than a guess, so the caller
/// can decide what an unresolvable locale means instead of inheriting one.
pub fn locale_language_from(primary: Option<&str>, secondary: Option<&str>) -> Option<String> {
    for raw in [primary, secondary].into_iter().flatten() {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        // `de_DE.UTF-8@euro` -> `de`
        let locale = trimmed.split(['.', '@']).next().unwrap_or(trimmed);
        let base = locale
            .split(['-', '_'])
            .next()
            .unwrap_or(locale)
            .trim()
            .to_ascii_lowercase();
        if base.is_empty() {
            continue;
        }
        if is_supported_language(&base) {
            return Some(base);
        }
    }
    None
}

/// The language the running system is configured for.
///
/// Read from the environment rather than from a shipped constant, because the
/// right default is a fact about the machine, and hardcoding one would be
/// wrong for everyone who does not speak it. `LC_ALL` wins, then
/// `LC_MESSAGES`, then `LANG`, which is the POSIX precedence order.
///
/// Returns [`LANGUAGE_AUTO`] when nothing resolves. That is a last resort, not
/// a preference: with no locale to go on there is genuinely nothing better than
/// asking the engine, and the confidence gate in the adapter is what keeps that
/// honest.
pub fn system_language() -> String {
    for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
        if let Ok(value) = std::env::var(key) {
            if let Some(lang) = locale_language_from(Some(&value), None) {
                return lang;
            }
        }
    }
    LANGUAGE_AUTO.to_string()
}

/// The language a fresh install transcribes in.
///
/// The user's locale, falling back to a known supported language ("en") only
/// when the environment says nothing usable or resolves to auto-detect. See
/// [`VoiceSettings::effective_language`] for why this is not `auto`.
pub fn default_voice_language() -> String {
    let lang = system_language();
    if lang == LANGUAGE_AUTO {
        "en".to_string()
    } else {
        lang
    }
}

// ---------------------------------------------------------------------------
// Model catalog
// ---------------------------------------------------------------------------

/// Base URL the models are served from.
pub const MODEL_BASE_URL: &str = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main";

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

/// SenseVoice-Small model identifier for sherpa-onnx.
pub const SHERPA_ENGINE_ID: &str = "sherpa-onnx";
pub const SENSEVOICE_SMALL_ID: &str = "sherpa-sensevoice-small";
pub const SENSEVOICE_MODEL_URL: &str = "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx";
pub const SENSEVOICE_TOKENS_URL: &str = "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt";
pub const SENSEVOICE_MODEL_SIZE_BYTES: u64 = 239_233_841;
pub const SENSEVOICE_TOKENS_SIZE_BYTES: u64 = 315_894;
pub const SENSEVOICE_TOTAL_SIZE_BYTES: u64 = SENSEVOICE_MODEL_SIZE_BYTES + SENSEVOICE_TOKENS_SIZE_BYTES;

static SENSEVOICE_ENTRY: ModelEntry = ModelEntry {
    id: SENSEVOICE_SMALL_ID,
    display_name: "SenseVoice Small (Sherpa-ONNX, fast ZH/EN)",
    size_bytes: SENSEVOICE_TOTAL_SIZE_BYTES,
};

/// Models catalog specifically for sherpa-onnx engine.
pub fn sherpa_model_descriptors() -> Vec<ModelDescriptor> {
    vec![ModelDescriptor {
        id: SENSEVOICE_SMALL_ID.to_string(),
        display_name: "SenseVoice Small (Sherpa-ONNX, fast ZH/EN)".to_string(),
        size_bytes: SENSEVOICE_TOTAL_SIZE_BYTES,
        size_label: format_size(SENSEVOICE_TOTAL_SIZE_BYTES),
    }]
}

/// Languages supported by SenseVoice-Small.
pub fn sherpa_language_options() -> Vec<LanguageOption> {
    vec![
        LanguageOption { code: "auto".to_string(), label: "Auto-detect".to_string() },
        LanguageOption { code: "zh".to_string(), label: "中文 (Chinese)".to_string() },
        LanguageOption { code: "en".to_string(), label: "English".to_string() },
        LanguageOption { code: "ja".to_string(), label: "日本語 (Japanese)".to_string() },
        LanguageOption { code: "ko".to_string(), label: "한국어 (Korean)".to_string() },
        LanguageOption { code: "yue".to_string(), label: "粤语 (Cantonese)".to_string() },
    ]
}

/// Looks a model up by id, falling back to [`DEFAULT_MODEL_ID`].
pub fn model_by_id(id: &str) -> &'static ModelEntry {
    if id == SENSEVOICE_SMALL_ID {
        return &SENSEVOICE_ENTRY;
    }
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
    if model_id == SENSEVOICE_SMALL_ID {
        let dir = models_dir().join(SENSEVOICE_SMALL_ID);
        let model = dir.join("model.int8.onnx");
        let tokens = dir.join("tokens.txt");
        if model.is_file() && tokens.is_file() {
            return Some(dir);
        }
        return None;
    }
    let path = models_dir().join(model_by_id(model_id).file_name());
    match std::fs::metadata(&path) {
        Ok(meta) if meta.len() > 0 => Some(path),
        _ => None,
    }
}

/// Whether a model id names something in the catalog.
pub fn is_known_model(id: &str) -> bool {
    id == SENSEVOICE_SMALL_ID || MODEL_CATALOG.iter().any(|m| m.id == id)
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
    /// The transcription language. Empty means "the user never chose", which
    /// resolves to the system locale; `"auto"` is a deliberate choice to detect
    /// it per utterance, and is a different thing.
    pub language: String,
    pub max_utterance_seconds: u32,
    pub silence_hangover_ms: u64,
    pub auto_finalize: bool,
    pub install_model_on_demand: bool,
    /// Capture through a PipeWire echo-cancelled source.
    ///
    /// Audit §3.3: loading `module-echo-cancel` without routing desktop playback
    /// through its sink gives the canceller zero reference samples, so it cannot
    /// cancel echo and instead distorts the mic with blind AGC. Defaults to off
    /// until sink routing (or an `rnnoise` capture-only filter) is implemented.
    /// Opt-in per session via `ASTRAL_VOICE_AEC_SOURCE`; never breaks dictation
    /// when the filter is unavailable.
    pub echo_cancel: bool,
    /// Capture through an operator-provisioned noise-suppression source.
    ///
    /// The evaluated `module-echo-cancel` replacement (audit §3.3): a
    /// capture-only `rnnoise` filter needs no playback reference, so it cannot
    /// fail the way blind AEC did. The node itself is operator-provisioned —
    /// the daemon never writes audio-graph config — and absence falls back to
    /// the default source. Opt-in per session via
    /// `ASTRAL_VOICE_NOISE_SUPPRESS_SOURCE`.
    pub noise_suppress: bool,
}

impl Default for VoiceSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            engine: DEFAULT_ENGINE.to_string(),
            model: DEFAULT_MODEL_ID.to_string(),
            language: default_voice_language(),
            max_utterance_seconds: DEFAULT_MAX_UTTERANCE_SECS,
            silence_hangover_ms: DEFAULT_SILENCE_HANGOVER_MS,
            auto_finalize: true,
            install_model_on_demand: true,
            echo_cancel: false,
            noise_suppress: false,
        }
    }
}

impl VoiceSettings {
    /// Applies every documented clamp and fallback.
    pub fn sanitized(mut self) -> Self {
        if let Ok(env_engine) = std::env::var("ASTRAL_VOICE_ENGINE") {
            let trimmed = env_engine.trim();
            if !trimmed.is_empty() {
                self.engine = trimmed.to_string();
            }
        }
        if let Ok(env_model) = std::env::var("ASTRAL_VOICE_MODEL") {
            let trimmed = env_model.trim();
            if !trimmed.is_empty() && is_known_model(trimmed) {
                self.model = trimmed.to_string();
            }
        }
        if self.engine == SHERPA_ENGINE_ID && (self.model == DEFAULT_MODEL_ID || !is_known_model(&self.model)) {
            self.model = SENSEVOICE_SMALL_ID.to_string();
        } else if !is_known_model(&self.model) {
            self.model = DEFAULT_MODEL_ID.to_string();
        }
        if self.engine.trim().is_empty() {
            self.engine = DEFAULT_ENGINE.to_string();
        }
        // An absent key is "the user never chose", not "choose auto". Collapsing
        // the two is what shipped the ungated argmax as the default, so they
        // are kept apart: only a value the user actually typed may become
        // `auto`.
        self.language = if self.language.trim().is_empty() {
            default_voice_language()
        } else {
            normalize_language(&self.language)
        };
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
    /// Whether the capture contained speech the detector recognised.
    ///
    /// This is the difference between "the microphone heard nothing" and "the
    /// engine heard something and had no words for it", which send the user to
    /// completely different places. It is reported so the UI can say which one
    /// happened instead of leaving an empty result unexplained: an empty
    /// transcript that arrives with no explanation is indistinguishable from a
    /// broken feature, and the user is left with a composer that silently
    /// refused to change.
    #[serde(default = "default_true")]
    pub speech_detected: bool,
    /// The engine's own probability for the reported language, when it gave one.
    #[serde(default)]
    pub language_confidence: Option<f32>,
    /// Why this language was used, so a wrong reading is explicable rather than
    /// merely wrong. See the adapter's `LanguageSource`.
    #[serde(default = "default_language_source")]
    pub language_source: LanguageSource,
}

fn default_true() -> bool {
    true
}

fn default_language_source() -> LanguageSource {
    LanguageSource::Configured
}

/// Why a transcription used the language it did.
///
/// Serialized so the UI can tell "you set this" from "the engine guessed and we
/// did not believe it", which are different problems with different fixes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LanguageSource {
    /// The user's setting, used verbatim.
    Configured,
    /// The engine detected it and was confident enough to be believed.
    Detected,
    /// The engine detected something, but not confidently enough, so the
    /// configured language was used instead. The detection is still reported.
    DetectedOverridden,
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
    /// Capture through the echo-cancelled source when one can be provided.
    pub echo_cancel: bool,
    /// Capture through an operator-provisioned noise-suppression source.
    pub noise_suppress: bool,
    pub model: String,
    pub language: String,
    /// A session-scoped language override, or "" for none.
    ///
    /// Never persisted (D9). `voice.language` in `settings.json` is the
    /// *default*; a user dictating in a second language for one prompt must not
    /// silently reconfigure their shell.
    pub language_override: String,
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
            echo_cancel: settings.echo_cancel,
            noise_suppress: settings.noise_suppress,
            model: settings.model.clone(),
            language: normalize_language(&settings.language),
            language_override: String::new(),
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

    /// Applies a session-scoped language override (D9).
    ///
    /// Normalized like any other tag, so a bad value from a shortcut or an IPC
    /// caller degrades to auto-detect rather than reaching the engine and failing
    /// opaquely. Never touches `VoiceSettings`: the override lives for this
    /// session and is gone with it.
    pub fn with_language_override(mut self, override_tag: &str) -> Self {
        let tag = override_tag.trim();
        if !tag.is_empty() {
            self.language = normalize_language(tag);
            self.language_override = self.language.clone();
        }
        self
    }

    /// The language a session should *fall back on*: the system locale.
    ///
    /// Kept separate from `language` so that "the user asked for auto-detect"
    /// and "we have nothing better than the locale" are two facts, not one.
    pub fn fallback_language(&self) -> String {
        default_voice_language()
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
    /// The language the session settled on, with the engine's own confidence.
    ///
    /// Emitted *before* the transcription pass, and only when the user asked for
    /// automatic detection. This is what makes D8 true: the reading is on screen
    /// while the decode is still running, so a wrong one is visible and
    /// correctable instead of arriving already baked into the text.
    ///
    /// With a fused `-l auto` pass there was nothing to show here -- the language
    /// only existed inside the decode, and by the time it could be read the
    /// transcript was already written and the strip had closed.
    Detected {
        language: String,
        confidence: Option<f32>,
    },
    /// Newtype rather than a struct variant so `payload` *is* the transcript
    /// object, letting the QML side read `payload.text` directly.
    Final(Transcript),
    /// Non-fatal session warning (audit §4.1 gain guard).
    ///
    /// Unlike `Error`, a warning never ends the session or changes
    /// `VoiceState`: the utterance continues and still produces a `Final`.
    /// Unknown variants are ignored by older QML event switches, so this is
    /// forward-compatible. Carries a human-readable remediation.
    Warning { message: String },
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
            VoiceEvent::Detected { .. } => "Detected",
            VoiceEvent::Final(_) => "Final",
            VoiceEvent::Warning { .. } => "Warning",
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
    /// `-dl` / `--detect-language`: identify the language and exit without
    /// transcribing.
    ///
    /// This is what makes a trustworthy `auto` possible. Detection and
    /// transcription are otherwise fused into one pass whose language decision
    /// cannot be inspected, shown or overridden before the decoder commits to
    /// it. `whisper-cli` has advertised this since 1.5, so a build without it
    /// is very old; the adapter still copes, falling back to a single pass.
    pub detect_language: bool,
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
    /// Configured: capture through a PipeWire echo-cancelled source.
    #[serde(default)]
    pub echo_cancel: bool,
    /// Whether the echo-cancelled source is present right now.
    #[serde(default)]
    pub echo_cancel_active: bool,
    /// Capture through an operator-provisioned noise-suppression source.
    #[serde(default)]
    pub noise_suppress: bool,
    /// Whether a suppression source is present right now.
    #[serde(default)]
    pub noise_suppress_active: bool,
    /// Whether the rnnoise LADSPA plugin is installed (suppression hostable).
    #[serde(default)]
    pub rnnoise_available: bool,
    /// Whether the Silero VAD asset is downloaded (neural endpointing active).
    /// Accuracy upgrade only: absence falls back to energy detection, never a gap.
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
        assert_eq!(
            pw_record_args(CaptureTarget::Sink, 8000, 1, 32),
            vec![
                "--raw",
                "-P",
                "stream.capture.sink=true",
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
        // Constant moderate noise must not be absorbed into the room estimate.
        // Above the admission ceiling it is not admitted at all, which is what
        // keeps a loud event from redefining the room it was measured in.
        let mut d = SilenceDetector::new(320, 16_000);
        for _ in 0..400 {
            d.push(0.08);
        }
        assert!(
            d.floor() <= FLOOR_ADMIT_CEILING,
            "floor absorbed loud-room noise to {}",
            d.floor()
        );
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
    fn locale_resolution_reads_the_posix_precedence_order() {
        // `LC_ALL` wins over `LC_MESSAGES`; an unresolvable value falls through
        // rather than poisoning the lookup; each is lowercased and stripped of
        // its region, codeset and modifier.
        for (primary, secondary, expected) in [
            (Some("de_DE.UTF-8"), Some("fr_FR"), Some("de")),
            (Some("fr_FR.UTF-8"), Some("de_DE"), Some("fr")),
            (Some(""), Some("de_DE"), Some("de")),
            // An unsupported primary must not stop the secondary being read.
            (Some("klingon"), Some("fr_FR.UTF-8"), Some("fr")),
            (None, Some("de_AT.UTF-8@euro"), Some("de")),
            (None, Some("ZH_Hant_TW"), Some("zh")),
            (Some("pt-BR"), None, Some("pt")),
            (Some("   "), None, None),
            (None, None, None),
        ] {
            assert_eq!(
                locale_language_from(primary, secondary),
                expected.map(str::to_string),
                "locale {primary:?} / {secondary:?}"
            );
        }
    }

    #[test]
    fn the_default_language_is_the_user_s_locale_not_a_guess() {
        // The reported failure: "can you help me" came back as Japanese, because
        // the default was `auto` and whisper's auto-detect is a bare argmax
        // over 100 language logits with no confidence gate. A dictation UI is a
        // committed-language interaction -- the user knows what they are
        // speaking -- so the default must be a real locale, and `auto` has to be
        // something the user chooses.
        let s = VoiceSettings::default();
        assert_ne!(
            s.language,
            LANGUAGE_AUTO,
            "shipping `auto` as the default hands the output alphabet to an ungated argmax"
        );
        assert!(
            is_supported_language(&s.language),
            "the default language {} is not one the engine can be asked for",
            s.language
        );
    }

    #[test]
    fn an_absent_language_resolves_to_the_locale_while_auto_stays_auto() {
        // The distinction has to survive deserialization: an absent key means
        // "the user never chose", which is not the same as a deliberate `auto`.
        let absent: VoiceSettings =
            serde_json::from_str(r#"{"enabled": true, "model": "ggml-small"}"#).unwrap();
        assert_ne!(
            absent.clone().sanitized().language,
            LANGUAGE_AUTO,
            "an absent language must not silently become auto-detect"
        );

        let chosen: VoiceSettings =
            serde_json::from_str(r#"{"enabled": true, "model": "ggml-small", "language": "auto"}"#)
                .unwrap();
        assert_eq!(
            chosen.sanitized().language,
            LANGUAGE_AUTO,
            "an explicit `auto` is a real choice and must be honoured"
        );
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
            speech_detected: true,
            language_confidence: None,
            language_source: LanguageSource::Configured,
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
