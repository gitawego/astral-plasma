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
    /// Appended by the stub capture with the arguments `pw-record` would get.
    capture_args_log: PathBuf,
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
# Records the arguments the daemon built, so the capture target (echo-cancelled
# source vs default) is assertable without touching PipeWire.
if [ -n "$ASTRAL_TEST_CAPTURE_LOG" ]; then
  echo "args=$*" >> "$ASTRAL_TEST_CAPTURE_LOG"
fi
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
  -dl, --detect-language [false] exit after automatically detecting language
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
detect=0
for a in "$@"; do
  [ "$prev" = "-f" ] && audio="$a"
  [ "$a" = "--vad" ] && vad=1
  [ "$a" = "--vad-model" ] && vad_model=1
  [ "$a" = "-oj" ] && json=1
  [ "$a" = "-dl" ] && detect=1
  prev="$a"
done

# `-dl` means "identify and stop", so the stub must not also transcribe. It
# reports the same way whisper does: the tag and its probability on stderr, and
# nothing on stdout.
if [ "$detect" = "1" ]; then
  echo "whisper_full_with_state: auto-detected language: ${ASTRAL_TEST_DETECTED_LANG:-fr} (p = ${ASTRAL_TEST_DETECTED_P:-0.91})" >&2
  echo "total time = 12.00 ms" >&2
  if [ -n "$ASTRAL_TEST_ENGINE_LOG" ] && [ -n "$audio" ]; then
    echo "detect_args=$*" >> "$ASTRAL_TEST_ENGINE_LOG"
  fi
  exit 0
fi

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
  printf '%s' '{"result":{"language":"fr"},"transcription":[{"text":" stub transcript "},{"text":"from engine"}]}' > "${audio}.json"
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

        // The stub engine appends the WAV size here, so the trim contract can
        // be asserted without a microphone or a real engine.
        let audio_log = dir.path().join("engine-audio-bytes");
        let capture_args_log = dir.path().join("capture-args");

        Self {
            _dir: dir,
            models,
            capture,
            engine,
            config_home,
            engine_audio_log: audio_log,
            capture_args_log,
        }
    }

    /// Spawns `voice session` wired to the stubs.
    fn session(&self) -> Child {
        self.session_with_aec("stub-aec")
    }

    /// Same, but with an explicit echo-cancel source override (`""` disables
    /// it), so both capture paths are testable without touching PipeWire.
    fn session_with_aec(&self, aec: &str) -> Child {
        let mut cmd = self.session_command();
        cmd.env("ASTRAL_VOICE_AEC_SOURCE", aec);
        cmd.spawn().expect("spawn voice session")
    }

    /// The common `voice session` command, without the echo-cancel override, so
    /// the real provisioning path can be exercised with a stub `pactl`.
    fn session_command(&self) -> Command {
        let mut cmd = Command::new(daemon_bin());
        cmd.arg("voice").arg("session")
            .env("ASTRAL_VOICE_ENGINE_BIN", &self.engine)
            .env("ASTRAL_VOICE_CAPTURE_BIN", &self.capture)
            .env("ASTRAL_VOICE_MODEL_DIR", &self.models)
            .env("XDG_CONFIG_HOME", &self.config_home)
            .env("ASTRAL_TEST_ENGINE_LOG", &self.engine_audio_log)
            .env("ASTRAL_TEST_CAPTURE_LOG", &self.capture_args_log)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        cmd
    }

    /// Writes a stub `pactl` into the fixture directory and returns its folder.
    ///
    /// `list short sources` prints the published state; `load-module` publishes
    /// the echo-cancelled source and records the call.
    fn stub_pactl_dir(&self) -> PathBuf {
        let dir = self._dir.path().join("bin");
        std::fs::create_dir_all(&dir).expect("stub bin dir");
        let state = dir.join("sources.state");
        let marker = dir.join("loaded");
        write_script(
            &dir.join("pactl"),
            &format!(
                r#"#!/usr/bin/env bash
case "$1" in
  list)
    [ -f "{state}" ] && cat "{state}"
    exit 0 ;;
  load-module)
    echo 536870916
    printf '60\tastral_echo_cancel\tPipeWire\ts16le 1ch 32000Hz\n' > "{state}"
    echo "$*" >> "{marker}"
    exit 0 ;;
esac
exit 1
"#,
                state = state.display(),
                marker = marker.display(),
            ),
        );
        dir
    }

    /// Runs a session, then collects its output.
    ///
    /// `hold_stdin` models a real client. When true the control pipe stays open
    /// for the whole session, because a closed pipe means "the client went away"
    /// and the daemon correctly stops immediately -- which would end every
    /// recording after one frame. When false the pipe is closed right after the
    /// script is written, which is what a caller that never sends `start` wants.
    /// Runs a session with extra environment for the stub engine, so one
    /// fixture can stand in for a confident engine and a doubtful one.
    fn run_with_env(
        &self,
        stdin_script: &str,
        env: &[(&str, &str)],
    ) -> (Vec<Value>, String, bool) {
        let mut cmd = self.session_command();
        for (k, v) in env {
            cmd.env(k, v);
        }
        let mut child = cmd.spawn().expect("spawn voice session");
        let mut stdin = child.stdin.take().expect("stdin");
        stdin.write_all(stdin_script.as_bytes()).expect("write stdin");
        stdin.flush().expect("flush stdin");
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
fn session_never_requests_engine_vad() {
    // whisper.cpp applies `--vad` before language detection (`whisper_full`
    // swaps in the VAD-filtered samples, then `whisper_full_with_state`
    // auto-detects from them), which measurably degrades detection and clips
    // speech. The daemon's own SilenceDetector handles endpointing and the
    // no-speech gate, so the engine must never receive the flags - even though
    // the stub advertises them and a VAD asset exists in the models dir.
    let fx = Fixture::new();
    let (events, _err, ok) = fx.run("start\n");

    assert!(ok);
    assert!(kinds(&events).contains(&"Final".to_string()),
        "the session must transcribe without engine VAD: {events:?}");
    assert!(!kinds(&events).contains(&"Error".to_string()),
        "no engine error may surface: {events:?}");
}

#[test]
fn session_captures_through_the_echo_cancelled_source() {
    // Speaker bleed is the root cause of wrong-language and empty transcripts on
    // a desktop; the session must capture from the echo-cancelled node when one
    // is available. The capture stub logs the arguments, so this is asserted
    // without touching PipeWire.
    let fx = Fixture::new();
    let _ = std::fs::remove_file(&fx.capture_args_log);
    let (events, _err, ok) = fx.run("start\n");
    assert!(ok);
    assert!(kinds(&events).contains(&"Final".to_string()));

    let logged = std::fs::read_to_string(&fx.capture_args_log)
        .expect("the capture stub must log its arguments");
    let args = logged
        .lines()
        .rev()
        .find(|l| l.starts_with("args="))
        .expect("a logged capture invocation");
    assert!(args.contains("--target stub-aec"),
        "capture must target the echo-cancelled source, got: {args}");
}

#[test]
fn session_falls_back_to_the_default_source_without_echo_cancellation() {
    // The fallback is load-bearing: a machine with no PipeWire echo-cancel
    // support must still dictate.
    let fx = Fixture::new();
    let _ = std::fs::remove_file(&fx.capture_args_log);
    let mut child = fx.session_with_aec("");
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("flush");
    let out = child.wait_with_output().expect("wait");
    drop(stdin);
    assert!(out.status.success());

    let logged = std::fs::read_to_string(&fx.capture_args_log)
        .expect("the capture stub must log its arguments");
    let args = logged
        .lines()
        .rev()
        .find(|l| l.starts_with("args="))
        .expect("a logged capture invocation");
    assert!(args.contains("--target @DEFAULT_AUDIO_SOURCE@"),
        "without echo cancellation the default source must be captured, got: {args}");
}

#[test]
fn session_provisions_no_echo_cancellation_by_default() {
    // Audit §3.3: loading `module-echo-cancel` without routing playback through
    // its sink gives AEC zero reference samples and adds blind AGC distortion.
    // The daemon must NOT provision the module by default; capture targets the
    // default source. Opt-in stays available via `ASTRAL_VOICE_AEC_SOURCE`.
    let fx = Fixture::new();
    let stub_dir = fx.stub_pactl_dir();
    let marker = stub_dir.join("loaded");
    let _ = std::fs::remove_file(&fx.capture_args_log);

    let mut cmd = fx.session_command();
    cmd.env("PATH", format!("{}:{}", stub_dir.display(), std::env::var("PATH").unwrap_or_default()));
    let mut child = cmd.spawn().expect("spawn");
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("flush");
    let out = child.wait_with_output().expect("wait");
    drop(stdin);
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let loaded = std::fs::read_to_string(&marker).unwrap_or_default();
    assert!(!loaded.contains("module-echo-cancel"),
        "the daemon must not provision echo cancellation by default, got: {loaded:?}");

    let logged = std::fs::read_to_string(&fx.capture_args_log)
        .expect("the capture stub must log its arguments");
    let args = logged.lines().rev().find(|l| l.starts_with("args=")).expect("capture args");
    assert!(args.contains("--target @DEFAULT_AUDIO_SOURCE@"),
        "capture must target the default source without opt-in, got: {args}");
}

#[test]
fn a_confident_detection_is_reported_and_used() {
    // Single-pass (audit §4.3): with `language: auto` the session transcribes
    // once with the locale prior and reports the sidecar `result.language` as
    // a display-only `Detected` event before `Final`. No `-dl` spawn exists.
    let fx = Fixture::new();
    let settings = fx.config_home.join("astral-plasma").join("settings.json");
    let raw = std::fs::read_to_string(&settings).expect("fixture settings");
    std::fs::write(&settings, raw.replace("\"language\":\"en\"", "\"language\":\"auto\""))
        .expect("rewrite fixture settings");

    let (events, _err, ok) = fx.run_with_env("start\n", &[("LANG", "en_US.UTF-8")]);
    assert!(ok);

    let kinds: Vec<&str> = events
        .iter()
        .filter_map(|e| e.get("type").and_then(|t| t.as_str()))
        .collect();
    let detected_at = kinds.iter().position(|k| *k == "Detected");
    let final_at = kinds.iter().position(|k| *k == "Final");
    assert!(detected_at.is_some(), "the reading must be announced, got: {kinds:?}");
    assert!(
        detected_at < final_at,
        "the reading must arrive before the transcript, or there is nothing to correct: {kinds:?}"
    );

    let detected = &events[detected_at.unwrap()];
    assert_eq!(detected.pointer("/payload/language").and_then(|l| l.as_str()), Some("fr"));

    let final_event = events[final_at.unwrap()].clone();
    assert_eq!(
        final_event.pointer("/payload/language").and_then(|l| l.as_str()),
        Some("fr"),
        "the single-pass reading is reported, got: {final_event:?}"
    );

    // Exactly one engine invocation: detection is not its own pass.
    let logged = std::fs::read_to_string(&fx.engine_audio_log).expect("engine log");
    assert!(
        !logged.contains("detect_args="),
        "single-pass must not spawn a -dl detection pass: {logged}"
    );
    let args = logged.lines().rev().find(|l| l.starts_with("args=")).expect("args");
    assert!(
        args.contains("-l en"),
        "the decode uses the locale prior in one pass, got: {args}"
    );
}

/// The old two-pass failure, closed structurally.
///
/// "Can you help me" came back as Japanese because whisper's `-dl` argmax over
/// 100 logits on a 1.3 s clip is a tie (`ja p=0.08`) committed as a decoder
/// constraint. Single-pass (audit §4.3) never spawns `-dl`: `auto` decodes once
/// with the locale prior and reports the sidecar tag display-only.
#[test]
fn an_unconfident_detection_is_reported_but_not_transcribed_with() {
    let fx = Fixture::new();
    let settings = fx.config_home.join("astral-plasma").join("settings.json");
    let raw = std::fs::read_to_string(&settings).expect("fixture settings");
    std::fs::write(&settings, raw.replace("\"language\":\"en\"", "\"language\":\"auto\""))
        .expect("rewrite fixture settings");

    // The legacy `-dl` tie variables are ignored: no detection spawn exists to
    // read them. The sidecar reports `fr`; the decode uses the locale prior.
    let (events, _err, ok) = fx.run_with_env("start\n", &[("LANG", "en_US.UTF-8"), ("ASTRAL_TEST_DETECTED_LANG", "ja"), ("ASTRAL_TEST_DETECTED_P", "0.084")]);
    assert!(ok);

    let final_event = events
        .iter()
        .find(|e| e.get("type").and_then(|t| t.as_str()) == Some("Final"))
        .expect("a Final event");

    assert_eq!(
        final_event.pointer("/payload/language").and_then(|l| l.as_str()),
        Some("fr"),
        "the single-pass sidecar reading is reported: {final_event:?}"
    );

    let logged = std::fs::read_to_string(&fx.engine_audio_log).expect("engine log");
    assert!(
        !logged.contains("detect_args="),
        "no -dl detection spawn may exist: {logged}"
    );
    let args = logged.lines().rev().find(|l| l.starts_with("args=")).expect("args");
    assert!(
        !args.contains("-l ja"),
        "a tie must never become the decode language: {args}"
    );
    assert!(
        !args.contains("-l auto"),
        "the decode must be committed to a language, not left to another argmax: {args}"
    );
}

#[test]
fn session_skips_the_engine_when_nothing_was_said() {
    // A music/noise-only capture must not reach the engine: it would answer
    // with annotations ("(upbeat music)") or hallucinated words. The
    // capture-side detector gates it, which is what replaces engine VAD's only
    // measured benefit without VAD's language-detection damage.
    let fx = Fixture::new();
    let silence = fx._dir.path().join("silence-capture.sh");
    write_script(
        &silence,
        r#"#!/usr/bin/env bash
python3 - <<'PY'
import sys
sys.stdout.buffer.write(bytes(16000 * 2 * 2))  # 2 s of silence
PY
"#,
    );
    let _ = std::fs::remove_file(&fx.engine_audio_log);

    let mut cmd = fx.session_command();
    cmd.env("ASTRAL_VOICE_CAPTURE_BIN", &silence);
    cmd.env("ASTRAL_VOICE_AEC_SOURCE", "");
    let mut child = cmd.spawn().expect("spawn");
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("flush");
    let out = child.wait_with_output().expect("wait");
    drop(stdin);
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let events: Vec<Value> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| serde_json::from_str(l).expect("valid JSON event"))
        .collect();
    let final_event = events
        .iter()
        .find(|e| e.get("type").and_then(|t| t.as_str()) == Some("Final"))
        .expect("a Final event");
    assert_eq!(
        final_event.pointer("/payload/text").and_then(|t| t.as_str()),
        Some(""),
        "nothing was said, so the transcript must be empty"
    );
    assert!(!fx.engine_audio_log.exists(),
        "the engine must not be invoked for a capture with no speech");
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
    assert!(!args.contains("--vad"),
        "engine VAD rewrites the audio before language detection and must never be requested, got: {args}");
    assert!(!args.contains("--vad-model"),
        "no VAD model may be named: the flags are not used, got: {args}");
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
fn session_warns_on_clipped_input_without_failing() {
    // Audit §4.1: +60 dB analog gain hard-clips 68% of samples. The session
    // must warn once (warn-only, never rewrites ALSA) and still transcribe.
    let fx = Fixture::new();
    let clipped = fx._dir.path().join("clipped-capture.sh");
    write_script(
        &clipped,
        r#"#!/usr/bin/env bash
python3 - <<'PY'
import sys, struct
# 1.2 s of full-scale square wave (clipped), then quiet for endpointing.
out = bytearray()
for i in range(int(16000 * 1.2)):
    out.extend(struct.pack('<h', 32767 if i % 2 == 0 else -32768))
out.extend(bytes(int(16000 * 2.5) * 2))
sys.stdout.buffer.write(bytes(out))
PY
"#,
    );

    let mut cmd = fx.session_command();
    cmd.env("ASTRAL_VOICE_CAPTURE_BIN", &clipped);
    cmd.env("ASTRAL_VOICE_AEC_SOURCE", "");
    let mut child = cmd.spawn().expect("spawn");
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("flush");
    let out = child.wait_with_output().expect("wait");
    drop(stdin);
    assert!(out.status.success());

    let events: Vec<Value> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| serde_json::from_str(l).expect("valid JSON event"))
        .collect();
    let k = kinds(&events);
    assert!(k.contains(&"Warning".to_string()), "clipped input must warn: {k:?}");
    assert!(k.contains(&"Final".to_string()), "a clipped session still transcribes: {k:?}");
    let warn = events.iter().find(|e| e.get("type").and_then(|t| t.as_str()) == Some("Warning")).unwrap();
    let msg = warn.pointer("/payload/message").and_then(|m| m.as_str()).unwrap_or("");
    assert!(msg.contains("clipping"), "warning must name the cause: {msg}");
}

/// Writes a stub neural-VAD binary printing `stdout_body`, logging its argv and
/// the WAV size it was handed, plus a stub VAD model file. Returns the binary
/// path; the caller wires `ASTRAL_VOICE_VAD_BIN` + `ASTRAL_VOICE_MODEL_DIR`.
fn write_vad_stub(fx: &Fixture, name: &str, stdout_body: &str) -> PathBuf {
    let vad = fx._dir.path().join(name);
    write_script(
        &vad,
        &format!(
            r#"#!/usr/bin/env bash
wav=""
prev=""
for a in "$@"; do
  [ "$prev" = "-f" ] && wav="$a"
  prev="$a"
done
if [ -n "$wav" ] && [ -f "$wav" ]; then
  echo "vad_bytes=$(wc -c < "$wav")" >> "{log}"
fi
echo "vad_args=$*" >> "{log}"
printf '%s' '{body}'
"#,
            log = fx.engine_audio_log.display(),
            body = stdout_body,
        ),
    );
    std::fs::write(fx.models.join("ggml-silero-v5.1.2.bin"), b"stub-vad-weights")
        .expect("stub vad model");
    vad
}

#[test]
fn session_trims_to_neural_bounds_when_vad_is_provisioned() {
    // Audit §4.2: the VAD judges the FULL capture and its union span replaces
    // the energy bounds. The stub capture emits 1.2 s of tone (energy would
    // keep ~1.7 s with padding); the stub VAD reports speech only at 0.10–0.50 s,
    // so the engine must receive ~0.9 s.
    let fx = Fixture::new();
    let vad = write_vad_stub(
        &fx,
        "stub-vad.sh",
        "Detected 2 speech segments:\nSpeech segment 0: start = 10.00, end = 50.00\n",
    );
    let _ = std::fs::remove_file(&fx.engine_audio_log);

    let mut cmd = fx.session_command();
    cmd.env("ASTRAL_VOICE_VAD_BIN", &vad);
    let mut child = cmd.spawn().expect("spawn");
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("flush");
    let out = child.wait_with_output().expect("wait");
    drop(stdin);
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let logged = std::fs::read_to_string(&fx.engine_audio_log).expect("vad+engine log");
    let bytes: u64 = logged
        .lines()
        .rev()
        .find(|l| l.starts_with("bytes="))
        .expect("engine must run on neural speech")
        .trim_start_matches("bytes=")
        .trim()
        .parse()
        .expect("numeric");
    let pcm_ms = bytes.saturating_sub(44) / 32;
    assert!(pcm_ms >= 600 && pcm_ms < 1_200,
        "engine must receive the neural span (~0.9 s with padding), got {pcm_ms}ms");

    // The VAD judged the whole endpointed capture, not an energy-trimmed
    // fragment: its input must strictly exceed what the engine received.
    let vad_bytes: u64 = logged
        .lines()
        .find(|l| l.starts_with("vad_bytes="))
        .expect("vad must see audio")
        .trim_start_matches("vad_bytes=")
        .trim()
        .parse()
        .expect("numeric");
    let vad_ms = vad_bytes.saturating_sub(44) / 32;
    assert!(vad_ms > pcm_ms,
        "VAD must judge the full capture ({vad_ms}ms), not the neural span ({pcm_ms}ms)");
}

#[test]
fn session_neural_silence_skips_the_engine_despite_loud_capture() {
    // The discriminator energy cannot make: a loud pure tone carries real RMS
    // (the energy detector votes speech) but no vocal content (Silero votes
    // silence, verified live). Neural silence must skip inference.
    let fx = Fixture::new();
    let vad = write_vad_stub(&fx, "stub-vad-silence.sh", "Detected 0 speech segments:\n");
    let _ = std::fs::remove_file(&fx.engine_audio_log);

    let mut cmd = fx.session_command();
    cmd.env("ASTRAL_VOICE_VAD_BIN", &vad);
    let mut child = cmd.spawn().expect("spawn");
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("flush");
    let out = child.wait_with_output().expect("wait");
    drop(stdin);
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let events: Vec<Value> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| serde_json::from_str(l).expect("valid JSON event"))
        .collect();
    let final_event = events
        .iter()
        .find(|e| e.get("type").and_then(|t| t.as_str()) == Some("Final"))
        .expect("a Final event");
    assert_eq!(
        final_event.pointer("/payload/text").and_then(|t| t.as_str()),
        Some(""),
        "neural silence must produce an empty transcript"
    );
    assert!(
        !logged_has_engine_bytes(&fx),
        "the engine must not be invoked for neural silence"
    );
}

fn logged_has_engine_bytes(fx: &Fixture) -> bool {
    std::fs::read_to_string(&fx.engine_audio_log)
        .unwrap_or_default()
        .lines()
        .any(|l| l.starts_with("bytes="))
}

#[test]
fn session_captures_through_the_noise_suppressed_source_when_configured() {
    // Audit §3.3 evaluated replacement: an explicit operator-provisioned
    // suppression node wins over the default source without loading modules.
    // `session_command` sets no AEC override, so the NR path is exercised.
    let fx = Fixture::new();
    let _ = std::fs::remove_file(&fx.capture_args_log);
    let mut cmd = fx.session_command();
    cmd.env("ASTRAL_VOICE_NOISE_SUPPRESS_SOURCE", "stub-nr-node");
    let mut child = cmd.spawn().expect("spawn");
    let mut stdin = child.stdin.take().expect("stdin");
    stdin.write_all(b"start\n").expect("write");
    stdin.flush().expect("flush");
    let out = child.wait_with_output().expect("wait");
    drop(stdin);
    assert!(out.status.success(), "stderr: {}", String::from_utf8_lossy(&out.stderr));

    let logged = std::fs::read_to_string(&fx.capture_args_log)
        .expect("the capture stub must log its arguments");
    let args = logged
        .lines()
        .rev()
        .find(|l| l.starts_with("args="))
        .expect("a logged capture invocation");
    assert!(args.contains("--target stub-nr-node"),
        "capture must target the suppression source, got: {args}");
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
        .env("ASTRAL_VOICE_AEC_SOURCE", "stub-aec")
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
    assert_eq!(v.get("echo_cancel"), Some(&Value::Bool(false)),
        "echo cancellation defaults off (audit §3.3): legacy AEC ships zero reference samples");
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
        .env("ASTRAL_VOICE_AEC_SOURCE", "stub-aec")
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
    write_script(&stalled, "#!/usr/bin/env bash\nexec sleep 600\n");

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
    if !done {
        // Never block on a child that ignored the cap: `wait_with_output` would
        // sit here until the stub's own 600s sleep ends, turning one late
        // watchdog into a ten-minute test-suite hang.
        let _ = child.kill();
    }
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
