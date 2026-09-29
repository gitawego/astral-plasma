//! Integration tests for `astral-plasma voice serve`.
//!
//! Drives the real binary against a stub `whisper-server` backend (a tiny
//! Python HTTP server answering `/health` + `/inference`), so residency,
//! the socket protocol and idle shutdown are verifiable with no model and no
//! microphone. See `docs/VOICE-INPUT-SPEC.md` §8.

use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};

fn daemon_bin() -> PathBuf {
    let mut dir = std::env::current_exe().expect("test executable path");
    dir.pop();
    if dir.ends_with("deps") {
        dir.pop();
    }
    let candidate = dir.join("astral-plasma");
    assert!(candidate.is_file(), "daemon binary not found at {}", candidate.display());
    candidate
}

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

/// A request through the serve protocol; returns the server's text line.
fn serve_request(sock: &std::path::Path, language: &str, model: &str, wav: &[u8]) -> String {
    let mut stream = UnixStream::connect(sock).expect("connect to voice serve");
    let header = serde_json::json!({"language": language, "model": model, "duration_ms": 100});
    stream.write_all(header.to_string().as_bytes()).expect("header");
    stream.write_all(b"\n").expect("newline");
    stream.write_all(&(wav.len() as u64).to_le_bytes()).expect("len");
    stream.write_all(wav).expect("wav");
    stream.flush().expect("flush");
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).expect("reply");
    line.trim().to_string()
}

#[test]
fn serve_answers_two_requests_from_one_resident_backend() {
    let dir = tempfile::tempdir().expect("tempdir");
    let models = dir.path().join("models");
    std::fs::create_dir_all(&models).expect("models dir");
    std::fs::write(models.join("ggml-tiny.bin"), b"stub-model-weights").expect("model");

    // Stub backend: answers /health, counts /inference hits, returns canned text.
    let hits = dir.path().join("inference-hits");
    let backend = dir.path().join("stub-whisper-server.sh");
    write_script(
        &backend,
        &format!(
            r#"#!/usr/bin/env bash
port=""
prev=""
for a in "$@"; do
  [ "$prev" = "--port" ] && port="$a"
  [ "$prev" = "-m" ] && echo "model=$a" >> "{hits}"
  prev="$a"
done
HITS="{hits}" PORT="$port" exec python3 - <<'PY'
import http.server, os
hits = os.environ["HITS"]
port = int(os.environ["PORT"])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'{{"status":"ok"}}')
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); self.rfile.read(n)
        with open(hits, 'a') as f: f.write('hit lang=' + str(self.headers.get('X-Lang', '')) + '\n')
        body = b'{{"text":" served transcript "}}'
        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
PY
"#,
            hits = hits.display(),
        ),
    );

    let sock = dir.path().join("voice.sock");
    let mut serve = Command::new(daemon_bin())
        .arg("voice")
        .arg("serve")
        .arg(&sock)
        .arg("30")
        .env("ASTRAL_VOICE_WHISPER_SERVER_BIN", &backend)
        .env("ASTRAL_VOICE_MODEL_DIR", &models)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn voice serve");

    // Wait for the socket to appear (backend boot happens on first request).
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(15);
    while !sock.exists() {
        if std::time::Instant::now() > deadline {
            let _ = serve.kill();
            panic!("voice serve did not bind its socket");
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }

    let wav = {
        let mut w = b"RIFF....WAVE".to_vec();
        w.extend_from_slice(&[0u8; 320]);
        w
    };
    assert_eq!(serve_request(&sock, "en", "ggml-tiny", &wav), "served transcript");
    assert_eq!(serve_request(&sock, "fr", "ggml-tiny", &wav), "served transcript");

    // One backend for both languages: the model was loaded once, not per request.
    let log = std::fs::read_to_string(&hits).unwrap_or_default();
    assert_eq!(log.lines().filter(|l| l.starts_with("model=")).count(), 1,
        "the backend must start once per model, not per request: {log}");
    assert_eq!(log.lines().filter(|l| *l == "hit lang=").count(), 2,
        "both requests must reach the same backend: {log}");

    // Idle shutdown was configured at 30 s; kill here rather than waiting.
    serve.kill().expect("kill serve");
    let out = serve.wait_with_output().expect("wait");
    assert!(
        String::from_utf8_lossy(&out.stderr).contains("listening on"),
        "serve must announce its socket"
    );
}

#[test]
fn serve_exits_on_idle_timeout() {
    let dir = tempfile::tempdir().expect("tempdir");
    let models = dir.path().join("models");
    std::fs::create_dir_all(&models).expect("models dir");
    let sock = dir.path().join("idle.sock");
    let mut serve = Command::new(daemon_bin())
        .arg("voice")
        .arg("serve")
        .arg(&sock)
        .arg("2")
        .env("ASTRAL_VOICE_MODEL_DIR", &models)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn voice serve");
    let out = serve.wait_with_output().expect("wait");
    assert!(out.status.success(), "idle exit must be clean");
    assert!(
        String::from_utf8_lossy(&out.stderr).contains("idle timeout"),
        "serve must report why it exited"
    );
    assert!(!sock.exists(), "the socket must be removed on exit");
}

#[test]
fn serve_rejects_a_missing_model_honestly() {
    // No model file: the request fails but the server stays up for the next one.
    let dir = tempfile::tempdir().expect("tempdir");
    let models = dir.path().join("models");
    std::fs::create_dir_all(&models).expect("models dir");
    let sock = dir.path().join("missing.sock");
    let mut serve = Command::new(daemon_bin())
        .arg("voice")
        .arg("serve")
        .arg(&sock)
        .arg("30")
        .env("ASTRAL_VOICE_MODEL_DIR", &models)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn voice serve");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(15);
    while !sock.exists() {
        if std::time::Instant::now() > deadline {
            let _ = serve.kill();
            panic!("no socket");
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    // A missing model yields EOF without text (client falls back to CLI).
    let mut stream = UnixStream::connect(&sock).expect("connect");
    let header = serde_json::json!({"language": "en", "model": "ggml-tiny", "duration_ms": 1});
    stream.write_all(header.to_string().as_bytes()).unwrap();
    stream.write_all(b"\n").unwrap();
    stream.write_all(&8u64.to_le_bytes()).unwrap();
    stream.write_all(b"12345678").unwrap();
    stream.flush().unwrap();
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).unwrap();
    assert!(buf.is_empty(), "a missing model must produce no text, not invented text");
    serve.kill().expect("kill");
    let _ = serve.wait();
}

#[test]
fn serve_answers_concurrent_requests_without_crossing_streams() {
    // Two sessions at once share the one resident backend; per-request staging
    // must keep their audio apart and each reply must match its request.
    let dir = tempfile::tempdir().expect("tempdir");
    let models = dir.path().join("models");
    std::fs::create_dir_all(&models).expect("models dir");
    std::fs::write(models.join("ggml-tiny.bin"), b"stub-model-weights").expect("model");

    let backend = dir.path().join("stub-whisper-server.sh");
    write_script(
        &backend,
        r#"#!/usr/bin/env bash
port=""
prev=""
for a in "$@"; do
  [ "$prev" = "--port" ] && port="$a"
  prev="$a"
done
PORT="$port" exec python3 - <<'PY'
import http.server, os
port = int(os.environ["PORT"])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"status":"ok"}')
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); self.rfile.read(n)
        body = b'{"text":" concurrent ok "}'
        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
PY
"#,
    );

    let sock = dir.path().join("conc.sock");
    let mut serve = Command::new(daemon_bin())
        .arg("voice")
        .arg("serve")
        .arg(&sock)
        .arg("30")
        .env("ASTRAL_VOICE_WHISPER_SERVER_BIN", &backend)
        .env("ASTRAL_VOICE_MODEL_DIR", &models)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn voice serve");
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(15);
    while !sock.exists() {
        if std::time::Instant::now() > deadline {
            let _ = serve.kill();
            panic!("voice serve did not bind its socket");
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }

    let wav = {
        let mut w = b"RIFF....WAVE".to_vec();
        w.extend_from_slice(&[0u8; 160]);
        w
    };
    let handles: Vec<_> = (0..4)
        .map(|_| {
            let sock = sock.clone();
            let wav = wav.clone();
            std::thread::spawn(move || serve_request(&sock, "en", "ggml-tiny", &wav))
        })
        .collect();
    for h in handles {
        assert_eq!(h.join().expect("client thread"), "concurrent ok");
    }
    serve.kill().expect("kill");
    let _ = serve.wait();
}
