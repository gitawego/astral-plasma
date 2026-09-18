use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use crate::domain::media::{MediaAction, WineAppKind, WineCaptionInfo, WinePlayerPort, WineTrackMeta};
use crate::infrastructure::media::universal_cover::UniversalCoverResolver;
use crate::infrastructure::x11_input::{send_wine_media_action, WineMediaAction};

pub struct NetEaseAdapter {
    cover_resolver: Arc<UniversalCoverResolver>,
}

impl Default for NetEaseAdapter {
    fn default() -> Self {
        Self {
            cover_resolver: Arc::new(UniversalCoverResolver::new()),
        }
    }
}

impl NetEaseAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_resolver(cover_resolver: Arc<UniversalCoverResolver>) -> Self {
        Self { cover_resolver }
    }

    pub fn get_base_dirs() -> Vec<PathBuf> {
        if let Ok(custom) = std::env::var("ASTRAL_TEST_NETEASE_DIR") {
            return vec![PathBuf::from(custom)];
        }
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/hlu".to_string());
        let user = std::env::var("USER").unwrap_or_else(|_| "hlu".to_string());
        vec![
            PathBuf::from(format!("{}/Programs/netease-cloud-music/drive_c/users/{}/AppData/Local/NetEase/CloudMusic", home, user)),
            PathBuf::from(format!("{}/.wine/drive_c/users/{}/AppData/Local/NetEase/CloudMusic", home, user)),
        ]
    }

    /// Tests whether a candidate song name matches the target title with resilience.
    pub fn title_matches(name: &str, target: &str) -> bool {
        let n = name.trim().to_lowercase();
        let t = target.trim().to_lowercase();
        if n.is_empty() || t.is_empty() {
            return false;
        }
        if n == t || t.contains(&n) || n.contains(&t) {
            return true;
        }

        // Strip common parentheses/brackets like (Live), (Remix), [2024 Remaster]
        let clean_n = n.split('(').next().unwrap_or(&n).split('[').next().unwrap_or(&n).trim();
        let clean_t = t.split('(').next().unwrap_or(&t).split('[').next().unwrap_or(&t).trim();
        if !clean_n.is_empty() && !clean_t.is_empty() && (clean_n == clean_t || clean_t.contains(clean_n) || clean_n.contains(clean_t)) {
            return true;
        }

        false
    }

    /// Extracts (duration_ms, track_id, pic_url) from a JSON track value.
    fn extract_track_json(track: &serde_json::Value) -> Option<(u64, String, String)> {
        let dur = track.get("duration").and_then(|d| d.as_u64()).unwrap_or(0);
        let track_id = track
            .get("id")
            .and_then(|i| {
                i.as_str()
                    .map(|s| s.to_string())
                    .or_else(|| i.as_u64().map(|n| n.to_string()))
            })
            .unwrap_or_default();
        let pic_url = track
            .get("album")
            .and_then(|a| a.get("picUrl").or_else(|| a.get("cover")))
            .and_then(|p| p.as_str())
            .unwrap_or_default()
            .to_string();

        Some((dur, track_id, pic_url))
    }

    /// Searches NetEase Personal FM mode queue (`webdata/file/fmPlay`).
    pub fn find_in_fm_play(base_dir: &Path, title: &str) -> Option<(u64, String, String)> {
        let file_path = base_dir.join("webdata/file/fmPlay");
        let content = fs::read_to_string(file_path).ok()?;
        let val: serde_json::Value = serde_json::from_str(&content).ok()?;

        let queue = val.get("queue").and_then(|q| q.as_array())?;
        let current_index = val.get("currentIndex").and_then(|i| i.as_u64()).unwrap_or(0) as usize;

        // 1. Check item at currentIndex first
        if let Some(current_item) = queue.get(current_index) {
            let name = current_item.get("name").and_then(|n| n.as_str()).unwrap_or_default();
            if Self::title_matches(name, title) {
                return Self::extract_track_json(current_item);
            }
        }

        // 2. Check remaining items in the queue
        for item in queue {
            let name = item.get("name").and_then(|n| n.as_str()).unwrap_or_default();
            if Self::title_matches(name, title) {
                return Self::extract_track_json(item);
            }
        }

        None
    }

    /// Searches standard playlists (`webdata/file/playingList` and `lastTimePlayingList`).
    pub fn find_in_playlist_file(file_path: &Path, title: &str) -> Option<(u64, String, String)> {
        let content = fs::read_to_string(file_path).ok()?;
        let val: serde_json::Value = serde_json::from_str(&content).ok()?;
        let list = val.get("list").and_then(|l| l.as_array())?;

        for item in list {
            let track = item.get("track").unwrap_or(item);
            let name = track.get("name").and_then(|n| n.as_str()).unwrap_or_default();
            if Self::title_matches(name, title) {
                return Self::extract_track_json(track);
            }
        }

        None
    }

    /// Searches NetEase SQLite database (`Library/webdb.dat`) strictly matching title.
    pub fn find_in_webdb(base_dir: &Path, title: &str) -> Option<(u64, String, String)> {
        let db_path = base_dir.join("Library/webdb.dat");
        if !db_path.exists() {
            return None;
        }

        let db_str = db_path.to_str().unwrap_or_default();

        // 1. Check historyTracks
        if let Ok(output) = std::process::Command::new("sqlite3")
            .args([db_str, "SELECT jsonStr FROM historyTracks ORDER BY playtime DESC LIMIT 25;"])
            .output()
        {
            if output.status.success() {
                let text = String::from_utf8_lossy(&output.stdout);
                for line in text.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() {
                        continue;
                    }
                    if let Ok(track) = serde_json::from_str::<serde_json::Value>(trimmed) {
                        let name = track.get("name").and_then(|n| n.as_str()).unwrap_or_default();
                        if Self::title_matches(name, title) {
                            return Self::extract_track_json(&track);
                        }
                    }
                }
            }
        }

        // 2. Check dbTrack
        let sanitized = title.replace('\'', "''");
        let query = format!("SELECT jsonStr FROM dbTrack WHERE jsonStr LIKE '%{}%' LIMIT 5;", sanitized);
        if let Ok(output) = std::process::Command::new("sqlite3")
            .args([db_str, &query])
            .output()
        {
            if output.status.success() {
                let text = String::from_utf8_lossy(&output.stdout);
                for line in text.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() {
                        continue;
                    }
                    if let Ok(track) = serde_json::from_str::<serde_json::Value>(trimmed) {
                        let name = track.get("name").and_then(|n| n.as_str()).unwrap_or_default();
                        if Self::title_matches(name, title) {
                            return Self::extract_track_json(&track);
                        }
                    }
                }
            }
        }

        None
    }

    /// Resolves cover art from NetEase Statics cache if available.
    pub fn resolve_statics_cover(base_dir: &Path, track_id: &str, pic_url: &str) -> Option<String> {
        let pic_id = pic_url
            .rsplit('/')
            .next()
            .and_then(|f| f.split('.').next())
            .unwrap_or_default();

        if pic_id.is_empty() {
            return None;
        }

        let statics_index = base_dir.join("Statics/index.dat");
        if !statics_index.exists() {
            return None;
        }

        let query = format!("SELECT path FROM cache WHERE url LIKE '%{}%' LIMIT 1;", pic_id);
        let output = std::process::Command::new("sqlite3")
            .args([statics_index.to_str().unwrap_or_default(), &query])
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let dat_file = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if dat_file.is_empty() {
            return None;
        }

        let dat_path = base_dir.join("Statics").join(&dat_file);
        if dat_path.exists() {
            if let Ok(meta) = fs::metadata(&dat_path) {
                if meta.len() > 100 {
                    let cache_dir = Path::new("/tmp/caelestia_art_cache");
                    let _ = fs::create_dir_all(cache_dir);
                    let target_file = cache_dir.join(format!("netease_{}.jpg", track_id));
                    if fs::copy(&dat_path, &target_file).is_ok() {
                        return Some(format!("file://{}", target_file.display()));
                    }
                }
            }
        }

        None
    }
}

impl WinePlayerPort for NetEaseAdapter {
    fn matches_window(&self, class: &str, app: &str) -> bool {
        let c = class.to_lowercase();
        let a = app.to_lowercase();
        c.contains("cloudmusic") || c.contains("netease") || a.contains("cloudmusic") || a.contains("netease")
    }

    fn app_kind(&self) -> WineAppKind {
        WineAppKind::NetEase
    }

    fn display_name(&self) -> &str {
        "NetEase Cloud Music (Wine)"
    }

    fn parse_caption(&self, caption: &str) -> Option<WineCaptionInfo> {
        let trimmed = caption.trim();

        if trimmed.is_empty() || trimmed == "网易云音乐" || trimmed == "CloudMusic" {
            return Some(WineCaptionInfo {
                title: String::new(),
                artist: String::new(),
                album: String::new(),
                is_playing: false,
            });
        }

        let (title, artist) = if let Some(last_dash_idx) = trimmed.rfind(" - ") {
            let t = trimmed[..last_dash_idx].trim().to_string();
            let a = trimmed[last_dash_idx + 3..].trim().to_string();
            (t, a)
        } else {
            (trimmed.to_string(), "NetEase Cloud Music".to_string())
        };

        Some(WineCaptionInfo {
            title,
            artist,
            album: String::new(),
            is_playing: true,
        })
    }

    fn resolve_metadata(&self, title: &str, artist: &str) -> WineTrackMeta {
        let base_dirs = Self::get_base_dirs();

        for base_dir in &base_dirs {
            if !base_dir.is_dir() {
                continue;
            }

            // 1. FM Play mode queue
            let mut matched = Self::find_in_fm_play(base_dir, title);

            // 2. Active playing list
            if matched.is_none() {
                matched = Self::find_in_playlist_file(&base_dir.join("webdata/file/playingList"), title);
            }

            // 3. Last time playing list
            if matched.is_none() {
                matched = Self::find_in_playlist_file(&base_dir.join("webdata/file/lastTimePlayingList"), title);
            }

            // 4. Local SQLite webdb.dat
            if matched.is_none() {
                matched = Self::find_in_webdb(base_dir, title);
            }

            if let Some((duration_ms, track_id, pic_url)) = matched {
                // Try resolving directly from Statics index cache
                let mut art_url = Self::resolve_statics_cover(base_dir, &track_id, &pic_url).unwrap_or_default();

                // If not cached locally in Statics, use universal resolver
                if art_url.is_empty() && !pic_url.is_empty() {
                    art_url = self.cover_resolver.resolve_art(title, artist, Some(&pic_url)).unwrap_or_default();
                }

                return WineTrackMeta {
                    duration_ms: if duration_ms > 0 { duration_ms } else { 180_000 },
                    art_url,
                    track_id,
                };
            }
        }

        // 5. Fallback: Universal online resolver (iTunes / QQ Music)
        let (online_art, online_dur) = self.cover_resolver.resolve_metadata(title, artist, None);
        WineTrackMeta {
            duration_ms: if online_dur > 0 { online_dur } else { 180_000 },
            art_url: online_art.unwrap_or_default(),
            track_id: UniversalCoverResolver::cache_key(title, artist),
        }
    }

    fn send_action(&self, action: MediaAction) -> Result<(), String> {
        let wine_act = match action {
            MediaAction::PlayPause | MediaAction::Play | MediaAction::Pause => WineMediaAction::PlayPause,
            MediaAction::Next => WineMediaAction::Next,
            MediaAction::Previous => WineMediaAction::Previous,
            MediaAction::Stop => WineMediaAction::PlayPause,
        };
        send_wine_media_action(wine_act)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_netease_fm_play_parsing() {
        let temp = tempfile::tempdir().expect("tempdir");
        let base = temp.path();
        let file_dir = base.join("webdata/file");
        fs::create_dir_all(&file_dir).expect("create_dir");

        let fm_json = r#"{
            "currentIndex": 1,
            "queue": [
                {
                    "name": "Prev Song",
                    "duration": 150000,
                    "id": "111",
                    "album": { "picUrl": "http://p1.music.126.net/111.jpg" }
                },
                {
                    "name": "Active FM Track",
                    "duration": 240000,
                    "id": "222",
                    "album": { "picUrl": "http://p1.music.126.net/222.jpg" }
                }
            ]
        }"#;
        fs::write(file_dir.join("fmPlay"), fm_json).expect("write");

        let matched = NetEaseAdapter::find_in_fm_play(base, "Active FM Track").expect("found");
        assert_eq!(matched.0, 240000);
        assert_eq!(matched.1, "222");
        assert_eq!(matched.2, "http://p1.music.126.net/222.jpg");
    }

    #[test]
    fn test_netease_no_fallback_leak() {
        let temp = tempfile::tempdir().expect("tempdir");
        let base = temp.path();
        let file_dir = base.join("webdata/file");
        fs::create_dir_all(&file_dir).expect("create_dir");

        let pl_json = r#"{
            "list": [
                {
                    "track": {
                        "name": "Old Song",
                        "duration": 120000,
                        "id": "999"
                    }
                }
            ]
        }"#;
        fs::write(file_dir.join("playingList"), pl_json).expect("write");

        // Searching for an unknown song must return None and NEVER leak the old song!
        assert!(NetEaseAdapter::find_in_playlist_file(&file_dir.join("playingList"), "Completely Different Song").is_none());
    }
}
