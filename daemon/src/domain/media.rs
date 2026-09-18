use std::fmt;
use crate::domain::ports::DynResult;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum WineAppKind {
    NetEase,
    QQMusic,
    Spotify,
    KuGou,
    KuWo,
    Foobar2000,
    Generic,
}

impl fmt::Display for WineAppKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NetEase => write!(f, "cloudmusic"),
            Self::QQMusic => write!(f, "qqmusic"),
            Self::Spotify => write!(f, "spotify_wine"),
            Self::KuGou => write!(f, "kugou"),
            Self::KuWo => write!(f, "kuwo"),
            Self::Foobar2000 => write!(f, "foobar2000"),
            Self::Generic => write!(f, "generic_wine"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MediaPlayerKind {
    Native(String),       // D-Bus well-known suffix, e.g. "spotify", "elisa", "vlc"
    Wine(WineAppKind),   // Wine application kind
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackState {
    Playing,
    Paused,
    Stopped,
}

impl fmt::Display for PlaybackState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Playing => write!(f, "Playing"),
            Self::Paused => write!(f, "Paused"),
            Self::Stopped => write!(f, "Stopped"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaAction {
    PlayPause,
    Play,
    Pause,
    Stop,
    Next,
    Previous,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MediaTrack {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration_ms: u64,
    pub art_url: String,
    pub track_id: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WineCaptionInfo {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub is_playing: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WineTrackMeta {
    pub duration_ms: u64,
    pub art_url: String,
    pub track_id: String,
}

/// Domain Port: Generic media player inspection and control contract.
pub trait MediaPlayerPort: Send + Sync {
    fn kind(&self) -> MediaPlayerKind;
    fn identity(&self) -> &str;
    fn playback_state(&self) -> PlaybackState;
    fn current_track(&self) -> Option<MediaTrack>;
    fn send_action(&self, action: MediaAction) -> DynResult<()>;
}

/// Domain Port: Album cover art and metadata discovery contract.
pub trait CoverArtResolverPort: Send + Sync {
    /// Resolves cover art URL and duration for a given track.
    fn resolve_metadata(&self, title: &str, artist: &str, raw_url: Option<&str>) -> (Option<String>, u64);

    /// Convenience resolver for just cover art.
    fn resolve_art(&self, title: &str, artist: &str, raw_url: Option<&str>) -> Option<String> {
        self.resolve_metadata(title, artist, raw_url).0
    }
}

/// Domain Port: Wine-specific media player contract bridging window events and caches.
pub trait WinePlayerPort: Send + Sync {
    /// Tests if this adapter matches the given window class or desktop app name.
    fn matches_window(&self, class: &str, app: &str) -> bool;

    /// Specific Wine application kind.
    fn app_kind(&self) -> WineAppKind;

    /// User-facing display identity (e.g. "NetEase Cloud Music (Wine)", "QQ Music (Wine)").
    fn display_name(&self) -> &str;

    /// Parses window caption into track title, artist, and playback state.
    fn parse_caption(&self, caption: &str) -> Option<WineCaptionInfo>;

    /// Resolves track duration and album cover art.
    fn resolve_metadata(&self, title: &str, artist: &str) -> WineTrackMeta;

    /// Sends a playback control action to the target Wine player.
    fn send_action(&self, action: MediaAction) -> Result<(), String>;
}
