use std::fs;
use astral_plasma::infrastructure::preview_capture::*;

#[test]
fn test_get_target_path() {
    let path0 = get_target_path("{1234-abcd}", "0");
    assert!(path0.ends_with("_0.png"), "Slot 0 must end with _0.png");
    assert!(!path0.contains('{'), "Must strip leading brace");
    assert!(!path0.contains('}'), "Must strip trailing brace");
    assert!(!path0.contains('?'), "Path must not contain URL query parameters");

    let path1 = get_target_path("1234-abcd", "1");
    assert!(path1.ends_with("_1.png"), "Slot 1 must end with _1.png");
}

#[test]
fn test_slot_alternation() {
    let test_uuid = "test-slot-unit-uuid";
    let p0 = get_target_path(test_uuid, "0");
    let p1 = get_target_path(test_uuid, "1");

    // Clean up if exist
    let _ = fs::remove_file(&p0);
    let _ = fs::remove_file(&p1);

    // Initial slot should be "0"
    let s1 = get_next_slot(test_uuid);
    assert_eq!(s1, "0");

    // Write file 0
    fs::write(&p0, b"dummy0").unwrap();

    // Next slot should be "1"
    let s2 = get_next_slot(test_uuid);
    assert_eq!(s2, "1");

    // Write file 1
    fs::write(&p1, b"dummy1").unwrap();

    // Simulate file 0 being updated later
    std::thread::sleep(std::time::Duration::from_millis(15));
    fs::write(&p0, b"dummy0_new").unwrap();

    // Older file is 1, so next slot should be "1"
    let s3 = get_next_slot(test_uuid);
    assert_eq!(s3, "1");

    // Cleanup
    let _ = fs::remove_file(&p0);
    let _ = fs::remove_file(&p1);
}

#[test]
fn test_downscale_and_convert_bgra_to_png() {
    // 2x2 BGRA test image
    // Pixel (0,0): Red (B=0, G=0, R=255, A=255)
    // Pixel (1,0): Green (B=0, G=255, R=0, A=255)
    // Pixel (0,1): Blue (B=255, G=0, R=0, A=255)
    // Pixel (1,1): White (B=255, G=255, R=255, A=255)
    let raw_bgra: Vec<u8> = vec![
        0, 0, 255, 255,   0, 255, 0, 255,
        255, 0, 0, 255,   255, 255, 255, 255,
    ];
    let width = 2;
    let height = 2;
    let stride = 8;
    let target_width = 2;

    let png_bytes = process_bgra_to_png(&raw_bgra, width, height, stride, target_width).expect("Must encode PNG");
    assert!(!png_bytes.is_empty());
    // Verify PNG magic header: \x89PNG\r\n\x1a\n
    assert_eq!(&png_bytes[0..8], b"\x89PNG\r\n\x1a\n");

    // Decode and verify
    let img = image::load_from_memory(&png_bytes).expect("Must load valid PNG");
    assert_eq!(img.width(), 2);
    assert_eq!(img.height(), 2);
    let rgba = img.to_rgba8();
    // Top-left pixel should be Red (R=255, G=0, B=0, A=255)
    let p00 = rgba.get_pixel(0, 0);
    assert_eq!(p00.0, [255, 0, 0, 255]);
}

#[test]
fn test_desktop_entry_content() {
    let dummy_exe = std::path::PathBuf::from("/opt/astral/bin/astral-plasma");
    let content = generate_desktop_entry(&dummy_exe);

    assert!(content.contains("[Desktop Entry]"), "Must have [Desktop Entry] section");
    assert!(content.contains("Exec=/opt/astral/bin/astral-plasma"), "Must specify exact executable path");
    assert!(
        content.contains("X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2,org.kde.kwin.Screenshot"),
        "Must declare KWin ScreenShot2 authorization"
    );
    assert!(
        content.contains("X-KDE-Wayland-Interfaces=org_kde_plasma_window_management,zkde_screencast_unstable_v1"),
        "Must declare Wayland interfaces"
    );
    assert!(content.contains("NoDisplay=true"), "Must be hidden from app launcher menu");
}

#[test]
fn test_desktop_entry_install_and_removal_lifecycle() {
    let temp_dir_holder = tempfile::tempdir().unwrap();
    let temp_dir = temp_dir_holder.path();

    let dummy_exe = std::path::PathBuf::from("/opt/test/bin/astral-plasma");

    // 1. Initial install: should succeed and report true (newly installed)
    let res1 = install_desktop_entry_with_notification(Some(temp_dir), Some(&dummy_exe));
    assert!(res1.is_ok());
    assert_eq!(res1.unwrap(), true, "First install must return true (action performed)");

    let desktop_file = temp_dir.join("astral-plasma.desktop");
    assert!(desktop_file.exists(), "Desktop file must exist after install");
    let saved_content = fs::read_to_string(&desktop_file).unwrap();
    assert!(saved_content.contains("Exec=/opt/test/bin/astral-plasma"));

    // 2. Idempotent install: should detect unchanged file and return false (no duplicate action or notification)
    let res2 = install_desktop_entry_with_notification(Some(temp_dir), Some(&dummy_exe));
    assert!(res2.is_ok());
    assert_eq!(res2.unwrap(), false, "Second install must return false (already up-to-date)");

    // 3. Update on changed executable path:
    let new_exe = std::path::PathBuf::from("/opt/test/v2/astral-plasma");
    let res3 = install_desktop_entry_with_notification(Some(temp_dir), Some(&new_exe));
    assert!(res3.is_ok());
    assert_eq!(res3.unwrap(), true, "Install with changed path must return true (updated)");
    let updated_content = fs::read_to_string(&desktop_file).unwrap();
    assert!(updated_content.contains("Exec=/opt/test/v2/astral-plasma"));

    // 4. Removal on app stop:
    let rem1 = remove_desktop_entry(Some(temp_dir));
    assert!(rem1.is_ok());
    assert_eq!(rem1.unwrap(), true, "Removal must return true when file was deleted");
    assert!(!desktop_file.exists(), "Desktop file must be deleted after removal");

    // 5. Secondary removal:
    let rem2 = remove_desktop_entry(Some(temp_dir));
    assert!(rem2.is_ok());
    assert_eq!(rem2.unwrap(), false, "Subsequent removal must return false when file is already gone");
}
