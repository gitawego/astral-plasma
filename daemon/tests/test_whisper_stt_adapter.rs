//! Integration tests for the whisper.cpp adapter.
//!
//! Every test here runs with **no engine installed**: argument construction and
//! output parsing are pure functions over a synthetic capability set, which is
//! what makes the adapter testable on a machine that has never downloaded a
//! model. See `docs/VOICE-INPUT-SPEC.md` §8.3.

use astral_plasma::domain::voice::{EngineCapabilities, LANGUAGE_AUTO};
use astral_plasma::infrastructure::whisper_stt_adapter::{
    audio_context_for, build_args, build_detect_args, extract_transcript, parse_detected_language,
    parse_version, probe_capabilities, resolve_transcription_language, EngineInvocation,
    LanguageSource,
};
use std::path::{Path, PathBuf};

fn invocation(caps: EngineCapabilities) -> EngineInvocation {
    EngineInvocation {
        binary: PathBuf::from("/usr/bin/whisper-cli"),
        model: PathBuf::from("/models/ggml-large-v3-turbo.bin"),
        language: "auto".to_string(),
        fallback_language: "en".to_string(),
        threads: 8,
        capabilities: caps,
    }
}

fn full_caps() -> EngineCapabilities {
    EngineCapabilities {
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
        detect_language: true,
    }
}

/// Every `build_args` call in these tests is about *flags*, not timing, so one
/// representative utterance duration keeps the calls readable.
const UTTERANCE_MS: u64 = 3_000;

fn flag_value(args: &[String], flag: &str) -> Option<String> {
    args.iter().position(|a| a == flag).and_then(|i| args.get(i + 1)).cloned()
}

// ---------------------------------------------------------------------------
// Capability probing
// ---------------------------------------------------------------------------

#[test]
fn probe_recognises_a_full_featured_build() {
    let help = "\
usage: whisper-cli [options] file.wav [file.wav ...]

  -f,    --file FNAME       [required] audio file
  -m,    --model FNAME      [required] model file
  -l,    --language LANG    [auto] spoken language
  -t,    --threads N        number of threads
  -np,   --no-prints        do not print anything
  -oj,   --output-json      output result in JSON format
  -ac N, --audio-ctx N      audio context size (0 - all)
  -bs N, --beam-size N      beam size for beam search
  -bo N, --best-of N        number of best candidates to keep
  -nf,   --no-fallback      do not use temperature fallback while decoding
  -tr,   --translate        translate non-English speech
  --vad                    enable VAD preprocessing
  --vad-model FNAME        VAD model path
";
    let caps = probe_capabilities(help);
    assert!(caps.reads_stdin);
    assert!(caps.no_prints);
    assert!(caps.output_json);
    assert!(caps.threads);
    assert!(caps.audio_context, "-ac/--audio-ctx is the encoder cost knob and must be probed");
    assert!(caps.beam_search, "-bs/--beam-size is the decode cost knob and must be probed");
    assert!(caps.best_of, "-bo/--best-of multiplies fallback passes and must be probed");
    assert!(caps.no_fallback, "-nf/--no-fallback bounds the decode and must be probed");
    assert!(caps.vad);
    assert!(caps.vad_model);
    assert!(caps.translate);
}

#[test]
fn probe_degrades_gracefully_on_a_minimal_build() {
    // An old or minimal build must not cause us to emit flags it will reject.
    let caps = probe_capabilities("whisper-cli -f in.wav -m model.bin\n");
    assert!(caps.reads_stdin, "the required file flag is always present");
    assert!(!caps.vad);
    assert!(!caps.audio_context);
    assert!(!caps.beam_search);
    assert!(!caps.best_of);
    assert!(!caps.no_fallback);
    assert!(!caps.output_json);
    assert!(!caps.no_prints);
    assert!(!caps.threads);
    assert!(!caps.vad_model);
}

#[test]
fn probe_of_unexpected_output_is_all_false() {
    let caps = probe_capabilities("");
    assert_eq!(caps, EngineCapabilities::default());
    assert!(!caps.reads_stdin);
}

// ---------------------------------------------------------------------------
// Argument construction
// ---------------------------------------------------------------------------

#[test]
fn required_flags_are_always_present() {
    for caps in [EngineCapabilities::default(), full_caps()] {
        let inv = invocation(caps);
        let args = build_args(&inv, Path::new("/tmp/utterance.wav"), UTTERANCE_MS);
        assert_eq!(
            flag_value(&args, "-m"),
            Some("/models/ggml-large-v3-turbo.bin".to_string()),
            "the model must always be named or the engine cannot start"
        );
        assert_eq!(flag_value(&args, "-f"), Some("/tmp/utterance.wav".to_string()));
        assert_eq!(flag_value(&args, "-l"), Some("auto".to_string()));
    }
}

#[test]
fn unsupported_flags_are_omitted() {
    // The whole point of probing: never pass a flag the build does not know.
    let args = build_args(&invocation(EngineCapabilities::default()), Path::new("/tmp/u.wav"), UTTERANCE_MS);
    for absent in ["--vad", "-oj", "-np", "-t", "-tr", "-ac", "-bs", "-bo", "-nf"] {
        assert!(!args.iter().any(|a| a == absent), "{absent} must not be emitted for a minimal build");
    }
}

#[test]
fn supported_flags_are_emitted_with_correct_values() {
    let args = build_args(&invocation(full_caps()), Path::new("/tmp/u.wav"), UTTERANCE_MS);
    assert!(args.iter().any(|a| a == "-oj"), "structured output avoids banner parsing");
    assert!(args.iter().any(|a| a == "-np"), "progress bars would corrupt the transcript");
    assert_eq!(flag_value(&args, "-t"), Some("8".to_string()));
    assert_eq!(flag_value(&args, "-ac"), Some(audio_context_for(UTTERANCE_MS).to_string()),
        "the encoder context must be sized to the utterance, not the 30s default");
}

#[test]
fn decode_is_bounded_so_hard_audio_cannot_loop() {
    // Measured on real-room captures (music + speech at conversational level):
    // the CLI defaults (beam 5, best-of 5, temperature fallback up to 1.0) let
    // the decoder generate long hallucinated sequences on non-speech audio.
    // The same 3.3s clip took 45s with the defaults, 24s with greedy plus full
    // fallback, and 6s with greedy plus no fallback - and clean speech was
    // unaffected (JFK: 0.6s, identical transcript). Dictation must be bounded,
    // so every knob that multiplies decode cost is pinned.
    let args = build_args(&invocation(full_caps()), Path::new("/tmp/u.wav"), UTTERANCE_MS);
    assert_eq!(flag_value(&args, "-bs"), Some("1".to_string()),
        "beam search multiplies every hallucinated token by the beam width");
    assert_eq!(flag_value(&args, "-bo"), Some("1".to_string()),
        "best-of multiplies every sampling pass");
    assert!(args.iter().any(|a| a == "-nf"),
        "temperature fallback must be off: it retries the whole decode several times on non-speech");
}

#[test]
fn audio_context_is_sized_to_the_utterance_and_bounded() {
    // whisper.cpp encodes `n_audio_ctx * 20ms` of audio per window regardless of
    // how short the clip is, so a fixed 30s context made every utterance pay the
    // same ~1.7s encoder pass on CPU. The context must cover the trimmed audio
    // with a margin (a window smaller than the audio splits it and degrades the
    // transcript), never fall below whisper's safe segmentation floor, and never
    // exceed the trained 30s window.
    assert_eq!(audio_context_for(0), 256, "an empty utterance keeps the safe floor");
    assert_eq!(audio_context_for(2_500), 256, "2.5s is below the floor: 5.12s window");
    assert_eq!(audio_context_for(4_000), 264, "4s + 1.28s margin");
    assert_eq!(audio_context_for(11_000), 614, "11s + 1.28s margin");
    assert_eq!(audio_context_for(30_000), 1500, "30s is the trained window");
    assert_eq!(audio_context_for(120_000), 1500, "longer audio keeps the trained window");
    for ms in [0u64, 1, 500, 2_000, 5_000, 9_999, 29_999, 30_000, 60_000] {
        let ctx = audio_context_for(ms);
        assert!((256..=1500).contains(&ctx), "context out of bounds for {ms}ms: {ctx}");
    }
}

#[test]
fn vad_preprocessing_is_never_requested_from_the_engine() {
    // whisper.cpp applies `--vad` *before* language detection: `whisper_full`
    // replaces the samples with the VAD-filtered audio and then
    // `whisper_full_with_state` auto-detects the language from that filtered
    // audio (src/whisper.cpp). Measured on music+speech mixes, that costs about
    // 3 dB of detection headroom and can clip the utterance: at -12 dB
    // music-to-voice the unfiltered run detects `fr` with the exact transcript
    // while the VAD run detects `en` and returns "Quoi ?". The daemon's own
    // SilenceDetector does endpointing and no-speech gating, so the engine is
    // never asked to VAD - however loudly the build advertises the flags.
    let args = build_args(&invocation(full_caps()), Path::new("/tmp/u.wav"), UTTERANCE_MS);
    assert!(!args.iter().any(|a| a == "--vad"),
        "engine VAD rewrites the audio before language detection and must not be requested");
    assert!(!args.iter().any(|a| a == "--vad-model"),
        "no VAD model may be named: the flags are not used");
}

#[test]
fn language_is_passed_through_for_every_supported_locale() {
    for lang in ["zh", "en", "fr", "de", "it", "es", "pt", "ru", "ja", "auto"] {
        let mut inv = invocation(EngineCapabilities::default());
        inv.language = lang.to_string();
        let args = build_args(&inv, Path::new("/tmp/u.wav"), UTTERANCE_MS);
        assert_eq!(flag_value(&args, "-l"), Some(lang.to_string()));
    }
}

#[test]
fn audio_is_always_a_file_never_a_stdin_pipe() {
    // Piping would hang on builds that read stdin, and a file is re-runnable
    // for debugging. This must hold even when the build advertises stdin.
    let mut caps = full_caps();
    caps.reads_stdin = true;
    let args = build_args(&invocation(caps), Path::new("/tmp/real.wav"), UTTERANCE_MS);
    assert!(!args.iter().any(|a| a == "-"), "must not request a stdin pipe");
    assert_eq!(flag_value(&args, "-f"), Some("/tmp/real.wav".to_string()));
}

#[test]
fn arg_vector_has_no_empty_tokens() {
    let args = build_args(&invocation(full_caps()), Path::new("/tmp/u.wav"), UTTERANCE_MS);
    assert!(!args.is_empty());
    for a in &args {
        assert!(!a.trim().is_empty(), "empty token would be passed literally to the engine");
    }
}

// ---------------------------------------------------------------------------
// Transcript extraction
// ---------------------------------------------------------------------------

#[test]
fn json_transcript_segments_are_concatenated() {
    let json = r#"{"transcription":[{"text":" Bonjour"},{"text":" le"},{"text":" monde"}]}"#;
    assert_eq!(extract_transcript(json, true), "Bonjour le monde");
}

#[test]
fn json_flat_text_field_is_supported() {
    assert_eq!(extract_transcript(r#"{"text":" 你好"}"#, true), "你好");
}

#[test]
fn plain_text_output_strips_timestamps_and_banners() {
    // whisper.cpp interleaves timestamps and log banners with the transcript.
    // Leaving a `[00:00:00.000 --> 00:00:02.000]` prefix in the prompt would
    // be both ugly and misleading to the model.
    let stdout = "\
whisper_print_system_info: n_mels = 80, n_vocab = 51866
model_load: n_ctx = 0
[00:00:00.000 --> 00:00:02.000]   Hello there.
[00:00:02.000 --> 00:00:04.500]   How are you?
total time = 1200.00 ms
";
    let text = extract_transcript(stdout, false);
    assert_eq!(text, "Hello there. How are you?");
    assert!(!text.contains("-->"), "timestamps must be stripped");
    assert!(!text.contains("n_mels"));
    assert!(!text.contains("total time"));
}

#[test]
fn multiline_transcripts_are_joined_into_one_line() {
    let stdout = "[00:00:00.000 --> 00:00:01.000]   first line\n[00:00:01.000 --> 00:00:02.000]   second line\n";
    assert_eq!(extract_transcript(stdout, false), "first line second line");
}

#[test]
fn noise_only_output_yields_an_empty_transcript_not_placeholder_text() {
    // AGENTS.md §4 forbids fabricating content. Silence and noise must surface
    // as an empty result, never as invented words.
    let stdout = "whisper_print_system_info: n_mels = 80\ntotal time = 900.00 ms\n";
    assert_eq!(extract_transcript(stdout, false), "");
    assert_eq!(extract_transcript("", true), "");
    assert_eq!(extract_transcript("   \n  \n", false), "");
}

#[test]
fn malformed_json_yields_empty_never_raw_engine_output() {
    // If the build advertises -oj then its stdout IS JSON. Falling back to the
    // line filter on a parse failure would splice raw engine noise straight
    // into the user's prompt.
    let broken = r#"{"transcription": [ {"text": "#;
    assert_eq!(extract_transcript(broken, true), "");
    assert_eq!(extract_transcript("not json at all", true), "");
    assert_eq!(extract_transcript("<html>404</html>", true), "");
}

#[test]
fn json_object_without_a_recognised_field_yields_empty() {
    assert_eq!(extract_transcript(r#"{"unexpected": 42}"#, true), "");
    assert_eq!(extract_transcript(r#"{"transcription": []}"#, true), "");
}

#[test]
fn json_output_is_preferred_when_the_build_supports_it() {
    // With -oj the payload is clean JSON, so the line filter is not needed and
    // would mangle it.
    let json = r#"{"transcription":[{"text":"keep [brackets] intact"}]}"#;
    assert_eq!(extract_transcript(json, true), "keep [brackets] intact");
}

#[test]
fn cjk_transcripts_survive_extraction() {
    let json = r#"{"transcription":[{"text":" 请帮我"},{"text":"检查系统日志"}]}"#;
    assert_eq!(extract_transcript(json, true), "请帮我检查系统日志");

    let plain = "[00:00:00.000 --> 00:00:03.000]   检查系统日志\n";
    assert_eq!(extract_transcript(plain, false), "检查系统日志");
}

// ---------------------------------------------------------------------------
// Version parsing
// ---------------------------------------------------------------------------

#[test]
fn version_parsing_finds_a_version_token() {
    assert_eq!(parse_version("whisper-cli v1.9.4"), Some("v1.9.4".to_string()));
    assert_eq!(parse_version("built with whisper.cpp 1.7.4"), Some("1.7.4".to_string()));
    assert_eq!(parse_version("version 2.0"), Some("2.0".to_string()));
}

#[test]
fn version_parsing_ignores_non_version_numbers() {
    assert_eq!(parse_version("no version information here"), None);
    assert_eq!(parse_version(""), None);
    // A bare sample rate is not a version.
    assert_eq!(parse_version("16000"), None);
    // Leading-zero values are parameter defaults, not versions.
    assert_eq!(parse_version("0.5"), None);
}

#[test]
fn version_parsing_survives_odd_shapes() {
    // Must terminate and not panic on adversarial input.
    for junk in ["...", "1.", ".1", "v", "999999999999999.0", "1.2.3.4.5"] {
        let _ = parse_version(junk);
    }
}

// ---------------------------------------------------------------------------
// Language detection
// ---------------------------------------------------------------------------

/// The reported failure, in one assertion.
///
/// "Can you help me" came back as "会議のも学び". The engine auto-detects by
/// taking a bare `argmax` over 100 language logits
/// (`whisper_lang_auto_detect_internal`, `return logits_id[0].second`), with
/// no confidence gate and no fallback: the winner is committed to
/// `state->lang_id` and becomes a hard decoder constraint. The probability of
/// that winner is printed to stderr and was being discarded, so the shell never
/// learned that the answer was a coin toss.
#[test]
fn the_detection_confidence_whisper_prints_is_recovered_and_gated() {
    let stderr = "\
load_backend: loaded CPU backend from /usr/lib/ggml/libggml-cpu.so
whisper_init_from_file_with_params_no_state: loading model from 'ggml-small.bin'
whisper_full_with_state: auto-detected language: ja (p = 0.084213)
";
    let (language, confidence) =
        parse_detected_language(stderr).expect("the engine reports its own detection");
    assert_eq!(language, "ja");
    assert!(
        (confidence - 0.084213).abs() < 1e-6,
        "the probability must survive the parse, got {confidence}"
    );

    // The user asked for auto-detect and the locale is English, and 0.08 is a
    // coin toss between 100 languages. Trusting it is what produced Japanese
    // output from English speech, so an unconfident detection must not be used.
    let resolved = resolve_transcription_language(LANGUAGE_AUTO, "en", Some((language, confidence)));
    assert_eq!(
        resolved.transcription_language, "en",
        "an unconfident detection must fall back to the configured language"
    );
    assert_eq!(
        resolved.detected_language, "ja",
        "the detection is still reported, so the UI can show what happened"
    );
    assert_eq!(
        resolved.source, LanguageSource::DetectedOverridden,
        "the reason it was overridden must be recorded, not hidden"
    );
    assert!(
        resolved.confidence.is_some(),
        "the engine's own reading must reach the UI, not just the decision"
    );
}

#[test]
fn a_confident_detection_is_used_as_asked() {
    let resolved = resolve_transcription_language(LANGUAGE_AUTO, "en", Some(("ja".into(), 0.91)));
    assert_eq!(resolved.transcription_language, "ja");
    assert_eq!(resolved.detected_language, "ja");
    assert_eq!(resolved.source, LanguageSource::Detected);
}

#[test]
fn a_configured_language_is_never_overridden_by_a_detection() {
    // The user pinned a language. Detection is advisory, never authoritative --
    // however confident it is. A bilingual speaker dictating in Japanese with
    // English set as the default must not have the setting overruled.
    let resolved = resolve_transcription_language("zh", "en", Some(("ja".into(), 0.99)));
    assert_eq!(resolved.transcription_language, "zh");
    assert_eq!(resolved.detected_language, "ja", "the disagreement is still shown");
    assert_eq!(resolved.source, LanguageSource::Configured);
    // And with no detection at all, the pinned language stands.
    let plain = resolve_transcription_language("zh", "en", None);
    assert_eq!(plain.transcription_language, "zh");
    assert_eq!(plain.source, LanguageSource::Configured);
    // Auto-detect with no detection available falls back to the locale.
    let fallback = resolve_transcription_language(LANGUAGE_AUTO, "de", None);
    assert_eq!(fallback.transcription_language, "de");
    assert_eq!(fallback.source, LanguageSource::Configured);
}

/// Detection is isolated from transcription so the answer can be judged, shown
/// and overridden *before* the expensive decode is committed to it.
#[test]
fn the_detection_pass_asks_the_engine_to_stop_after_identifying() {
    let inv = invocation(full_caps());
    let args = build_detect_args(&inv, Path::new("/tmp/utterance.wav"));
    let joined = args.join(" ");

    assert!(
        args.contains(&"-dl".to_string()),
        "the detection pass must ask the engine to exit after detecting: {joined}"
    );
    assert!(flag_value(&args, "-f").is_some(), "it still needs the audio");
    assert!(flag_value(&args, "-m").is_some(), "it still needs the model");
    assert!(
        !args.contains(&"-tr".to_string()),
        "a detection pass must not translate: {joined}"
    );
    // A build that cannot detect separately must get nothing rather than a
    // guessed flag list, and the caller falls back to a single `-l auto` pass.
    let mut caps = full_caps();
    caps.detect_language = false;
    assert!(
        build_detect_args(&invocation(caps), Path::new("/tmp/u.wav")).is_empty(),
        "an unsupported flag must not be emitted at all"
    );
}

#[test]
fn the_detection_flag_is_discovered_from_the_installed_build() {
    let caps = probe_capabilities(
        "usage: whisper-cli [options]\n  -dl, --detect-language [false] exit after detecting\n",
    );
    assert!(
        caps.detect_language,
        "whisper-cli advertises -dl; the probe must find it"
    );
}
