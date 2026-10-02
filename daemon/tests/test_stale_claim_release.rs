//! A desktop claim outlives the process that made it.
//!
//! The shell's claim on the desktop lives in files - the KDE shortcut journal,
//! the panel marker, KWin's blur snapshot - so a machine that is switched off (or
//! crashes) while the shell runs never executes a hand-back. The next login then
//! starts Plasma with the shell's keys still displaced and no shell serving them:
//! the user's own bare-Meta, Meta+W and Meta+D actions are dead until something
//! restores them. That is the reported regression these tests pin down.
//!
//! Two layers are covered: the *decision* (which records a previous boot left
//! behind, in which order they are handed back) against recording mocks, and the
//! *wiring* at the session start against the real adapters, on throwaway config
//! homes - including the exact on-disk state the user was left with.

use astral_plasma::application::shortcut_service::ShortcutControlUseCase;
use astral_plasma::application::stale_claim::StaleClaimRelease;
use astral_plasma::domain::branding;
use astral_plasma::domain::desktop_integration::{ClaimStamp, HandBack};
use astral_plasma::domain::plasma::{PlasmaPanelInfo, PlasmaStatus};
use astral_plasma::domain::ports::{
    BlurControlPort, DynResult, PlasmaControlPort, ShortcutControlPort,
};
use astral_plasma::domain::shortcuts::{AstralShortcutSessionBackup, GranularShortcutSnapshot};
use astral_plasma::infrastructure::kwin_blur::KWinBlurAdapter;
use astral_plasma::infrastructure::kwin_shortcuts::KWinShortcutsAdapter;
use astral_plasma::infrastructure::plasma_adapter::PlasmaAdapter;
use std::sync::{Arc, Mutex, Once};

/// The boot the test session is running in.
const THIS_BOOT: &str = "19b856cd-3601-443d-a12f-dbaef4533265";
/// The boot whose claim a reboot left behind.
const PREVIOUS_BOOT: &str = "0badc0de-1111-2222-3333-444455556666";

/// Pin this session's boot id for every test in this binary.
///
/// `ASTRAL_PLASMA_BOOT_ID` is process-global, so it is set exactly once and all
/// tests use the same running boot - which is also what makes the "previous
/// boot" cases meaningful rather than racy.
fn running_boot() -> &'static str {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| std::env::set_var(branding::ENV_BOOT_ID, THIS_BOOT));
    THIS_BOOT
}

fn boot(id: &str) -> ClaimStamp {
    ClaimStamp::Boot(id.to_string())
}

/// Serialises the filesystem phases of this suite.
///
/// `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and the backup-dir overrides are process
/// globals, and cargo runs the tests in one process in parallel: two tests
/// pointing them at different temp roots would edit each other's fixtures. The
/// decision tests need none of this and stay parallel.
fn desktop() -> std::sync::MutexGuard<'static, ()> {
    static DESKTOP: Mutex<()> = Mutex::new(());
    DESKTOP.lock().unwrap_or_else(|error| error.into_inner())
}

/// Ordered log of every port call the release made.
#[derive(Default)]
struct Recorder {
    calls: Mutex<Vec<&'static str>>,
}

impl Recorder {
    fn record(&self, call: &'static str) {
        self.calls.lock().unwrap().push(call);
    }

    fn calls(&self) -> Vec<&'static str> {
        self.calls.lock().unwrap().clone()
    }
}

struct MockPlasma {
    log: Arc<Recorder>,
    stamp: ClaimStamp,
    restore_fails: bool,
}

impl PlasmaControlPort for MockPlasma {
    fn query_panels(&self) -> DynResult<Vec<PlasmaPanelInfo>> {
        Ok(Vec::new())
    }

    fn disable_panels(&self, _target: &str) -> DynResult<u32> {
        self.log.record("plasma.disable_panels");
        Ok(0)
    }

    fn backup_config(&self) -> DynResult<bool> {
        Ok(false)
    }

    fn restore_config(&self) -> DynResult<bool> {
        self.log.record("plasma.restore_config");
        if self.restore_fails {
            return Err("plasmashell did not answer".into());
        }
        Ok(true)
    }

    fn get_status(&self) -> DynResult<PlasmaStatus> {
        Ok(PlasmaStatus {
            panels: Vec::new(),
            backup_dir: String::new(),
            session_active: self.stamp != ClaimStamp::Unclaimed,
            watchdog_pid: None,
        })
    }

    fn stop_watchdog(&self) {}

    fn panel_claim(&self) -> ClaimStamp {
        self.stamp.clone()
    }
}

struct MockShortcuts {
    log: Arc<Recorder>,
    stamp: ClaimStamp,
    restore_fails: bool,
}

impl ShortcutControlPort for MockShortcuts {
    fn snapshot_relevant_shortcuts(
        &self,
        _target_shortcut: &str,
        _mode: &str,
    ) -> DynResult<AstralShortcutSessionBackup> {
        self.log.record("shortcuts.snapshot");
        Ok(AstralShortcutSessionBackup {
            timestamp: 0,
            affected_entries: Vec::new(),
            previous_kwin_plugin_enabled: false,
            displaced_action: None,
            displaced_actions: Vec::new(),
            mode: Some("meta-space".to_string()),
            boot_id: Some(THIS_BOOT.to_string()),
        })
    }

    fn restore_relevant_shortcuts(&self) -> DynResult<bool> {
        self.log.record("shortcuts.restore");
        if self.restore_fails {
            return Err("kwriteconfig6 failed".into());
        }
        Ok(true)
    }

    fn bind_shortcuts(&self, _mode: &str) -> DynResult<()> {
        self.log.record("shortcuts.bind");
        Ok(())
    }

    fn is_backup_active(&self) -> bool {
        self.stamp != ClaimStamp::Unclaimed
    }

    fn shortcut_claim(&self) -> ClaimStamp {
        self.stamp.clone()
    }
}

struct MockBlur {
    log: Arc<Recorder>,
    stamp: ClaimStamp,
}

impl BlurControlPort for MockBlur {
    fn blur_claim(&self) -> ClaimStamp {
        self.stamp.clone()
    }

    fn restore(&self) -> DynResult<bool> {
        self.log.record("blur.restore");
        Ok(true)
    }
}

struct Session {
    log: Arc<Recorder>,
    release: StaleClaimRelease,
}

impl Session {
    fn new(shortcuts: ClaimStamp, blur: ClaimStamp, panels: ClaimStamp) -> Self {
        let log = Arc::new(Recorder::default());
        let release = StaleClaimRelease::new(
            Arc::new(MockPlasma { log: Arc::clone(&log), stamp: panels, restore_fails: false }),
            Arc::new(MockShortcuts {
                log: Arc::clone(&log),
                stamp: shortcuts.clone(),
                restore_fails: false,
            }),
            Arc::new(MockBlur { log: Arc::clone(&log), stamp: blur }),
        );
        Self { log, release }
    }
}

// ============================================================================
// The decision: what a previous boot left behind is handed back, in order
// ============================================================================

#[test]
fn a_claim_from_a_previous_boot_is_handed_back_in_hand_back_order() {
    let _ = running_boot();
    let session = Session::new(boot(PREVIOUS_BOOT), boot(PREVIOUS_BOOT), boot(PREVIOUS_BOOT));

    let released = session.release.release_if_stale();

    assert_eq!(released, vec![HandBack::Shortcuts, HandBack::Blur, HandBack::Panels]);
    assert_eq!(
        session.log.calls(),
        vec!["shortcuts.restore", "blur.restore", "plasma.restore_config"],
        "the keys are handed back before KWin's blur, and the panel service last"
    );
}

#[test]
fn a_claim_this_boot_owns_is_left_completely_alone() {
    let _ = running_boot();
    let session = Session::new(boot(THIS_BOOT), boot(THIS_BOOT), boot(THIS_BOOT));

    assert!(session.release.release_if_stale().is_empty());
    assert!(session.log.calls().is_empty(), "a live session must not be disturbed");
}

#[test]
fn an_emptied_claim_only_hands_back_what_is_actually_held() {
    let _ = running_boot();
    // The state a machine switched off mid-session leaves behind on older
    // builds: an empty panel marker and a journal with no boot stamp at all.
    let session = Session::new(ClaimStamp::Unstamped, ClaimStamp::Unclaimed, ClaimStamp::Unstamped);

    assert_eq!(session.release.release_if_stale(), vec![HandBack::Shortcuts, HandBack::Panels]);
    assert_eq!(session.log.calls(), vec!["shortcuts.restore", "plasma.restore_config"]);
}

#[test]
fn a_hand_back_that_fails_does_not_strand_the_other_resources() {
    let _ = running_boot();
    let log = Arc::new(Recorder::default());
    let release = StaleClaimRelease::new(
        Arc::new(MockPlasma {
            log: Arc::clone(&log),
            stamp: boot(PREVIOUS_BOOT),
            restore_fails: true,
        }),
        Arc::new(MockShortcuts {
            log: Arc::clone(&log),
            stamp: boot(PREVIOUS_BOOT),
            restore_fails: true,
        }),
        Arc::new(MockBlur { log: Arc::clone(&log), stamp: boot(PREVIOUS_BOOT) }),
    );

    // Both restores report failure; the panel hand-back still has to run, or one
    // broken config write would leave the user's panels hidden forever.
    assert_eq!(
        release.release_if_stale(),
        vec![HandBack::Shortcuts, HandBack::Blur, HandBack::Panels]
    );
    assert_eq!(
        log.calls(),
        vec!["shortcuts.restore", "blur.restore", "plasma.restore_config"]
    );
}

// ============================================================================
// The bind path: never bind over a previous boot's journal
// ============================================================================

#[test]
fn binding_hands_a_previous_boots_journal_back_first() {
    let _ = running_boot();
    let log = Arc::new(Recorder::default());
    let use_case = ShortcutControlUseCase::new(MockShortcuts {
        log: Arc::clone(&log),
        stamp: boot(PREVIOUS_BOOT),
        restore_fails: false,
    });

    use_case.backup_and_bind("meta-space").expect("bind");

    assert_eq!(
        log.calls(),
        vec!["shortcuts.restore", "shortcuts.snapshot", "shortcuts.bind"],
        "the previous claim is released before the snapshot records pristine values"
    );
}

#[test]
fn binding_keeps_a_claim_this_boot_already_owns() {
    let _ = running_boot();
    let log = Arc::new(Recorder::default());
    let use_case = ShortcutControlUseCase::new(MockShortcuts {
        log: Arc::clone(&log),
        stamp: boot(THIS_BOOT),
        restore_fails: false,
    });

    use_case.backup_and_bind("meta-space").expect("bind");

    assert_eq!(log.calls(), vec!["shortcuts.snapshot", "shortcuts.bind"]);
}

// ============================================================================
// The wiring: the reported on-disk state, repaired by one session start
// ============================================================================

/// One test owns the filesystem phases: `XDG_CONFIG_HOME`/`XDG_DATA_HOME` and
/// the two backup-dir overrides are process-global, so two tests setting them
/// would race (the same trap `test_kwin_blur` documents).
#[test]
fn a_session_start_repairs_what_a_reboot_left_claimed() {
    let _desktop = desktop();
    let _ = running_boot();
    let tmp = tempfile::tempdir().expect("tempdir");
    let config = tmp.path().join("config");
    let shortcut_backup = tmp.path().join("shortcuts-backup");
    let plasma_backup = tmp.path().join("plasma-backup");
    std::fs::create_dir_all(&config).unwrap();
    std::fs::create_dir_all(&shortcut_backup).unwrap();
    std::fs::create_dir_all(&plasma_backup).unwrap();
    std::env::set_var("XDG_CONFIG_HOME", &config);
    std::env::set_var("XDG_DATA_HOME", tmp.path().join("data"));
    std::env::set_var(branding::ENV_SHORTCUTS_BACKUP_DIR, &shortcut_backup);
    std::env::set_var(branding::ENV_PLASMA_BACKUP_DIR, &plasma_backup);
    std::env::set_var(branding::ENV_TEST_MODE, "1");

    // The claimed state the user was left with: bare Meta taken off the Plasma
    // launcher, the shell's actions bound, KWin told to load the Astral script,
    // and nothing running to serve any of it.
    std::fs::write(
        config.join("kglobalshortcutsrc"),
        "[kwin]\nAstralLauncher=Meta+Space,none,Astral Plasma: Toggle Launcher\n\n\
         [plasmashell]\nactivate application launcher=Alt+F1,Meta\\tAlt+F1,Activate Application Launcher\n",
    )
    .unwrap();
    std::fs::write(
        config.join("kwinrc"),
        "[Plugins]\nastral-plasma-shortcutsEnabled=true\n",
    )
    .unwrap();
    std::fs::write(
        config.join("plasma-org.kde.plasma.desktop-appletsrc"),
        "[Containments][42]\nplugin=org.kde.panel\n",
    )
    .unwrap();

    // The journal and the panel marker, as a previous boot left them: a journal
    // without a boot stamp and an empty marker (both were written before claim
    // stamping existed, and neither can be proved to belong to this boot).
    let journal = AstralShortcutSessionBackup {
        timestamp: 1790840723,
        affected_entries: vec![
            GranularShortcutSnapshot {
                group: "kwin".to_string(),
                key: "AstralLauncher".to_string(),
                previous_value: Some("none,none,Astral Plasma: Toggle Launcher".to_string()),
                keys: Vec::new(),
            },
            GranularShortcutSnapshot {
                group: "plasmashell".to_string(),
                key: "activate application launcher".to_string(),
                previous_value: Some(
                    "Meta\tAlt+F1\tMeta+Space,Meta\tAlt+F1,Activate Application Launcher"
                        .to_string(),
                ),
                keys: Vec::new(),
            },
        ],
        previous_kwin_plugin_enabled: false,
        displaced_action: None,
        displaced_actions: Vec::new(),
        mode: Some("meta-space".to_string()),
        boot_id: None,
    };
    std::fs::write(
        shortcut_backup.join("shortcuts_backup.json"),
        serde_json::to_string_pretty(&journal).unwrap(),
    )
    .unwrap();
    std::fs::write(plasma_backup.join("session_active"), "").unwrap();

    // ...and KWin's blur snapshot, taken when the shell tuned the compositor.
    let blur_backup = tmp.path().join("data").join(branding::DATA_DIR).join("blur-backup");
    std::fs::create_dir_all(&blur_backup).unwrap();
    std::fs::write(
        blur_backup.join("blur_backup.json"),
        r#"{"strength":null,"noise_strength":null}"#,
    )
    .unwrap();

    let released = StaleClaimRelease::for_desktop().release_if_stale();

    assert_eq!(released, vec![HandBack::Shortcuts, HandBack::Blur, HandBack::Panels]);

    // Bare Meta is back on the Plasma launcher: the symptom the user reported.
    let kglobal = std::fs::read_to_string(config.join("kglobalshortcutsrc")).unwrap();
    let after = astral_plasma::infrastructure::kwin_shortcuts::KdeIniFile::parse(&kglobal);
    let launcher = after
        .get("plasmashell", "activate application launcher")
        .expect("the launcher entry must survive the hand-back");
    assert!(
        launcher.contains("Meta"),
        "bare Meta must be handed back to the Plasma launcher, got: {launcher}"
    );

    // The shell's own actions are unbound (the pre-session value had no key),
    // KWin no longer loads its shortcut script, and nothing is left claiming the
    // desktop.
    let astral = after
        .get("kwin", "AstralLauncher")
        .expect("the shell's own key is a monitored entry");
    assert!(
        astral.starts_with("none,none"),
        "the shell's keys must be released, got: {astral}"
    );
    let kwinrc = std::fs::read_to_string(config.join("kwinrc")).unwrap();
    assert!(
        !kwinrc.contains("astral-plasma-shortcutsEnabled"),
        "the KWin plugin flag is dropped, not ratcheted on:\n{kwinrc}"
    );
    assert!(
        !shortcut_backup.join("shortcuts_backup.json").exists(),
        "a released claim must not leave its journal behind"
    );
    assert!(
        !plasma_backup.join("session_active").exists(),
        "a released panel claim must clear the marker"
    );
    assert!(
        !blur_backup.join("blur_backup.json").exists(),
        "a released blur claim must drop its snapshot"
    );
    assert_eq!(
        PlasmaAdapter::new().panel_claim(),
        ClaimStamp::Unclaimed,
        "the panel side must now read as unclaimed"
    );
    assert!(!KWinShortcutsAdapter::new().is_backup_active());
}

#[test]
fn a_marker_that_names_this_boot_is_not_handed_back() {
    let _desktop = desktop();
    let _ = running_boot();
    let tmp = tempfile::tempdir().expect("tempdir");
    let backup = tmp.path().join("plasma-backup");
    std::fs::create_dir_all(&backup).unwrap();
    std::env::set_var(branding::ENV_PLASMA_BACKUP_DIR, &backup);
    std::env::set_var(branding::ENV_TEST_MODE, "1");

    std::fs::write(backup.join("session_active"), format!("{THIS_BOOT}\n")).unwrap();
    assert_eq!(PlasmaAdapter::new().panel_claim(), boot(THIS_BOOT));

    std::fs::write(backup.join("session_active"), format!("{PREVIOUS_BOOT}\n")).unwrap();
    assert_eq!(PlasmaAdapter::new().panel_claim(), boot(PREVIOUS_BOOT));
}

#[test]
fn the_blur_snapshot_records_the_boot_that_applied_it() {
    let _desktop = desktop();
    let _ = running_boot();
    let tmp = tempfile::tempdir().expect("tempdir");
    // The live desktop's own config, which no test may touch.
    let real_kwinrc = branding::home_dir().join(".config").join("kwinrc");
    let real_before = std::fs::read(&real_kwinrc).ok();

    std::env::set_var("XDG_CONFIG_HOME", tmp.path());
    std::env::set_var("XDG_DATA_HOME", tmp.path().join("data"));
    std::env::set_var(branding::ENV_TEST_MODE, "1");
    std::fs::write(tmp.path().join("kwinrc"), "[General]\nfoo=bar\n").unwrap();

    let adapter = KWinBlurAdapter::new();
    assert_eq!(adapter.blur_claim(), ClaimStamp::Unclaimed, "nothing is claimed yet");

    adapter
        .apply(&astral_plasma::infrastructure::kwin_blur::BlurSettings {
            strength: 3,
            noise_strength: 0,
        })
        .expect("apply");

    assert_eq!(
        adapter.blur_claim(),
        boot(THIS_BOOT),
        "the override is stamped with the boot that took it"
    );
    assert!(
        tmp.path().join("kwinrc").exists(),
        "the override belongs in the isolated config home"
    );
    assert_eq!(
        std::fs::read(&real_kwinrc).ok(),
        real_before,
        "an apply must never write into the live desktop's kwinrc"
    );
    assert!(BlurControlPort::restore(&adapter).expect("restore"));
    assert_eq!(adapter.blur_claim(), ClaimStamp::Unclaimed);
}
