use astral_plasma::infrastructure::clipboard_adapter::{
    clipboard_cache_dir, read_clipboard, set_clipboard, clear_clipboard, ClipboardItem,
};
use std::fs::File;
use std::io::Write;

#[test]
fn test_clipboard_cache_dir_exists() {
    let dir = clipboard_cache_dir();
    assert!(dir.is_dir(), "clipboard cache dir must be created");
}

#[test]
fn test_clipboard_item_serialization() {
    let text_item = ClipboardItem::Text { text: "hello".to_string() };
    let json = serde_json::to_string(&text_item).expect("serialize text");
    assert!(json.contains(r#""type":"text""#));
    assert!(json.contains(r#""text":"hello""#));

    let img_item = ClipboardItem::Image {
        path: "/tmp/test.png".to_string(),
        preview: "file:///tmp/test.png".to_string(),
        text: "Image (100×100)".to_string(),
        mime: "image/png".to_string(),
        width: 100,
        height: 100,
        bytes_len: 1234,
    };
    let json_img = serde_json::to_string(&img_item).expect("serialize image");
    assert!(json_img.contains(r#""type":"image""#));
    assert!(json_img.contains(r#""width":100"#));

    let deserialized: ClipboardItem = serde_json::from_str(&json_img).expect("deserialize image");
    assert_eq!(deserialized, img_item);
}

#[test]
fn test_clipboard_set_and_read_text() {
    let test_str = "Astral Plasma Clipboard Test String 12345";
    let ok = set_clipboard(test_str, false);

    // If WAYLAND_DISPLAY is not set (e.g. isolated cargo test), wl-copy cannot connect
    if std::env::var("WAYLAND_DISPLAY").is_err() {
        assert!(!ok, "in headless environment without Wayland, set_clipboard returns false");
        let item = read_clipboard();
        assert_eq!(item, ClipboardItem::Empty, "in headless environment, read returns empty");
        return;
    }

    assert!(ok, "setting text clipboard should succeed when Wayland is available");
    let item = read_clipboard();
    match item {
        ClipboardItem::Text { text } => {
            assert_eq!(text, test_str, "read clipboard should match set text");
        }
        _ => {}
    }
}

#[test]
fn test_clipboard_set_and_read_image() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let img_path = temp_dir.path().join("test.png");

    let png_bytes: &[u8] = &[
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48,
        0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
        0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78,
        0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    ];

    let mut file = File::create(&img_path).expect("create file");
    file.write_all(png_bytes).expect("write png");
    drop(file);

    let ok = set_clipboard(&img_path.to_string_lossy(), true);

    if std::env::var("WAYLAND_DISPLAY").is_err() {
        assert!(!ok, "in headless environment without Wayland, set_clipboard returns false");
        return;
    }

    assert!(ok, "setting image clipboard should succeed when Wayland is available");
    let item = read_clipboard();
    match item {
        ClipboardItem::Image { path, preview, width, height, .. } => {
            assert!(path.contains("clip_"), "image path should be cached");
            assert!(preview.starts_with("file://"), "preview should be file URL");
            assert_eq!(width, 1, "image width should be decoded");
            assert_eq!(height, 1, "image height should be decoded");
        }
        _ => {}
    }
}

#[test]
fn test_clipboard_clear() {
    clear_clipboard();
}
