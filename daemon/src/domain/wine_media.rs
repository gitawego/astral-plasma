use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WineMediaInfo {
    pub player_id: String,
    pub player_name: String,
    pub title: String,
    pub artist: String,
    pub is_playing: bool,
    pub art_url: String,
    pub duration_ms: u64,
}

/// Parses window caption and resource class to extract media info if it belongs to a Wine music app.
pub fn parse_wine_media(caption: &str, cls: &str) -> Option<WineMediaInfo> {
    let cls_lower = cls.to_lowercase();
    let is_cloudmusic = cls_lower.contains("cloudmusic") || cls_lower.contains("netease");

    if !is_cloudmusic {
        return None;
    }

    let trimmed = caption.trim();

    // Idle or stopped states
    if trimmed.is_empty() || trimmed == "网易云音乐" || trimmed == "CloudMusic" {
        return Some(WineMediaInfo {
            player_id: "cloudmusic".to_string(),
            player_name: "NetEase Cloud Music".to_string(),
            title: String::new(),
            artist: String::new(),
            is_playing: false,
            art_url: String::new(),
            duration_ms: 0,
        });
    }

    // When playing, NetEase formats window title as: "<Title> - <Artist>"
    let (title, artist) = if let Some(last_dash_idx) = trimmed.rfind(" - ") {
        let t = trimmed[..last_dash_idx].trim().to_string();
        let a = trimmed[last_dash_idx + 3..].trim().to_string();
        (t, a)
    } else {
        (trimmed.to_string(), "NetEase Cloud Music".to_string())
    };

    let meta = extract_wine_track_meta(&title, &artist);

    Some(WineMediaInfo {
        player_id: "cloudmusic".to_string(),
        player_name: "NetEase Cloud Music".to_string(),
        title,
        artist,
        is_playing: true,
        art_url: meta.art_url,
        duration_ms: meta.duration_ms,
    })
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WineTrackMeta {
    pub duration_ms: u64,
    pub art_url: String,
}

pub fn get_netease_base_dirs() -> Vec<PathBuf> {
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

pub fn find_track_in_playing_list(base_dir: &Path, title: &str) -> Option<(u64, String, String)> {
    let candidate = base_dir.join("webdata/file/playingList");
    let content = fs::read_to_string(candidate).ok()?;
    let val: serde_json::Value = serde_json::from_str(&content).ok()?;
    let list = val.get("list").and_then(|l| l.as_array())?;

    for item in list {
        if let Some(track) = item.get("track") {
            let name = track.get("name").and_then(|n| n.as_str()).unwrap_or_default();
            if !name.is_empty()
                && (name.eq_ignore_ascii_case(title)
                    || title.to_lowercase().contains(&name.to_lowercase())
                    || name.to_lowercase().contains(&title.to_lowercase()))
            {
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
                return Some((dur, track_id, pic_url));
            }
        }
    }
    None
}

pub fn find_track_in_webdb(base_dir: &Path, title: &str) -> Option<(u64, String, String)> {
    let db_path = base_dir.join("Library/webdb.dat");
    if !db_path.exists() {
        return None;
    }

    let output = std::process::Command::new("sqlite3")
        .args([
            db_path.to_str().unwrap_or_default(),
            "SELECT jsonStr FROM historyTracks ORDER BY playtime DESC LIMIT 10;",
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let mut fallback: Option<(u64, String, String)> = None;

    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Ok(track) = serde_json::from_str::<serde_json::Value>(trimmed) {
            let name = track.get("name").and_then(|n| n.as_str()).unwrap_or_default();
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

            if fallback.is_none() && (!pic_url.is_empty() || dur > 0) {
                fallback = Some((dur, track_id.clone(), pic_url.clone()));
            }

            if !name.is_empty()
                && (name.eq_ignore_ascii_case(title)
                    || title.to_lowercase().contains(&name.to_lowercase())
                    || name.to_lowercase().contains(&title.to_lowercase()))
            {
                return Some((dur, track_id, pic_url));
            }
        }
    }

    fallback
}

pub fn resolve_wine_cover_art(base_dir: &Path, track_id: &str, pic_url: &str) -> Option<String> {
    if pic_url.is_empty() && track_id.is_empty() {
        return None;
    }

    let key = if !track_id.is_empty() {
        track_id.to_string()
    } else {
        pic_url
            .chars()
            .filter(|c| c.is_alphanumeric())
            .take(16)
            .collect()
    };

    let target_cache_file = format!("/tmp/caelestia_wine_cover_{}.jpg", key);
    let p = Path::new(&target_cache_file);

    // 1. If we already downloaded/cached this track's cover, return immediately
    if p.exists() {
        if let Ok(meta) = fs::metadata(p) {
            if meta.len() > 1000 {
                return Some(format!("file://{}", target_cache_file));
            }
        }
    }

    // 2. Check if NetEase already cached a thumbnail/file in Statics/index.dat
    if !pic_url.is_empty() {
        let pic_id = pic_url
            .rsplit('/')
            .next()
            .and_then(|f| f.split('.').next())
            .unwrap_or_default();
        if !pic_id.is_empty() {
            let statics_index = base_dir.join("Statics/index.dat");
            if statics_index.exists() {
                let query = format!(
                    "SELECT path FROM cache WHERE url LIKE '%{}%' LIMIT 1;",
                    pic_id
                );
                if let Ok(output) = std::process::Command::new("sqlite3")
                    .args([statics_index.to_str().unwrap_or_default(), &query])
                    .output()
                {
                    if output.status.success() {
                        let dat_file = String::from_utf8_lossy(&output.stdout).trim().to_string();
                        if !dat_file.is_empty() {
                            let dat_path = base_dir.join("Statics").join(&dat_file);
                            if dat_path.exists() {
                                if let Ok(meta) = fs::metadata(&dat_path) {
                                    if meta.len() > 100 {
                                        let _ = fs::copy(&dat_path, &target_cache_file);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 3. Download high-res (500x500) cover if pic_url is HTTP(S)
    if pic_url.starts_with("http://") || pic_url.starts_with("https://") {
        let clean_url = pic_url.split('?').next().unwrap_or(pic_url);
        let dl_url = format!("{}?param=500y500", clean_url);
        let _ = std::process::Command::new("curl")
            .args(["-s", "-m", "2", &dl_url, "-o", &target_cache_file])
            .output();

        if p.exists() {
            if let Ok(meta) = fs::metadata(p) {
                if meta.len() > 1000 {
                    return Some(format!("file://{}", target_cache_file));
                }
            }
        }

        // Return HTTP URL directly so QML can load it if download did not complete
        return Some(dl_url);
    }

    if p.exists() {
        return Some(format!("file://{}", target_cache_file));
    }

    None
}

/// Locates the track duration and album cover from NetEase Cloud Music local caches
pub fn extract_wine_track_meta(title: &str, _artist: &str) -> WineTrackMeta {
    let base_dirs = get_netease_base_dirs();

    for base_dir in &base_dirs {
        if !base_dir.is_dir() {
            continue;
        }

        let mut matched = find_track_in_playing_list(base_dir, title);
        if matched.is_none() {
            matched = find_track_in_webdb(base_dir, title);
        }

        if let Some((duration_ms, track_id, pic_url)) = matched {
            let art_url = resolve_wine_cover_art(base_dir, &track_id, &pic_url)
                .or_else(extract_or_find_wine_cover)
                .unwrap_or_default();

            return WineTrackMeta {
                duration_ms: if duration_ms > 0 { duration_ms } else { 180_000 },
                art_url,
            };
        }
    }

    // Fallback if not found in any playlist or database
    let art_url = extract_or_find_wine_cover().unwrap_or_default();
    WineTrackMeta {
        duration_ms: 180_000,
        art_url,
    }
}

/// Locates the track duration in milliseconds from NetEase Cloud Music local playlist cache
pub fn extract_track_duration(title: &str) -> u64 {
    extract_wine_track_meta(title, "").duration_ms
}

/// Fallback locator for the newest cached cover art in the Wine prefix
pub fn extract_or_find_wine_cover() -> Option<String> {
    let base_dirs = get_netease_base_dirs();

    for base_dir in &base_dirs {
        let p = base_dir.join("Statics");
        if !p.is_dir() {
            continue;
        }

        if let Ok(entries) = fs::read_dir(&p) {
            let mut newest_file: Option<(PathBuf, SystemTime)> = None;

            for entry in entries.flatten() {
                let path = entry.path();
                let file_name = path.file_name().and_then(|n| n.to_str()).unwrap_or_default();

                // Cover art files in Statics are hashes with .dat extension, excluding index.dat
                if file_name.ends_with(".dat") && !file_name.starts_with("index") {
                    if let Ok(meta) = entry.metadata() {
                        if meta.len() > 100 {
                            let mtime = meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
                            if newest_file.as_ref().map_or(true, |(_, cur_time)| mtime > *cur_time) {
                                newest_file = Some((path, mtime));
                            }
                        }
                    }
                }
            }

            if let Some((target_path, _)) = newest_file {
                // Verify image header magic bytes (JPEG: 0xFF 0xD8, PNG: 0x89 0x50)
                if let Ok(bytes) = fs::read(&target_path) {
                    if (bytes.len() > 4 && bytes[0] == 0xFF && bytes[1] == 0xD8)
                        || (bytes.len() > 8 && bytes[0] == 0x89 && bytes[1] == 0x50)
                    {
                        let out_cover = "/tmp/caelestia_wine_cover.jpg";
                        if fs::copy(&target_path, out_cover).is_ok() {
                            return Some(format!("file://{}", out_cover));
                        }
                    }
                }
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_netease_cloudmusic_title_artist_split() {
        let info = parse_wine_media("road trip - 汉堡黄", "cloudmusic.exe").expect("Must parse");
        assert_eq!(info.player_id, "cloudmusic");
        assert_eq!(info.title, "road trip");
        assert_eq!(info.artist, "汉堡黄");
        assert!(info.is_playing);
        assert!(info.duration_ms > 0);
    }

    #[test]
    fn test_netease_cloudmusic_dash_in_title() {
        let info = parse_wine_media("Song - Remix - Some Artist", "cloudmusic.exe").expect("Must parse");
        assert_eq!(info.title, "Song - Remix");
        assert_eq!(info.artist, "Some Artist");
        assert!(info.is_playing);
    }

    #[test]
    fn test_netease_cloudmusic_idle() {
        let info = parse_wine_media("网易云音乐", "cloudmusic.exe").expect("Must parse");
        assert_eq!(info.title, "");
        assert_eq!(info.artist, "");
        assert!(!info.is_playing);
        assert_eq!(info.duration_ms, 0);
    }

    #[test]
    fn test_non_wine_ignored() {
        assert!(parse_wine_media("Visual Studio Code", "code").is_none());
    }

    #[test]
    fn test_find_track_in_playing_list() {
        let temp_dir = tempfile::tempdir().expect("tempdir");
        let base_dir = temp_dir.path();
        let webdata_dir = base_dir.join("webdata/file");
        fs::create_dir_all(&webdata_dir).expect("create_dir_all");

        let json_content = r#"{
            "list": [
                {
                    "track": {
                        "id": "2681067724",
                        "name": "New notes",
                        "duration": 194010,
                        "album": {
                            "name": "如果每天都可以 happy happy 谁想要sad:)) - 一起去度假",
                            "picUrl": "http://p3.music.126.net/SM9I8flDSW7Eps_Z7uvPZg==/109951170540389548.jpg"
                        }
                    }
                }
            ]
        }"#;

        fs::write(webdata_dir.join("playingList"), json_content).expect("write playingList");

        let result = find_track_in_playing_list(base_dir, "New notes").expect("Must find track");
        assert_eq!(result.0, 194010);
        assert_eq!(result.1, "2681067724");
        assert_eq!(result.2, "http://p3.music.126.net/SM9I8flDSW7Eps_Z7uvPZg==/109951170540389548.jpg");
    }

    #[test]
    fn test_extract_wine_track_meta_with_mock() {
        let temp_dir = tempfile::tempdir().expect("tempdir");
        let base_dir = temp_dir.path();
        let webdata_dir = base_dir.join("webdata/file");
        fs::create_dir_all(&webdata_dir).expect("create_dir_all");

        let json_content = r#"{
            "list": [
                {
                    "track": {
                        "id": "2681067724",
                        "name": "New notes",
                        "duration": 194010,
                        "album": {
                            "picUrl": "http://p3.music.126.net/SM9I8flDSW7Eps_Z7uvPZg==/109951170540389548.jpg"
                        }
                    }
                }
            ]
        }"#;

        fs::write(webdata_dir.join("playingList"), json_content).expect("write playingList");

        std::env::set_var("ASTRAL_TEST_NETEASE_DIR", base_dir.to_str().unwrap());
        let meta = extract_wine_track_meta("New notes", "陳嫺靜");
        std::env::remove_var("ASTRAL_TEST_NETEASE_DIR");

        assert_eq!(meta.duration_ms, 194010);
        assert!(!meta.art_url.is_empty(), "art_url must not be empty");
        assert!(
            meta.art_url.contains("2681067724") || meta.art_url.contains("109951170540389548"),
            "art_url must be track-accurate, got: {}",
            meta.art_url
        );
    }
}
