use crate::domain::model::{TrayItem, TrayMenuItem};
use crate::domain::ports::{DynResult, TrayPort};
use std::process::Command;
use std::hash::{Hash, Hasher};

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

fn sni_get_str(svc: &str, path: &str, prop: &str) -> String {
    for iface in ["org.kde.StatusNotifierItem", "org.freedesktop.StatusNotifierItem"] {
        if let Ok(out) = Command::new("busctl")
            .args(["--user", "get-property", svc, path, iface, prop])
            .output()
        {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if let Some(rest) = s.strip_prefix("s \"") {
                    if let Some(val) = rest.strip_suffix('"') {
                        if !val.starts_with("Error") {
                            return val.to_string();
                        }
                    }
                } else if let Some(rest) = s.strip_prefix('"') {
                    if let Some(val) = rest.strip_suffix('"') {
                        if !val.starts_with("Error") {
                            return val.to_string();
                        }
                    }
                } else if !s.starts_with("Error") && !s.starts_with("Failed") {
                    return s;
                }
            }
        }
    }

    for iface in ["org.kde.StatusNotifierItem", "org.freedesktop.StatusNotifierItem"] {
        let method = format!("{}.{}", iface, prop);
        let val = qdbus_get(svc, path, &method);
        if !val.is_empty() && !val.starts_with("Error") {
            return val;
        }
    }

    String::new()
}

fn sni_get_tooltip_title(svc: &str, path: &str) -> String {
    for iface in ["org.kde.StatusNotifierItem", "org.freedesktop.StatusNotifierItem"] {
        if let Ok(out) = Command::new("busctl")
            .args(["--user", "get-property", svc, path, iface, "ToolTip"])
            .output()
        {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
                let quotes: Vec<&str> = s.split('"').collect();
                if quotes.len() >= 4 && !quotes[3].is_empty() {
                    return quotes[3].to_string();
                }
            }
        }
    }
    String::new()
}

fn busctl_get_objpath(svc: &str, path: &str, prop: &str) -> String {
    for iface in ["org.kde.StatusNotifierItem", "org.freedesktop.StatusNotifierItem"] {
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
                } else if !s.starts_with("Error") && !s.starts_with("Failed") {
                    return s;
                }
            }
        }
    }
    String::new()
}

fn sni_get_bool(svc: &str, path: &str, prop: &str) -> bool {
    for iface in ["org.kde.StatusNotifierItem", "org.freedesktop.StatusNotifierItem"] {
        if let Ok(out) = Command::new("busctl")
            .args(["--user", "get-property", svc, path, iface, prop])
            .output()
        {
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if s.starts_with("b true") || s == "true" {
                    return true;
                }
            }
        }
    }
    false
}

fn sni_get_pixmap(svc: &str, path: &str) -> Option<String> {
    for iface in ["org.kde.StatusNotifierItem", "org.freedesktop.StatusNotifierItem"] {
        if let Ok(out) = Command::new("busctl")
            .args(["--user", "--json=short", "get-property", svc, path, iface, "IconPixmap"])
            .output()
        {
            if out.status.success() {
                if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
                    if let Some(data) = val.get("data").and_then(|d| d.as_array()) {
                        let mut best_pixmap: Option<(u32, u32, &[serde_json::Value])> = None;
                        let mut best_score: i32 = -1;

                        for item in data {
                            if let Some(arr) = item.as_array() {
                                if arr.len() >= 3 {
                                    let w = arr[0].as_i64().unwrap_or(0) as u32;
                                    let h = arr[1].as_i64().unwrap_or(0) as u32;
                                    if let Some(bytes) = arr[2].as_array() {
                                        if w > 0 && h > 0 && bytes.len() == (w * h * 4) as usize {
                                            let score = if w >= 32 && w <= 64 {
                                                1000 - (w as i32 - 48).abs()
                                            } else if w < 32 {
                                                w as i32
                                            } else {
                                                500 - (w as i32 - 64)
                                            };
                                            if score > best_score {
                                                best_score = score;
                                                best_pixmap = Some((w, h, bytes));
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if let Some((w, h, bytes)) = best_pixmap {
                            let mut hasher = std::collections::hash_map::DefaultHasher::new();
                            let mut rgba = Vec::with_capacity((w * h * 4) as usize);

                            for chunk in bytes.chunks_exact(4) {
                                let a = chunk[0].as_u64().unwrap_or(0) as u8;
                                let r = chunk[1].as_u64().unwrap_or(0) as u8;
                                let g = chunk[2].as_u64().unwrap_or(0) as u8;
                                let b = chunk[3].as_u64().unwrap_or(0) as u8;
                                a.hash(&mut hasher);
                                r.hash(&mut hasher);
                                g.hash(&mut hasher);
                                b.hash(&mut hasher);
                                rgba.push(r);
                                rgba.push(g);
                                rgba.push(b);
                                rgba.push(a);
                            }

                            let hash = hasher.finish();
                            let uid = unsafe { libc::getuid() };
                            let cache_dir = std::env::temp_dir().join(format!("caelestia_tray_{}", uid));
                            let _ = std::fs::create_dir_all(&cache_dir);

                            let safe_svc = svc.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect::<String>();
                            let file_name = format!("tray_{}_{:016x}.png", safe_svc, hash);
                            let file_path = cache_dir.join(file_name);

                            if !file_path.exists() {
                                if let Some(img) = image::RgbaImage::from_raw(w, h, rgba) {
                                    let _ = img.save(&file_path);
                                }
                            }

                            if file_path.exists() {
                                return Some(format!("file://{}", file_path.to_string_lossy()));
                            }
                        }
                    }
                }
            }
        }
    }
    None
}

fn resolve_desktop_icon(svc: &str, item_id: &str) -> Option<String> {
    let pid = if let Ok(out) = Command::new("busctl")
        .args(["--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", svc])
        .output()
    {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout);
            s.split_whitespace().nth(1).and_then(|p| p.parse::<u32>().ok())
        } else {
            None
        }
    } else {
        None
    };

    let mut candidate_names = Vec::new();

    if let Some(p) = pid {
        if let Ok(comm) = std::fs::read_to_string(format!("/proc/{}/comm", p)) {
            let trimmed = comm.trim().to_lowercase();
            if !trimmed.is_empty() {
                candidate_names.push(trimmed);
            }
        }
    }

    let sanitized_id = item_id
        .split(|c: char| !c.is_alphanumeric())
        .next()
        .unwrap_or("")
        .to_lowercase();
    if !sanitized_id.is_empty() && !candidate_names.contains(&sanitized_id) {
        candidate_names.push(sanitized_id);
    }

    for cand in &candidate_names {
        for dir in ["/usr/share/applications", "/usr/local/share/applications"] {
            if let Ok(entries) = std::fs::read_dir(dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if let Some(fname) = path.file_name().and_then(|f| f.to_str()) {
                        let fname_lower = fname.to_lowercase();
                        if fname_lower.ends_with(".desktop") && fname_lower.contains(cand) {
                            if let Ok(content) = std::fs::read_to_string(&path) {
                                for line in content.lines() {
                                    if let Some(rest) = line.strip_prefix("Icon=") {
                                        let icon_val = rest.trim();
                                        if !icon_val.is_empty() {
                                            return Some(icon_val.to_string());
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if std::path::Path::new(&format!("/usr/share/icons/hicolor/48x48/apps/{}.png", cand)).exists()
            || std::path::Path::new(&format!("/usr/share/pixmaps/{}.png", cand)).exists()
        {
            return Some(cand.clone());
        }
    }

    None
}

pub struct TrayAdapter;

impl TrayAdapter {
    pub fn new() -> Self {
        Self
    }

    pub fn resolve_tray_meta(item_id: &str, item_title: &str, item_icon: &str) -> (String, String, String) {
        let mut title = item_title.to_string();
        let mut icon = item_icon.to_string();
        let mut m_icon = "circle".to_string();

        let id_lower = format!("{} {} {}", item_id, title, icon).to_lowercase();

        if id_lower.contains("keyboard") || id_lower.contains("fcitx") || id_lower.contains("input") {
            m_icon = "keyboard".to_string();
        } else if id_lower.contains("antigravity") || id_lower.contains("opencode") {
            m_icon = "smart_toy".to_string();
            if icon.is_empty() {
                icon = "antigravity".to_string();
            }
            if title.is_empty() {
                title = "Antigravity".to_string();
            }
        } else if id_lower.contains("music") || id_lower.contains("strawberry") || id_lower.contains("spotify") || id_lower.contains("player") || id_lower.contains("audio") {
            m_icon = "music_note".to_string();
            if icon.is_empty() {
                if id_lower.contains("spotify") { icon = "spotify".to_string(); }
                else if id_lower.contains("strawberry") { icon = "strawberry".to_string(); }
            }
        } else if id_lower.contains("update") || id_lower.contains("cachy") {
            m_icon = "system_update".to_string();
        } else if id_lower.contains("sunshine") || id_lower.contains("stream") {
            m_icon = "cast".to_string();
        } else if id_lower.contains("token") {
            m_icon = "toll".to_string();
        } else if id_lower.contains("dropbox") || id_lower.contains("cloud") {
            m_icon = "cloud".to_string();
        } else if id_lower.contains("discord") {
            m_icon = "chat".to_string();
            if icon.is_empty() { icon = "discord".to_string(); }
        } else if id_lower.contains("slack") {
            m_icon = "forum".to_string();
            if icon.is_empty() { icon = "slack".to_string(); }
        } else if id_lower.contains("code") || id_lower.contains("vscode") {
            m_icon = "code".to_string();
            if icon.is_empty() { icon = "vscode".to_string(); }
        } else if id_lower.contains("steam") {
            m_icon = "sports_esports".to_string();
            if icon.is_empty() { icon = "steam".to_string(); }
        } else if id_lower.contains("telegram") {
            m_icon = "send".to_string();
            if icon.is_empty() { icon = "telegram".to_string(); }
        } else if id_lower.contains("bluetooth") {
            m_icon = "bluetooth".to_string();
        } else if id_lower.contains("volume") || id_lower.contains("audio") {
            m_icon = "volume_up".to_string();
        } else if id_lower.contains("wifi") || id_lower.contains("network") {
            m_icon = "wifi".to_string();
        } else if icon.is_empty() {
            if let Some(prefix) = item_id.split('_').next() {
                if !prefix.is_empty() && !prefix.chars().all(|c| c.is_ascii_digit()) && !prefix.contains(' ') {
                    icon = prefix.to_lowercase();
                }
            }
        }

        if !icon.starts_with("file://") && !icon.starts_with('/') && icon.contains(' ') {
            icon = icon.split_whitespace().next().unwrap_or("").to_lowercase();
        }

        (title, icon, m_icon)
    }

    pub fn clean_menu_label(raw: &str) -> String {
        raw.replace("__", "\u{0000}").replace('_', "").replace("\u{0000}", "_")
    }

    pub fn parse_dbusmenu_node(val: &serde_json::Value) -> Option<TrayMenuItem> {
        let node_arr = if let Some(arr) = val.get("data").and_then(|d| d.as_array()) {
            arr
        } else if let Some(arr) = val.as_array() {
            arr
        } else {
            return None;
        };

        if node_arr.len() < 2 {
            return None;
        }

        let id = node_arr[0].as_i64().unwrap_or(0) as i32;
        let props = node_arr[1].as_object();

        let visible = props
            .and_then(|p| p.get("visible"))
            .and_then(|v| v.get("data").or(Some(v)))
            .and_then(|b| b.as_bool())
            .unwrap_or(true);

        if !visible {
            return None;
        }

        let raw_label = props
            .and_then(|p| p.get("label"))
            .and_then(|l| l.get("data").or(Some(l)))
            .and_then(|s| s.as_str())
            .unwrap_or("");
        let label = Self::clean_menu_label(raw_label);

        let item_type = props
            .and_then(|p| p.get("type"))
            .and_then(|t| t.get("data").or(Some(t)))
            .and_then(|s| s.as_str())
            .unwrap_or("");

        let is_separator = item_type == "separator";

        let enabled = props
            .and_then(|p| p.get("enabled"))
            .and_then(|e| e.get("data").or(Some(e)))
            .and_then(|b| b.as_bool())
            .unwrap_or(true);

        let icon = props
            .and_then(|p| p.get("icon-name"))
            .and_then(|i| i.get("data").or(Some(i)))
            .and_then(|s| s.as_str())
            .unwrap_or("")
            .to_string();

        let children_display = props
            .and_then(|p| p.get("children-display"))
            .and_then(|c| c.get("data").or(Some(c)))
            .and_then(|s| s.as_str())
            .unwrap_or("");

        let toggle_type = props
            .and_then(|p| p.get("toggle-type"))
            .and_then(|t| t.get("data").or(Some(t)))
            .and_then(|s| s.as_str())
            .unwrap_or("")
            .to_string();

        let toggle_state = props
            .and_then(|p| p.get("toggle-state"))
            .and_then(|s| s.get("data").or(Some(s)))
            .and_then(|i| i.as_i64())
            .unwrap_or(0) as i32;

        let disposition = props
            .and_then(|p| p.get("disposition"))
            .and_then(|d| d.get("data").or(Some(d)))
            .and_then(|s| s.as_str())
            .unwrap_or("normal")
            .to_string();

        let mut children = Vec::new();
        if node_arr.len() >= 3 {
            if let Some(c_arr) = node_arr[2].as_array() {
                for c_val in c_arr {
                    if let Some(child_item) = Self::parse_dbusmenu_node(c_val) {
                        children.push(child_item);
                    }
                }
            }
        }

        let has_submenu = !children.is_empty() || children_display == "submenu";

        Some(TrayMenuItem {
            id,
            label,
            is_separator,
            enabled,
            icon,
            has_submenu,
            toggle_type,
            toggle_state,
            disposition,
            children,
        })
    }

    pub fn parse_dbusmenu_json(raw: &serde_json::Value) -> DynResult<Vec<TrayMenuItem>> {
        let mut items = Vec::new();
        if let Some(data) = raw.get("data").and_then(|d| d.as_array()) {
            if data.len() >= 2 {
                if let Some(root_node) = data[1].as_array() {
                    if root_node.len() >= 3 {
                        if let Some(children) = root_node[2].as_array() {
                            for child in children {
                                if let Some(item) = Self::parse_dbusmenu_node(child) {
                                    items.push(item);
                                }
                            }
                        }
                    }
                }
            }
        }
        Ok(items)
    }
    pub fn resolve_xembed_identity(win_id: u64) -> (String, String, String) {
        let (class_opt, title_opt) = crate::infrastructure::x11_input::query_x11_window_class_and_title(win_id);
        let raw_class = class_opt.unwrap_or_default();
        let raw_title = title_opt.unwrap_or_default();
        let class_lower = raw_class.to_lowercase();

        if class_lower.contains("cloudmusic") {
            let title = if !raw_title.is_empty() && !raw_title.to_lowercase().contains("cloudmusic") {
                raw_title
            } else {
                "NetEase Cloud Music".to_string()
            };
            ("cloudmusic".to_string(), title, "music_note".to_string())
        } else if class_lower.contains("wechat") {
            ("wechat".to_string(), "WeChat".to_string(), "chat".to_string())
        } else if class_lower.contains("qq") {
            ("qq".to_string(), "QQ".to_string(), "chat".to_string())
        } else if class_lower.contains("foobar2000") {
            ("foobar2000".to_string(), "foobar2000".to_string(), "music_note".to_string())
        } else if !raw_class.is_empty() {
            let clean_id = raw_class
                .strip_suffix(".exe")
                .or_else(|| raw_class.strip_suffix(".EXE"))
                .unwrap_or(&raw_class)
                .split('\0')
                .next()
                .unwrap_or(&raw_class)
                .trim()
                .to_string();
            let clean_title = if !raw_title.is_empty() {
                raw_title
            } else {
                clean_id.clone()
            };
            (clean_id, clean_title, String::new())
        } else {
            (String::new(), String::new(), String::new())
        }
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

            let item_id = sni_get_str(svc, path, "Id");
            let mut item_icon = sni_get_str(svc, path, "IconName");
            let mut item_title = sni_get_str(svc, path, "Title");

            if item_icon.starts_with("Error") {
                item_icon.clear();
            }
            if item_title.starts_with("Error") {
                item_title.clear();
            }

            if item_title.is_empty() {
                let tt = sni_get_tooltip_title(svc, path);
                if !tt.is_empty() {
                    item_title = tt;
                }
            }

            if item_icon.is_empty() {
                if let Some(pixmap_url) = sni_get_pixmap(svc, path) {
                    item_icon = pixmap_url;
                }
            }

            if item_icon.is_empty() {
                if let Some(desktop_icon) = resolve_desktop_icon(svc, &item_id) {
                    item_icon = desktop_icon;
                }
            }

            let mut final_id = item_id.clone();
            let mut final_title = item_title.clone();
            let mut final_icon = item_icon.clone();

            let is_numeric = (final_id.chars().all(|c| c.is_ascii_digit()) && !final_id.is_empty()) || final_id.is_empty();
            if is_numeric {
                let win_id = if !final_id.is_empty() {
                    final_id.parse::<u64>().unwrap_or(0)
                } else {
                    sni_get_str(svc, path, "WindowId").parse::<u64>().unwrap_or(0)
                };
                if win_id > 0 {
                    let (x_id, x_title, x_icon) = Self::resolve_xembed_identity(win_id);
                    if !x_id.is_empty() {
                        final_id = x_id;
                    }
                    if final_title.is_empty() && !x_title.is_empty() {
                        final_title = x_title;
                    }
                    if final_icon.is_empty() && !x_icon.is_empty() {
                        final_icon = x_icon;
                    }
                }
            }

            if final_id.is_empty() && final_title.is_empty() && final_icon.is_empty() {
                continue;
            }
            if final_id.chars().all(|c| c.is_ascii_digit()) && final_icon.is_empty() && final_title.is_empty() {
                continue;
            }

            let (item_title, mut item_icon, mut m_icon) = Self::resolve_tray_meta(&final_id, &final_title, &final_icon);
            let mut im_badge = String::new();

            let id_lower = format!("{} {} {}", final_id, item_title, item_icon).to_lowercase();
            if id_lower.contains("keyboard") || id_lower.contains("fcitx") || id_lower.contains("input") {
                m_icon = "keyboard".to_string();
                if let Ok(cur_out) = Command::new("fcitx5-remote").arg("-n").output() {
                    let cur_im = String::from_utf8_lossy(&cur_out.stdout).trim().to_string();
                    let cur_lower = cur_im.to_lowercase();
                    if cur_lower.contains("rime") {
                        item_icon = "fcitx-rime".to_string();
                        m_icon = "rime".to_string();
                        im_badge = "中".to_string();
                    } else if cur_lower.contains("pinyin") {
                        item_icon = "fcitx-pinyin".to_string();
                        m_icon = "translate".to_string();
                        im_badge = "拼".to_string();
                    } else if cur_lower.contains("us") || cur_lower.contains("keyboard") {
                        item_icon = "input-keyboard".to_string();
                        m_icon = "keyboard".to_string();
                        im_badge = "EN".to_string();
                    } else if !cur_im.is_empty() {
                        im_badge = cur_im.chars().take(2).collect::<String>().to_uppercase();
                    }
                }
            }

            let mut menu_path = busctl_get_objpath(svc, path, "Menu");
            let item_is_menu = sni_get_bool(svc, path, "ItemIsMenu");

            if menu_path.is_empty() {
                menu_path = "/SyntheticMenu".to_string();
            }

            tray_items.push(TrayItem {
                service: svc.to_string(),
                path: path.to_string(),
                menu_path,
                item_is_menu,
                id: final_id,
                title: item_title,
                material_icon: m_icon,
                raw_icon: item_icon,
                im_badge,
            });
        }

        Ok(tray_items)
    }

    fn fetch_menu(&self, service: &str, menu_path: &str) -> DynResult<Vec<TrayMenuItem>> {
        if menu_path == "/SyntheticMenu" || menu_path == "synthetic" {
            return Ok(Self::fetch_synthetic_menu(service));
        }

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
                "10",
                "0",
            ])
            .output()?;

        if !out.status.success() {
            return Ok(Self::fetch_synthetic_menu(service));
        }

        let val: serde_json::Value = serde_json::from_slice(&out.stdout)?;
        Self::parse_dbusmenu_json(&val)
    }

    fn click_item(&self, service: &str, menu_path: &str, item_id: i32) -> DynResult<()> {
        if menu_path == "/SyntheticMenu" || menu_path == "synthetic" {
            return Self::click_synthetic_item(service, item_id);
        }

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

impl TrayAdapter {
    pub fn fetch_synthetic_menu(service: &str) -> Vec<TrayMenuItem> {
        let mut app_id = sni_get_str(service, "/StatusNotifierItem", "Id");
        if app_id.is_empty() {
            app_id = sni_get_str(service, "/", "Id");
        }
        let mut app_title = sni_get_str(service, "/StatusNotifierItem", "Title");
        if app_title.is_empty() {
            app_title = sni_get_str(service, "/", "Title");
        }

        if app_id.chars().all(|c| c.is_ascii_digit()) || app_id.is_empty() {
            let win_id = if !app_id.is_empty() {
                app_id.parse::<u64>().unwrap_or(0)
            } else {
                sni_get_str(service, "/StatusNotifierItem", "WindowId").parse::<u64>().unwrap_or(0)
            };
            if win_id > 0 {
                let (x_id, x_title, _) = Self::resolve_xembed_identity(win_id);
                if !x_id.is_empty() {
                    app_id = x_id;
                }
                if app_title.is_empty() && !x_title.is_empty() {
                    app_title = x_title;
                }
            }
        }

        let id_lower = format!("{} {}", app_id, app_title).to_lowercase();
        let mut items = Vec::new();

        let make_item = |id: i32, label: &str, icon: &str, has_submenu: bool, children: Vec<TrayMenuItem>| -> TrayMenuItem {
            TrayMenuItem {
                id,
                label: label.to_string(),
                is_separator: false,
                enabled: true,
                icon: icon.to_string(),
                has_submenu,
                toggle_type: String::new(),
                toggle_state: 0,
                disposition: "normal".to_string(),
                children,
            }
        };

        let make_separator = |id: i32| -> TrayMenuItem {
            TrayMenuItem {
                id,
                label: String::new(),
                is_separator: true,
                enabled: true,
                icon: String::new(),
                has_submenu: false,
                toggle_type: String::new(),
                toggle_state: 0,
                disposition: "normal".to_string(),
                children: Vec::new(),
            }
        };

        if id_lower.contains("cloudmusic") || id_lower.contains("music") || id_lower.contains("spotify") || id_lower.contains("player") {
            // Nested Submenu 1: Playback Controls
            let playback_children = vec![
                make_item(1001, "Play / Pause", "play_arrow", false, Vec::new()),
                make_item(1002, "Next Track", "skip_next", false, Vec::new()),
                make_item(1003, "Previous Track", "skip_previous", false, Vec::new()),
            ];
            items.push(make_item(2000, "Playback Controls", "music_note", true, playback_children));

            // Nested Submenu 2: Window Options
            let window_children = vec![
                make_item(1004, "Show / Minimize Window", "open_in_new", false, Vec::new()),
                make_item(1005, "Open Native Win32 Menu...", "menu", false, Vec::new()),
            ];
            items.push(make_item(2001, "Window Options", "window", true, window_children));

            items.push(make_separator(2002));
            let exit_label = if id_lower.contains("cloudmusic") {
                "Exit NetEase Cloud Music"
            } else {
                "Exit Player"
            };
            items.push(make_item(1006, exit_label, "power_settings_new", false, Vec::new()));
        } else {
            // Generic Wine / XEmbed Application with nested menu
            let window_children = vec![
                make_item(1004, "Restore / Show Window", "open_in_new", false, Vec::new()),
                make_item(1005, "Open Native Win32 Menu...", "menu", false, Vec::new()),
            ];
            items.push(make_item(2001, "Window Options", "window", true, window_children));

            items.push(make_separator(2002));
            let exit_label = if !app_title.is_empty() {
                format!("Exit {}", app_title)
            } else {
                "Exit Application".to_string()
            };
            items.push(make_item(1006, &exit_label, "power_settings_new", false, Vec::new()));
        }

        items
    }

    pub fn click_synthetic_item(service: &str, item_id: i32) -> DynResult<()> {
        match item_id {
            1001 => {
                let _ = crate::infrastructure::x11_input::send_wine_media_action(crate::infrastructure::x11_input::WineMediaAction::PlayPause);
            }
            1002 => {
                let _ = crate::infrastructure::x11_input::send_wine_media_action(crate::infrastructure::x11_input::WineMediaAction::Next);
            }
            1003 => {
                let _ = crate::infrastructure::x11_input::send_wine_media_action(crate::infrastructure::x11_input::WineMediaAction::Previous);
            }
            1004 => {
                let _ = Command::new("qdbus6")
                    .args([service, "/StatusNotifierItem", "org.kde.StatusNotifierItem.Activate", "0", "0"])
                    .output();
            }
            1005 => {
                let (cx, cy) = crate::infrastructure::x11_input::get_cursor_position().unwrap_or((0, 0));
                let (sx, sy) = (cx.to_string(), cy.to_string());
                let _ = Command::new("qdbus6")
                    .args([service, "/StatusNotifierItem", "org.kde.StatusNotifierItem.ContextMenu", &sx, &sy])
                    .output();
            }
            1006 => {
                Self::terminate_wine_app_for_service(service);
            }
            _ => {}
        }
        Ok(())
    }

    pub fn terminate_wine_app_for_service(service: &str) {
        let item_id = sni_get_str(service, "/StatusNotifierItem", "Id");
        let win_id = item_id.parse::<u64>().unwrap_or(0);
        let mut app_name = String::new();
        if win_id > 0 {
            let (x_id, _, _) = Self::resolve_xembed_identity(win_id);
            app_name = x_id;
        }

        if !app_name.is_empty() {
            let _ = Command::new("pkill")
                .args(["-f", &format!("{}.exe", app_name)])
                .output();
        }

        if let Ok(entries) = std::fs::read_dir("/proc") {
            for entry in entries.flatten() {
                let p = entry.path();
                if let Some(fname) = p.file_name().and_then(|f| f.to_str()) {
                    if fname.chars().all(|c| c.is_ascii_digit()) {
                        let cmdline_file = p.join("cmdline");
                        if let Ok(data) = std::fs::read(cmdline_file) {
                            let cmd = String::from_utf8_lossy(&data).replace('\0', " ");
                            let cmd_lower = cmd.to_lowercase();
                            if !app_name.is_empty() && cmd_lower.contains(&app_name.to_lowercase()) {
                                if let Ok(pid) = fname.parse::<i32>() {
                                    unsafe { libc::kill(pid, libc::SIGTERM); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
