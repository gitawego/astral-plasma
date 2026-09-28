//! Domain-level tests for voice input.
//!
//! These require no speech engine, no model and no microphone, which is the point:
//! see `docs/VOICE-INPUT-SPEC.md` §8.1.

use astral_plasma::domain::voice::{
    append_transcript, format_size, frame_rms, is_known_model, model_by_id, normalize_language,
    package_manager_for_os_release, vad_model_url, PackageManager,
    pcm_bytes_to_f32, pw_record_args, should_finalize, staged_download_paths, wav_container,
    wav_header, CaptureTarget, EngineCapabilities, FinalizeReason, LanguageOption,
    PcmSpec, SetupGap, SilenceDetector, Transcript, VoiceEvent, VoiceSessionConfig, VoiceSettings,
    VoiceState, DEFAULT_MAX_UTTERANCE_SECS, DEFAULT_MODEL_ID, MAX_MAX_UTTERANCE_SECS,
    MIN_MAX_UTTERANCE_SECS, MODEL_CATALOG, PcmSpec as Spec, SILENCE_HEADROOM,
    SILENCE_WARMUP_FRAMES, SPEECH_SAMPLE_RATE, VAD_MODEL_FILE, VAD_MODEL_SIZE_BYTES, WAV_HEADER_LEN,
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
fn silence_detector_floor_stays_bounded_in_a_noisy_room() {
    // In a loud room the floor must not creep up until steady background noise
    // starts reading as silence, which would truncate every utterance.
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
fn vad_asset_points_at_the_public_repo() {
    // The asset is not in the ASR model repo. Upstream's own
    // `models/download-vad-model.sh` fetches it from `ggml-org/whisper-vad`,
    // and an earlier attempt at `ggml-org/whisper.cpp` saw HTTP 401 and
    // concluded "unreachable" - Hugging Face answers 401, not 404, for paths
    // an anonymous client may not see. Pin the working, credential-free source.
    assert_eq!(VAD_MODEL_FILE, "ggml-silero-v5.1.2.bin");
    assert!(
        VAD_MODEL_SIZE_BYTES > 100_000 && VAD_MODEL_SIZE_BYTES < 10_000_000,
        "the VAD asset is a small model, got {VAD_MODEL_SIZE_BYTES} bytes"
    );
    assert!(
        vad_model_url().starts_with("https://huggingface.co/ggml-org/whisper-vad/"),
        "the VAD asset lives in its own public repo, got {}",
        vad_model_url()
    );
    assert!(vad_model_url().ends_with(VAD_MODEL_FILE));
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
    assert_eq!(s.language, "auto");
    assert_eq!(s.max_utterance_seconds, DEFAULT_MAX_UTTERANCE_SECS);
    assert!(s.auto_finalize);
    assert!(s.install_model_on_demand);
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
    assert_eq!(cfg.silence_hangover_ms, 0, "autoFinalize:false must disable the hangover");
    assert_eq!(cfg.sample_rate, 16_000);
    assert!(cfg.frame_len > 0);
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
    };
    let events = vec![
        VoiceEvent::StateChanged { state: VoiceState::Idle },
        VoiceEvent::StateChanged { state: VoiceState::Recording },
        VoiceEvent::StateChanged { state: VoiceState::Finalizing },
        VoiceEvent::StateChanged { state: VoiceState::Failed },
        VoiceEvent::Level { rms: 0.42 },
        VoiceEvent::Partial { text: "bonjour".into() },
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
