//! High-performance speech-to-text adapter backed by `sherpa-onnx`.
//!
//! Hosts SenseVoice-Small for sub-100ms on-device ASR with state-of-the-art
//! Mandarin Chinese, English, Japanese, Korean and Cantonese accuracy, zero
//! silence hallucinations, and low CPU footprint.
//!
//! Pluggable behind `SpeechToTextPort`, reusing the shared PipeWire / native
//! audio capture, Silero VAD, gain guards, and safety protocols.

use crate::domain::ports::{DynError, DynResult, SpeechToTextPort};
use crate::domain::voice::{
    models_dir, wav_container, EngineCapabilities, EngineProbe, LanguageSource, PcmSpec,
    Transcript, VoiceEvent, VoiceSessionConfig, VoiceState, LANGUAGE_UNDETERMINED,
};
use crate::infrastructure::whisper_stt_adapter::{
    apply_neural_vad, capture_utterance_shared, trim_to_speech, CancelHandle,
};
use std::path::PathBuf;
use std::process::{Command, Stdio};

/// Environment override for Sherpa binary discovery (test seam + escape hatch).
pub const SHERPA_BIN_ENV: &str = "ASTRAL_VOICE_SHERPA_BIN";
/// Environment override for Sherpa model directory.
pub const SHERPA_MODEL_DIR_ENV: &str = "ASTRAL_VOICE_SHERPA_MODEL_DIR";
/// Environment override for direct model file path.
pub const SHERPA_MODEL_ENV: &str = "ASTRAL_VOICE_SHERPA_MODEL";
/// Environment override for direct tokens file path.
pub const SHERPA_TOKENS_ENV: &str = "ASTRAL_VOICE_SHERPA_TOKENS";

/// Engine id reported in transcripts and status.
pub const SHERPA_ENGINE_ID: &str = "sherpa-onnx";
/// SenseVoice-Small model id in the Sherpa catalog.
pub const SENSEVOICE_SMALL_ID: &str = crate::domain::voice::SENSEVOICE_SMALL_ID;

/// Candidate sidecar binary names. `sherpa-onnx-offline` is the upstream binary for offline ASR.
const SHERPA_BINARIES: &[&str] = &["sherpa-onnx-offline", "sherpa-onnx", "sense-voice"];

/// Resolved model files required by SenseVoice.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SherpaModelFiles {
    pub model_path: PathBuf,
    pub tokens_path: PathBuf,
}

/// Locates the Sherpa sidecar binary.
pub fn locate_sherpa() -> Option<PathBuf> {
    if let Ok(explicit) = std::env::var(SHERPA_BIN_ENV) {
        let p = PathBuf::from(explicit);
        if p.is_file() {
            return Some(p);
        }
    }
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in path_var.split(':').filter(|d| !d.is_empty()) {
            for name in SHERPA_BINARIES {
                let p = PathBuf::from(dir).join(name);
                if p.is_file() {
                    return Some(p);
                }
            }
        }
    }
    let data_home = std::env::var("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| crate::domain::branding::data_home());
    let bin_dir = data_home.join("astral-plasma").join("bin");
    for name in SHERPA_BINARIES {
        let p = bin_dir.join(name);
        if p.is_file() {
            return Some(p);
        }
    }
    None
}

/// Resolves SenseVoice model and tokens files.
pub fn resolve_sherpa_model(model_id: &str) -> Option<SherpaModelFiles> {
    if let (Ok(m), Ok(t)) = (std::env::var(SHERPA_MODEL_ENV), std::env::var(SHERPA_TOKENS_ENV)) {
        let mp = PathBuf::from(m);
        let tp = PathBuf::from(t);
        if mp.is_file() && tp.is_file() {
            return Some(SherpaModelFiles { model_path: mp, tokens_path: tp });
        }
    }

    let base = match std::env::var(SHERPA_MODEL_DIR_ENV) {
        Ok(d) if !d.is_empty() => PathBuf::from(d),
        _ => models_dir(),
    };

    let search_dirs = [
        base.join(model_id),
        base.clone(),
    ];

    let model_names = ["model.int8.onnx", "model.onnx", "sherpa-sensevoice-small.int8.onnx", "sherpa-sensevoice-small.onnx"];
    let tokens_names = ["tokens.txt", "sherpa-sensevoice-small-tokens.txt", "sherpa-sensevoice-small.tokens.txt"];

    for dir in &search_dirs {
        if !dir.is_dir() {
            continue;
        }
        let mut found_model = None;
        let mut found_tokens = None;

        for name in &model_names {
            let candidate = dir.join(name);
            if candidate.is_file() && candidate.metadata().map(|m| m.len() > 0).unwrap_or(false) {
                found_model = Some(candidate);
                break;
            }
        }

        for name in &tokens_names {
            let candidate = dir.join(name);
            if candidate.is_file() && candidate.metadata().map(|m| m.len() > 0).unwrap_or(false) {
                found_tokens = Some(candidate);
                break;
            }
        }

        if let (Some(mp), Some(tp)) = (found_model, found_tokens) {
            return Some(SherpaModelFiles { model_path: mp, tokens_path: tp });
        }
    }

    None
}

/// Maps language preferences to SenseVoice language tags (`auto`, `zh`, `en`, `ja`, `ko`, `yue`).
pub fn map_sensevoice_language(lang: &str) -> &'static str {
    let l = lang.trim().to_lowercase();
    if l.is_empty() || l == "auto" {
        "auto"
    } else if l.starts_with("zh") || l.starts_with("cmn") {
        "zh"
    } else if l.starts_with("en") {
        "en"
    } else if l.starts_with("ja") {
        "ja"
    } else if l.starts_with("ko") {
        "ko"
    } else if l.starts_with("yue") {
        "yue"
    } else {
        "auto"
    }
}

/// Parses recognition output from `sherpa-onnx-offline`.
///
/// Output format is typically:
/// `{"lang": "<|zh|>", "emotion": "<|NEUTRAL|>", "event": "<|Speech|>", "text": "...", "tokens": [...]}`
pub fn parse_sherpa_output(stdout: &str, default_lang: &str) -> (String, String) {
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('{') && trimmed.ends_with('}') {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
                if let Some(text) = v.get("text").and_then(|t| t.as_str()) {
                    let text = text.trim().to_string();
                    let lang = v.get("lang")
                        .and_then(|l| l.as_str())
                        .map(|l| l.trim_matches(|c| c == '<' || c == '|' || c == '>').to_string())
                        .filter(|l| !l.is_empty())
                        .unwrap_or_else(|| default_lang.to_string());
                    return (text, lang);
                }
            }
        }
    }

    if let Ok(v) = serde_json::from_str::<serde_json::Value>(stdout.trim()) {
        if let Some(text) = v.get("text").and_then(|t| t.as_str()) {
            let text = text.trim().to_string();
            let lang = v.get("lang")
                .and_then(|l| l.as_str())
                .map(|l| l.trim_matches(|c| c == '<' || c == '|' || c == '>').to_string())
                .filter(|l| !l.is_empty())
                .unwrap_or_else(|| default_lang.to_string());
            return (text, lang);
        }
    }

    let mut fallback_lines = Vec::new();
    for line in stdout.lines() {
        let t = line.trim();
        if !t.is_empty() && !t.starts_with('[') && !t.starts_with("INFO") && !t.starts_with("DEBUG") {
            fallback_lines.push(t);
        }
    }
    (fallback_lines.join(" "), default_lang.to_string())
}

/// File-based Sherpa-ONNX adapter (SenseVoice-Small).
pub struct SherpaOnnxAdapter {
    binary: Option<PathBuf>,
}

impl SherpaOnnxAdapter {
    pub fn new() -> Self {
        Self { binary: locate_sherpa() }
    }

    #[cfg(test)]
    pub fn with_binary(binary: PathBuf) -> Self {
        Self { binary: Some(binary) }
    }
}

impl Default for SherpaOnnxAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl SpeechToTextPort for SherpaOnnxAdapter {
    fn probe(&self) -> DynResult<EngineProbe> {
        let binary_path = self.binary.as_ref().map(|p| p.to_string_lossy().into_owned());
        let version = self.binary.as_ref().and_then(|bin| {
            Command::new(bin)
                .arg("--version")
                .output()
                .ok()
                .and_then(|out| {
                    if out.status.success() {
                        Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
                    } else {
                        None
                    }
                })
        });

        Ok(EngineProbe {
            engine_id: SHERPA_ENGINE_ID.to_string(),
            binary_path,
            version,
            capabilities: EngineCapabilities {
                reads_stdin: false,
                vad: false,
                vad_model: false,
                audio_context: false,
                beam_search: false,
                best_of: false,
                no_fallback: true,
                language_auto: true,
                detect_language: true,
                output_json: true,
                no_prints: false,
                threads: true,
                translate: false,
            },
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
        let binary = self.binary.clone().ok_or_else(|| -> DynError {
            "sherpa-onnx is not installed".into()
        })?;
        let model_files = resolve_sherpa_model(&cfg.model).ok_or_else(|| -> DynError {
            format!("Sherpa model '{}' is not downloaded yet", cfg.model).into()
        })?;

        sink(VoiceEvent::StateChanged {
            state: VoiceState::Recording,
        });

        let (full_pcm, energy_first, energy_last, energy_speech) =
            match capture_utterance_shared(cfg, handle, sink) {
                Ok(captured) => captured,
                Err(e) => {
                    sink(VoiceEvent::fatal_error(e.to_string()));
                    return Err(e);
                }
            };

        if handle.is_discarded() {
            sink(VoiceEvent::StateChanged {
                state: VoiceState::Idle,
            });
            return Ok(Transcript {
                text: String::new(),
                language: LANGUAGE_UNDETERMINED.to_string(),
                duration_ms: 0,
                engine: SHERPA_ENGINE_ID.to_string(),
                model: cfg.model.clone(),
                speech_detected: false,
                language_confidence: None,
                language_source: LanguageSource::Configured,
            });
        }

        sink(VoiceEvent::StateChanged {
            state: VoiceState::Finalizing,
        });

        let (pcm, has_speech) = match apply_neural_vad(&full_pcm, cfg) {
            Some((Some((first, last)), true)) => (
                trim_to_speech(&full_pcm, cfg.sample_rate, cfg.frame_len, Some(first), Some(last)),
                true,
            ),
            Some((_, neural_speech)) => (Vec::new(), neural_speech),
            None => (
                trim_to_speech(&full_pcm, cfg.sample_rate, cfg.frame_len, energy_first, energy_last),
                energy_speech,
            ),
        };

        if !has_speech {
            let transcript = Transcript {
                text: String::new(),
                language: LANGUAGE_UNDETERMINED.to_string(),
                duration_ms: 0,
                engine: SHERPA_ENGINE_ID.to_string(),
                model: cfg.model.clone(),
                speech_detected: false,
                language_confidence: None,
                language_source: LanguageSource::Configured,
            };
            sink(VoiceEvent::Final(transcript.clone()));
            return Ok(transcript);
        }

        let spec = PcmSpec::speech();
        let duration_ms = spec.duration_ns(pcm.len()) / 1_000_000;
        let wav = wav_container(spec, &pcm);

        let models_dir = models_dir();
        let _ = std::fs::create_dir_all(&models_dir);
        let wav_path = models_dir.join(format!("utterance-sherpa-{}.wav", std::process::id()));
        let tmp_wav = wav_path.with_extension("wav.part");

        std::fs::write(&tmp_wav, &wav)
            .map_err(|e| -> DynError { format!("Cannot stage audio for sherpa-onnx: {e}").into() })?;
        std::fs::rename(&tmp_wav, &wav_path)
            .map_err(|e| -> DynError { format!("Cannot publish staged audio for sherpa-onnx: {e}").into() })?;

        let lang_arg = map_sensevoice_language(&cfg.language);
        let cmd_res = Command::new(&binary)
            .arg(format!("--sense-voice-model={}", model_files.model_path.display()))
            .arg(format!("--tokens={}", model_files.tokens_path.display()))
            .arg(format!("--sense-voice-language={}", lang_arg))
            .arg("--use-itn=true")
            .arg("--num-threads=4")
            .arg(&wav_path)
            .stdin(Stdio::null())
            .output();

        let _ = std::fs::remove_file(&wav_path);
        let _ = std::fs::remove_file(&tmp_wav);

        let out = cmd_res.map_err(|e| -> DynError { format!("Failed to run sherpa-onnx: {e}").into() })?;
        if !out.status.success() {
            let detail = String::from_utf8_lossy(&out.stderr);
            let err_msg = format!("sherpa-onnx failed: {}", detail.lines().last().unwrap_or("no output"));
            sink(VoiceEvent::fatal_error(err_msg.clone()));
            return Err(err_msg.into());
        }

        let stdout_str = String::from_utf8_lossy(&out.stdout);
        let (text, detected_lang) = parse_sherpa_output(&stdout_str, if lang_arg == "auto" { "zh" } else { lang_arg });

        let transcript = Transcript {
            text,
            language: detected_lang,
            duration_ms,
            engine: SHERPA_ENGINE_ID.to_string(),
            model: cfg.model.clone(),
            speech_detected: true,
            language_confidence: None,
            language_source: if cfg.language.is_empty() || cfg.language == "auto" {
                LanguageSource::Detected
            } else {
                LanguageSource::Configured
            },
        };
        sink(VoiceEvent::Final(transcript.clone()));
        Ok(transcript)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probe_reports_missing_installation_honestly() {
        let adapter = SherpaOnnxAdapter { binary: None };
        let probe = crate::domain::ports::SpeechToTextPort::probe(&adapter).unwrap();
        assert_eq!(probe.engine_id, SHERPA_ENGINE_ID);
        assert!(probe.binary_path.is_none());
    }

    #[test]
    fn missing_binary_is_a_setup_gap_not_a_panic() {
        let adapter = SherpaOnnxAdapter { binary: None };
        let cfg = VoiceSessionConfig {
            capture: crate::domain::voice::CaptureTarget::Source,
            echo_cancel: false,
            noise_suppress: false,
            model: SENSEVOICE_SMALL_ID.to_string(),
            language: "en".to_string(),
            language_override: String::new(),
            silence_hangover_ms: 1200,
            max_utterance_ms: 30_000,
            auto_finalize: true,
            frame_len: 320,
            sample_rate: 16_000,
        };
        let mut events = Vec::new();
        let result = crate::domain::ports::SpeechToTextPort::run_session(
            &adapter,
            &cfg,
            &mut |e| events.push(e),
        );
        assert!(result.is_err());
    }

    #[test]
    fn language_mapping_handles_locale_variants() {
        assert_eq!(map_sensevoice_language(""), "auto");
        assert_eq!(map_sensevoice_language("auto"), "auto");
        assert_eq!(map_sensevoice_language("zh"), "zh");
        assert_eq!(map_sensevoice_language("zh-CN"), "zh");
        assert_eq!(map_sensevoice_language("cmn"), "zh");
        assert_eq!(map_sensevoice_language("en"), "en");
        assert_eq!(map_sensevoice_language("en-US"), "en");
        assert_eq!(map_sensevoice_language("ja"), "ja");
        assert_eq!(map_sensevoice_language("ko"), "ko");
        assert_eq!(map_sensevoice_language("yue"), "yue");
        assert_eq!(map_sensevoice_language("fr"), "auto");
    }

    #[test]
    fn output_parser_extracts_json_text_and_lang() {
        let raw = r#"
[I] Reading audio...
{"lang": "<|zh|>", "emotion": "<|NEUTRAL|>", "event": "<|Speech|>", "text": "你好世界", "timestamps": [0.1, 0.2]}
"#;
        let (text, lang) = parse_sherpa_output(raw, "en");
        assert_eq!(text, "你好世界");
        assert_eq!(lang, "zh");

        let raw_en = r#"{"lang": "<|en|>", "text": "Hello world"}"#;
        let (text, lang) = parse_sherpa_output(raw_en, "auto");
        assert_eq!(text, "Hello world");
        assert_eq!(lang, "en");
    }

    #[test]
    fn output_parser_falls_back_to_clean_text() {
        let raw = "Hello world from plain output\n";
        let (text, lang) = parse_sherpa_output(raw, "en");
        assert_eq!(text, "Hello world from plain output");
        assert_eq!(lang, "en");
    }

    #[test]
    fn model_resolver_respects_env_and_directory() {
        let tmp = tempfile::tempdir().unwrap();
        let model_dir = tmp.path().join(SENSEVOICE_SMALL_ID);
        std::fs::create_dir_all(&model_dir).unwrap();
        let model_file = model_dir.join("model.int8.onnx");
        let tokens_file = model_dir.join("tokens.txt");
        std::fs::write(&model_file, b"fake-onnx").unwrap();
        std::fs::write(&tokens_file, b"fake-tokens").unwrap();

        std::env::set_var(SHERPA_MODEL_DIR_ENV, tmp.path().to_str().unwrap());
        let res = resolve_sherpa_model(SENSEVOICE_SMALL_ID);
        std::env::remove_var(SHERPA_MODEL_DIR_ENV);

        assert!(res.is_some());
        let files = res.unwrap();
        assert_eq!(files.model_path, model_file);
        assert_eq!(files.tokens_path, tokens_file);
    }
}
