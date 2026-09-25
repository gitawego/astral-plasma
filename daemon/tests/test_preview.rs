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

// --- Aspect preservation inside the fit box --------------------------------
//
// Captures are scaled into a box of (target_width x 260). Locking the width
// and clamping the height bakes a WRONG aspect ratio into the PNG whenever the
// source cannot fit at the requested width (portrait, square, strip-shaped
// windows), and the overview grid then displays squashed content. Contract:
// fit INSIDE the box, aspect preserved, for every source shape. The 260px
// bound is pinned here because it is the documented thumbnail height ceiling.

const BOX_H: u32 = 260;

#[test]
fn test_fit_box_preserves_square_aspect() {
    let (w, h) = (500u32, 500u32);
    let stride = w * 4;
    let raw = vec![0u8; (stride * h) as usize];
    let png = process_bgra_to_png(&raw, w, h, stride, 480).expect("must encode PNG");
    let img = image::load_from_memory(&png).expect("must load PNG");
    assert!(img.width() <= 480, "width must stay in the box, got {}", img.width());
    assert!(img.height() <= BOX_H, "height must stay under the ceiling, got {}", img.height());
    let aspect = img.width() as f64 / img.height() as f64;
    assert!((aspect - 1.0).abs() < 0.02,
        "square source must stay square, got {}x{} (aspect {:.3})", img.width(), img.height(), aspect);
    assert!(img.width() > 200,
        "square source must use most of the width budget, got {}", img.width());
}

#[test]
fn test_fit_box_preserves_portrait_aspect() {
    let (w, h) = (400u32, 800u32);
    let stride = w * 4;
    let raw = vec![0u8; (stride * h) as usize];
    let png = process_bgra_to_png(&raw, w, h, stride, 480).expect("must encode PNG");
    let img = image::load_from_memory(&png).expect("must load PNG");
    assert!(img.width() <= 480, "width must stay in the box, got {}", img.width());
    assert!(img.height() <= BOX_H, "height must stay under the ceiling, got {}", img.height());
    let aspect = img.width() as f64 / img.height() as f64;
    assert!((aspect - 0.5).abs() < 0.02,
        "portrait source must stay 1:2, got {}x{} (aspect {:.3})", img.width(), img.height(), aspect);
    assert_eq!(img.height(), BOX_H,
        "portrait source must be height-bound to use the full box");
}

#[test]
fn test_fit_box_landscape_aspect() {
    let (w, h) = (1920u32, 1080u32);
    let stride = w * 4;
    let raw = vec![0u8; (stride * h) as usize];
    let png = process_bgra_to_png(&raw, w, h, stride, 480).expect("must encode PNG");
    let img = image::load_from_memory(&png).expect("must load PNG");
    assert!(img.width() <= 480, "width must stay in the box, got {}", img.width());
    assert!(img.height() <= BOX_H, "height must stay under the ceiling, got {}", img.height());
    let aspect = img.width() as f64 / img.height() as f64;
    assert!((aspect - (16.0 / 9.0)).abs() < 0.02,
        "16:9 source must stay 16:9, got {}x{} (aspect {:.3})", img.width(), img.height(), aspect);
}

#[test]
fn test_fit_box_short_window_height_not_fabricated() {
    // A 1920x100 strip must keep its true shape: no minimum-height padding,
    // no clamped-height squash.
    let (w, h) = (1920u32, 100u32);
    let stride = w * 4;
    let raw = vec![0u8; (stride * h) as usize];
    let png = process_bgra_to_png(&raw, w, h, stride, 320).expect("must encode PNG");
    let img = image::load_from_memory(&png).expect("must load PNG");
    let aspect = img.width() as f64 / img.height() as f64;
    assert!((aspect - 19.2).abs() < 0.5,
        "strip source must keep ~19.2:1 aspect, got {}x{} (aspect {:.3})", img.width(), img.height(), aspect);
    assert!(img.height() < 40,
        "height must not be fabricated up to the old 40px floor, got {}", img.height());
}

#[test]
fn test_get_existing_preview_resolution() {
    let test_uuid = "unit-test-existing-preview-id";
    let p0 = get_target_path(test_uuid, "0");
    let p1 = get_target_path(test_uuid, "1");

    let _ = fs::remove_file(&p0);
    let _ = fs::remove_file(&p1);

    // 1. None when files don't exist
    assert_eq!(get_existing_preview(test_uuid), None);

    // 2. Only slot 0 exists
    fs::write(&p0, b"data0").unwrap();
    assert_eq!(get_existing_preview(test_uuid), Some(p0.clone()));

    // 3. Both exist, slot 1 newer
    std::thread::sleep(std::time::Duration::from_millis(15));
    fs::write(&p1, b"data1").unwrap();
    assert_eq!(get_existing_preview(test_uuid), Some(p1.clone()));

    // 4. Slot 0 updated to be newer than slot 1
    std::thread::sleep(std::time::Duration::from_millis(15));
    fs::write(&p0, b"data0_new").unwrap();
    assert_eq!(get_existing_preview(test_uuid), Some(p0.clone()));

    // Cleanup
    let _ = fs::remove_file(&p0);
    let _ = fs::remove_file(&p1);
}
