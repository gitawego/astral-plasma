//! Durable import of user-configured avatar images into the app config dir.
//!
//! Settings stores avatar images by path (the dashboard system-host card and
//! the media tab). A path in `~/Downloads` dies with the next cleanup, so
//! every configured image is copied into `$XDG_CONFIG_HOME/astral-plasma/`
//! and only that durable copy is stored. This module owns the *pure* path
//! pipeline - normalization, boundary-safe containment, target naming, and
//! ownership recognition; filesystem execution lives in
//! `infrastructure::avatar_fs`, CLI wiring in `interfaces::cli`.
//!
//! Two invariants are enforced here:
//!
//! 1. A stored path is always readable: on a failed copy the *original*
//!    source path is stored, never the path of a copy that does not exist.
//! 2. Deletion is ownership-guarded: only files this feature generated
//!    (`<kind>-avatar.<ext>` directly inside the config dir) can ever be
//!    removed on reset.

/// Avatar slots that participate in the durable import. Doubles as the
/// allowlist for the path-influencing `kind` argument.
pub const AVATAR_KINDS: &[&str] = &["host", "media"];

/// Trim whitespace and strip a `file://` scheme so QML URLs, file-dialog
/// picks, and pasted shell paths all compare and store as plain paths.
pub fn normalize_local_path(path: &str) -> String {
    let trimmed = path.trim();
    trimmed
        .strip_prefix("file://")
        .map(|rest| rest.to_string())
        .unwrap_or_else(|| trimmed.to_string())
}

/// Boundary-safe containment: `dir` itself or a path *inside* it. A sibling
/// directory sharing the name prefix (`astral-plasmaEVIL/`) must not match.
pub fn is_path_in_dir(path: &str, dir: &str) -> bool {
    let p = normalize_local_path(path);
    let d = normalize_local_path(dir);
    if p.is_empty() || d.is_empty() {
        return false;
    }
    let d = d.trim_end_matches('/');
    p == d || p.starts_with(&format!("{d}/"))
}

/// Lowercased extension (with dot) of the *basename*; `""` when absent or
/// when the basename only leads with a dot (`.hidden` is not an extension).
pub fn path_extension(path: &str) -> String {
    let p = normalize_local_path(path);
    let base_start = p.rfind('/').map(|i| i + 1).unwrap_or(0);
    let base = &p[base_start..];
    match base.rfind('.') {
        Some(i) if i > 0 => base[i..].to_lowercase(),
        _ => String::new(),
    }
}

/// Where a configured image should live after import:
/// already inside `base_dir` stays untouched; anything else becomes
/// `<base_dir>/<kind>-avatar<ext>` (extension preserved, lowercased).
pub fn import_target_path(src: &str, kind: &str, base_dir: &str) -> String {
    let s = normalize_local_path(src);
    if s.is_empty() {
        return String::new();
    }
    if is_path_in_dir(&s, base_dir) {
        return s;
    }
    let base = normalize_local_path(base_dir);
    format!("{}/{kind}-avatar{}", base.trim_end_matches('/'), path_extension(&s))
}

/// True only for files this feature generated: `<kind>-avatar[.ext]`
/// *directly* inside `base_dir`. Everything else in the config dir (and any
/// path outside it) is off-limits for deletion.
pub fn is_owned_import_path(path: &str, base_dir: &str) -> bool {
    let p = normalize_local_path(path);
    let base = normalize_local_path(base_dir);
    if base.is_empty() || !is_path_in_dir(&p, &base) {
        return false;
    }
    let base = base.trim_end_matches('/');
    let rel = &p[base.len()..];
    let name = match rel.strip_prefix('/') {
        Some(n) => n,
        None => return false, // path == base dir itself
    };
    if name.is_empty() || name.contains('/') {
        return false;
    }
    AVATAR_KINDS.iter().any(|kind| {
        let prefix = format!("{kind}-avatar");
        match name.strip_prefix(prefix.as_str()) {
            Some(rest) => {
                rest.is_empty()
                    || (rest.starts_with('.')
                        && rest.len() > 1
                        && rest[1..].chars().all(|c| c.is_ascii_alphanumeric()))
            }
            None => false,
        }
    })
}

/// Outcome of planning an import for one configured avatar path.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ImportPlan {
    /// Nothing to copy - store this path as-is (already durable, or blank
    /// reset value).
    Keep(String),
    /// Copy `from` to `to`; if the copy fails, `from` is stored instead.
    Copy { from: String, to: String },
}

/// Outcome of planning a reset-time deletion.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ForgetPlan {
    /// Not ours to delete - refuse.
    Skip,
    /// Owned durable copy - remove it.
    Remove(String),
}

/// Decide what `config import-image <src> <kind> [dir]` should do.
///
/// `kind` is path-influencing input and must come from the allowlist;
/// anything else is rejected before it can reach the filesystem.
pub fn plan_import(src: &str, kind: &str, base_dir: &str) -> Result<ImportPlan, String> {
    if !AVATAR_KINDS.contains(&kind) {
        return Err(format!("unknown avatar kind '{kind}' (expected one of {AVATAR_KINDS:?})"));
    }
    let s = normalize_local_path(src);
    if s.is_empty() {
        return Ok(ImportPlan::Keep(String::new()));
    }
    let target = import_target_path(&s, kind, base_dir);
    if target == s {
        Ok(ImportPlan::Keep(s))
    } else {
        Ok(ImportPlan::Copy { from: s, to: target })
    }
}

/// Decide what `config forget-image <path> [dir]` should do. Ownership is
/// re-verified on every call - the caller never gets a blanket delete.
pub fn plan_forget(path: &str, base_dir: &str) -> ForgetPlan {
    if is_owned_import_path(path, base_dir) {
        ForgetPlan::Remove(normalize_local_path(path))
    } else {
        ForgetPlan::Skip
    }
}
