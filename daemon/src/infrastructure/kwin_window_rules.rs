//! KWin window rules for the shell's xdg-toplevel surfaces.
//!
//! Quickshell's `FloatingWindow` (the AI Copilot and the Nexus Settings panel)
//! is a real xdg-toplevel, and KWin 6 decorates every xdg-toplevel by default,
//! so those windows grow a titlebar and a frame. A `kwinrulesrc` entry keyed on
//! the shell's window class with `noborder=true` (`noborderrule=2` = "force")
//! makes the windows frameless again while leaving the transparent surface
//! intact. Both toplevels share the class `org.quickshell`, so one rule covers
//! every shell window.
//!
//! Layer-shell panels use a different class (`quickshell`) and are never
//! touched by this rule.

use crate::domain::ports::DynResult;
use crate::infrastructure::kwin_shortcuts::{KWinShortcutsAdapter, KdeIniFile};
use std::fs;
use std::path::PathBuf;
use std::process::Command;

/// Rule keys KWin reads for a frameless window, in the exact spelling used by
/// the KDE Rules KCM.
const RULE_NOBORDER: (&str, &str) = ("noborder", "true");
const RULE_NOBORDER_RULE: (&str, &str) = ("noborderrule", "2");
const RULE_WMCLASS_MATCH: (&str, &str) = ("wmclassmatch", "1");

pub struct KWinWindowRulesAdapter {
    shortcuts: KWinShortcutsAdapter,
}

impl KWinWindowRulesAdapter {
    pub fn new() -> Self {
        Self { shortcuts: KWinShortcutsAdapter::new() }
    }

    fn kwinrules_path(&self) -> PathBuf {
        self.shortcuts.resolve_config_dir().join("kwinrulesrc")
    }

    /// Render `kwinrulesrc` with the frameless rule applied. Pure: parses the
    /// existing text, updates or appends one numeric rule group, and rewrites
    /// `[General]` so KWin sees a consistent rule list.
    pub fn render_kwinrulesrc(existing: &str, description: &str, wm_class: &str) -> String {
        let mut ini = KdeIniFile::parse(existing);

        // Reuse the group already carrying our marker so the rule is stable
        // across runs; otherwise take the next free numeric slot.
        let target = match Self::existing_marker_group(&ini, description) {
            Some(group) => group,
            None => Self::next_free_group_id(&ini),
        };

        ini.set(&target, "Description", description);
        ini.set(&target, RULE_NOBORDER.0, RULE_NOBORDER.1);
        ini.set(&target, RULE_NOBORDER_RULE.0, RULE_NOBORDER_RULE.1);
        ini.set(&target, "wmclass", wm_class);
        ini.set(&target, RULE_WMCLASS_MATCH.0, RULE_WMCLASS_MATCH.1);

        // `[General]` mirrors the numeric rule groups present after the edit.
        let ids = Self::numeric_rule_ids(&ini);
        ini.set("General", "count", &ids.len().to_string());
        ini.set("General", "rules", &ids.join(","));

        ini.serialize()
    }

    /// Apply the frameless rule to `kwinrulesrc`.
    ///
    /// Missing files are treated as empty, and the file is only rewritten when
    /// the rendered content differs, so re-running the daemon never churns the
    /// user's config or reconfigures KWin needlessly. Returns whether the file
    /// changed. Compositor absence is not an error: KWin is simply not asked to
    /// reload when nothing was written, and a missing `qdbus6` is ignored.
    pub fn apply(&self) -> DynResult<bool> {
        let path = self.kwinrules_path();
        let existing = fs::read_to_string(&path).unwrap_or_default();
        let rendered = Self::render_kwinrulesrc(
            &existing,
            crate::domain::branding::KWIN_RULE_ASSISTANT_DESCRIPTION,
            crate::domain::branding::WINDOW_CLASS_QUICKSHELL,
        );
        if rendered == existing {
            return Ok(false);
        }
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&path, rendered)?;
        self.reconfigure();
        Ok(true)
    }

    /// Is the frameless rule already exactly what [`Self::apply`] would write?
    ///
    /// The reconciler asks this instead of re-applying blindly: applying is
    /// cheap, but knowing the answer is what makes "no drift" observable.
    pub fn frameless_rule_present(&self) -> bool {
        let existing = fs::read_to_string(self.kwinrules_path()).unwrap_or_default();
        Self::render_kwinrulesrc(
            &existing,
            crate::domain::branding::KWIN_RULE_ASSISTANT_DESCRIPTION,
            crate::domain::branding::WINDOW_CLASS_QUICKSHELL,
        ) == existing
    }

    /// Ask the running compositor to re-read its window rules. Best-effort: a
    /// headless or non-KWin session has no `org.kde.KWin` service.
    fn reconfigure(&self) {
        let _ = Command::new("qdbus6")
            .args(["org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"])
            .output();
    }

    /// Group id of the rule carrying `description`, if any.
    pub fn rule_group_id(content: &str, description: &str) -> Option<String> {
        let ini = KdeIniFile::parse(content);
        Self::existing_marker_group(&ini, description)
    }

    /// The numeric group whose `Description` matches `description`.
    ///
    /// Only numeric groups are rules: `[General]` and any other named group are
    /// bookkeeping/custom sections and must never be matched or overwritten.
    fn existing_marker_group(ini: &KdeIniFile, description: &str) -> Option<String> {
        ini.groups
            .iter()
            .filter(|(group, _)| parse_rule_id(group).is_some())
            .find(|(_, keys)| keys.get("Description").map(|d| d == description).unwrap_or(false))
            .map(|(group, _)| group.clone())
    }

    /// Smallest numeric rule id greater than every existing rule id.
    ///
    /// KWin rule groups are `[1]`, `[2]`, ... so the successor of the current
    /// maximum is always free; an empty file yields `[1]`.
    fn next_free_group_id(ini: &KdeIniFile) -> String {
        let max = ini
            .groups
            .keys()
            .filter_map(|group| parse_rule_id(group))
            .max()
            .unwrap_or(0);
        (max + 1).to_string()
    }

    /// Numeric rule group ids present, ascending.
    fn numeric_rule_ids(ini: &KdeIniFile) -> Vec<String> {
        let mut ids: Vec<u64> = ini.groups.keys().filter_map(|group| parse_rule_id(group)).collect();
        ids.sort_unstable();
        ids.into_iter().map(|id| id.to_string()).collect()
    }
}

impl Default for KWinWindowRulesAdapter {
    fn default() -> Self {
        Self::new()
    }
}

/// Rule group ids are plain positive integers; anything else (`General`, custom
/// sections) is not a KWin rule.
fn parse_rule_id(group: &str) -> Option<u64> {
    let trimmed = group.trim();
    if trimmed.is_empty() || !trimmed.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    trimmed.parse::<u64>().ok()
}
