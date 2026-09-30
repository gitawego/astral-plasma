//! Display refresh preference: what the outputs offer, and what to ask for.
//!
//! Vendors expose the display setup as JSON (`kscreen-doctor -j`), and this module
//! owns the pure part of the decision: parse the outputs, pick the mode that
//! honours the user's preference, and turn that into one atomic kscreen-doctor
//! invocation. Nothing here runs a process; the adapter does.
//!
//! Two rules shape the choice:
//!
//! - **The resolution is never changed.** Reaching a refresh rate by dropping to a
//!   smaller mode would be a far more invasive change than the one being asked for.
//! - **Never round up.** A target of 120 Hz on a panel offering 240/60 picks 60,
//!   because the point of the preference is to spend *less* on scanout; a user who
//!   wants the maximum says `max`.

use crate::domain::ports::{DynError, DynResult};
use serde::Deserialize;

/// One mode an output offers.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct DisplayMode {
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(rename = "refreshRate", default)]
    pub refresh_hz: f64,
    #[serde(default)]
    pub size: ModeSize,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Deserialize)]
pub struct ModeSize {
    #[serde(default)]
    pub width: u32,
    #[serde(default)]
    pub height: u32,
}

/// One output, with everything needed to choose a mode for it.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct DisplayOutput {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub connected: bool,
    #[serde(default)]
    pub enabled: bool,
    #[serde(rename = "currentModeId", default)]
    pub current_mode_id: String,
    #[serde(default)]
    pub modes: Vec<DisplayMode>,
}

impl DisplayOutput {
    /// The mode the output is currently running, when the compositor reports one.
    pub fn current_mode(&self) -> Option<&DisplayMode> {
        self.modes.iter().find(|mode| mode.id == self.current_mode_id)
    }
}

#[derive(Debug, Deserialize)]
struct KscreenDump {
    #[serde(default)]
    outputs: Vec<DisplayOutput>,
}

/// What the user asked scanout to cost.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum RefreshPreference {
    /// The highest refresh the output offers at its current resolution.
    Max,
    /// The highest refresh at the current resolution that does not exceed this.
    Target(f64),
}

impl Default for RefreshPreference {
    /// 60 Hz: the shell's own motion budget is 30 fps, and every other client's
    /// per-frame work scales with the refresh rate.
    fn default() -> Self {
        RefreshPreference::Target(60.0)
    }
}

impl RefreshPreference {
    /// Parse a settings value: `"max"` or a refresh rate in hertz.
    ///
    /// Anything unrecognised - an absent key, a typo, a hand-edited negative -
    /// falls back to the default rather than being trusted.
    pub fn from_setting(raw: &str) -> Self {
        let value = raw.trim();
        if value.eq_ignore_ascii_case("max") {
            return RefreshPreference::Max;
        }
        match value.parse::<f64>() {
            Ok(hz) if hz.is_finite() && hz > 0.0 => RefreshPreference::Target(hz),
            _ => RefreshPreference::default(),
        }
    }

    /// The value written back to settings.
    pub fn as_setting(self) -> String {
        match self {
            RefreshPreference::Max => "max".to_string(),
            RefreshPreference::Target(hz) => {
                if (hz.fract()).abs() < f64::EPSILON {
                    format!("{}", hz as i64)
                } else {
                    format!("{hz}")
                }
            }
        }
    }
}

/// Parse `kscreen-doctor -j` output.
pub fn parse_kscreen_json(text: &str) -> DynResult<Vec<DisplayOutput>> {
    let dump: KscreenDump = serde_json::from_str(text)
        .map_err(|error| -> DynError { format!("unreadable display dump: {error}").into() })?;
    Ok(dump.outputs)
}

/// The mode to switch to, or `None` when the output offers nothing usable.
pub fn choose_mode(output: &DisplayOutput, target_hz: f64) -> Option<String> {
    let current = output.current_mode();
    let (width, height) = current
        .map(|mode| (mode.size.width, mode.size.height))
        .unwrap_or((0, 0));

    let mut candidates: Vec<&DisplayMode> = output
        .modes
        .iter()
        .filter(|mode| mode.size.width == width && mode.size.height == height)
        .collect();

    if candidates.is_empty() {
        return None;
    }

    // Highest refresh that does not exceed the target. A tenth of a hertz of
    // slack absorbs the rounding in reported rates (a mode called `@240` may
    // report 239.92), without letting a lower target reach a higher rate.
    candidates.sort_by(|a, b| b.refresh_hz.partial_cmp(&a.refresh_hz).unwrap_or(std::cmp::Ordering::Equal));
    if let Some(mode) = candidates.iter().find(|mode| mode.refresh_hz <= target_hz + 0.1) {
        return Some(mode.id.clone());
    }

    // ...or the lowest one when the target is below everything on offer.
    candidates
        .iter()
        .min_by(|a, b| a.refresh_hz.partial_cmp(&b.refresh_hz).unwrap_or(std::cmp::Ordering::Equal))
        .map(|mode| mode.id.clone())
}

/// The `(output, mode)` pairs that have to change for this preference.
///
/// Disabled or disconnected outputs are left alone (their mode is the
/// compositor's business), and an output already at the requested rate is not
/// touched - a mode switch blanks the output for a moment.
///
/// This never *un*-manages the display: whatever the session was running before
/// the first switch is journalled and put back when the shell exits, so no
/// "leave it alone" setting is needed here.
pub fn plan_outputs(outputs: &[DisplayOutput], preference: &RefreshPreference) -> Vec<(String, String)> {
    let target = match preference {
        RefreshPreference::Max => f64::INFINITY,
        RefreshPreference::Target(hz) => *hz,
    };

    outputs
        .iter()
        .filter(|output| output.enabled && output.connected)
        .filter_map(|output| {
            // A mode switch blanks the output for a moment, so only ask for one
            // when the rate actually changes.
            choose_mode(output, target)
                .filter(|id| *id != output.current_mode_id)
                .map(|id| (output.name.clone(), id))
        })
        .collect()
}

/// The argument kscreen-doctor expects when putting an output back.
///
/// The snapshot stores both the mode's name and its id: names survive a driver
/// reload renumbering ids (`2560x1600@240` is stable, `37` is not), so the name is
/// preferred and the id is the fallback. kscreen-doctor accepts either.
pub fn resolve_mode_reference(
    outputs: &[DisplayOutput],
    output_name: &str,
    mode_name: &str,
    mode_id: &str,
) -> Option<String> {
    let output = outputs.iter().find(|output| output.name == output_name)?;
    if output.modes.iter().any(|mode| mode.name == mode_name) {
        return Some(mode_name.to_string());
    }
    if output.modes.iter().any(|mode| mode.id == mode_id) {
        return Some(mode_id.to_string());
    }
    None
}

/// One atomic `kscreen-doctor` argument list for a plan.
///
/// kscreen-doctor applies every setting in a single invocation, so a multi-output
/// change never leaves the session in a half-switched state.
pub fn kscreen_args(plan: &[(String, String)]) -> Vec<String> {
    plan.iter()
        .map(|(output, mode)| format!("output.{output}.mode.{mode}"))
        .collect()
}
