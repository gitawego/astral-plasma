use crate::domain::branding;
use crate::domain::ports::DynResult;
use crate::domain::wallpaper::{ColorPalette, Wallpaper, WallpaperPort, WallpaperType};
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

const DESKTOP_CONTAINMENT_PLUGIN: &str = "org.kde.plasma.folder";
const PANEL_CONTAINMENT_PLUGIN: &str = "org.kde.panel";
const APPLETSRC: &str = "plasma-org.kde.plasma.desktop-appletsrc";

/// Wallpaper configured for the desktop containment in KDE's appletsrc.
///
/// The file groups everything by containment. Panels carry their own
/// `wallpaperplugin` - and can hold an `Image=` key - so the desktop containment
/// (the one declaring `plugin=org.kde.plasma.folder`) is resolved first. Only
/// when no containment declares that plugin does any non-panel containment
/// qualify, which keeps older or minimal configs working.
pub fn desktop_wallpaper_from_appletsrc(content: &str) -> Option<PathBuf> {
    let mut desktops: Vec<&str> = Vec::new();
    let mut panels: Vec<&str> = Vec::new();
    let mut candidates: Vec<(&str, PathBuf)> = Vec::new();
    let mut section: Vec<&str> = Vec::new();

    for line in content.lines() {
        let line = line.trim();
        if let Some(inner) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            section = inner.split("][").collect();
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let (key, value) = (key.trim(), value.trim());
        match section.as_slice() {
            ["Containments", id] => {
                if key != "plugin" {
                    continue;
                }
                if value == DESKTOP_CONTAINMENT_PLUGIN {
                    desktops.push(id);
                } else if value == PANEL_CONTAINMENT_PLUGIN {
                    panels.push(id);
                }
            }
            ["Containments", id, "Wallpaper", "org.kde.image", "General"] => {
                if key == "Image" && !value.is_empty() {
                    let path = value.strip_prefix("file://").unwrap_or(value);
                    candidates.push((id, PathBuf::from(path)));
                }
            }
            _ => {}
        }
    }

    candidates
        .iter()
        .find(|(id, _)| desktops.contains(id))
        .or_else(|| candidates.iter().find(|(id, _)| !panels.contains(id)))
        .map(|(_, path)| path.clone())
}

/// What to do when the shell's remembered wallpaper and the desktop's applied
/// wallpaper disagree.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WallpaperReconcile {
    /// The picker's choice is authoritative: put it back on the desktop.
    ApplyState(PathBuf),
    /// The desktop was changed outside the shell: remember it instead of
    /// fighting it.
    AdoptApplied(PathBuf),
    /// Nothing to reconcile.
    Nothing,
}

/// Decide who wins when the two records of "the current wallpaper" disagree.
///
/// The state file records the wallpaper the user picked in the picker, and that
/// choice is what the shell must keep on screen: a plasmashell restart rewrites
/// its containment config from its own saved state and silently reverts the
/// wallpaper, after which the picker would focus a wallpaper the user never
/// chose. A desktop wallpaper the shell never wrote (no state at all) is adopted
/// instead, so a fresh session follows whatever the desktop already shows.
pub fn reconcile_decision(applied: Option<&Path>, state: Option<&Path>) -> WallpaperReconcile {
    match (applied, state) {
        (Some(applied), Some(state)) if applied != state => {
            WallpaperReconcile::ApplyState(state.to_path_buf())
        }
        (None, Some(state)) => WallpaperReconcile::ApplyState(state.to_path_buf()),
        (Some(applied), _) => WallpaperReconcile::AdoptApplied(applied.to_path_buf()),
        (None, None) => WallpaperReconcile::Nothing,
    }
}

/// The Plasma scripting call that sets the image on every desktop containment.
///
/// `plasma-apply-wallpaperimage` is a thin client over this interface. Going
/// through Plasma itself is what makes the running containment reload the
/// wallpaper, so the desktop repaints instead of keeping the old image until
/// plasmashell restarts. The path is emitted as a JSON string literal, which is
/// also a valid JS literal and therefore escapes quotes and backslashes.
pub fn plasma_wallpaper_script(path: &Path) -> String {
    let url = format!("file://{}", path.to_string_lossy());
    let literal = serde_json::to_string(&url).unwrap_or_else(|_| "\"\"".to_string());
    format!(
        "var ds = desktops();\n\
         for (var i = 0; i < ds.length; i++) {{\n\
         \x20 ds[i].wallpaperPlugin = \"org.kde.image\";\n\
         \x20 ds[i].currentConfigGroup = [\"Wallpaper\", \"org.kde.image\", \"General\"];\n\
         \x20 ds[i].writeConfig(\"Image\", {literal});\n\
         }}"
    )
}

/// The command that asks the running Plasma shell to write the wallpaper.
///
/// `plasma-apply-wallpaperimage` is a thin client over this interface, and going
/// through Plasma itself is what makes the running containment reload the
/// wallpaper - a config write on its own can sit unapplied until plasmashell
/// restarts. `qdbus6` is how the rest of the daemon talks to Plasma, and a
/// subprocess is also what keeps this callable from the CLI's async runtime.
pub fn plasma_apply_command(path: &Path) -> (String, Vec<String>) {
    (
        "qdbus6".to_string(),
        vec![
            "org.kde.plasmashell".to_string(),
            "/PlasmaShell".to_string(),
            "org.kde.PlasmaShell.evaluateScript".to_string(),
            plasma_wallpaper_script(path),
        ],
    )
}

/// Ask the running Plasma shell to write and reload the desktop wallpaper.
fn apply_wallpaper_via_plasma(path: &Path) -> DynResult<()> {
    let (program, args) = plasma_apply_command(path);
    let output = Command::new(&program).args(&args).output()?;
    if !output.status.success() {
        return Err(format!(
            "{program} exited with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        )
        .into());
    }
    Ok(())
}

pub struct FsWallpaperAdapter {
    home_dir: PathBuf,
    state_path: PathBuf,
    thumbnail_cache_dir: PathBuf,
}

impl Default for FsWallpaperAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl FsWallpaperAdapter {
    pub fn new() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/user".to_string());
        let home_dir = PathBuf::from(&home);
        let state_path = branding::state_dir().join("wallpaper").join("path.txt");
        let thumbnail_cache_dir = branding::cache_dir().join("thumbnails");

        Self {
            home_dir,
            state_path,
            thumbnail_cache_dir,
        }
    }

    pub fn with_state_path(state_path: PathBuf) -> Self {
        let home_dir = state_path.parent().map(Path::to_path_buf).unwrap_or_else(|| PathBuf::from("/tmp"));
        Self::with_paths(home_dir, state_path)
    }


    pub fn with_paths(home_dir: PathBuf, state_path: PathBuf) -> Self {
        let thumbnail_cache_dir = home_dir
            .join(".cache")
            .join(branding::CACHE_DIR)
            .join("thumbnails");
        Self {
            home_dir,
            state_path,
            thumbnail_cache_dir,
        }
    }

    fn appletsrc_path(&self) -> PathBuf {
        self.home_dir.join(".config").join(APPLETSRC)
    }

    /// The wallpaper actually applied to the desktop, if it still exists.
    fn applied_wallpaper(&self) -> Option<PathBuf> {
        let content = fs::read_to_string(self.appletsrc_path()).ok()?;
        desktop_wallpaper_from_appletsrc(&content).filter(|path| path.exists())
    }

    /// The last wallpaper the shell wrote, when no Plasma desktop answers.
    fn state_wallpaper(&self) -> Option<PathBuf> {
        let content = fs::read_to_string(&self.state_path).ok()?;
        let trimmed = content.trim();
        (!trimmed.is_empty()).then(|| PathBuf::from(trimmed))
    }

    fn write_state(&self, path: &Path) -> DynResult<()> {
        if let Some(parent) = self.state_path.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut file = File::create(&self.state_path)?;
        writeln!(file, "{}", path.to_string_lossy())?;
        Ok(())
    }

    /// Keep the desktop on the wallpaper the user picked.
    ///
    /// Returns the wallpaper that is now current.
    pub fn reconcile_active_wallpaper(&self) -> DynResult<Option<PathBuf>> {
        let applied = self.applied_wallpaper();
        let state = self.state_wallpaper().filter(|path| path.exists());

        match reconcile_decision(applied.as_deref(), state.as_deref()) {
            WallpaperReconcile::ApplyState(path) => {
                self.set_active_wallpaper(&path)?;
                Ok(Some(path))
            }
            WallpaperReconcile::AdoptApplied(path) => {
                self.write_state(&path)?;
                Ok(Some(path))
            }
            WallpaperReconcile::Nothing => Ok(None),
        }
    }

    fn ensure_thumbnail_for_video(&self, wallpaper: &mut Wallpaper) {
        if !wallpaper.is_video {
            wallpaper.thumbnail_path = Some(wallpaper.path.clone());
            return;
        }

        let _ = fs::create_dir_all(&self.thumbnail_cache_dir);
        let thumb_filename = format!("{}.jpg", wallpaper.id);
        let thumb_path = self.thumbnail_cache_dir.join(&thumb_filename);

        if thumb_path.exists() {
            wallpaper.thumbnail_path = Some(thumb_path);
            return;
        }

        // Fast ffmpeg single-frame extraction (at 1s mark)
        let status = Command::new("ffmpeg")
            .args([
                "-ss", "00:00:01",
                "-i", &wallpaper.path.to_string_lossy(),
                "-vframes", "1",
                "-vf", "scale=480:-1",
                "-q:v", "3",
                "-y",
                &thumb_path.to_string_lossy(),
            ])
            .output();

        if let Ok(out) = status {
            if out.status.success() && thumb_path.exists() {
                wallpaper.thumbnail_path = Some(thumb_path);
                return;
            }
        }

        wallpaper.thumbnail_path = None;
    }

    fn scan_recursive(&self, dir: &Path, base_dir: &Path, depth: u32, out: &mut Vec<Wallpaper>) {
        if depth > 4 {
            return;
        }

        let entries = match fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => return,
        };

        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                // Don't recurse into hidden directories
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if !name.starts_with('.') {
                        self.scan_recursive(&path, base_dir, depth + 1, out);
                    }
                }
            } else if path.is_file() {
                if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                    if stem.eq_ignore_ascii_case("screenshot") {
                        continue;
                    }
                }
                let wtype = WallpaperType::from_path(&path);
                if wtype != WallpaperType::Unsupported {
                    let mut wall = Wallpaper::from_file(&path, base_dir, None);
                    self.ensure_thumbnail_for_video(&mut wall);
                    out.push(wall);
                }
            }
        }
    }
}

impl WallpaperPort for FsWallpaperAdapter {
    fn scan_wallpapers(&self, dir: &Path) -> DynResult<Vec<Wallpaper>> {
        let mut results = Vec::new();
        if dir.is_dir() {
            self.scan_recursive(dir, dir, 0, &mut results);
        }
        if results.is_empty() && dir != Path::new("/usr/share/wallpapers") {
            let sys_dir = Path::new("/usr/share/wallpapers");
            if sys_dir.is_dir() {
                self.scan_recursive(sys_dir, sys_dir, 0, &mut results);
            }
        }
        results.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        Ok(results)
    }

    fn scan_library(&self) -> DynResult<Vec<Wallpaper>> {
        let mut results = Vec::new();
        let mut seen_paths: std::collections::HashSet<PathBuf> = std::collections::HashSet::new();

        let mut add_file = |path: &Path, base_dir: &Path, out: &mut Vec<Wallpaper>| {
            if !path.is_file() {
                return;
            }
            if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                if stem.eq_ignore_ascii_case("screenshot") {
                    return;
                }
            }
            let wtype = WallpaperType::from_path(path);
            if wtype != WallpaperType::Unsupported {
                let canonical = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
                if seen_paths.insert(canonical) {
                    let mut wall = Wallpaper::from_file(path, base_dir, None);
                    self.ensure_thumbnail_for_video(&mut wall);
                    out.push(wall);
                }
            }
        };

        // 1. KDE Plasma plasmarc ([Wallpapers] usersWallpapers=...)
        let plasmarc = self.home_dir.join(".config").join("plasmarc");
        if plasmarc.is_file() {
            if let Ok(content) = fs::read_to_string(&plasmarc) {
                for line in content.lines() {
                    let trimmed = line.trim();
                    if let Some(val) = trimmed.strip_prefix("usersWallpapers=") {
                        for item in val.split(',') {
                            let item_clean = item.trim();
                            let clean_path = if let Some(stripped) = item_clean.strip_prefix("file://") {
                                stripped
                            } else {
                                item_clean
                            };
                            if !clean_path.is_empty() {
                                let p = PathBuf::from(clean_path);
                                if p.is_file() {
                                    let parent = p.parent().unwrap_or(&p);
                                    add_file(&p, parent, &mut results);
                                } else if p.is_dir() {
                                    self.scan_recursive(&p, &p, 0, &mut results);
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. KDE Plasma desktop-appletsrc (the applied wallpaper + SlidePaths)
        let appletsrc = self.appletsrc_path();
        if appletsrc.is_file() {
            if let Ok(content) = fs::read_to_string(&appletsrc) {
                if let Some(active) = desktop_wallpaper_from_appletsrc(&content) {
                    if active.is_file() {
                        let parent = active.parent().unwrap_or(&active).to_path_buf();
                        add_file(&active, &parent, &mut results);
                    }
                }
                for line in content.lines() {
                    let trimmed = line.trim();
                    if let Some(val) = trimmed.strip_prefix("SlidePaths=") {
                        for item in val.split(',') {
                            let p = PathBuf::from(item.trim());
                            if p.is_dir() {
                                self.scan_recursive(&p, &p, 0, &mut results);
                            }
                        }
                    }
                }
            }
        }

        // 3. User wallpaper directories
        let user_dirs = [
            self.home_dir.join("Pictures").join("wallpapers"),
            self.home_dir.join("Pictures").join("Wallpapers"),
            self.home_dir.join("Pictures").join("Wallpaper"),
            self.home_dir.join(".local").join("share").join("wallpapers"),
        ];

        for udir in &user_dirs {
            if udir.is_dir() {
                self.scan_recursive(udir, udir, 0, &mut results);
            }
        }

        // 4. System wallpapers
        let sys_dirs = [
            PathBuf::from("/usr/share/wallpapers"),
            PathBuf::from("/usr/local/share/wallpapers"),
        ];
        for sdir in &sys_dirs {
            if sdir.is_dir() {
                self.scan_recursive(sdir, sdir, 0, &mut results);
            }
        }

        // Deduplicate resolution duplicates and exact name/category pairs
        let mut final_results = Vec::new();
        let mut seen_ids = std::collections::HashSet::new();
        for wall in results {
            let key = (wall.name.to_lowercase(), wall.category.to_lowercase());
            if seen_ids.insert(key) {
                final_results.push(wall);
            }
        }

        final_results.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        Ok(final_results)
    }

    fn get_active_wallpaper(&self) -> DynResult<Option<PathBuf>> {
        // The desktop's own wallpaper is the ground truth: the picker focuses
        // this, so it has to be what the user sees. The state file only records
        // the last path the shell *wrote* - it drifts whenever the wallpaper is
        // changed outside the shell, or when an apply fails - so it is the
        // fallback.
        if let Some(applied) = self.applied_wallpaper() {
            return Ok(Some(applied));
        }
        Ok(self.state_wallpaper())
    }

    fn set_active_wallpaper(&self, path: &Path) -> DynResult<()> {
        self.write_state(path)?;

        if !path.exists() {
            return Ok(());
        }

        // KDE's own tool is the documented way to set the desktop wallpaper. Its
        // result used to be ignored: an apply that failed left the state file
        // claiming a wallpaper the desktop never showed, and the picker then
        // focused that invisible wallpaper. Verify the containment really points
        // at the requested image.
        let config_updated = Command::new("plasma-apply-wallpaperimage")
            .arg(path)
            .status()
            .map(|status| status.success())
            .unwrap_or(false)
            && self.applied_wallpaper().as_deref() == Some(path);

        if !config_updated {
            eprintln!(
                "[wallpaper] plasma-apply-wallpaperimage did not record {path:?} in the containment config"
            );
        }

        // The tool persists the containment config, but a path it accepts is not
        // always handed to the *running* containment - a wallpaper written to the
        // config but never applied live is exactly how the picker ended up
        // focusing a wallpaper the desktop was not showing. Asking Plasma itself
        // makes the live desktop repaint; the call is idempotent, so it always
        // runs. Best effort: on a session without plasmashell the state file (and
        // the shell's own wallpaper layer) still carry the change.
        if let Err(error) = apply_wallpaper_via_plasma(path) {
            eprintln!("[wallpaper] plasma scripting apply failed: {error}");
        }

        Ok(())
    }



    fn extract_palette(&self, path: &Path) -> DynResult<ColorPalette> {
        // Run matugen if installed, or fallback to pastel
        let output = Command::new("matugen")
            .args(["image", &path.to_string_lossy(), "--source-color-index", "0", "--json", "hex"])
            .output();

        if let Ok(out) = output {
            if out.status.success() {
                // Save to ~/.cache/astral-plasma/colors.json for Colors.qml
                let cache_dir = branding::cache_dir();
                let _ = fs::create_dir_all(&cache_dir);
                let colors_file = cache_dir.join("colors.json");
                let _ = fs::write(&colors_file, &out.stdout);

                if let Ok(parsed) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
                    if let Some(colors) = parsed.get("colors").and_then(|c| c.get("dark")) {
                        let primary = colors.get("primary").and_then(|v| v.as_str()).unwrap_or("#cba6f7").to_string();
                        let secondary = colors.get("secondary").and_then(|v| v.as_str()).unwrap_or("#89b4fa").to_string();
                        let surface = colors.get("surface").and_then(|v| v.as_str()).unwrap_or("#1e1e2e").to_string();
                        let on_surface = colors.get("on_surface").and_then(|v| v.as_str()).unwrap_or("#cdd6f4").to_string();
                        let accent = colors.get("tertiary").and_then(|v| v.as_str()).unwrap_or("#f5c2e7").to_string();

                        return Ok(ColorPalette {
                            primary,
                            secondary,
                            surface,
                            on_surface,
                            accent,
                            is_dark: true,
                        });
                    }
                }
            }
        }

        Ok(ColorPalette::default_pastel())
    }
}
