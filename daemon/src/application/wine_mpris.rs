use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::Mutex;
use zbus::connection::Builder;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedValue, Value};
use zbus::Connection;

use crate::domain::ports::DynResult;
use crate::domain::wine_media::WineMediaInfo;
use crate::infrastructure::x11_input::{send_wine_media_action, WineMediaAction};

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

#[derive(Clone)]
pub struct WineMprisPlayerState {
    pub title: String,
    pub artist: String,
    pub art_url: String,
    pub is_playing: bool,
    pub duration_micros: i64,
    pub position_micros: i64,
    pub last_play_instant: Option<Instant>,
}

impl Default for WineMprisPlayerState {
    fn default() -> Self {
        Self {
            title: String::new(),
            artist: String::new(),
            art_url: String::new(),
            is_playing: false,
            duration_micros: 0,
            position_micros: 0,
            last_play_instant: None,
        }
    }
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
        if st.duration_micros > 0 {
            if let Ok(val) = Value::from(st.duration_micros).try_into_owned() {
                map.insert("mpris:length".to_string(), val);
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
    async fn position(&self) -> i64 {
        let st = self.state.lock().await;
        if st.is_playing {
            if let Some(instant) = st.last_play_instant {
                let elapsed = instant.elapsed().as_micros() as i64;
                let pos = st.position_micros + elapsed;
                if st.duration_micros > 0 {
                    pos.min(st.duration_micros)
                } else {
                    pos
                }
            } else {
                st.position_micros
            }
        } else {
            st.position_micros
        }
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
        let _ = send_wine_media_action(WineMediaAction::Next);
        let mut st = self.state.lock().await;
        st.position_micros = 0;
        st.last_play_instant = if st.is_playing { Some(Instant::now()) } else { None };
    }

    async fn previous(&self) {
        let _ = send_wine_media_action(WineMediaAction::Previous);
        let mut st = self.state.lock().await;
        st.position_micros = 0;
        st.last_play_instant = if st.is_playing { Some(Instant::now()) } else { None };
    }

    async fn play_pause(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        let _ = send_wine_media_action(WineMediaAction::PlayPause);
        let is_now_playing = {
            let mut st = self.state.lock().await;
            st.is_playing = !st.is_playing;
            if st.is_playing {
                st.last_play_instant = Some(Instant::now());
            } else if let Some(instant) = st.last_play_instant.take() {
                st.position_micros += instant.elapsed().as_micros() as i64;
            }
            st.is_playing
        };

        let _ = self.playback_status_changed(&emitter).await;

        if is_now_playing {
            pause_other_mpris_players().await;
        }
    }

    async fn play(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        let is_playing = {
            let st = self.state.lock().await;
            st.is_playing
        };
        if !is_playing {
            self.play_pause(emitter).await;
        }
    }

    async fn pause(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        let is_playing = {
            let st = self.state.lock().await;
            st.is_playing
        };
        if is_playing {
            self.play_pause(emitter).await;
        }
    }

    async fn stop(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        let is_playing = {
            let st = self.state.lock().await;
            st.is_playing
        };
        if is_playing {
            self.play_pause(emitter).await;
        }
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
        let (status_changed, meta_changed) = {
            let mut st = self.state.lock().await;
            let title_changed = st.title != media.title;
            let artist_changed = st.artist != media.artist;
            let art_changed = st.art_url != media.art_url;
            let new_duration_micros = (media.duration_ms * 1000) as i64;
            let duration_changed = st.duration_micros != new_duration_micros;

            if media.title.is_empty() {
                // Stopped state (empty or "网易云音乐" caption)
                let had_title = !st.title.is_empty();
                let was_playing = st.is_playing;
                st.title.clear();
                st.artist.clear();
                st.art_url.clear();
                st.duration_micros = 0;
                st.position_micros = 0;
                st.last_play_instant = None;
                st.is_playing = false;
                (was_playing, had_title)
            } else if title_changed {
                st.title = media.title.clone();
                st.artist = media.artist.clone();
                st.art_url = media.art_url.clone();
                st.duration_micros = new_duration_micros;
                st.position_micros = 0;

                let should_play = true;
                let was_playing = st.is_playing;
                st.is_playing = should_play;
                st.last_play_instant = Some(Instant::now());
                (was_playing != should_play, true)
            } else {
                // Same title: update art_url or duration if changed, but NEVER overwrite playback state!
                let mut meta_c = false;
                if art_changed {
                    st.art_url = media.art_url.clone();
                    meta_c = true;
                }
                if duration_changed {
                    st.duration_micros = new_duration_micros;
                    meta_c = true;
                }
                if artist_changed {
                    st.artist = media.artist.clone();
                    meta_c = true;
                }
                (false, meta_c)
            }
        };

        if let Ok(emitter) = SignalEmitter::new(&self.conn, "/org/mpris/MediaPlayer2") {
            if status_changed {
                let _ = self.player.playback_status_changed(&emitter).await;
            }
            if meta_changed {
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
                if is_playing {
                    st.last_play_instant = Some(Instant::now());
                } else if let Some(instant) = st.last_play_instant.take() {
                    st.position_micros += instant.elapsed().as_micros() as i64;
                }
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

/// Checks if any other MPRIS player on the session bus is currently in the "Playing" state.
pub async fn is_other_mpris_playing() -> bool {
    let out = match tokio::process::Command::new("busctl")
        .args(["--user", "list", "--acquired"])
        .output()
        .await
    {
        Ok(o) => o,
        Err(_) => return false,
    };
    let text = String::from_utf8_lossy(&out.stdout);
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(first) = trimmed.split_whitespace().next() {
            if first.starts_with("org.mpris.MediaPlayer2.") && first != "org.mpris.MediaPlayer2.cloudmusic" {
                if let Ok(prop) = tokio::process::Command::new("busctl")
                    .args([
                        "--user",
                        "get-property",
                        first,
                        "/org/mpris/MediaPlayer2",
                        "org.mpris.MediaPlayer2.Player",
                        "PlaybackStatus",
                    ])
                    .output()
                    .await
                {
                    let val = String::from_utf8_lossy(&prop.stdout);
                    if val.contains("Playing") {
                        return true;
                    }
                }
            }
        }
    }
    false
}

/// Pauses any other MPRIS player currently in the Playing state on the session bus.
pub async fn pause_other_mpris_players() {
    let out = match tokio::process::Command::new("busctl")
        .args(["--user", "list", "--acquired"])
        .output()
        .await
    {
        Ok(o) => o,
        Err(_) => return,
    };
    let text = String::from_utf8_lossy(&out.stdout);
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(first) = trimmed.split_whitespace().next() {
            if first.starts_with("org.mpris.MediaPlayer2.") && first != "org.mpris.MediaPlayer2.cloudmusic" {
                if let Ok(prop) = tokio::process::Command::new("busctl")
                    .args([
                        "--user",
                        "get-property",
                        first,
                        "/org/mpris/MediaPlayer2",
                        "org.mpris.MediaPlayer2.Player",
                        "PlaybackStatus",
                    ])
                    .output()
                    .await
                {
                    let val = String::from_utf8_lossy(&prop.stdout);
                    if val.contains("Playing") {
                        let _ = tokio::process::Command::new("qdbus6")
                            .args([first, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player.Pause"])
                            .output()
                            .await;
                    }
                }
            }
        }
    }
}

