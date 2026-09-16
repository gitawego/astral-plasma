use crate::domain::ports::DynResult;
use serde_json::json;
use std::io::Write;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};

pub async fn get_mpris_art_url(conn: &zbus::Connection, app_name: &str) -> Option<String> {
    let bus = zbus::fdo::DBusProxy::new(conn).await.ok()?;
    let names = bus.list_names().await.ok()?;

    let app_lower = app_name.to_lowercase();
    for name in names {
        let name_str = name.as_str();
        if name_str.starts_with("org.mpris.MediaPlayer2.") {
            let player_part = name_str
                .trim_start_matches("org.mpris.MediaPlayer2.")
                .to_lowercase();
            if app_lower.contains(&player_part) || player_part.contains(&app_lower) {
                if let Ok(proxy) = zbus::Proxy::new(
                    conn,
                    name_str,
                    "/org/mpris/MediaPlayer2",
                    "org.mpris.MediaPlayer2.Player",
                )
                .await
                {
                    if let Ok(metadata) = proxy
                        .get_property::<std::collections::HashMap<
                            String,
                            zbus::zvariant::OwnedValue,
                        >>("Metadata")
                        .await
                    {
                        if let Some(art) = metadata.get("mpris:artUrl") {
                            if let Ok(s) = <&str>::try_from(art) {
                                if !s.is_empty() {
                                    return Some(s.to_string());
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    None
}

pub async fn run_notif_monitor() -> DynResult<()> {
    let conn = match zbus::Connection::session().await {
        Ok(c) => Some(c),
        Err(e) => {
            eprintln!("[notif_monitor] Failed to connect to session bus: {}", e);
            None
        }
    };

    let mut child = match tokio::process::Command::new("dbus-monitor")
        .arg("type='method_call',interface='org.freedesktop.Notifications',member='Notify'")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Failed to run dbus-monitor: {}", e);
            return Ok(());
        }
    };

    let stdout = match child.stdout.take() {
        Some(s) => s,
        None => return Ok(()),
    };

    let mut reader = BufReader::new(stdout).lines();
    let mut in_notify = false;
    let mut strings = Vec::new();
    let mut image_path = String::new();

    while let Ok(Some(line)) = reader.next_line().await {
        let trimmed = line.trim();
        if trimmed.contains("member=Notify") {
            in_notify = true;
            strings.clear();
            image_path.clear();
            continue;
        }

        if in_notify {
            let val_opt = if let Some(rest) = trimmed.strip_prefix("string \"") {
                rest.strip_suffix('"')
            } else if let Some(idx) = trimmed.find("string \"") {
                let rest = &trimmed[idx + 8..];
                rest.strip_suffix('"')
            } else {
                None
            };

            if let Some(val) = val_opt {
                if strings.len() < 4 {
                    strings.push(val.to_string());
                } else if image_path.is_empty()
                    && (val.starts_with('/') || val.starts_with("file://"))
                {
                    image_path = val.to_string();
                }
            } else if line.starts_with("   int32 ")
                || trimmed.starts_with("method call")
                || trimmed.starts_with("signal")
            {
                if strings.len() >= 4 {
                    let icon_is_path =
                        strings[1].starts_with('/') || strings[1].starts_with("file://");
                    let mut img = if !image_path.is_empty() {
                        image_path.clone()
                    } else if icon_is_path {
                        strings[1].clone()
                    } else {
                        String::new()
                    };

                    if img.is_empty() {
                        if let Some(ref c) = conn {
                            if let Some(art) = get_mpris_art_url(c, &strings[0]).await {
                                img = art;
                            }
                        }
                    }

                    let app_lower = strings[0].to_lowercase();
                    let is_media = app_lower.contains("strawberry")
                        || app_lower.contains("elisa")
                        || app_lower.contains("cloudmusic")
                        || app_lower.contains("netease")
                        || app_lower.contains("music")
                        || app_lower.contains("spotify");

                    let icon_name = if !strings[1].is_empty() {
                        &strings[1]
                    } else if is_media {
                        "music_note"
                    } else {
                        "info"
                    };

                    let payload = json!({
                        "app": strings[0],
                        "icon": icon_name,
                        "summary": strings[2],
                        "body": strings[3],
                        "image": img,
                    });

                    let mut out = std::io::stdout();
                    if writeln!(out, "{}", payload).is_err() || out.flush().is_err() {
                        // Broken pipe: reader exited cleanly
                        break;
                    }
                    strings.clear();
                    image_path.clear();
                }
                in_notify = false;
            }
        }
    }

    let _ = child.kill().await;
    Ok(())
}
