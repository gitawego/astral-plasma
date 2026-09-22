use astral_plasma::domain::shortcuts::{
    merge_missing_entries, AstralShortcutSessionBackup, DisplacedShortcut, GranularShortcutSnapshot,
};

fn snap(group: &str, key: &str, previous_value: Option<&str>) -> GranularShortcutSnapshot {
    GranularShortcutSnapshot {
        group: group.to_string(),
        key: key.to_string(),
        previous_value: previous_value.map(str::to_string),
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
        displaced_action: displaced,
    }
}

fn displaced_action(group: &str, key: &str) -> DisplacedShortcut {
    DisplacedShortcut {
        group: group.to_string(),
        key: key.to_string(),
        full_value: "Meta,none,Other Action".to_string(),
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
