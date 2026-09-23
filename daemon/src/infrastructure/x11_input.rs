use std::ptr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WineMediaAction {
    PlayPause,
    Next,
    Previous,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaKey {
    PlayPause = 172,
    Next = 171,
    Previous = 173,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct XButtonEvent {
    pub type_: libc::c_int,
    pub serial: libc::c_ulong,
    pub send_event: libc::c_int,
    pub display: *mut libc::c_void,
    pub window: libc::c_ulong,
    pub root: libc::c_ulong,
    pub subwindow: libc::c_ulong,
    pub time: libc::c_ulong,
    pub x: libc::c_int,
    pub y: libc::c_int,
    pub x_root: libc::c_int,
    pub y_root: libc::c_int,
    pub state: libc::c_uint,
    pub button: libc::c_uint,
    pub same_screen: libc::c_int,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct XClientMessageEvent {
    pub type_: libc::c_int,
    pub serial: libc::c_ulong,
    pub send_event: libc::c_int,
    pub display: *mut libc::c_void,
    pub window: libc::c_ulong,
    pub message_type: libc::c_ulong,
    pub format: libc::c_int,
    pub data: [libc::c_long; 5],
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct XKeyEvent {
    pub type_: libc::c_int,
    pub serial: libc::c_ulong,
    pub send_event: libc::c_int,
    pub display: *mut libc::c_void,
    pub window: libc::c_ulong,
    pub root: libc::c_ulong,
    pub subwindow: libc::c_ulong,
    pub time: libc::c_ulong,
    pub x: libc::c_int,
    pub y: libc::c_int,
    pub x_root: libc::c_int,
    pub y_root: libc::c_int,
    pub state: libc::c_uint,
    pub keycode: libc::c_uint,
    pub same_screen: libc::c_int,
}

#[repr(C)]
pub union XEvent {
    pub type_: libc::c_int,
    pub xkey: XKeyEvent,
    pub xbutton: XButtonEvent,
    pub xclient: XClientMessageEvent,
    pub pad: [libc::c_long; 24],
}

#[link(name = "X11")]
#[link(name = "Xtst")]
extern "C" {
    pub(crate) fn XOpenDisplay(display_name: *const libc::c_char) -> *mut libc::c_void;
    pub(crate) fn XCloseDisplay(display: *mut libc::c_void) -> libc::c_int;
    pub(crate) fn XFlush(display: *mut libc::c_void) -> libc::c_int;
    pub(crate) fn XDefaultRootWindow(display: *mut libc::c_void) -> libc::c_ulong;
    pub(crate) fn XInternAtom(
        display: *mut libc::c_void,
        atom_name: *const libc::c_char,
        only_if_exists: libc::c_int,
    ) -> libc::c_ulong;
    pub(crate) fn XGetWindowProperty(
        display: *mut libc::c_void,
        w: libc::c_ulong,
        property: libc::c_ulong,
        long_offset: libc::c_long,
        long_length: libc::c_long,
        delete: libc::c_int,
        req_type: libc::c_ulong,
        actual_type_return: *mut libc::c_ulong,
        actual_format_return: *mut libc::c_int,
        nitems_return: *mut libc::c_ulong,
        bytes_after_return: *mut libc::c_ulong,
        prop_return: *mut *mut libc::c_uchar,
    ) -> libc::c_int;
    pub(crate) fn XFree(data: *mut libc::c_void) -> libc::c_int;
    pub(crate) fn XGetInputFocus(
        display: *mut libc::c_void,
        focus_return: *mut libc::c_ulong,
        revert_to_return: *mut libc::c_int,
    ) -> libc::c_int;
    pub(crate) fn XSetInputFocus(
        display: *mut libc::c_void,
        focus: libc::c_ulong,
        revert_to: libc::c_int,
        time: libc::c_ulong,
    ) -> libc::c_int;
    #[allow(dead_code)]
    pub(crate) fn XGetGeometry(
        display: *mut libc::c_void,
        d: libc::c_ulong,
        root_return: *mut libc::c_ulong,
        x_return: *mut libc::c_int,
        y_return: *mut libc::c_int,
        width_return: *mut libc::c_uint,
        height_return: *mut libc::c_uint,
        border_width_return: *mut libc::c_uint,
        depth_return: *mut libc::c_uint,
    ) -> libc::c_int;
    pub(crate) fn XSendEvent(
        display: *mut libc::c_void,
        w: libc::c_ulong,
        propagate: libc::c_int,
        event_mask: libc::c_long,
        event_send: *mut XEvent,
    ) -> libc::c_int;
    #[allow(dead_code)]
    pub(crate) fn XTranslateCoordinates(
        display: *mut libc::c_void,
        src_w: libc::c_ulong,
        dest_w: libc::c_ulong,
        src_x: libc::c_int,
        src_y: libc::c_int,
        dest_x_return: *mut libc::c_int,
        dest_y_return: *mut libc::c_int,
        child_return: *mut libc::c_ulong,
    ) -> libc::c_int;
    pub(crate) fn XTestFakeKeyEvent(
        display: *mut libc::c_void,
        keycode: libc::c_uint,
        is_press: libc::c_int,
        delay: libc::c_ulong,
    ) -> libc::c_int;
    pub(crate) fn XQueryTree(
        display: *mut libc::c_void,
        w: libc::c_ulong,
        root_return: *mut libc::c_ulong,
        parent_return: *mut libc::c_ulong,
        children_return: *mut *mut libc::c_ulong,
        nchildren_return: *mut libc::c_uint,
    ) -> libc::c_int;
    #[allow(dead_code)]
    pub(crate) fn XQueryPointer(
        display: *mut libc::c_void,
        w: libc::c_ulong,
        root_return: *mut libc::c_ulong,
        child_return: *mut libc::c_ulong,
        root_x_return: *mut libc::c_int,
        root_y_return: *mut libc::c_int,
        win_x_return: *mut libc::c_int,
        win_y_return: *mut libc::c_int,
        mask_return: *mut libc::c_uint,
    ) -> libc::c_int;
    #[allow(dead_code)]
    pub(crate) fn XSetErrorHandler(
        handler: Option<unsafe extern "C" fn(*mut libc::c_void, *mut libc::c_void) -> libc::c_int>,
    ) -> libc::c_int;
}

unsafe extern "C" fn x11_silent_error_handler(_dpy: *mut libc::c_void, _event: *mut libc::c_void) -> libc::c_int {
    0
}


/// Computes target click coordinates on the bottom playback bar of a Wine media player window.
pub fn calculate_wine_media_coords(action: WineMediaAction, width: u32, height: u32) -> (i32, i32) {
    let cx = (width / 2) as i32;
    let cy = (height.saturating_sub(50)) as i32;
    let x = match action {
        WineMediaAction::PlayPause => cx,
        WineMediaAction::Next => cx + 51,
        WineMediaAction::Previous => cx - 51,
    };
    (x, cy)
}

/// Locates a Wine media client window (such as NetEase Cloud Music) from `_NET_CLIENT_LIST`.
unsafe fn evaluate_candidate_window(
    dpy: *mut libc::c_void,
    win: libc::c_ulong,
    target_lower: &str,
    wm_class: libc::c_ulong,
    wm_name: libc::c_ulong,
) -> Option<u64> {
    let mut matches = false;
    let mut has_title = false;

    // 1. Check WM_CLASS
    let mut c_type = 0;
    let mut c_fmt = 0;
    let mut c_nitems = 0;
    let mut c_after = 0;
    let mut c_prop: *mut libc::c_uchar = ptr::null_mut();

    if XGetWindowProperty(
        dpy,
        win,
        wm_class,
        0,
        1024,
        0,
        0,
        &mut c_type,
        &mut c_fmt,
        &mut c_nitems,
        &mut c_after,
        &mut c_prop,
    ) == 0 && !c_prop.is_null() {
        let slice = std::slice::from_raw_parts(c_prop, c_nitems as usize);
        let class_str = String::from_utf8_lossy(slice).to_lowercase();
        XFree(c_prop as *mut libc::c_void);
        if class_str.contains(target_lower) {
            matches = true;
        }
    }

    // 2. Check WM_NAME
    let mut n_type = 0;
    let mut n_fmt = 0;
    let mut n_nitems = 0;
    let mut n_after = 0;
    let mut n_prop: *mut libc::c_uchar = ptr::null_mut();

    if XGetWindowProperty(
        dpy,
        win,
        wm_name,
        0,
        1024,
        0,
        0,
        &mut n_type,
        &mut n_fmt,
        &mut n_nitems,
        &mut n_after,
        &mut n_prop,
    ) == 0 && !n_prop.is_null() {
        let slice = std::slice::from_raw_parts(n_prop, n_nitems as usize);
        let name_str = String::from_utf8_lossy(slice);
        let trimmed = name_str.trim();
        if !trimmed.is_empty() {
            has_title = true;
        }
        if trimmed.to_lowercase().contains(target_lower) {
            matches = true;
        }
        XFree(n_prop as *mut libc::c_void);
    }

    if !matches {
        return None;
    }

    // 3. Check Geometry
    let mut root = 0;
    let mut x = 0;
    let mut y = 0;
    let mut width = 0;
    let mut height = 0;
    let mut border_width = 0;
    let mut depth = 0;

    if XGetGeometry(
        dpy,
        win,
        &mut root,
        &mut x,
        &mut y,
        &mut width,
        &mut height,
        &mut border_width,
        &mut depth,
    ) == 0 {
        return None;
    }

    // Filter out dummy 1x1, tooltips, and non-main helper windows
    if width < 200 || height < 200 {
        return None;
    }

    let area = (width as u64) * (height as u64);
    let title_boost = if has_title { 10_000_000 } else { 0 };
    Some(title_boost + area)
}

#[allow(dead_code)]
pub unsafe fn find_window_by_class(dpy: *mut libc::c_void, target_class: &str) -> Option<libc::c_ulong> {
    let root = XDefaultRootWindow(dpy);
    let net_client_list = XInternAtom(dpy, b"_NET_CLIENT_LIST\0".as_ptr() as *const libc::c_char, 0);
    let wm_class = XInternAtom(dpy, b"WM_CLASS\0".as_ptr() as *const libc::c_char, 0);
    let wm_name = XInternAtom(dpy, b"WM_NAME\0".as_ptr() as *const libc::c_char, 0);
    let target_lower = target_class.to_lowercase();

    let mut best_candidate: Option<(libc::c_ulong, u64)> = None;

    // Fast-path: query _NET_CLIENT_LIST
    let mut actual_type = 0;
    let mut actual_format = 0;
    let mut nitems = 0;
    let mut bytes_after = 0;
    let mut prop: *mut libc::c_uchar = ptr::null_mut();

    let ret = XGetWindowProperty(
        dpy,
        root,
        net_client_list,
        0,
        2048,
        0,
        0,
        &mut actual_type,
        &mut actual_format,
        &mut nitems,
        &mut bytes_after,
        &mut prop,
    );

    if ret == 0 && !prop.is_null() {
        let windows = prop as *const libc::c_ulong;
        for i in 0..nitems as usize {
            let win = *windows.add(i);
            if let Some(score) = evaluate_candidate_window(dpy, win, &target_lower, wm_class, wm_name) {
                if best_candidate.as_ref().map_or(true, |(_, s)| score > *s) {
                    best_candidate = Some((win, score));
                }
            }
        }
        XFree(prop as *mut libc::c_void);
    }

    // Fallback: enumerate root window hierarchy via XQueryTree
    if best_candidate.is_none() {
        let mut q_root = 0;
        let mut q_parent = 0;
        let mut children: *mut libc::c_ulong = ptr::null_mut();
        let mut nchildren = 0;

        if XQueryTree(dpy, root, &mut q_root, &mut q_parent, &mut children, &mut nchildren) != 0 && !children.is_null() {
            for i in 0..nchildren as usize {
                let win = *children.add(i);
                if let Some(score) = evaluate_candidate_window(dpy, win, &target_lower, wm_class, wm_name) {
                    if best_candidate.as_ref().map_or(true, |(_, s)| score > *s) {
                        best_candidate = Some((win, score));
                    }
                }
            }
            XFree(children as *mut libc::c_void);
        }
    }

    best_candidate.map(|(win, _)| win)
}


/// Queries the currently active window ID via `_NET_ACTIVE_WINDOW` on the root window.
#[allow(dead_code)]
pub unsafe fn get_active_window(dpy: *mut libc::c_void) -> libc::c_ulong {
    let root = XDefaultRootWindow(dpy);
    let net_active_window = XInternAtom(dpy, b"_NET_ACTIVE_WINDOW\0".as_ptr() as *const libc::c_char, 0);

    let mut actual_type = 0;
    let mut actual_format = 0;
    let mut nitems = 0;
    let mut bytes_after = 0;
    let mut prop: *mut libc::c_uchar = ptr::null_mut();

    let ret = XGetWindowProperty(
        dpy,
        root,
        net_active_window,
        0,
        1,
        0,
        0,
        &mut actual_type,
        &mut actual_format,
        &mut nitems,
        &mut bytes_after,
        &mut prop,
    );

    if ret == 0 && !prop.is_null() && nitems > 0 {
        let win = *(prop as *const libc::c_ulong);
        XFree(prop as *mut libc::c_void);
        win
    } else {
        if !prop.is_null() {
            XFree(prop as *mut libc::c_void);
        }
        0
    }
}

/// Restores focus to the specified active window via an EWMH `_NET_ACTIVE_WINDOW` client message.
#[allow(dead_code)]
pub unsafe fn restore_active_window(dpy: *mut libc::c_void, win: libc::c_ulong) {
    if win == 0 {
        return;
    }
    let root = XDefaultRootWindow(dpy);
    let net_active_window = XInternAtom(dpy, b"_NET_ACTIVE_WINDOW\0".as_ptr() as *const libc::c_char, 0);

    let mut ev = XEvent {
        xclient: XClientMessageEvent {
            type_: 33, // ClientMessage
            serial: 0,
            send_event: 1,
            display: dpy,
            window: win,
            message_type: net_active_window,
            format: 32,
            data: [2, 0, 0, 0, 0], // 2 = pager / user client
        },
    };

    let mask = (1 << 19) | (1 << 20); // SubstructureNotifyMask | SubstructureRedirectMask
    XSendEvent(dpy, root, 0, mask, &mut ev);
    XFlush(dpy);
}

/// Emits a targeted X11 KeyPress/KeyRelease event directly to the specified window.
/// This routes media keys directly into the Wine process without requiring the window to be active,
/// without moving the mouse pointer, and without triggering global desktop shortcuts.
pub fn send_window_key(win: libc::c_ulong, key: MediaKey) -> Result<(), String> {
    unsafe {
        let dpy = XOpenDisplay(ptr::null());
        if dpy.is_null() {
            return Err("Failed to open X11 display".to_string());
        }

        let root = XDefaultRootWindow(dpy);
        let keycode = key as libc::c_uint;

        let mut press_ev = XEvent {
            xkey: XKeyEvent {
                type_: 2, // KeyPress
                serial: 0,
                send_event: 1,
                display: dpy,
                window: win,
                root,
                subwindow: 0,
                time: 0,
                x: 0,
                y: 0,
                x_root: 0,
                y_root: 0,
                state: 0,
                keycode,
                same_screen: 1,
            },
        };
        XSendEvent(dpy, win, 1, 1, &mut press_ev); // KeyPressMask = 1
        XFlush(dpy);

        std::thread::sleep(std::time::Duration::from_millis(30));

        let mut release_ev = XEvent {
            xkey: XKeyEvent {
                type_: 3, // KeyRelease
                serial: 0,
                send_event: 1,
                display: dpy,
                window: win,
                root,
                subwindow: 0,
                time: 0,
                x: 0,
                y: 0,
                x_root: 0,
                y_root: 0,
                state: 0,
                keycode,
                same_screen: 1,
            },
        };
        XSendEvent(dpy, win, 1, 2, &mut release_ev); // KeyReleaseMask = 2
        XFlush(dpy);

        XCloseDisplay(dpy);
    }
    Ok(())
}

/// Is this window class a Wine (Windows) application?
///
/// Wine reports the executable as the window class, so the `.exe` suffix is the
/// one reliable marker of an X11 client that Wine owns.
pub fn is_wine_class(class: &str) -> bool {
    class.trim().to_lowercase().ends_with(".exe")
}

/// Should Xwayland's keyboard focus be handed back?
///
/// Yes when a Wine window still holds the X11 keyboard focus but some other
/// window is the active one: KWin keeps forwarding keystrokes to Xwayland's
/// focus, so otherwise typing in a native application also drives the Wine
/// application (pressing Enter in a chat box would press its play button).
pub fn should_release_x11_focus(focused_class: &str, active_class: &str) -> bool {
    is_wine_class(focused_class) && !is_wine_class(active_class)
}

/// Hand Xwayland's keyboard focus back when a Wine window is no longer active.
///
/// Called on every window activation: reads the X11 input focus, and clears it
/// when [`should_release_x11_focus`] says so. Best-effort - a machine without
/// Xwayland simply has nothing to do.
pub fn release_stale_wine_focus(active_class: &str) -> bool {
    if std::env::var_os("DISPLAY").is_none() {
        return false;
    }
    unsafe {
        let dpy = XOpenDisplay(ptr::null());
        if dpy.is_null() {
            return false;
        }
        let mut focused: libc::c_ulong = 0;
        let mut revert_to: libc::c_int = 0;
        XGetInputFocus(dpy, &mut focused, &mut revert_to);

        let focused_class = if focused == 0 {
            String::new()
        } else {
            window_class(dpy, focused).unwrap_or_default()
        };

        let released = if should_release_x11_focus(&focused_class, active_class) {
            // `None` + RevertToNone: no X11 client receives keys until KWin
            // focuses a real X11 window again.
            XSetInputFocus(dpy, 0, 0, 0);
            XFlush(dpy);
            log_release(&focused_class, active_class);
            true
        } else {
            false
        };
        XCloseDisplay(dpy);
        released
    }
}

/// Log a release, at most once every five seconds.
///
/// A Wine application can re-assert its focus right after being cleared; the
/// guard then releases it again on every tick, and an unthrottled log would
/// flood the shell's output with identical lines.
fn log_release(focused_class: &str, active_class: &str) {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static LAST_LOG_MS: AtomicU64 = AtomicU64::new(0);
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let last = LAST_LOG_MS.load(Ordering::Relaxed);
    if now_ms.saturating_sub(last) < 5_000 {
        return;
    }
    LAST_LOG_MS.store(now_ms, Ordering::Relaxed);
    eprintln!(
        "[x11] released stale Wine keyboard focus (was {focused_class:?}, active {active_class:?})"
    );
}

/// The `WM_CLASS` instance name of an X11 window, if readable.
unsafe fn window_class(dpy: *mut libc::c_void, win: libc::c_ulong) -> Option<String> {
    let wm_class = XInternAtom(dpy, b"WM_CLASS\0".as_ptr() as *const libc::c_char, 0);
    let mut actual_type = 0;
    let mut actual_format = 0;
    let mut nitems = 0;
    let mut bytes_after = 0;
    let mut prop: *mut libc::c_uchar = ptr::null_mut();

    let ret = XGetWindowProperty(
        dpy,
        win,
        wm_class,
        0,
        64,
        0,
        0,
        &mut actual_type,
        &mut actual_format,
        &mut nitems,
        &mut bytes_after,
        &mut prop,
    );
    if ret != 0 || prop.is_null() {
        return None;
    }
    let bytes = std::slice::from_raw_parts(prop, nitems as usize);
    // WM_CLASS is NUL-separated: "instance\0class\0".
    let instance = bytes
        .split(|b| *b == 0)
        .next()
        .map(|slice| String::from_utf8_lossy(slice).to_string())
        .unwrap_or_default();
    XFree(prop as *mut libc::c_void);
    Some(instance)
}

/// Sends a media action to a Wine player without moving the mouse pointer.
/// Dispatches clean targeted X11 KeyPress/KeyRelease events directly to the Wine window.
pub fn send_wine_media_action(action: WineMediaAction) -> Result<(), String> {
    let key = match action {
        WineMediaAction::PlayPause => MediaKey::PlayPause,
        WineMediaAction::Next => MediaKey::Next,
        WineMediaAction::Previous => MediaKey::Previous,
    };

    unsafe {
        let dpy = XOpenDisplay(ptr::null());
        if !dpy.is_null() {
            let win_opt = find_window_by_class(dpy, "cloudmusic");
            XCloseDisplay(dpy);
            if let Some(win) = win_opt {
                return send_window_key(win, key);
            }
        }
    }

    send_media_key(key)
}

/// Read the icon an X11 window publishes for itself (`_NET_WM_ICON`).
///
/// This is the only truthful identity source for an application that ships no
/// desktop entry (Wine reports the executable as its class), and it is what the
/// desktop's own taskbar uses in that case. Returns the raw CARDINAL data; the
/// caller decodes and caches it.
pub fn read_net_wm_icon(target_class: &str) -> Option<Vec<u32>> {
    unsafe {
        let dpy = XOpenDisplay(ptr::null());
        if dpy.is_null() {
            return None;
        }

        let result = (|| {
            let win = find_window_by_class(dpy, target_class)?;
            let atom = XInternAtom(dpy, b"_NET_WM_ICON\0".as_ptr() as *const libc::c_char, 0);
            let mut actual_type = 0;
            let mut actual_format = 0;
            let mut nitems: libc::c_ulong = 0;
            let mut bytes_after: libc::c_ulong = 0;
            let mut prop: *mut libc::c_uchar = ptr::null_mut();

            // XA_CARDINAL = 6. The length is in 32-bit units; 256x256 icons need
            // ~65k of them.
            let ret = XGetWindowProperty(
                dpy,
                win,
                atom,
                0,
                262144,
                0,
                6,
                &mut actual_type,
                &mut actual_format,
                &mut nitems,
                &mut bytes_after,
                &mut prop,
            );
            if ret != 0 || prop.is_null() {
                return None;
            }
            if actual_format != 32 || nitems == 0 {
                XFree(prop as *mut libc::c_void);
                return None;
            }
            // Format-32 properties come back as an array of `long`, not `u32`.
            let items = std::slice::from_raw_parts(prop as *const libc::c_long, nitems as usize);
            let data: Vec<u32> = items.iter().map(|v| *v as u32).collect();
            XFree(prop as *mut libc::c_void);
            Some(data)
        })();

        XCloseDisplay(dpy);
        result
    }
}

/// Queries cursor position (root_x, root_y) via XQueryPointer.
pub fn get_cursor_position() -> Option<(i32, i32)> {
    unsafe {
        let display = XOpenDisplay(ptr::null());
        if display.is_null() {
            return None;
        }
        let root = XDefaultRootWindow(display);
        let mut root_return = 0;
        let mut child_return = 0;
        let mut root_x = 0;
        let mut root_y = 0;
        let mut win_x = 0;
        let mut win_y = 0;
        let mut mask = 0;
        let res = XQueryPointer(
            display,
            root,
            &mut root_return,
            &mut child_return,
            &mut root_x,
            &mut root_y,
            &mut win_x,
            &mut win_y,
            &mut mask,
        );
        XCloseDisplay(display);
        if res != 0 {
            Some((root_x, root_y))
        } else {
            None
        }
    }
}

unsafe fn is_wine_system_proc(name: &str) -> bool {
    let lower = name.to_lowercase();
    lower.contains("explorer.exe")
        || lower.contains("services.exe")
        || lower.contains("winedevice.exe")
        || lower.contains("svchost.exe")
        || lower.contains("plugplay.exe")
        || lower.contains("rpcss.exe")
        || lower.contains("conhost.exe")
        || lower.contains("wineserver")
}

unsafe fn scan_active_wine_client(
    dpy: *mut libc::c_void,
    wm_class: libc::c_ulong,
    wm_name: libc::c_ulong,
    net_wm_name: libc::c_ulong,
) -> Option<(String, Option<String>)> {
    let root = XDefaultRootWindow(dpy);
    let net_client_list = XInternAtom(dpy, b"_NET_CLIENT_LIST\0".as_ptr() as *const libc::c_char, 0);

    let get_str = |win: libc::c_ulong, atom: libc::c_ulong| -> Option<String> {
        let mut p_type = 0;
        let mut p_fmt = 0;
        let mut p_nitems = 0;
        let mut p_after = 0;
        let mut p_prop: *mut libc::c_uchar = ptr::null_mut();
        if XGetWindowProperty(
            dpy,
            win,
            atom,
            0,
            1024,
            0,
            0,
            &mut p_type,
            &mut p_fmt,
            &mut p_nitems,
            &mut p_after,
            &mut p_prop,
        ) == 0 && !p_prop.is_null() {
            let slice = std::slice::from_raw_parts(p_prop, p_nitems as usize);
            let s = String::from_utf8_lossy(slice).trim().to_string();
            XFree(p_prop as *mut libc::c_void);
            if !s.is_empty() {
                return Some(s);
            }
        }
        None
    };

    // 1. Check _NET_CLIENT_LIST
    let mut actual_type = 0;
    let mut actual_format = 0;
    let mut nitems = 0;
    let mut bytes_after = 0;
    let mut prop: *mut libc::c_uchar = ptr::null_mut();

    if XGetWindowProperty(
        dpy,
        root,
        net_client_list,
        0,
        2048,
        0,
        0,
        &mut actual_type,
        &mut actual_format,
        &mut nitems,
        &mut bytes_after,
        &mut prop,
    ) == 0 && !prop.is_null() {
        let windows = prop as *const libc::c_ulong;
        for i in 0..nitems as usize {
            let win = *windows.add(i);
            if let Some(c) = get_str(win, wm_class) {
                let lower = c.to_lowercase();
                if lower.contains(".exe") && !is_wine_system_proc(&lower) {
                    let t = get_str(win, net_wm_name).or_else(|| get_str(win, wm_name));
                    XFree(prop as *mut libc::c_void);
                    return Some((c, t));
                }
            }
        }
        XFree(prop as *mut libc::c_void);
    }

    // 2. Check XQueryTree
    let mut q_root = 0;
    let mut q_parent = 0;
    let mut children: *mut libc::c_ulong = ptr::null_mut();
    let mut nchildren = 0;
    if XQueryTree(dpy, root, &mut q_root, &mut q_parent, &mut children, &mut nchildren) != 0 && !children.is_null() {
        for i in 0..nchildren as usize {
            let win = *children.add(i);
            if let Some(c) = get_str(win, wm_class) {
                let lower = c.to_lowercase();
                if lower.contains(".exe") && !is_wine_system_proc(&lower) {
                    let t = get_str(win, net_wm_name).or_else(|| get_str(win, wm_name));
                    XFree(children as *mut libc::c_void);
                    return Some((c, t));
                }
            }
        }
        XFree(children as *mut libc::c_void);
    }

    // 3. Fallback: scan /proc for running wine .exe processes
    if let Ok(entries) = std::fs::read_dir("/proc") {
        for entry in entries.flatten() {
            let p = entry.path();
            if let Some(fname) = p.file_name().and_then(|f| f.to_str()) {
                if fname.chars().all(|c| c.is_ascii_digit()) {
                    let cmdline_file = p.join("cmdline");
                    if let Ok(data) = std::fs::read(cmdline_file) {
                        let cmd = String::from_utf8_lossy(&data).replace('\0', " ");
                        let cmd_lower = cmd.to_lowercase();
                        if cmd_lower.contains(".exe") {
                            for part in cmd.split_whitespace() {
                                let part_lower = part.to_lowercase();
                                if part_lower.contains(".exe") && !is_wine_system_proc(&part_lower) {
                                    let exe_name = std::path::Path::new(part.replace('\\', "/").as_str())
                                        .file_name()
                                        .map(|s| s.to_string_lossy().to_string())
                                        .unwrap_or_else(|| part.to_string());
                                    return Some((exe_name, None));
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    None
}

/// Inspects a candidate window or scans running Wine processes/windows to determine the client application.
pub fn query_x11_window_class_and_title(win_id: u64) -> (Option<String>, Option<String>) {
    unsafe {
        let dpy = XOpenDisplay(ptr::null());
        if dpy.is_null() {
            return (None, None);
        }
        XSetErrorHandler(Some(x11_silent_error_handler));

        let wm_class = XInternAtom(dpy, b"WM_CLASS\0".as_ptr() as *const libc::c_char, 0);
        let wm_name = XInternAtom(dpy, b"WM_NAME\0".as_ptr() as *const libc::c_char, 0);
        let net_wm_name = XInternAtom(dpy, b"_NET_WM_NAME\0".as_ptr() as *const libc::c_char, 0);

        let get_str_prop = |win: libc::c_ulong, atom: libc::c_ulong| -> Option<String> {
            let mut p_type = 0;
            let mut p_fmt = 0;
            let mut p_nitems = 0;
            let mut p_after = 0;
            let mut p_prop: *mut libc::c_uchar = ptr::null_mut();
            if XGetWindowProperty(
                dpy,
                win,
                atom,
                0,
                1024,
                0,
                0,
                &mut p_type,
                &mut p_fmt,
                &mut p_nitems,
                &mut p_after,
                &mut p_prop,
            ) == 0 && !p_prop.is_null() {
                let slice = std::slice::from_raw_parts(p_prop, p_nitems as usize);
                let s = String::from_utf8_lossy(slice).trim().to_string();
                XFree(p_prop as *mut libc::c_void);
                if !s.is_empty() {
                    return Some(s);
                }
            }
            None
        };

        let mut class = if win_id != 0 {
            get_str_prop(win_id as libc::c_ulong, wm_class)
        } else {
            None
        };
        let mut title = if win_id != 0 {
            get_str_prop(win_id as libc::c_ulong, net_wm_name).or_else(|| get_str_prop(win_id as libc::c_ulong, wm_name))
        } else {
            None
        };

        // If the window belongs to Wine's explorer.exe, or win_id was 0, discover the underlying Wine app
        if class.as_ref().map_or(win_id == 0, |c| c.to_lowercase().contains("explorer.exe")) {
            if let Some((app_class, app_title)) = scan_active_wine_client(dpy, wm_class, wm_name, net_wm_name) {
                class = Some(app_class);
                if title.is_none() {
                    title = app_title;
                }
            }
        }

        XCloseDisplay(dpy);
        (class, title)
    }
}

/// Emits an X11 XTest KeyPress and KeyRelease sequence for the given media key.
pub fn send_media_key(key: MediaKey) -> Result<(), String> {
    unsafe {
        let dpy = XOpenDisplay(ptr::null());
        if dpy.is_null() {
            return Err("Failed to open X11 display".to_string());
        }

        let keycode = key as libc::c_uint;
        XTestFakeKeyEvent(dpy, keycode, 1, 0);
        XTestFakeKeyEvent(dpy, keycode, 0, 0);
        XFlush(dpy);
        XCloseDisplay(dpy);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_media_key_enum_values() {
        assert_eq!(MediaKey::PlayPause as u32, 172);
        assert_eq!(MediaKey::Next as u32, 171);
        assert_eq!(MediaKey::Previous as u32, 173);
    }

    #[test]
    fn test_wine_media_action_coords() {
        let (cx, cy) = calculate_wine_media_coords(WineMediaAction::PlayPause, 1000, 600);
        assert_eq!(cx, 500);
        assert_eq!(cy, 550);

        let (nx, ny) = calculate_wine_media_coords(WineMediaAction::Next, 1000, 600);
        assert_eq!(nx, 551);
        assert_eq!(ny, 550);

        let (px, py) = calculate_wine_media_coords(WineMediaAction::Previous, 1000, 600);
        assert_eq!(px, 449);
        assert_eq!(py, 550);
    }
}
