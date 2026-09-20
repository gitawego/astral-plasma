//! KWin compositor blur tuning.
//!
//! The shell's liquid glass relies on `BackgroundEffect.blurRegion`, which is
//! executed by KWin's own blur effect. KWin's `BlurStrength` parameter therefore
//! directly controls how much backdrop structure survives through the glass: at
//! high strength the dual-kawase filter homogenises the backdrop into flat grey,
//! so a genuinely translucent panel still reads as an opaque slab. This adapter
//! applies the user's configured strength to kwinrc and nudges KWin to reload
//! the effect, so the value is no longer dead config.

use crate::domain::ports::DynResult;
use crate::infrastructure::kwin_shortcuts::{KWinShortcutsAdapter, KdeIniFile};
use std::fs;

/// KWin's UI exposes blur strength 1..=10. Values above ~4 flatten the backdrop
/// enough that glass stops reading as glass; 3 keeps shapes recognisable while
/// still frosting them.
pub const MIN_STRENGTH: u32 = 1;
pub const MAX_STRENGTH: u32 = 10;
pub const DEFAULT_STRENGTH: u32 = 3;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlurSettings {
    pub strength: u32,
    /// KWin's constant-noise overlay. Left at 0 by default: the shell draws its
    /// own refractive gradients and noise muddies them.
    pub noise_strength: u32,
}

impl Default for BlurSettings {
    fn default() -> Self {
        Self { strength: DEFAULT_STRENGTH, noise_strength: 0 }
    }
}

impl BlurSettings {
    /// Clamp a user-supplied strength into the range KWin accepts.
    pub fn clamped(strength: u32, noise_strength: u32) -> Self {
        Self {
            strength: strength.clamp(MIN_STRENGTH, MAX_STRENGTH),
            noise_strength: noise_strength.min(MAX_STRENGTH),
        }
    }

    /// Map the shell's 0.0..=1.0 `blurStrength` preference onto KWin's 1..=10
    /// scale, inverted: the preference expresses *desired glass fidelity*, and
    /// fidelity is highest at the lowest blur strength.
    pub fn from_normalized(preference: f64) -> Self {
        let p = preference.clamp(0.0, 1.0);
        // 1.0 -> strength 1 (crispest), 0.0 -> strength 10 (most diffuse)
        let strength = (MAX_STRENGTH as f64 - p * (MAX_STRENGTH as f64 - MIN_STRENGTH as f64))
            .round() as u32;
        Self { strength: strength.clamp(MIN_STRENGTH, MAX_STRENGTH), noise_strength: 0 }
    }
}

pub struct KWinBlurAdapter {
    shortcuts: KWinShortcutsAdapter,
}

impl KWinBlurAdapter {
    pub fn new() -> Self {
        Self { shortcuts: KWinShortcutsAdapter::new() }
    }

    fn kwinrc_path(&self) -> std::path::PathBuf {
        self.shortcuts.resolve_config_dir().join("kwinrc")
    }

    /// Render the kwinrc content with the blur settings applied. Pure function so
    /// the KDE INI round-trip is unit-testable without touching the filesystem.
    pub fn render_kwinrc(existing: &str, settings: &BlurSettings) -> String {
        let mut ini = KdeIniFile::parse(existing);
        ini.set("Effect-blur", "BlurStrength", &settings.strength.to_string());
        ini.set("Effect-blur", "NoiseStrength", &settings.noise_strength.to_string());
        ini.serialize()
    }

    /// Apply the settings to kwinrc and ask KWin to reload the blur effect.
    pub fn apply(&self, settings: &BlurSettings) -> DynResult<bool> {
        let path = self.kwinrc_path();
        let existing = fs::read_to_string(&path).unwrap_or_default();
        let rendered = Self::render_kwinrc(&existing, settings);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&path, rendered)?;
        self.reconfigure();
        Ok(true)
    }

    /// Ask the running compositor to re-read the blur effect configuration.
    /// Best-effort: a headless or non-KWin session has no such service.
    pub fn reconfigure(&self) {
        let _ = std::process::Command::new("qdbus6")
            .args([
                "org.kde.KWin",
                "/Effects",
                "org.kde.kwin.Effects.reconfigureEffect",
                "blur",
            ])
            .output();
    }

    /// Read the currently configured strength, if KWin has one set.
    pub fn current(&self) -> DynResult<Option<BlurSettings>> {
        let path = self.kwinrc_path();
        if !path.exists() {
            return Ok(None);
        }
        let content = fs::read_to_string(&path)?;
        let ini = KdeIniFile::parse(&content);
        let strength = ini
            .get("Effect-blur", "BlurStrength")
            .and_then(|v| v.trim().parse::<u32>().ok());
        let noise = ini
            .get("Effect-blur", "NoiseStrength")
            .and_then(|v| v.trim().parse::<u32>().ok())
            .unwrap_or(0);
        Ok(strength.map(|s| BlurSettings::clamped(s, noise)))
    }
}

impl Default for KWinBlurAdapter {
    fn default() -> Self {
        Self::new()
    }
}
