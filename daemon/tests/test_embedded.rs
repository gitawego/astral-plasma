use astral_plasma::infrastructure::embedded_bundle::extract_embedded_theme;

#[test]
fn test_embedded_dir_extraction() {
    let tmp = tempfile::tempdir().unwrap();
    let res = extract_embedded_theme(tmp.path());
    assert!(res.is_ok(), "Extraction of self-contained bundle must succeed");
    assert!(tmp.path().join("shell.qml").exists());
    assert!(tmp.path().join("dock").exists());
    assert!(tmp.path().join("theme").exists());
}
