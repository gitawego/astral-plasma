use astral_plasma::domain::wallpaper::{WallpaperPort, WallpaperType};
use astral_plasma::infrastructure::fs_wallpaper::FsWallpaperAdapter;
use std::fs::{self, File};
use tempfile::tempdir;


#[test]
fn test_fs_wallpaper_adapter_scanning() {
    let dir = tempdir().unwrap();
    let root = dir.path();

    // Create mock wallpapers
    File::create(root.join("violet.png")).unwrap();
    File::create(root.join("landscape.jpg")).unwrap();
    File::create(root.join("notes.txt")).unwrap(); // Should be ignored

    let anime_dir = root.join("anime");
    fs::create_dir_all(&anime_dir).unwrap();
    File::create(anime_dir.join("raiden.mp4")).unwrap();

    let adapter = FsWallpaperAdapter::new();
    let walls = adapter.scan_wallpapers(root).expect("scan failed");

    // Expect 3 wallpapers (violet, landscape, raiden)
    assert_eq!(walls.len(), 3);

    let raiden = walls.iter().find(|w| w.name == "raiden").unwrap();
    assert_eq!(raiden.category, "anime");
    assert!(raiden.is_video);
    assert_eq!(raiden.wallpaper_type, WallpaperType::DynamicVideo);

    let violet = walls.iter().find(|w| w.name == "violet").unwrap();
    assert_eq!(violet.category, "General");
    assert!(!violet.is_video);
    assert_eq!(violet.wallpaper_type, WallpaperType::StaticImage);
}

#[test]
fn test_fs_wallpaper_active_persistence() {
    let dir = tempdir().unwrap();
    let state_file = dir.path().join("current_wallpaper.txt");

    let adapter = FsWallpaperAdapter::with_state_path(state_file.clone());

    // Initially none
    let current = adapter.get_active_wallpaper().unwrap();
    assert!(current.is_none());

    // Set active
    let target = dir.path().join("anime").join("raiden.mp4");
    adapter.set_active_wallpaper(&target).unwrap();

    let reloaded = adapter.get_active_wallpaper().unwrap();
    assert_eq!(reloaded, Some(target));

    // Check file was written
    let content = fs::read_to_string(&state_file).unwrap();
    assert!(content.contains("raiden.mp4"));
}

#[test]
fn test_fs_wallpaper_library_discovery() {
    let home_tmp = tempdir().unwrap();
    let home = home_tmp.path();

    // 1. Mock external files added to plasmarc
    let ext_dir = tempdir().unwrap();
    let ext_wall1 = ext_dir.path().join("wall1.png");
    let ext_wall2 = ext_dir.path().join("wall2.jpg");
    File::create(&ext_wall1).unwrap();
    File::create(&ext_wall2).unwrap();

    // 2. KDE plasmarc with user wallpaper
    let config_dir = home.join(".config");
    fs::create_dir_all(&config_dir).unwrap();
    let plasmarc_content = format!(
        "[Wallpapers]\nusersWallpapers={},{}\n",
        ext_wall1.to_str().unwrap(),
        ext_wall2.to_str().unwrap()
    );
    fs::write(config_dir.join("plasmarc"), plasmarc_content).unwrap();

    // 3. User ~/Pictures/wallpapers directory
    let pic_wallpapers = home.join("Pictures").join("wallpapers");
    fs::create_dir_all(&pic_wallpapers).unwrap();
    let pic_wall = pic_wallpapers.join("user_fav.jpg");
    File::create(&pic_wall).unwrap();

    // 4. User ~/.local/share/wallpapers directory
    let local_wallpapers = home.join(".local").join("share").join("wallpapers").join("Sweet");
    fs::create_dir_all(&local_wallpapers).unwrap();
    let sweet_wall = local_wallpapers.join("Sweet-S1.png");
    File::create(&sweet_wall).unwrap();

    let state_file = home.join("state.txt");
    let adapter = FsWallpaperAdapter::with_paths(home.to_path_buf(), state_file);
    let library = adapter.scan_library().expect("scan_library failed");

    // Verify all sources were discovered
    let names: Vec<String> = library.iter().map(|w| w.name.clone()).collect();
    assert!(names.contains(&"wall1".to_string()));
    assert!(names.contains(&"wall2".to_string()));
    assert!(names.contains(&"user_fav".to_string()));
    assert!(names.contains(&"Sweet-S1".to_string()));
}

#[test]
fn test_fs_wallpaper_kde_active_fallback() {
    let home_tmp = tempdir().unwrap();
    let home = home_tmp.path();

    let dummy_wall = home.join("active.png");
    File::create(&dummy_wall).unwrap();

    let config_dir = home.join(".config");
    fs::create_dir_all(&config_dir).unwrap();
    let appletsrc_content = format!(
        "[Containments][1][Wallpaper][org.kde.image][General]\nImage=file://{}\n",
        dummy_wall.to_str().unwrap()
    );
    fs::write(config_dir.join("plasma-org.kde.plasma.desktop-appletsrc"), appletsrc_content).unwrap();

    let state_file = home.join("non_existent_state.txt");
    let adapter = FsWallpaperAdapter::with_paths(home.to_path_buf(), state_file);

    let active = adapter.get_active_wallpaper().unwrap();
    assert_eq!(active, Some(dummy_wall));
}


