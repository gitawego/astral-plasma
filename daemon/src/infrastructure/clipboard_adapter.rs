//! High-performance, data-driven Wayland & KDE clipboard adapter.
//! Handles rich clipboard content (text and images), image caching, and copy operations.

use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum ClipboardItem {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "image")]
    Image {
        path: String,
        preview: String,
        text: String,
        mime: String,
        width: u32,
        height: u32,
        bytes_len: usize,
    },
    #[serde(rename = "empty")]
    Empty,
}

pub fn clipboard_cache_dir() -> PathBuf {
    let base = std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
            PathBuf::from(home).join(".cache")
        });
    let dir = base.join("astral-plasma/clipboard");
    let _ = fs::create_dir_all(&dir);
    dir
}

fn fnv1a_hash(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for &b in bytes {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

/// Query currently offered MIME types on Wayland clipboard
pub fn get_available_mime_types() -> Vec<String> {
    let output = match Command::new("wl-paste").arg("-l").output() {
        Ok(out) => out,
        Err(_) => return Vec::new(),
    };
    if !output.status.success() {
        return Vec::new();
    }
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect()
}

/// Read current clipboard content, correctly differentiating images from text.
pub fn read_clipboard() -> ClipboardItem {
    let types = get_available_mime_types();
    if types.is_empty() {
        return ClipboardItem::Empty;
    }

    // 1. Check for image types first
    let image_mime = types.iter().find(|t| {
        t.starts_with("image/png")
            || t.starts_with("image/jpeg")
            || t.starts_with("image/webp")
            || t.starts_with("image/bmp")
    });

    if let Some(mime) = image_mime {
        let output = match Command::new("wl-paste").arg("-t").arg(mime).output() {
            Ok(out) => out,
            Err(_) => return ClipboardItem::Empty,
        };
        if output.status.success() && !output.stdout.is_empty() {
            let bytes = output.stdout;
            let hash = fnv1a_hash(&bytes);
            let ext = if mime.contains("jpeg") || mime.contains("jpg") {
                "jpg"
            } else if mime.contains("webp") {
                "webp"
            } else {
                "png"
            };
            let cache_dir = clipboard_cache_dir();
            let file_name = format!("clip_{:016x}.{}", hash, ext);
            let file_path = cache_dir.join(&file_name);

            if !file_path.exists() {
                if let Ok(mut f) = File::create(&file_path) {
                    let _ = f.write_all(&bytes);
                }
            }

            use std::sync::{Mutex, OnceLock};
            static LAST_IMG_DIMS: OnceLock<Mutex<Option<(u64, u32, u32)>>> = OnceLock::new();
            let dims_cache = LAST_IMG_DIMS.get_or_init(|| Mutex::new(None));
            let cached_dims = dims_cache.lock().ok().and_then(|g| {
                g.filter(|(h, _, _)| *h == hash).map(|(_, w, h)| (w, h))
            });
            let (width, height) = match cached_dims {
                Some(dims) => dims,
                None => {
                    let dims = match image::load_from_memory(&bytes) {
                        Ok(img) => (img.width(), img.height()),
                        Err(_) => (0, 0),
                    };
                    if let Ok(mut g) = dims_cache.lock() {
                        *g = Some((hash, dims.0, dims.1));
                    }
                    dims
                }
            };

            let label = if width > 0 && height > 0 {
                format!("Image ({}×{})", width, height)
            } else {
                "Image".to_string()
            };

            let path_str = file_path.to_string_lossy().to_string();
            let preview = format!("file://{}", path_str);

            return ClipboardItem::Image {
                path: path_str,
                preview,
                text: label,
                mime: mime.clone(),
                width,
                height,
                bytes_len: bytes.len(),
            };
        }
    }

    // 2. Fall back to text
    let text_output = match Command::new("wl-paste").arg("--no-newline").output() {
        Ok(out) => out,
        Err(_) => return ClipboardItem::Empty,
    };
    if text_output.status.success() && !text_output.stdout.is_empty() {
        // Sanity check: Ensure it's not raw binary image bytes misreported as text
        if text_output.stdout.starts_with(b"\x89PNG") || text_output.stdout.contains(&0) {
            return ClipboardItem::Empty;
        }
        if let Ok(txt) = String::from_utf8(text_output.stdout) {
            let trimmed = txt.trim();
            if !trimmed.is_empty() {
                return ClipboardItem::Text { text: txt };
            }
        }
    }

    ClipboardItem::Empty
}

/// Set clipboard content (either text or image file).
pub fn set_clipboard(content: &str, is_image: bool) -> bool {
    let path = Path::new(content);
    let treat_as_image = is_image || (path.is_file() && (content.ends_with(".png") || content.ends_with(".jpg") || content.ends_with(".jpeg") || content.ends_with(".webp")));

    if treat_as_image && path.is_file() {
        if let Ok(file) = File::open(path) {
            let mime = if content.ends_with(".jpg") || content.ends_with(".jpeg") {
                "image/jpeg"
            } else if content.ends_with(".webp") {
                "image/webp"
            } else {
                "image/png"
            };
            let status = Command::new("setsid")
                .args(["wl-copy", "-t", mime])
                .stdin(file)
                .status();
            if let Ok(s) = status {
                if s.success() {
                    return true;
                }
            }
        }
    }

    // Otherwise copy as text
    let status = Command::new("setsid")
        .args(["wl-copy", content])
        .status();
    let _ = Command::new("qdbus6")
        .args(["org.kde.klipper", "/klipper", "org.kde.klipper.klipper.setClipboardContents", content])
        .output();
    status.map(|s| s.success()).unwrap_or(false)
}

/// Clear clipboard history.
pub fn clear_clipboard() -> bool {
    let _ = Command::new("wl-copy").arg("-c").status();
    let _ = Command::new("qdbus6")
        .args(["org.kde.klipper", "/klipper", "org.kde.klipper.klipper.clearClipboardHistory"])
        .output();
    true
}
