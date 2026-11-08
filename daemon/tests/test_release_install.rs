//! End-to-end install and removal through the scripts a user actually runs.
//!
//! The daemon tests prove the layout; these prove the two entry points that the
//! README and the release tarball hand to a person, against a real binary
//! (`CARGO_BIN_EXE_astral-plasma`) in a throwaway `$HOME`.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf()
}

struct Sandbox {
    root: tempfile::TempDir,
}

impl Sandbox {
    fn new() -> Self {
        let root = tempfile::tempdir().unwrap();
        // A `quickshell` on PATH: the installers refuse to install a shell whose
        // runtime is missing, and the check must be exercised, not bypassed.
        let fake_bin = root.path().join("fakebin");
        fs::create_dir_all(&fake_bin).unwrap();
        let quickshell = fake_bin.join("quickshell");
        fs::write(&quickshell, "#!/bin/sh\nexit 0\n").unwrap();
        fs::set_permissions(&quickshell, fs::Permissions::from_mode(0o755)).unwrap();

        // Existing user settings that must survive install and uninstall.
        let config = root.path().join("config").join("astral-plasma");
        fs::create_dir_all(&config).unwrap();
        fs::write(config.join("settings.json"), r#"{"theme":{"blurStrength":0.7}}"#).unwrap();

        Self { root }
    }

    fn path(&self) -> &Path {
        self.root.path()
    }

    fn data_home(&self) -> PathBuf {
        self.root.path().join("data")
    }

    fn data_dir(&self) -> PathBuf {
        self.data_home().join("astral-plasma")
    }

    fn home(&self) -> PathBuf {
        self.root.path().join("home")
    }

    fn command(&self, script: &Path) -> Command {
        let mut cmd = Command::new("bash");
        cmd.arg(script);
        cmd.env("HOME", self.home())
            .env("XDG_DATA_HOME", self.data_home())
            .env("XDG_CONFIG_HOME", self.root.path().join("config"))
            .env("XDG_STATE_HOME", self.root.path().join("state"))
            .env("XDG_CACHE_HOME", self.root.path().join("cache"))
            .env("XDG_BIN_HOME", self.home().join(".local/bin"))
            .env("ASTRAL_PLASMA_TEST_MODE", "1")
            .env(
                "PATH",
                format!(
                    "{}:{}",
                    self.root.path().join("fakebin").display(),
                    std::env::var("PATH").unwrap_or_default()
                ),
            );
        // A developer running the suite inside Omarchy must not have the install
        // silently take the plugin path.
        for var in ["OMARCHY_SESSION_ID", "OMARCHY_DIR", "OMARCHY_SESSION"] {
            cmd.env_remove(var);
        }
        cmd
    }
}

#[test]
fn the_installer_creates_a_self_contained_managed_install() {
    let sandbox = Sandbox::new();
    let installer = repo_root().join("install.sh");
    let binary = env!("CARGO_BIN_EXE_astral-plasma");

    let output = sandbox
        .command(&installer)
        .args(["--from", binary])
        .output()
        .expect("run install.sh");
    assert!(
        output.status.success(),
        "install.sh failed:\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let data = sandbox.data_dir();
    let installed = data.join("bin/astral-plasma");
    assert!(installed.is_file(), "the binary must be installed");
    assert_eq!(
        fs::metadata(&installed).unwrap().permissions().mode() & 0o777,
        0o755,
        "an installed binary must be executable"
    );
    assert!(
        installed.metadata().unwrap().len() > 0,
        "the binary must not be truncated"
    );
    assert!(
        data.join("package/shell.qml").is_file(),
        "the QML bundle must be extracted beside the binary"
    );
    assert!(data.join("install.json").is_file(), "the owner must be recorded");

    let record = fs::read_to_string(data.join("install.json")).unwrap();
    assert!(record.contains("\"method\": \"managed\""), "{record}");

    let link = sandbox.home().join(".local/bin/astral-plasma");
    assert!(
        fs::symlink_metadata(&link).unwrap().file_type().is_symlink(),
        "the command must be reachable on PATH"
    );
    assert_eq!(fs::read_link(&link).unwrap(), installed);

    assert!(
        !sandbox.root.path().join("config/quickshell").exists(),
        "a managed install is self-contained: it must not claim ~/.config/quickshell"
    );

    let settings = fs::read_to_string(
        sandbox.root.path().join("config/astral-plasma/settings.json"),
    )
    .unwrap();
    assert!(settings.contains("0.7"), "install must not rewrite settings: {settings}");
}

#[test]
fn reinstalling_over_an_install_keeps_it_working() {
    let sandbox = Sandbox::new();
    let installer = repo_root().join("install.sh");
    let binary = env!("CARGO_BIN_EXE_astral-plasma");

    for _ in 0..2 {
        let output = sandbox
            .command(&installer)
            .args(["--from", binary])
            .output()
            .unwrap();
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    }

    let installed = sandbox.data_dir().join("bin/astral-plasma");
    assert!(installed.metadata().unwrap().len() > 0, "reinstall truncated the binary");

    // A dry run must not change anything.
    let before = fs::read(&installed).unwrap();
    let output = sandbox
        .command(&installer)
        .args(["--from", binary, "--dry-run"])
        .output()
        .unwrap();
    assert!(output.status.success());
    assert!(String::from_utf8_lossy(&output.stdout).contains("[dry-run]"));
    assert_eq!(fs::read(&installed).unwrap(), before);
}

#[test]
fn the_uninstaller_removes_the_install_and_keeps_settings() {
    let sandbox = Sandbox::new();
    let installer = repo_root().join("install.sh");
    let uninstaller = repo_root().join("uninstall.sh");
    let binary = env!("CARGO_BIN_EXE_astral-plasma");

    assert!(sandbox
        .command(&installer)
        .args(["--from", binary])
        .status()
        .unwrap()
        .success());

    let output = sandbox.command(&uninstaller).arg("--yes").output().unwrap();
    assert!(
        output.status.success(),
        "uninstall.sh failed:\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    assert!(!sandbox.data_dir().exists(), "the managed layout must be gone");
    assert!(
        !sandbox.home().join(".local/bin/astral-plasma").exists(),
        "a dangling command on PATH is worse than no command"
    );
    assert!(
        sandbox.root.path().join("config/astral-plasma/settings.json").is_file(),
        "settings survive an uninstall"
    );
}

#[test]
fn the_uninstaller_purges_settings_only_when_asked() {
    let sandbox = Sandbox::new();
    let installer = repo_root().join("install.sh");
    let uninstaller = repo_root().join("uninstall.sh");
    let binary = env!("CARGO_BIN_EXE_astral-plasma");

    assert!(sandbox
        .command(&installer)
        .args(["--from", binary])
        .status()
        .unwrap()
        .success());

    let output = sandbox
        .command(&uninstaller)
        .args(["--yes", "--purge"])
        .output()
        .unwrap();
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    assert!(
        !sandbox.root.path().join("config/astral-plasma").exists(),
        "--purge must remove settings too"
    );
}

#[test]
fn the_uninstaller_asks_before_removing_anything() {
    let sandbox = Sandbox::new();
    let installer = repo_root().join("install.sh");
    let uninstaller = repo_root().join("uninstall.sh");
    let binary = env!("CARGO_BIN_EXE_astral-plasma");

    assert!(sandbox
        .command(&installer)
        .args(["--from", binary])
        .status()
        .unwrap()
        .success());

    // No `--yes` and no stdin answer: the prompt must default to "no".
    let output = sandbox
        .command(&uninstaller)
        .stdin(std::process::Stdio::null())
        .output()
        .unwrap();
    assert!(output.status.success());
    assert!(
        sandbox.data_dir().exists(),
        "an unanswered prompt must leave the install untouched"
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("Nothing was changed"));
}
