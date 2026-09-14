use crate::domain::model::Desktop;
use regex::Regex;

pub fn parse_uptime_content(content: &str) -> String {
    if let Some(first_word) = content.split_whitespace().next() {
        if let Ok(secs) = first_word.parse::<f64>() {
            let total_secs = secs as u64;
            let hours = total_secs / 3600;
            let minutes = (total_secs % 3600) / 60;
            if hours > 0 {
                let h_unit = if hours == 1 { "hour" } else { "hours" };
                let m_unit = if minutes == 1 { "minute" } else { "minutes" };
                return format!("up {} {}, {} {}", hours, h_unit, minutes, m_unit);
            } else {
                let m_unit = if minutes == 1 { "minute" } else { "minutes" };
                return format!("up {} {}", minutes, m_unit);
            }
        }
    }
    "up 0 minutes".to_string()
}

pub fn parse_meminfo_content(content: &str) -> f64 {
    let mut total: f64 = 1.0;
    let mut avail: f64 = 0.0;

    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("MemTotal:") {
            if let Some(val_str) = rest.split_whitespace().next() {
                if let Ok(val) = val_str.parse::<f64>() {
                    total = val;
                }
            }
        } else if let Some(rest) = line.strip_prefix("MemAvailable:") {
            if let Some(val_str) = rest.split_whitespace().next() {
                if let Ok(val) = val_str.parse::<f64>() {
                    avail = val;
                }
            }
        }
    }

    if total > 0.0 {
        ((total - avail) / total).clamp(0.0, 1.0)
    } else {
        0.0
    }
}

pub fn parse_kwin_desktops(output: &str, current_id: &str) -> Vec<Desktop> {
    let re = Regex::new(r#"\(([0-9]+),\s*"([^"]+)",\s*"([^"]+)"\)"#).unwrap();
    let mut desktops = Vec::new();

    for cap in re.captures_iter(output) {
        let index = cap[1].parse::<u32>().unwrap_or(0);
        let id = cap[2].to_string();
        let name = cap[3].to_string();
        let active = id == current_id;

        desktops.push(Desktop {
            index,
            id,
            name,
            active,
        });
    }

    if desktops.is_empty() {
        desktops.push(Desktop {
            index: 0,
            id: "default".to_string(),
            name: "Desktop 1".to_string(),
            active: true,
        });
    }

    desktops
}
