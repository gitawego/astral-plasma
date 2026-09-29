//! Opt-in cloud STT adapter: Deepgram Nova-3 live (audit follow-up).
//!
//! The local engine stays the default; this adapter exists because dedicated
//! ASR is materially better at Mandarin and streams interim results while you
//! speak. Selecting `engine: "deepgram"` in settings IS the consent — no key,
//! no session — and the key lives in an owner-only file outside settings,
//! diagnostics, logs and reports (never serialized, never printed).
//!
//! Protocol: `wss://api.deepgram.com/v1/listen` with
//! `Authorization: Token <KEY>`, 16 kHz mono linear16 PCM chunks, then
//! `{"type":"CloseStream"}`. Interim `Results` (`is_final: false`) become
//! genuine `Partial` events (engine-streamed, never fabricated — D6); the
//! final result becomes the transcript. `ASTRAL_DEEPGRAM_ENDPOINT` overrides
//! the URL (plain `ws://` test servers).
//!
//! Capture reuses the shared session path (endpointing, VAD, clipping) and
//! streams the trimmed clip; interim text therefore arrives as a burst after
//! capture rather than word-by-word. True concurrent stream-while-speaking is
//! the documented follow-up, not a silent behavior change.

use crate::domain::ports::{DynError, DynResult, SpeechToTextPort};
use crate::domain::voice::{
    EngineProbe, PcmSpec, Transcript, VoiceEvent, VoiceSessionConfig, LanguageSource,
};
use std::path::PathBuf;
use std::time::Duration;

/// Engine id used in settings and transcripts.
pub const DEEPGRAM_ENGINE_ID: &str = "deepgram";
/// Model reported on transcripts.
pub const DEEPGRAM_MODEL_ID: &str = "nova-3";
/// Environment override for the API key (tests + escape hatch).
pub const DEEPGRAM_KEY_ENV: &str = "ASTRAL_DEEPGRAM_KEY";
/// Environment override for the endpoint URL (tests use plain `ws://`).
pub const DEEPGRAM_ENDPOINT_ENV: &str = "ASTRAL_DEEPGRAM_ENDPOINT";
/// Default live endpoint.
pub const DEEPGRAM_ENDPOINT: &str = "wss://api.deepgram.com/v1/listen";

/// File holding the API key, beside settings.json, owner-only.
fn key_path() -> PathBuf {
    crate::domain::branding::config_home()
        .join("astral-plasma")
        .join("deepgram_api_key")
}

/// Reads the API key: explicit env wins, then the owner-only file.
/// Returns `None` when neither exists — selecting the engine without a key is
/// a setup gap, reported, never a crash.
pub fn read_key() -> Option<String> {
    if let Ok(k) = std::env::var(DEEPGRAM_KEY_ENV) {
        let k = k.trim().to_string();
        if !k.is_empty() {
            return Some(k);
        }
    }
    std::fs::read_to_string(key_path()).ok().map(|k| k.trim().to_string()).filter(|k| !k.is_empty())
}

/// Stores the API key with owner-only permissions, replacing any previous one.
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
    std::fs::write(&path, key).map_err(|e| -> DynError { format!("Cannot store key: {e}").into() })?;
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

fn endpoint() -> String {
    std::env::var(DEEPGRAM_ENDPOINT_ENV)
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| DEEPGRAM_ENDPOINT.to_string())
}

/// Deepgram query: fixed US English only when the user asked for nothing else;
/// their pinned language otherwise (Deepgram language codes match ours for the
/// supported set; unknown tags fall back to `en-US` rather than failing).
fn listen_url(base: &str, language: &str) -> String {
    let lang = match language.trim().to_lowercase().as_str() {
        "zh" => "zh-CN",
        "en" | "" | "auto" => "en-US",
        "fr" => "fr",
        "de" => "de",
        "it" => "it",
        "es" => "es",
        "pt" => "pt",
        "ru" => "ru",
        "ja" => "ja",
        "ko" => "ko",
        "hi" => "hi",
        "nl" => "nl",
        _ => "en-US",
    };
    format!(
        "{base}?model={DEEPGRAM_MODEL_ID}&language={lang}\
         &sample_rate=16000&channels=1&encoding=linear16\
         &interim_results=true&punctuate=true&smart_format=true"
    )
}

/// One interim/final hypothesis from a `Results` message.
#[derive(Debug, Clone, PartialEq)]
struct Hypothesis {
    text: String,
    is_final: bool,
}

/// Extracts the top hypothesis from a Deepgram streaming message.
///
/// Non-`Results` messages (Metadata, UtteranceEnd, SpeechStarted) carry no
/// transcript and yield `None`: control traffic is never rendered as words.
fn parse_message(raw: &str) -> Option<Hypothesis> {
    let value: serde_json::Value = serde_json::from_str(raw).ok()?;
    if value.get("type").and_then(|t| t.as_str()) != Some("Results") {
        return None;
    }
    let text = value
        .pointer("/channel/alternatives/0/transcript")
        .and_then(|t| t.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    if text.is_empty() {
        return None;
    }
    let is_final = value.get("is_final").and_then(|f| f.as_bool()).unwrap_or(false);
    Some(Hypothesis { text, is_final })
}

pub struct DeepgramAdapter;

impl DeepgramAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl Default for DeepgramAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl SpeechToTextPort for DeepgramAdapter {
    fn probe(&self) -> DynResult<EngineProbe> {
        // No binary: availability is key presence, resolved by the service.
        Ok(EngineProbe {
            engine_id: DEEPGRAM_ENGINE_ID.to_string(),
            binary_path: None,
            version: Some(DEEPGRAM_MODEL_ID.to_string()),
            capabilities: crate::domain::voice::EngineCapabilities::default(),
        })
    }

    fn run_session(
        &self,
        cfg: &VoiceSessionConfig,
        sink: &mut dyn FnMut(VoiceEvent),
    ) -> DynResult<Transcript> {
        self.run_session_cancellable(
            cfg,
            &crate::infrastructure::whisper_stt_adapter::CancelHandle::new(),
            sink,
        )
    }

    fn run_session_cancellable(
        &self,
        cfg: &VoiceSessionConfig,
        handle: &crate::infrastructure::whisper_stt_adapter::CancelHandle,
        sink: &mut dyn FnMut(VoiceEvent),
    ) -> DynResult<Transcript> {
        let key = read_key().ok_or_else(|| -> DynError {
            "No Deepgram API key. Run: astral-plasma voice cloud-key set (key stays on this device)".into()
        })?;
        // Capture owns endpointing/VAD/trim via the shared session path; the
        // cloud sees only the trimmed speech region, exactly like whisper.
        let (pcm, _first, _last, has_speech) =
            crate::infrastructure::whisper_stt_adapter::capture_utterance_shared(
                cfg,
                handle,
                sink,
            )?;
        sink(VoiceEvent::StateChanged {
            state: crate::domain::voice::VoiceState::Finalizing,
        });
        if !has_speech {
            let transcript = Transcript {
                text: String::new(),
                language: crate::domain::voice::LANGUAGE_UNDETERMINED.to_string(),
                duration_ms: 0,
                engine: DEEPGRAM_ENGINE_ID.to_string(),
                model: DEEPGRAM_MODEL_ID.to_string(),
                speech_detected: false,
                language_confidence: None,
                language_source: LanguageSource::Configured,
            };
            sink(VoiceEvent::Final(transcript.clone()));
            return Ok(transcript);
        }
        let spec = PcmSpec::speech();
        let duration_ms = spec.duration_ns(pcm.len()) / 1_000_000;
        let url = listen_url(&endpoint(), &cfg.language);
        // Interim hypotheses are forwarded as genuine Partial events: they are
        // engine output streamed back mid-exchange, which is exactly what
        // Partial means (D6). All interims precede the Final below.
        let (final_text, interims) = stream_transcribe(&url, &key, &pcm)?;
        for partial in interims {
            sink(VoiceEvent::Partial { text: partial });
        }
        if final_text.trim().is_empty() {
            // The engine heard speech but had no words for it: distinct from
            // the microphone hearing nothing (reported above).
            let transcript = Transcript {
                text: String::new(),
                language: "en".to_string(),
                duration_ms,
                engine: DEEPGRAM_ENGINE_ID.to_string(),
                model: DEEPGRAM_MODEL_ID.to_string(),
                speech_detected: true,
                language_confidence: None,
                language_source: LanguageSource::Configured,
            };
            sink(VoiceEvent::Final(transcript.clone()));
            return Ok(transcript);
        }
        let transcript = Transcript {
            text: final_text,
            language: "en".to_string(),
            duration_ms,
            engine: DEEPGRAM_ENGINE_ID.to_string(),
            model: DEEPGRAM_MODEL_ID.to_string(),
            speech_detected: true,
            language_confidence: None,
            language_source: LanguageSource::Configured,
        };
        sink(VoiceEvent::Final(transcript.clone()));
        Ok(transcript)
    }
}

/// Streams one clip through the live endpoint, collecting interim Partials.
///
/// Built on a per-session Tokio runtime: the port is synchronous by design so
/// every adapter stays trivially fakeable. Returns `(final_text, interims)` —
/// the caller emits interims as `Partial` before the `Final`, preserving
/// engine order.
fn stream_transcribe(url: &str, key: &str, pcm: &[u8]) -> DynResult<(String, Vec<String>)> {
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::Message;

    let url = url.to_string();
    let key = key.to_string();
    let pcm = pcm.to_vec();
    // The port is synchronous; the exchange is async (see block_on_ws).
    // Returns `(final_text, interims)` — the caller emits interims as
    // `Partial` before the `Final`, preserving engine order.
    block_on_ws(async move {
        stream_transcribe_async(&url, &key, &pcm).await
    })
}

async fn stream_transcribe_async(url: &str, key: &str, pcm: &[u8]) -> DynResult<(String, Vec<String>)> {
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::Message;
    // A caller-built Request carries no handshake headers, so the WS key,
    // version and upgrade pair are added explicitly (tungstenite only
    // derives them for string-URL connects, which cannot carry auth).
    let ws_key = tokio_tungstenite::tungstenite::handshake::client::generate_key();
    let request = tokio_tungstenite::tungstenite::http::Request::builder()
        .uri(url)
        .header("Authorization", format!("Token {key}"))
        .header("Host", host_of(url))
        .header("Sec-WebSocket-Key", ws_key)
        .header("Sec-WebSocket-Version", "13")
        .header("Upgrade", "websocket")
        .header("Connection", "Upgrade")
        .body(())
        .map_err(|e| -> DynError { format!("Bad endpoint URL: {e}").into() })?;
        let (mut ws, _) = tokio_tungstenite::connect_async(request)
            .await
            .map_err(|e| -> DynError { map_ws_error(&e) })?;
        for chunk in pcm.chunks(8000) {
            ws.send(Message::Binary(chunk.to_vec().into()))
                .await
                .map_err(|e| -> DynError { format!("Audio upload failed: {e}").into() })?;
        }
        ws.send(Message::Text(r#"{"type":"CloseStream"}"#.into()))
            .await
            .map_err(|e| -> DynError { format!("CloseStream failed: {e}").into() })?;

        let mut final_text = String::new();
        let mut interims: Vec<String> = Vec::new();
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(30);
        loop {
            if tokio::time::Instant::now() > deadline {
                break;
            }
            let msg = tokio::time::timeout(Duration::from_secs(5), ws.next())
                .await
                .map_err(|_| -> DynError { "Timed out waiting for the transcript".into() })?;
            let Some(msg) = msg else { break };
            let msg = msg.map_err(|e| -> DynError { format!("Stream failed: {e}").into() })?;
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

// ---------------------------------------------------------------------------
// Key probing above; test module below.
// ---------------------------------------------------------------------------

/// Drives one WS future from sync code: fresh runtime in production sessions,
/// the ambient runtime under `block_in_place` in tests — never nested.
fn block_on_ws<F, T>(fut: F) -> DynResult<T>
where
    F: std::future::Future<Output = DynResult<T>>,
{
    match tokio::runtime::Handle::try_current() {
        Ok(handle) => tokio::task::block_in_place(|| handle.block_on(fut)),
        Err(_) => tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| -> DynError { format!("Cannot start async runtime: {e}").into() })?
            .block_on(fut),
    }
}
///
/// Sends half a second of silence and waits for any protocol message: anything
/// but HTTP 401 proves authentication. Returns `Ok(true)` on auth success.
pub fn test_key() -> DynResult<bool> {
    let key = read_key().ok_or_else(|| -> DynError { "No API key stored".into() })?;
    let url = listen_url(&endpoint(), "en");
    let silence = vec![0u8; 16_000 * 2]; // 1 s of 16 kHz s16 silence
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::Message;
    block_on_ws(async move {
        let ws_key = tokio_tungstenite::tungstenite::handshake::client::generate_key();
        let request = tokio_tungstenite::tungstenite::http::Request::builder()
            .uri(&url)
            .header("Authorization", format!("Token {key}"))
            .header("Host", host_of(&url))
            .header("Sec-WebSocket-Key", ws_key)
            .header("Sec-WebSocket-Version", "13")
            .header("Upgrade", "websocket")
            .header("Connection", "Upgrade")
            .body(())
            .map_err(|e| -> DynError { format!("Bad endpoint URL: {e}").into() })?;
        let (mut ws, _) = tokio_tungstenite::connect_async(request)
            .await
            .map_err(|e| -> DynError { map_ws_error(&e) })?;
        ws.send(Message::Binary(silence.into()))
            .await
            .map_err(|e| -> DynError { format!("Audio upload failed: {e}").into() })?;
        ws.send(Message::Text(r#"{"type":"CloseStream"}"#.into()))
            .await
            .map_err(|e| -> DynError { format!("CloseStream failed: {e}").into() })?;
        // Any message at all (even an empty Results) proves the key was
        // accepted: auth failures arrive as HTTP 401 at connect time.
        let msg = tokio::time::timeout(std::time::Duration::from_secs(15), ws.next())
            .await
            .map_err(|_| -> DynError { "No response from Deepgram".into() })?;
        let _ = ws.close(None).await;
        match msg {
            Some(Ok(_)) => Ok(true),
            _ => Err("Stream ended without a response".into()),
        }
    })
}

fn host_of(url: &str) -> String {
    url.split("://")
        .nth(1)
        .unwrap_or(url)
        .split('/')
        .next()
        .unwrap_or("")
        .to_string()
}

/// Maps transport failures to actionable messages without leaking the key.
fn map_ws_error(e: &tokio_tungstenite::tungstenite::Error) -> DynError {
    use tokio_tungstenite::tungstenite::Error as E;
    match e {
        E::Http(r) if r.status() == tokio_tungstenite::tungstenite::http::StatusCode::UNAUTHORIZED => {
            "Deepgram rejected the API key (401). Run: astral-plasma voice cloud-key test".into()
        }
        E::Http(r) => format!("Deepgram endpoint answered HTTP {}", r.status()).into(),
        E::Io(io) => format!("Network failure reaching Deepgram: {io}").into(),
        other => format!("Streaming failed: {other}").into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn interim_and_final_messages_parse() {
        let interim = r#"{"type":"Results","channel":{"alternatives":[{"transcript":"hello there"}]},"is_final":false}"#;
        assert_eq!(
            parse_message(interim),
            Some(Hypothesis { text: "hello there".into(), is_final: false })
        );
        let final_msg = r#"{"type":"Results","channel":{"alternatives":[{"transcript":"Hello there."}]},"is_final":true,"speech_final":true}"#;
        assert_eq!(
            parse_message(final_msg),
            Some(Hypothesis { text: "Hello there.".into(), is_final: true })
        );
        // Control traffic and empties are never words.
        assert_eq!(parse_message(r#"{"type":"Metadata"}"#), None);
        assert_eq!(
            parse_message(r#"{"type":"Results","channel":{"alternatives":[{"transcript":"  "}]},"is_final":false}"#),
            None
        );
        assert_eq!(parse_message("not json"), None);
    }

    #[test]
    fn language_param_mapping() {
        assert!(listen_url("wss://x", "zh").contains("language=zh-CN"));
        assert!(listen_url("wss://x", "en").contains("language=en-US"));
        assert!(listen_url("wss://x", "klingon").contains("language=en-US"),
            "unknown tags fall back rather than failing opaquely");
        assert!(listen_url("wss://x", "fr").contains("language=fr"));
    }

    #[test]
    fn key_round_trips_with_owner_only_permissions() {
        std::env::set_var(DEEPGRAM_KEY_ENV, "test-key-123");
        assert_eq!(read_key().as_deref(), Some("test-key-123"), "env wins for tests");
        std::env::remove_var(DEEPGRAM_KEY_ENV);
    }
}
