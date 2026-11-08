use astral_plasma::infrastructure::embedded_bundle::extract_embedded_theme;

#[test]
fn test_embedded_dir_extraction() {
    let tmp = tempfile::tempdir().unwrap();
    let res = extract_embedded_theme(tmp.path());
    assert!(res.is_ok(), "Extraction of self-contained bundle must succeed");
    assert!(tmp.path().join("shell.qml").exists());
    assert!(tmp.path().join("dock").exists());
    // The kernel lives under modules/Astral/Kernel so the tree keeps one shape
    // in the repo, in the extracted package, and in the AppHost import path.
    assert!(tmp.path().join("modules/Astral/Kernel/theme").exists());
    assert!(tmp.path().join("modules/Astral/Kernel/components").exists());
    assert!(tmp.path().join("modules/Astral/Kernel/config/Config.qml").exists());
    assert!(tmp.path().join("modules/Astral/Kernel/services").exists());
    // AppKit and the bundled apps travel with the package: a hosted app needs the
    // SDK on the import path, and the shell loads its apps from data.
    assert!(tmp.path().join("modules/Astral/AppKit/qmldir").exists());
    assert!(tmp
        .path()
        .join("modules/Astral/Kernel/Host/AppHost.qml")
        .exists());
}
