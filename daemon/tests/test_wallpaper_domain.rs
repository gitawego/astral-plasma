use astral_plasma::domain::ports::DynResult;
use astral_plasma::domain::wallpaper::{
    ColorPalette, Wallpaper, WallpaperFilter, WallpaperPort, WallpaperType,
};
use astral_plasma::application::wallpaper_service::{
    ListWallpapersUseCase, SetWallpaperUseCase, GeneratePaletteUseCase,
};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

#[derive(Clone, Default)]
struct MockWallpaperPort {
    wallpapers: Vec<Wallpaper>,
    active_path: Arc<Mutex<Option<PathBuf>>>,
    applied_wallpapers: Arc<Mutex<Vec<PathBuf>>>,
}

impl WallpaperPort for MockWallpaperPort {
    fn scan_wallpapers(&self, _dir: &Path) -> DynResult<Vec<Wallpaper>> {
        Ok(self.wallpapers.clone())
    }

    fn scan_library(&self) -> DynResult<Vec<Wallpaper>> {
        Ok(self.wallpapers.clone())
    }


    fn get_active_wallpaper(&self) -> DynResult<Option<PathBuf>> {
        let lock = self.active_path.lock().unwrap();
        Ok(lock.clone())
    }

    fn set_active_wallpaper(&self, path: &Path) -> DynResult<()> {
        let mut lock = self.active_path.lock().unwrap();
        *lock = Some(path.to_path_buf());
        let mut applied = self.applied_wallpapers.lock().unwrap();
        applied.push(path.to_path_buf());
        Ok(())
    }

    fn extract_palette(&self, path: &Path) -> DynResult<ColorPalette> {
        let name = path.file_stem().and_then(|s| s.to_str()).unwrap_or("default");
        if name == "raiden" {
            Ok(ColorPalette {
                primary: "#9d4edd".to_string(),
                secondary: "#7b2cbf".to_string(),
                surface: "#10002b".to_string(),
                on_surface: "#e0aaff".to_string(),
                accent: "#c77dff".to_string(),
                is_dark: true,
            })
        } else {
            Ok(ColorPalette::default_pastel())
        }
    }
}

#[test]
fn test_wallpaper_type_detection() {
    assert_eq!(
        WallpaperType::from_path(Path::new("/tmp/image.png")),
        WallpaperType::StaticImage
    );
    assert_eq!(
        WallpaperType::from_path(Path::new("/tmp/photo.jpg")),
        WallpaperType::StaticImage
    );
    assert_eq!(
        WallpaperType::from_path(Path::new("/tmp/pic.webp")),
        WallpaperType::StaticImage
    );
    assert_eq!(
        WallpaperType::from_path(Path::new("/tmp/animation.mp4")),
        WallpaperType::DynamicVideo
    );
    assert_eq!(
        WallpaperType::from_path(Path::new("/tmp/loop.webm")),
        WallpaperType::DynamicVideo
    );
    assert_eq!(
        WallpaperType::from_path(Path::new("/tmp/readme.txt")),
        WallpaperType::Unsupported
    );
}

#[test]
fn test_wallpaper_entity_category_and_name() {
    let base_dir = Path::new("/home/user/Pictures/Wallpapers");
    let wall_path = base_dir.join("anime").join("violet_evergarden.png");

    let wallpaper = Wallpaper::from_file(&wall_path, base_dir, None);
    assert_eq!(wallpaper.name, "violet_evergarden");
    assert_eq!(wallpaper.category, "anime");
    assert_eq!(wallpaper.wallpaper_type, WallpaperType::StaticImage);
    assert!(!wallpaper.is_video);

    let root_wall = base_dir.join("landscape.mp4");
    let root_wallpaper = Wallpaper::from_file(&root_wall, base_dir, None);
    assert_eq!(root_wallpaper.name, "landscape");
    assert_eq!(root_wallpaper.category, "General");
    assert_eq!(root_wallpaper.wallpaper_type, WallpaperType::DynamicVideo);
    assert!(root_wallpaper.is_video);
}

#[test]
fn test_wallpaper_resolution_name_fallback() {
    let base_dir = Path::new("/usr/share/wallpapers");
    let kde_wall = base_dir.join("Honeywave").join("contents").join("images").join("1920x1080.jpg");

    let wallpaper = Wallpaper::from_file(&kde_wall, base_dir, None);
    assert_eq!(wallpaper.name, "Honeywave");
    assert_eq!(wallpaper.category, "Honeywave");
}

#[test]
fn test_wallpaper_json_serialization() {
    let wallpaper = Wallpaper {
        id: "violet".to_string(),
        name: "violet".to_string(),
        path: PathBuf::from("/path/to/violet.png"),
        is_video: false,
        wallpaper_type: WallpaperType::StaticImage,
        thumbnail_path: Some(PathBuf::from("/cache/thumb.png")),
        category: "anime".to_string(),
    };

    let json_str = serde_json::to_string(&wallpaper).expect("serialization failed");
    assert!(json_str.contains("\"id\":\"violet\""));
    assert!(json_str.contains("\"is_video\":false"));
    assert!(json_str.contains("\"category\":\"anime\""));
}

#[test]
fn test_list_wallpapers_use_case_filtering() {
    let mock_port = MockWallpaperPort {
        wallpapers: vec![
            Wallpaper {
                id: "1".to_string(),
                name: "room".to_string(),
                path: PathBuf::from("/walls/room.png"),
                is_video: false,
                wallpaper_type: WallpaperType::StaticImage,
                thumbnail_path: None,
                category: "cyberpunk".to_string(),
            },
            Wallpaper {
                id: "2".to_string(),
                name: "raiden".to_string(),
                path: PathBuf::from("/walls/raiden.mp4"),
                is_video: true,
                wallpaper_type: WallpaperType::DynamicVideo,
                thumbnail_path: None,
                category: "anime".to_string(),
            },
            Wallpaper {
                id: "3".to_string(),
                name: "violet".to_string(),
                path: PathBuf::from("/walls/violet.jpg"),
                is_video: false,
                wallpaper_type: WallpaperType::StaticImage,
                thumbnail_path: None,
                category: "anime".to_string(),
            },
        ],
        ..Default::default()
    };

    let use_case = ListWallpapersUseCase::new(Arc::new(mock_port));

    // No filter
    let all = use_case.execute(Path::new("/walls"), WallpaperFilter::default()).unwrap();
    assert_eq!(all.len(), 3);

    // Query filter
    let filtered = use_case.execute(
        Path::new("/walls"),
        WallpaperFilter {
            query: Some("raid".to_string()),
            ..Default::default()
        },
    ).unwrap();
    assert_eq!(filtered.len(), 1);
    assert_eq!(filtered[0].name, "raiden");

    // Video only filter
    let videos = use_case.execute(
        Path::new("/walls"),
        WallpaperFilter {
            videos_only: true,
            ..Default::default()
        },
    ).unwrap();
    assert_eq!(videos.len(), 1);
    assert_eq!(videos[0].name, "raiden");
}

#[test]
fn test_set_wallpaper_use_case() {
    let mock_port = MockWallpaperPort::default();
    let port_arc = Arc::new(mock_port);
    let use_case = SetWallpaperUseCase::new(port_arc.clone());

    let target = PathBuf::from("/walls/violet.png");
    use_case.execute(&target).unwrap();

    let active = port_arc.get_active_wallpaper().unwrap();
    assert_eq!(active, Some(target));
}

#[test]
fn test_generate_palette_use_case() {
    let mock_port = MockWallpaperPort::default();
    let use_case = GeneratePaletteUseCase::new(Arc::new(mock_port));

    let palette = use_case.execute(Path::new("/walls/raiden.png")).unwrap();
    assert_eq!(palette.primary, "#9d4edd");
    assert!(palette.is_dark);
}

#[test]
fn test_list_wallpapers_use_case_library() {
    let mock_port = MockWallpaperPort {
        wallpapers: vec![
            Wallpaper {
                id: "1".to_string(),
                name: "custom_wall".to_string(),
                path: PathBuf::from("/home/user/wall.png"),
                is_video: false,
                wallpaper_type: WallpaperType::StaticImage,
                thumbnail_path: None,
                category: "General".to_string(),
            },
        ],
        ..Default::default()
    };

    let use_case = ListWallpapersUseCase::new(Arc::new(mock_port));
    let library = use_case.execute_library(WallpaperFilter::default()).unwrap();
    assert_eq!(library.len(), 1);
    assert_eq!(library[0].name, "custom_wall");
}

