use std::sync::Arc;
use crate::domain::media::{MediaAction, WineAppKind, WineCaptionInfo, WinePlayerPort, WineTrackMeta};
use crate::infrastructure::media::universal_cover::UniversalCoverResolver;
use crate::infrastructure::x11_input::{send_media_key, MediaKey};

pub struct GenericWineAdapter {
    cover_resolver: Arc<UniversalCoverResolver>,
}

impl Default for GenericWineAdapter {
    fn default() -> Self {
        Self {
            cover_resolver: Arc::new(UniversalCoverResolver::new()),
        }
    }
}

impl GenericWineAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_resolver(cover_resolver: Arc<UniversalCoverResolver>) -> Self {
        Self { cover_resolver }
    }
}

impl WinePlayerPort for GenericWineAdapter {
    fn matches_window(&self, class: &str, app: &str) -> bool {
        let c = class.to_lowercase();
        let a = app.to_lowercase();
        let known = [
            "kugou", "kuwo", "kwmusic", "foobar2000", "aimp", "musicbee",
            "yesplaymusic", "apple music", "itunes", "winamp",
        ];
        for k in known {
            if c.contains(k) || a.contains(k) {
                return true;
            }
        }
        false
    }

    fn app_kind(&self) -> WineAppKind {
        WineAppKind::Generic
    }

    fn display_name(&self) -> &str {
        "Wine Media Player"
    }

    fn parse_caption(&self, caption: &str) -> Option<WineCaptionInfo> {
        let mut trimmed = caption.trim();

        let idle_names = [
            "酷狗音乐", "酷我音乐", "foobar2000", "aimp", "musicbee",
            "kugou", "kuwo", "yesplaymusic", "winamp",
        ];
        for idl in idle_names {
            if trimmed.eq_ignore_ascii_case(idl) {
                return Some(WineCaptionInfo {
                    title: String::new(),
                    artist: String::new(),
                    album: String::new(),
                    is_playing: false,
                });
            }
        }

        if trimmed.is_empty() {
            return Some(WineCaptionInfo {
                title: String::new(),
                artist: String::new(),
                album: String::new(),
                is_playing: false,
            });
        }

        // Strip common player suffixes
        if trimmed.ends_with(" [foobar2000]") {
            trimmed = trimmed.trim_end_matches(" [foobar2000]").trim();
        } else if trimmed.ends_with(" - 酷狗音乐") {
            trimmed = trimmed.trim_end_matches(" - 酷狗音乐").trim();
        } else if trimmed.ends_with(" - 酷我音乐") {
            trimmed = trimmed.trim_end_matches(" - 酷我音乐").trim();
        } else if trimmed.ends_with(" - AIMP") {
            trimmed = trimmed.trim_end_matches(" - AIMP").trim();
        } else if trimmed.ends_with(" - MusicBee") {
            trimmed = trimmed.trim_end_matches(" - MusicBee").trim();
        }

        let (title, artist) = if let Some(last_dash) = trimmed.rfind(" - ") {
            let p1 = trimmed[..last_dash].trim().to_string();
            let p2 = trimmed[last_dash + 3..].trim().to_string();
            (p1, p2)
        } else {
            (trimmed.to_string(), "Wine Media".to_string())
        };

        Some(WineCaptionInfo {
            title,
            artist,
            album: String::new(),
            is_playing: true,
        })
    }

    fn resolve_metadata(&self, title: &str, artist: &str) -> WineTrackMeta {
        let (art_url, duration) = self.cover_resolver.resolve_metadata(title, artist, None);
        WineTrackMeta {
            duration_ms: if duration > 0 { duration } else { 180_000 },
            art_url: art_url.unwrap_or_default(),
            track_id: UniversalCoverResolver::cache_key(title, artist),
        }
    }

    fn send_action(&self, action: MediaAction) -> Result<(), String> {
        let key = match action {
            MediaAction::PlayPause | MediaAction::Play | MediaAction::Pause | MediaAction::Stop => MediaKey::PlayPause,
            MediaAction::Next => MediaKey::Next,
            MediaAction::Previous => MediaKey::Previous,
        };
        send_media_key(key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_foobar_caption_parsing() {
        let adapter = GenericWineAdapter::new();
        let playing = adapter.parse_caption("Bohemian Rhapsody - Queen [foobar2000]").expect("parsed");
        assert!(playing.is_playing);
        assert_eq!(playing.title, "Bohemian Rhapsody");
        assert_eq!(playing.artist, "Queen");
    }

    #[test]
    fn test_kugou_caption_parsing() {
        let adapter = GenericWineAdapter::new();
        let playing = adapter.parse_caption("海阔天空 - Beyond - 酷狗音乐").expect("parsed");
        assert!(playing.is_playing);
        assert_eq!(playing.title, "海阔天空");
        assert_eq!(playing.artist, "Beyond");
    }
}
