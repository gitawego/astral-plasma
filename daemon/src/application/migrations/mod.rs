//! One-time repairs that reach installs which already exist.
//!
//! A release cannot fix an installed layout by shipping new code alone: the
//! files on the user's disk were written by an older build, and code that only
//! applies to fresh installs leaves every existing user behind. Installers are
//! the wrong place for those repairs - an installer is a script that ran once
//! and may never run again, while a migration is code that runs on every start
//! until it has succeeded.
//!
//! The contract, borrowed from the one mechanism that has to survive arbitrary
//! user machines (Omarchy's `migrations/*.sh`):
//!
//! * **Idempotent** - a second run is a no-op, not a second repair.
//! * **Per-user marker** - completion is recorded under the state directory, so
//!   two users on one machine each get their own run.
//! * **Ordered** - registry order is execution order; names never change once
//!   shipped, because the marker is the name.
//! * **Blocking on failure** - a failed migration stops the shell from starting.
//!   Starting anyway would leave a half-migrated desktop that looks fine until
//!   the next update.

pub mod legacy_layout;

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

use crate::domain::branding;
use crate::domain::ports::DynResult;

/// Directories a migration may touch, resolved once so tests can point the
/// whole set at a temporary root instead of the live desktop.
#[derive(Debug, Clone)]
pub struct MigrationContext {
    pub home_dir: PathBuf,
    pub config_home: PathBuf,
    pub data_dir: PathBuf,
    pub state_dir: PathBuf,
    pub package_dir: PathBuf,
    pub bin_path: PathBuf,
    pub systemd_dir: PathBuf,
    pub marker_dir: PathBuf,
    /// Executable to install when adopting a legacy layout. `None` means "the
    /// executable running this migration"; tests pin it to a fixture so they do
    /// not depend on where the test harness itself lives.
    pub source_bin: Option<PathBuf>,
}

impl MigrationContext {
    /// The live desktop's directories.
    pub fn for_user() -> Self {
        Self {
            home_dir: branding::home_dir(),
            config_home: branding::config_home(),
            data_dir: branding::data_dir(),
            state_dir: branding::state_dir(),
            package_dir: branding::default_package_dir(),
            bin_path: branding::bin_path(),
            systemd_dir: branding::config_home().join("systemd").join("user"),
            marker_dir: branding::migrations_dir(),
            source_bin: None,
        }
    }

    /// A context rooted at `root`, for tests and dry runs.
    pub fn rooted_at(root: &Path) -> Self {
        let home = root.join("home");
        let config = root.join("config");
        let data = root.join("data").join(branding::DATA_DIR);
        let state = root.join("state").join(branding::STATE_DIR);
        Self {
            home_dir: home.clone(),
            config_home: config.clone(),
            data_dir: data.clone(),
            state_dir: state.clone(),
            package_dir: data.join(branding::PACKAGE_SUBDIR),
            bin_path: data.join(branding::BIN_SUBDIR).join(branding::BIN_FILE),
            systemd_dir: config.join("systemd").join("user"),
            marker_dir: state.join(branding::MIGRATIONS_SUBDIR),
            source_bin: None,
        }
    }
}

/// What a migration did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MigrationOutcome {
    /// The repair ran; the message is shown to the user once.
    Changed(String),
    /// The install already matched the contract; nothing was written.
    AlreadySatisfied,
}

impl MigrationOutcome {
    pub fn message(&self) -> Option<&str> {
        match self {
            Self::Changed(message) => Some(message),
            Self::AlreadySatisfied => None,
        }
    }
}

/// One repair.
pub trait Migration {
    /// Stable identifier; also the marker file name. Never rename.
    fn name(&self) -> &'static str;
    /// One line for `migrate --pending`.
    fn describe(&self) -> &'static str;
    fn run(&self, ctx: &MigrationContext) -> DynResult<MigrationOutcome>;
}

/// A completed migration, as reported by the CLI.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CompletedMigration {
    pub name: String,
    /// False when the migration found the install already correct.
    pub changed: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

/// Marker file contents.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct Marker {
    name: String,
    completed_at_unix: u64,
    #[serde(default)]
    message: Option<String>,
}

/// Runs pending migrations in registry order.
pub struct MigrationRunner {
    marker_dir: PathBuf,
    migrations: Vec<Box<dyn Migration>>,
}

impl MigrationRunner {
    /// The migrations this build ships, in execution order.
    pub fn standard(ctx: &MigrationContext) -> Self {
        Self::with_migrations(ctx.marker_dir.clone(), registry())
    }

    /// A runner over an explicit list, so tests can prove ordering and blocking
    /// without shipping a deliberately broken migration.
    pub fn with_migrations(marker_dir: PathBuf, migrations: Vec<Box<dyn Migration>>) -> Self {
        Self {
            marker_dir,
            migrations,
        }
    }

    pub fn marker_dir(&self) -> &Path {
        &self.marker_dir
    }

    pub fn is_complete(&self, name: &str) -> bool {
        self.marker_dir.join(name).is_file()
    }

    /// Names not yet marked complete, in order.
    pub fn pending(&self) -> Vec<(&'static str, &'static str)> {
        self.migrations
            .iter()
            .map(|m| (m.name(), m.describe()))
            .filter(|(name, _)| !self.is_complete(name))
            .collect()
    }

    /// Run every pending migration and mark it complete.
    ///
    /// A failing migration is returned as an error naming itself, and the ones
    /// after it do not run: the caller must refuse to start the shell rather
    /// than continue from an unknown state.
    pub fn run_pending(&self, ctx: &MigrationContext) -> DynResult<Vec<CompletedMigration>> {
        let mut completed = Vec::new();

        for (name, _) in self.pending() {
            let migration = self
                .migrations
                .iter()
                .find(|m| m.name() == name)
                .ok_or_else(|| format!("migration '{name}' is registered but not implemented"))?;

            let outcome = migration
                .run(ctx)
                .map_err(|err| format!("migration '{name}' failed: {err}"))?;

            let changed = matches!(outcome, MigrationOutcome::Changed(_));
            let message = outcome.message().map(str::to_string);
            self.write_marker(name, message.as_deref())?;
            completed.push(CompletedMigration {
                name: name.to_string(),
                changed,
                message,
            });
        }

        Ok(completed)
    }

    fn write_marker(&self, name: &str, message: Option<&str>) -> DynResult<()> {
        fs::create_dir_all(&self.marker_dir)?;
        let marker = Marker {
            name: name.to_string(),
            completed_at_unix: crate::domain::install_record::now_unix(),
            message: message.map(str::to_string),
        };
        let path = self.marker_dir.join(name);
        let tmp = self.marker_dir.join(format!(".{name}.tmp"));
        fs::write(&tmp, format!("{}\n", serde_json::to_string_pretty(&marker)?))?;
        fs::rename(&tmp, &path)?;
        Ok(())
    }
}

/// Every migration this build knows, in execution order.
pub fn registry() -> Vec<Box<dyn Migration>> {
    vec![Box::new(legacy_layout::LegacyLayoutMigration)]
}

/// Run pending migrations against the live directories.
///
/// Called by `astral-plasma run` before the shell starts, and by
/// `astral-plasma migrate`.
pub fn run_pending_for_user() -> DynResult<Vec<CompletedMigration>> {
    let ctx = MigrationContext::for_user();
    MigrationRunner::standard(&ctx).run_pending(&ctx)
}
