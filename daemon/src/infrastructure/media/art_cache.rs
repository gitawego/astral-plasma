//! Bounded disk footprint of the extracted-artwork cache.
//!
//! The cache stores whatever the player or the provider served, and nothing on
//! the drawing side needs more than a few hundred device pixels. A live session
//! had grown to 141 files / 29 MB, holding 108x108 thumbnails next to 4000x4000
//! (8.25 MB) covers; the directory is written on every track change and had no
//! bound at all, in size or in age.
//!
//! The *decode* half of that problem is bounded at the consumer
//! (`Theme.mediaArtPreviewEdge`, one shared `sourceSize` so the pixmap cache keeps
//! a single decode per cover). This module bounds the other half: a cache that has
//! been written for a year must not keep every cover it ever saw.
//!
//! Pruning is deliberately best-effort and total: a cache that cannot be read is a
//! cache that is not pruned, and a cover that disappeared from under a surface is a
//! missing thumbnail, never an error the timeline should see.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

/// Covers kept regardless of age (a few hundred tracks of history).
pub const DEFAULT_KEEP_FILES: usize = 200;
/// Covers untouched for this long are removed (they belong to tracks nobody replays).
pub const DEFAULT_MAX_AGE: Duration = Duration::from_secs(14 * 24 * 60 * 60);

/// Age- and count-bounded view of one artwork cache directory.
pub struct ArtCache {
    dir: PathBuf,
    keep_files: usize,
    max_age: Duration,
}

impl ArtCache {
    /// The shipped policy: `DEFAULT_KEEP_FILES` / `DEFAULT_MAX_AGE`.
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self::with_limits(dir, DEFAULT_KEEP_FILES, DEFAULT_MAX_AGE)
    }

    pub fn with_limits(dir: impl Into<PathBuf>, keep_files: usize, max_age: Duration) -> Self {
        Self {
            dir: dir.into(),
            keep_files,
            max_age,
        }
    }

    /// Remove expired covers, then trim the oldest survivors beyond `keep_files`.
    ///
    /// `protect` is the file a caller has just written and must survive its own
    /// prune: a re-used cache key can carry an old mtime, and removing it would
    /// leave the surface that asked for the cover loading a URL that just vanished.
    ///
    /// Returns how many files were removed. Never fails: an unreadable directory
    /// prunes nothing.
    pub fn prune(&self, protect: Option<&Path>) -> usize {
        let entries = match fs::read_dir(&self.dir) {
            Ok(entries) => entries,
            Err(_) => return 0,
        };

        let protected_name = protect.and_then(|path| path.file_name().map(|name| name.to_os_string()));
        let now = SystemTime::now();
        let mut survivors: Vec<(SystemTime, PathBuf)> = Vec::new();
        let mut removed = 0;

        for entry in entries.flatten() {
            let path = entry.path();
            let metadata = match entry.metadata() {
                Ok(metadata) => metadata,
                Err(_) => continue,
            };
            // A directory (or a dangling link) in the cache is not a cover.
            if !metadata.is_file() {
                continue;
            }
            if let Some(name) = &protected_name {
                if path.file_name() == Some(name.as_os_str()) {
                    continue;
                }
            }

            let modified = metadata.modified().unwrap_or(now);
            let expired = now
                .duration_since(modified)
                .map(|age| age > self.max_age)
                .unwrap_or(false);
            if expired {
                if fs::remove_file(&path).is_ok() {
                    removed += 1;
                }
                continue;
            }
            survivors.push((modified, path));
        }

        if survivors.len() > self.keep_files {
            // Newest first, so the tail is what goes.
            survivors.sort_by(|a, b| b.0.cmp(&a.0));
            for (_, path) in survivors.into_iter().skip(self.keep_files) {
                if fs::remove_file(&path).is_ok() {
                    removed += 1;
                }
            }
        }

        removed
    }
}
