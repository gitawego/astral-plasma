//! The supervisor really swaps the binary and re-execs it.
//!
//! This drives `astral-plasma run` in a throwaway `$HOME` with a fake
//! `quickshell`, a pre-staged update and a restart request. The staged "binary" is
//! a shell script, so if the swap and the `execv` happen the script runs and
//! leaves proof - which is exactly the mechanism the desktop restart relies on.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

struct Sandbox {
    root: tempfile::TempDir,
}

impl Sandbox {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        let fake_bin = root.path().join("fakebin");
        fs::create_dir_all(&fake_bin).unwrap();
        let quickshell = fake_bin.join("quickshell");
        fs::write(&quickshell, "#!/bin/sh\nexit 0\n").unwrap();
        fs::set_permissions(&quickshell, fs::Permissions::from_mode(0o755)).unwrap();

        let sandbox = Self { root };
        let data = sandbox.data_dir();
        fs::create_dir_all(data.join("bin")).unwrap();
        fs::create_dir_all(data.join("package")).unwrap();
        fs::write(data.join("package/shell.qml"), "// live bundle").unwrap();
        // A managed install at the current version: migration 001 must be a
        // no-op, so the update path is what this test actually exercises.
        fs::write(
            data.join("install.json"),
            format!(
                r#"{{"schema":1,"method":"managed","version":"{}","channel":"stable","installed_at_unix":1}}"#,
                env!("CARGO_PKG_VERSION")
            ),
        )
        .unwrap();
        fs::write(data.join("bin/astral-plasma"), b"old binary").unwrap();
        sandbox
    }

    fn path(&self) -> &Path {
        self.root.path()
    }

    fn data_dir(&self) -> PathBuf {
        self.root.path().join("data/astral-plasma")
    }

    fn state_dir(&self) -> PathBuf {
        self.root.path().join("state/astral-plasma")
    }

    fn command(&self) -> Command {
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_astral-plasma"));
        cmd.arg("run")
            .env("HOME", self.root.path().join("home"))
            .env("XDG_DATA_HOME", self.root.path().join("data"))
            .env("XDG_CONFIG_HOME", self.root.path().join("config"))
            .env("XDG_STATE_HOME", self.root.path().join("state"))
            .env("XDG_CACHE_HOME", self.root.path().join("cache"))
            .env("ASTRAL_PLASMA_TEST_MODE", "1")
            .env(
                "PATH",
                format!(
                    "{}:{}",
                    self.root.path().join("fakebin").display(),
                    std::env::var("PATH").unwrap_or_default()
                ),
            )
            .env_remove("WAYLAND_DISPLAY")
            .env_remove("DISPLAY")
            .env_remove("OMARCHY_SESSION_ID")
            .env_remove("OMARCHY_DIR")
            .env_remove("OMARCHY_SESSION")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        cmd
    }
}

fn wait_for(path: &Path, limit: Duration) -> bool {
    let deadline = Instant::now() + limit;
    while Instant::now() < deadline {
        if path.exists() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    false
}

#[test]
fn a_staged_update_is_swapped_in_and_executed_by_the_supervisor() {
    let sandbox = Sandbox::new();
    let proof = sandbox.path().join("new-binary-ran");
    let staged = sandbox.data_dir().join("bin/astral-plasma.next");
    fs::write(
        &staged,
        format!(
            "#!/bin/sh\necho \"{}\" > {}\nexit 0\n",
            "0.2.0",
            proof.display()
        ),
    )
    .unwrap();
    fs::set_permissions(&staged, fs::Permissions::from_mode(0o755)).unwrap();

    fs::create_dir_all(sandbox.state_dir()).unwrap();
    fs::write(
        sandbox.state_dir().join("restart-requested.json"),
        format!(
            r#"{{"schema":1,"target_version":"0.2.0","staged_binary":"{}","at_unix":1,"already_in_place":false}}"#,
            staged.display()
        ),
    )
    .unwrap();

    let mut child = sandbox.command().spawn().expect("start the supervisor");
    let ran = wait_for(&proof, Duration::from_secs(30));
    let _ = child.kill();
    let _ = child.wait();

    assert!(ran, "the staged binary was never executed");

    let live = sandbox.data_dir().join("bin/astral-plasma");
    let live_body = fs::read_to_string(&live).unwrap();
    assert!(
        live_body.contains("new-binary-ran"),
        "the live path must hold the staged binary after the swap: {live_body}"
    );
    assert!(
        sandbox.data_dir().join("bin/astral-plasma.prev").is_file(),
        "the previous binary must be kept for rollback"
    );
    assert!(
        !sandbox.state_dir().join("restart-requested.json").exists(),
        "a consumed request must not restart the shell again"
    );

    let record = fs::read_to_string(sandbox.data_dir().join("install.json")).unwrap();
    assert!(
        record.contains("\"version\": \"0.2.0\""),
        "the install record must name the version that is now live: {record}"
    );
}
