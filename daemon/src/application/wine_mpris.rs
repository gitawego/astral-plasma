use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::Mutex;
use zbus::connection::Builder;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedValue, Value};
use zbus::Connection;

use crate::domain::media::MediaAction;
use crate::domain::ports::DynResult;
use crate::domain::wine_media::WineMediaInfo;
use crate::infrastructure::media::registry::WinePlayerRegistry;

pub struct WineMprisRoot {
    state: Arc<Mutex<WineMprisPlayerState>>,
}

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
    async fn identity(&self) -> String {
        let st = self.state.lock().await;
        if !st.player_name.is_empty() {
            st.player_name.clone()
        } else {
            "NetEase Cloud Music (Wine)".to_string()
        }
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
    pub player_id: String,
    pub player_name: String,
    pub title: String,
    pub artist: String,
    pub art_url: String,
    pub is_playing: bool,
    pub duration_micros: i64,
    pub position_micros: i64,
    pub last_play_instant: Option<Instant>,
    pub track_id: String,
    pub seq: u64,
}

impl Default for WineMprisPlayerState {
    fn default() -> Self {
        Self {
            player_id: "cloudmusic".to_string(),
            player_name: "NetEase Cloud Music (Wine)".to_string(),
            title: String::new(),
            artist: String::new(),
            art_url: String::new(),
            is_playing: false,
            duration_micros: 0,
            position_micros: 0,
            last_play_instant: None,
            track_id: String::new(),
            seq: 0,
        }
    }
}

/// Best-effort description of a D-Bus caller, for playback diagnostics.
///
/// The Wine bridge is a public MPRIS interface: any client on the session can
/// press its buttons. When playback toggles unexpectedly, the log must say who
/// asked for it instead of leaving it a mystery.
async fn describe_caller(sender: Option<&zbus::names::UniqueName<'_>>) -> String {
    let Some(sender) = sender else {
        return "unknown caller".to_string();
    };
    let unique = sender.as_str().to_string();
    let pid = tokio::process::Command::new("qdbus6")
        .args([
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus.GetConnectionUnixProcessID",
            &unique,
        ])
        .output()
        .await
        .ok()
        .filter(|out| out.status.success())
        .and_then(|out| {
            String::from_utf8_lossy(&out.stdout)
                .trim()
                .parse::<u32>()
                .ok()
        });
    match pid {
        Some(pid) => {
            let comm = std::fs::read_to_string(format!("/proc/{pid}/comm")).unwrap_or_default();
            format!("{unique} (pid {pid} {})", comm.trim())
        }
        None => unique,
    }
}

async fn log_mpris_call(method: &str, sender: Option<&zbus::names::UniqueName<'_>>) {
    eprintln!("[mpris] {method} requested by {}", describe_caller(sender).await);
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

        let track_path_suffix = if !st.track_id.is_empty() {
            let clean: String = st.track_id.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '_').collect();
            clean
        } else {
            format!("track_{}", st.seq)
        };

        if let Ok(track_id) = ObjectPath::try_from(format!("/org/mpris/MediaPlayer2/Track/{}", track_path_suffix)) {
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

    async fn next(&self, #[zbus(header)] header: zbus::message::Header<'_>) {
        eprintln!("[mpris] Next requested by {}", describe_caller(header.sender()).await);
        let (player_id, _is_playing) = {
            let mut st = self.state.lock().await;
            st.position_micros = 0;
            st.last_play_instant = if st.is_playing { Some(Instant::now()) } else { None };
            (st.player_id.clone(), st.is_playing)
        };
        let reg = WinePlayerRegistry::new();
        let adapter = reg.find_adapter(&player_id, "");
        let _ = adapter.send_action(MediaAction::Next);
    }

    async fn previous(&self, #[zbus(header)] header: zbus::message::Header<'_>) {
        eprintln!("[mpris] Previous requested by {}", describe_caller(header.sender()).await);
        let (player_id, _is_playing) = {
            let mut st = self.state.lock().await;
            st.position_micros = 0;
            st.last_play_instant = if st.is_playing { Some(Instant::now()) } else { None };
            (st.player_id.clone(), st.is_playing)
        };
        let reg = WinePlayerRegistry::new();
        let adapter = reg.find_adapter(&player_id, "");
        let _ = adapter.send_action(MediaAction::Previous);
    }

    /// The D-Bus entry point every playback toggle funnels through.
    ///
    /// The logging is deliberate: this interface is public, so "why did my
    /// music start playing?" must be answerable from the daemon log.
    async fn play_pause(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) {
        log_mpris_call("PlayPause", header.sender()).await;
        self.toggle_playback(emitter).await;
    }

    async fn play(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) {
        let is_playing = self.state.lock().await.is_playing;
        if !is_playing {
            log_mpris_call("Play", header.sender()).await;
            self.toggle_playback(emitter).await;
        }
    }

    async fn pause(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) {
        let is_playing = self.state.lock().await.is_playing;
        if is_playing {
            log_mpris_call("Pause", header.sender()).await;
            self.toggle_playback(emitter).await;
        }
    }

    async fn stop(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) {
        let is_playing = self.state.lock().await.is_playing;
        if is_playing {
            log_mpris_call("Stop", header.sender()).await;
            self.toggle_playback(emitter).await;
        }
    }
}

impl WineMprisPlayer {
    /// Toggle the Wine player and publish the resulting state.
    async fn toggle_playback(&self, emitter: SignalEmitter<'_>) {
        let (player_id, is_now_playing) = {
            let mut st = self.state.lock().await;
            st.is_playing = !st.is_playing;
            if st.is_playing {
                st.last_play_instant = Some(Instant::now());
            } else if let Some(instant) = st.last_play_instant.take() {
                st.position_micros += instant.elapsed().as_micros() as i64;
            }
            (st.player_id.clone(), st.is_playing)
        };

        let reg = WinePlayerRegistry::new();
        let adapter = reg.find_adapter(&player_id, "");
        let _ = adapter.send_action(MediaAction::PlayPause);

        let _ = self.playback_status_changed(&emitter).await;

        if is_now_playing {
            pause_other_mpris_players().await;
        }
    }
}

pub struct WineMprisService {
    conn: Connection,
    player: WineMprisPlayer,
    state: Arc<Mutex<WineMprisPlayerState>>,
}

/// Acquire the Wine MPRIS bridge, waiting out a previous owner of the bus name.
///
/// The bridge is a session singleton, and a shell reload starts the incoming
/// daemon before the outgoing one has necessarily released
/// `org.mpris.MediaPlayer2.cloudmusic`. zbus requests names without queueing, so
/// a single attempt is not enough: retry until the previous instance is gone.
/// Losing the race permanently would leave the session with no Wine player at
/// all, which is worse than a short start-up delay.
pub async fn connect_wine_mpris_with_retry(
    attempts: u32,
    delay: std::time::Duration,
) -> DynResult<WineMprisService> {
    crate::application::retry::retry_async(attempts, delay, WineMprisService::new).await
}

impl WineMprisService {
    pub async fn new() -> DynResult<Self> {
        let state = Arc::new(Mutex::new(WineMprisPlayerState::default()));
        let root = WineMprisRoot {
            state: Arc::clone(&state),
        };
        let player = WineMprisPlayer {
            state: Arc::clone(&state),
        };

        let conn = Builder::session()?
            .name("org.mpris.MediaPlayer2.cloudmusic")?
            .serve_at("/org/mpris/MediaPlayer2", root)?
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
        let (status_changed, meta_changed, should_retry, current_seq) = {
            let mut st = self.state.lock().await;
            st.seq += 1;
            let current_seq = st.seq;

            let title_changed = st.title != media.title;
            let artist_changed = st.artist != media.artist;
            let art_changed = st.art_url != media.art_url;
            let new_duration_micros = (media.duration_ms * 1000) as i64;
            let duration_changed = st.duration_micros != new_duration_micros;

            st.player_id = media.player_id.clone();
            if !media.player_name.is_empty() {
                st.player_name = media.player_name.clone();
            }

            if media.title.is_empty() {
                // Stopped state
                let had_title = !st.title.is_empty();
                let was_playing = st.is_playing;
                st.title.clear();
                st.artist.clear();
                st.art_url.clear();
                st.duration_micros = 0;
                st.position_micros = 0;
                st.last_play_instant = None;
                st.is_playing = false;
                (was_playing, had_title, false, current_seq)
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

                let needs_retry = st.art_url.is_empty() || media.duration_ms == 180_000;
                (was_playing != should_play, true, needs_retry, current_seq)
            } else {
                // Same title: update art_url or duration if changed
                let mut meta_c = false;
                if art_changed && !media.art_url.is_empty() {
                    st.art_url = media.art_url.clone();
                    meta_c = true;
                }
                if duration_changed && media.duration_ms > 0 && media.duration_ms != 180_000 {
                    st.duration_micros = new_duration_micros;
                    meta_c = true;
                }
                if artist_changed {
                    st.artist = media.artist.clone();
                    meta_c = true;
                }
                let needs_retry = st.art_url.is_empty() || st.duration_micros == 180_000_000;
                (false, meta_c, needs_retry, current_seq)
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

        // Spawn asynchronous staggered retry task if art_url is missing or duration is placeholder
        if should_retry && !media.title.is_empty() {
            let target_title = media.title.clone();
            let target_artist = media.artist.clone();
            let player_id = media.player_id.clone();
            let state = Arc::clone(&self.state);
            let conn = self.conn.clone();
            let player = self.player.clone();

            tokio::spawn(async move {
                let retry_delays_ms = [250, 650, 1400, 2800];
                for delay in retry_delays_ms {
                    tokio::time::sleep(tokio::time::Duration::from_millis(delay)).await;

                    // Check if track is still current
                    {
                        let st = state.lock().await;
                        if st.seq != current_seq || st.title != target_title {
                            break; // User skipped or track changed
                        }
                        if !st.art_url.is_empty() && st.duration_micros != 180_000_000 {
                            break; // Already fully resolved
                        }
                    }

                    // Run metadata resolver in worker thread
                    let target_t = target_title.clone();
                    let target_a = target_artist.clone();
                    let pid = player_id.clone();
                    let meta_res = tokio::task::spawn_blocking(move || {
                        let reg = WinePlayerRegistry::new();
                        let ad = reg.find_adapter(&pid, "");
                        ad.resolve_metadata(&target_t, &target_a)
                    }).await;

                    if let Ok(meta) = meta_res {
                        let mut changed = false;
                        {
                            let mut st = state.lock().await;
                            if st.seq != current_seq || st.title != target_title {
                                break;
                            }
                            if !meta.art_url.is_empty() && st.art_url != meta.art_url {
                                st.art_url = meta.art_url.clone();
                                changed = true;
                            }
                            if meta.duration_ms > 0 && meta.duration_ms != 180_000 {
                                let new_dur = (meta.duration_ms * 1000) as i64;
                                if st.duration_micros != new_dur {
                                    st.duration_micros = new_dur;
                                    changed = true;
                                }
                            }
                        }

                        if changed {
                            if let Ok(emitter) = SignalEmitter::new(&conn, "/org/mpris/MediaPlayer2") {
                                let _ = player.metadata_changed(&emitter).await;
                            }
                            let st = state.lock().await;
                            if !st.art_url.is_empty() && st.duration_micros != 180_000_000 {
                                break;
                            }
                        }
                    }
                }
            });
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
