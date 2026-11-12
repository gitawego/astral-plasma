use crate::application::get_metrics::GetMetricsUseCase;
use crate::application::launch_app::LaunchAppUseCase;
use crate::application::plasma_service::PlasmaControlUseCase;
use crate::application::systemd_service::SystemdControlUseCase;
use crate::application::window_control::WindowControlUseCase;
use crate::application::workspace_control::WorkspaceControlUseCase;
use crate::domain::ports::DynResult;
use crate::infrastructure::launcher::DesktopLauncherAdapter;
use crate::infrastructure::plasma_adapter::PlasmaAdapter;
use crate::infrastructure::proc_metrics::ProcMetricsAdapter;
use crate::infrastructure::systemd_adapter::SystemdAdapter;
use crate::interfaces::http::{self, HttpRequest};
use crate::interfaces::mcp_server::HttpMcp;
use serde_json::Value;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UnixListener, UnixStream};
use tokio::time::{timeout, Duration};

pub const DEFAULT_API_PORT: u16 = 8942;
pub const DEFAULT_SOCKET_PATH: &str = "/tmp/astral-plasma.sock";

/// The API/MCP port: `ASTRAL_API_PORT` when it is a valid non-zero port, else the default.
///
/// A client's MCP URL is fixed configuration, so the server never silently picks another port.
/// The override exists so a machine can move the endpoint deliberately and configure clients to
/// the same URL.
pub fn api_port() -> u16 {
    api_port_from(std::env::var("ASTRAL_API_PORT").ok().as_deref())
}

pub fn api_port_from(value: Option<&str>) -> u16 {
    value
        .and_then(|value| value.trim().parse::<u16>().ok())
        .filter(|port| *port != 0)
        .unwrap_or(DEFAULT_API_PORT)
}

pub async fn run_api_server(port: u16) -> DynResult<()> {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let tcp_listener = match TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(error) if error.kind() == std::io::ErrorKind::AddrInUse => {
            return Err(format!(
                "port {port} is already in use; stop the other process, pass a different port, or set ASTRAL_API_PORT to a free port (MCP clients must use the same URL)"
            )
            .into())
        }
        Err(error) => return Err(error.into()),
    };
    let bound = tcp_listener.local_addr().unwrap_or(addr);
    println!("[API Server] Listening on http://{}", bound);
    println!("[API Server] MCP Streamable HTTP: http://{}/mcp", bound);

    let _ = std::fs::remove_file(DEFAULT_SOCKET_PATH);
    let unix_listener = UnixListener::bind(DEFAULT_SOCKET_PATH)?;
    println!("[API Server] Listening on unix:{}", DEFAULT_SOCKET_PATH);

    let mcp = Arc::new(HttpMcp::from_env());
    loop {
        tokio::select! {
            Ok((stream, _)) = tcp_listener.accept() => {
                let mcp = mcp.clone();
                tokio::spawn(async move {
                    let _ = handle_tcp_connection(stream, mcp).await;
                });
            }
            Ok((stream, _)) = unix_listener.accept() => {
                tokio::spawn(async move {
                    let _ = handle_unix_connection(stream).await;
                });
            }
            _ = tokio::signal::ctrl_c() => {
                println!("[API Server] Shutting down.");
                let _ = std::fs::remove_file(DEFAULT_SOCKET_PATH);
                break;
            }
        }
    }

    Ok(())
}

/// Start the API/MCP server only when this port is not already served by this daemon.
///
/// The shell can be launched two ways: `astral-plasma run` starts the server itself, while a
/// direct `quickshell -p …` only starts the `watch` daemon. Both paths call this, so the MCP
/// endpoint exists either way and a second process does not fight for the port.
pub async fn run_api_server_if_needed(port: u16) -> DynResult<()> {
    if tcp_port_open(port).await {
        if api_status_is_ours(port).await {
            println!("[API Server] Already running on http://127.0.0.1:{port}");
            return Ok(());
        }
        return Err(format!(
            "port {port} is already in use by another process; stop it or set ASTRAL_API_PORT (MCP clients must use the same URL)"
        )
        .into());
    }
    run_api_server(port).await
}

async fn tcp_port_open(port: u16) -> bool {
    timeout(
        Duration::from_millis(400),
        TcpStream::connect(("127.0.0.1", port)),
    )
    .await
    .map(|result| result.is_ok())
    .unwrap_or(false)
}

async fn api_status_is_ours(port: u16) -> bool {
    let Ok(Ok(mut stream)) = timeout(
        Duration::from_millis(600),
        TcpStream::connect(("127.0.0.1", port)),
    )
    .await
    else {
        return false;
    };
    let request = format!(
        "GET /api/status HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n"
    );
    if stream.write_all(request.as_bytes()).await.is_err() {
        return false;
    }
    let mut response = Vec::new();
    let _ = timeout(Duration::from_secs(1), stream.read_to_end(&mut response)).await;
    let text = String::from_utf8_lossy(&response);
    text.starts_with("HTTP/1.1 200") && text.contains("\"name\":\"astral-plasma\"")
}

async fn handle_tcp_connection(mut stream: TcpStream, mcp: Arc<HttpMcp>) -> DynResult<()> {
    let req_str = http::read_request(&mut stream).await?;
    if req_str.is_empty() {
        return Ok(());
    }

    // `/mcp` is the Streamable HTTP endpoint; every other path keeps the REST behaviour.
    if let Ok(request) = HttpRequest::parse(&req_str) {
        if request.path == "/mcp" {
            let response = mcp.handle(request).await;
            return http::write_response(&mut stream, &response).await;
        }
    }

    let (status_code, body) = dispatch_http_request(&req_str).await;

    let response = format!(
        "HTTP/1.1 {} OK\r\n\
         Content-Type: application/json; charset=utf-8\r\n\
         Content-Length: {}\r\n\
         Access-Control-Allow-Origin: *\r\n\
         Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n\
         Access-Control-Allow-Headers: Content-Type\r\n\
         Connection: close\r\n\r\n{}",
        status_code,
        body.len(),
        body
    );

    stream.write_all(response.as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

async fn handle_unix_connection(mut stream: UnixStream) -> DynResult<()> {
    let mut buf = [0u8; 4096];
    let n = stream.read(&mut buf).await?;
    if n == 0 {
        return Ok(());
    }

    let req_str = String::from_utf8_lossy(&buf[..n]);
    let (_, body) = dispatch_http_request(&req_str).await;

    stream.write_all(body.as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

pub async fn dispatch_http_request(req: &str) -> (u16, String) {
    let mut lines = req.lines();
    let first_line = lines.next().unwrap_or("");
    let mut parts = first_line.split_whitespace();
    let method = parts.next().unwrap_or("GET");
    let full_path = parts.next().unwrap_or("/");

    let path = full_path.split('?').next().unwrap_or("/");

    if method == "OPTIONS" {
        return (200, "{}".to_string());
    }

    // Extract body if present
    let body = if let Some(idx) = req.find("\r\n\r\n") {
        &req[idx + 4..]
    } else if let Some(idx) = req.find("\n\n") {
        &req[idx + 2..]
    } else {
        ""
    };

    match (method, path) {
        ("GET", "/api/status") | ("GET", "/status") => {
            (200, format!(r#"{{"ok":true,"name":"astral-plasma","version":"{}"}}"#, env!("CARGO_PKG_VERSION")))
        }

        ("GET", "/api/metrics") | ("GET", "/metrics") => {
            let use_case = GetMetricsUseCase::new(ProcMetricsAdapter::new());
            match use_case.execute_json() {
                Ok(json) => (200, json),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("GET", "/api/workspaces") => {
            let use_case = WorkspaceControlUseCase::new(crate::infrastructure::desktop_factory::create_workspace_port());
            match use_case.query_json() {
                Ok(json) => (200, json),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("POST", "/api/workspaces/switch") => {
            let parsed: Value = serde_json::from_str(body).unwrap_or(Value::Null);
            let id = parsed.get("id").and_then(|v| v.as_str()).unwrap_or("");
            let use_case = WorkspaceControlUseCase::new(crate::infrastructure::desktop_factory::create_workspace_port());
            match use_case.switch(id) {
                Ok(_) => (200, r#"{"success":true}"#.to_string()),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("GET", "/api/plasma/status") => {
            let use_case = PlasmaControlUseCase::new(PlasmaAdapter::new());
            match use_case.get_status() {
                Ok(st) => (200, serde_json::to_string(&st).unwrap_or_else(|_| "{}".to_string())),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("POST", "/api/plasma/disable") => {
            let parsed: Value = serde_json::from_str(body).unwrap_or(Value::Null);
            let target = parsed.get("target").and_then(|v| v.as_str()).unwrap_or("all");
            let pid = parsed.get("pid").and_then(|v| v.as_u64()).map(|p| p as u32);
            let use_case = PlasmaControlUseCase::new(PlasmaAdapter::new());
            match use_case.backup_and_disable(target, pid) {
                Ok(count) => (200, format!(r#"{{"success":true,"removed":{}}}"#, count)),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("POST", "/api/plasma/restore") => {
            let use_case = PlasmaControlUseCase::new(PlasmaAdapter::new());
            match use_case.restore() {
                Ok(restored) => (200, format!(r#"{{"success":true,"restored":{}}}"#, restored)),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("GET", "/api/systemd/status") => {
            let use_case = SystemdControlUseCase::new(SystemdAdapter::new());
            match use_case.get_status() {
                Ok(st) => (200, serde_json::to_string(&st).unwrap_or_else(|_| "{}".to_string())),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("POST", "/api/systemd/install") => {
            let use_case = SystemdControlUseCase::new(SystemdAdapter::new());
            match use_case.install() {
                Ok(st) => (200, serde_json::to_string(&st).unwrap_or_else(|_| "{}".to_string())),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("POST", "/api/systemd/remove") => {
            let use_case = SystemdControlUseCase::new(SystemdAdapter::new());
            match use_case.remove() {
                Ok(st) => (200, serde_json::to_string(&st).unwrap_or_else(|_| "{}".to_string())),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("POST", "/api/window/activate") => {
            let parsed: Value = serde_json::from_str(body).unwrap_or(Value::Null);
            let wid = parsed.get("id").and_then(|v| v.as_str()).unwrap_or("");
            let use_case = WindowControlUseCase::new(crate::infrastructure::desktop_factory::create_window_manager_port());
            match use_case.activate(wid) {
                Ok(_) => (200, r#"{"success":true}"#.to_string()),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("POST", "/api/window/close") => {
            let parsed: Value = serde_json::from_str(body).unwrap_or(Value::Null);
            let wid = parsed.get("id").and_then(|v| v.as_str()).unwrap_or("");
            let use_case = WindowControlUseCase::new(crate::infrastructure::desktop_factory::create_window_manager_port());
            match use_case.close(wid) {
                Ok(_) => (200, r#"{"success":true}"#.to_string()),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        ("POST", "/api/app/launch") => {
            let parsed: Value = serde_json::from_str(body).unwrap_or(Value::Null);
            let target = parsed.get("target").and_then(|v| v.as_str()).unwrap_or("");
            let use_case = LaunchAppUseCase::new(DesktopLauncherAdapter::new());
            match use_case.execute(target) {
                Ok(_) => (200, r#"{"success":true}"#.to_string()),
                Err(e) => (500, format!(r#"{{"error":"{}"}}"#, e)),
            }
        }

        _ => (404, r#"{"error":"Not Found"}"#.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_api_port_override_is_validated() {
        assert_eq!(api_port_from(None), DEFAULT_API_PORT);
        assert_eq!(api_port_from(Some("9000")), 9000);
        assert_eq!(api_port_from(Some(" 9001 ")), 9001);
        assert_eq!(api_port_from(Some("not-a-port")), DEFAULT_API_PORT);
        assert_eq!(api_port_from(Some("0")), DEFAULT_API_PORT, "0 would be an unknown ephemeral port");
        assert_eq!(api_port_from(Some("70000")), DEFAULT_API_PORT);
    }
}
