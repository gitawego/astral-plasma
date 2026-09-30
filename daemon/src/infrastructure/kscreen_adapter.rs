//! Applying a display refresh preference through `kscreen-doctor`.
//!
//! The session journal lives in the cache directory next to the blur backup: the
//! first apply records what the outputs were running, so leaving the shell can put
//! the session back exactly as it was found. Nothing is applied when the outputs
//! already satisfy the preference or when the preference is `max`.

use crate::domain::branding;
use crate::domain::display_modes::{
    kscreen_args, parse_kscreen_json, plan_outputs, resolve_mode_reference, DisplayOutput,
    RefreshPreference,
};
use crate::domain::ports::DynResult;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::process::Command;

/// What the outputs were running before this theme changed them.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DisplaySnapshot {
    /// `(output, mode name, mode id)` per output that was switched.
    #[serde(default)]
    pub modes: Vec<DisplayModeRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayModeRef {
    pub output: String,
    pub name: String,
    pub id: String,
}

pub struct KscreenAdapter;

impl KscreenAdapter {
    pub fn new() -> Self {
        Self
    }

    pub fn backup_path(&self) -> PathBuf {
        branding::cache_dir()
            .join("display-backup")
            .join("display_backup.json")
    }

    /// Every output the compositor reports, with its modes.
    pub fn query(&self) -> DynResult<Vec<DisplayOutput>> {
        let out = Command::new("kscreen-doctor").arg("-j").output()?;
        let text = String::from_utf8_lossy(&out.stdout);
        parse_kscreen_json(&text)
    }

    /// The refresh rate each enabled output is running, for `display get`.
    pub fn current(&self) -> DynResult<Vec<(String, f64, String)>> {
        let outputs = self.query()?;
        Ok(outputs
            .iter()
            .filter(|output| output.enabled && output.connected)
            .filter_map(|output| {
                output
                    .current_mode()
                    .map(|mode| (output.name.clone(), mode.refresh_hz, mode.name.clone()))
            })
            .collect())
    }

    /// Remember what the session was running, once per applied preference.
    fn snapshot(&self, outputs: &[DisplayOutput], plan: &[(String, String)]) -> DynResult<()> {
        let path = self.backup_path();
        if path.is_file() {
            return Ok(());
        }
        let modes: Vec<DisplayModeRef> = plan
            .iter()
            .filter_map(|(name, _)| {
                let output = outputs.iter().find(|output| &output.name == name)?;
                let mode = output.current_mode()?;
                Some(DisplayModeRef {
                    output: output.name.clone(),
                    name: mode.name.clone(),
                    id: mode.id.clone(),
                })
            })
            .collect();
        if modes.is_empty() {
            return Ok(());
        }

        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let snapshot = DisplaySnapshot { modes };
        let json = serde_json::to_string_pretty(&snapshot)?;
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, json)?;
        fs::rename(&tmp, &path)?;
        Ok(())
    }

    /// Apply a preference. Returns the `(output, mode)` switches that were made.
    pub fn apply(&self, preference: RefreshPreference) -> DynResult<Vec<(String, String)>> {
        let outputs = self.query()?;
        let plan = plan_outputs(&outputs, &preference);
        if plan.is_empty() {
            return Ok(plan);
        }

        // Record the previous state before touching anything.
        self.snapshot(&outputs, &plan)?;

        let args = kscreen_args(&plan);
        let status = Command::new("kscreen-doctor").args(&args).status()?;
        if !status.success() {
            return Err(format!(
                "kscreen-doctor {} failed with {status}",
                args.join(" ")
            )
            .into());
        }
        Ok(plan)
    }

    /// Put back the modes that were running before the preference was applied.
    pub fn restore(&self) -> DynResult<bool> {
        let path = self.backup_path();
        if !path.is_file() {
            return Ok(false);
        }
        let snapshot: DisplaySnapshot = serde_json::from_str(&fs::read_to_string(&path)?)?;
        let outputs = self.query()?;

        let mut args = Vec::new();
        for entry in &snapshot.modes {
            if let Some(reference) =
                resolve_mode_reference(&outputs, &entry.output, &entry.name, &entry.id)
            {
                args.push(format!("output.{}.mode.{}", entry.output, reference));
            }
        }
        if !args.is_empty() {
            let status = Command::new("kscreen-doctor").args(&args).status()?;
            if !status.success() {
                return Err(format!("kscreen-doctor {} failed with {status}", args.join(" ")).into());
            }
        }
        let _ = fs::remove_file(&path);
        Ok(!args.is_empty())
    }
}

impl Default for KscreenAdapter {
    fn default() -> Self {
        Self::new()
    }
}
