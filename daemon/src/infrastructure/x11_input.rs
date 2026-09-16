use std::ptr;

#[link(name = "X11")]
#[link(name = "Xtst")]
extern "C" {
    fn XOpenDisplay(display_name: *const libc::c_char) -> *mut libc::c_void;
    fn XCloseDisplay(display: *mut libc::c_void) -> libc::c_int;
    fn XFlush(display: *mut libc::c_void) -> libc::c_int;
    fn XTestFakeKeyEvent(
        display: *mut libc::c_void,
        keycode: libc::c_uint,
        is_press: libc::c_int,
        delay: libc::c_ulong,
    ) -> libc::c_int;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaKey {
    PlayPause = 172,
    Next = 171,
    Previous = 173,
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
}
