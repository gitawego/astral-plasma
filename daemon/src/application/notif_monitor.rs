use serde_json::json;
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};

pub fn run_notif_monitor() {
    let mut child = match Command::new("dbus-monitor")
        .arg("type='method_call',interface='org.freedesktop.Notifications',member='Notify'")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Failed to run dbus-monitor: {}", e);
            return;
        }
    };

    if let Some(stdout) = child.stdout.take() {
        let reader = BufReader::new(stdout);
        let mut in_notify = false;
        let mut strings = Vec::new();

        for line in reader.lines().flatten() {
            let trimmed = line.trim();
            if trimmed.contains("member=Notify") {
                in_notify = true;
                strings.clear();
                continue;
            }

            if in_notify {
                if let Some(rest) = trimmed.strip_prefix("string \"") {
                    if let Some(val) = rest.strip_suffix('"') {
                        strings.push(val.to_string());
                        if strings.len() == 4 {
                            let payload = json!({
                                "app": strings[0],
                                "icon": if strings[1].is_empty() { "info" } else { &strings[1] },
                                "summary": strings[2],
                                "body": strings[3],
                            });
                            println!("{}", payload);
                            in_notify = false;
                        }
                    }
                } else if trimmed.starts_with("method call") || trimmed.starts_with("signal") {
                    in_notify = false;
                }
            }
        }
    }
}
