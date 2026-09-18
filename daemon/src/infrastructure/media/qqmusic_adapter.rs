use std::sync::Arc;
use crate::domain::media::{MediaAction, WineAppKind, WineCaptionInfo, WinePlayerPort, WineTrackMeta};
use crate::infrastructure::media::universal_cover::UniversalCoverResolver;
use crate::infrastructure::x11_input::{send_media_key, MediaKey};

pub struct QQMusicAdapter {
    cover_resolver: Arc<UniversalCoverResolver>,
}

impl Default for QQMusicAdapter {
    fn default() -> Self {
        Self {
            cover_resolver: Arc::new(UniversalCoverResolver::new()),
        }
    }
}

impl QQMusicAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_resolver(cover_resolver: Arc<UniversalCoverResolver>) -> Self {
        Self { cover_resolver }
    }
}

impl WinePlayerPort for QQMusicAdapter {
    fn matches_window(&self, class: &str, app: &str) -> bool {
        let c = class.to_lowercase();
        let a = app.to_lowercase();
        c.contains("qqmusic") || c.contains("tencent") || a.contains("qqmusic") || a.contains("tencent")
    }

    fn app_kind(&self) -> WineAppKind {
        WineAppKind::QQMusic
    }

    fn display_name(&self) -> &str {
        "QQ Music (Wine)"
    }

    fn parse_caption(&self, caption: &str) -> Option<WineCaptionInfo> {
        let mut trimmed = caption.trim();

        if trimmed.is_empty() || trimmed == "QQ音乐" || trimmed == "QQMusic" {
            return Some(WineCaptionInfo {
                title: String::new(),
                artist: String::new(),
                album: String::new(),
                is_playing: false,
            });
        }

        // Strip player branding suffix if present
        if trimmed.ends_with(" - QQ音乐") {
            trimmed = trimmed.trim_end_matches(" - QQ音乐").trim();
        } else if trimmed.ends_with(" - QQMusic") {
            trimmed = trimmed.trim_end_matches(" - QQMusic").trim();
        }

        let (title, artist) = if let Some(last_dash_idx) = trimmed.rfind(" - ") {
            let t = trimmed[..last_dash_idx].trim().to_string();
            let a = trimmed[last_dash_idx + 3..].trim().to_string();
            (t, a)
        } else {
            (trimmed.to_string(), "QQ Music".to_string())
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
    fn test_qqmusic_caption_parsing() {
        let adapter = QQMusicAdapter::new();

        // Idle state
        let idle = adapter.parse_caption("QQ音乐").expect("parsed");
        assert!(!idle.is_playing);

        // Standard format with suffix
        let playing = adapter.parse_caption("七里香 - 周杰伦 - QQ音乐").expect("parsed");
        assert!(playing.is_playing);
        assert_eq!(playing.title, "七里香");
        assert_eq!(playing.artist, "周杰伦");

        // Format without suffix
        let playing2 = adapter.parse_caption("晴天 - 周杰伦").expect("parsed");
        assert!(playing2.is_playing);
        assert_eq!(playing2.title, "晴天");
        assert_eq!(playing2.artist, "周杰伦");
    }
}
