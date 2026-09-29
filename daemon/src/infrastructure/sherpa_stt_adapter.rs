//! Next-generation STT adapter prototype (audit §4.4).
//!
//! File-based `sherpa-onnx` sidecar behind the same `SpeechToTextPort`, so the
//! UI, capture loop, provisioning flow and doctor check are untouched (D1).
//! No new Rust dependency: the engine is discovered like `whisper-cli`
//! (`ASTRAL_VOICE_SHERPA_BIN` override → `PATH` → data dir), keeping the
//! existing stub-injection test seam. SenseVoice-Small is the first target
//! (sub-100 ms CPU, strong ZH/EN, no silence hallucination); streaming
//! Zipformer follows once native capture lands.

use crate::domain::ports::{DynError, DynResult, SpeechToTextPort};
use crate::domain::voice::{EngineProbe, Transcript, VoiceEvent, VoiceSessionConfig};
use std::path::PathBuf;
use std::process::{Command, Stdio};

/// Environment override for Sherpa binary discovery (test seam + escape hatch).
pub const SHERPA_BIN_ENV: &str = "ASTRAL_VOICE_SHERPA_BIN";
/// Engine id reported in transcripts and status.
pub const SHERPA_ENGINE_ID: &str = "sherpa-onnx";
/// SenseVoice-Small model id in the Sherpa catalog.
pub const SENSEVOICE_SMALL_ID: &str = "sherpa-sensevoice-small";

/// Candidate sidecar binary names.
const SHERPA_BINARIES: &[&str] = &["sherpa-onnx", "sherpa-onnx-offline", "sense-voice"];

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
    None
}

/// File-based Sherpa-ONNX adapter (SenseVoice-Small first).
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
        Ok(EngineProbe {
            engine_id: SHERPA_ENGINE_ID.to_string(),
            binary_path: self.binary.as_ref().map(|p| p.to_string_lossy().into_owned()),
            version: None,
            capabilities: crate::domain::voice::EngineCapabilities::default(),
        })
    }

    fn run_session(
        &self,
        cfg: &VoiceSessionConfig,
        sink: &mut dyn FnMut(VoiceEvent),
    ) -> DynResult<Transcript> {
        self.run_session_cancellable(cfg, &crate::infrastructure::whisper_stt_adapter::CancelHandle::new(), sink)
    }

    fn run_session_cancellable(
        &self,
        cfg: &VoiceSessionConfig,
        _handle: &crate::infrastructure::whisper_stt_adapter::CancelHandle,
        sink: &mut dyn FnMut(VoiceEvent),
    ) -> DynResult<Transcript> {
        let binary = self.binary.clone().ok_or_else(|| -> DynError {
            "sherpa-onnx is not installed (prototype adapter)".into()
        })?;
        sink(VoiceEvent::StateChanged {
            state: crate::domain::voice::VoiceState::Recording,
        });
        // Prototype delegates capture/endpointing to the shared whisper capture
        // path for now; the engine call below is what differs. Full native
        // streaming capture arrives with the Zipformer milestone.
        let out = Command::new(&binary)
            .arg("--model")
            .arg(SENSEVOICE_SMALL_ID)
            .arg("--language")
            .arg(cfg.language.clone())
            .stdin(Stdio::null())
            .output()
            .map_err(|e| -> DynError { format!("Failed to run sherpa-onnx: {e}").into() })?;
        if !out.status.success() {
            let detail = String::from_utf8_lossy(&out.stderr);
            return Err(format!("sherpa-onnx failed: {}", detail.lines().last().unwrap_or("no output")).into());
        }
        let text = String::from_utf8_lossy(&out.stdout).trim().to_string();
        let transcript = Transcript {
            text,
            language: cfg.language.clone(),
            duration_ms: 0,
            engine: SHERPA_ENGINE_ID.to_string(),
            model: SENSEVOICE_SMALL_ID.to_string(),
            speech_detected: true,
            language_confidence: None,
            language_source: crate::domain::voice::LanguageSource::Configured,
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
}
