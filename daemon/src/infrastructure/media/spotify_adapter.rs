use std::sync::Arc;
use crate::domain::media::{MediaAction, WineAppKind, WineCaptionInfo, WinePlayerPort, WineTrackMeta};
use crate::infrastructure::media::universal_cover::UniversalCoverResolver;
use crate::infrastructure::x11_input::{send_media_key, MediaKey};

pub struct SpotifyWineAdapter {
    cover_resolver: Arc<UniversalCoverResolver>,
}

impl Default for SpotifyWineAdapter {
    fn default() -> Self {
        Self {
            cover_resolver: Arc::new(UniversalCoverResolver::new()),
        }
    }
}

impl SpotifyWineAdapter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_resolver(cover_resolver: Arc<UniversalCoverResolver>) -> Self {
        Self { cover_resolver }
    }
}

impl WinePlayerPort for SpotifyWineAdapter {
    fn matches_window(&self, class: &str, app: &str) -> bool {
        let c = class.to_lowercase();
        let a = app.to_lowercase();
        c.contains("spotify") || a.contains("spotify")
    }

    fn app_kind(&self) -> WineAppKind {
        WineAppKind::Spotify
    }

    fn display_name(&self) -> &str {
        "Spotify (Wine)"
    }

    fn parse_caption(&self, caption: &str) -> Option<WineCaptionInfo> {
        let mut trimmed = caption.trim();

        if trimmed.is_empty()
            || trimmed.eq_ignore_ascii_case("spotify")
            || trimmed.eq_ignore_ascii_case("spotify free")
            || trimmed.eq_ignore_ascii_case("spotify premium")
        {
            return Some(WineCaptionInfo {
                title: String::new(),
                artist: String::new(),
                album: String::new(),
                is_playing: false,
            });
        }

        // Strip "Spotify - " prefix if present
        if trimmed.starts_with("Spotify - ") {
            trimmed = trimmed.trim_start_matches("Spotify - ").trim();
        } else if trimmed.starts_with("Spotify Free - ") {
            trimmed = trimmed.trim_start_matches("Spotify Free - ").trim();
        } else if trimmed.starts_with("Spotify Premium - ") {
            trimmed = trimmed.trim_start_matches("Spotify Premium - ").trim();
        }

        // Spotify standard format is usually "<Artist> - <Title>"
        let (artist, title) = if let Some(dash_idx) = trimmed.find(" - ") {
            let a = trimmed[..dash_idx].trim().to_string();
            let t = trimmed[dash_idx + 3..].trim().to_string();
            (a, t)
        } else {
            ("Spotify".to_string(), trimmed.to_string())
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
    fn test_spotify_caption_parsing() {
        let adapter = SpotifyWineAdapter::new();

        // Idle
        let idle = adapter.parse_caption("Spotify Free").expect("parsed");
        assert!(!idle.is_playing);

        // Standard artist - title format
        let playing = adapter.parse_caption("The Marías - Nobody New").expect("parsed");
        assert!(playing.is_playing);
        assert_eq!(playing.artist, "The Marías");
        assert_eq!(playing.title, "Nobody New");

        // With Spotify prefix
        let playing2 = adapter.parse_caption("Spotify - The Weeknd - Blinding Lights").expect("parsed");
        assert!(playing2.is_playing);
        assert_eq!(playing2.artist, "The Weeknd");
        assert_eq!(playing2.title, "Blinding Lights");
    }
}
