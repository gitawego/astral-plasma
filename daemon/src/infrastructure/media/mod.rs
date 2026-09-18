pub mod universal_cover;
pub mod netease_adapter;
pub mod qqmusic_adapter;
pub mod spotify_adapter;
pub mod generic_adapter;
pub mod native_adapter;
pub mod registry;

pub use universal_cover::UniversalCoverResolver;
pub use netease_adapter::NetEaseAdapter;
pub use qqmusic_adapter::QQMusicAdapter;
pub use spotify_adapter::SpotifyWineAdapter;
pub use generic_adapter::GenericWineAdapter;
pub use native_adapter::NativeMprisAdapter;
pub use registry::WinePlayerRegistry;
