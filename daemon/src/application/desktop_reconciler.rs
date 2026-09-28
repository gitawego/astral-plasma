//! Desired-state reconciler for the desktop-integration session.
//!
//! `plan_repairs` (domain) decides *what* drifted; this module reads the real
//! desktop and applies the repairs. Every step is idempotent, so a tick that
//! finds nothing to do costs one observation and nothing else - which is what
//! makes "bind once at startup" survivable when a supervisor restarts the shell
//! or Plasma respawns a panel.

use crate::domain::desktop_integration::{plan_repairs, DesiredState, ObservedState, Repair};
use crate::domain::ports::{PlasmaControlPort, ShortcutControlPort};
use crate::infrastructure::kwin_shortcuts::KWinShortcutsAdapter;
use crate::infrastructure::kwin_window_rules::KWinWindowRulesAdapter;
use std::sync::Arc;
use std::time::Duration;

/// How often drift is looked for. Panels respawn within seconds of being
/// disabled, so this stays in the range of the watchdog it replaces.
pub const RECONCILE_INTERVAL: Duration = Duration::from_secs(5);

pub struct DesktopReconciler {
    plasma: Arc<dyn PlasmaControlPort>,
    shortcuts: KWinShortcutsAdapter,
    window_rules: KWinWindowRulesAdapter,
}

impl DesktopReconciler {
    pub fn new(plasma: Arc<dyn PlasmaControlPort>) -> Self {
        Self {
            plasma,
            shortcuts: KWinShortcutsAdapter::new(),
            window_rules: KWinWindowRulesAdapter::new(),
        }
    }

    /// Read what the desktop looks like. Every read is best-effort: an
    /// unreadable config or a missing compositor reads as "not in place", which
    /// the planner turns into a repair attempt rather than a silent pass.
    pub fn observe(&self, desired: &DesiredState) -> ObservedState {
        ObservedState {
            panels_present: self.plasma.query_panels().map(|panels| panels.len()).unwrap_or(0),
            shortcuts_claimed: self.shortcuts.shortcut_claim_is_current(&desired.mode),
            shortcut_script_loaded: self.shortcuts.shortcut_script_loaded(),
            frameless_rule_present: self.window_rules.frameless_rule_present(),
        }
    }

    /// Apply one repair.
    pub fn apply(&self, repair: Repair, desired: &DesiredState) {
        match repair {
            Repair::DisablePanels => {
                let _ = self.plasma.disable_panels("all");
            }
            Repair::LoadShortcutScript => self.shortcuts.load_shortcut_script(),
            Repair::ClaimShortcuts => {
                let _ = self.shortcuts.bind_shortcuts(&desired.mode);
            }
            Repair::ApplyFramelessRule => {
                let _ = self.window_rules.apply();
            }
        }
    }

    /// One pass: observe, plan, repair. Returns the repairs that were applied.
    pub fn reconcile(&self, desired: &DesiredState) -> Vec<Repair> {
        let observed = self.observe(desired);
        let repairs = plan_repairs(&observed, desired);
        for repair in &repairs {
            self.apply(*repair, desired);
        }
        repairs
    }
}

/// Reconcile the desktop until the process ends.
pub async fn run_desktop_reconcile_loop(desired: DesiredState, interval: Duration) {
    let plasma: Arc<dyn PlasmaControlPort> =
        Arc::new(crate::infrastructure::plasma_adapter::PlasmaAdapter::new());
    let reconciler = DesktopReconciler::new(plasma);
    let mut ticker = tokio::time::interval(interval);
    loop {
        ticker.tick().await;
        let repairs = reconciler.reconcile(&desired);
        if !repairs.is_empty() {
            eprintln!("[reconciler] repaired {:?} (mode {})", repairs, desired.mode);
        }
    }
}
