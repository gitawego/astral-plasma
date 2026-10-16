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
/// The gate is the *truthfulness of the resolved icon*, never the shape of the
/// window class: any identity that resolved to no drawable icon (an empty name,
/// the generic `wine` glyph, or the class name the resolver falls back to when
/// it knows nothing better - `steam_app_default` for Proton/Steam games)
/// publishes its only real icon on the window itself. A class-suffix heuristic
/// (`*.exe`) looks like a Wine test but silently drops every other X11 client.
///
/// A desktop-entry icon always wins: it is the application's own declared
/// identity, and re-reading the window would be redundant work.
pub fn should_extract_window_icon(icon_name: &str) -> bool {
    let icon = icon_name.trim();
    if icon.is_empty() || icon.eq_ignore_ascii_case("wine") {
        return true;
    }
    // Already a file (an extracted icon, or a path the resolver produced).
    if icon.starts_with('/') || icon.starts_with("file:") {
        return false;
    }
    // A name the icon theme cannot draw is not an icon. The resolver hands back
    // the window class when it knows nothing better, and the shell would render
    // its generic material glyph for it.
    !theme_icon_exists(icon)
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

/// Roots an icon-theme lookup searches, in load order.
pub fn default_icon_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Ok(home) = std::env::var("HOME") {
        roots.push(PathBuf::from(&home).join(".local/share/icons"));
        roots.push(PathBuf::from(&home).join(".icons"));
    }
    let data_dirs =
        std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".to_string());
    for dir in data_dirs.split(':').filter(|d| !d.trim().is_empty()) {
        roots.push(PathBuf::from(dir).join("icons"));
    }
    roots.push(PathBuf::from("/usr/share/pixmaps"));
    roots
}

/// Can the icon theme draw `name`?
///
/// Memoized per name and per root: the answer only changes when a package is
/// installed, and the caller asks once per window identity.
pub fn theme_icon_exists(name: &str) -> bool {
    static CACHE: std::sync::OnceLock<std::sync::Mutex<std::collections::HashMap<String, bool>>> =
        std::sync::OnceLock::new();
    let cache = CACHE.get_or_init(|| std::sync::Mutex::new(std::collections::HashMap::new()));
    let key = name.trim().to_ascii_lowercase();
    if let Ok(guard) = cache.lock() {
        if let Some(hit) = guard.get(&key) {
            return *hit;
        }
    }
    let found = theme_icon_exists_in(&default_icon_roots(), &key);
    if let Ok(mut guard) = cache.lock() {
        guard.insert(key, found);
    }
    found
}

/// Locate a themed icon file against an explicit set of roots (pure, testable).
pub fn find_theme_icon_in(roots: &[PathBuf], name: &str) -> Option<PathBuf> {
    let name = name.trim().to_ascii_lowercase();
    if name.is_empty() || name.contains('/') || name.starts_with("file:") {
        return None;
    }
    for root in roots {
        if let Some(path) = icon_map_under(root).get(&name) {
            return Some(path.clone());
        }
    }
    None
}

/// `theme_icon_exists` against an explicit set of roots (pure, testable).
pub fn theme_icon_exists_in(roots: &[PathBuf], name: &str) -> bool {
    find_theme_icon_in(roots, name).is_some()
}

/// Image extensions an icon may carry. A name that only exists as some other
/// kind of file is not an icon the theme can draw.
const ICON_EXTENSIONS: [&str; 4] = ["png", "svg", "svgz", "xpm"];

/// Map of icon names to file paths under a root, indexed once per process.
fn icon_map_under(root: &Path) -> std::sync::Arc<std::collections::HashMap<String, PathBuf>> {
    static INDEX: std::sync::OnceLock<
        std::sync::Mutex<std::collections::HashMap<PathBuf, std::sync::Arc<std::collections::HashMap<String, PathBuf>>>>,
    > = std::sync::OnceLock::new();
    let index = INDEX.get_or_init(|| std::sync::Mutex::new(std::collections::HashMap::new()));
    if let Ok(guard) = index.lock() {
        if let Some(hit) = guard.get(root) {
            return std::sync::Arc::clone(hit);
        }
    }
    let mut map = std::collections::HashMap::new();
    collect_icon_map(root, 4, &mut map);
    let map = std::sync::Arc::new(map);
    if let Ok(mut guard) = index.lock() {
        guard.insert(root.to_path_buf(), std::sync::Arc::clone(&map));
    }
    map
}

fn collect_icon_map(
    dir: &Path,
    depth: usize,
    map: &mut std::collections::HashMap<String, PathBuf>,
) {
    if depth == 0 {
        return;
    }
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_icon_map(&path, depth - 1, map);
            continue;
        }
        let extension = path
            .extension()
            .map(|e| e.to_string_lossy().to_ascii_lowercase())
            .unwrap_or_default();
        if !ICON_EXTENSIONS.contains(&extension.as_str()) {
            continue;
        }
        let Some(stem) = path.file_stem() else { continue };
        let stem = stem.to_string_lossy().to_ascii_lowercase();
        if let Some(base) = stem
            .strip_suffix("-symbolic")
            .or_else(|| stem.strip_suffix(".symbolic"))
        {
            map.entry(base.to_string()).or_insert_with(|| path.clone());
        }
        map.entry(stem).or_insert(path);
    }
}

/// Find an existing icon file for `name` on disk.
/// Searches window-icons cache, bundled assets, loose user icons, pixmaps, and theme roots.
pub fn find_icon_path(name: &str) -> Option<PathBuf> {
    let clean = name.trim();
    if clean.is_empty() {
        return None;
    }
    if clean.starts_with('/') || clean.starts_with("file:") {
        let p = PathBuf::from(clean.trim_start_matches("file://"));
        if p.is_file() {
            return Some(p);
        }
    }

    let safe_stem = clean.to_ascii_lowercase();

    // 1. Check window-icons cache directly
    let cache_dir = icon_cache_dir();
    for suffix in ["", ".exe"] {
        let p = cache_dir.join(format!("{safe_stem}{suffix}.png"));
        if p.is_file() {
            return Some(p);
        }
    }
    if let Some(stripped) = safe_stem.strip_suffix(".exe") {
        let p = cache_dir.join(format!("{stripped}.png"));
        if p.is_file() {
            return Some(p);
        }
    }

    // 2. Check bundled Astral Plasma icons: theme/assets/icons/<name>.svg
    for candidate in [&safe_stem, &safe_stem.replace(".desktop", "")] {
        let bundled = PathBuf::from("theme/assets/icons").join(format!("{candidate}.svg"));
        if bundled.is_file() {
            if let Ok(abs) = std::fs::canonicalize(&bundled) {
                return Some(abs);
            }
            return Some(bundled);
        }
        if let Ok(exe) = std::env::current_exe() {
            if let Some(parent) = exe.parent() {
                let p = parent.join("../theme/assets/icons").join(format!("{candidate}.svg"));
                if p.is_file() {
                    if let Ok(abs) = std::fs::canonicalize(&p) {
                        return Some(abs);
                    }
                    return Some(p);
                }
            }
        }
    }

    // 3. Check loose user icons (~/.local/share/icons, ~/.icons, /usr/share/pixmaps)
    let roots = default_icon_roots();
    let exts = [".svg", ".png", ".desktop.png", ".xpm"];
    for r in &roots {
        for ext in &exts {
            let candidate = r.join(format!("{safe_stem}{ext}"));
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }

    // 4. Search icon themes under default_icon_roots
    if let Some(p) = find_theme_icon_in(&roots, &safe_stem) {
        return Some(p);
    }
    if let Some(stripped) = safe_stem.strip_suffix(".desktop") {
        if let Some(p) = find_theme_icon_in(&roots, stripped) {
            return Some(p);
        }
    }

    None
}

/// Icon path for a window identity, extracting the window's own icon or resolving
/// an on-disk icon file when the theme cannot draw the bare name.
pub fn resolve_window_icon(class: &str, resolved_icon: &str) -> Option<PathBuf> {
    // 1. If resolved_icon is already a valid file path, return it directly.
    let icon_clean = resolved_icon.trim();
    if icon_clean.starts_with('/') || icon_clean.starts_with("file:") {
        let p = PathBuf::from(icon_clean.trim_start_matches("file://"));
        if p.is_file() {
            return Some(p);
        }
    }

    // 2. Check window-icons cache directly (e.g. cloudmusic.exe.png)
    let cache_dir = icon_cache_dir();
    for candidate in [class, resolved_icon] {
        let c = candidate.trim().to_ascii_lowercase();
        if c.is_empty() { continue; }
        for ext in [".png", ".exe.png"] {
            let p = cache_dir.join(format!("{c}{ext}"));
            if p.is_file() {
                return Some(p);
            }
        }
        if let Some(stripped) = c.strip_suffix(".exe") {
            let p = cache_dir.join(format!("{stripped}.png"));
            if p.is_file() {
                return Some(p);
            }
        }
    }

    // 3. For X11 / Wine apps publishing _NET_WM_ICON, extract it
    if should_extract_window_icon(resolved_icon) {
        if let Some(extracted) = ensure_window_icon(class) {
            return Some(extracted);
        }
    }

    // 4. Find icon file on disk for resolved_icon or class
    if let Some(path) = find_icon_path(resolved_icon).or_else(|| find_icon_path(class)) {
        return Some(path);
    }

    None
}

/// True when the path looks like an icon file we produced.
pub fn is_extracted_icon(path: &Path) -> bool {
    path.starts_with(icon_cache_dir())
}
