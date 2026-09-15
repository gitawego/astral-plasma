use crate::domain::model::{TrayItem, TrayMenuItem};
use crate::domain::ports::{DynResult, TrayPort};
use std::process::Command;

fn qdbus_get(svc: &str, path: &str, method: &str) -> String {
    if let Ok(out) = Command::new("qdbus6").args([svc, path, method]).output() {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.starts_with("Error:") && !s.starts_with("Cannot find") {
                return s;
            }
        }
    }
    String::new()
}

fn busctl_get_objpath(svc: &str, path: &str, iface: &str, prop: &str) -> String {
    if let Ok(out) = Command::new("busctl")
        .args(["--user", "get-property", svc, path, iface, prop])
        .output()
    {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if let Some(rest) = s.strip_prefix("o \"") {
                if let Some(val) = rest.strip_suffix('"') {
                    return val.to_string();
                }
            } else if let Some(rest) = s.strip_prefix('"') {
                if let Some(val) = rest.strip_suffix('"') {
                    return val.to_string();
                }
            } else if !s.starts_with("Error") {
                return s;
            }
        }
    }
    String::new()
}

pub struct TrayAdapter;

impl TrayAdapter {
    pub fn new() -> Self {
        Self
    }

    pub fn parse_dbusmenu_json(raw: &serde_json::Value) -> DynResult<Vec<TrayMenuItem>> {
        let mut items = Vec::new();
        if let Some(data) = raw.get("data").and_then(|d| d.as_array()) {
            if data.len() >= 2 {
                if let Some(root_node) = data[1].as_array() {
                    if root_node.len() >= 3 {
                        if let Some(children) = root_node[2].as_array() {
                            for child in children {
                                if let Some(cdata) = child.get("data").and_then(|d| d.as_array()) {
                                    if cdata.len() >= 2 {
                                        let id = cdata[0].as_i64().unwrap_or(0) as i32;
                                        let props = cdata[1].as_object();

                                        let label = props
                                            .and_then(|p| p.get("label"))
                                            .and_then(|l| l.get("data"))
                                            .and_then(|s| s.as_str())
                                            .unwrap_or("")
                                            .replace('_', "");

                                        let item_type = props
                                            .and_then(|p| p.get("type"))
                                            .and_then(|t| t.get("data"))
                                            .and_then(|s| s.as_str())
                                            .unwrap_or("");

                                        let is_separator = item_type == "separator";

                                        let enabled = props
                                            .and_then(|p| p.get("enabled"))
                                            .and_then(|e| e.get("data"))
                                            .and_then(|b| b.as_bool())
                                            .unwrap_or(true);

                                        let icon = props
                                            .and_then(|p| p.get("icon-name"))
                                            .and_then(|i| i.get("data"))
                                            .and_then(|s| s.as_str())
                                            .unwrap_or("")
                                            .to_string();

                                        items.push(TrayMenuItem {
                                            id,
                                            label,
                                            is_separator,
                                            enabled,
                                            icon,
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Ok(items)
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

            let item_id = qdbus_get(svc, path, "org.kde.StatusNotifierItem.Id");
            let mut item_icon = qdbus_get(svc, path, "org.kde.StatusNotifierItem.IconName");
            let mut item_title = qdbus_get(svc, path, "org.kde.StatusNotifierItem.Title");

            if item_id.is_empty() && item_title.is_empty() && item_icon.is_empty() {
                continue;
            }
            if item_id.chars().all(|c| c.is_ascii_digit()) && item_icon.is_empty() && item_title.is_empty() {
                continue;
            }
            if item_icon.starts_with("Error") {
                item_icon.clear();
            }
            if item_title.starts_with("Error") {
                item_title.clear();
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

            let menu_path = busctl_get_objpath(svc, path, "org.kde.StatusNotifierItem", "Menu");

            tray_items.push(TrayItem {
                service: svc.to_string(),
                path: path.to_string(),
                menu_path,
                id: item_id,
                title: item_title,
                material_icon: m_icon,
                raw_icon: item_icon,
                im_badge,
            });
        }

        Ok(tray_items)
    }

    fn fetch_menu(&self, service: &str, menu_path: &str) -> DynResult<Vec<TrayMenuItem>> {
        let out = Command::new("busctl")
            .args([
                "--user",
                "--json=short",
                "call",
                service,
                menu_path,
                "com.canonical.dbusmenu",
                "GetLayout",
                "iias",
                "0",
                "2",
                "0",
            ])
            .output()?;

        if !out.status.success() {
            let err = String::from_utf8_lossy(&out.stderr);
            return Err(format!("busctl GetLayout failed: {}", err).into());
        }

        let val: serde_json::Value = serde_json::from_slice(&out.stdout)?;
        Self::parse_dbusmenu_json(&val)
    }

    fn click_item(&self, service: &str, menu_path: &str, item_id: i32) -> DynResult<()> {
        let out = Command::new("busctl")
            .args([
                "--user",
                "call",
                service,
                menu_path,
                "com.canonical.dbusmenu",
                "Event",
                "isvu",
                &item_id.to_string(),
                "clicked",
                "s",
                "",
                "0",
            ])
            .output()?;

        if !out.status.success() {
            let err = String::from_utf8_lossy(&out.stderr);
            return Err(format!("busctl Event failed: {}", err).into());
        }

        Ok(())
    }
}
