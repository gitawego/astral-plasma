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

    let art_url = extract_or_find_wine_cover().unwrap_or_default();

    Some(WineMediaInfo {
        player_id: "cloudmusic".to_string(),
        player_name: "NetEase Cloud Music".to_string(),
        title,
        artist,
        is_playing: true,
        art_url,
    })
}

/// Locates the newest cached cover art in the Wine prefix and copies it to /tmp/caelestia_wine_cover.jpg
pub fn extract_or_find_wine_cover() -> Option<String> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/home/hlu".to_string());
    
    // Candidate directories where Wine NetEase Cloud Music caches album art
    let candidates = [
        format!("{}/Programs/netease-cloud-music/drive_c/users/{}/AppData/Local/NetEase/CloudMusic/Statics", home, std::env::var("USER").unwrap_or_else(|_| "hlu".to_string())),
        format!("{}/.wine/drive_c/users/{}/AppData/Local/NetEase/CloudMusic/Statics", home, std::env::var("USER").unwrap_or_else(|_| "hlu".to_string())),
    ];

    for dir_path in &candidates {
        let p = Path::new(dir_path);
        if !p.is_dir() {
            continue;
        }

        if let Ok(entries) = fs::read_dir(p) {
            let mut newest_file: Option<(PathBuf, SystemTime)> = None;

            for entry in entries.flatten() {
                let path = entry.path();
                let file_name = path.file_name().and_then(|n| n.to_str()).unwrap_or_default();

                // Cover art files in Statics are hashes with .dat extension, excluding index.dat
                if file_name.ends_with(".dat") && !file_name.starts_with("index") {
                    if let Ok(meta) = entry.metadata() {
                        // Check if file is non-empty
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
    }

    #[test]
    fn test_non_wine_ignored() {
        assert!(parse_wine_media("Visual Studio Code", "code").is_none());
    }
}
