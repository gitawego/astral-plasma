//! Window icons for applications that ship no desktop entry.
//!
//! Wine applications (and other X11 clients without an installed entry) publish
//! their own icon through `_NET_WM_ICON`, which is the only truthful source for
//! their identity: identity resolution is data-driven, and a generic Wine glyph
//! is not the application's icon.

use crate::domain::branding;
use std::fs;
use std::path::{Path, PathBuf};

/// Directory the extracted icons are cached in.
pub fn icon_cache_dir() -> PathBuf {
    branding::cache_dir().join("window-icons")
}

/// Cache path for a window class, e.g. `cloudmusic.exe` -> `<cache>/window-icons/cloudmusic_exe.png`.
///
/// The name is sanitized so a hostile class cannot escape the directory.
pub fn icon_cache_path(class: &str) -> PathBuf {
    let mut safe: String = class
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.' {
                c.to_ascii_lowercase()
            } else {
                '_'
            }
        })
        .collect();
    while safe.starts_with('.') {
        safe.remove(0);
    }
    // `..` cannot traverse once separators are gone, but strip it anyway so the
    // name can never be mistaken for a relative path.
    while safe.contains("..") {
        safe = safe.replace("..", "_");
    }
    if safe.is_empty() {
        safe.push_str("window");
    }
    icon_cache_dir().join(format!("{safe}.png"))
}

/// Should the window's own icon be extracted for this identity?
///
/// Only when the application is an X11/Wine client (`*.exe` class) AND identity
/// resolution produced no icon of its own - i.e. it fell back to the generic
/// `wine` glyph (or nothing). A desktop-entry icon always wins: it is the
/// application's own declared identity, and re-reading the window would be
/// redundant work.
pub fn should_extract_window_icon(class: &str, icon_name: &str) -> bool {
    let is_wine = class.trim().to_lowercase().ends_with(".exe");
    if !is_wine {
        return false;
    }
    let icon = icon_name.trim();
    icon.is_empty() || icon.eq_ignore_ascii_case("wine")
}

/// Decode a `_NET_WM_ICON` property into RGBA.
///
/// The property is a sequence of images, each `[width, height, width*height
/// ARGB pixels]`, from which the largest is used. Returns `None` for empty,
/// degenerate or truncated data - a broken icon property must never take the
/// shell down or produce a garbage texture.
pub fn decode_net_wm_icon(data: &[u32]) -> Option<(u32, u32, Vec<u8>)> {
    let mut best: Option<(u32, u32, Vec<u8>)> = None;
    let mut offset = 0usize;

    while offset + 2 <= data.len() {
        let width = data[offset];
        let height = data[offset + 1];
        offset += 2;

        if width == 0 || height == 0 {
            return best;
        }
        let pixels = (width as usize).checked_mul(height as usize)?;
        if offset + pixels > data.len() {
            // Truncated image: keep whatever was decoded so far.
            return best;
        }

        let mut rgba = Vec::with_capacity(pixels * 4);
        for argb in &data[offset..offset + pixels] {
            rgba.push(((argb >> 16) & 0xFF) as u8); // R
            rgba.push(((argb >> 8) & 0xFF) as u8); // G
            rgba.push((argb & 0xFF) as u8); // B
            rgba.push(((argb >> 24) & 0xFF) as u8); // A
        }
        offset += pixels;

        let replace = match &best {
            None => true,
            Some((w, h, _)) => width as u64 * height as u64 > *w as u64 * *h as u64,
        };
        if replace {
            best = Some((width, height, rgba));
        }
    }

    best
}

/// Extract (and cache) the icon an X11 window publishes for itself.
///
/// Returns the cached PNG path. The first call for a class reads the X11
/// property and writes the file; later calls hit the cache.
pub fn ensure_window_icon(class: &str) -> Option<PathBuf> {
    let path = icon_cache_path(class);
    if path.is_file() {
        return Some(path);
    }

    let data = crate::infrastructure::x11_input::read_net_wm_icon(class)?;
    let (width, height, rgba) = decode_net_wm_icon(&data)?;
    let image = image::RgbaImage::from_raw(width, height, rgba)?;

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).ok()?;
    }
    // Write through a temporary file so a crash cannot leave a half-written PNG
    // in the cache (the UI would then fail to decode it forever).
    let tmp = path.with_extension("png.tmp");
    image.save_with_format(&tmp, image::ImageFormat::Png).ok()?;
    fs::rename(&tmp, &path).ok()?;
    Some(path)
}

/// Icon path for a window identity, extracting the window's own icon when the
/// resolver could not supply a real one.
pub fn resolve_window_icon(class: &str, resolved_icon: &str) -> Option<PathBuf> {
    if !should_extract_window_icon(class, resolved_icon) {
        return None;
    }
    ensure_window_icon(class)
}

/// True when the path looks like an icon file we produced.
pub fn is_extracted_icon(path: &Path) -> bool {
    path.starts_with(icon_cache_dir())
}
