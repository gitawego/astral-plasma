use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use zbus::connection::Builder;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedValue, Value};
use zbus::Connection;

use crate::domain::ports::DynResult;
use crate::domain::wine_media::WineMediaInfo;
use crate::infrastructure::x11_input::{send_media_key, MediaKey};

pub struct WineMprisRoot;

#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl WineMprisRoot {
    #[zbus(property)]
    fn can_quit(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn can_raise(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn identity(&self) -> &str {
        "NetEase Cloud Music (Wine)"
    }

    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> {
        Vec::new()
    }

    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> {
        Vec::new()
    }

    async fn raise(&self) {
        let _ = tokio::process::Command::new("qdbus6")
            .args(["org.kde.KWin", "/WindowsRunner", "org.kde.krunner1.Match", ""])
            .output()
            .await;
    }

    async fn quit(&self) {}
}

#[derive(Clone, Default)]
pub struct WineMprisPlayerState {
    pub title: String,
    pub artist: String,
    pub art_url: String,
    pub is_playing: bool,
}

#[derive(Clone)]
pub struct WineMprisPlayer {
    state: Arc<Mutex<WineMprisPlayerState>>,
}

#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl WineMprisPlayer {
    #[zbus(property)]
    async fn playback_status(&self) -> String {
        let st = self.state.lock().await;
        if st.title.is_empty() {
            "Stopped".to_string()
        } else if st.is_playing {
            "Playing".to_string()
        } else {
            "Paused".to_string()
        }
    }

    #[zbus(property)]
    async fn metadata(&self) -> HashMap<String, OwnedValue> {
        let st = self.state.lock().await;
        let mut map = HashMap::new();
        if let Ok(track_id) = ObjectPath::try_from("/org/mpris/MediaPlayer2/Track/1") {
            if let Ok(val) = Value::from(track_id).try_into_owned() {
                map.insert("mpris:trackid".to_string(), val);
            }
        }
        if let Ok(val) = Value::from(st.title.clone()).try_into_owned() {
            map.insert("xesam:title".to_string(), val);
        }
        if let Ok(val) = Value::from(vec![st.artist.clone()]).try_into_owned() {
            map.insert("xesam:artist".to_string(), val);
        }
        if !st.art_url.is_empty() {
            if let Ok(val) = Value::from(st.art_url.clone()).try_into_owned() {
                map.insert("mpris:artUrl".to_string(), val);
            }
        }
        map
    }

    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn volume(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn position(&self) -> i64 {
        0
    }

    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_seek(&self) -> bool {
        false
    }

    async fn next(&self) {
        let _ = send_media_key(MediaKey::Next);
    }

    async fn previous(&self) {
        let _ = send_media_key(MediaKey::Previous);
    }

    async fn play_pause(&self) {
        let _ = send_media_key(MediaKey::PlayPause);
    }

    async fn play(&self) {
        let st = self.state.lock().await;
        if !st.is_playing {
            let _ = send_media_key(MediaKey::PlayPause);
        }
    }

    async fn pause(&self) {
        let st = self.state.lock().await;
        if st.is_playing {
            let _ = send_media_key(MediaKey::PlayPause);
        }
    }

    async fn stop(&self) {
        let _ = send_media_key(MediaKey::PlayPause);
    }
}

pub struct WineMprisService {
    conn: Connection,
    player: WineMprisPlayer,
    state: Arc<Mutex<WineMprisPlayerState>>,
}

impl WineMprisService {
    pub async fn new() -> DynResult<Self> {
        let state = Arc::new(Mutex::new(WineMprisPlayerState::default()));
        let player = WineMprisPlayer {
            state: Arc::clone(&state),
        };

        let conn = Builder::session()?
            .name("org.mpris.MediaPlayer2.cloudmusic")?
            .serve_at("/org/mpris/MediaPlayer2", WineMprisRoot)?
            .serve_at("/org/mpris/MediaPlayer2", player.clone())?
            .build()
            .await?;

        Ok(Self {
            conn,
            player,
            state,
        })
    }

    pub async fn update_media(&self, media: &WineMediaInfo) -> DynResult<()> {
        let changed = {
            let mut st = self.state.lock().await;
            if st.title != media.title
                || st.artist != media.artist
                || st.is_playing != media.is_playing
                || st.art_url != media.art_url
            {
                st.title = media.title.clone();
                st.artist = media.artist.clone();
                st.art_url = media.art_url.clone();
                st.is_playing = media.is_playing;
                true
            } else {
                false
            }
        };

        if changed {
            if let Ok(emitter) = SignalEmitter::new(&self.conn, "/org/mpris/MediaPlayer2") {
                let _ = self.player.playback_status_changed(&emitter).await;
                let _ = self.player.metadata_changed(&emitter).await;
            }
        }

        Ok(())
    }

    pub async fn update_playback_status(&self, is_playing: bool) -> DynResult<()> {
        let changed = {
            let mut st = self.state.lock().await;
            if st.is_playing != is_playing {
                st.is_playing = is_playing;
                true
            } else {
                false
            }
        };

        if changed {
            if let Ok(emitter) = SignalEmitter::new(&self.conn, "/org/mpris/MediaPlayer2") {
                let _ = self.player.playback_status_changed(&emitter).await;
            }
        }

        Ok(())
    }
}
