use astral_plasma::domain::shortcuts::{
    merge_missing_entries, AstralShortcutSessionBackup, DisplacedShortcut, GranularShortcutSnapshot,
};

fn snap(group: &str, key: &str, previous_value: Option<&str>) -> GranularShortcutSnapshot {
    GranularShortcutSnapshot {
        group: group.to_string(),
        key: key.to_string(),
        previous_value: previous_value.map(str::to_string),
        keys: Vec::new(),
    }
}

fn backup(
    entries: Vec<GranularShortcutSnapshot>,
    displaced: Option<DisplacedShortcut>,
) -> AstralShortcutSessionBackup {
    AstralShortcutSessionBackup {
        timestamp: 1,
        affected_entries: entries,
        previous_kwin_plugin_enabled: false,
        displaced_action: displaced.clone(),
        displaced_actions: displaced.into_iter().collect(),
        mode: Some("meta-space".to_string()),
    }
}

fn displaced_action(group: &str, key: &str) -> DisplacedShortcut {
    DisplacedShortcut {
        group: group.to_string(),
        key: key.to_string(),
        full_value: "Meta,none,Other Action".to_string(),
        keys: Vec::new(),
    }
}

// A key Astral Plasma only started managing AFTER this session's backup was
// written (the bare-Meta overview) must still be restorable: the merge records
// its pristine current value, while every already-recorded entry keeps its
// ORIGINAL previous value - re-binding after the first bind must never
// overwrite the true pre-session state with the already-modified value.
#[test]
fn merge_appends_missing_keys_and_preserves_recorded_values() {
    let existing = backup(vec![snap("kwin", "AstralLauncher", Some("none,none,Launcher"))], None);
    let fresh = vec![
        snap("kwin", "AstralLauncher", Some("Meta+Space,none,Launcher")),
        snap("kwin", "AstralOverview", None),
        snap(
            "plasmashell",
            "activate application launcher",
            Some("Meta\tAlt+F1,Meta\tAlt+F1,Launcher"),
        ),
    ];

    let (merged, changed) = merge_missing_entries(existing, fresh, None);

    assert!(changed, "appending a missing key must mark the backup changed");
    assert_eq!(merged.affected_entries.len(), 3, "all three keys must be recorded");

    let launcher = merged
        .affected_entries
        .iter()
        .find(|e| e.key == "AstralLauncher")
        .expect("AstralLauncher entry");
    assert_eq!(
        launcher.previous_value.as_deref(),
        Some("none,none,Launcher"),
        "an already-recorded key must keep its ORIGINAL previous value, not the re-bind snapshot"
    );

    let overview = merged
        .affected_entries
        .iter()
        .find(|e| e.key == "AstralOverview")
        .expect("AstralOverview entry");
    assert_eq!(
        overview.previous_value, None,
        "a key that did not exist before the session records None so restore removes it"
    );
}

// Idempotence: snapshot runs on every bind, so a second run with nothing new
// must not rewrite, duplicate, or re-stamp anything.
#[test]
fn merge_is_a_noop_when_everything_is_recorded() {
    let existing = backup(
        vec![snap("kwin", "AstralLauncher", Some("original"))],
        Some(displaced_action("kwin", "ShowDesktop")),
    );
    let fresh = vec![snap("kwin", "AstralLauncher", Some("modified-later"))];

    let (merged, changed) = merge_missing_entries(existing, fresh, Some(displaced_action("kwin", "OtherAction")));

    assert!(!changed, "nothing missing means nothing changed");
    assert_eq!(merged.affected_entries.len(), 1);
    assert_eq!(
        merged.affected_entries[0].previous_value.as_deref(),
        Some("original"),
        "recorded values survive untouched"
    );
    let disp = merged.displaced_action.expect("displaced must survive");
    assert_eq!(
        disp.key, "ShowDesktop",
        "the FIRST recorded displaced action wins, never a later overwrite"
    );
}

// The displaced action (who owned the target key before we claimed it) fills
// in only when the backup has none.
#[test]
fn merge_fills_displaced_only_when_absent() {
    let existing = backup(vec![], None);
    let fresh = vec![snap("kwin", "AstralOverview", None)];

    let (merged, changed) = merge_missing_entries(
        existing,
        fresh,
        Some(displaced_action("plasmashell", "activate application launcher")),
    );

    assert!(changed, "filling the displaced action must mark the backup changed");
    let disp = merged.displaced_action.expect("displaced must be filled");
    assert_eq!(disp.group, "plasmashell");
}

// ShortcutControlUseCase::snapshot must reach the adapter EVEN when a backup
// already exists: the adapter's snapshot is what merges newly-managed keys
// (the bare-Meta overview) into the active session backup. Gating on
// is_backup_active() skipped that merge - observed live as a backup that never
// gained the AstralOverview entry, leaving `shortcuts restore` unable to
// release the key and recreating the two-owners-of-Meta hazard.
#[test]
fn snapshot_reaches_the_adapter_even_with_an_active_backup() {
    use astral_plasma::application::shortcut_service::ShortcutControlUseCase;
    use astral_plasma::domain::ports::ShortcutControlPort;
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::Arc;

    struct CountingPort {
        snapshots: Arc<AtomicU32>,
        backup_active: bool,
    }

    impl ShortcutControlPort for CountingPort {
        fn snapshot_relevant_shortcuts(
            &self,
            _target_shortcut: &str,
            _mode: &str,
        ) -> astral_plasma::domain::ports::DynResult<AstralShortcutSessionBackup> {
            self.snapshots.fetch_add(1, Ordering::SeqCst);
            Ok(backup(vec![], None))
        }

        fn restore_relevant_shortcuts(&self) -> astral_plasma::domain::ports::DynResult<bool> {
            Ok(false)
        }

        fn bind_shortcuts(&self, _mode: &str) -> astral_plasma::domain::ports::DynResult<()> {
            Ok(())
        }

        fn is_backup_active(&self) -> bool {
            self.backup_active
        }
    }

    let counter = Arc::new(AtomicU32::new(0));
    let port = CountingPort { snapshots: counter.clone(), backup_active: true };
    let use_case = ShortcutControlUseCase::new(port);

    use_case.snapshot("meta-space").expect("snapshot must succeed");

    assert_eq!(
        counter.load(Ordering::SeqCst),
        1,
        "an active backup must still reach snapshot_relevant_shortcuts so newly-managed keys get merged in"
    );
}

// ============================================================================
// Live key codes: the config text alone is not enough
// ============================================================================

/// A file-level restore does not move KGlobalAccel's *live* registration: the
/// running daemon keeps the keys it has, so a restored `kglobalshortcutsrc`
/// leaves the user's shortcuts dead until the next login. That is exactly how
/// Meta+W (Overview) and the launcher's bare Meta were lost: the session's
/// journal recorded the config text but not the key codes KGlobalAccel was
/// holding. The journal therefore records the codes, and the restore replays
/// them.
#[test]
fn backup_round_trips_the_live_key_codes() {
    let entry = GranularShortcutSnapshot {
        group: "kwin".to_string(),
        key: "Overview".to_string(),
        previous_value: Some("none,Meta+W,Toggle Overview".to_string()),
        keys: vec![268435543],
    };
    let json = serde_json::to_string(&entry).expect("serialize");
    let parsed: GranularShortcutSnapshot = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(parsed.keys, vec![268435543]);
}

/// Journals written before the codes were captured must still load.
#[test]
fn journals_without_key_codes_still_load() {
    let legacy = r#"{"timestamp":1,"affected_entries":[{"group":"kwin","key":"AstralLauncher","previous_value":"none,none,Launcher"}],"previous_kwin_plugin_enabled":false,"displaced_action":null,"displaced_actions":[{"group":"kwin","key":"Overview","full_value":"none,Meta+W,Toggle Overview"}],"mode":"meta-space"}"#;
    let parsed: AstralShortcutSessionBackup =
        serde_json::from_str(legacy).expect("legacy journal must load");
    assert!(parsed.affected_entries[0].keys.is_empty());
    assert!(parsed.displaced_actions[0].keys.is_empty());
}

/// The replay must name the action it re-arms and pass the recorded codes.
#[test]
fn the_rearm_step_hands_the_recorded_codes_back() {
    use astral_plasma::infrastructure::kwin_shortcuts::rearm_snippet;

    let mut confirmed = GranularShortcutSnapshot {
        group: "kwin".to_string(),
        key: "Overview".to_string(),
        previous_value: Some("none,Meta+W,Toggle Overview".to_string()),
        keys: vec![268435543],
    };
    let displaced = DisplacedShortcut {
        group: "kwin".to_string(),
        key: "Show Desktop".to_string(),
        full_value: "none,Meta+D,Peek at Desktop".to_string(),
        keys: vec![268435524],
    };
    let partial_journal = AstralShortcutSessionBackup {
        timestamp: 1,
        affected_entries: vec![confirmed.clone()],
        previous_kwin_plugin_enabled: false,
        displaced_action: None,
        displaced_actions: vec![displaced],
        mode: Some("meta-space".to_string()),
    };

    let snippet = rearm_snippet(&partial_journal);
    assert!(snippet.contains("setForeignShortcut"), "the replay must use setForeignShortcut:\n{snippet}");
    assert!(snippet.contains("'Overview'"), "the overview action must be re-armed:\n{snippet}");
    assert!(snippet.contains("268435543"), "the recorded code must be replayed:\n{snippet}");
    assert!(snippet.contains("'Show Desktop'") && snippet.contains("268435524"),
        "every displaced action must be re-armed:\n{snippet}");
    assert!(snippet.contains("Toggle Overview"),
        "the replay must use the action's own label, not a placeholder:\n{snippet}");

    // An entry without codes must not be replayed (old journals must not make
    // the restore emit a bogus zero-key reset)...
    confirmed.keys.clear();
    let bare = AstralShortcutSessionBackup { affected_entries: vec![confirmed], ..partial_journal.clone() };
    let partial = rearm_snippet(&bare);
    assert!(!partial.contains("'Overview'"),
        "an entry without recorded codes must not be replayed:\n{partial}");

    // ...and a journal with no codes at all produces no replay script.
    let nothing = AstralShortcutSessionBackup {
        affected_entries: Vec::new(),
        displaced_action: None,
        displaced_actions: Vec::new(),
        ..partial_journal
    };
    assert!(rearm_snippet(&nothing).is_empty(),
        "a journal with no recorded codes must produce no replay script");
}

/// The restore path must call the replay (a config rewrite alone is not enough).
#[test]
fn restore_replays_the_live_keys() {
    let source = std::fs::read_to_string(
        concat!(env!("CARGO_MANIFEST_DIR"), "/src/infrastructure/kwin_shortcuts.rs"),
    )
    .expect("kwin_shortcuts.rs must be readable");
    assert!(source.contains("rearm_snippet"),
        "restore_relevant_shortcuts must replay the recorded live keys");
    assert!(source.contains("shortcutKeys"),
        "the snapshot must capture the live keys before the session claims them");
}
