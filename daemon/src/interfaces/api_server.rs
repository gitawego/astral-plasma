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
use serde_json::Value;
use std::net::SocketAddr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UnixListener, UnixStream};

pub const DEFAULT_API_PORT: u16 = 8942;
pub const DEFAULT_SOCKET_PATH: &str = "/tmp/astral-plasma.sock";

pub async fn run_api_server(port: u16) -> DynResult<()> {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let tcp_listener = TcpListener::bind(addr).await?;
    println!("[API Server] Listening on http://{}", addr);

    let _ = std::fs::remove_file(DEFAULT_SOCKET_PATH);
    let unix_listener = UnixListener::bind(DEFAULT_SOCKET_PATH)?;
    println!("[API Server] Listening on unix:{}", DEFAULT_SOCKET_PATH);

    loop {
        tokio::select! {
            Ok((stream, _)) = tcp_listener.accept() => {
                tokio::spawn(async move {
                    let _ = handle_tcp_connection(stream).await;
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

async fn handle_tcp_connection(mut stream: TcpStream) -> DynResult<()> {
    let mut buf = [0u8; 4096];
    let n = stream.read(&mut buf).await?;
    if n == 0 {
        return Ok(());
    }

    let req_str = String::from_utf8_lossy(&buf[..n]);
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
