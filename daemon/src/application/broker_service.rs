//! The broker endpoint: one Unix socket per launch, one app, one token.
//!
//! The policy is `domain::broker`; this is the transport. It is split in two so the
//! decisions stay testable without a socket:
//!
//! * [`handle_line`] — one request line in, one response line out, plus the audit entry.
//! * [`serve`] — bind, accept, handshake, pump lines through `handle_line`.

use std::collections::BTreeSet;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use crate::domain::broker::{authorize, AuditEntry, Decision, RateLimiter};
use crate::domain::ports::DynResult;

#[derive(Debug, Clone)]
pub struct BrokerConfig {
    pub app_id: String,
    /// The one-shot token this launch was given.
    pub token: String,
    pub granted: BTreeSet<String>,
    pub audit_path: PathBuf,
}

/// What the host can answer. `None` means "granted, but this shell cannot serve it".
pub type MethodResult = Box<dyn Fn(&str, &Value) -> Option<Value> + Send + Sync>;

/// Handle one request line. Returns the response line; the caller appends the audit entry.
///
/// The handshake is deliberately boring: the first line must carry the same token the
/// launcher put in the app's environment. A wrong token is `denied` and audited — an app
/// that cannot authenticate must not be able to probe the method catalogue quietly.
pub fn handle_line(
    config: &BrokerConfig,
    limiter: &mut RateLimiter,
    now_ms: u64,
    line: &str,
    resolve: &MethodResult,
) -> (String, AuditEntry) {
    let audit = |method: &str, outcome: &'static str, reason: String| AuditEntry {
        at_ms: now_ms,
        app_id: config.app_id.clone(),
        method: method.to_string(),
        outcome,
        reason,
    };

    let request: Value = match serde_json::from_str(line) {
        Ok(value @ Value::Object(_)) => value,
        _ => {
            let response = json!({ "id": Value::Null, "status": "invalid", "reason": "line is not a JSON object" });
            return (
                response.to_string(),
                audit("", "invalid", "line is not a JSON object".to_string()),
            );
        }
    };

    let id = request.get("id").cloned().unwrap_or(Value::Null);
    let method = request.get("method").and_then(Value::as_str).unwrap_or("");

    // Handshake: the token must match this launch's token.
    if let Some(token) = request.get("token").and_then(Value::as_str) {
        if token != config.token {
            let response = json!({ "id": id, "status": "denied", "reason": "token does not match this launch" });
            return (
                response.to_string(),
                audit(method, "denied", "token does not match this launch".to_string()),
            );
        }
    }

    match authorize(method, &config.granted, limiter, now_ms) {
        Decision::Unsupported => {
            let response = json!({ "id": id, "status": "unsupported", "reason": format!("no method '{method}'") });
            (response.to_string(), audit(method, "unsupported", "unknown method".to_string()))
        }
        Decision::RateLimited => {
            let response = json!({ "id": id, "status": "stale", "reason": "too many calls; slow down" });
            (response.to_string(), audit(method, "stale", "rate limited".to_string()))
        }
        Decision::Deny { permission } => {
            let reason = format!("needs '{permission}', which this app has not been granted");
            let response = json!({ "id": id, "status": "denied", "reason": reason });
            (response.to_string(), audit(method, "denied", reason))
        }
        Decision::Allow { .. } => match resolve(method, &request) {
            Some(value) => {
                let response = json!({ "id": id, "status": "applied", "value": value });
                (response.to_string(), audit(method, "applied", String::new()))
            }
            None => {
                let reason = format!("this shell cannot serve '{method}' yet");
                let response = json!({ "id": id, "status": "unavailable", "reason": reason });
                (response.to_string(), audit(method, "unavailable", reason))
            }
        },
    }
}

/// Bind the socket and serve until the app exits (or the listener closes).
pub fn serve(
    socket_path: &Path,
    config: BrokerConfig,
    resolve: MethodResult,
) -> DynResult<std::thread::JoinHandle<()>> {
    let _ = std::fs::remove_file(socket_path);
    let listener = UnixListener::bind(socket_path)?;
    // Only this user may talk to the broker.
    std::fs::set_permissions(socket_path, std::os::unix::fs::PermissionsExt::from_mode(0o600))?;

    let handle = std::thread::spawn(move || {
        let mut limiter = RateLimiter::new(0);
        for stream in listener.incoming().flatten() {
            handle_stream(stream, &config, &mut limiter, &resolve);
        }
    });
    Ok(handle)
}

fn handle_stream(stream: UnixStream, config: &BrokerConfig, limiter: &mut RateLimiter, resolve: &MethodResult) {
    let mut writer = match stream.try_clone() {
        Ok(clone) => clone,
        Err(_) => return,
    };
    let reader = BufReader::new(stream);

    for line in reader.lines().map_while(Result::ok) {
        if line.trim().is_empty() {
            continue;
        }
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_millis() as u64)
            .unwrap_or(0);
        let (response, audit) = handle_line(config, limiter, now, &line, resolve);
        append_audit(&config.audit_path, &audit);
        if writer.write_all(response.as_bytes()).is_err() || writer.write_all(b"\n").is_err() {
            return;
        }
        let _ = writer.flush();
    }
}

fn append_audit(path: &Path, entry: &AuditEntry) {
    use std::io::Write as _;
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(file, "{}", entry.line());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(granted: &[&str]) -> BrokerConfig {
        BrokerConfig {
            app_id: "io.github.fixture".to_string(),
            token: "tok-1".to_string(),
            granted: granted.iter().map(|p| p.to_string()).collect(),
            audit_path: PathBuf::from("/dev/null"),
        }
    }

    fn resolver() -> MethodResult {
        Box::new(|method, _params| match method {
            "session.windows" => Some(serde_json::json!([{ "id": "w1" }])),
            _ => None,
        })
    }

    #[test]
    fn a_granted_call_returns_its_value_and_an_applied_audit() {
        let mut limiter = RateLimiter::new(0);
        let (response, audit) = handle_line(
            &config(&["windows.read"]),
            &mut limiter,
            5,
            r#"{"id":7,"method":"session.windows","token":"tok-1"}"#,
            &resolver(),
        );
        let value: Value = serde_json::from_str(&response).unwrap();
        assert_eq!(value["status"], "applied");
        assert_eq!(value["id"], 7);
        assert_eq!(value["value"][0]["id"], "w1");
        assert_eq!(audit.outcome, "applied");
        assert_eq!(audit.at_ms, 5);
    }

    #[test]
    fn an_undeclared_permission_is_denied_with_the_permission_named() {
        let mut limiter = RateLimiter::new(0);
        let (response, audit) = handle_line(
            &config(&[]),
            &mut limiter,
            5,
            r#"{"id":1,"method":"session.activate","token":"tok-1"}"#,
            &resolver(),
        );
        let value: Value = serde_json::from_str(&response).unwrap();
        assert_eq!(value["status"], "denied");
        assert!(value["reason"].as_str().unwrap().contains("windows.control"));
        assert_eq!(audit.outcome, "denied");
    }

    #[test]
    fn an_unknown_method_is_unsupported_and_audited() {
        let mut limiter = RateLimiter::new(0);
        let (response, audit) = handle_line(
            &config(&["windows.read"]),
            &mut limiter,
            5,
            r#"{"id":2,"method":"shell.exit","token":"tok-1"}"#,
            &resolver(),
        );
        let value: Value = serde_json::from_str(&response).unwrap();
        assert_eq!(value["status"], "unsupported");
        assert_eq!(audit.outcome, "unsupported");
    }

    #[test]
    fn a_wrong_token_is_denied_before_the_method_is_considered() {
        let mut limiter = RateLimiter::new(0);
        let (response, audit) = handle_line(
            &config(&["windows.read"]),
            &mut limiter,
            5,
            r#"{"id":3,"method":"session.windows","token":"stolen"}"#,
            &resolver(),
        );
        let value: Value = serde_json::from_str(&response).unwrap();
        assert_eq!(value["status"], "denied");
        assert_eq!(audit.reason, "token does not match this launch");
    }

    #[test]
    fn a_granted_method_the_shell_cannot_serve_says_unavailable() {
        let mut limiter = RateLimiter::new(0);
        let (response, audit) = handle_line(
            &config(&["notifications.post"]),
            &mut limiter,
            5,
            r#"{"id":4,"method":"notifications.post","token":"tok-1"}"#,
            &resolver(),
        );
        let value: Value = serde_json::from_str(&response).unwrap();
        assert_eq!(value["status"], "unavailable");
        assert_eq!(audit.outcome, "unavailable");
    }

    #[test]
    fn a_non_json_line_is_invalid_and_never_reaches_a_method() {
        let mut limiter = RateLimiter::new(0);
        let (response, audit) = handle_line(&config(&[]), &mut limiter, 5, "not json", &resolver());
        let value: Value = serde_json::from_str(&response).unwrap();
        assert_eq!(value["status"], "invalid");
        assert_eq!(audit.outcome, "invalid");
    }

    #[test]
    fn a_burst_is_rate_limited_over_the_socket_too() {
        let mut limiter = RateLimiter::new(0);
        let cfg = config(&["windows.read"]);
        let resolve = resolver();
        let mut limited = 0;
        for _ in 0..(crate::domain::broker::RATE_BURST + 5) {
            let (response, _) = handle_line(
                &cfg,
                &mut limiter,
                0,
                r#"{"id":1,"method":"session.windows","token":"tok-1"}"#,
                &resolve,
            );
            let value: Value = serde_json::from_str(&response).unwrap();
            if value["status"] == "stale" {
                limited += 1;
            }
        }
        assert_eq!(limited, 5);
    }
}
