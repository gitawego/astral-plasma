use crate::domain::ports::{DynResult, ShortcutControlPort};

#[derive(Clone)]
pub struct ShortcutControlUseCase<P: ShortcutControlPort> {
    port: P,
}

impl<P: ShortcutControlPort> ShortcutControlUseCase<P> {
    pub fn new(port: P) -> Self {
        Self { port }
    }

    /// Granularly snapshots only Astral-relevant shortcuts if not already backed up
    pub fn snapshot(&self, mode: &str) -> DynResult<()> {
        let target_key = match mode {
            "meta" | "super" => "Alt+F1",
            "alt-space" => "Alt+Space",
            _ => "Meta+Space",
        };

        if !self.port.is_backup_active() {
            self.port.snapshot_relevant_shortcuts(target_key)?;
        }
        Ok(())
    }

    /// Granularly snapshots only Astral-relevant shortcuts (if not already backed up) and binds this shell's shortcuts
    pub fn backup_and_bind(&self, mode: &str) -> DynResult<()> {
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
