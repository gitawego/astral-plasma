//! Wine windows are X11 clients. Focusing one leaves Xwayland's keyboard focus
//! on it, and KWin keeps forwarding keys there after a native (Wayland) window
//! becomes active - so typing in any native app also drives the Wine app.
//!
//! Observed on a real session: pressing Enter in a native chat box delivered
//! keycode 36 (Return) into NetEase CloudMusic, whose focused control was its
//! play/pause button, stopping the music.

use astral_plasma::infrastructure::x11_input::{is_wine_class, should_release_x11_focus};

#[test]
fn wine_window_classes_are_recognised_by_their_executable_suffix() {
    assert!(is_wine_class("cloudmusic.exe"));
    assert!(is_wine_class("CLOUDMUSIC.EXE"));
    assert!(is_wine_class("notepad.exe"));
    assert!(!is_wine_class("code"));
    assert!(!is_wine_class("ai.opencode.desktop"));
    assert!(!is_wine_class(""));
}

#[test]
fn x11_focus_is_released_only_while_a_wine_window_holds_it_but_is_not_active() {
    // The leak: Wine keeps Xwayland's focus while a native app is active.
    assert!(should_release_x11_focus("cloudmusic.exe", "ai.opencode.desktop"));
    assert!(should_release_x11_focus("cloudmusic.exe", "com.mitchellh.ghostty"));

    // The Wine window is the active window: it must keep the focus.
    assert!(!should_release_x11_focus("cloudmusic.exe", "cloudmusic.exe"));

    // A native window holds the X11 focus: nothing to release.
    assert!(!should_release_x11_focus("ghostty", "ghostty"));
    assert!(!should_release_x11_focus("", ""));
    assert!(!should_release_x11_focus("", "ai.opencode.desktop"));
}
