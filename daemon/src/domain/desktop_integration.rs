//! Desktop-integration session policy: claim, reconcile, release.
//!
//! The shell and the daemon both mutate state that belongs to the *desktop*, not
//! to a process: KDE global shortcuts, the KWin shortcut script, the frameless
//! window rule and the Plasma panel configuration. Two rules keep that state
//! honest, and both are pure decisions so they can be tested without a session:
//!
//! 1. **A process signal is never user intent.** Signals end the process; the
//!    desktop is handed back when the *shell* disappears (the watchdog) or when
//!    the user asks for it (`plasma restore`), never because a supervisor
//!    restarted us.
//! 2. **Desired state is reconciled, not applied once.** Anything that drifts -
//!    a respawned panel, an unloaded KWin script, a claim Plasma overwrote - is
//!    repaired on the next tick instead of relying on somebody re-running setup.

/// What the daemon wants the desktop to look like while the shell runs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DesiredState {
    /// Shortcut mode the session is claimed in (`meta-space`, `meta`, ...).
    pub mode: String,
    /// Built-in Plasma panels stay disabled while the shell owns the desktop.
    pub panels_disabled: bool,
    /// The shell's toplevel windows stay frameless.
    pub frameless_rule: bool,
}

/// What the desktop actually looks like right now.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ObservedState {
    /// Built-in Plasma panels currently present.
    pub panels_present: usize,
    /// Session claimed: the journal records this mode *and* the live
    /// configuration still carries it.
    pub shortcuts_claimed: bool,
    /// The KWin script owning the shortcut actions is loaded.
    pub shortcut_script_loaded: bool,
    /// The frameless window rule for the shell's toplevel class is present.
    pub frameless_rule_present: bool,
}

/// One repair the reconciler performs. The order is the order it must run in:
/// the shortcut actions live in the KWin script, so the script has to be loaded
/// before the keys are worth claiming.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Repair {
    DisablePanels,
    LoadShortcutScript,
    ClaimShortcuts,
    ApplyFramelessRule,
}

/// Decide what has to be repaired. Pure: the caller supplies the observation.
pub fn plan_repairs(observed: &ObservedState, desired: &DesiredState) -> Vec<Repair> {
    let mut repairs = Vec::new();

    if desired.panels_disabled && observed.panels_present > 0 {
        repairs.push(Repair::DisablePanels);
    }

    if !observed.shortcuts_claimed {
        if !observed.shortcut_script_loaded {
            repairs.push(Repair::LoadShortcutScript);
        }
        repairs.push(Repair::ClaimShortcuts);
    }

    if desired.frameless_rule && !observed.frameless_rule_present {
        repairs.push(Repair::ApplyFramelessRule);
    }

    repairs
}

/// The desktop resources a session claim owns.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HandBack {
    Shortcuts,
    Blur,
    Panels,
}

/// Position of a hand-back step in the order the steps must run.
fn hand_back_order(step: HandBack) -> u8 {
    match step {
        HandBack::Shortcuts => 0,
        HandBack::Blur => 1,
        HandBack::Panels => 2,
    }
}

/// What a resource's own record says about it.
///
/// `Unclaimed` is the healthy state, `Unstamped` is a record written before
/// boot stamping existed (or one whose stamp cannot be read), and `Boot` names
/// the boot the claim was made in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClaimStamp {
    Unclaimed,
    Unstamped,
    Boot(String),
}

/// Does a claim belong to a *previous* boot?
///
/// A claim outlives the process that made it: the shortcuts journal and the
/// panel marker are files on disk, and a machine that is switched off - or
/// crashes - while the shell runs never runs a hand-back. The next login then
/// starts Plasma with the shell's keys still claimed and no shell to serve them,
/// so the user's own bare-Meta / Meta+W / Meta+D actions are dead until somebody
/// restores them by hand.
///
/// The boot id is what makes that state recognisable: a claim stamped with the
/// running boot is this session's, and a claim stamped with any other boot (or
/// with no stamp at all) can never be proved to be ours, so it is handed back
/// instead of kept.
pub fn claim_is_stale(stamp: &ClaimStamp, current_boot_id: Option<&str>) -> bool {
    match stamp {
        ClaimStamp::Unclaimed => false,
        ClaimStamp::Unstamped => true,
        ClaimStamp::Boot(claimed) => current_boot_id.map_or(true, |current| current != claimed),
    }
}

/// One claimed resource as its own record describes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClaimRecord {
    pub resource: HandBack,
    pub stamp: ClaimStamp,
}

/// What a starting session must give back: every record that cannot be proved
/// to belong to the running boot, in hand-back order.
///
/// Resources are decided one by one - a shortcut journal can be this boot's while
/// a panel marker is a previous boot's - and the result is ordered so the desktop
/// is never left half handed back: the keys first, then KWin's blur, then the
/// panel service, because a plasmashell started while the shell's keys are still
/// claimed shows the user a desktop whose Meta keys do nothing.
pub fn plan_stale_hand_back(records: &[ClaimRecord], current_boot_id: Option<&str>) -> Vec<HandBack> {
    let mut steps: Vec<HandBack> = records
        .iter()
        .filter(|record| claim_is_stale(&record.stamp, current_boot_id))
        .map(|record| record.resource)
        .collect();
    steps.sort_by_key(|step| hand_back_order(*step));
    steps.dedup();
    steps
}

/// Which mode a starting session resumes: the one the journal recorded, so a
/// restart never silently switches the user back to the default mode.
pub fn resume_mode(journal_mode: Option<&str>) -> &str {
    journal_mode.unwrap_or(DEFAULT_SHORTCUT_MODE)
}

/// The mode used when nothing was ever claimed.
pub const DEFAULT_SHORTCUT_MODE: &str = "meta-space";

/// Should the desktop be handed back when the supervised shell disappears?
///
/// `plasma.autoRestoreOnExit` defaults to true; a user who turned it off keeps
/// the shell's desktop state after quitting.
pub fn restore_on_exit(setting: Option<bool>) -> bool {
    setting.unwrap_or(true)
}

/// Read `plasma.autoRestoreOnExit` out of a shell settings document. `None` when
/// the block or the key is absent, which the caller treats as the default.
pub fn auto_restore_from_settings(settings_json: &str) -> Option<bool> {
    let value: serde_json::Value = serde_json::from_str(settings_json).ok()?;
    value.get("plasma")?.get("autoRestoreOnExit")?.as_bool()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn desired() -> DesiredState {
        DesiredState {
            mode: DEFAULT_SHORTCUT_MODE.to_string(),
            panels_disabled: true,
            frameless_rule: true,
        }
    }

    fn healthy() -> ObservedState {
        ObservedState {
            panels_present: 0,
            shortcuts_claimed: true,
            shortcut_script_loaded: true,
            frameless_rule_present: true,
        }
    }

    #[test]
    fn a_healthy_desktop_is_left_alone() {
        assert!(plan_repairs(&healthy(), &desired()).is_empty());
    }

    #[test]
    fn a_respawned_panel_is_disabled_again() {
        let observed = ObservedState { panels_present: 2, ..healthy() };
        assert_eq!(plan_repairs(&observed, &desired()), vec![Repair::DisablePanels]);
    }

    #[test]
    fn a_lost_claim_loads_the_script_before_re_claiming() {
        let observed = ObservedState {
            shortcuts_claimed: false,
            shortcut_script_loaded: false,
            ..healthy()
        };
        assert_eq!(
            plan_repairs(&observed, &desired()),
            vec![Repair::LoadShortcutScript, Repair::ClaimShortcuts]
        );
    }

    #[test]
    fn a_lost_claim_with_the_script_still_loaded_only_re_claims() {
        let observed = ObservedState { shortcuts_claimed: false, ..healthy() };
        assert_eq!(plan_repairs(&observed, &desired()), vec![Repair::ClaimShortcuts]);
    }

    #[test]
    fn a_missing_window_rule_is_re_applied() {
        let observed = ObservedState { frameless_rule_present: false, ..healthy() };
        assert_eq!(plan_repairs(&observed, &desired()), vec![Repair::ApplyFramelessRule]);
    }

    #[test]
    fn several_drifts_repair_in_dependency_order() {
        let observed = ObservedState {
            panels_present: 1,
            shortcuts_claimed: false,
            shortcut_script_loaded: false,
            frameless_rule_present: false,
        };
        assert_eq!(
            plan_repairs(&observed, &desired()),
            vec![
                Repair::DisablePanels,
                Repair::LoadShortcutScript,
                Repair::ClaimShortcuts,
                Repair::ApplyFramelessRule,
            ]
        );
    }

    #[test]
    fn nothing_is_repaired_that_was_not_asked_for() {
        let passive = DesiredState {
            mode: DEFAULT_SHORTCUT_MODE.to_string(),
            panels_disabled: false,
            frameless_rule: false,
        };
        let observed = ObservedState {
            panels_present: 3,
            frameless_rule_present: false,
            ..healthy()
        };
        assert!(plan_repairs(&observed, &passive).is_empty());
    }

    fn record(resource: HandBack, stamp: ClaimStamp) -> ClaimRecord {
        ClaimRecord { resource, stamp }
    }

    fn boot(id: &str) -> ClaimStamp {
        ClaimStamp::Boot(id.to_string())
    }

    #[test]
    fn a_claim_from_a_previous_boot_is_stale() {
        // The reported regression: the machine is rebooted while the shell runs,
        // so the hand-back never executes and the claim is still on disk when
        // the next session starts.
        assert!(claim_is_stale(&boot("boot-a"), Some("boot-b")));
    }

    #[test]
    fn a_claim_stamped_with_this_boot_is_kept() {
        assert!(!claim_is_stale(&boot("boot-b"), Some("boot-b")));
    }

    #[test]
    fn an_unstamped_claim_is_stale() {
        // Journals written before the boot stamp existed, and an empty panel
        // marker, cannot be proved to belong to this boot.
        assert!(claim_is_stale(&ClaimStamp::Unstamped, Some("boot-b")));
    }

    #[test]
    fn an_unreadable_boot_id_never_keeps_a_claim() {
        assert!(claim_is_stale(&boot("boot-b"), None));
        assert!(claim_is_stale(&ClaimStamp::Unstamped, None));
    }

    #[test]
    fn an_unclaimed_resource_is_never_a_reason_to_restore() {
        assert!(!claim_is_stale(&ClaimStamp::Unclaimed, Some("boot-b")));
        assert!(!claim_is_stale(&ClaimStamp::Unclaimed, None));
    }

    #[test]
    fn nothing_is_claimed_nothing_is_handed_back() {
        assert!(plan_stale_hand_back(&[], Some("boot-b")).is_empty());
    }

    #[test]
    fn a_stale_claim_gives_every_resource_back_in_hand_back_order() {
        let records = [
            record(HandBack::Panels, boot("boot-a")),
            record(HandBack::Shortcuts, boot("boot-a")),
            record(HandBack::Blur, boot("boot-a")),
        ];
        assert_eq!(
            plan_stale_hand_back(&records, Some("boot-b")),
            vec![HandBack::Shortcuts, HandBack::Blur, HandBack::Panels]
        );
    }

    #[test]
    fn a_resource_this_boot_owns_is_not_handed_back() {
        let records = [
            record(HandBack::Shortcuts, boot("boot-b")),
            record(HandBack::Panels, boot("boot-a")),
        ];
        assert_eq!(plan_stale_hand_back(&records, Some("boot-b")), vec![HandBack::Panels]);
    }

    #[test]
    fn an_unstamped_claim_is_handed_back_while_this_boot_keeps_its_own() {
        let records = [
            record(HandBack::Shortcuts, ClaimStamp::Unstamped),
            record(HandBack::Panels, boot("boot-b")),
        ];
        assert_eq!(
            plan_stale_hand_back(&records, Some("boot-b")),
            vec![HandBack::Shortcuts]
        );
    }

    #[test]
    fn a_restart_resumes_the_recorded_mode() {
        assert_eq!(resume_mode(Some("meta")), "meta");
        assert_eq!(resume_mode(None), DEFAULT_SHORTCUT_MODE);
    }

    #[test]
    fn handing_the_desktop_back_follows_the_user_setting() {
        assert!(restore_on_exit(None));
        assert!(restore_on_exit(Some(true)));
        assert!(!restore_on_exit(Some(false)));

        assert_eq!(auto_restore_from_settings(r#"{"plasma":{"autoRestoreOnExit":false}}"#), Some(false));
        assert_eq!(auto_restore_from_settings(r#"{"plasma":{}}"#), None);
        assert_eq!(auto_restore_from_settings("not json"), None);
    }
}
