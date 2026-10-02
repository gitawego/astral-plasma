//! Handing a previous boot's session claim back before this session takes one.
//!
//! The shell's desktop claim lives in files - the KDE shortcut journal, the panel
//! marker, KWin's blur snapshot - so it outlives the process that made it. A
//! machine that is switched off (or crashes) while the shell runs never executes
//! the hand-back, and the next login then starts Plasma with the shell's keys
//! still claimed and no shell serving them: the user's own bare-Meta, Meta+W and
//! Meta+D actions are dead until somebody restores them by hand.
//!
//! Every session start therefore asks this use case first. It reads what each
//! resource's own record says (`ClaimStamp`), lets the pure
//! `plan_stale_hand_back` decide what belongs to a previous boot, and performs
//! exactly those hand-back steps in dependency order. Nothing is released that
//! this boot can prove it owns, so a running session is never disturbed.

use crate::domain::desktop_integration::{plan_stale_hand_back, ClaimRecord, HandBack};
use crate::domain::ports::{BlurControlPort, PlasmaControlPort, ShortcutControlPort};
use crate::infrastructure::session_identity;
use std::sync::Arc;

pub struct StaleClaimRelease {
    plasma: Arc<dyn PlasmaControlPort>,
    shortcuts: Arc<dyn ShortcutControlPort>,
    blur: Arc<dyn BlurControlPort>,
}

impl StaleClaimRelease {
    pub fn new(
        plasma: Arc<dyn PlasmaControlPort>,
        shortcuts: Arc<dyn ShortcutControlPort>,
        blur: Arc<dyn BlurControlPort>,
    ) -> Self {
        Self { plasma, shortcuts, blur }
    }

    /// The session start's own release authority, wired to the desktop's ports.
    pub fn for_desktop() -> Self {
        Self::new(
            Arc::new(crate::infrastructure::plasma_adapter::PlasmaAdapter::new()),
            Arc::new(crate::infrastructure::kwin_shortcuts::KWinShortcutsAdapter::new()),
            Arc::new(crate::infrastructure::kwin_blur::KWinBlurAdapter::new()),
        )
    }

    /// What the desktop's own records say is currently claimed.
    ///
    /// Read from the records, not from process state: a claim is on disk whether
    /// or not anything is still running to serve it.
    pub fn records(&self) -> Vec<ClaimRecord> {
        vec![
            ClaimRecord { resource: HandBack::Shortcuts, stamp: self.shortcuts.shortcut_claim() },
            ClaimRecord { resource: HandBack::Blur, stamp: self.blur.blur_claim() },
            ClaimRecord { resource: HandBack::Panels, stamp: self.plasma.panel_claim() },
        ]
    }

    /// Hand back everything a previous boot left claimed.
    ///
    /// Returns the steps that ran, in the order they ran, so callers can report
    /// what a reboot had been holding. A session that owns its claim gets an
    /// empty list and no side effect.
    pub fn release_if_stale(&self) -> Vec<HandBack> {
        let current = session_identity::current_boot_id();
        let steps = plan_stale_hand_back(&self.records(), current.as_deref());
        for step in &steps {
            match step {
                HandBack::Shortcuts => {
                    let _ = self.shortcuts.restore_relevant_shortcuts();
                }
                HandBack::Blur => {
                    let _ = self.blur.restore();
                }
                HandBack::Panels => {
                    let _ = self.plasma.restore_config();
                }
            }
        }
        steps
    }
}

/// Release a stale shortcut claim before binding a new one.
///
/// Called from the shortcut bind path itself, so the order of a session's two
/// claim calls (`plasma disable` and `shortcuts bind`, which the shell fires
/// concurrently) can never matter: whichever runs second cannot bind over a
/// previous boot's journal, and cannot be reverted by the other's release.
pub fn release_stale_shortcuts(port: &dyn ShortcutControlPort) -> bool {
    let records = [ClaimRecord { resource: HandBack::Shortcuts, stamp: port.shortcut_claim() }];
    let steps = plan_stale_hand_back(&records, session_identity::current_boot_id().as_deref());
    if steps.is_empty() {
        return false;
    }
    port.restore_relevant_shortcuts().is_ok()
}

/// Stamp a claim taken now, so a later boot can tell it from its own.
///
/// `None` when this boot has no readable id: the record then carries no stamp,
/// the next session cannot prove the claim is its own, and releases it - which
/// is the honest outcome rather than keeping keys nobody can account for.
pub fn current_claim_boot_id() -> Option<String> {
    session_identity::current_boot_id()
}
