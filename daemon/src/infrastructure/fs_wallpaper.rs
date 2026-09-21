use crate::domain::branding;
use crate::domain::ports::DynResult;
use crate::domain::wallpaper::{ColorPalette, Wallpaper, WallpaperPort, WallpaperType};
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct FsWallpaperAdapter {
    home_dir: PathBuf,
    state_path: PathBuf,
    thumbnail_cache_dir: PathBuf,
}

impl Default for FsWallpaperAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl FsWallpaperAdapter {
    pub fn new() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/user".to_string());
        let home_dir = PathBuf::from(&home);
        let state_path = branding::state_dir().join("wallpaper").join("path.txt");
        let thumbnail_cache_dir = branding::cache_dir().join("thumbnails");

        Self {
            home_dir,
            state_path,
            thumbnail_cache_dir,
        }
    }

    pub fn with_state_path(state_path: PathBuf) -> Self {
        let home_dir = state_path.parent().map(Path::to_path_buf).unwrap_or_else(|| PathBuf::from("/tmp"));
        Self::with_paths(home_dir, state_path)
    }


    pub fn with_paths(home_dir: PathBuf, state_path: PathBuf) -> Self {
        let thumbnail_cache_dir = home_dir
            .join(".cache")
            .join(branding::CACHE_DIR)
            .join("thumbnails");
        Self {
            home_dir,
            state_path,
            thumbnail_cache_dir,
        }
    }

    fn ensure_thumbnail_for_video(&self, wallpaper: &mut Wallpaper) {
        if !wallpaper.is_video {
            wallpaper.thumbnail_path = Some(wallpaper.path.clone());
            return;
        }

        let _ = fs::create_dir_all(&self.thumbnail_cache_dir);
        let thumb_filename = format!("{}.jpg", wallpaper.id);
        let thumb_path = self.thumbnail_cache_dir.join(&thumb_filename);

        if thumb_path.exists() {
            wallpaper.thumbnail_path = Some(thumb_path);
            return;
        }

        // Fast ffmpeg single-frame extraction (at 1s mark)
        let status = Command::new("ffmpeg")
            .args([
                "-ss", "00:00:01",
                "-i", &wallpaper.path.to_string_lossy(),
                "-vframes", "1",
                "-vf", "scale=480:-1",
                "-q:v", "3",
                "-y",
                &thumb_path.to_string_lossy(),
            ])
            .output();

        if let Ok(out) = status {
            if out.status.success() && thumb_path.exists() {
                wallpaper.thumbnail_path = Some(thumb_path);
                return;
            }
        }

        wallpaper.thumbnail_path = None;
    }

    fn scan_recursive(&self, dir: &Path, base_dir: &Path, depth: u32, out: &mut Vec<Wallpaper>) {
        if depth > 4 {
            return;
        }

        let entries = match fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => return,
        };

        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                // Don't recurse into hidden directories
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if !name.starts_with('.') {
                        self.scan_recursive(&path, base_dir, depth + 1, out);
                    }
                }
            } else if path.is_file() {
                if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                    if stem.eq_ignore_ascii_case("screenshot") {
                        continue;
                    }
                }
                let wtype = WallpaperType::from_path(&path);
                if wtype != WallpaperType::Unsupported {
                    let mut wall = Wallpaper::from_file(&path, base_dir, None);
                    self.ensure_thumbnail_for_video(&mut wall);
                    out.push(wall);
                }
            }
        }
    }
}

impl WallpaperPort for FsWallpaperAdapter {
    fn scan_wallpapers(&self, dir: &Path) -> DynResult<Vec<Wallpaper>> {
        let mut results = Vec::new();
        if dir.is_dir() {
            self.scan_recursive(dir, dir, 0, &mut results);
        }
        if results.is_empty() && dir != Path::new("/usr/share/wallpapers") {
            let sys_dir = Path::new("/usr/share/wallpapers");
            if sys_dir.is_dir() {
                self.scan_recursive(sys_dir, sys_dir, 0, &mut results);
            }
        }
        results.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        Ok(results)
    }

    fn scan_library(&self) -> DynResult<Vec<Wallpaper>> {
        let mut results = Vec::new();
        let mut seen_paths: std::collections::HashSet<PathBuf> = std::collections::HashSet::new();

        let mut add_file = |path: &Path, base_dir: &Path, out: &mut Vec<Wallpaper>| {
            if !path.is_file() {
                return;
            }
            if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                if stem.eq_ignore_ascii_case("screenshot") {
                    return;
                }
            }
            let wtype = WallpaperType::from_path(path);
            if wtype != WallpaperType::Unsupported {
                let canonical = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
                if seen_paths.insert(canonical) {
                    let mut wall = Wallpaper::from_file(path, base_dir, None);
                    self.ensure_thumbnail_for_video(&mut wall);
                    out.push(wall);
                }
            }
        };

        // 1. KDE Plasma plasmarc ([Wallpapers] usersWallpapers=...)
        let plasmarc = self.home_dir.join(".config").join("plasmarc");
        if plasmarc.is_file() {
            if let Ok(content) = fs::read_to_string(&plasmarc) {
                for line in content.lines() {
                    let trimmed = line.trim();
                    if let Some(val) = trimmed.strip_prefix("usersWallpapers=") {
                        for item in val.split(',') {
                            let item_clean = item.trim();
                            let clean_path = if let Some(stripped) = item_clean.strip_prefix("file://") {
                                stripped
                            } else {
                                item_clean
                            };
                            if !clean_path.is_empty() {
                                let p = PathBuf::from(clean_path);
                                if p.is_file() {
                                    let parent = p.parent().unwrap_or(&p);
                                    add_file(&p, parent, &mut results);
                                } else if p.is_dir() {
                                    self.scan_recursive(&p, &p, 0, &mut results);
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. KDE Plasma desktop-appletsrc (Image=..., SlidePaths=...)
        let appletsrc = self.home_dir.join(".config").join("plasma-org.kde.plasma.desktop-appletsrc");
        if appletsrc.is_file() {
            if let Ok(content) = fs::read_to_string(&appletsrc) {
                for line in content.lines() {
                    let trimmed = line.trim();
                    if let Some(val) = trimmed.strip_prefix("Image=") {
                        let path_str = if let Some(stripped) = val.strip_prefix("file://") {
                            stripped
                        } else {
                            val
                        };
                        let p = PathBuf::from(path_str.trim());
                        if p.is_file() {
                            let parent = p.parent().unwrap_or(&p);
                            add_file(&p, parent, &mut results);
                        }
                    } else if let Some(val) = trimmed.strip_prefix("SlidePaths=") {
                        for item in val.split(',') {
                            let p = PathBuf::from(item.trim());
                            if p.is_dir() {
                                self.scan_recursive(&p, &p, 0, &mut results);
                            }
                        }
                    }
                }
            }
        }

        // 3. User wallpaper directories
        let user_dirs = [
            self.home_dir.join("Pictures").join("wallpapers"),
            self.home_dir.join("Pictures").join("Wallpapers"),
            self.home_dir.join("Pictures").join("Wallpaper"),
            self.home_dir.join(".local").join("share").join("wallpapers"),
        ];

        for udir in &user_dirs {
            if udir.is_dir() {
                self.scan_recursive(udir, udir, 0, &mut results);
            }
        }

        // 4. System wallpapers
        let sys_dirs = [
            PathBuf::from("/usr/share/wallpapers"),
            PathBuf::from("/usr/local/share/wallpapers"),
        ];
        for sdir in &sys_dirs {
            if sdir.is_dir() {
                self.scan_recursive(sdir, sdir, 0, &mut results);
            }
        }

        // Deduplicate resolution duplicates and exact name/category pairs
        let mut final_results = Vec::new();
        let mut seen_ids = std::collections::HashSet::new();
        for wall in results {
            let key = (wall.name.to_lowercase(), wall.category.to_lowercase());
            if seen_ids.insert(key) {
                final_results.push(wall);
            }
        }

        final_results.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        Ok(final_results)
    }

    fn get_active_wallpaper(&self) -> DynResult<Option<PathBuf>> {
        if self.state_path.exists() {
            let content = fs::read_to_string(&self.state_path)?;
            let trimmed = content.trim();
            if !trimmed.is_empty() {
                return Ok(Some(PathBuf::from(trimmed)));
            }
        }

        // Fallback: Read active wallpaper from KDE Plasma config
        let appletsrc = self.home_dir.join(".config").join("plasma-org.kde.plasma.desktop-appletsrc");
        if appletsrc.is_file() {
            if let Ok(content) = fs::read_to_string(&appletsrc) {
                for line in content.lines() {
                    let trimmed = line.trim();
                    if let Some(val) = trimmed.strip_prefix("Image=") {
                        let path_str = if let Some(stripped) = val.strip_prefix("file://") {
                            stripped
                        } else {
                            val
                        };
                        let p = PathBuf::from(path_str.trim());
                        if p.exists() {
                            return Ok(Some(p));
                        }
                    }
                }
            }
        }

        Ok(None)
    }

    fn set_active_wallpaper(&self, path: &Path) -> DynResult<()> {
        if let Some(parent) = self.state_path.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut file = File::create(&self.state_path)?;
        writeln!(file, "{}", path.to_string_lossy())?;

        // Sync with KDE Plasma desktop if plasma-apply-wallpaperimage is available
        if path.exists() {
            let _ = Command::new("plasma-apply-wallpaperimage")
                .arg(path.to_string_lossy().as_ref())
                .spawn();
        }

        Ok(())
    }



    fn extract_palette(&self, path: &Path) -> DynResult<ColorPalette> {
        // Run matugen if installed, or fallback to pastel
        let output = Command::new("matugen")
            .args(["image", &path.to_string_lossy(), "--source-color-index", "0", "--json", "hex"])
            .output();

        if let Ok(out) = output {
            if out.status.success() {
                // Save to ~/.cache/astral-plasma/colors.json for Colors.qml
                let cache_dir = branding::cache_dir();
                let _ = fs::create_dir_all(&cache_dir);
                let colors_file = cache_dir.join("colors.json");
                let _ = fs::write(&colors_file, &out.stdout);

                if let Ok(parsed) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
                    if let Some(colors) = parsed.get("colors").and_then(|c| c.get("dark")) {
                        let primary = colors.get("primary").and_then(|v| v.as_str()).unwrap_or("#cba6f7").to_string();
                        let secondary = colors.get("secondary").and_then(|v| v.as_str()).unwrap_or("#89b4fa").to_string();
                        let surface = colors.get("surface").and_then(|v| v.as_str()).unwrap_or("#1e1e2e").to_string();
                        let on_surface = colors.get("on_surface").and_then(|v| v.as_str()).unwrap_or("#cdd6f4").to_string();
                        let accent = colors.get("tertiary").and_then(|v| v.as_str()).unwrap_or("#f5c2e7").to_string();

                        return Ok(ColorPalette {
                            primary,
                            secondary,
                            surface,
                            on_surface,
                            accent,
                            is_dark: true,
                        });
                    }
                }
            }
        }

        Ok(ColorPalette::default_pastel())
    }
}
