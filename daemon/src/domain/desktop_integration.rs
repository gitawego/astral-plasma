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
