use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use crate::domain::ports::DynResult;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WallpaperType {
    StaticImage,
    DynamicVideo,
    Unsupported,
}

impl WallpaperType {
    pub fn from_path(path: &Path) -> Self {
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase())
            .unwrap_or_default();

        match ext.as_str() {
            "png" | "jpg" | "jpeg" | "webp" | "bmp" | "avif" => WallpaperType::StaticImage,
            "mp4" | "webm" | "mkv" | "mov" | "avi" => WallpaperType::DynamicVideo,
            _ => WallpaperType::Unsupported,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ColorPalette {
    pub primary: String,
    pub secondary: String,
    pub surface: String,
    pub on_surface: String,
    pub accent: String,
    pub is_dark: bool,
}

impl ColorPalette {
    pub fn default_pastel() -> Self {
        Self {
            primary: "#cba6f7".to_string(),
            secondary: "#89b4fa".to_string(),
            surface: "#1e1e2e".to_string(),
            on_surface: "#cdd6f4".to_string(),
            accent: "#f5c2e7".to_string(),
            is_dark: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Wallpaper {
    pub id: String,
    pub name: String,
    pub path: PathBuf,
    pub is_video: bool,
    pub wallpaper_type: WallpaperType,
    pub thumbnail_path: Option<PathBuf>,
    pub category: String,
}

impl Wallpaper {
    pub fn from_file(file_path: &Path, base_dir: &Path, thumbnail_path: Option<PathBuf>) -> Self {
        let mut name = file_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown")
            .to_string();

        let wtype = WallpaperType::from_path(file_path);
        let is_video = matches!(wtype, WallpaperType::DynamicVideo);

        // Compute relative category:
        // if file is in /base_dir/anime/sub/wall.png -> "anime"
        // if file is in /base_dir/wall.png -> "General"
        let category = match file_path.strip_prefix(base_dir) {
            Ok(rel) => {
                let mut components = rel.components();
                if let Some(first) = components.next() {
                    let first_str = first.as_os_str().to_string_lossy().to_string();
                    if components.next().is_some() {
                        // Subdirectory exists, category is top relative dir
                        first_str
                    } else {
                        "General".to_string()
                    }
                } else {
                    "General".to_string()
                }
            }
            Err(_) => "General".to_string(),
        };

        // If name looks like a resolution (e.g. "1920x1080", "1080x1920", "3840x2160"), use category name
        let is_resolution_stem = name.contains('x') && name.chars().all(|c| c.is_ascii_digit() || c == 'x');
        if is_resolution_stem && category != "General" {
            name = category.clone();
        }

        let id = format!("{:x}", md5_hash(file_path.to_string_lossy().as_bytes()));

        Self {
            id,
            name,
            path: file_path.to_path_buf(),
            is_video,
            wallpaper_type: wtype,
            thumbnail_path,
            category,
        }
    }
}

fn md5_hash(bytes: &[u8]) -> u128 {
    // Ultra-lightweight deterministic hash for stable wallpaper IDs
    let mut hash: u128 = 0xcbf29ce484222325;
    for &b in bytes {
        hash = (hash ^ (b as u128)).wrapping_mul(0x100000001b3);
    }
    hash
}

#[derive(Debug, Clone, Default)]
pub struct WallpaperFilter {
    pub query: Option<String>,
    pub category: Option<String>,
    pub videos_only: bool,
}

pub trait WallpaperPort: Send + Sync {
    fn scan_wallpapers(&self, dir: &Path) -> DynResult<Vec<Wallpaper>>;
    fn scan_library(&self) -> DynResult<Vec<Wallpaper>> {
        self.scan_wallpapers(Path::new("/usr/share/wallpapers"))
    }
    fn get_active_wallpaper(&self) -> DynResult<Option<PathBuf>>;
    fn set_active_wallpaper(&self, path: &Path) -> DynResult<()>;
    fn extract_palette(&self, path: &Path) -> DynResult<ColorPalette>;
}

