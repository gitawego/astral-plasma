//! Adopt the layouts that existed before this feature.
//!
//! Two of them are real and both are still on users' disks:
//!
//! 1. **Symlinked checkout** - `install.sh` used to symlink the git checkout
//!    into `~/.config/quickshell`. The shell then ran from the checkout, so
//!    there was nothing to update and nothing to roll back to.
//! 2. **Unit pointing at Quickshell** - `astral-plasma systemd install` wrote
//!    `ExecStart=<quickshell> -p <dir>`, which skipped the supervisor entirely:
//!    no Plasma claim, no shortcut journal, no restore on exit.
//!
//! This migration copies what is needed into the managed layout, records the
//! owner, and rewrites the unit to run the supervisor. It **copies**; nothing is
//! moved and the checkout is never modified, because the checkout may hold the
//! user's own commits.
//!
//! The `~/.config/quickshell` symlink itself is deliberately left in place.
//! Removing a user-visible config path is a destructive change that needs the
//! user's confirmation (AGENTS.md §4b); the outcome message names it, and the
//! Updates page offers removal.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use crate::application::migrations::{Migration, MigrationContext, MigrationOutcome};
use crate::domain::branding;
use crate::domain::install_record::{self, InstallMethod, InstallRecord};
use crate::domain::ports::DynResult;
use crate::infrastructure::embedded_bundle::extract_embedded_theme;

/// Marker name and registry identity. Never rename.
pub const NAME: &str = "001_adopt_legacy_install";

pub struct LegacyLayoutMigration;

impl Migration for LegacyLayoutMigration {
    fn name(&self) -> &'static str {
        NAME
    }

    fn describe(&self) -> &'static str {
        "Adopt a symlinked checkout or a Quickshell-only unit into the managed layout"
    }

    fn run(&self, ctx: &MigrationContext) -> DynResult<MigrationOutcome> {
        let record_path = install_record::record_path_in(&ctx.data_dir);
        let record = InstallRecord::read(&record_path)?;

        // A package-managed or checkout install has a different owner. Writing
        // our files there would be the two-owners failure this record prevents.
        if let Some(existing) = &record {
            if existing.method != InstallMethod::Managed {
                return Ok(MigrationOutcome::AlreadySatisfied);
            }
        }

        let legacy_link = ctx.config_home.join("quickshell");
        let legacy_source = resolve_legacy_checkout(&legacy_link);
        let unit_path = ctx.systemd_dir.join(branding::SYSTEMD_UNIT);
        let legacy_unit = unit_needs_rewrite(&unit_path)?;
        let bundle_missing = !ctx.package_dir.join("shell.qml").is_file();

        if record.is_some() && legacy_source.is_none() && !legacy_unit && !bundle_missing {
            return Ok(MigrationOutcome::AlreadySatisfied);
        }

        // 1. The binary the unit will exec.
        //
        //    Prefer the executable that is running this migration: by definition
        //    it works here, while a checkout's `bin/` may be stale. A debug
        //    build is the exception - adopting `target/debug` as a user's daily
        //    shell would degrade the desktop, so that case takes the checkout's
        //    release build and refuses rather than installs something worse.
        if !ctx.bin_path.is_file() {
            let source = ctx
                .source_bin
                .clone()
                .or_else(|| std::env::current_exe().ok());
            let source = match source {
                Some(exe) if !is_development_build(&exe) => exe,
                Some(exe) => {
                    return Err(format!(
                        "refusing to adopt {}: a cargo debug build is not an install. \
                         Run `make build` and start bin/astral-plasma, or use install.sh.",
                        exe.display()
                    )
                    .into())
                }
                None => {
                    return Err("cannot adopt the legacy install: the running executable \
                                could not be resolved. Use install.sh instead."
                        .into())
                }
            };
            copy_executable(&source, &ctx.bin_path)?;
        }

        // 2. The bundle this binary can actually run. Extracted from *this*
        //    build rather than copied from the checkout, so binary and QML
        //    cannot disagree (the desync the update design forbids).
        extract_embedded_theme(&ctx.package_dir)?;

        // 3. The record.
        let installed_at = record
            .as_ref()
            .map(|r| r.installed_at_unix)
            .unwrap_or_else(install_record::now_unix);
        InstallRecord::new(
            InstallMethod::Managed,
            env!("CARGO_PKG_VERSION"),
            record
                .as_ref()
                .map(|r| r.channel.clone())
                .unwrap_or_else(|| "stable".to_string()),
            installed_at,
        )
        .write(&record_path)?;

        // 4. The unit, if the user installed one.
        if legacy_unit {
            rewrite_unit(&unit_path, &ctx.bin_path, &ctx.package_dir)?;
        }

        let mut message = format!(
            "Astral Plasma {version} now lives in {data} and can update itself.",
            version = env!("CARGO_PKG_VERSION"),
            data = ctx.data_dir.display()
        );
        if let Some(dir) = legacy_source {
            message.push_str(&format!(
                " Your existing checkout at {link} was left untouched (it points at {dir}); remove it from Settings → Updates if you no longer use it.",
                link = legacy_link.display(),
                dir = dir.display()
            ));
        }

        Ok(MigrationOutcome::Changed(message))
    }
}

/// Whether this executable is a cargo build rather than something a user would
/// want installed as their desktop shell (`target/debug`, `target/debug/deps`).
fn is_development_build(exe: &Path) -> bool {
    let parts: Vec<String> = exe
        .components()
        .map(|c| c.as_os_str().to_string_lossy().to_string())
        .collect();
    parts
        .windows(2)
        .any(|pair| pair[0] == "target" && (pair[1] == "debug" || pair[1] == "deps"))
}

/// Resolve `~/.config/quickshell` when it is a legacy symlink (or a directory
/// that plainly is a checkout) into its target.
fn resolve_legacy_checkout(link: &Path) -> Option<PathBuf> {
    let meta = fs::symlink_metadata(link).ok()?;
    if meta.file_type().is_symlink() {
        let target = fs::read_link(link).ok()?;
        let resolved = if target.is_absolute() {
            target
        } else {
            link.parent()?.join(target)
        };
        return resolved.join("shell.qml").is_file().then_some(resolved);
    }
    // An older install may have copied rather than linked.
    (meta.is_dir() && link.join("shell.qml").is_file()).then(|| link.to_path_buf())
}

fn unit_needs_rewrite(unit_path: &Path) -> DynResult<bool> {
    let text = match fs::read_to_string(unit_path) {
        Ok(text) => text,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(err) => return Err(Box::new(err)),
    };
    Ok(exec_start_line(&text)
        .map(|line| {
            let rest = line.trim_start_matches("ExecStart=");
            // Any ExecStart that is not this binary's `run` subcommand is a
            // previous layout: `quickshell -p <dir>`, or an old path.
            !rest.starts_with(branding::BIN_FILE) || !rest.trim_end().ends_with(" run")
        })
        .unwrap_or(false))
}

fn exec_start_line(unit: &str) -> Option<&str> {
    unit.lines().find(|line| line.starts_with("ExecStart="))
}

/// Copy a binary, preserving the executable bit and replacing atomically.
fn copy_executable(source: &Path, dest: &Path) -> DynResult<()> {
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = dest.with_extension("adopt.tmp");
    fs::copy(source, &tmp)?;
    fs::set_permissions(&tmp, fs::Permissions::from_mode(0o755))?;
    fs::rename(&tmp, dest)?;
    Ok(())
}

/// Point the unit at the supervisor and pin the package directory it serves.
fn rewrite_unit(unit_path: &Path, bin_path: &Path, package_dir: &Path) -> DynResult<()> {
    let text = fs::read_to_string(unit_path)?;
    let exec = format!("ExecStart={} run", bin_path.display());
    let env = format!("Environment=ASTRAL_PLASMA_PACKAGE_DIR={}", package_dir.display());

    let mut lines: Vec<String> = Vec::new();
    let mut wrote_exec = false;
    for line in text.lines() {
        if line.starts_with("ExecStart=") && !wrote_exec {
            lines.push(exec.clone());
            if !text.contains("ASTRAL_PLASMA_PACKAGE_DIR=") {
                lines.push(env.clone());
            }
            wrote_exec = true;
            continue;
        }
        if line.starts_with("ASTRAL_PLASMA_PACKAGE_DIR=") {
            continue;
        }
        lines.push(line.to_string());
    }
    if !wrote_exec {
        lines.push(exec);
        if !text.contains("ASTRAL_PLASMA_PACKAGE_DIR=") {
            lines.push(env);
        }
    }

    let body = format!("{}\n", lines.join("\n"));
    let tmp = unit_path.with_extension("service.tmp");
    fs::write(&tmp, body)?;
    fs::set_permissions(&tmp, fs::Permissions::from_mode(0o644))?;
    fs::rename(&tmp, unit_path)?;
    Ok(())
}
