//! Resident STT server (audit §4.3).
//!
//! `astral-plasma voice serve [socket] [idle-secs]` holds `whisper-server`
//! with the model resident in RAM and translates the Unix-socket session
//! protocol to its `/inference` endpoint. Repeat utterances skip the ~543 ms
//! model reload entirely: the load happens once per backend lifetime, and an
//! idle timer unloads it after 60 s of silence (no resident cost when unused,
//! per the voice feature's cost-nothing-when-unused goal).
//!
//! No new Rust dependency: the backend is supervised via `curl`, matching the
//! downloader's established pattern. Per-request `language` is passed through,
//! so one backend serves every language — verified live (`fr` decodes French
//! orthography, `auto` detects).
//!
//! Protocol (client: `WhisperCppAdapter::transcribe_via_server`):
//! `<header JSON>\n<u64 LE wav len><wav bytes>` → `<transcript text>\n` + EOF.

use crate::domain::ports::{DynError, DynResult};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

/// Request header from the session client. `language` is the already-resolved
/// single-pass prior (pinned or locale, never an argmax); `model` is the
/// catalog id.
#[derive(Debug, serde::Deserialize)]
struct ServeRequest {
    language: String,
    model: String,
    #[allow(dead_code)]
    duration_ms: u64,
}

/// Supervised `whisper-server` backend, keyed by model path.
struct Backend {
    child: Child,
    port: u16,
    model: PathBuf,
}

/// Environment override for the backend binary (test seam + escape hatch).
pub const WHISPER_SERVER_BIN_ENV: &str = "ASTRAL_VOICE_WHISPER_SERVER_BIN";

/// Resolves the backend binary: explicit override, else `whisper-server`.
fn backend_binary() -> String {
    std::env::var(WHISPER_SERVER_BIN_ENV)
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| "whisper-server".to_string())
}

impl Backend {
    /// Starts (or restarts) the backend for `model`, waiting for `/health`.
    fn ensure(current: &mut Option<Backend>, model: &PathBuf) -> DynResult<u16> {
        if let Some(b) = current {
            if &b.model == model && b.child.try_wait().map(|s| s.is_none()).unwrap_or(false) {
                return Ok(b.port);
            }
            let _ = current.take().map(|mut b| b.child.kill());
            *current = None;
        }
        let port = free_port()?;
        let mut child = Command::new(backend_binary())
            .arg("-m")
            .arg(model)
            .arg("-l")
            .arg("auto")
            .arg("--host")
            .arg("127.0.0.1")
            .arg("--port")
            .arg(port.to_string())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| -> DynError { format!("Cannot start whisper-server: {e}").into() })?;
        if wait_healthy(port, Duration::from_secs(180)) {
            *current = Some(Backend { child, port, model: model.clone() });
            return Ok(port);
        }
        let _ = child.kill();
        Err("whisper-server did not become healthy".into())
    }
}

/// Finds an ephemeral loopback port.
fn free_port() -> DynResult<u16> {
    let listener = std::net::TcpListener::bind("127.0.0.1:0")
        .map_err(|e| -> DynError { format!("Cannot find a free port: {e}").into() })?;
    Ok(listener.local_addr().map(|a| a.port()).unwrap_or(18080))
}

/// Polls `/health` until ready or the timeout elapses.
fn wait_healthy(port: u16, timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if let Ok(out) = Command::new("curl")
            .args(["-sf", &format!("http://127.0.0.1:{port}/health")])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .output()
        {
            if out.status.success() {
                return true;
            }
        }
        std::thread::sleep(Duration::from_millis(500));
    }
    false
}

/// Runs one inference over a staged WAV through the resident backend.
fn infer(port: u16, wav_path: &std::path::Path, language: &str) -> DynResult<String> {
    let out = Command::new("curl")
        .arg("-s")
        .arg("-F")
        .arg(format!("file=@{}", wav_path.display()))
        .arg("-F")
        .arg(format!("language={language}"))
        .arg("-F")
        .arg("response_format=json")
        .arg(format!("http://127.0.0.1:{port}/inference"))
        .stdin(Stdio::null())
        .output()
        .map_err(|e| -> DynError { format!("inference request failed: {e}").into() })?;
    if !out.status.success() {
        return Err("inference request failed".into());
    }
    let body = String::from_utf8_lossy(&out.stdout).into_owned();
    // Verified shape: `{"text":" ..."}`. Anything else surfaces trimmed and
    // raw rather than failing the session over a parse technicality.
    if let Ok(value) = serde_json::from_str::<serde_json::Value>(&body) {
        if let Some(text) = value.get("text").and_then(|t| t.as_str()) {
            return Ok(text.trim().to_string());
        }
    }
    Ok(body.trim().to_string())
}

/// Serves STT over `socket_path` (default `$XDG_RUNTIME_DIR/astral-voice.sock`),
/// exiting after `idle_secs` without a request.
pub fn serve(socket_arg: String, idle_secs: u64) -> DynResult<()> {
    let socket_path = if socket_arg.trim().is_empty() {
        default_socket()
    } else {
        PathBuf::from(socket_arg)
    };
    if let Some(parent) = socket_path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| -> DynError { format!("Cannot create socket dir: {e}").into() })?;
    }
    let _ = std::fs::remove_file(&socket_path);
    let listener = UnixListener::bind(&socket_path)
        .map_err(|e| -> DynError { format!("Cannot bind {}: {e}", socket_path.display()).into() })?;
    listener
        .set_nonblocking(true)
        .map_err(|e| -> DynError { format!("Cannot set nonblocking: {e}").into() })?;
    eprintln!("[voice serve] listening on {}", socket_path.display());

    // Shared across connection threads: one backend per model (model stays
    // resident no matter how many sessions arrive), activity timestamp and an
    // in-flight count so the idle timer never reaps a busy server.
    let backend = std::sync::Arc::new(std::sync::Mutex::new(None::<Backend>));
    let last_activity = std::sync::Arc::new(std::sync::Mutex::new(Instant::now()));
    let in_flight = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let idle = Duration::from_secs(idle_secs.max(1));
    loop {
        match listener.accept() {
            Ok((stream, _)) => {
                *last_activity.lock().unwrap() = Instant::now();
                in_flight.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                let backend = std::sync::Arc::clone(&backend);
                let last_activity = std::sync::Arc::clone(&last_activity);
                let in_flight = std::sync::Arc::clone(&in_flight);
                std::thread::spawn(move || {
                    // Backend access is serialized: concurrent sessions share
                    // the one resident model instead of racing restarts.
                    let mut guard = backend.lock().unwrap();
                    let result = handle(stream, &mut guard);
                    drop(guard);
                    if let Err(e) = result {
                        eprintln!("[voice serve] request failed: {e}");
                    }
                    *last_activity.lock().unwrap() = Instant::now();
                    in_flight.fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
                });
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(50));
                let quiet = last_activity.lock().unwrap().elapsed() >= idle;
                let busy = in_flight.load(std::sync::atomic::Ordering::SeqCst) > 0;
                if quiet && !busy {
                    eprintln!("[voice serve] idle timeout, exiting");
                    break;
                }
            }
            Err(e) => {
                eprintln!("[voice serve] accept failed: {e}");
                break;
            }
        }
    }
    if let Some(mut b) = backend.lock().unwrap().take() {
        let _ = b.child.kill();
        let _ = b.child.wait();
    }
    let _ = std::fs::remove_file(&socket_path);
    Ok(())
}

/// Default socket location: the runtime dir, falling back to the models dir.
pub fn default_socket() -> PathBuf {
    if let Ok(runtime) = std::env::var("XDG_RUNTIME_DIR") {
        if !runtime.trim().is_empty() {
            return PathBuf::from(runtime).join("astral-voice.sock");
        }
    }
    crate::infrastructure::whisper_stt_adapter::models_dir().join("voice-server.sock")
}

fn handle(mut stream: UnixStream, backend: &mut Option<Backend>) -> DynResult<()> {
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut header_line = String::new();
    reader.read_line(&mut header_line)?;
    let req: ServeRequest = serde_json::from_str(header_line.trim())
        .map_err(|e| -> DynError { format!("bad request header: {e}").into() })?;
    let mut len_buf = [0u8; 8];
    reader.read_exact(&mut len_buf)?;
    let len = u64::from_le_bytes(len_buf) as usize;
    if len == 0 || len > 64 * 1024 * 1024 {
        return Err("bad audio length".into());
    }
    let mut wav = vec![0u8; len];
    reader.read_exact(&mut wav)?;
    drop(reader);

    let model_path =
        crate::infrastructure::whisper_stt_adapter::resolve_model_file(&req.model).ok_or_else(
            || -> DynError { format!("Model '{}' is not downloaded", req.model).into() },
        )?;
    let port = Backend::ensure(backend, &model_path)?;
    let dir = crate::infrastructure::whisper_stt_adapter::models_dir();
    // Per-request staging: concurrent sessions must never share a path.
    static STAGE_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let stage_id = STAGE_COUNTER.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    let wav_path = dir.join(format!("serve-{}-{}.wav", std::process::id(), stage_id));
    std::fs::write(&wav_path, &wav)?;
    let result = infer(port, &wav_path, &req.language);
    let _ = std::fs::remove_file(&wav_path);
    let text = result?;
    stream.write_all(text.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_socket_is_absolute() {
        assert!(default_socket().is_absolute());
    }

    #[test]
    fn free_port_is_usable() {
        let port = free_port().unwrap();
        assert!(port > 0);
    }
}
