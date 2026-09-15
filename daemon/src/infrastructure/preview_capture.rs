use std::collections::HashMap;
use std::fs;
use std::io::Read;
use std::os::fd::FromRawFd;
use zbus::zvariant::{OwnedFd, Value};
use zbus::Connection;

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

    let connection = Connection::session().await?;

    let mut fds = [0i32; 2];
    unsafe {
        if libc::pipe(fds.as_mut_ptr()) != 0 {
            return Err("Failed to create pipe for screenshot".into());
        }
    }
    let mut read_file = unsafe { fs::File::from_raw_fd(fds[0]) };
    let write_owned = unsafe { std::os::fd::OwnedFd::from_raw_fd(fds[1]) };
    let zbus_fd = OwnedFd::from(write_owned);

    let options: HashMap<String, Value> = HashMap::new();

    let proxy = zbus::Proxy::new(
        &connection,
        "org.kde.KWin",
        "/org/kde/KWin/ScreenShot2",
        "org.kde.KWin.ScreenShot2",
    ).await?;

    let reply: HashMap<String, zbus::zvariant::OwnedValue> = proxy.call(
        "CaptureWindow",
        &(clean_uuid, &options, zbus_fd),
    ).await?;

    let mut raw_data = Vec::new();
    read_file.read_to_end(&mut raw_data)?;

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
    fs::write(&out_path, png_bytes)?;

    Ok(out_path)
}
