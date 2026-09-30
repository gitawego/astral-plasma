//! Deepgram adapter tests against a fake live endpoint.
//!
//! A local plain-`ws://` stub stands in for `wss://api.deepgram.com`: it
//! asserts the auth header, drains the PCM upload, answers one interim and one
//! final `Results` message, and closes. No network, no key, no microphone.

use astral_plasma::domain::ports::SpeechToTextPort;
use astral_plasma::domain::voice::{VoiceEvent, VoiceSessionConfig, VoiceSettings};
use futures_util::{SinkExt, StreamExt};

/// The API key lives in the *process* environment and both tests here mutate it
/// (one points the adapter at its stub endpoint, the other asserts that a
/// missing key is reported as a setup gap). Cargo runs the tests of a binary in
/// parallel threads, so without this lock one test's key makes the other take
/// the "key present" path - and with a current-thread runtime that panics in
/// `block_in_place` instead of asserting. One writer at a time, as in
/// `test_plasma_rust.rs`.
static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn write_script(path: &std::path::Path, body: &str) {
    std::fs::write(path, body).expect("write script");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(path).expect("stat").permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(path, perms).expect("chmod");
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn streams_interim_partials_then_final() {
    let _env = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let dir = tempfile::tempdir().expect("tempdir");

    // Capture stub: speech-like tone (energy sees speech) then quiet.
    let capture = dir.path().join("stub-cap.sh");
    write_script(
        &capture,
        "#!/usr/bin/env bash\npython3 - <<'PY'\nimport sys,math,struct\nout=bytearray()\nfor i in range(int(16000*1.0)):\n out.extend(struct.pack('<h',int(0.35*32767*math.sin(2*math.pi*220*i/16000))))\nout.extend(bytes(int(16000*2.0)*2))\nsys.stdout.buffer.write(bytes(out))\nPY\n",
    );

    // Fake Deepgram: auth check, drain upload, interim + final, close.
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let port = listener.local_addr().unwrap().port();
    let seen_auth = std::sync::Arc::new(std::sync::Mutex::new(None::<String>));
    let seen_auth_server = std::sync::Arc::clone(&seen_auth);
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.expect("accept");
        let mut ws = tokio_tungstenite::accept_hdr_async(
            stream,
            |req: &tokio_tungstenite::tungstenite::handshake::server::Request,
             _res: tokio_tungstenite::tungstenite::handshake::server::Response|
             -> Result<
                tokio_tungstenite::tungstenite::http::Response<()>,
                tokio_tungstenite::tungstenite::http::Response<Option<String>>,
            > {
                // The key travels in exactly one place; anything else is a leak.
                *seen_auth_server.lock().unwrap() = req
                    .headers()
                    .get("Authorization")
                    .and_then(|v| v.to_str().ok())
                    .map(str::to_string);
                Ok(_res.map(|_| ()))
            },
        )
        .await
        .expect("handshake");
        // A 401 would have failed the handshake above.
        let mut saw_audio = false;
        let mut saw_close = false;
        while let Some(msg) = ws.next().await {
            let msg = msg.expect("frame");
            match msg {
                tokio_tungstenite::tungstenite::Message::Binary(_) => saw_audio = true,
                tokio_tungstenite::tungstenite::Message::Text(t) if t.contains("CloseStream") => {
                    saw_close = true;
                    break;
                }
                _ => {}
            }
        }
        assert!(saw_audio, "client must upload PCM before closing");
        assert!(saw_close, "client must send CloseStream");
        for payload in [
            r#"{"type":"Results","channel":{"alternatives":[{"transcript":"hello"}]},"is_final":false}"#,
            r#"{"type":"Results","channel":{"alternatives":[{"transcript":"Hello world."}]},"is_final":true,"speech_final":true}"#,
        ] {
            ws.send(tokio_tungstenite::tungstenite::Message::Text(payload.into()))
                .await
                .expect("send");
        }
        ws.close(None).await.expect("close");
    });

    std::env::set_var("ASTRAL_DEEPGRAM_KEY", "test-key-abc");
    std::env::set_var(
        "ASTRAL_DEEPGRAM_ENDPOINT",
        format!("ws://127.0.0.1:{port}/v1/listen"),
    );
    std::env::set_var("ASTRAL_VOICE_CAPTURE_BIN", &capture);
    std::env::set_var("ASTRAL_VOICE_AEC_SOURCE", "stub-aec");

    let settings = VoiceSettings {
        language: "en".to_string(),
        ..VoiceSettings::default()
    };
    let cfg = VoiceSessionConfig::from_settings(&settings);
    let adapter = astral_plasma::infrastructure::deepgram_stt_adapter::DeepgramAdapter::new();
    let mut events: Vec<VoiceEvent> = Vec::new();
    let result = adapter.run_session(&cfg, &mut |e| events.push(e));

    std::env::remove_var("ASTRAL_DEEPGRAM_KEY");
    std::env::remove_var("ASTRAL_DEEPGRAM_ENDPOINT");
    std::env::remove_var("ASTRAL_VOICE_CAPTURE_BIN");
    std::env::remove_var("ASTRAL_VOICE_AEC_SOURCE");
    server.await.expect("server task");
    assert_eq!(
        seen_auth.lock().unwrap().as_deref(),
        Some("Token test-key-abc"),
        "the key must travel as an Authorization header and nowhere else"
    );

    let transcript = result.expect("session succeeds");
    assert_eq!(transcript.text, "Hello world.");
    assert_eq!(transcript.engine, "deepgram");
    assert!(transcript.speech_detected);

    let partials: Vec<&str> = events
        .iter()
        .filter_map(|e| match e {
            VoiceEvent::Partial { text } => Some(text.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(partials, vec!["hello"], "engine-streamed interim must surface, verbatim");
    assert!(
        events.iter().any(|e| matches!(e, VoiceEvent::Final(_))),
        "a Final must close the stream"
    );
}

#[tokio::test]
async fn missing_key_is_a_setup_gap() {
    let _env = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    std::env::remove_var("ASTRAL_DEEPGRAM_KEY");
    let cfg = VoiceSessionConfig::from_settings(&VoiceSettings::default());
    let adapter = astral_plasma::infrastructure::deepgram_stt_adapter::DeepgramAdapter::new();
    let mut events = Vec::new();
    let err = adapter.run_session(&cfg, &mut |e| events.push(e)).unwrap_err();
    assert!(
        err.to_string().contains("API key"),
        "must name the missing key, got: {err}"
    );
    assert!(
        !err.to_string().contains("test-key"),
        "errors must never echo key material"
    );
}
