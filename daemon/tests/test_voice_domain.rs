//! Domain-level tests for voice input.
//!
//! These require no speech engine, no model and no microphone, which is the point:
//! see `docs/VOICE-INPUT-SPEC.md` §8.1.

use astral_plasma::domain::voice::{
    LanguageSource,
    append_transcript, clipping_advice, clipping_ratio, format_size, frame_rms, is_known_model, model_by_id, normalize_language,
    package_manager_for_os_release, pw_record_args_for_node, vad_is_speech, vad_model_file_name, PackageManager,
    pcm_bytes_to_f32, pw_record_args, should_finalize, staged_download_paths, wav_container,
    wav_header, CaptureTarget, EngineCapabilities, FinalizeReason, LanguageOption,
    PcmSpec, SetupGap, SilenceDetector, Transcript, VoiceEvent, VoiceSessionConfig, VoiceSettings,
    VoiceState, CLIPPING_WARN_RATIO, DEFAULT_MAX_UTTERANCE_SECS, DEFAULT_MODEL_ID, MAX_MAX_UTTERANCE_SECS,
    MIN_MAX_UTTERANCE_SECS, MODEL_CATALOG, PcmSpec as Spec, SILENCE_HEADROOM,
    SILENCE_WARMUP_FRAMES, SPEECH_SAMPLE_RATE, VAD_SPEECH_PROB_THRESHOLD, WAV_HEADER_LEN, LANGUAGE_AUTO,
    is_supported_language,
};
use std::path::Path;

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

#[test]
fn capture_target_sink_preserves_the_visualizer_contract() {
    let args = pw_record_args(CaptureTarget::Sink, 8000, 1, 32);
    let p = args.iter().position(|a| a == "-P").expect("sink must request stream properties");
    assert!(args[p + 1].contains("\"stream.capture.sink\": true"));
    let t = args.iter().position(|a| a == "--target").unwrap();
    assert_eq!(args[t + 1], "@DEFAULT_AUDIO_SINK@");
}

#[test]
fn capture_target_source_never_records_the_speakers() {
    // Regression guard for the whole point of CaptureTarget: a microphone
    // session that accidentally captured the output monitor would transcribe
    // whatever the user happens to be playing.
    let args = pw_record_args(CaptureTarget::Source, SPEECH_SAMPLE_RATE, 1, 32);
    assert!(
        !args.iter().any(|a| a.contains("stream.capture.sink")),
        "microphone capture must not request the sink monitor"
    );
    assert!(!args.iter().any(|a| a == "@DEFAULT_AUDIO_SINK@"));
    let t = args.iter().position(|a| a == "--target").unwrap();
    assert_eq!(args[t + 1], "@DEFAULT_AUDIO_SOURCE@");
}

#[test]
fn capture_args_always_request_whisper_native_pcm() {
    for target in [CaptureTarget::Sink, CaptureTarget::Source] {
        let args = pw_record_args(target, SPEECH_SAMPLE_RATE, 1, 32);
        let r = args.iter().position(|a| a == "--rate").unwrap();
        assert_eq!(args[r + 1], "16000");
        let c = args.iter().position(|a| a == "--channels").unwrap();
        assert_eq!(args[c + 1], "1", "whisper expects mono");
        let f = args.iter().position(|a| a == "--format").unwrap();
        assert_eq!(args[f + 1], "s16");
        assert_eq!(args.last().unwrap(), "-");
    }
}

#[test]
fn capture_args_reject_nothing_and_never_emit_empty_tokens() {
    for target in [CaptureTarget::Sink, CaptureTarget::Source] {
        for a in pw_record_args(target, SPEECH_SAMPLE_RATE, 1, 32) {
            assert!(!a.is_empty(), "empty argv token would be passed literally to pw-record");
        }
    }
}

// ---------------------------------------------------------------------------
// PCM / WAV
// ---------------------------------------------------------------------------

#[test]
fn wav_header_declares_a_well_formed_pcm_stream() {
    let h = wav_header(Spec::speech(), 64_000);
    assert_eq!(h.len(), WAV_HEADER_LEN);
    assert_eq!(&h[0..4], b"RIFF");
    assert_eq!(u32::from_le_bytes([h[4], h[5], h[6], h[7]]), 36 + 64_000);
    assert_eq!(&h[8..12], b"WAVE");
    assert_eq!(&h[12..16], b"fmt ");
    assert_eq!(&h[36..40], b"data");
    assert_eq!(u32::from_le_bytes([h[40], h[41], h[42], h[43]]), 64_000);
}

#[test]
fn wav_container_embeds_the_payload_verbatim() {
    let pcm: Vec<u8> = (0..1000u32).map(|i| (i % 251) as u8).collect();
    let wav = wav_container(Spec::speech(), &pcm);
    assert_eq!(&wav[WAV_HEADER_LEN..], &pcm[..], "PCM payload must not be altered");
}

#[test]
fn wav_container_handles_empty_audio_without_panicking() {
    let wav = wav_container(Spec::speech(), &[]);
    assert_eq!(wav.len(), WAV_HEADER_LEN);
    assert_eq!(u32::from_le_bytes([wav[40], wav[41], wav[42], wav[43]]), 0);
}

#[test]
fn pcm_spec_geometry_is_consistent() {
    let s = PcmSpec::speech();
    assert_eq!(s.block_align(), 2);
    assert_eq!(s.byte_rate(), 32_000);
    assert_eq!(s.duration_ns(32_000), 1_000_000_000);
    assert_eq!(s.duration_ns(0), 0);
}

#[test]
fn pcm_conversion_normalizes_signed_16_bit() {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&0i16.to_le_bytes());
    bytes.extend_from_slice(&32767i16.to_le_bytes());
    bytes.extend_from_slice(&(-32768i16).to_le_bytes());
    let s = pcm_bytes_to_f32(&bytes);
    assert_eq!(s.len(), 3);
    assert_eq!(s[0], 0.0);
    assert!((s[1] - 32767.0 / 32768.0).abs() < 1e-4);
    assert_eq!(s[2], -1.0);
}

#[test]
fn pcm_conversion_ignores_a_trailing_odd_byte() {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&100i16.to_le_bytes());
    bytes.push(0xAB); // incomplete frame
    assert_eq!(pcm_bytes_to_f32(&bytes).len(), 1);
}

#[test]
fn frame_rms_rejects_dc_and_non_finite_input() {
    assert_eq!(frame_rms(&[]), 0.0);
    assert_eq!(frame_rms(&vec![0.7f32; 100]), 0.0, "constant DC is not acoustic energy");
    assert!(frame_rms(&[f32::NAN, 1.0, 1.0]).is_finite());
    let loud = frame_rms(&[1.0, -1.0, 1.0, -1.0]);
    assert!((loud - 1.0).abs() < 1e-4);
}

// ---------------------------------------------------------------------------
// Silence detection
// ---------------------------------------------------------------------------

#[test]
fn silence_warmup_prevents_premature_finalize() {
    let mut d = SilenceDetector::new(320, 16_000);
    // Opening the mic in a quiet room yields silence first. If that counted as
    // "the user finished", every session would finalize before a word was said.
    for _ in 0..SILENCE_WARMUP_FRAMES {
        let dec = d.push(0.0002);
        assert_eq!(dec.silent_for_ms, 0, "warm-up frames must not accumulate silence");
    }
    // Counting may only begin once warm-up completes, so a user who pauses
    // before speaking has not already burned part of the hangover budget.
    assert_eq!(d.silent_for_ms(), 0, "silence timer started during warm-up");

    // Even after many quiet frames, the recorded silence must reflect only the
    // post-warm-up frames -- otherwise the hangover is pre-paid and a user who
    // pauses before speaking gets cut off almost immediately.
    let mut d = SilenceDetector::new(320, 16_000);
    const TOTAL: u32 = 85;
    for _ in 0..TOTAL {
        d.push(0.0002);
    }
    let expected = (TOTAL - SILENCE_WARMUP_FRAMES) as u64 * d.frame_ms();
    assert_eq!(
        d.silent_for_ms(),
        expected,
        "silence timer must account for exactly the post-warm-up frames"
    );

    assert!(!should_finalize(
        FinalizeReason::Silence,
        1200,
        d.silent_for_ms(),
        false,
        1200,
        DEFAULT_MAX_UTTERANCE_SECS as u64 * 1000
    ));
}

#[test]
fn silence_detector_tracks_a_speech_burst_and_its_trailing_gap() {
    let mut d = SilenceDetector::new(320, 16_000);
    assert_eq!(d.frame_ms(), 20);

    for _ in 0..30 {
        d.push(0.0003);
    }
    let mut saw_speech = false;
    for _ in 0..50 {
        if d.push(0.35).speaking {
            saw_speech = true;
        }
    }
    assert!(saw_speech, "loud frames after warm-up must register as speech");

    // Trailing quiet must accumulate past the hangover.
    let mut reached = 0;
    for _ in 0..100 {
        reached = d.push(0.0003).silent_for_ms;
    }
    assert!(reached >= 1200, "expected >=1200ms of trailing silence, got {reached}ms");
    assert!(should_finalize(FinalizeReason::Silence, 5000, reached, true, 1200, 30_000));
}

#[test]
fn silence_detector_floor_stays_bounded_in_a_loud_room() {
    // In a loud room the floor must not creep up until steady background noise
    // starts reading as silence, which would truncate every utterance.
    //
    // The assertion is on the estimate rather than the classification, because
    // "a constant signal is the room" versus "a constant signal is speech" is a
    // level judgement no energy-based detector can make any other way. Where
    // that line sits is pinned by
    // `a_session_with_no_speech_is_reported_as_having_none`.
    let mut d = SilenceDetector::new(320, 16_000);
    for _ in 0..600 {
        d.push(0.09);
    }
    assert!(
        d.floor() < 0.06,
        "noise floor drifted to {} in a loud room; would misread noise as silence",
        d.floor()
    );
}

#[test]
fn silence_detector_is_robust_to_hostile_input() {
    let mut d = SilenceDetector::new(320, 16_000);
    for bad in [f32::NAN, f32::INFINITY, -1.0, 0.0] {
        let dec = d.push(bad);
        assert!(dec.level.is_finite(), "non-finite level must be coerced");
        assert!(dec.level >= 0.0);
    }
    // A zero-length frame must not divide by zero.
    let mut z = SilenceDetector::new(0, 0);
    let dec = z.push(0.5);
    assert_eq!(dec.silent_for_ms, 0);
    assert!(dec.level.is_finite());
}

#[test]
fn silence_headroom_is_a_ratio_not_an_absolute_gate() {
    // The detector is relative: the same absolute level is speech in a quiet
    // room and background in a loud one.
    let mut quiet = SilenceDetector::new(320, 16_000);
    for _ in 0..40 {
        quiet.push(0.0002);
    }
    assert!(quiet.push(0.01).speaking, "0.01 is loud against a 0.0002 floor");

    let mut loud = SilenceDetector::new(320, 16_000);
    for _ in 0..40 {
        loud.push(0.05);
    }
    assert!(!loud.push(0.05).speaking, "0.05 is unremarkable against a 0.05 floor");
    assert!(SILENCE_HEADROOM > 1.0);
}

/// The floor is a low quantile of frames that were not themselves speech.
///
/// The previous estimator averaged every frame below a hard ceiling, so
/// ordinary dictation (0.04-0.05 RMS, comfortably under that ceiling) was
/// averaged into the floor. Once the floor reached the speech level,
/// `level > floor * 3` could never be satisfied again and the detector latched
/// off mid-sentence, handing the engine a fragment. Regression guard, at the
/// levels a desktop microphone actually produces.
#[test]
fn ordinary_dictation_is_tracked_for_its_whole_length() {
    const ROOM: f32 = 0.002;
    const SPEECH: f32 = 0.05;
    const SPEECH_FRAMES: u32 = 65; // 1.3 s: "can you help me"

    let mut d = SilenceDetector::new(320, 16_000);
    for _ in 0..30 {
        d.push(ROOM);
    }
    let mut first: Option<u32> = None;
    let mut last = 0;
    for i in 0..SPEECH_FRAMES {
        if d.push(SPEECH).speaking {
            first.get_or_insert(i);
            last = i;
        }
    }
    let first = first.expect("speech at 0.05 in a 0.002 room must register");
    assert_eq!(
        (first, last),
        (0, SPEECH_FRAMES - 1),
        "speech tracked for only {} of {} frames: the floor absorbed the speech",
        last - first + 1,
        SPEECH_FRAMES
    );
}

/// A continuously speaking user must not be cut off.
///
/// The floor is learned from the room before the user starts, so sustained
/// speech can never drag it up. Without that, a long utterance latched off
/// after about a second and finalized on its own silence.
#[test]
fn continuous_speech_is_never_mistaken_for_its_own_silence() {
    let mut d = SilenceDetector::new(320, 16_000);
    for _ in 0..30 {
        d.push(0.002);
    }
    // 10 s of unbroken speech: well past the hangover, many times over.
    for i in 0..500 {
        assert!(
            d.push(0.05).speaking,
            "frame {i} of continuous speech read as silence; the utterance would be truncated"
        );
        assert_eq!(d.silent_for_ms(), 0, "silence accumulated during continuous speech");
    }
}

/// Whether a session contained speech is an evidence question, not a
/// single-frame one.
///
/// `has_speech` decides whether the engine runs at all, so this is a recall
/// test: a false negative costs the user their entire utterance, because the
/// session then reports an empty transcript and nothing reaches the composer.
#[test]
fn speech_presence_survives_a_noisy_room() {
    // Room at 0.03 is a fan or an open window; speech at 0.06 is ordinary
    // dictation raised a little to compete with it.
    let mut d = SilenceDetector::new(320, 16_000);
    for _ in 0..60 {
        d.push(0.03);
    }
    for _ in 0..20 {
        d.push(0.06);
    }
    assert!(
        d.has_speech(),
        "0.06 of speech over 0.03 of room noise is transcribable and must count as speech"
    );
}

#[test]
fn a_session_with_no_speech_is_reported_as_having_none() {
    // The guard that keeps an accidental mic click from spending an inference
    // on silence. These are levels a quiet room and a fan actually sit at.
    //
    // The boundary is `FLOOR_ADMIT_CEILING`: a *constant* signal at or below it
    // is measurably the room, and one above it is measurably an event. No
    // energy-based detector can place that line anywhere else, so a steady
    // background above it is read as speech. That costs one wasted inference
    // which returns nothing -- and which the UI now reports, rather than the
    // composer silently refusing to change. It is the preferable trade to
    // discarding utterances, which is what a stricter line caused.
    for (name, background) in [
        ("silent room", 0.0002f32),
        ("quiet room", 0.002),
        ("fan", 0.02),
        ("busy room", 0.04),
    ] {
        let mut d = SilenceDetector::new(320, 16_000);
        for _ in 0..300 {
            d.push(background);
        }
        assert!(!d.has_speech(), "{name} at {background} was read as speech");
    }
}

/// Warm-up must not gate speech classification, only the silence accumulator.
///
/// The previous detector wrote `speaking = warmed_up && ...`, so the first
/// 500 ms of every session was classified as "not yet measurable" at any level.
/// A user who starts talking the instant they click the mic therefore had the
/// whole sentence scored as silence.
#[test]
fn speech_is_classified_before_the_lead_in_has_ended() {
    let mut d = SilenceDetector::new(320, 16_000);
    // Still inside SILENCE_WARMUP_FRAMES.
    for _ in 0..5 {
        d.push(0.0002);
    }
    let dec = d.push(0.30);
    assert!(
        dec.speaking,
        "a 0.30 frame inside the lead-in was not classified as speech; \
         the first word of an immediate utterance is discarded"
    );
    assert_eq!(dec.silent_for_ms, 0, "speech must not leave a silence balance");
}

/// A single transient must not pin the threshold.
///
/// The peak is a decaying maximum, not an all-time one: without the decay, one
/// cough or door slam would raise the speech threshold for the rest of the
/// session and every following word would read as silence.
#[test]
fn a_transient_does_not_pin_the_threshold() {
    let mut d = SilenceDetector::new(320, 16_000);
    for _ in 0..40 {
        d.push(0.002);
    }
    d.push(0.9); // a door
    // ~4.5 s later the peak has decayed well past the room.
    for _ in 0..225 {
        d.push(0.002);
    }
    assert!(
        d.push(0.05).speaking,
        "ordinary speech stopped registering after a transient; peak={} floor={}",
        d.peak(),
        d.floor()
    );
}

#[test]
fn finalize_rules_cover_every_documented_path() {
    let cap = 30_000u64;
    // Manual always wins, even with no speech at all.
    assert!(should_finalize(FinalizeReason::Manual, 0, 0, false, 1200, cap));
    // Nothing spoken: only the cap ends the wait.
    assert!(!should_finalize(FinalizeReason::Silence, 2000, 9000, false, 1200, cap));
    assert!(should_finalize(FinalizeReason::Silence, cap, 9000, false, 1200, cap));
    // Speech present: hangover fires.
    assert!(!should_finalize(FinalizeReason::Silence, 2000, 900, true, 1200, cap));
    assert!(should_finalize(FinalizeReason::Silence, 2000, 1300, true, 1200, cap));
    // The hard cap always fires, even mid-word.
    assert!(should_finalize(FinalizeReason::DurationCap, cap, 0, true, 1200, cap));
    // autoFinalize: false zeroes the hangover, leaving manual + cap only.
    assert!(!should_finalize(FinalizeReason::Silence, 5000, 99_000, true, 0, cap));
}

// ---------------------------------------------------------------------------
// Language
// ---------------------------------------------------------------------------

#[test]
fn language_normalization_handles_the_documented_locale_spellings() {
    let cases = [
        ("", "auto"),
        ("   ", "auto"),
        ("auto", "auto"),
        ("AUTO", "auto"),
        ("zh", "zh"),
        ("zh-CN", "zh"),
        ("zh_CN", "zh"),
        ("ZH-Hans", "zh"),
        ("zh-TW", "zh"),
        ("en", "en"),
        ("EN-GB", "en"),
        ("fr-FR", "fr"),
        ("de", "de"),
        ("it", "it"),
        ("es-MX", "es"),
        ("pt-BR", "pt"),
        ("ru", "ru"),
        ("ja", "ja"),
    ];
    for (input, want) in cases {
        assert_eq!(normalize_language(input), want, "normalize({input:?})");
    }
}

#[test]
fn language_normalization_never_forwards_an_unknown_tag() {
    // An unknown tag reaching the engine produces an opaque failure, so it is
    // collapsed to auto-detect here instead.
    for junk in ["klingon", "xx", "123", "!!", "e"] {
        assert_eq!(normalize_language(junk), "auto", "normalize({junk:?})");
    }
}

#[test]
fn supported_languages_cover_the_required_set_and_are_unique() {
    let opts = LanguageOption::all();
    let mut seen = std::collections::HashSet::new();
    for o in &opts {
        assert!(seen.insert(o.code.clone()), "duplicate language code {}", o.code);
        assert!(!o.label.is_empty(), "{} needs a label", o.code);
    }
    for required in ["auto", "zh", "en", "fr", "de", "it", "es"] {
        assert!(seen.contains(required), "language picker must offer {required}");
    }
}

// ---------------------------------------------------------------------------
// Model catalog
// ---------------------------------------------------------------------------

#[test]
fn model_catalog_entries_are_internally_consistent() {
    let mut ids = std::collections::HashSet::new();
    for m in MODEL_CATALOG {
        assert!(ids.insert(&m.id), "duplicate model id {}", m.id);
        assert!(m.size_bytes > 0, "{} must declare a real size", m.id);
        assert!(m.file_name().ends_with(".bin"));
        assert!(m.url().starts_with("https://"), "{} must use https", m.id);
        assert!(!m.size_label().is_empty(), "{} needs a size label", m.id);
    }
    assert!(is_known_model(DEFAULT_MODEL_ID));
    assert!(!is_known_model("ggml-does-not-exist"));
}

#[test]
fn default_model_is_the_documented_tier() {
    // The default must stay interactive on a CPU-only install: whisper-cli
    // 1.9.4's large-v3-turbo measured ~5x slower than realtime on a 12th-gen
    // i9, while small ran at ~0.8x realtime for the same clip. Changing the
    // default silently would change quality for every existing user, so pin it.
    assert_eq!(DEFAULT_MODEL_ID, "ggml-small");
    assert_eq!(model_by_id(DEFAULT_MODEL_ID).size_bytes, 487_601_967);
}

#[test]
fn model_lookup_falls_back_rather_than_panicking() {
    assert_eq!(model_by_id("ggml-tiny").id, "ggml-tiny");
    assert_eq!(model_by_id("nonsense").id, DEFAULT_MODEL_ID);
    assert_eq!(model_by_id("").id, DEFAULT_MODEL_ID);
}

#[test]
fn size_formatting_is_human_readable() {
    assert_eq!(format_size(512), "512 B");
    assert_eq!(format_size(2048), "2 KiB");
    assert_eq!(format_size(147_951_465), "141 MiB");
    assert_eq!(format_size(1_624_555_275), "1.51 GiB");
    assert_eq!(format_size(3_095_033_483), "2.88 GiB");
}

#[test]
fn settings_read_camel_case_keys_like_the_rest_of_settings_json() {
    // settings.json is camelCase throughout. If the voice block used snake_case
    // keys it would silently ignore every value the user actually configured.
    let raw = r#"{
        "enabled": false,
        "engine": "whisper-cpp",
        "model": "ggml-base",
        "language": "fr",
        "maxUtteranceSeconds": 45,
        "silenceHangoverMs": 2000,
        "autoFinalize": false,
        "installModelOnDemand": false
    }"#;
    let s: VoiceSettings = serde_json::from_str(raw).expect("camelCase block must parse");
    assert!(!s.enabled);
    assert_eq!(s.model, "ggml-base");
    assert_eq!(s.language, "fr");
    assert_eq!(s.max_utterance_seconds, 45);
    assert_eq!(s.silence_hangover_ms, 2000);
    assert!(!s.auto_finalize);
    assert!(!s.install_model_on_demand);
}

#[test]
fn downloads_stage_on_a_part_file() {
    let (part, finalp) = staged_download_paths(Path::new("/cache/models"), "ggml-base");
    assert!(part.to_string_lossy().ends_with(".part"), "interrupted downloads must be distinguishable");
    assert!(!finalp.to_string_lossy().ends_with(".part"));
    assert_eq!(finalp.file_name().unwrap(), "ggml-base.bin");
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

#[test]
fn settings_default_to_the_documented_values() {
    let s = VoiceSettings::default();
    assert!(s.enabled);
    assert_eq!(s.model, DEFAULT_MODEL_ID);
    // The default is the user's locale, not auto-detect. The reported failure
    // was English speech coming back as Japanese: whisper auto-detects with a
    // bare argmax over 100 language logits and no confidence gate, so shipping
    // `auto` as the default handed the output alphabet to a coin toss. See
    // `the_default_language_is_the_user_s_locale_not_a_guess`.
    assert_ne!(s.language, LANGUAGE_AUTO,
        "auto-detect must be opt-in; it is the wrong default for a dictation UI");
    assert!(is_supported_language(&s.language),
        "the default language {} must be one the engine can be asked for", s.language);
    assert_eq!(s.max_utterance_seconds, DEFAULT_MAX_UTTERANCE_SECS);
    assert!(s.auto_finalize);
    assert!(s.install_model_on_demand);
    assert!(!s.echo_cancel,
        "echo cancellation defaults off (audit §3.3): the legacy module-echo-cancel path ships zero reference samples without sink routing");
    assert!(!s.noise_suppress,
        "noise suppression defaults off: its source node is operator-provisioned");
    assert_eq!(s.max_utterance_ms(), 30_000);
}

#[test]
fn settings_survive_an_absent_or_partial_block() {
    // A shell must always start, even with an old settings.json.
    let d = VoiceSettings::default();
    assert_eq!(serde_json::from_str::<VoiceSettings>("{}").unwrap(), d);
    assert_eq!(serde_json::from_str::<VoiceSettings>("null").unwrap_or(d.clone()), d);

    let p: VoiceSettings = serde_json::from_str(r#"{"enabled":false,"language":"fr"}"#).unwrap();
    assert!(!p.enabled);
    assert_eq!(p.language, "fr");
    assert_eq!(p.model, DEFAULT_MODEL_ID, "absent keys must take defaults");
}

#[test]
fn settings_clamp_instead_of_rejecting() {
    let too_small: VoiceSettings = serde_json::from_str(r#"{"maxUtteranceSeconds":0}"#).unwrap();
    assert_eq!(too_small.sanitized().max_utterance_seconds, MIN_MAX_UTTERANCE_SECS);

    let too_big: VoiceSettings = serde_json::from_str(r#"{"maxUtteranceSeconds":100000}"#).unwrap();
    assert_eq!(too_big.sanitized().max_utterance_seconds, MAX_MAX_UTTERANCE_SECS);

    let bad_hangover: VoiceSettings = serde_json::from_str(r#"{"silenceHangoverMs":1}"#).unwrap();
    assert_eq!(bad_hangover.sanitized().silence_hangover_ms, 300);
}

#[test]
fn settings_sanitize_unknown_model_and_language() {
    let s: VoiceSettings = serde_json::from_str(r#"{"model":"bogus","language":"klingon"}"#).unwrap();
    let s = s.sanitized();
    assert_eq!(s.model, DEFAULT_MODEL_ID);
    assert_eq!(s.language, "auto");
}

#[test]
fn session_config_is_derived_from_sanitized_settings() {
    let mut settings = VoiceSettings::default();
    settings.language = "zh-CN".into();
    settings.auto_finalize = false;
    let cfg = VoiceSessionConfig::from_settings(&settings);
    assert_eq!(cfg.language, "zh");
    assert_eq!(cfg.capture, CaptureTarget::Source, "voice always captures the microphone");
    assert!(!cfg.echo_cancel, "the session inherits the echo-cancellation setting (default off)");
    assert_eq!(cfg.silence_hangover_ms, 0, "autoFinalize:false must disable the hangover");
    assert_eq!(cfg.sample_rate, 16_000);
    assert!(cfg.frame_len > 0);

    settings.echo_cancel = true;
    assert!(VoiceSessionConfig::from_settings(&settings).echo_cancel);
    assert!(!VoiceSessionConfig::from_settings(&settings).noise_suppress,
        "noise suppression is opt-in per session like echo cancellation");
    settings.noise_suppress = true;
    assert!(VoiceSessionConfig::from_settings(&settings).noise_suppress);
}

#[test]
fn explicit_node_capture_keeps_the_pcm_contract() {
    // The echo-cancelled source is not a `@DEFAULT_...@` token, so it needs its
    // own builder - with the same format contract as the default one.
    let args = pw_record_args_for_node("astral_echo_cancel", 16_000, 1, 32);
    let target = args.iter().position(|a| a == "--target").expect("--target");
    assert_eq!(args[target + 1], "astral_echo_cancel");
    assert_eq!(args.iter().position(|a| a == "-P"), None,
        "a capture node must not be asked for sink semantics");
    let rate = args.iter().position(|a| a == "--rate").expect("--rate");
    assert_eq!(args[rate + 1], "16000");
    let format = args.iter().position(|a| a == "--format").expect("--format");
    assert_eq!(args[format + 1], "s16");
    assert_eq!(args.last().map(String::as_str), Some("-"), "stdout is the sink");
}

#[test]
fn session_config_never_carries_an_unknown_model_to_the_engine() {
    let mut settings = VoiceSettings::default();
    settings.model = "not-real".into();
    let cfg = VoiceSessionConfig::from_settings(&settings);
    assert_eq!(cfg.model, DEFAULT_MODEL_ID);
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

#[test]
fn events_serialize_in_the_same_shape_as_chat_streaming() {
    // The QML SplitParser already understands {"type":..,"payload":..}; matching
    // it means the UI can share one event switch.
    let e = VoiceEvent::StateChanged { state: VoiceState::Recording };
    let j = serde_json::to_string(&e).unwrap();
    assert!(j.contains(r#""type":"StateChanged""#), "{j}");
    assert!(j.contains(r#""state":"recording""#), "{j}");
}

#[test]
fn final_event_payload_is_the_transcript_object_itself() {
    // Regression guard: as a struct variant, adjacent tagging nested this under
    // `payload.transcript`, forcing the UI to reach two levels deep for the
    // text. It is a newtype variant specifically so `payload.text` works.
    let t = Transcript {
        text: "hello".into(),
        language: "en".into(),
        duration_ms: 900,
        engine: "whisper-cpp".into(),
        model: "ggml-tiny".into(),
        speech_detected: true,
        language_confidence: None,
        language_source: LanguageSource::Configured,
    };
    let json = serde_json::to_value(VoiceEvent::Final(t.clone())).unwrap();
    assert_eq!(json["type"], "Final");
    assert_eq!(json["payload"]["text"], "hello", "payload must be the transcript itself");
    assert_eq!(json["payload"]["language"], "en");
    assert!(json["payload"].get("transcript").is_none(), "must not be double-nested");
    assert_eq!(VoiceEvent::Final(t).as_final().unwrap().text, "hello");
}

#[test]
fn every_event_variant_round_trips() {
    let transcript = Transcript {
        text: "bonjour, comment allez-vous ?".into(),
        language: "fr".into(),
        duration_ms: 2340,
        engine: "whisper-cpp".into(),
        model: DEFAULT_MODEL_ID.into(),
        speech_detected: true,
        language_confidence: None,
        language_source: LanguageSource::Configured,
    };
    let events = vec![
        VoiceEvent::StateChanged { state: VoiceState::Idle },
        VoiceEvent::StateChanged { state: VoiceState::Recording },
        VoiceEvent::StateChanged { state: VoiceState::Finalizing },
        VoiceEvent::StateChanged { state: VoiceState::Failed },
        VoiceEvent::Level { rms: 0.42 },
        VoiceEvent::Partial { text: "bonjour".into() },
        VoiceEvent::Warning { message: "clipping 68%".into() },
        VoiceEvent::Final(transcript.clone()),
        VoiceEvent::setup_error("model missing"),
        VoiceEvent::fatal_error("engine killed"),
    ];
    for e in events {
        let json = serde_json::to_string(&e).unwrap();
        let back: VoiceEvent = serde_json::from_str(&json)
            .unwrap_or_else(|err| panic!("{} failed to round-trip: {err}", e.kind()));
        assert_eq!(back, e, "{} did not round-trip", e.kind());
    }
}

#[test]
fn recoverable_flag_separates_setup_gaps_from_runtime_deaths() {
    // Setup gaps belong in a persistent inline notice; runtime deaths belong in
    // the crash carousel. Conflating them was explicitly rejected.
    match VoiceEvent::setup_error("no model") {
        VoiceEvent::Error { recoverable, .. } => assert!(recoverable),
        other => panic!("expected Error, got {other:?}"),
    }
    match VoiceEvent::fatal_error("segfault") {
        VoiceEvent::Error { recoverable, .. } => assert!(!recoverable),
        other => panic!("expected Error, got {other:?}"),
    }
}

#[test]
fn voice_state_reports_whether_the_microphone_is_held() {
    assert!(VoiceState::Recording.is_capturing());
    assert!(!VoiceState::Finalizing.is_capturing(), "the mic is released during transcription");
    assert!(!VoiceState::Idle.is_capturing());
    assert!(!VoiceState::Failed.is_capturing());
}

#[test]
fn empty_transcript_is_recognised_as_such() {
    let t = Transcript {
        text: "   ".into(),
        language: "und".into(),
        duration_ms: 900,
        engine: "whisper-cpp".into(),
        model: DEFAULT_MODEL_ID.into(),
        speech_detected: false,
        language_confidence: None,
        language_source: LanguageSource::Configured,
    };
    assert!(t.is_empty(), "whitespace is not a transcript");
    let mut real = t.clone();
    real.text = "你好".into();
    assert!(!real.is_empty());
}

#[test]
fn setup_gap_classification() {
    assert!(!SetupGap::Ready.is_recoverable());
    for gap in [SetupGap::EngineMissing, SetupGap::ModelMissing, SetupGap::NoAudioSource] {
        assert!(gap.is_recoverable(), "{gap:?} must be user-fixable");
    }
}

#[test]
fn engine_probe_reports_a_missing_installation() {
    let p = astral_plasma::domain::voice::EngineProbe::missing("whisper-cpp");
    assert_eq!(p.engine_id, "whisper-cpp");
    assert!(p.binary_path.is_none());
    assert_eq!(p.capabilities, EngineCapabilities::default());
}

// ---------------------------------------------------------------------------
// Transcript insertion
// ---------------------------------------------------------------------------

#[test]
fn transcript_append_never_destroys_typed_text() {
    // Losing a half-written prompt to a dictation result would be a serious
    // data-loss bug, so insertion must be additive in every case.
    assert_eq!(append_transcript("", "hello"), "hello");
    assert_eq!(append_transcript("partial draft", "hello"), "partial draft hello");
    assert_eq!(append_transcript("trailing space ", "hello"), "trailing space hello");
    assert_eq!(append_transcript("new\nline", "hello"), "new\nline hello");
    assert_eq!(append_transcript("代码", "测试"), "代码 测试");
}

#[test]
fn transcript_append_drops_blank_results() {
    // Silence is not content: appending whitespace would corrupt the prompt.
    for blank in ["", "   ", "\n", "\t \n "] {
        assert_eq!(append_transcript("keep me", blank), "keep me");
    }
    assert_eq!(append_transcript("", "   "), "");
}

#[test]
fn transcript_append_normalizes_both_edges() {
    // Engine output routinely carries stray whitespace; normalizing both ends
    // keeps the joined prompt free of double spaces and ragged breaks.
    assert_eq!(append_transcript("x", "  indented  "), "x indented");
    assert_eq!(append_transcript("x", "\nleading"), "x leading");
}

// ---------------------------------------------------------------------------
// The engine's install command must match the machine it is shown on.
// ---------------------------------------------------------------------------

#[test]
fn the_install_command_follows_the_distribution() {
    // Arch and its derivatives: CachyOS declares the family, not the id.
    assert_eq!(package_manager_for_os_release("ID=arch\nID_LIKE=arch\n"), PackageManager::Pacman);
    assert_eq!(package_manager_for_os_release("ID=cachyos\nID_LIKE=\"arch\"\n"), PackageManager::Pacman);
    assert_eq!(package_manager_for_os_release("ID=manjaro\n"), PackageManager::Pacman);

    assert_eq!(package_manager_for_os_release("NAME=\"Ubuntu\"\nID=ubuntu\nID_LIKE=debian\n"), PackageManager::Apt);
    assert_eq!(package_manager_for_os_release("ID=debian\n"), PackageManager::Apt);
    assert_eq!(package_manager_for_os_release("ID=fedora\n"), PackageManager::Dnf);
    assert_eq!(package_manager_for_os_release("ID=rocky\nID_LIKE=\"rhel centos fedora\"\n"), PackageManager::Dnf);
    assert_eq!(
        package_manager_for_os_release("ID=\"opensuse-tumbleweed\"\nID_LIKE=\"opensuse suse\"\n"),
        PackageManager::Zypper
    );
    assert_eq!(package_manager_for_os_release("ID=nixos\n"), PackageManager::Nix);

    // An unknown distribution must not be guessed at.
    assert_eq!(package_manager_for_os_release("ID=plan9\n"), PackageManager::Unknown);
    assert_eq!(package_manager_for_os_release(""), PackageManager::Unknown);
}

#[test]
fn every_named_manager_yields_a_runnable_command_for_the_engine() {
    for manager in [
        PackageManager::Pacman,
        PackageManager::Apt,
        PackageManager::Dnf,
        PackageManager::Zypper,
        PackageManager::Nix,
    ] {
        let command = manager.engine_install_command().expect("a command");
        assert!(command.contains("whisper"), "{command} must name the engine");
        assert!(
            command.starts_with("sudo ") || command.starts_with("nix-shell "),
            "{command} must be runnable as written"
        );
    }
    assert_eq!(
        PackageManager::Unknown.engine_install_command(),
        None,
        "an unknown distro gets the upstream build, not an invented package"
    );
}

// ---------------------------------------------------------------------------
// Audit remediation: gain guard, warning event, neural VAD gate
// ---------------------------------------------------------------------------

#[test]
fn clipping_ratio_detects_adc_saturation() {
    // Silence and ordinary speech never trip the guard.
    assert_eq!(clipping_ratio(&[]), 0.0);
    assert_eq!(clipping_ratio(&vec![0.0f32; 100]), 0.0);
    assert!(clipping_ratio(&vec![0.35f32; 1000]) < CLIPPING_WARN_RATIO);
    assert_eq!(clipping_ratio(&[f32::NAN, 0.1, -0.1]), 0.0);
    // 68% hard-clipped ambient (the measured ALC256 failure) trips it hard.
    let mut clipped = vec![0.99997f32; 684];
    clipped.extend(vec![0.1f32; 316]);
    assert!(clipping_ratio(&clipped) >= 0.68);
    // DC latch at the rails counts as clipped; DC near zero does not.
    assert_eq!(clipping_ratio(&vec![1.0f32; 50]), 1.0);
    assert_eq!(clipping_ratio(&vec![0.7f32; 50]), 0.0);
}

#[test]
fn clipping_advice_names_the_fix() {
    let msg = clipping_advice(0.684);
    assert!(msg.contains("68%"), "must quantify the saturation: {msg}");
    assert!(msg.contains("alsamixer") || msg.contains("Mic Boost"), "must name the remediation: {msg}");
}

#[test]
fn warning_event_round_trips_and_never_fails_the_session() {
    let e = VoiceEvent::Warning { message: "clipping".into() };
    assert_eq!(e.kind(), "Warning");
    let json = serde_json::to_string(&e).unwrap();
    assert!(json.contains(r#""type":"Warning""#), "{json}");
    let back: VoiceEvent = serde_json::from_str(&json).unwrap();
    assert_eq!(back, e);
}

#[test]
fn vad_gate_uses_probability_not_energy() {
    assert!(vad_is_speech(0.91));
    assert!(vad_is_speech(0.5001));
    assert!(!vad_is_speech(0.5), "the gate is strict: p > 0.5");
    assert!(!vad_is_speech(0.08), "a 0.08 tie is not speech");
    assert!(!vad_is_speech(f32::NAN), "non-finite scores never open the gate");
    assert!(!vad_is_speech(f32::INFINITY));
    assert_eq!(VAD_SPEECH_PROB_THRESHOLD, 0.5);
    assert!(!vad_model_file_name().is_empty());
}

#[test]
fn vad_segment_output_parses_to_seconds() {
    use astral_plasma::domain::voice::{parse_vad_segments, vad_segments_to_frames};
    // Live shape from whisper-vad-speech-segments on Front_Center.wav.
    let output = "\
whisper_vad_segments_from_probs: Final speech segments after filtering: 2
Detected 2 speech segments:
Speech segment 0: start = 7.00, end = 54.00
Speech segment 1: start = 77.00, end = 144.00
";
    let segs = parse_vad_segments(output);
    assert_eq!(segs.len(), 2);
    assert!((segs[0].start_s - 0.07).abs() < 1e-6);
    assert!((segs[0].end_s - 0.54).abs() < 1e-6);
    assert!((segs[1].start_s - 0.77).abs() < 1e-6);
    assert!((segs[1].end_s - 1.44).abs() < 1e-6);

    // Silence, banners and garbage parse to nothing — never fabricated.
    assert!(parse_vad_segments("").is_empty());
    assert!(parse_vad_segments("Detected 0 speech segments:\n").is_empty());
    assert!(parse_vad_segments("whisper_print_system_info: n_mels = 80\n").is_empty());
    assert!(parse_vad_segments("Speech segment 0: start = 90.00, end = 10.00\n").is_empty(),
        "an end before its start must not become a negative span");

    // Frame conversion at 16 kHz / 20 ms frames: 0.07s -> frame 3, 1.44s -> frame 72.
    let bounds = vad_segments_to_frames(&segs, 16_000, 320, 200).expect("bounds");
    assert_eq!(bounds, (3, 72));
    assert!(vad_segments_to_frames(&[], 16_000, 320, 200).is_none());
    assert!(vad_segments_to_frames(&segs, 16_000, 0, 200).is_none());
    assert!(vad_segments_to_frames(&segs, 0, 320, 200).is_none());
}

#[test]
fn capture_backend_selection_defaults_to_the_subprocess() {
    use astral_plasma::domain::voice::{select_capture_backend, CaptureBackend};
    assert_eq!(select_capture_backend(""), CaptureBackend::PwRecord);
    assert_eq!(select_capture_backend("pw-record"), CaptureBackend::PwRecord);
    assert_eq!(select_capture_backend("anything-unknown"), CaptureBackend::PwRecord,
        "unknown values must never enable the experimental path by accident");
    assert_eq!(select_capture_backend("native"), CaptureBackend::Native);
    assert_eq!(select_capture_backend(" Native "), CaptureBackend::Native);
}
