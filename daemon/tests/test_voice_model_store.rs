//! The speech-model store: install progress and removal.
//!
//! Driven through the **real binary** with a stub `curl` on `PATH` and a temp
//! model directory, so the whole path - progress parsing, the JSONL event the UI
//! reads, the staged `.part` file, the rename, and deletion - is verifiable
//! without a network, an engine or a microphone.
//!
//! This is the regression the user reported twice over: a 1.5 GiB download that
//! sat at 0% and then announced "downloaded", and a model that could be
//! installed but never removed.

use serde_json::Value;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

fn temp_root(name: &str) -> PathBuf {
    let root = std::env::temp_dir().join(format!("astral-model-store-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    fs::create_dir_all(&root).expect("temp root");
    root
}

/// A stand-in for curl that writes the file and emits the progress bar shape the
/// installer parses: one rewritten line per update, `####  42.3%`.
fn stub_curl(dir: &Path) -> PathBuf {
    let path = dir.join("curl");
    fs::write(
        &path,
        "#!/bin/sh\n\
         out=\"\"\n\
         while [ $# -gt 0 ]; do\n\
         \x20 case \"$1\" in\n\
         \x20   --output) out=\"$2\"; shift 2 ;;\n\
         \x20   *) shift ;;\n\
         \x20 esac\n\
         done\n\
         printf '#####                                            10.0%%\\r'\n\
         printf '##############################                   50.0%%\\r'\n\
         printf '################################################ 100.0%%\\r'\n\
         printf 'model-bytes' > \"$out\"\n\
         exit 0\n",
    )
    .expect("write stub curl");
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).expect("chmod stub curl");
    path
}

fn run(bin: &str, stub_dir: &Path, models: &Path, args: &[&str]) -> String {
    let path = format!(
        "{}:{}",
        stub_dir.display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let out = Command::new(bin)
        .args(args)
        .env("ASTRAL_VOICE_MODEL_DIR", models)
        .env("PATH", path)
        .output()
        .expect("run the daemon binary");
    format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    )
}

#[test]
fn install_streams_progress_fractions_and_remove_deletes_the_model() {
    let root = temp_root("progress");
    let models = root.join("models");
    let bin = env!("CARGO_BIN_EXE_astral-plasma");
    stub_curl(&root);

    // Install: the UI reads `payload` as a number, so that is what must arrive.
    let stdout = run(bin, &root, &models, &["voice", "install-model", "ggml-tiny"]);
    let fractions: Vec<f64> = stdout
        .lines()
        .filter_map(|line| {
            let value: Value = serde_json::from_str(line).ok()?;
            if value.get("type")?.as_str()? != "Progress" {
                return None;
            }
            value.get("payload")?.as_f64()
        })
        .collect();
    assert!(
        fractions.len() >= 3,
        "install must stream Progress events, got:\n{stdout}"
    );
    assert!(
        fractions.iter().all(|f| (0.0..=1.0).contains(f)),
        "every fraction must be a fraction, got {fractions:?}"
    );
    assert!(
        fractions.windows(2).all(|pair| pair[1] >= pair[0]),
        "progress must never go backwards, got {fractions:?}"
    );
    assert_eq!(
        fractions.last().copied(),
        Some(1.0),
        "the stream must finish at 1.0, got {fractions:?}"
    );

    let model = models.join("ggml-tiny.bin");
    assert!(model.exists(), "the download must land at {}", model.display());
    assert!(
        fs::read_to_string(&model).unwrap().contains("model-bytes"),
        "the staged .part file must be moved into place"
    );

    // Remove: the file goes, and the status says so.
    let stdout = run(bin, &root, &models, &["voice", "remove-model", "ggml-tiny"]);
    assert!(
        stdout.contains("\"removed\":true"),
        "removing a present model must report it, got:\n{stdout}"
    );
    assert!(!model.exists(), "the model file must be gone");

    // Removing again is a no-op, not an error: a UI can call it blind.
    let stdout = run(bin, &root, &models, &["voice", "remove-model", "ggml-tiny"]);
    assert!(
        stdout.contains("\"removed\":false"),
        "removing an absent model must be a no-op, got:\n{stdout}"
    );

    let _ = fs::remove_dir_all(&root);
}

#[test]
fn status_reports_echo_cancellation_without_loading_it() {
    // A status probe must never mutate the audio graph. It reports the setting
    // and whether the source is already present, and nothing else.
    let root = temp_root("echo-cancel-status");
    let models = root.join("models");
    let bin = env!("CARGO_BIN_EXE_astral-plasma");
    let marker = root.join("pactl-calls");
    let pactl = root.join("pactl");
    fs::write(
        &pactl,
        format!(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"{}\"\ncase \"$1\" in\n  list) exit 0 ;;\n  *) exit 0 ;;\nesac\n",
            marker.display()
        ),
    )
    .expect("stub pactl");
    fs::set_permissions(&pactl, fs::Permissions::from_mode(0o755)).expect("chmod");

    let out = Command::new(bin)
        .args(["voice", "status"])
        .env("ASTRAL_VOICE_MODEL_DIR", &models)
        .env("PATH", format!("{}:{}", root.display(), std::env::var("PATH").unwrap_or_default()))
        .output()
        .expect("run the daemon binary");
    let status: serde_json::Value = serde_json::from_slice(&out.stdout).expect("valid JSON");
    assert_eq!(status.get("echo_cancel"), Some(&serde_json::Value::Bool(false)),
        "echo cancellation defaults off (audit §3.3)");
    assert_eq!(status.get("echo_cancel_active"), Some(&serde_json::Value::Bool(false)),
        "the stub publishes no source, so it must report inactive");

    let calls = fs::read_to_string(&marker).unwrap_or_default();
    assert!(calls.contains("list short sources"),
        "status must check for the source, got: {calls}");
    assert!(!calls.contains("load-module"),
        "a status probe must never load the module, got: {calls}");

    let _ = fs::remove_dir_all(&root);
}

#[test]
fn the_status_names_the_install_command_for_this_machine() {
    let root = temp_root("model-store-status");
    let models = root.join("models");
    let bin = env!("CARGO_BIN_EXE_astral-plasma");

    let out = Command::new(bin)
        .args(["voice", "status"])
        .env("ASTRAL_VOICE_MODEL_DIR", &models)
        .output()
        .expect("run the daemon binary");
    let stdout = String::from_utf8_lossy(&out.stdout);
    let status: serde_json::Value =
        serde_json::from_str(stdout.trim()).expect("voice status must print one JSON document");

    if status.get("engine_available").and_then(|v| v.as_bool()) == Some(false) {
        let command = status
            .get("engine_install_command")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("a missing engine must carry an install command, got {status}"));
        assert!(
            command.contains("whisper"),
            "the install command must name the engine package, got {command}"
        );
    }

    let _ = fs::remove_dir_all(&root);
}

#[test]
fn cloud_key_set_status_and_clear_round_trip_without_leaking() {
    // Hermetic config home: set reads the key from stdin (never argv), stores
    // it owner-only, status reports presence without the value, clear removes.
    let root = temp_root("cloud-key");
    let bin = env!("CARGO_BIN_EXE_astral-plasma");
    let run = |args: &[&str], stdin: &str| -> String {
        let mut child = Command::new(bin)
            .arg("voice")
            .args(args)
            .env("XDG_CONFIG_HOME", &root)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .expect("spawn");
        use std::io::Write;
        child
            .stdin
            .take()
            .expect("stdin")
            .write_all(stdin.as_bytes())
            .expect("write");
        let out = child.wait_with_output().expect("wait");
        String::from_utf8_lossy(&out.stdout).into_owned()
    };

    let key_file = root.join("astral-plasma").join("deepgram_api_key");
    assert!(!key_file.is_file(), "no key may pre-exist");

    let set_out = run(&["cloud-key", "set"], "dg-secret-xyz\n");
    assert!(set_out.contains("\"success\":true"), "set must succeed, got: {set_out}");
    assert!(!set_out.contains("dg-secret-xyz"), "the key must never be echoed, got: {set_out}");
    assert_eq!(fs::read_to_string(&key_file).expect("key file"), "dg-secret-xyz");
    #[cfg(unix)]
    {
        let mode = fs::metadata(&key_file).expect("stat").permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "key file must be owner-only, got {mode:o}");
    }

    let status_out = run(&["cloud-key"], "");
    assert!(status_out.contains("\"present\":true"), "status must report presence, got: {status_out}");
    assert!(!status_out.contains("dg-secret-xyz"), "status must not leak the key, got: {status_out}");

    let clear_out = run(&["cloud-key", "clear"], "");
    assert!(clear_out.contains("\"success\":true"), "clear must succeed, got: {clear_out}");
    assert!(!key_file.is_file(), "clear must remove the file");

    let _ = fs::remove_dir_all(&root);
}
