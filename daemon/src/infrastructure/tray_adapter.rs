use crate::domain::model::TrayItem;
use crate::domain::ports::{DynResult, TrayPort};
use std::process::Command;

pub struct TrayAdapter;

impl TrayAdapter {
    pub fn new() -> Self {
        Self
    }
}

impl Default for TrayAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl TrayPort for TrayAdapter {
    fn query_tray(&self) -> DynResult<Vec<TrayItem>> {
        let mut tray_items = Vec::new();

        let output = match Command::new("qdbus6")
            .args(["org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher.RegisteredStatusNotifierItems"])
            .output()
        {
            Ok(out) => String::from_utf8_lossy(&out.stdout).to_string(),
            Err(_) => return Ok(tray_items),
        };

        for line in output.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            let (svc, path) = if let Some(idx) = trimmed.find('/') {
                (&trimmed[..idx], &trimmed[idx..])
            } else {
                (trimmed, "/")
            };

            let item_id = Command::new("qdbus6")
                .args([svc, path, "org.kde.StatusNotifierItem.Id"])
                .output()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .unwrap_or_default();

            let mut item_icon = Command::new("qdbus6")
                .args([svc, path, "org.kde.StatusNotifierItem.IconName"])
                .output()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .unwrap_or_default();

            let mut item_title = Command::new("qdbus6")
                .args([svc, path, "org.kde.StatusNotifierItem.Title"])
                .output()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .unwrap_or_default();

            if item_id.is_empty() && item_title.is_empty() {
                continue;
            }
            if item_id.chars().all(|c| c.is_ascii_digit()) && item_icon.is_empty() && item_title.is_empty() {
                continue;
            }

            let mut m_icon = "circle".to_string();
            let id_lower = format!("{} {} {}", item_id, item_title, item_icon).to_lowercase();
            let mut im_badge = String::new();

            if id_lower.contains("keyboard") || id_lower.contains("fcitx") || id_lower.contains("input") {
                m_icon = "keyboard".to_string();
                if let Ok(cur_out) = Command::new("fcitx5-remote").arg("-n").output() {
                    let cur_im = String::from_utf8_lossy(&cur_out.stdout).trim().to_string();
                    let cur_lower = cur_im.to_lowercase();
                    if cur_lower.contains("rime") {
                        item_icon = "fcitx-rime".to_string();
                        m_icon = "rime".to_string();
                        im_badge = "中".to_string();
                        item_title = "Input Method: Rime (中)".to_string();
                    } else if cur_lower.contains("pinyin") {
                        item_icon = "fcitx-pinyin".to_string();
                        m_icon = "translate".to_string();
                        im_badge = "拼".to_string();
                        item_title = "Input Method: Pinyin (拼)".to_string();
                    } else if cur_lower.contains("us") || cur_lower.contains("keyboard") {
                        item_icon = "input-keyboard".to_string();
                        m_icon = "keyboard".to_string();
                        im_badge = "EN".to_string();
                        item_title = "Input Method: English (EN)".to_string();
                    } else if !cur_im.is_empty() {
                        im_badge = cur_im.chars().take(2).collect::<String>().to_uppercase();
                        item_title = format!("Input Method: {}", cur_im);
                    }
                }
            } else if id_lower.contains("update") || id_lower.contains("cachy") {
                m_icon = "system_update".to_string();
            } else if id_lower.contains("sunshine") || id_lower.contains("stream") {
                m_icon = "cast".to_string();
            } else if id_lower.contains("token") {
                m_icon = "toll".to_string();
            } else if id_lower.contains("dropbox") || id_lower.contains("cloud") {
                m_icon = "cloud".to_string();
            } else if id_lower.contains("bluetooth") {
                m_icon = "bluetooth".to_string();
            } else if id_lower.contains("volume") || id_lower.contains("audio") {
                m_icon = "volume_up".to_string();
            } else if id_lower.contains("wifi") || id_lower.contains("network") {
                m_icon = "wifi".to_string();
            }

            tray_items.push(TrayItem {
                service: svc.to_string(),
                path: path.to_string(),
                id: item_id,
                title: item_title,
                material_icon: m_icon,
                raw_icon: item_icon,
                im_badge,
            });
        }

        Ok(tray_items)
    }
}
