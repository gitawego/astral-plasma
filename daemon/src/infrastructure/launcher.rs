//! Application launching and enumeration.
//!
//! Both directions are driven by the same desktop-entry data the rest of the
//! desktop uses - there is no per-application branch anywhere in this module:
//!
//! * [`DesktopLauncherAdapter::launch`] turns a target into a [`LaunchPlan`].
//!   A desktop id is resolved by the system's own entry resolver, a URI is
//!   handed to its scheme handler. Nothing here knows the name of any app.
//! * [`DesktopLauncherAdapter::list_apps`] reuses
//!   [`AppIdentityIndex::load_from`], so the list is exactly the set of
//!   installed applications - including nested entries such as Wine programs
//!   and Flatpak exports - parsed once, by one parser.

use crate::domain::app_identity::{AppIdentityIndex, DesktopApp};
use crate::domain::ports::{AppInfo, AppLauncherPort, DynResult};
use std::path::PathBuf;
use std::process::Command;

/// How a launch target should be resolved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LaunchPlan {
    /// A URI (`lutris:rungame/...`): handed to the handler registered for its
    /// scheme. The scheme is a protocol, not application knowledge.
    Uri(String),
    /// A desktop-entry id: resolved by the system's own entry resolver.
    DesktopEntry(String),
}

/// Decide how to launch `target` from its form alone.
///
/// A desktop id is passed through exactly as given: an id may legitimately
/// contain `.desktop` (`ai.opencode.desktop` is the name of OpenCode's entry),
/// so trimming the suffix here would corrupt it. The executor asks the
/// system's resolver for the variants instead.
pub fn resolve_launch_plan(target: &str) -> Option<LaunchPlan> {
    let trimmed = target.trim();
    if trimmed.is_empty() {
        return None;
    }
    if uri_scheme(trimmed).is_some() {
        return Some(LaunchPlan::Uri(trimmed.to_string()));
    }
    Some(LaunchPlan::DesktopEntry(trimmed.to_string()))
}

/// The URI scheme of `target`, per RFC 3986: an alphabetic first character
/// followed by letters, digits, `+`, `-` or `.`. A single letter is rejected so
/// a Windows path (`C:\...`) is not mistaken for a scheme.
fn uri_scheme(target: &str) -> Option<&str> {
    let (scheme, _) = target.split_once(':')?;
    if scheme.len() < 2 {
        return None;
    }
    let mut chars = scheme.chars();
    if !chars.next()?.is_ascii_alphabetic() {
        return None;
    }
    if !chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.')) {
        return None;
    }
    Some(scheme)
}

/// Map an indexed desktop entry to the launcher's view of it.
pub fn app_info_from_entry(entry: &DesktopApp) -> AppInfo {
    AppInfo {
        name: entry.name.clone(),
        desktop_file: format!("{}.desktop", entry.desktop_id),
        icon: entry.icon.clone(),
        comment: entry.comment.clone(),
        exec: entry.exec.clone(),
    }
}

pub struct DesktopLauncherAdapter;

impl DesktopLauncherAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl Default for DesktopLauncherAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl AppLauncherPort for DesktopLauncherAdapter {
    fn launch(&self, target: &str) -> DynResult<()> {
        let Some(plan) = resolve_launch_plan(target) else {
            return Ok(());
        };

        match plan {
            LaunchPlan::Uri(uri) => {
                // The desktop environment dispatches the URI to whichever
                // application registered that scheme.
                let _ = Command::new("xdg-open").arg(&uri).spawn();
            }
            LaunchPlan::DesktopEntry(id) => {
                // The system's desktop-entry resolver decides what the id means
                // (a normal app, a Flatpak export, a Wine program...). Both the
                // bare id and the `.desktop`-suffixed form are offered because
                // an id may itself end in `.desktop`.
                let bare = id.strip_suffix(".desktop").unwrap_or(&id).to_string();
                let with_suffix = format!("{bare}.desktop");
                let mut candidates = vec![id.clone(), bare.clone(), with_suffix];
                candidates.dedup();
                for candidate in &candidates {
                    if let Ok(mut child) = Command::new("gtk-launch").arg(candidate).spawn() {
                        if let Ok(status) = child.wait() {
                            if status.success() {
                                return Ok(());
                            }
                        }
                    }
                }
                // Direct execution fallback for bare commands.
                for cmd in [id.as_str(), bare.as_str(), &id.to_lowercase()] {
                    if !cmd.is_empty() && Command::new(cmd).spawn().is_ok() {
                        return Ok(());
                    }
                }
            }
        }

        Ok(())
    }

    fn list_apps(&self) -> DynResult<Vec<AppInfo>> {
        let mut apps: Vec<AppInfo> = AppIdentityIndex::load_from(&Self::search_dirs())
            .entries()
            .iter()
            .map(|entry| app_info_from_entry(entry))
            .collect();
        apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        Ok(apps)
    }
}

impl DesktopLauncherAdapter {
    /// Directories searched for launcher entries, in precedence order.
    fn search_dirs() -> Vec<PathBuf> {
        AppIdentityIndex::search_dirs()
    }
}
