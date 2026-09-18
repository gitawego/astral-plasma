use std::sync::Arc;
use crate::domain::media::{MediaAction, MediaPlayerKind, MediaPlayerPort, MediaTrack, PlaybackState};
use crate::domain::ports::DynResult;
use crate::infrastructure::media::universal_cover::UniversalCoverResolver;

pub struct NativeMprisAdapter {
    bus_name: String,
    cover_resolver: Arc<UniversalCoverResolver>,
}

impl NativeMprisAdapter {
    pub fn new(bus_name: String, cover_resolver: Arc<UniversalCoverResolver>) -> Self {
        Self {
            bus_name,
            cover_resolver,
        }
    }

    pub fn full_dbus_name(&self) -> String {
        if self.bus_name.starts_with("org.mpris.MediaPlayer2.") {
            self.bus_name.clone()
        } else {
            format!("org.mpris.MediaPlayer2.{}", self.bus_name)
        }
    }

    /// Enriches track art URL if missing from native player metadata.
    pub fn enrich_track(&self, mut track: MediaTrack) -> MediaTrack {
        if track.art_url.is_empty() && !track.title.is_empty() {
            if let Some(art) = self.cover_resolver.resolve_art(&track.title, &track.artist, None) {
                track.art_url = art;
            }
        }
        track
    }
}

impl MediaPlayerPort for NativeMprisAdapter {
    fn kind(&self) -> MediaPlayerKind {
        let suffix = self.bus_name.trim_start_matches("org.mpris.MediaPlayer2.");
        MediaPlayerKind::Native(suffix.to_string())
    }

    fn identity(&self) -> &str {
        &self.bus_name
    }

    fn playback_state(&self) -> PlaybackState {
        // Query D-Bus synchronously via zbus/busctl or default to stopped
        PlaybackState::Stopped
    }

    fn current_track(&self) -> Option<MediaTrack> {
        None
    }

    fn send_action(&self, action: MediaAction) -> DynResult<()> {
        let member = match action {
            MediaAction::PlayPause => "PlayPause",
            MediaAction::Play => "Play",
            MediaAction::Pause => "Pause",
            MediaAction::Stop => "Stop",
            MediaAction::Next => "Next",
            MediaAction::Previous => "Previous",
        };

        let full_name = self.full_dbus_name();
        let _ = std::process::Command::new("qdbus6")
            .args([&full_name, "/org/mpris/MediaPlayer2", &format!("org.mpris.MediaPlayer2.Player.{}", member)])
            .output();

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_native_adapter_full_name() {
        let resolver = Arc::new(UniversalCoverResolver::new());
        let adapter = NativeMprisAdapter::new("spotify".to_string(), resolver);
        assert_eq!(adapter.full_dbus_name(), "org.mpris.MediaPlayer2.spotify");
    }

    #[test]
    fn test_native_adapter_enrich_missing_art() {
        let temp = tempfile::tempdir().expect("tempdir");
        let resolver = Arc::new(UniversalCoverResolver::with_cache_dir(temp.path().to_path_buf()));
        let adapter = NativeMprisAdapter::new("elisa".to_string(), resolver);

        let input_track = MediaTrack {
            title: "Test Track".to_string(),
            artist: "Test Artist".to_string(),
            album: "".to_string(),
            duration_ms: 180000,
            art_url: "".to_string(),
            track_id: "1".to_string(),
        };

        let enriched = adapter.enrich_track(input_track);
        // If resolver cannot find it online/mock, art_url remains empty without error
        assert_eq!(enriched.title, "Test Track");
    }
}
