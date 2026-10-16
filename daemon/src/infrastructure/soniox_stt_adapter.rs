//! Opt-in cloud STT adapter: Soniox realtime speech-to-text.
//!
//! Soniox specializes in high-accuracy multilingual recognition and
//! speech-to-text code-switching (e.g. Chinese-English).
//! Selecting `engine: "soniox"` in settings activates this adapter.
//! The API key is stored owner-only beside settings.json.
//!
//! Protocol: `wss://api.soniox.com/transcribe-websocket`.
//! On connect, sends a config JSON frame, followed by binary PCM chunks (16kHz s16le),
//! and receives real-time JSON events containing non-final and final words.

use crate::domain::ports::{DynError, DynResult, SpeechToTextPort};
use crate::domain::voice::{
    EngineProbe, LanguageSource, PcmSpec, Transcript, VoiceEvent, VoiceSessionConfig,
};
use std::path::PathBuf;
use std::time::Duration;

/// Engine id used in settings and transcripts.
pub const SONIOX_ENGINE_ID: &str = "soniox";
/// Model reported on transcripts.
pub const SONIOX_MODEL_ID: &str = "soniox-realtime";
/// Environment override for the API key.
pub const SONIOX_KEY_ENV: &str = "ASTRAL_SONIOX_KEY";
/// Environment override for the endpoint URL.
pub const SONIOX_ENDPOINT_ENV: &str = "ASTRAL_SONIOX_ENDPOINT";
/// Default live endpoint.
pub const SONIOX_ENDPOINT: &str = "wss://api.soniox.com/transcribe-websocket";

/// File holding the API key, beside settings.json, owner-only.
fn key_path() -> PathBuf {
    crate::domain::branding::config_home()
        .join("astral-plasma")
        .join("soniox_api_key")
}

/// Reads the API key: explicit env wins, then owner-only file.
pub fn read_key() -> Option<String> {
    if let Ok(k) = std::env::var(SONIOX_KEY_ENV) {
        let k = k.trim().to_string();
        if !k.is_empty() {
            return Some(k);
        }
    }
    std::fs::read_to_string(key_path())
        .ok()
        .map(|k| k.trim().to_string())
        .filter(|k| !k.is_empty())
}

/// Stores the API key with owner-only permissions.
pub fn store_key(key: &str) -> DynResult<()> {
    let key = key.trim();
    if key.is_empty() {
        return Err("Refusing to store an empty API key".into());
    }
    let path = key_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| -> DynError { format!("Cannot create config dir: {e}").into() })?;
    }
    std::fs::write(&path, key)
        .map_err(|e| -> DynError { format!("Cannot store key: {e}").into() })?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))
            .map_err(|e| -> DynError { format!("Cannot lock down key file: {e}").into() })?;
    }
    Ok(())
}

/// Deletes the stored API key, if any.
pub fn clear_key() -> DynResult<bool> {
    let path = key_path();
    match std::fs::remove_file(&path) {
        Ok(()) => Ok(true),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(format!("Cannot clear key: {e}").into()),
    }
}

pub fn endpoint() -> String {
    std::env::var(SONIOX_ENDPOINT_ENV)
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| SONIOX_ENDPOINT.to_string())
}

/// Generates the initial configuration JSON for the Soniox session.
pub fn make_config_payload(key: &str) -> String {
    serde_json::json!({
        "api_key": key,
        "app_name": "astral-plasma",
        "sample_rate": 16000,
        "num_channels": 1,
        "audio_format": "pcm_s16le",
        "include_nonfinal": true
    })
    .to_string()
}

/// One parsed hypothesis from a Soniox stream packet.
#[derive(Debug, Clone, PartialEq)]
pub struct SonioxHypothesis {
    pub text: String,
    pub is_final: bool,
}

/// Parses a Soniox websocket JSON message.
pub fn parse_message(raw: &str) -> Option<SonioxHypothesis> {
    let v: serde_json::Value = serde_json::from_str(raw).ok()?;
    if let Some(err) = v.get("error_code") {
        if err.as_i64().unwrap_or(0) != 0 {
            return None;
        }
    }

    if let Some(words) = v.get("words").and_then(|w| w.as_array()) {
        if words.is_empty() {
            return None;
        }
        let mut tokens = Vec::with_capacity(words.len());
        let mut all_final = true;
        for w in words {
            if let Some(text) = w.get("text").and_then(|t| t.as_str()) {
                tokens.push(text);
            }
            if !w.get("is_final").and_then(|f| f.as_bool()).unwrap_or(false) {
                all_final = false;
            }
        }
        let text = tokens.join(" ").trim().to_string();
        if text.is_empty() {
            return None;
        }
        return Some(SonioxHypothesis {
            text,
            is_final: all_final,
        });
    }

    if let Some(t) = v.get("text").and_then(|s| s.as_str()) {
        let trimmed = t.trim().to_string();
        if !trimmed.is_empty() {
            let is_final = v.get("is_final").and_then(|b| b.as_bool()).unwrap_or(false);
            return Some(SonioxHypothesis {
                text: trimmed,
                is_final,
            });
        }
    }

    None
}

pub struct SonioxSttAdapter;

impl SonioxSttAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl Default for SonioxSttAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl SpeechToTextPort for SonioxSttAdapter {
    fn probe(&self) -> DynResult<EngineProbe> {
        Ok(EngineProbe {
            engine_id: SONIOX_ENGINE_ID.to_string(),
            binary_path: None,
            version: Some(SONIOX_MODEL_ID.to_string()),
            capabilities: crate::domain::voice::EngineCapabilities::default(),
        })
    }

    fn run_session(
        &self,
        cfg: &VoiceSessionConfig,
        sink: &mut dyn FnMut(VoiceEvent),
    ) -> DynResult<Transcript> {
        let handle = crate::infrastructure::whisper_stt_adapter::CancelHandle::new();
        self.run_session_cancellable(cfg, &handle, sink)
    }

    fn run_session_cancellable(
        &self,
        cfg: &VoiceSessionConfig,
        handle: &crate::infrastructure::whisper_stt_adapter::CancelHandle,
        sink: &mut dyn FnMut(VoiceEvent),
    ) -> DynResult<Transcript> {
        let key = read_key().ok_or_else(|| -> DynError {
            "Soniox API key is not configured. Set it in Settings or via ASTRAL_SONIOX_KEY".into()
        })?;

        let (pcm, _first, _last, has_speech) =
            crate::infrastructure::whisper_stt_adapter::capture_utterance_shared(
                cfg, handle, sink,
            )?;

        sink(VoiceEvent::StateChanged {
            state: crate::domain::voice::VoiceState::Finalizing,
        });

        if !has_speech {
            let transcript = Transcript {
                text: String::new(),
                language: crate::domain::voice::LANGUAGE_UNDETERMINED.to_string(),
                duration_ms: 0,
                engine: SONIOX_ENGINE_ID.to_string(),
                model: SONIOX_MODEL_ID.to_string(),
                speech_detected: false,
                language_confidence: None,
                language_source: LanguageSource::Configured,
            };
            sink(VoiceEvent::Final(transcript.clone()));
            return Ok(transcript);
        }

        let spec = PcmSpec::speech();
        let duration_ms = spec.duration_ns(pcm.len()) / 1_000_000;
        let url = endpoint();

        let (final_text, interims) = stream_transcribe(&url, &key, &pcm)?;
        for partial in interims {
            sink(VoiceEvent::Partial { text: partial });
        }

        let transcript = Transcript {
            text: final_text,
            language: if cfg.language.is_empty() || cfg.language == "auto" {
                "zh".to_string()
            } else {
                cfg.language.clone()
            },
            duration_ms,
            engine: SONIOX_ENGINE_ID.to_string(),
            model: SONIOX_MODEL_ID.to_string(),
            speech_detected: true,
            language_confidence: None,
            language_source: LanguageSource::Configured,
        };
        sink(VoiceEvent::Final(transcript.clone()));
        Ok(transcript)
    }
}

fn stream_transcribe(url: &str, key: &str, pcm: &[u8]) -> DynResult<(String, Vec<String>)> {
    let url = url.to_string();
    let key = key.to_string();
    let pcm = pcm.to_vec();

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| -> DynError { format!("Tokio runtime failed: {e}").into() })?;

    rt.block_on(async move { stream_transcribe_async(&url, &key, &pcm).await })
}

async fn stream_transcribe_async(
    url: &str,
    key: &str,
    pcm: &[u8],
) -> DynResult<(String, Vec<String>)> {
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::Message;

    let (mut ws, _) = tokio_tungstenite::connect_async(url)
        .await
        .map_err(|e| -> DynError { format!("Soniox connect failed: {e}").into() })?;

    let init_config = make_config_payload(key);
    ws.send(Message::Text(init_config.into()))
        .await
        .map_err(|e| -> DynError { format!("Config handshake failed: {e}").into() })?;

    for chunk in pcm.chunks(8000) {
        ws.send(Message::Binary(chunk.to_vec().into()))
            .await
            .map_err(|e| -> DynError { format!("Audio chunk upload failed: {e}").into() })?;
    }

    // Send empty binary frame to signal end of audio to Soniox
    ws.send(Message::Binary(vec![].into()))
        .await
        .map_err(|e| -> DynError { format!("Final audio EOF frame failed: {e}").into() })?;

    let mut final_text = String::new();
    let mut interims: Vec<String> = Vec::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);

    loop {
        if tokio::time::Instant::now() > deadline {
            break;
        }
        let msg = match tokio::time::timeout(Duration::from_secs(5), ws.next()).await {
            Ok(Some(Ok(m))) => m,
            _ => break,
        };

        let text = match msg {
            Message::Text(t) => t.to_string(),
            Message::Binary(b) => String::from_utf8_lossy(&b).into_owned(),
            _ => continue,
        };

        if let Some(h) = parse_message(&text) {
            if h.is_final {
                final_text = h.text;
                break;
            } else {
                interims.push(h.text);
            }
        }
    }

    let _ = ws.close(None).await;
    Ok((final_text, interims))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_message_extracts_words_array() {
        let msg = r#"{
            "words": [
                {"text": "调用", "is_final": true},
                {"text": "这个", "is_final": true},
                {"text": "API", "is_final": true}
            ]
        }"#;
        let h = parse_message(msg).expect("should parse");
        assert_eq!(h.text, "调用 这个 API");
        assert!(h.is_final);
    }

    #[test]
    fn parse_message_marks_non_final() {
        let msg = r#"{
            "words": [
                {"text": "调用", "is_final": true},
                {"text": "这个", "is_final": false}
            ]
        }"#;
        let h = parse_message(msg).expect("should parse");
        assert_eq!(h.text, "调用 这个");
        assert!(!h.is_final);
    }

    #[test]
    fn parse_message_ignores_error_frames() {
        let msg = r#"{"error_code": 401, "error_message": "Invalid API key"}"#;
        assert!(parse_message(msg).is_none());
    }

    #[test]
    fn config_payload_has_required_fields() {
        let json = make_config_payload("test-key-123");
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["api_key"], "test-key-123");
        assert_eq!(v["sample_rate"], 16000);
        assert_eq!(v["num_channels"], 1);
        assert_eq!(v["audio_format"], "pcm_s16le");
        assert_eq!(v["include_nonfinal"], true);
    }
}
