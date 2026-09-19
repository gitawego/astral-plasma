use std::collections::HashMap;
use std::fs;
use std::io::Read;
use std::os::fd::FromRawFd;
use std::path::{Path, PathBuf};
use zbus::zvariant::{OwnedFd, Value};
use zbus::Connection;

pub fn generate_desktop_entry(exe_path: &Path) -> String {
    format!(
        "[Desktop Entry]\nVersion=1.5\nType=Application\nNoDisplay=true\nName=Astral Plasma\nExec={}\nX-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2,org.kde.kwin.Screenshot\nX-KDE-Wayland-Interfaces=org_kde_plasma_window_management,zkde_screencast_unstable_v1\n",
        exe_path.display()
    )
}

pub fn get_default_applications_dir() -> PathBuf {
    if let Ok(home) = std::env::var("HOME") {
        PathBuf::from(home).join(".local/share/applications")
    } else {
        PathBuf::from("/tmp")
    }
}

pub fn install_desktop_entry_with_notification(
    custom_dir: Option<&Path>,
    custom_exe: Option<&Path>,
) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    let app_dir = custom_dir
        .map(Path::to_path_buf)
        .unwrap_or_else(get_default_applications_dir);

    let exe_path = match custom_exe {
        Some(p) => p.to_path_buf(),
        None => std::env::current_exe().unwrap_or_else(|_| PathBuf::from("astral-plasma")),
    };

    let canonical_exe = exe_path.canonicalize().unwrap_or(exe_path);
    let desktop_path = app_dir.join("astral-plasma.desktop");
    let expected_content = generate_desktop_entry(&canonical_exe);

    if desktop_path.exists() {
        if let Ok(existing) = fs::read_to_string(&desktop_path) {
            if existing == expected_content {
                return Ok(false);
            }
        }
    }

    fs::create_dir_all(&app_dir)?;
    fs::write(&desktop_path, &expected_content)?;

    // Ensure backward-compatible symlink in the binary's directory
    if let Some(parent) = canonical_exe.parent() {
        let legacy_symlink = parent.join("caelestia-daemon");
        if !legacy_symlink.exists() {
            #[cfg(unix)]
            let _ = std::os::unix::fs::symlink(&canonical_exe, &legacy_symlink);
        }
    }

    eprintln!(
        "[astral-plasma] Notice: Registered KWin screenshot authorization entry: {}",
        desktop_path.display()
    );

    // Notify user via desktop notification
    let _ = std::process::Command::new("notify-send")
        .args(&[
            "-a",
            "Astral Plasma",
            "-i",
            "security-high",
            "Astral Plasma Authorization",
            "Registered KWin screenshot authorization for live window previews. It will be removed automatically when Astral Plasma stops.",
        ])
        .spawn();

    let _ = std::process::Command::new("kbuildsycoca6").output();

    Ok(true)
}

pub fn remove_desktop_entry(
    custom_dir: Option<&Path>,
) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    let app_dir = custom_dir
        .map(Path::to_path_buf)
        .unwrap_or_else(get_default_applications_dir);

    let target_astral = app_dir.join("astral-plasma.desktop");
    let target_legacy = app_dir.join("caelestia-daemon.desktop");

    let mut removed = false;

    if target_astral.exists() {
        if fs::remove_file(&target_astral).is_ok() {
            eprintln!(
                "[astral-plasma] Notice: Removed KWin screenshot authorization entry: {}",
                target_astral.display()
            );
            removed = true;
        }
    }

    if target_legacy.exists() {
        if fs::remove_file(&target_legacy).is_ok() {
            eprintln!(
                "[astral-plasma] Notice: Removed legacy authorization entry: {}",
                target_legacy.display()
            );
            removed = true;
        }
    }

    if removed {
        let _ = std::process::Command::new("kbuildsycoca6").output();
    }

    Ok(removed)
}

pub fn get_target_path(win_uuid: &str, slot: &str) -> String {
    let clean_uuid = win_uuid.trim_matches(|c| c == '{' || c == '}');
    format!("/tmp/caelestia_preview_{}_{}.png", clean_uuid, slot)
}

pub fn get_next_slot(win_uuid: &str) -> &'static str {
    let p0 = get_target_path(win_uuid, "0");
    let p1 = get_target_path(win_uuid, "1");

    let m0 = fs::metadata(&p0).ok().and_then(|m| m.modified().ok());
    let m1 = fs::metadata(&p1).ok().and_then(|m| m.modified().ok());

    match (m0, m1) {
        (None, _) => "0",
        (Some(_), None) => "1",
        (Some(t0), Some(t1)) => {
            if t0 <= t1 {
                "0"
            } else {
                "1"
            }
        }
    }
}

pub fn process_bgra_to_png(
    raw: &[u8],
    width: u32,
    height: u32,
    stride: u32,
    target_width: u32,
) -> Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>> {
    if width == 0 || height == 0 || target_width == 0 {
        return Err("Invalid image dimensions".into());
    }

    let computed_h = (target_width as u64 * height as u64) / width as u64;
    let target_height = if height < 40 {
        computed_h.max(1) as u32
    } else {
        computed_h.clamp(40, 260) as u32
    };
    let mut rgba_img = image::RgbaImage::new(target_width, target_height);

    for y in 0..target_height {
        let src_y = ((y as u64 * height as u64) / target_height as u64).min((height - 1) as u64) as u32;
        let row_offset = (src_y * stride) as usize;
        for x in 0..target_width {
            let src_x = ((x as u64 * width as u64) / target_width as u64).min((width - 1) as u64) as u32;
            let px_offset = row_offset + (src_x * 4) as usize;
            if px_offset + 3 < raw.len() {
                let b = raw[px_offset];
                let g = raw[px_offset + 1];
                let r = raw[px_offset + 2];
                let a = raw[px_offset + 3];
                rgba_img.put_pixel(x, y, image::Rgba([r, g, b, a]));
            }
        }
    }

    let mut png_bytes = Vec::new();
    rgba_img.write_to(&mut std::io::Cursor::new(&mut png_bytes), image::ImageFormat::Png)?;
    Ok(png_bytes)
}

async fn do_capture(
    proxy: &zbus::Proxy<'_>,
    clean_uuid: &str,
    options: &HashMap<String, Value<'_>>,
) -> Result<(HashMap<String, zbus::zvariant::OwnedValue>, Vec<u8>), Box<dyn std::error::Error + Send + Sync>> {
    let mut fds = [0i32; 2];
    unsafe {
        if libc::pipe(fds.as_mut_ptr()) != 0 {
            return Err("Failed to create pipe for screenshot".into());
        }
    }
    let mut read_file = unsafe { fs::File::from_raw_fd(fds[0]) };
    let write_owned = unsafe { std::os::fd::OwnedFd::from_raw_fd(fds[1]) };
    let zbus_fd = OwnedFd::from(write_owned);

    let reply: HashMap<String, zbus::zvariant::OwnedValue> = proxy.call(
        "CaptureWindow",
        &(clean_uuid, options, zbus_fd),
    ).await?;

    let mut raw_data = Vec::new();
    read_file.read_to_end(&mut raw_data)?;
    Ok((reply, raw_data))
}

pub async fn capture_window(
    win_uuid: &str,
    target_width: u32,
    slot: Option<&str>,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let clean_uuid = win_uuid.trim_matches(|c| c == '{' || c == '}');
    let effective_slot = match slot {
        Some(s) if !s.is_empty() => s,
        _ => get_next_slot(clean_uuid),
    };

    // Preemptively ensure desktop entry is registered
    let _ = install_desktop_entry_with_notification(None, None);

    let connection = Connection::session().await?;

    let options: HashMap<String, Value> = HashMap::new();

    let proxy = zbus::Proxy::new(
        &connection,
        "org.kde.KWin",
        "/org/kde/KWin/ScreenShot2",
        "org.kde.KWin.ScreenShot2",
    ).await?;

    let (reply, raw_data) = match do_capture(&proxy, clean_uuid, &options).await {
        Ok(res) => res,
        Err(e) => {
            let err_str = e.to_string();
            if err_str.contains("NoAuthorized") || err_str.contains("not authorized") {
                // Re-register desktop entry and notify user, then retry once
                let _ = install_desktop_entry_with_notification(None, None);
                let _ = std::process::Command::new("kbuildsycoca6").output();
                do_capture(&proxy, clean_uuid, &options).await?
            } else {
                return Err(e);
            }
        }
    };

    if raw_data.is_empty() {
        return Err("No pixel data received from KWin".into());
    }

    use std::ops::Deref;
    let width = reply
        .get("width")
        .and_then(|v| match v.deref() {
            Value::I32(i) => Some(*i as u32),
            Value::U32(u) => Some(*u),
            _ => None,
        })
        .unwrap_or(0);

    let height = reply
        .get("height")
        .and_then(|v| match v.deref() {
            Value::I32(i) => Some(*i as u32),
            Value::U32(u) => Some(*u),
            _ => None,
        })
        .unwrap_or(0);

    let stride = reply
        .get("stride")
        .and_then(|v| match v.deref() {
            Value::I32(i) => Some(*i as u32),
            Value::U32(u) => Some(*u),
            _ => None,
        })
        .unwrap_or(width * 4);

    let png_bytes = process_bgra_to_png(&raw_data, width, height, stride, target_width)?;
    let out_path = get_target_path(clean_uuid, effective_slot);
    let tmp_path = format!("{}.tmp.{}", out_path, std::process::id());
    fs::write(&tmp_path, png_bytes)?;
    fs::rename(&tmp_path, &out_path)?;

    Ok(out_path)
}
