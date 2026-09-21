use crate::domain::ports::DynResult;
use crate::domain::wallpaper::{ColorPalette, Wallpaper, WallpaperFilter, WallpaperPort};
use std::path::{Path, PathBuf};
use std::sync::Arc;

pub struct ListWallpapersUseCase {
    port: Arc<dyn WallpaperPort>,
}

impl ListWallpapersUseCase {
    pub fn new(port: Arc<dyn WallpaperPort>) -> Self {
        Self { port }
    }

    fn filter_and_sort(&self, mut list: Vec<Wallpaper>, filter: WallpaperFilter) -> Vec<Wallpaper> {
        if filter.videos_only {
            list.retain(|w| w.is_video);
        }

        if let Some(cat) = &filter.category {
            let cat_lower = cat.to_lowercase();
            list.retain(|w| w.category.to_lowercase() == cat_lower);
        }

        if let Some(q) = &filter.query {
            let q_lower = q.to_lowercase();
            list.retain(|w| {
                w.name.to_lowercase().contains(&q_lower)
                    || w.category.to_lowercase().contains(&q_lower)
            });
        }

        // Sort alphabetically by name
        list.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        list
    }

    pub fn execute(&self, dir: &Path, filter: WallpaperFilter) -> DynResult<Vec<Wallpaper>> {
        let list = self.port.scan_wallpapers(dir)?;
        Ok(self.filter_and_sort(list, filter))
    }

    pub fn execute_library(&self, filter: WallpaperFilter) -> DynResult<Vec<Wallpaper>> {
        let list = self.port.scan_library()?;
        Ok(self.filter_and_sort(list, filter))
    }
}


/// Answers which wallpaper the desktop is showing.
///
/// The picker focuses this value, so it is the ground truth (the desktop
/// containment's image) rather than the shell's own last-written path.
pub struct ActiveWallpaperUseCase {
    port: Arc<dyn WallpaperPort>,
}

impl ActiveWallpaperUseCase {
    pub fn new(port: Arc<dyn WallpaperPort>) -> Self {
        Self { port }
    }

    pub fn execute(&self) -> DynResult<Option<PathBuf>> {
        self.port.get_active_wallpaper()
    }

    /// `wallpaper get` output. JSON is the shell's interface; `raw` prints the
    /// bare path so shell scripts (the palette generator) do not have to parse
    /// JSON, and print an empty line when no wallpaper is known.
    pub fn format(path: Option<&Path>, raw: bool) -> String {
        match (raw, path) {
            (true, Some(path)) => path.to_string_lossy().to_string(),
            (true, None) => String::new(),
            (false, path) => serde_json::json!({
                "path": path.map(|p| p.to_string_lossy().to_string()),
            })
            .to_string(),
        }
    }
}

pub struct SetWallpaperUseCase {
    port: Arc<dyn WallpaperPort>,
}

impl SetWallpaperUseCase {
    pub fn new(port: Arc<dyn WallpaperPort>) -> Self {
        Self { port }
    }

    pub fn execute(&self, path: &Path) -> DynResult<()> {
        self.port.set_active_wallpaper(path)
    }
}

pub struct GeneratePaletteUseCase {
    port: Arc<dyn WallpaperPort>,
}

impl GeneratePaletteUseCase {
    pub fn new(port: Arc<dyn WallpaperPort>) -> Self {
        Self { port }
    }

    pub fn execute(&self, path: &Path) -> DynResult<ColorPalette> {
        self.port.extract_palette(path)
    }
}
