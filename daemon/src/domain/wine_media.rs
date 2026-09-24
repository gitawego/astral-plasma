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
