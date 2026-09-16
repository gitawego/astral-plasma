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
pub union XEvent {
    pub type_: libc::c_int,
    pub xbutton: XButtonEvent,
    pub pad: [libc::c_long; 24],
}

#[link(name = "X11")]
#[link(name = "Xtst")]
extern "C" {
    fn XOpenDisplay(display_name: *const libc::c_char) -> *mut libc::c_void;
    fn XCloseDisplay(display: *mut libc::c_void) -> libc::c_int;
    fn XFlush(display: *mut libc::c_void) -> libc::c_int;
    fn XDefaultRootWindow(display: *mut libc::c_void) -> libc::c_ulong;
    fn XInternAtom(
        display: *mut libc::c_void,
        atom_name: *const libc::c_char,
        only_if_exists: libc::c_int,
    ) -> libc::c_ulong;
    fn XGetWindowProperty(
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
    fn XFree(data: *mut libc::c_void) -> libc::c_int;
    fn XGetGeometry(
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
    fn XSendEvent(
        display: *mut libc::c_void,
        w: libc::c_ulong,
        propagate: libc::c_int,
        event_mask: libc::c_long,
        event_send: *mut XEvent,
    ) -> libc::c_int;
    fn XTestFakeKeyEvent(
        display: *mut libc::c_void,
        keycode: libc::c_uint,
        is_press: libc::c_int,
        delay: libc::c_ulong,
    ) -> libc::c_int;
}

/// Computes target click coordinates on the bottom playback bar of a Wine media player window.
pub fn calculate_wine_media_coords(action: WineMediaAction, width: u32, height: u32) -> (i32, i32) {
    let cx = (width / 2) as i32;
    let cy = (height.saturating_sub(35)) as i32;
    let x = match action {
        WineMediaAction::PlayPause => cx,
        WineMediaAction::Next => cx + 52,
        WineMediaAction::Previous => cx - 52,
    };
    (x, cy)
}

/// Locates a Wine media client window (such as NetEase Cloud Music) from `_NET_CLIENT_LIST`.
pub unsafe fn find_wine_media_window(dpy: *mut libc::c_void, target_class: &str) -> Option<libc::c_ulong> {
    let root = XDefaultRootWindow(dpy);
    let net_client_list = XInternAtom(dpy, b"_NET_CLIENT_LIST\0".as_ptr() as *const libc::c_char, 0);
    let wm_class = XInternAtom(dpy, b"WM_CLASS\0".as_ptr() as *const libc::c_char, 0);
    let wm_name = XInternAtom(dpy, b"WM_NAME\0".as_ptr() as *const libc::c_char, 0);

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

    if ret != 0 || prop.is_null() {
        return None;
    }

    let windows = prop as *const libc::c_ulong;
    let mut found = None;
    let target_lower = target_class.to_lowercase();

    for i in 0..nitems as usize {
        let win = *windows.add(i);

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
            if class_str.contains(&target_lower) {
                found = Some(win);
                break;
            }
        }

        // 2. Check WM_NAME fallback
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
            let name_str = String::from_utf8_lossy(slice).to_lowercase();
            XFree(n_prop as *mut libc::c_void);
            if name_str.contains(&target_lower) {
                found = Some(win);
                break;
            }
        }
    }

    XFree(prop as *mut libc::c_void);
    found
}

/// Sends a direct targeted click event (`XSendEvent`) to the Wine media window controls.
/// This avoids generating global X11 media keys that KDE plasma/kglobalaccel intercepts and routes to other players.
pub fn send_wine_media_action(action: WineMediaAction) -> Result<(), String> {
    unsafe {
        let dpy = XOpenDisplay(ptr::null());
        if dpy.is_null() {
            return Err("Failed to open X11 display".to_string());
        }

        let win_opt = find_wine_media_window(dpy, "cloudmusic");
        let win = match win_opt {
            Some(w) => w,
            None => {
                XCloseDisplay(dpy);
                return Err("No NetEase Cloud Music window found".to_string());
            }
        };

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
            XCloseDisplay(dpy);
            return Err("Failed to query window geometry".to_string());
        }

        let (target_x, target_y) = calculate_wine_media_coords(action, width, height);

        let mut ev = XEvent {
            xbutton: XButtonEvent {
                type_: 4, // ButtonPress
                serial: 0,
                send_event: 1,
                display: dpy,
                window: win,
                root: 0,
                subwindow: 0,
                time: 0,
                x: target_x,
                y: target_y,
                x_root: target_x,
                y_root: target_y,
                state: 0,
                button: 1, // Left click
                same_screen: 1,
            },
        };

        XSendEvent(dpy, win, 1, 4, &mut ev); // ButtonPressMask = 4
        ev.xbutton.type_ = 5; // ButtonRelease
        XSendEvent(dpy, win, 1, 8, &mut ev); // ButtonReleaseMask = 8
        XFlush(dpy);
        XCloseDisplay(dpy);
    }
    Ok(())
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
        assert_eq!(cy, 565);

        let (nx, ny) = calculate_wine_media_coords(WineMediaAction::Next, 1000, 600);
        assert_eq!(nx, 552);
        assert_eq!(ny, 565);

        let (px, py) = calculate_wine_media_coords(WineMediaAction::Previous, 1000, 600);
        assert_eq!(px, 448);
        assert_eq!(py, 565);
    }
}
