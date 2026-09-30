//! The desktop-integration session lifecycle: claim, reconcile, release.
//!
//! These tests spawn the *real* binary against a throwaway `XDG_CONFIG_HOME`, so
//! they observe the thing that regressed: what a start and a signal do to the
//! user's KDE configuration. They are the reason the signal path no longer
//! restores anything - a unit test over a pure function could never have caught
//! "restarting the shell unbinds every shortcut".

use astral_plasma::domain::branding;
use astral_plasma::infrastructure::kwin_shortcuts::KdeIniFile;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

/// A throwaway desktop configuration: its own config dir, its own session
/// journal, and the binary under test.
struct Session {
    root: PathBuf,
    child: Option<Child>,
}

impl Session {
    fn new(name: &str) -> Self {
        let root = std::env::temp_dir().join(format!("astral-lifecycle-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("config")).expect("temp config dir");
        fs::create_dir_all(root.join("backup")).expect("temp backup dir");
        Self { root, child: None }
    }

    fn config_home(&self) -> PathBuf {
        self.root.join("config")
    }

    fn kglobal(&self) -> PathBuf {
        self.config_home().join("kglobalshortcutsrc")
    }

    fn kwinrc(&self) -> PathBuf {
        self.config_home().join("kwinrc")
    }

    fn journal(&self) -> PathBuf {
        self.root.join("backup").join("shortcuts_backup.json")
    }

    fn write(&self, path: &Path, content: &str) {
        fs::write(path, content).expect("write fixture");
    }

    fn read(&self, path: &Path) -> String {
        fs::read_to_string(path).unwrap_or_default()
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut cmd = Command::new(env!("CARGO_BIN_EXE_astral-plasma"));
        cmd.args(args)
            .env(branding::ENV_TEST_MODE, "1")
            .env("XDG_CONFIG_HOME", self.config_home())
            .env(branding::ENV_SHORTCUTS_BACKUP_DIR, self.root.join("backup"))
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        cmd
    }

    fn run(&self, args: &[&str]) {
        let status = self.command(args).status().expect("run binary");
        assert!(status.success(), "`astral-plasma {}` failed", args.join(" "));
    }

    /// Start the long-running daemon and keep the handle for signalling.
    fn start_daemon(&mut self) {
        let child = self.command(&["watch"]).spawn().expect("spawn daemon");
        self.child = Some(child);
    }

    fn terminate_daemon(&mut self) {
        if let Some(mut child) = self.child.take() {
            unsafe { libc::kill(child.id() as i32, libc::SIGTERM) };
            let deadline = Instant::now() + Duration::from_secs(5);
            loop {
                match child.try_wait() {
                    Ok(Some(_)) => return,
                    Ok(None) if Instant::now() < deadline => sleep(Duration::from_millis(50)),
                    Ok(None) => {
                        let _ = child.kill();
                        panic!("daemon ignored SIGTERM; a supervisor restart must end the process");
                    }
                    Err(err) => panic!("waiting for the daemon failed: {err}"),
                }
            }
        }
    }

    /// Wait until `check` holds, or fail with `what`.
    fn wait_for(&self, what: &str, check: impl Fn(&Session) -> bool) {
        let deadline = Instant::now() + Duration::from_secs(10);
        while Instant::now() < deadline {
            if check(self) {
                return;
            }
            sleep(Duration::from_millis(50));
        }
        panic!("timed out waiting for {what}");
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        if let Some(child) = self.child.as_mut() {
            let _ = child.kill();
            let _ = child.wait();
        }
        let _ = fs::remove_dir_all(&self.root);
    }
}

/// A desktop that Plasma owns, as `plasma disable` would find it.
const PLASMA_OWNED: &str = "[kwin]\nActivate Window Demanding Attention=Meta+Ctrl+A,Meta+Ctrl+A,Activate Window Demanding Attention\nAstralLauncher=Alt+F1,none,Astral Plasma: Toggle Launcher\nAstralAssistant=none,none,Astral Plasma: Toggle AI Copilot\n\n[plasmashell]\nactivate application launcher=Meta+Space,none,Activate Application Launcher\n";

fn shortcut_keys(content: &str) -> Vec<(String, String)> {
    let ini = KdeIniFile::parse(content);
    let mut keys: Vec<(String, String)> = Vec::new();
    if let Some(group) = ini.groups.get("kwin") {
        for (key, value) in group {
            if key.starts_with("Astral") {
                keys.push((key.clone(), value.clone()));
            }
        }
    }
    keys
}

#[test]
fn claiming_twice_changes_nothing() {
    let session = Session::new("idempotent");
    session.write(&session.kglobal(), PLASMA_OWNED);
    session.write(&session.kwinrc(), "[Plugins]\nastral-plasma-shortcutsEnabled=true\n");

    session.run(&["shortcuts", "bind", "meta-space"]);
    let after_first = session.read(&session.kglobal());
    session.run(&["shortcuts", "bind", "meta-space"]);
    let after_second = session.read(&session.kglobal());

    assert_eq!(
        after_first, after_second,
        "a second claim in the same mode must be a no-op"
    );
    assert!(
        after_first.contains("AstralLauncher=Meta+Space,none,"),
        "the claim binds the launcher key, got:\n{after_first}"
    );
    let journal = session.read(&session.journal());
    assert!(
        journal.contains("\"meta-space\""),
        "the session journal records the claimed mode, got:\n{journal}"
    );
}

#[test]
fn releasing_gives_the_original_keys_back() {
    let session = Session::new("release");
    session.write(&session.kglobal(), PLASMA_OWNED);
    session.write(&session.kwinrc(), "[Plugins]\nastral-plasma-shortcutsEnabled=true\n");
    let before = shortcut_keys(&session.read(&session.kglobal()));

    session.run(&["shortcuts", "bind", "meta-space"]);
    let claimed = shortcut_keys(&session.read(&session.kglobal()));
    assert_ne!(before, claimed, "claiming must actually change the keys");

    session.run(&["shortcuts", "restore"]);
    let released = shortcut_keys(&session.read(&session.kglobal()));
    assert_eq!(
        before, released,
        "releasing must restore exactly the keys the session displaced"
    );
    assert!(
        !session.journal().exists(),
        "the journal is cleared once the session is released"
    );
}

#[test]
fn a_termination_signal_is_not_user_intent() {
    let session = Session::new("sigterm");
    session.write(&session.kglobal(), PLASMA_OWNED);
    session.write(&session.kwinrc(), "[Plugins]\nastral-plasma-shortcutsEnabled=true\n");

    let mut session = session;
    session.start_daemon();
    session.wait_for("the session claim", |s| {
        s.read(&s.kglobal()).contains("AstralLauncher=Meta+Space,none,")
    });
    let claimed = session.read(&session.kglobal());

    session.terminate_daemon();

    let after = session.read(&session.kglobal());
    assert_eq!(
        claimed, after,
        "a supervisor restarting the daemon must not hand the desktop back\n--- before ---\n{claimed}\n--- after ---\n{after}"
    );
    assert!(
        session.journal().exists(),
        "the session stays claimed after a signal"
    );
}

#[test]
fn a_restart_resumes_the_recorded_mode() {
    let session = Session::new("resume");
    session.write(&session.kglobal(), PLASMA_OWNED);
    session.write(&session.kwinrc(), "[Plugins]\nastral-plasma-shortcutsEnabled=true\n");

    // The user chose bare Meta for the launcher.
    session.run(&["shortcuts", "bind", "meta"]);

    let mut session = session;
    session.start_daemon();
    session.wait_for("the daemon to come up", |s| s.journal().exists());
    sleep(Duration::from_millis(400));

    let content = session.read(&session.kglobal());
    assert!(
        content.contains("AstralLauncher=Meta,none,"),
        "a restart must resume the recorded mode instead of resetting it, got:\n{content}"
    );
    session.terminate_daemon();
}

#[test]
fn a_legacy_journal_learns_its_mode() {
    // Journals written before the mode was recorded must not stay anonymous: the
    // claim check would never recognise them and every start would re-bind.
    let session = Session::new("legacy");
    session.write(&session.kglobal(), PLASMA_OWNED);
    session.write(&session.kwinrc(), "[Plugins]\nastral-plasma-shortcutsEnabled=true\n");
    session.write(
        &session.journal(),
        r#"{"timestamp":1,"affected_entries":[],"previous_kwin_plugin_enabled":true,"displaced_action":null,"displaced_actions":[]}"#,
    );

    session.run(&["shortcuts", "bind", "meta-space"]);
    let journal = session.read(&session.journal());
    assert!(
        journal.contains("\"mode\": \"meta-space\""),
        "the journal must record the mode it was claimed in, got:\n{journal}"
    );

    // And with the mode recorded, the next claim is a no-op.
    let claimed = session.read(&session.kglobal());
    session.run(&["shortcuts", "bind", "meta-space"]);
    assert_eq!(claimed, session.read(&session.kglobal()));
}

#[test]
fn releasing_deactivates_the_astral_kwin_script() {
    // The kwinrc plugin flag decides whether KWin loads the Astral shortcut
    // script at login. A previous session can leave it enabled; "restoring" that
    // value then keeps KWin registering Astral shortcuts (the bare Meta overview
    // key included) even with the theme not running - which is how a session
    // loses Alt+Tab *without* the theme. Releasing must always deactivate it.
    let session = Session::new("plugin-release");
    session.write(&session.kglobal(), PLASMA_OWNED);
    session.write(&session.kwinrc(), "[Plugins]\nastral-plasma-shortcutsEnabled=true\n");

    session.run(&["shortcuts", "bind", "meta-space"]);
    session.run(&["shortcuts", "restore"]);

    let kwinrc = session.read(&session.kwinrc());
    assert!(
        !kwinrc.contains("astral-plasma-shortcutsEnabled=true"),
        "releasing the session must deactivate the Astral KWin script, got:\n{kwinrc}"
    );
}
