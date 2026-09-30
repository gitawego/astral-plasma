//! KWin blur tuning: the shell's glass depends on KWin's compositor blur, and
//! excessive blur strength homogenises the backdrop so that even a genuinely
//! translucent panel reads as an opaque slab.

use astral_plasma::infrastructure::kwin_blur::{
    BlurSettings, KWinBlurAdapter, DEFAULT_STRENGTH, MAX_STRENGTH, MIN_STRENGTH,
};
use astral_plasma::infrastructure::kwin_shortcuts::KdeIniFile;

// ============================================================================
// Strength clamping
// ============================================================================

#[test]
fn strength_is_clamped_into_kwin_range() {
    assert_eq!(BlurSettings::clamped(0, 0).strength, MIN_STRENGTH);
    assert_eq!(BlurSettings::clamped(999, 0).strength, MAX_STRENGTH);
    assert_eq!(BlurSettings::clamped(4, 0).strength, 4);
}

#[test]
fn noise_strength_is_clamped() {
    assert_eq!(BlurSettings::clamped(3, 999).noise_strength, MAX_STRENGTH);
}

#[test]
fn default_strength_is_glass_friendly() {
    // The whole point of this module: the default must be low enough that the
    // backdrop silhouette survives through the glass.
    let d = BlurSettings::default();
    assert_eq!(d.strength, DEFAULT_STRENGTH);
    assert!(
        d.strength <= 4,
        "default blur strength {} is too diffuse - the backdrop will flatten into a grey slab",
        d.strength
    );
}

// ============================================================================
// Normalized preference mapping
// ============================================================================

#[test]
fn normalized_preference_is_inverted_against_blur_strength() {
    // The shell's `blurStrength` preference expresses desired glass FIDELITY,
    // which is highest when KWin's blur radius is lowest.
    assert_eq!(BlurSettings::from_normalized(1.0).strength, MIN_STRENGTH);
    assert_eq!(BlurSettings::from_normalized(0.0).strength, MAX_STRENGTH);
}

#[test]
fn normalized_preference_is_monotonic_and_bounded() {
    let mut previous = MAX_STRENGTH + 1;
    for step in 0..=10 {
        let p = step as f64 / 10.0;
        let s = BlurSettings::from_normalized(p).strength;
        assert!(
            (MIN_STRENGTH..=MAX_STRENGTH).contains(&s),
            "strength {} out of range for preference {}",
            s,
            p
        );
        assert!(s <= previous, "mapping must be monotonically non-increasing");
        previous = s;
    }
}

#[test]
fn normalized_preference_out_of_range_is_safe() {
    assert_eq!(BlurSettings::from_normalized(-5.0).strength, MAX_STRENGTH);
    assert_eq!(BlurSettings::from_normalized(5.0).strength, MIN_STRENGTH);
}

// ============================================================================
// kwinrc round-trip
// ============================================================================

#[test]
fn render_writes_blur_settings_into_kwinrc() {
    let existing = "[Plugins]\nblurEnabled=true\n\n[Effect-blur]\nBlurStrength=8\n";
    let rendered = KWinBlurAdapter::render_kwinrc(existing, &BlurSettings::default());
    let ini = KdeIniFile::parse(&rendered);
    assert_eq!(
        ini.get("Effect-blur", "BlurStrength"),
        Some(DEFAULT_STRENGTH.to_string())
    );
}

#[test]
fn render_preserves_unrelated_kwinrc_content() {
    // Must never clobber a user's other KWin settings.
    let existing = "\
[Plugins]
blurEnabled=true
kwin4_effect_dimscreenEnabled=true

[Effect-blur]
BlurStrength=9
NoiseStrength=5

[Desktops]
Number=4
Rows=2
";
    let rendered = KWinBlurAdapter::render_kwinrc(existing, &BlurSettings::clamped(2, 1));
    let ini = KdeIniFile::parse(&rendered);

    assert_eq!(ini.get("Plugins", "blurEnabled"), Some("true".to_string()));
    assert_eq!(ini.get("Plugins", "kwin4_effect_dimscreenEnabled"), Some("true".to_string()));
    assert_eq!(ini.get("Desktops", "Number"), Some("4".to_string()));
    assert_eq!(ini.get("Desktops", "Rows"), Some("2".to_string()));
    assert_eq!(ini.get("Effect-blur", "BlurStrength"), Some("2".to_string()));
    assert_eq!(ini.get("Effect-blur", "NoiseStrength"), Some("1".to_string()));
}

#[test]
fn render_on_empty_config_creates_the_group() {
    let rendered = KWinBlurAdapter::render_kwinrc("", &BlurSettings::default());
    let ini = KdeIniFile::parse(&rendered);
    assert_eq!(
        ini.get("Effect-blur", "BlurStrength"),
        Some(DEFAULT_STRENGTH.to_string())
    );
}

#[test]
fn render_is_idempotent() {
    let once = KWinBlurAdapter::render_kwinrc("", &BlurSettings::default());
    let twice = KWinBlurAdapter::render_kwinrc(&once, &BlurSettings::default());
    let a = KdeIniFile::parse(&once);
    let b = KdeIniFile::parse(&twice);
    assert_eq!(a.get("Effect-blur", "BlurStrength"), b.get("Effect-blur", "BlurStrength"));
    assert_eq!(a.get("Effect-blur", "NoiseStrength"), b.get("Effect-blur", "NoiseStrength"));
}

// ============================================================================
// Regression guard: the glass-fidelity failure this module exists to prevent
// ============================================================================

#[test]
fn high_strength_is_recognised_as_glass_hostile() {
    // Documents WHY the default is low: a strength of 8+ is what makes a
    // translucent panel look like a flat slab. If someone raises
    // DEFAULT_STRENGTH past this, the glass regresses.
    let hostile = BlurSettings::clamped(8, 0);
    assert!(
        hostile.strength > DEFAULT_STRENGTH,
        "sanity: 8 must exceed the glass-friendly default"
    );
    assert!(
        DEFAULT_STRENGTH < hostile.strength,
        "the default must stay below the diffuse range"
    );
}

// ============================================================================
// Snapshot / restore: the shell must not leave its blur override behind
// ============================================================================

/// One test owns both phases: `XDG_CONFIG_HOME`/`XDG_DATA_HOME` are
/// process-global, so two tests setting them would race (see the Deepgram
/// suite for the same trap).
#[test]
fn the_shell_hands_kwins_blur_back() {
    let tmp = tempfile::tempdir().expect("tempdir");
    std::env::set_var("XDG_CONFIG_HOME", tmp.path());
    std::env::set_var("XDG_DATA_HOME", tmp.path().join("data"));
    let kwinrc = tmp.path().join("kwinrc");
    let adapter = KWinBlurAdapter::new();

    // Phase 1 - the user had tuned blur before the shell touched it.
    std::fs::write(&kwinrc, "[Effect-blur]\nBlurStrength=9\nNoiseStrength=2\n").unwrap();
    adapter
        .apply(&BlurSettings { strength: 3, noise_strength: 0 })
        .expect("apply");
    adapter
        .apply(&BlurSettings { strength: 4, noise_strength: 0 })
        .expect("the second apply must not overwrite the first snapshot");
    assert!(adapter.restore().expect("restore"));
    let after = std::fs::read_to_string(&kwinrc).unwrap();
    assert!(after.contains("BlurStrength=9"),
        "the user's original strength must come back, got:\n{after}");
    assert!(after.contains("NoiseStrength=2"),
        "the user's original noise must come back, got:\n{after}");

    // Phase 2 - the shell introduced the override on a clean config.
    let tmp2 = tempfile::tempdir().expect("tempdir");
    std::env::set_var("XDG_CONFIG_HOME", tmp2.path());
    std::env::set_var("XDG_DATA_HOME", tmp2.path().join("data"));
    let kwinrc2 = tmp2.path().join("kwinrc");
    std::fs::write(&kwinrc2, "[General]\nfoo=bar\n").unwrap();
    adapter
        .apply(&BlurSettings { strength: 3, noise_strength: 0 })
        .expect("apply");
    adapter.restore().expect("restore");
    let after2 = std::fs::read_to_string(&kwinrc2).unwrap();
    assert!(!after2.contains("BlurStrength"),
        "a shell-introduced override must be removed, got:\n{after2}");
    assert!(after2.contains("foo=bar"),
        "unrelated config must survive, got:\n{after2}");
}
