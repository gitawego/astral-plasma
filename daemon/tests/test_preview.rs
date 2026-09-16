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
