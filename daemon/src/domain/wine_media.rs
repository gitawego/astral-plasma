use std::path::{Path, PathBuf};
use crate::infrastructure::media::netease_adapter::NetEaseAdapter;
use crate::infrastructure::media::registry::WinePlayerRegistry;
use crate::domain::media::WinePlayerPort;

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

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WineTrackMeta {
    pub duration_ms: u64,
    pub art_url: String,
}

/// Parses window caption and resource class across ANY Wine music app (NetEase, QQ Music, Spotify, Foobar2000, etc.).
pub fn parse_wine_media(caption: &str, cls: &str) -> Option<WineMediaInfo> {
    let registry = WinePlayerRegistry::new();
    if !registry.is_wine_media_window(cls, "") {
        return None;
    }

    let adapter = registry.find_adapter(cls, "");
    let caption_info = adapter.parse_caption(caption)?;

    if !caption_info.is_playing {
        return Some(WineMediaInfo {
            player_id: adapter.app_kind().to_string(),
            player_name: adapter.display_name().to_string(),
            title: String::new(),
            artist: String::new(),
            is_playing: false,
            art_url: String::new(),
            duration_ms: 0,
        });
    }

    let meta = adapter.resolve_metadata(&caption_info.title, &caption_info.artist);

    Some(WineMediaInfo {
        player_id: adapter.app_kind().to_string(),
        player_name: adapter.display_name().to_string(),
        title: caption_info.title,
        artist: caption_info.artist,
        is_playing: true,
        art_url: meta.art_url,
        duration_ms: meta.duration_ms,
    })
}

pub fn get_netease_base_dirs() -> Vec<PathBuf> {
    NetEaseAdapter::get_base_dirs()
}

pub fn find_track_in_playing_list(base_dir: &Path, title: &str) -> Option<(u64, String, String)> {
    NetEaseAdapter::find_in_playlist_file(&base_dir.join("webdata/file/playingList"), title)
}

pub fn find_track_in_webdb(base_dir: &Path, title: &str) -> Option<(u64, String, String)> {
    NetEaseAdapter::find_in_webdb(base_dir, title)
}

pub fn extract_wine_track_meta(title: &str, artist: &str) -> WineTrackMeta {
    let adapter = NetEaseAdapter::new();
    let meta = adapter.resolve_metadata(title, artist);
    WineTrackMeta {
        duration_ms: meta.duration_ms,
        art_url: meta.art_url,
    }
}

pub fn extract_track_duration(title: &str) -> u64 {
    extract_wine_track_meta(title, "").duration_ms
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

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
        let info = parse_wine_media("a - b - c - 汉堡黄", "cloudmusic.exe").expect("Must parse");
        assert_eq!(info.title, "a - b - c");
        assert_eq!(info.artist, "汉堡黄");
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
    }
}
