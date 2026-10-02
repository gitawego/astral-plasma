use crate::domain::ports::{DynResult, ShortcutControlPort};

#[derive(Clone)]
pub struct ShortcutControlUseCase<P: ShortcutControlPort> {
    port: P,
}

impl<P: ShortcutControlPort> ShortcutControlUseCase<P> {
    pub fn new(port: P) -> Self {
        Self { port }
    }

    /// Granularly snapshots only Astral-relevant shortcuts. The adapter is
    /// ALWAYS reached: with an active backup it merges keys it only started
    /// managing after that backup was written (never overwriting recorded
    /// originals); with none it creates one. Gating on is_backup_active()
    /// here silently skipped that merge.
    pub fn snapshot(&self, mode: &str) -> DynResult<()> {
        let target_key = match mode {
            "meta" | "super" => "Alt+F1",
            "alt-space" => "Alt+Space",
            _ => "Meta+Space",
        };

        self.port.snapshot_relevant_shortcuts(target_key, mode)?;
        Ok(())
    }

    /// Granularly snapshots only Astral-relevant shortcuts (merging into an
    /// existing backup when present) and binds this shell's shortcuts.
    ///
    /// A journal left behind by a *previous boot* is handed back first, before
    /// anything is claimed: the machine may have been switched off mid-session,
    /// and binding over that journal would leave the user's own Meta keys
    /// displaced with no shell serving the replacements. Releasing here (rather
    /// than only at the caller) keeps the session's two concurrent claim calls -
    /// the shell fires `plasma disable` and `shortcuts bind` together - order
    /// independent: whichever runs second cannot resurrect the old claim.
    pub fn backup_and_bind(&self, mode: &str) -> DynResult<()> {
        crate::application::stale_claim::release_stale_shortcuts(&self.port);
        self.snapshot(mode)?;
        self.port.bind_shortcuts(mode)?;
        Ok(())
    }

    /// Restores only the specific shortcuts that Astral modified, preserving all other user modifications
    pub fn restore(&self) -> DynResult<bool> {
        self.port.restore_relevant_shortcuts()
    }

    pub fn is_active(&self) -> bool {
        self.port.is_backup_active()
    }
}
