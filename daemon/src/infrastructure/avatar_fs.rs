//! Filesystem execution of the avatar import plans.
//!
//! `domain::avatar_import` decides *what* should happen (pure, fully unit
//! tested); this adapter performs the copy/removal and upholds the stored-
//! path invariant: a failed copy reports the original source, never the
//! path of a copy that does not exist.

use crate::domain::avatar_import::{plan_forget, plan_import, ForgetPlan, ImportPlan};

/// Execute an import plan: copy `src` into the config dir when needed and
/// return the path the setting should store. Never fails - an unreadable
/// source falls back to the original path (settings keep working exactly as
/// before the durable-import feature).
pub fn import_image(src: &str, kind: &str, base_dir: &str) -> Result<String, String> {
    match plan_import(src, kind, base_dir)? {
        ImportPlan::Keep(path) => Ok(path),
        ImportPlan::Copy { from, to } => {
            if let Some(parent) = std::path::Path::new(&to).parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            match std::fs::copy(&from, &to) {
                Ok(_) => Ok(to),
                Err(_) => Ok(from),
            }
        }
    }
}

/// Execute a forget plan. Returns `true` only when an owned copy was
/// actually removed; anything not owned (or already gone) is `false` and
/// leaves the filesystem untouched.
pub fn forget_import(path: &str, base_dir: &str) -> bool {
    match plan_forget(path, base_dir) {
        ForgetPlan::Skip => false,
        ForgetPlan::Remove(target) => std::fs::remove_file(&target).is_ok(),
    }
}
