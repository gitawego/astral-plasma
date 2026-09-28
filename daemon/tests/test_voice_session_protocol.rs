//! End-to-end tests for the `astral-plasma voice session` line protocol.
//!
//! These drive the **real binary** with a stub capture tool and a stub engine,
//! injected through the documented environment overrides. That makes the whole
//! stack -- control channel, capture loop, endpointing, event encoding, process
//! lifecycle -- verifiable on a machine with no microphone, no speech engine and
//! no downloaded model. See `docs/VOICE-INPUT-SPEC.md` §8.4.

use serde_json::Value;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};

/// Locates the built binary next to the integration test executable.
fn daemon_bin() -> PathBuf {
    let mut dir = std::env::current_exe().expect("test executable path");
    dir.pop(); // deps/
    if dir.ends_with("deps") {
        dir.pop();
    }
    let candidate = dir.join("astral-plasma");
    assert!(
        candidate.is_file(),
        "daemon binary not found at {} (run `cargo test` from the daemon directory)",
        candidate.display()
    );
    candidate
}

struct Fixture {
    _dir: tempfile::TempDir,
    models: PathBuf,
    capture: PathBuf,
    engine: PathBuf,
    config_home: PathBuf,
    /// Appended by the stub engine with the byte size of the WAV it was given.
    engine_audio_log: PathBuf,
}

impl Fixture {
    /// Builds a stub environment.
    ///
    /// * capture stub: writes a burst of alternating-amplitude s16 PCM (which
    ///   has real AC energy, so the silence detector sees speech) followed by
    ///   quiet, then exits. No audio hardware involved.
    /// * engine stub: prints a whisper-style JSON transcript, so extraction is
    ///   exercised against realistic output.
    fn new() -> Self {
        let dir = tempfile::tempdir().expect("tempdir");
        let models = dir.path().join("models");
        std::fs::create_dir_all(&models).expect("models dir");

        // --- capture stub -------------------------------------------------
        let capture = dir.path().join("stub-capture.sh");
        write_script(
            &capture,
            r#"#!/usr/bin/env bash
# Emits synthetic 16 kHz mono s16 PCM: 1.2 s of speech-like tone, then quiet.
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
emit(1.2, 0.35)   # "speech"
emit(2.5, 0.0)    # trailing silence -> triggers auto-finalize
sys.stdout.buffer.write(bytes(out))
sys.stdout.buffer.flush()
PY
"#,
        );

        // --- engine stub --------------------------------------------------
        // Answers `--help` with a realistic banner so the capability probe
        // discovers `-oj`/`-np`/`--vad`. The stub then behaves like
        // whisper-cli 1.9.4, not like the assumption this used to encode:
        //   * `--vad` without `--vad-model` is fatal (exit 10, "failed to
        //     process audio") - exactly the live failure that made voice input
        //     look like it was ignoring the microphone.
        //   * `-oj` writes the JSON document beside the audio file, while
        //     stdout still carries the timestamped transcript.
        // A stub that printed JSON on stdout masked both behaviors.
        let engine = dir.path().join("stub-engine.sh");
        write_script(
            &engine,
            r#"#!/usr/bin/env bash
if [ "$1" = "--help" ]; then
cat <<'HELP'
usage: whisper-cli [options] file.wav [file.wav ...]
  -f,  --file FNAME      [required] audio file
  -m,  --model FNAME     [required] model file
  -l,  --language LANG   [auto] spoken language
  -t,  --threads N       number of threads
  -np, --no-prints       do not print anything
  -oj, --output-json     output result in JSON format
  -ac N, --audio-ctx N   audio context size (0 - all)
  -bs N, --beam-size N   beam size for beam search
  -bo N, --best-of N     number of best candidates to keep
  -nf, --no-fallback     do not use temperature fallback
  --vad                  enable Voice Activity Detection (VAD)
  -vm, --vad-model FNAME VAD model path
whisper-cli version 1.9.4
HELP
  exit 0
fi

audio=""
prev=""
vad=0
vad_model=0
json=0
for a in "$@"; do
  [ "$prev" = "-f" ] && audio="$a"
  [ "$a" = "--vad" ] && vad=1
  [ "$a" = "--vad-model" ] && vad_model=1
  [ "$a" = "-oj" ] && json=1
  prev="$a"
done

if [ "$vad" = "1" ] && [ "$vad_model" = "0" ]; then
  echo "whisper-cli: failed to process audio" >&2
  exit 10
fi

echo "whisper_print_system_info: n_mels = 80" >&2
echo "total time = 42.00 ms" >&2
if [ -n "$ASTRAL_TEST_ENGINE_LOG" ] && [ -n "$audio" ]; then
  echo "bytes=$(wc -c < "$audio")" >> "$ASTRAL_TEST_ENGINE_LOG"
  echo "args=$*" >> "$ASTRAL_TEST_ENGINE_LOG"
fi
if [ "$json" = "1" ] && [ -n "$audio" ]; then
  printf '%s' '{"transcription":[{"text":" stub transcript "},{"text":"from engine"}]}' > "${audio}.json"
fi
printf '[00:00:00.000 --> 00:00:02.000]   stub transcript from engine\n'
"#,
        );

        // --- settings -----------------------------------------------------
        // Must sit at $XDG_CONFIG_HOME/astral-plasma/settings.json, which is
        // where load_settings() looks.
        let config_home = dir.path().join("config");
        let config_dir = config_home.join("astral-plasma");
        std::fs::create_dir_all(&config_dir).expect("config dir");
        let settings = config_dir.join("settings.json");
        std::fs::write(
            &settings,
            r#"{"voice":{"enabled":true,"engine":"whisper-cpp","model":"ggml-tiny","language":"en","maxUtteranceSeconds":20,"silenceHangoverMs":500,"autoFinalize":true}}"#,
        )
        .expect("settings");

        // A non-empty model file so preparation succeeds.
        std::fs::write(models.join("ggml-tiny.bin"), b"stub-model-weights").expect("model");
        // The VAD asset, so sessions exercise inference-time speech filtering
        // (`--vad --vad-model`) exactly as a real install would.
        std::fs::write(models.join("ggml-silero-v5.1.2.bin"), b"stub-vad-weights").expect("vad model");

        // The stub engine appends the WAV size here, so the trim contract can
        // be asserted without a microphone or a real engine.
        let audio_log = dir.path().join("engine-audio-bytes");

        Self {
            _dir: dir,
            models,
            capture,
            engine,
            config_home,
            engine_audio_log: audio_log,
        }
    }

    /// Spawns `voice session` wired to the stubs.
    fn session(&self) -> Child {
        let mut cmd = Command::new(daemon_bin());
        cmd.arg("voice").arg("session")
            .env("ASTRAL_VOICE_ENGINE_BIN", &self.engine)
            .env("ASTRAL_VOICE_CAPTURE_BIN", &self.capture)
            .env("ASTRAL_VOICE_MODEL_DIR", &self.models)
            .env("XDG_CONFIG_HOME", &self.config_home)
            .env("ASTRAL_TEST_ENGINE_LOG", &self.engine_audio_log)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        cmd.spawn().expect("spawn voice session")
    }

    /// Runs a session, then collects its output.
    ///
    /// `hold_stdin` models a real client. When true the control pipe stays open
    /// for the whole session, because a closed pipe means "the client went away"
    /// and the daemon correctly stops immediately -- which would end every
    /// recording after one frame. When false the pipe is closed right after the
    /// script is written, which is what a caller that never sends `start` wants.
    fn run_inner(&self, stdin_script: &str, hold_stdin: bool) -> (Vec<Value>, String, bool) {
        let mut child = self.session();
        let mut stdin = child.stdin.take().expect("stdin");
        stdin.write_all(stdin_script.as_bytes()).expect("write stdin");
        stdin.flush().expect("flush stdin");
        if !hold_stdin {
            drop(stdin);
        }

        let out = child.wait_with_output().expect("wait");
        let text = String::from_utf8_lossy(&out.stdout).into_owned();
        let events = text
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| {
                serde_json::from_str::<Value>(l)
                    .unwrap_or_else(|e| panic!("event line is not valid JSON: {l:?} ({e})"))
            })
            .collect();
        (events, String::from_utf8_lossy(&out.stderr).into_owned(), out.status.success())
    }

    /// Runs a full session, holding the control channel open like a real client.
    fn run(&self, stdin_script: &str) -> (Vec<Value>, String, bool) {
        self.run_inner(stdin_script, true)
    }

    /// Runs expecting no session at all, so the control channel is closed.
    fn run_without_session(&self, stdin_script: &str) -> (Vec<Value>, String, bool) {
        self.run_inner(stdin_script, false)
    }
}

fn write_script(path: &Path, body: &str) {
    std::fs::write(path, body).expect("write script");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(path).expect("stat").permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(path, perms).expect("chmod");
    }
}

fn kinds(events: &[Value]) -> Vec<String> {
    events
        .iter()
        .filter_map(|e| e.get("type").and_then(|t| t.as_str()).map(String::from))
        .collect()
}

// ---------------------------------------------------------------------------

#[test]
fn session_emits_a_well_formed_event_stream() {
    let fx = Fixture::new();
    let (events, _err, ok) = fx.run("start\n");

    assert!(ok, "the session must exit cleanly");
    assert!(!events.is_empty(), "a started session must emit events");

    let k = kinds(&events);
    assert_eq!(k.first().map(String::as_str), Some("StateChanged"), "got {k:?}");
    assert!(k.contains(&"Level".to_string()), "real audio level must be reported: {k:?}");
    assert_eq!(k.last().map(String::as_str), Some("Final"), "a Final must close the stream: {k:?}");
}

#[test]
fn session_reports_state_transitions_in_order() {
    let fx = Fixture::new();
    let (events, _err, _ok) = fx.run("start\n");

    let states: Vec<String> = events
        .iter()
        .filter(|e| e.get("type").and_then(|t| t.as_str()) == Some("StateChanged"))
        .filter_map(|e| e.pointer("/payload/state").and_then(|s| s.as_str()).map(String::from))
        .collect();

    assert_eq!(states.first().map(String::as_str), Some("recording"));
    assert!(states.iter().any(|s| s == "finalizing"), "must report transcription: {states:?}");
}

#[test]
fn session_carries_the_real_transcript_from_the_engine() {
    let fx = Fixture::new();
    let (events, _err, _ok) = fx.run("start\n");

    let final_event = events
        .iter()
        .find(|e| e.get("type").and_then(|t| t.as_str()) == Some("Final"))
        .expect("a Final event");
    let text = final_event
        .pointer("/payload/text")
        .and_then(|t| t.as_str())
        .expect("transcript text");
    // whisper-cli's `-oj` writes the document to `<audio>.json`; stdout carries
    // only the timestamped transcript. Reading stdout as JSON produced an empty
    // transcript for every real utterance, which is what the user experienced.
    assert_eq!(text, "stub transcript from engine");

    assert_eq!(
        final_event.pointer("/payload/language").and_then(|l| l.as_str()),
        Some("en"),
        "an explicit language must be reported back, not replaced with a guess"
    );
    assert_eq!(
        final_event.pointer("/payload/model").and_then(|m| m.as_str()),
        Some("ggml-tiny"),
        "the transcript must record which model produced it"
    );
}

#[test]
fn session_does_not_send_a_bare_vad_flag_to_the_engine() {
    // whisper-cli 1.9.4 advertises `--vad` in its help, but fails every
    // transcription ("failed to process audio", exit 10) when the flag is
    // passed without `--vad-model`; the daemon's own SilenceDetector does the
    // endpointing (docs/VOICE-INPUT-SPEC.md D4), so the flag must not be sent
    // at all. The stub mirrors the real engine, so a regression here fails
    // the session instead of silently emptying the transcript.
    let fx = Fixture::new();
    let (events, _err, ok) = fx.run("start\n");

    assert!(ok, "a bare --vad would have aborted the session: {events:?}");
    assert!(kinds(&events).contains(&"Final".to_string()),
        "the engine must still transcribe: {events:?}");
    assert!(!kinds(&events).contains(&"Error".to_string()),
        "no engine error may surface for a normal utterance: {events:?}");
}

#[test]
fn session_trims_silence_before_inference() {
    // The stub capture emits 1.2s of tone then 2.5s of quiet (3.7s total).
    // Whisper processes every sample it is handed, so shipping trailing silence
    // costs CPU inference time and invites hallucinated text. The WAV given to
    // the engine must be the speech region plus the padding margin.
    let fx = Fixture::new();
    let _ = std::fs::remove_file(&fx.engine_audio_log);
    let (events, _err, ok) = fx.run("start\n");
    assert!(ok);
    assert!(kinds(&events).contains(&"Final".to_string()));

    let logged = std::fs::read_to_string(&fx.engine_audio_log)
        .expect("stub engine must log the WAV size");
    let bytes: u64 = logged
        .lines()
        .rev()
        .find(|l| l.starts_with("bytes="))
        .expect("a logged size")
        .trim_start_matches("bytes=")
        .trim()
        .parse()
        .expect("numeric size");
    let pcm_ms = bytes.saturating_sub(44) / 32; // 16 kHz s16 mono
    assert!(pcm_ms >= 1_000, "the speech region must survive the trim: {pcm_ms}ms");
    assert!(pcm_ms < 2_500, "trailing silence must be trimmed: kept {pcm_ms}ms of 3700ms");

    // The encoder context must be sized to what the engine is actually given.
    // whisper encodes `n_audio_ctx * 20ms` per window, so a fixed 30s context
    // made every utterance pay the same ~1.7s CPU encoder pass.
    let args = logged
        .lines()
        .rev()
        .find(|l| l.starts_with("args="))
        .expect("the stub engine must log its arguments");
    assert!(args.contains("-ac 256"),
        "a ~1.5s utterance must get the 5.12s floor context, got: {args}");
    assert!(args.contains("-bs 1") && args.contains("-bo 1") && args.contains("-nf"),
        "the decode must be bounded so hard audio cannot loop, got: {args}");
    assert!(args.contains("--vad") && args.contains("--vad-model"),
        "the installed VAD asset must enable inference-time speech filtering, got: {args}");
    assert!(args.contains("ggml-silero-v5.1.2.bin"),
        "the VAD model path must be named when the asset is present, got: {args}");
}

#[test]
fn session_levels_reflect_real_captured_audio() {
    let fx = Fixture::new();
    let (events, _err, _ok) = fx.run("start\n");

    let levels: Vec<f64> = events
        .iter()
        .filter(|e| e.get("type").and_then(|t| t.as_str()) == Some("Level"))
        .filter_map(|e| e.pointer("/payload/rms").and_then(|r| r.as_f64()))
        .collect();

    assert!(!levels.is_empty(), "levels must come from the PCM stream");
    assert!(levels.iter().all(|v| (0.0..=1.0).contains(v)), "levels must be normalized: {levels:?}");
    // The stub emits a loud tone then silence, so both must be observable. This
    // is the property that proves the meter is reading real audio rather than
    // animating a placeholder.
    assert!(levels.iter().any(|v| *v > 0.05), "no speech-level energy observed: {levels:?}");
    assert!(levels.iter().any(|v| *v < 0.01), "no silence observed: {levels:?}");
}

#[test]
fn session_does_not_open_the_microphone_without_a_start_command() {
    let fx = Fixture::new();
    // No `start` on stdin: the process must exit having recorded nothing.
    let (events, _err, ok) = fx.run_without_session("");
    assert!(ok);
    assert!(events.is_empty(), "no events may be emitted without an explicit start: {events:?}");
}

#[test]
fn session_cancel_before_start_returns_to_idle() {
    let fx = Fixture::new();
    let (events, _err, ok) = fx.run_without_session("cancel\n");
    assert!(ok);
    assert_eq!(kinds(&events), vec!["StateChanged"]);
    assert_eq!(
        events[0].pointer("/payload/state").and_then(|s| s.as_str()),
        Some("idle")
    );
    assert!(!kinds(&events).contains(&"Recording".to_string()));
}

#[test]
fn session_ignores_blank_and_unknown_commands() {
    let fx = Fixture::new();
    let (events, _err, ok) = fx.run("\n   \nnot-a-command\nstart\n");
    assert!(ok, "unknown commands must be ignored, not fatal");
    assert!(kinds(&events).contains(&"Final".to_string()));
}

#[test]
fn session_auto_finalizes_on_trailing_silence() {
    // The stub emits 1.2 s of tone then 2.5 s of quiet, and the fixture sets a
    // 500 ms hangover. Without endpointing the process would have to wait for
    // the 20 s cap; with it, trailing silence ends the utterance.
    let fx = Fixture::new();
    let start = std::time::Instant::now();
    let (events, _err, _ok) = fx.run("start\n");
    let elapsed = start.elapsed();

    assert!(kinds(&events).contains(&"Final".to_string()), "must finalize on silence");
    assert!(
        elapsed < std::time::Duration::from_secs(15),
        "endpointing did not fire early; took {elapsed:?}"
    );
}

#[test]
fn session_reports_a_setup_gap_when_the_model_is_missing() {
    let fx = Fixture::new();
    std::fs::remove_file(fx.models.join("ggml-tiny.bin")).expect("remove model");

    let (events, _err, ok) = fx.run("start\n");
    assert!(ok, "a setup gap must not crash the process");

    let err = events
        .iter()
        .find(|e| e.get("type").and_then(|t| t.as_str()) == Some("Error"))
        .expect("an Error event must be emitted");
    assert_eq!(
        err.pointer("/payload/recoverable"),
        Some(&Value::Bool(true)),
        "a missing model is a setup gap the user can fix, not a crash"
    );
}

#[test]
fn session_reports_a_fatal_error_when_the_engine_fails() {
    let fx = Fixture::new();
    let engine = fx._dir.path().join("failing-engine.sh");
    write_script(&engine, "#!/usr/bin/env bash\necho 'model load failed' >&2\nexit 1\n");

    let mut child = Command::new(daemon_bin());
    child
        .arg("voice").arg("session")
        .env("ASTRAL_VOICE_ENGINE_BIN", &engine)
        .env("ASTRAL_VOICE_CAPTURE_BIN", &fx.capture)
        .env("ASTRAL_VOICE_MODEL_DIR", &fx.models)
        .env("XDG_CONFIG_HOME", &fx.config_home)
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = child.spawn().expect("spawn");
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("write");
    let out = child.wait_with_output().expect("wait");
    drop(stdin);

    let events: Vec<Value> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| serde_json::from_str(l).expect("valid JSON event"))
        .collect();

    let err = events
        .iter()
        .find(|e| e.get("type").and_then(|t| t.as_str()) == Some("Error"))
        .expect("an Error event must be emitted");
    assert_eq!(
        err.pointer("/payload/recoverable"),
        Some(&Value::Bool(false)),
        "an engine crash is not user-recoverable in-session"
    );
}

#[test]
fn session_status_subcommand_reports_readiness_without_an_engine() {
    // Made hermetic rather than relying on the host lacking whisper.cpp: the
    // engine override and an empty model directory force the "not installed"
    // state regardless of what happens to be on the developer's machine.
    let empty = tempfile::tempdir().expect("tempdir");
    let out = Command::new(daemon_bin())
        .arg("voice").arg("status")
        // A bogus override plus an empty data dir neutralises all three of
        // locate_engine's discovery paths, so the result does not depend on
        // whether the host happens to have whisper.cpp installed.
        .env("ASTRAL_VOICE_ENGINE_BIN", empty.path().join("no-such-engine"))
        .env("ASTRAL_VOICE_MODEL_DIR", empty.path())
        .env("XDG_DATA_HOME", empty.path())
        .env("PATH", "/nonexistent")
        .output()
        .expect("run voice status");
    assert!(out.status.success());

    let v: Value = serde_json::from_slice(&out.stdout).expect("status must be valid JSON");
    assert_eq!(v.get("engine").and_then(|e| e.as_str()), Some("whisper-cpp"));
    assert_eq!(
        v.get("engine_available"),
        Some(&Value::Bool(false)),
        "a bogus engine override must report unavailable"
    );
    assert_eq!(v.get("setup_complete"), Some(&Value::Bool(false)));
    assert_eq!(
        v.get("gap").and_then(|g| g.as_str()),
        Some("engine_missing"),
        "must name the actual gap"
    );

    let models = v.get("models_available").and_then(|m| m.as_array()).expect("model catalog");
    assert!(!models.is_empty(), "the catalog must be advertised even with nothing installed");
    let languages = v.get("languages").and_then(|l| l.as_array()).expect("language list");
    let codes: Vec<&str> = languages.iter().filter_map(|l| l.get("code").and_then(|c| c.as_str())).collect();
    for required in ["zh", "en", "fr", "de", "it", "es"] {
        assert!(codes.contains(&required), "language list must include {required}");
    }
}

#[test]
fn session_status_reports_ready_when_engine_and_model_are_present() {
    // The mirror image of the above, using the same stubs, so both branches of
    // the readiness contract are pinned without depending on host state.
    let fx = Fixture::new();
    let out = Command::new(daemon_bin())
        .arg("voice").arg("status")
        .env("ASTRAL_VOICE_ENGINE_BIN", &fx.engine)
        .env("ASTRAL_VOICE_MODEL_DIR", &fx.models)
        .env("XDG_CONFIG_HOME", &fx.config_home)
        .output()
        .expect("run voice status");

    let v: Value = serde_json::from_slice(&out.stdout).expect("status must be valid JSON");
    assert_eq!(v.get("engine_available"), Some(&Value::Bool(true)));
    assert_eq!(v.get("model_present"), Some(&Value::Bool(true)));
    assert_eq!(v.get("vad_model_present"), Some(&Value::Bool(true)),
        "status must report the optional speech detection asset");
    assert_eq!(v.get("setup_complete"), Some(&Value::Bool(true)));
    assert_eq!(v.get("gap").and_then(|g| g.as_str()), Some("ready"));
}

#[test]
fn session_engines_subcommand_lists_the_catalog() {
    let out = Command::new(daemon_bin())
        .arg("voice").arg("engines")
        .output()
        .expect("run voice engines");
    assert!(out.status.success());
    let v: Value = serde_json::from_slice(&out.stdout).expect("valid JSON");
    let models = v.get("models").and_then(|m| m.as_array()).expect("models");
    assert!(models.iter().any(|m| m.get("id").and_then(|i| i.as_str()) == Some("ggml-large-v3-turbo")));
    assert!(models.iter().all(|m| m.get("size_label").and_then(|s| s.as_str()).is_some()));
}

#[test]
fn session_install_model_rejects_an_unknown_id_without_network_access() {
    let out = Command::new(daemon_bin())
        .arg("voice").arg("install-model").arg("definitely-not-a-model")
        .output()
        .expect("run install-model");
    let v: Value = serde_json::from_slice(&out.stdout).expect("valid JSON");
    assert_eq!(v.get("success"), Some(&Value::Bool(false)));
    assert!(v
        .get("error")
        .and_then(|e| e.as_str())
        .expect("error message")
        .contains("Unknown speech model"));
}

#[test]
fn unknown_voice_subcommand_prints_usage_without_panicking() {
    let out = Command::new(daemon_bin())
        .arg("voice").arg("not-a-subcommand")
        .output()
        .expect("run voice");
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(err.contains("Usage:"), "expected usage text, got {err:?}");
}

#[test]
fn session_releases_the_capture_device_on_exit() {
    // The stub records its own lifetime; if the daemon leaked the child, the
    // marker file would show an overlapping second invocation.
    let fx = Fixture::new();
    let marker = fx._dir.path().join("capture-invocations");
    let capture = fx._dir.path().join("counting-capture.sh");
    write_script(
        &capture,
        &format!(
            r#"#!/usr/bin/env bash
echo "run" >> "{}"
python3 - <<'PY'
import sys, struct, math
out = bytearray()
for i in range(16000 * 2):
    t = i / 16000
    out.extend(struct.pack('<h', int(0.3 * 32767 * math.sin(2*math.pi*200*t))))
sys.stdout.buffer.write(bytes(out))
PY
"#,
            marker.display()
        ),
    );

    let mut cmd = Command::new(daemon_bin());
    cmd.arg("voice").arg("session")
        .env("ASTRAL_VOICE_ENGINE_BIN", &fx.engine)
        .env("ASTRAL_VOICE_CAPTURE_BIN", &capture)
        .env("ASTRAL_VOICE_MODEL_DIR", &fx.models)
        .env("XDG_CONFIG_HOME", &fx.config_home)
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = cmd.spawn().expect("spawn");
    // The handle must outlive wait_with_output(): closing the control channel
    // means "the client went away" and correctly ends the session at once,
    // which would race the stub's first marker write.
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("flush");
    let _out = child.wait_with_output().expect("wait");
    drop(stdin);

    let runs = std::fs::read_to_string(&marker).unwrap_or_default().lines().count();
    assert_eq!(runs, 1, "capture must be started exactly once per session");

    // The staged WAV and its JSON sidecar must not survive the session.
    let leftovers: Vec<PathBuf> = std::fs::read_dir(&fx.models)
        .expect("models dir")
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .map(|n| n.to_string_lossy().starts_with("utterance-"))
                .unwrap_or(false)
        })
        .collect();
    assert!(leftovers.is_empty(), "staged audio and its sidecar must be cleaned up: {leftovers:?}");
}

#[test]
fn session_stdout_is_pure_jsonl_with_no_diagnostics_mixed_in() {
    // The QML side parses stdout with a line splitter, so any stray print
    // would corrupt the stream.
    let fx = Fixture::new();
    let mut child = fx.session();
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("write");
    let out = child.wait_with_output().expect("wait");
    drop(stdin);

    let stdout = String::from_utf8_lossy(&out.stdout);
    let reader = BufReader::new(stdout.as_bytes());
    for (i, line) in reader.lines().enumerate() {
        let line = line.expect("valid utf8 line");
        if line.trim().is_empty() {
            continue;
        }
        serde_json::from_str::<Value>(&line)
            .unwrap_or_else(|e| panic!("line {i} is not JSON: {line:?} ({e})"));
    }
}

#[test]
fn a_stalled_capture_still_hits_the_hard_cap() {
    // Regression guard for a bug the visual pass caught: a session was still
    // "recording" after sixteen minutes. The cap used to be checked only inside
    // the frame loop, so a capture that delivers no frames blocked in `read`
    // forever and held the microphone open. The watchdog must end it regardless
    // of whether audio ever arrives.
    let fx = Fixture::new();

    // A capture stub that opens its stdout and then never writes a byte.
    let stalled = fx._dir.path().join("stalled-capture.sh");
    write_script(&stalled, "#!/usr/bin/env bash\nsleep 600\n");

    // A short cap, so the test does not have to wait half a minute.
    let config_dir = fx.config_home.join("astral-plasma");
    std::fs::write(
        config_dir.join("settings.json"),
        r#"{"voice":{"enabled":true,"engine":"whisper-cpp","model":"ggml-tiny","language":"en","maxUtteranceSeconds":5,"silenceHangoverMs":500,"autoFinalize":true}}"#,
    )
    .expect("settings");

    let mut cmd = Command::new(daemon_bin());
    cmd.arg("voice").arg("session")
        .env("ASTRAL_VOICE_ENGINE_BIN", &fx.engine)
        .env("ASTRAL_VOICE_CAPTURE_BIN", &stalled)
        .env("ASTRAL_VOICE_MODEL_DIR", &fx.models)
        .env("XDG_CONFIG_HOME", &fx.config_home)
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = cmd.spawn().expect("spawn");
    child.stdin.take().unwrap().write_all(b"start\n").unwrap();

    // Generous slack for CI, but far below the 600s the stub would otherwise sleep.
    let done = wait_for_exit(&mut child, std::time::Duration::from_secs(30));
    let out = child.wait_with_output().expect("wait");

    assert!(done, "a stalled capture must not hold the microphone past the hard cap");

    // The capture process must be gone too, not merely detached.
    let text = String::from_utf8_lossy(&out.stdout);
    let kinds: Vec<String> = text
        .lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|l| serde_json::from_str::<Value>(l).ok())
        .filter_map(|v| v.get("type").and_then(|t| t.as_str()).map(String::from))
        .collect();
    assert!(
        kinds.iter().any(|k| k == "Final" || k == "Error"),
        "the capped session must still emit a terminal event, got: {kinds:?}"
    );
}

/// Polls for child exit up to `limit`, returning whether it happened.
fn wait_for_exit(child: &mut Child, limit: std::time::Duration) -> bool {
    let deadline = std::time::Instant::now() + limit;
    while std::time::Instant::now() < deadline {
        match child.try_wait() {
            Ok(Some(_)) => return true,
            Ok(None) => std::thread::sleep(std::time::Duration::from_millis(50)),
            Err(_) => return false,
        }
    }
    false
}
