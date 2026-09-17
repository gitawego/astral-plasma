use crate::domain::ports::DynResult;
use crate::domain::wallpaper::{ColorPalette, Wallpaper, WallpaperFilter, WallpaperPort};
use std::path::Path;
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
