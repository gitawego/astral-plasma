//! Integration tests for the Sherpa-ONNX (SenseVoice-Small) speech adapter.

use astral_plasma::domain::ports::SpeechToTextPort;
use astral_plasma::domain::voice::{
    CaptureTarget, VoiceEvent, VoiceSessionConfig, VoiceSettings, SENSEVOICE_SMALL_ID,
};
use astral_plasma::infrastructure::sherpa_stt_adapter::{
    SherpaOnnxAdapter, SHERPA_BIN_ENV, SHERPA_ENGINE_ID, SHERPA_MODEL_DIR_ENV,
};
use astral_plasma::infrastructure::whisper_stt_adapter::{
    CancelHandle, CAPTURE_BIN_ENV, VAD_BIN_ENV,
};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn write_script(path: &Path, content: &str) {
    std::fs::write(path, content).expect("write script");
    let mut perms = std::fs::metadata(path).expect("meta").permissions();
    perms.set_mode(0o755);
    std::fs::set_permissions(path, perms).expect("chmod +x");
}

struct SherpaFixture {
    _dir: tempfile::TempDir,
    models: PathBuf,
    capture: PathBuf,
    vad: PathBuf,
    engine: PathBuf,
    arg_log: PathBuf,
}

impl SherpaFixture {
    fn new() -> Self {
        let dir = tempfile::tempdir().expect("tempdir");
        let models = dir.path().join("models");
        std::fs::create_dir_all(&models).expect("models dir");

        // Create fake SenseVoice model files
        let model_dir = models.join(SENSEVOICE_SMALL_ID);
        std::fs::create_dir_all(&model_dir).expect("sensevoice model dir");
        std::fs::write(model_dir.join("model.int8.onnx"), b"fake-model-weights").expect("write model");
        std::fs::write(model_dir.join("tokens.txt"), b"fake-tokens").expect("write tokens");

        let arg_log = dir.path().join("engine-args.log");

        // Capture stub: writes 1.2s tone + silence
        let capture = dir.path().join("stub-capture.sh");
        write_script(
            &capture,
            r#"#!/usr/bin/env bash
python3 - <<'PY'
import sys, math, struct
rate = 16000
out = bytearray()
def emit(seconds, amplitude):
    n = int(rate * seconds)
    for i in range(n):
        t = i / rate
        v = int(amplitude * 32767 * math.sin(2 * math.pi * 220 * t))
        out.extend(struct.pack('<h', v))
emit(1.2, 0.35)   # tone / speech
emit(2.0, 0.0)    # trailing silence
sys.stdout.buffer.write(bytes(out))
sys.stdout.buffer.flush()
PY
"#,
        );

        // VAD stub: confirms speech segment in synthetic audio
        let vad = dir.path().join("stub-vad.sh");
        write_script(
            &vad,
            r#"#!/usr/bin/env bash
cat <<'EOF'
Detected 1 speech segments:
Speech segment 0: start = 0.10, end = 1.00
EOF
"#,
        );

        // Engine stub: simulates sherpa-onnx-offline
        let engine = dir.path().join("stub-sherpa.sh");
        let arg_log_str = arg_log.to_str().unwrap();
        let engine_script = format!(
            r#"#!/usr/bin/env bash
echo "$*" >> "{}"
cat <<'EOF'
[I] Initialized SenseVoice model
{{"lang": "<|zh|>", "emotion": "<|NEUTRAL|>", "event": "<|Speech|>", "text": "你好，世界！", "timestamps": [0.1, 0.5]}}
EOF
"#,
            arg_log_str
        );
        write_script(&engine, &engine_script);

        Self {
            _dir: dir,
            models,
            capture,
            vad,
            engine,
            arg_log,
        }
    }
}

#[test]
fn sherpa_adapter_executes_session_with_clean_capture_and_args() {
    let _lock = ENV_LOCK.lock().unwrap();
    let fix = SherpaFixture::new();

    std::env::set_var(CAPTURE_BIN_ENV, fix.capture.to_str().unwrap());
    std::env::set_var(VAD_BIN_ENV, fix.vad.to_str().unwrap());
    std::env::set_var(SHERPA_BIN_ENV, fix.engine.to_str().unwrap());
    std::env::set_var(SHERPA_MODEL_DIR_ENV, fix.models.to_str().unwrap());

    let adapter = SherpaOnnxAdapter::new();
    let cfg = VoiceSessionConfig {
        capture: CaptureTarget::Source,
        echo_cancel: false,
        noise_suppress: false,
        model: SENSEVOICE_SMALL_ID.to_string(),
        language: "zh".to_string(),
        language_override: String::new(),
        silence_hangover_ms: 1200,
        max_utterance_ms: 30_000,
        auto_finalize: true,
        frame_len: 320,
        sample_rate: 16_000,
    };

    let mut events = Vec::new();
    let transcript = adapter
        .run_session_cancellable(&cfg, &CancelHandle::new(), &mut |e| events.push(e))
        .expect("run sherpa session");

    std::env::remove_var(CAPTURE_BIN_ENV);
    std::env::remove_var(VAD_BIN_ENV);
    std::env::remove_var(SHERPA_BIN_ENV);
    std::env::remove_var(SHERPA_MODEL_DIR_ENV);

    assert_eq!(transcript.text, "你好，世界！");
    assert_eq!(transcript.language, "zh");
    assert_eq!(transcript.engine, SHERPA_ENGINE_ID);
    assert_eq!(transcript.model, SENSEVOICE_SMALL_ID);
    assert!(transcript.speech_detected);

    // Verify events sequence
    assert!(events.iter().any(|e| matches!(e, VoiceEvent::StateChanged { state: astral_plasma::domain::voice::VoiceState::Recording })));
    assert!(events.iter().any(|e| matches!(e, VoiceEvent::StateChanged { state: astral_plasma::domain::voice::VoiceState::Finalizing })));
    assert!(events.iter().any(|e| matches!(e, VoiceEvent::Final(_))));

    // Verify CLI arguments received by stub-sherpa.sh
    let logged_args = std::fs::read_to_string(&fix.arg_log).expect("read arg log");
    assert!(logged_args.contains("--sense-voice-model="), "must pass sense-voice-model");
    assert!(logged_args.contains("--tokens="), "must pass tokens");
    assert!(logged_args.contains("--sense-voice-language=zh"), "must pass language");
    assert!(logged_args.contains("--use-itn=true"), "must enable ITN");
    assert!(logged_args.contains(".wav"), "must pass WAV file");
}

#[test]
fn sherpa_adapter_handles_silence_honestly_without_hallucinating() {
    let _lock = ENV_LOCK.lock().unwrap();
    let fix = SherpaFixture::new();

    // VAD stub that reports 0 speech segments (pure silence)
    let vad_silent = fix._dir.path().join("stub-vad-silent.sh");
    write_script(&vad_silent, "#!/usr/bin/env bash\necho 'Detected 0 speech segments:'\n");

    std::env::set_var(CAPTURE_BIN_ENV, fix.capture.to_str().unwrap());
    std::env::set_var(VAD_BIN_ENV, vad_silent.to_str().unwrap());
    std::env::set_var(SHERPA_BIN_ENV, fix.engine.to_str().unwrap());
    std::env::set_var(SHERPA_MODEL_DIR_ENV, fix.models.to_str().unwrap());

    let adapter = SherpaOnnxAdapter::new();
    let cfg = VoiceSessionConfig {
        capture: CaptureTarget::Source,
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
    let transcript = adapter
        .run_session_cancellable(&cfg, &CancelHandle::new(), &mut |e| events.push(e))
        .expect("run sherpa session");

    std::env::remove_var(CAPTURE_BIN_ENV);
    std::env::remove_var(VAD_BIN_ENV);
    std::env::remove_var(SHERPA_BIN_ENV);
    std::env::remove_var(SHERPA_MODEL_DIR_ENV);

    assert_eq!(transcript.text, "");
    assert!(!transcript.speech_detected);
}

#[test]
fn voice_service_catalogs_and_status_are_engine_aware() {
    let _lock = ENV_LOCK.lock().unwrap();
    let fix = SherpaFixture::new();
    std::env::set_var(SHERPA_BIN_ENV, fix.engine.to_str().unwrap());
    std::env::set_var(SHERPA_MODEL_DIR_ENV, fix.models.to_str().unwrap());

    let mut settings = VoiceSettings::default();
    settings.engine = SHERPA_ENGINE_ID.to_string();
    settings.model = SENSEVOICE_SMALL_ID.to_string();

    let svc = astral_plasma::application::voice_service::VoiceService::new(
        std::sync::Arc::new(SherpaOnnxAdapter::new()),
        settings,
    );

    let (models, languages) = svc.catalogs();
    assert!(models.iter().any(|m| m.id == SENSEVOICE_SMALL_ID));
    assert!(languages.iter().any(|l| l.code == "zh"));

    let status = svc.status();
    assert_eq!(status.engine, SHERPA_ENGINE_ID);
    assert!(status.engine_available);
    assert!(status.model_present);

    std::env::remove_var(SHERPA_BIN_ENV);
    std::env::remove_var(SHERPA_MODEL_DIR_ENV);
}
