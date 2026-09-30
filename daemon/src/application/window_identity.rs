//! One identity for a window, whichever source produced it.
//!
//! The compositor's initial query, a pushed window list and a focus change all
//! describe the same window, and identity resolution had drifted between them:
//! the pushed list also extracted the app's own `_NET_WM_ICON` while the initial
//! query returned the desktop-entry icon only. A Proton/Steam game therefore
//! started the session with a generic window glyph and only picked up its real
//! icon after some unrelated window event - the taskbar looked like it was hiding
//! a running application.
//!
//! Everything that builds a window's identity goes through here, so an identity
//! fix applies to every source at once.

use crate::domain::app_identity::AppIdentityIndex;
use crate::domain::meta_resolver::resolve_window_meta_with;
use crate::domain::model::WindowMeta;
use crate::infrastructure::window_icons;

/// Identity of a window, using the window's own icon when nothing better resolved.
pub fn resolve_window_identity(
    index: Option<&AppIdentityIndex>,
    title: &str,
    cls: &str,
    app: &str,
    krunner_icon: &str,
) -> WindowMeta {
    let mut meta = resolve_window_meta_with(index, title, cls, app, krunner_icon);
    // The icon the window publishes for itself is its only truthful identity when
    // no desktop entry supplied one (see `window_icons`).
    if let Some(icon) = window_icons::resolve_window_icon(cls, &meta.icon_name) {
        meta.icon_name = icon.to_string_lossy().to_string();
    }
    meta
}
