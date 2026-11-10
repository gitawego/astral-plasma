//! Album-artwork cache hygiene.
//!
//! The cache holds whatever the player or provider served. Measured on a live
//! session it had grown to 141 files / 29 MB, with covers from 108x108 up to
//! 4000x4000 (8.25 MB) — the directory is written on every track change and had
//! no bound at all. These tests pin the two rules: the newest covers stay, and a
//! cover that has not been touched for the age limit goes regardless of count.

use astral_plasma::infrastructure::media::art_cache::{ArtCache, DEFAULT_KEEP_FILES, DEFAULT_MAX_AGE};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

fn write_cover(dir: &Path, name: &str, age: Duration) -> PathBuf {
    let path = dir.join(name);
    fs::write(&path, b"jpeg-bytes, deliberately longer than a failed download").expect("write cover");
    if age > Duration::ZERO {
        let file = fs::OpenOptions::new().write(true).open(&path).expect("open cover");
        let when = SystemTime::now() - age;
        file.set_times(fs::FileTimes::new().set_modified(when))
            .expect("set mtime");
    }
    path
}

fn names(dir: &Path) -> Vec<String> {
    let mut out: Vec<String> = fs::read_dir(dir)
        .expect("read cache dir")
        .flatten()
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();
    out.sort();
    out
}

#[test]
fn the_newest_covers_survive_and_the_tail_is_removed() {
    let temp = tempfile::tempdir().expect("tempdir");
    let cache = ArtCache::with_limits(temp.path(), 3, DEFAULT_MAX_AGE);

    // Six covers, one hour apart, all inside the age limit.
    for i in 0..6u64 {
        write_cover(temp.path(), &format!("cover{}.jpg", i), Duration::from_secs(3600 * (6 - i)));
    }

    let removed = cache.prune(None);

    assert_eq!(removed, 3, "only the tail beyond the keep count may be removed");
    assert_eq!(
        names(temp.path()),
        vec!["cover3.jpg", "cover4.jpg", "cover5.jpg"],
        "the three newest covers must survive and the three oldest must go"
    );
}

#[test]
fn a_cover_older_than_the_age_limit_is_removed_even_under_the_count() {
    let temp = tempfile::tempdir().expect("tempdir");
    let cache = ArtCache::with_limits(temp.path(), DEFAULT_KEEP_FILES, Duration::from_secs(24 * 3600));

    write_cover(temp.path(), "ancient.jpg", Duration::from_secs(3 * 24 * 3600));
    write_cover(temp.path(), "fresh.jpg", Duration::from_secs(60));

    let removed = cache.prune(None);

    assert_eq!(removed, 1, "exactly the expired cover must be removed");
    assert_eq!(names(temp.path()), vec!["fresh.jpg"]);
}

#[test]
fn the_cover_that_was_just_written_is_never_pruned() {
    // A cache key can be reused for a track whose art was fetched long ago, and the
    // caller has just re-written the file: pruning it would leave the surface that
    // asked for it loading a URL that no longer exists.
    let temp = tempfile::tempdir().expect("tempdir");
    let cache = ArtCache::with_limits(temp.path(), 1, Duration::ZERO);

    let old_but_ours = write_cover(temp.path(), "netease_42.jpg", Duration::from_secs(3600));
    write_cover(temp.path(), "older.jpg", Duration::from_secs(7200));

    let removed = cache.prune(Some(&old_but_ours));

    assert_eq!(removed, 1, "the unrelated cover must go");
    assert!(
        names(temp.path()).contains(&"netease_42.jpg".to_string()),
        "the file the caller just wrote must survive its own prune"
    );
}

#[test]
fn a_missing_directory_is_not_an_error() {
    let temp = tempfile::tempdir().expect("tempdir");
    let cache = ArtCache::new(temp.path().join("never-created"));

    assert_eq!(cache.prune(None), 0, "an absent cache simply has nothing to prune");
}

#[test]
fn directories_and_unrelated_entries_are_left_alone() {
    let temp = tempfile::tempdir().expect("tempdir");
    let cache = ArtCache::with_limits(temp.path(), 1, DEFAULT_MAX_AGE);

    write_cover(temp.path(), "a.jpg", Duration::from_secs(10));
    write_cover(temp.path(), "b.jpg", Duration::from_secs(20));
    fs::create_dir(temp.path().join("nested")).expect("nested dir");
    fs::write(temp.path().join("nested/keep.txt"), b"not a cover").expect("nested file");

    cache.prune(None);

    assert!(temp.path().join("nested/keep.txt").exists(), "a directory in the cache is not a cover");
    assert_eq!(names(temp.path()).len(), 2, "the nested directory must still be listed");
}

#[test]
fn the_shipped_defaults_bound_a_directory_that_has_been_written_for_a_year() {
    // The failure this guards against is unbounded growth, so the shipped limits
    // have to actually bite: 600 covers written over a year, none of them recent.
    let temp = tempfile::tempdir().expect("tempdir");
    let cache = ArtCache::new(temp.path());

    for i in 0..DEFAULT_KEEP_FILES + 100 {
        write_cover(
            temp.path(),
            &format!("track{}.jpg", i),
            Duration::from_secs(60 + i as u64 * 10),
        );
    }

    let removed = cache.prune(None);

    assert_eq!(removed, 100, "the directory must be trimmed back to the keep count");
    assert_eq!(names(temp.path()).len(), DEFAULT_KEEP_FILES);
}
