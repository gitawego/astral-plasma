use std::sync::Arc;
use crate::domain::media::WinePlayerPort;
use crate::infrastructure::media::generic_adapter::GenericWineAdapter;
use crate::infrastructure::media::netease_adapter::NetEaseAdapter;
use crate::infrastructure::media::qqmusic_adapter::QQMusicAdapter;
use crate::infrastructure::media::spotify_adapter::SpotifyWineAdapter;
use crate::infrastructure::media::universal_cover::UniversalCoverResolver;

pub struct WinePlayerRegistry {
    adapters: Vec<Arc<dyn WinePlayerPort>>,
    fallback: Arc<dyn WinePlayerPort>,
}

impl Default for WinePlayerRegistry {
    fn default() -> Self {
        let resolver = Arc::new(UniversalCoverResolver::new());
        let adapters: Vec<Arc<dyn WinePlayerPort>> = vec![
            Arc::new(NetEaseAdapter::with_resolver(Arc::clone(&resolver))),
            Arc::new(QQMusicAdapter::with_resolver(Arc::clone(&resolver))),
            Arc::new(SpotifyWineAdapter::with_resolver(Arc::clone(&resolver))),
        ];
        let fallback: Arc<dyn WinePlayerPort> = Arc::new(GenericWineAdapter::with_resolver(resolver));

        Self { adapters, fallback }
    }
}

impl WinePlayerRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Finds the best matching Wine player adapter for the given window class and app name.
    pub fn find_adapter(&self, class: &str, app: &str) -> Arc<dyn WinePlayerPort> {
        for adapter in &self.adapters {
            if adapter.matches_window(class, app) {
                return Arc::clone(adapter);
            }
        }
        Arc::clone(&self.fallback)
    }

    /// Checks if a given window class or app name belongs to any known Wine music player.
    pub fn is_wine_media_window(&self, class: &str, app: &str) -> bool {
        let c = class.to_lowercase();
        let a = app.to_lowercase();
        let known = [
            "cloudmusic", "netease", "qqmusic", "tencent", "spotify",
            "kugou", "kuwo", "kwmusic", "foobar2000", "aimp", "musicbee",
            "yesplaymusic",
        ];
        for k in known {
            if c.contains(k) || a.contains(k) {
                return true;
            }
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::media::WineAppKind;

    #[test]
    fn test_registry_adapter_resolution() {
        let reg = WinePlayerRegistry::new();

        let netease = reg.find_adapter("cloudmusic.exe", "netease-cloud-music");
        assert_eq!(netease.app_kind(), WineAppKind::NetEase);

        let qq = reg.find_adapter("qqmusic.exe", "QQMusic");
        assert_eq!(qq.app_kind(), WineAppKind::QQMusic);

        let spotify = reg.find_adapter("spotify.exe", "Spotify");
        assert_eq!(spotify.app_kind(), WineAppKind::Spotify);

        let unknown = reg.find_adapter("foobar2000.exe", "foobar2000");
        assert_eq!(unknown.app_kind(), WineAppKind::Generic);
    }
}
