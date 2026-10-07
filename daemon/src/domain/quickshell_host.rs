//! Hosting QtWebEngine in a stock Quickshell.
//!
//! Stock Quickshell cannot construct a WebEngineView: QtWebEngine must be
//! initialised before QGuiApplication, and Chromium needs argv[0], neither of
//! which Quickshell provides (upstream quickshell-mirror/quickshell#298).
//! scripts/install-quickshell-webengine-shim.sh builds a small LD_PRELOAD
//! library that supplies both at run time, so the *unpatched* system Quickshell
//! can host the embedded DSH web view. This module resolves that library so
//! astral-plasma run can pass it to the shell it starts: no root, no rebuild.

use std::env;
use std::path::{Path, PathBuf};

use super::branding;

/// Overrides the shim path. Empty or "0" disables the shim entirely.
pub const PRELOAD_ENV: &str = "ASTRAL_QUICKSHELL_PRELOAD";

/// The user-local shim installed by the helper script.
pub fn default_preload_path() -> PathBuf {
    branding::home_dir().join(".local/lib/astral-plasma/libquickshell-webengine-shim.so")
}

/// The LD_PRELOAD library to give the launched Quickshell, if any.
///
/// An explicit PRELOAD_ENV wins (and disables when empty or "0"); otherwise the
/// user-local shim is used when present; otherwise nothing is preloaded.
pub fn preload_library() -> Option<PathBuf> {
    preload_library_from(
        env::var(PRELOAD_ENV).ok(),
        &default_preload_path(),
        |path| path.exists(),
    )
}

fn preload_library_from(
    override_value: Option<String>,
    default_path: &Path,
    exists: impl Fn(&Path) -> bool,
) -> Option<PathBuf> {
    if let Some(value) = override_value {
        let trimmed = value.trim();
        if trimmed.is_empty() || trimmed == "0" {
            return None;
        }
        let path = PathBuf::from(trimmed);
        return exists(&path).then_some(path);
    }
    exists(default_path).then(|| default_path.to_path_buf())
}

/// The value to set for LD_PRELOAD, keeping any library the user already had
/// (the shim must not shadow an existing preload).
pub fn preload_env_value(shim: &Path, existing: Option<&str>) -> String {
    match existing.map(str::trim).filter(|value| !value.is_empty()) {
        Some(previous) => format!("{}:{}", shim.display(), previous),
        None => shim.display().to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn explicit_override_wins_when_present() {
        let explicit = PathBuf::from("/tmp/explicit.so");
        let default = PathBuf::from("/tmp/default.so");
        let got = preload_library_from(Some(explicit.display().to_string()), &default, |_| true);
        assert_eq!(got, Some(explicit));
    }

    #[test]
    fn missing_override_disables_the_preload() {
        let default = PathBuf::from("/tmp/default.so");
        assert_eq!(
            preload_library_from(Some("/tmp/nope.so".into()), &default, |_| false),
            None
        );
    }

    #[test]
    fn empty_or_zero_override_disables_even_when_default_exists() {
        let default = PathBuf::from("/tmp/default.so");
        for value in ["", "   ", "0"] {
            assert_eq!(
                preload_library_from(Some(value.into()), &default, |_| true),
                None,
                "override {value:?} must disable the shim"
            );
        }
    }

    #[test]
    fn default_is_used_when_it_exists() {
        let default = PathBuf::from("/tmp/default.so");
        assert_eq!(preload_library_from(None, &default, |_| true), Some(default));
    }

    #[test]
    fn nothing_is_preloaded_when_absent() {
        let default = PathBuf::from("/tmp/default.so");
        assert_eq!(preload_library_from(None, &default, |_| false), None);
    }

    #[test]
    fn preload_env_value_preserves_an_existing_preload() {
        let shim = PathBuf::from("/home/u/.local/lib/astral-plasma/libquickshell-webengine-shim.so");
        assert_eq!(
            preload_env_value(&shim, Some("/opt/other.so")),
            format!("{}:/opt/other.so", shim.display())
        );
        assert_eq!(preload_env_value(&shim, None), shim.display().to_string());
        assert_eq!(preload_env_value(&shim, Some("  ")), shim.display().to_string());
    }
}
