use crate::domain::model::WindowMeta;

pub fn resolve_window_meta(
    title: &str,
    cls: &str,
    app: &str,
    krunner_icon: &str,
) -> WindowMeta {
    let cls_lower = cls.to_lowercase();
    let app_lower = app.to_lowercase();
    let t_lower = title.to_lowercase();

    // 1. High-priority exact or class-based matches
    if cls_lower.contains("cloudmusic") || cls_lower.contains("netease") || app_lower.contains("cloudmusic") {
        return WindowMeta {
            app_name: "CloudMusic".to_string(),
            icon_name: "netease-cloud-music".to_string(),
            material_icon: "music_note".to_string(),
            app_id: "cloudmusic".to_string(),
            desktop_file: "lutris:rungame/netease-cloud-music".to_string(),
        };
    }

    if cls_lower.contains("antigravity") || app_lower.contains("antigravity") || cls_lower.contains("opencode") || app_lower.contains("opencode") {
        return WindowMeta {
            app_name: "Antigravity".to_string(),
            icon_name: "antigravity".to_string(),
            material_icon: "smart_toy".to_string(),
            app_id: "antigravity".to_string(),
            desktop_file: "ai.opencode.desktop".to_string(),
        };
    }

    if cls_lower.contains("edge") || cls_lower.contains("msedge") {
        return WindowMeta {
            app_name: "Edge".to_string(),
            icon_name: "microsoft-edge".to_string(),
            material_icon: "language".to_string(),
            app_id: "microsoft-edge".to_string(),
            desktop_file: "microsoft-edge".to_string(),
        };
    }

    if cls_lower.contains("ghostty") || app_lower.contains("ghostty") {
        return WindowMeta {
            app_name: "Terminal".to_string(),
            icon_name: "com.mitchellh.ghostty".to_string(),
            material_icon: "terminal".to_string(),
            app_id: "ghostty".to_string(),
            desktop_file: "com.mitchellh.ghostty".to_string(),
        };
    }

    if cls_lower.contains("quickshell") || app_lower.contains("quickshell") {
        return WindowMeta {
            app_name: "Quickshell".to_string(),
            icon_name: "org.quickshell".to_string(),
            material_icon: "widgets".to_string(),
            app_id: "quickshell".to_string(),
            desktop_file: "org.quickshell".to_string(),
        };
    }

    if cls_lower.contains("code") {
        return WindowMeta {
            app_name: "VS Code".to_string(),
            icon_name: "vscode".to_string(),
            material_icon: "code".to_string(),
            app_id: "code".to_string(),
            desktop_file: "code".to_string(),
        };
    }

    if cls_lower.contains("dolphin") {
        return WindowMeta {
            app_name: "Files".to_string(),
            icon_name: "org.kde.dolphin".to_string(),
            material_icon: "folder".to_string(),
            app_id: "org.kde.dolphin".to_string(),
            desktop_file: "org.kde.dolphin".to_string(),
        };
    }

    if cls_lower.contains("lutris") {
        return WindowMeta {
            app_name: "Lutris".to_string(),
            icon_name: "net.lutris.Lutris".to_string(),
            material_icon: "sports_esports".to_string(),
            app_id: "net.lutris.Lutris".to_string(),
            desktop_file: "net.lutris.Lutris".to_string(),
        };
    }

    if cls_lower.contains("token-tracker") || app_lower.contains("token-tracker") {
        return WindowMeta {
            app_name: "Tracker".to_string(),
            icon_name: "token-tracker".to_string(),
            material_icon: "insights".to_string(),
            app_id: "token-tracker".to_string(),
            desktop_file: "com.gitawego.token-tracker-dashboard".to_string(),
        };
    }

    if cls_lower.contains("haruna") || t_lower.contains("mp4") || t_lower.contains("mkv") {
        return WindowMeta {
            app_name: "Haruna".to_string(),
            icon_name: "org.kde.haruna".to_string(),
            material_icon: "movie".to_string(),
            app_id: "haruna".to_string(),
            desktop_file: "org.kde.haruna".to_string(),
        };
    }

    if cls_lower.contains("gradia") {
        return WindowMeta {
            app_name: "Gradia".to_string(),
            icon_name: "be.alexandervanhee.gradia".to_string(),
            material_icon: "palette".to_string(),
            app_id: "gradia".to_string(),
            desktop_file: "be.alexandervanhee.gradia".to_string(),
        };
    }

    if cls_lower.contains("spectacle") {
        return WindowMeta {
            app_name: "Spectacle".to_string(),
            icon_name: "org.kde.spectacle".to_string(),
            material_icon: "photo_camera".to_string(),
            app_id: "spectacle".to_string(),
            desktop_file: "org.kde.spectacle".to_string(),
        };
    }

    if cls_lower.contains("discord") || cls_lower.contains("vesktop") {
        return WindowMeta {
            app_name: "Discord".to_string(),
            icon_name: "discord".to_string(),
            material_icon: "chat".to_string(),
            app_id: "discord".to_string(),
            desktop_file: "discord".to_string(),
        };
    }

    if cls_lower.contains("steam") {
        return WindowMeta {
            app_name: "Steam".to_string(),
            icon_name: "steam".to_string(),
            material_icon: "sports_esports".to_string(),
            app_id: "steam".to_string(),
            desktop_file: "steam".to_string(),
        };
    }

    if cls_lower.contains("spotify") {
        return WindowMeta {
            app_name: "Spotify".to_string(),
            icon_name: "spotify".to_string(),
            material_icon: "music_note".to_string(),
            app_id: "spotify".to_string(),
            desktop_file: "spotify".to_string(),
        };
    }

    // 2. Wine executable recognition
    if cls_lower.ends_with(".exe") {
        let clean = &cls[..cls.len() - 4];
        let clean_lower = clean.to_lowercase();
        if clean_lower.contains("cloudmusic") || clean_lower.contains("netease") {
            return WindowMeta {
                app_name: "CloudMusic".to_string(),
                icon_name: "netease-cloud-music".to_string(),
                material_icon: "music_note".to_string(),
                app_id: "cloudmusic".to_string(),
                desktop_file: "lutris:rungame/netease-cloud-music".to_string(),
            };
        }
        if clean_lower.contains("wechat") {
            return WindowMeta {
                app_name: "WeChat".to_string(),
                icon_name: "wechat".to_string(),
                material_icon: "chat".to_string(),
                app_id: "wechat".to_string(),
                desktop_file: "wechat".to_string(),
            };
        }
        if clean_lower.contains("qq") {
            return WindowMeta {
                app_name: "QQ".to_string(),
                icon_name: "qq".to_string(),
                material_icon: "chat".to_string(),
                app_id: "qq".to_string(),
                desktop_file: "qq".to_string(),
            };
        }
        let cap = capitalize_truncate(clean, 14);
        let icon = if !krunner_icon.is_empty() { krunner_icon } else { "wine" };
        return WindowMeta {
            app_name: cap,
            icon_name: icon.to_string(),
            material_icon: "window".to_string(),
            app_id: clean_lower.clone(),
            desktop_file: clean_lower,
        };
    }

    // 3. Title-based fallbacks
    if t_lower.contains("antigravity") {
        return WindowMeta {
            app_name: "Antigravity".to_string(),
            icon_name: "antigravity".to_string(),
            material_icon: "smart_toy".to_string(),
            app_id: "antigravity".to_string(),
            desktop_file: "ai.opencode.desktop".to_string(),
        };
    }
    if t_lower.contains("netease") || t_lower.contains("cloudmusic") {
        return WindowMeta {
            app_name: "CloudMusic".to_string(),
            icon_name: "netease-cloud-music".to_string(),
            material_icon: "music_note".to_string(),
            app_id: "cloudmusic".to_string(),
            desktop_file: "lutris:rungame/netease-cloud-music".to_string(),
        };
    }
    if t_lower.contains("visual studio code") {
        return WindowMeta {
            app_name: "VS Code".to_string(),
            icon_name: "vscode".to_string(),
            material_icon: "code".to_string(),
            app_id: "code".to_string(),
            desktop_file: "code".to_string(),
        };
    }
    if t_lower.contains("terminal") || t_lower.contains("konsole") || t_lower.contains("workspace") {
        return WindowMeta {
            app_name: "Terminal".to_string(),
            icon_name: "utilities-terminal".to_string(),
            material_icon: "terminal".to_string(),
            app_id: "terminal".to_string(),
            desktop_file: "utilities-terminal".to_string(),
        };
    }

    // 4. General fallback
    let mut icon_candidate = if !krunner_icon.is_empty() {
        krunner_icon
    } else if !app.is_empty() {
        app
    } else {
        cls
    };
    if icon_candidate == "ai.opencode.desktop" {
        icon_candidate = "antigravity";
    }

    let app_name = if let Some(idx) = title.rfind(" — ") {
        title[idx + 4..].trim().chars().take(14).collect::<String>()
    } else if let Some(idx) = title.rfind(" - ") {
        title[idx + 3..].trim().chars().take(14).collect::<String>()
    } else if !cls.is_empty() {
        let last_part = cls.rsplit('.').next().unwrap_or(cls);
        capitalize_truncate(last_part, 14)
    } else if !title.is_empty() {
        title.chars().take(14).collect::<String>()
    } else {
        "Window".to_string()
    };

    let app_id = if !app.is_empty() {
        app.to_lowercase().replace(' ', "-")
    } else if !cls.is_empty() {
        cls.to_lowercase().replace(' ', "-")
    } else {
        app_name.to_lowercase().replace(' ', "-")
    };

    let desktop_file = if !app.is_empty() {
        app.to_string()
    } else if !cls.is_empty() {
        cls.to_string()
    } else {
        app_id.clone()
    };

    WindowMeta {
        app_name,
        icon_name: icon_candidate.to_string(),
        material_icon: "window".to_string(),
        app_id,
        desktop_file,
    }
}

fn capitalize_truncate(s: &str, max_chars: usize) -> String {
    let mut c = s.chars();
    match c.next() {
        None => String::new(),
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
    }
    .chars()
    .take(max_chars)
    .collect()
}
