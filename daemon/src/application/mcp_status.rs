//! Is the MCP endpoint up, and is it registered with each agent?
//!
//! Two different questions, answered from two different truths:
//!
//! * the server is probed over the same Streamable HTTP endpoint a client uses;
//! * each agent is read from the MCP configuration it actually loads (never from a guess about
//!   what the agent might support).
//!
//! The result is data, so the CLI and the Skills page render the same report.

use std::env;
use std::fs;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Serialize;
use serde_json::Value;

pub const SERVER_NAME: &str = "astral-skills";

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct McpServerStatus {
    pub url: String,
    /// A TCP connection reached something on the port.
    pub reachable: bool,
    /// `up`, `down`, or `wrong-service`.
    pub state: String,
    pub protocol: Option<String>,
    pub server_name: Option<String>,
    pub tools: Vec<String>,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct AgentMcpStatus {
    pub id: String,
    pub label: String,
    /// The agent (or at least its config directory) is present on this machine.
    pub installed: bool,
    /// The agent's loaded config has an `astral-skills` server that points at this endpoint.
    pub configured: bool,
    pub transport: String,
    pub url: String,
    /// The key inside the agent's MCP map (usually `astral-skills`).
    pub entry: String,
    pub source: String,
    /// The real file behind `source`; not serialized, used by uninstall.
    #[serde(skip)]
    pub path: PathBuf,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct McpStatusReport {
    pub server: McpServerStatus,
    pub agents: Vec<AgentMcpStatus>,
    #[serde(rename = "configuredCount")]
    pub configured_count: usize,
    #[serde(rename = "installedCount")]
    pub installed_count: usize,
    #[serde(rename = "allInstalledConfigured")]
    pub all_installed_configured: bool,
    #[serde(rename = "allSupportedConfigured")]
    pub all_supported_configured: bool,
    pub summary: String,
}

impl McpStatusReport {
    pub fn render(&self) -> String {
        let mut out = String::new();
        let mark = match self.server.state.as_str() {
            "up" => "●",
            "down" => "○",
            _ => "!",
        };
        out.push_str(&format!(
            "MCP server: {mark} {} — {}\n",
            self.server.state.replace('-', " "),
            self.server.url
        ));
        out.push_str(&format!("  {}\n", self.server.detail));
        out.push_str("Agents:\n");
        for agent in &self.agents {
            let mark = if agent.configured {
                "●"
            } else if agent.installed {
                "○"
            } else {
                "-"
            };
            out.push_str(&format!(
                "  {mark} {:<18} {}\n",
                agent.label, agent.detail
            ));
        }
        out.push_str(&format!("Summary: {}\n", self.summary));
        out.push_str(&format!(
            "All supported configured: {}\n",
            if self.all_supported_configured { "yes" } else { "no" }
        ));
        out
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct McpRemoval {
    pub agent: String,
    pub label: String,
    pub source: String,
    pub entry: String,
    pub removed: bool,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct McpUninstallReport {
    pub removed: Vec<McpRemoval>,
    pub skipped: Vec<McpRemoval>,
}

impl McpUninstallReport {
    pub fn render(&self) -> String {
        let mut out = String::new();
        for removal in &self.removed {
            out.push_str(&format!(
                "Removed {} from {} ({})\n",
                removal.entry, removal.label, removal.source
            ));
        }
        for removal in &self.skipped {
            out.push_str(&format!("Skipped {}: {}\n", removal.label, removal.detail));
        }
        if self.removed.is_empty() && self.skipped.is_empty() {
            out.push_str("Nothing to remove.\n");
        }
        out
    }
}

/// Probe the server and read every agent's MCP configuration.
pub fn inspect(home: &Path, cwd: &Path, port: u16) -> McpStatusReport {
    let server = probe_server(port);
    let agents = vec![
        claude_agent(home, cwd, port),
        opencode_agent(home, cwd, port),
        pi_agent(home, cwd, port),
        codex_agent(home, port),
        cursor_agent(home, cwd, port),
        gemini_agent(home, port),
        copilot_agent(home, cwd, port),
    ];
    let configured_count = agents.iter().filter(|agent| agent.configured).count();
    let installed_count = agents.iter().filter(|agent| agent.installed).count();
    let all_installed_configured = installed_count > 0
        && agents
            .iter()
            .filter(|agent| agent.installed)
            .all(|agent| agent.configured);
    let all_supported_configured = agents.iter().all(|agent| agent.configured);
    let summary = if server.state == "up" {
        format!(
            "server up · {configured_count} of {installed_count} installed agents configured"
        )
    } else if installed_count == 0 {
        "no supported agent detected".to_string()
    } else {
        format!(
            "server {} · {configured_count} of {installed_count} installed agents configured",
            server.state.replace('-', " ")
        )
    };
    McpStatusReport {
        server,
        agents,
        configured_count,
        installed_count,
        all_installed_configured,
        all_supported_configured,
        summary,
    }
}

/// Ask the endpoint the same `server/discover` question a modern client asks, then fall back to
/// the legacy `initialize` handshake for an older server.
pub fn probe_server(port: u16) -> McpServerStatus {
    let url = format!("http://127.0.0.1:{port}/mcp");
    let discover = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "server/discover",
        "params": { "_meta": {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": {}
        }}
    });
    let modern_headers = [
        ("MCP-Protocol-Version", "2026-07-28"),
        ("Mcp-Method", "server/discover"),
    ];
    let modern = post_json(port, &discover.to_string(), &modern_headers);
    let mut modern_error = String::new();
    if let Ok((status, body)) = &modern {
        if *status == 200 {
            if let Some(result) = response_result(body) {
                if let Some((name, protocol)) = astral_identity(&result) {
                    let tools = probe_tools(port, true);
                    return up(url, protocol, name, tools);
                }
            }
        }
        modern_error = format!("HTTP {status}");
    } else if let Err(error) = &modern {
        return down(url, error.clone());
    }

    let initialize = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": { "name": "astral-plasma-status", "version": env!("CARGO_PKG_VERSION") }
        }
    });
    let legacy_headers = [("MCP-Protocol-Version", "2025-11-25")];
    match post_json(port, &initialize.to_string(), &legacy_headers) {
        Ok((status, body)) if status == 200 => {
            if let Some(result) = response_result(&body) {
                if let Some((name, protocol)) = astral_identity(&result) {
                    let tools = probe_tools(port, false);
                    return up(url, protocol, name, tools);
                }
            }
            wrong_service(url, format!("port {port} answered, but not as {SERVER_NAME}"))
        }
        Ok((status, _)) => wrong_service(url, format!("port {port} returned HTTP {status}")),
        Err(error) => {
            if modern_error.is_empty() {
                down(url, error)
            } else {
                down(url, format!("{modern_error}; {error}"))
            }
        }
    }
}

fn up(
    url: String,
    protocol: Option<String>,
    server_name: String,
    tools: Vec<String>,
) -> McpServerStatus {
    let detail = format!(
        "{} tools{}",
        tools.len(),
        protocol
            .as_ref()
            .map(|version| format!(" · {version}"))
            .unwrap_or_default()
    );
    McpServerStatus {
        url,
        reachable: true,
        state: "up".to_string(),
        protocol,
        server_name: Some(server_name),
        tools,
        detail,
    }
}

fn down(url: String, detail: String) -> McpServerStatus {
    McpServerStatus {
        url,
        reachable: false,
        state: "down".to_string(),
        protocol: None,
        server_name: None,
        tools: Vec::new(),
        detail: format!(
            "{detail}; start the shell or `astral-plasma skills mcp --http`"
        ),
    }
}

fn wrong_service(url: String, detail: String) -> McpServerStatus {
    McpServerStatus {
        url,
        reachable: true,
        state: "wrong-service".to_string(),
        protocol: None,
        server_name: None,
        tools: Vec::new(),
        detail,
    }
}

fn probe_tools(port: u16, modern: bool) -> Vec<String> {
    let request = if modern {
        serde_json::json!({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": { "_meta": {
                "io.modelcontextprotocol/protocolVersion": "2026-07-28",
                "io.modelcontextprotocol/clientCapabilities": {}
            }}
        })
    } else {
        serde_json::json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" })
    };
    let headers = if modern {
        vec![
            ("MCP-Protocol-Version", "2026-07-28"),
            ("Mcp-Method", "tools/list"),
        ]
    } else {
        vec![("MCP-Protocol-Version", "2025-11-25")]
    };
    let Ok((status, body)) = post_json(port, &request.to_string(), &headers) else {
        return Vec::new();
    };
    if status != 200 {
        return Vec::new();
    }
    response_result(&body)
        .and_then(|result| {
            result
                .get("tools")
                .and_then(Value::as_array)
                .map(|tools| {
                    tools
                        .iter()
                        .filter_map(|tool| tool.get("name").and_then(Value::as_str))
                        .map(str::to_string)
                        .collect()
                })
        })
        .unwrap_or_default()
}

fn post_json(
    port: u16,
    body: &str,
    headers: &[(&str, &str)],
) -> Result<(u16, String), String> {
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    let mut stream = TcpStream::connect_timeout(&address, Duration::from_millis(800))
        .map_err(|error| format!("cannot connect to 127.0.0.1:{port}: {error}"))?;
    let _ = stream.set_read_timeout(Some(Duration::from_secs(3)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(3)));
    let mut request = format!(
        "POST /mcp HTTP/1.1\r\n\
         Host: 127.0.0.1:{port}\r\n\
         Content-Type: application/json\r\n\
         Accept: application/json, text/event-stream\r\n\
         Connection: close\r\n\
         Content-Length: {}\r\n",
        body.len()
    );
    for (name, value) in headers {
        request.push_str(name);
        request.push_str(": ");
        request.push_str(value);
        request.push_str("\r\n");
    }
    request.push_str("\r\n");
    request.push_str(body);
    stream
        .write_all(request.as_bytes())
        .map_err(|error| format!("cannot send the MCP probe: {error}"))?;
    let mut response = Vec::new();
    if let Err(error) = stream.read_to_end(&mut response) {
        if response.is_empty() {
            return Err(format!("cannot read the MCP probe: {error}"));
        }
    }
    let text = String::from_utf8_lossy(&response);
    let (head, body) = text
        .split_once("\r\n\r\n")
        .or_else(|| text.split_once("\n\n"))
        .ok_or("the MCP endpoint returned no HTTP headers")?;
    let status = head
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|code| code.parse::<u16>().ok())
        .ok_or("the MCP endpoint returned no HTTP status")?;
    Ok((status, body.to_string()))
}

fn response_result(body: &str) -> Option<Value> {
    let trimmed = body.trim();
    let json = if trimmed.starts_with("data:") {
        trimmed
            .lines()
            .filter_map(|line| line.strip_prefix("data:"))
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .last()?
    } else {
        trimmed
    };
    serde_json::from_str::<Value>(json).ok()?.get("result").cloned()
}

fn astral_identity(result: &Value) -> Option<(String, Option<String>)> {
    let name = result
        .get("_meta")
        .and_then(|meta| meta.get("io.modelcontextprotocol/serverInfo"))
        .and_then(|info| info.get("name"))
        .and_then(Value::as_str)
        .or_else(|| {
            result
                .get("serverInfo")
                .and_then(|info| info.get("name"))
                .and_then(Value::as_str)
        })?;
    if name != SERVER_NAME {
        return None;
    }
    let protocol = result
        .get("supportedVersions")
        .and_then(Value::as_array)
        .and_then(|versions| versions.first())
        .and_then(Value::as_str)
        .or_else(|| result.get("protocolVersion").and_then(Value::as_str))
        .map(str::to_string);
    Some((name.to_string(), protocol))
}

fn claude_agent(home: &Path, cwd: &Path, port: u16) -> AgentMcpStatus {
    let paths = vec![home.join(".claude.json"), cwd.join(".mcp.json")];
    let mut status = agent_base("claude-code", "Claude Code", "claude", &paths, home);
    for path in &paths {
        let Some(value) = read_json(path) else {
            continue;
        };
        let mut maps = Vec::new();
        if let Some(map) = value.get("mcpServers") {
            maps.push(map);
        }
        if let Some(map) = value
            .get("projects")
            .and_then(|projects| projects.get(cwd.to_string_lossy().as_ref()))
            .and_then(|project| project.get("mcpServers"))
        {
            maps.push(map);
        }
        if let Some(found) = find_in_maps(&maps, port) {
            status.configured = true;
            status.entry = found.0;
            status.transport = found.1;
            status.url = found.2;
            status.source = display_path(home, path);
            status.path = path.clone();
            status.detail = format!("{} · {}", status.transport, status.source);
            return status;
        }
    }
    finish_agent(status, home)
}

fn opencode_agent(home: &Path, cwd: &Path, port: u16) -> AgentMcpStatus {
    let paths = vec![
        home.join(".config/opencode/opencode.json"),
        home.join(".config/opencode/opencode.jsonc"),
        cwd.join("opencode.json"),
        cwd.join("opencode.jsonc"),
    ];
    json_agent("opencode", "OpenCode", "opencode", &paths, "mcp", home, port)
}

fn pi_agent(home: &Path, cwd: &Path, port: u16) -> AgentMcpStatus {
    let paths = vec![home.join(".pi/agent/mcp.json"), cwd.join(".pi/mcp.json")];
    json_agent("pi", "Pi", "pi", &paths, "mcpServers", home, port)
}

fn cursor_agent(home: &Path, cwd: &Path, port: u16) -> AgentMcpStatus {
    let paths = vec![home.join(".cursor/mcp.json"), cwd.join(".cursor/mcp.json")];
    json_agent("cursor", "Cursor", "cursor", &paths, "mcpServers", home, port)
}

fn gemini_agent(home: &Path, port: u16) -> AgentMcpStatus {
    let paths = vec![home.join(".gemini/settings.json")];
    json_agent(
        "gemini-cli",
        "Gemini CLI",
        "gemini",
        &paths,
        "mcpServers",
        home,
        port,
    )
}

fn copilot_agent(home: &Path, cwd: &Path, port: u16) -> AgentMcpStatus {
    let paths = vec![
        home.join(".copilot/mcp-config.json"),
        cwd.join(".github/mcp.json"),
        cwd.join(".mcp.json"),
    ];
    json_agent(
        "github-copilot",
        "GitHub Copilot",
        "copilot",
        &paths,
        "mcpServers",
        home,
        port,
    )
}

fn json_agent(
    id: &str,
    label: &str,
    binary: &str,
    paths: &[PathBuf],
    container: &str,
    home: &Path,
    port: u16,
) -> AgentMcpStatus {
    let mut status = agent_base(id, label, binary, paths, home);
    for path in paths {
        let Some(value) = read_json(path) else {
            continue;
        };
        let map = value.get(container);
        if let Some(found) = map.and_then(|map| find_in_map(map, port)) {
            status.configured = true;
            status.entry = found.0;
            status.transport = found.1;
            status.url = found.2;
            status.source = display_path(home, path);
            status.path = path.clone();
            status.detail = format!("{} · {}", status.transport, status.source);
            return status;
        }
    }
    finish_agent(status, home)
}

fn codex_agent(home: &Path, port: u16) -> AgentMcpStatus {
    let path = home.join(".codex/config.toml");
    let mut status = agent_base(
        "codex",
        "Codex",
        "codex",
        std::slice::from_ref(&path),
        home,
    );
    if let Ok(text) = fs::read_to_string(&path) {
        if let Some(found) = codex_find(&text, port) {
            status.configured = true;
            status.entry = found.0;
            status.transport = found.1;
            status.url = found.2;
            status.source = display_path(home, &path);
            status.path = path.clone();
            status.detail = format!("{} · {}", status.transport, status.source);
            return status;
        }
    }
    finish_agent(status, home)
}

fn agent_base(
    id: &str,
    label: &str,
    binary: &str,
    paths: &[PathBuf],
    home: &Path,
) -> AgentMcpStatus {
    let config = paths.iter().find(|path| path.is_file());
    let directory_present = paths
        .iter()
        .any(|path| path.parent().map(|parent| parent.is_dir()).unwrap_or(false));
    let installed = config.is_some() || directory_present || command_exists(binary);
    let source = config
        .map(|path| display_path(home, path))
        .unwrap_or_default();
    AgentMcpStatus {
        id: id.to_string(),
        label: label.to_string(),
        installed,
        configured: false,
        transport: String::new(),
        url: String::new(),
        entry: String::new(),
        source,
        path: config.cloned().unwrap_or_default(),
        detail: String::new(),
    }
}

fn finish_agent(mut status: AgentMcpStatus, _home: &Path) -> AgentMcpStatus {
    status.detail = if status.configured {
        format!("{} · {}", status.transport, status.source)
    } else if !status.installed {
        "not installed".to_string()
    } else if status.source.is_empty() {
        "config not found".to_string()
    } else {
        "not configured".to_string()
    };
    status
}

fn find_in_maps(maps: &[&Value], port: u16) -> Option<(String, String, String)> {
    maps.iter()
        .find_map(|map| find_in_map(map, port))
}

fn find_in_map(map: &Value, port: u16) -> Option<(String, String, String)> {
    let object = map.as_object()?;
    object.iter().find_map(|(entry, server)| {
        server_match(server, port).map(|(transport, url)| (entry.clone(), transport, url))
    })
}

fn server_match(server: &Value, port: u16) -> Option<(String, String)> {
    if let Some(url) = server.get("url").and_then(Value::as_str) {
        if is_ours_url(url, port) {
            return Some(("http".to_string(), url.to_string()));
        }
    }
    let mut parts = Vec::new();
    if let Some(command) = server.get("command") {
        if let Some(command) = command.as_str() {
            parts.push(command.to_string());
        } else if let Some(command) = command.as_array() {
            parts.extend(
                command
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_string),
            );
        }
    }
    if let Some(args) = server.get("args").and_then(Value::as_array) {
        parts.extend(args.iter().filter_map(Value::as_str).map(str::to_string));
    }
    if command_is_ours(&parts) {
        return Some(("stdio".to_string(), parts.join(" ")));
    }
    None
}

fn is_ours_url(url: &str, port: u16) -> bool {
    let url = url.trim().trim_end_matches('/');
    ["127.0.0.1", "localhost", "[::1]"]
        .iter()
        .any(|host| {
            url.eq_ignore_ascii_case(&format!("http://{host}:{port}/mcp"))
                || url.eq_ignore_ascii_case(&format!("https://{host}:{port}/mcp"))
        })
}

fn command_is_ours(parts: &[String]) -> bool {
    let joined = parts.join(" ").to_ascii_lowercase();
    joined.contains("astral-plasma") && joined.contains("skills") && joined.contains("mcp")
}

fn codex_find(text: &str, port: u16) -> Option<(String, String, String)> {
    let mut section = String::new();
    let mut in_servers = false;
    let mut url: Option<String> = None;
    let mut command: Option<String> = None;
    let mut args: Vec<String> = Vec::new();
    let check = |section: &str,
                     url: &mut Option<String>,
                     command: &mut Option<String>,
                     args: &mut Vec<String>|
     -> Option<(String, String, String)> {
        let entry = section
            .strip_prefix("mcp_servers.")
            .unwrap_or(section)
            .trim_matches('"')
            .to_string();
        if entry.is_empty() {
            return None;
        }
        if let Some(url) = url.take() {
            if is_ours_url(&url, port) {
                return Some((entry, "http".to_string(), url));
            }
        }
        if let Some(command) = command.take() {
            let mut parts = vec![command];
            parts.append(args);
            if command_is_ours(&parts) {
                return Some((entry, "stdio".to_string(), parts.join(" ")));
            }
        }
        args.clear();
        None
    };
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            if in_servers {
                if let Some(found) = check(&section, &mut url, &mut command, &mut args) {
                    return Some(found);
                }
            }
            section = trimmed.trim_matches(['[', ']']).to_string();
            in_servers = section.starts_with("mcp_servers.");
            url = None;
            command = None;
            args.clear();
            continue;
        }
        if !in_servers {
            continue;
        }
        if let Some(value) = toml_string(trimmed, "url") {
            url = Some(value);
        }
        if let Some(value) = toml_string(trimmed, "command") {
            command = Some(value);
        }
        if trimmed.starts_with("args") {
            args = toml_strings(trimmed);
        }
    }
    if in_servers {
        check(&section, &mut url, &mut command, &mut args)
    } else {
        None
    }
}

fn toml_string(line: &str, key: &str) -> Option<String> {
    let rest = line.strip_prefix(key)?.trim_start();
    let rest = rest.strip_prefix('=')?.trim();
    rest.strip_prefix('"')?.strip_suffix('"').map(str::to_string)
}

fn toml_strings(line: &str) -> Vec<String> {
    let Some((_, rest)) = line.split_once('=') else {
        return Vec::new();
    };
    rest.trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .split(',')
        .filter_map(|part| {
            let part = part.trim().trim_matches('"').trim();
            if part.is_empty() {
                None
            } else {
                Some(part.to_string())
            }
        })
        .collect()
}

fn read_json(path: &Path) -> Option<Value> {
    let text = fs::read_to_string(path).ok()?;
    let text = if path.extension().and_then(|extension| extension.to_str()) == Some("jsonc") {
        strip_jsonc(&text)
    } else {
        text
    };
    serde_json::from_str(&text).ok()
}

fn strip_jsonc(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    let mut in_string = false;
    let mut escaped = false;
    while let Some(character) = chars.next() {
        if in_string {
            out.push(character);
            if escaped {
                escaped = false;
            } else if character == '\\' {
                escaped = true;
            } else if character == '"' {
                in_string = false;
            }
            continue;
        }
        if character == '"' {
            in_string = true;
            out.push(character);
            continue;
        }
        if character == '/' {
            match chars.peek() {
                Some('/') => {
                    chars.next();
                    for next in chars.by_ref() {
                        if next == '\n' {
                            out.push('\n');
                            break;
                        }
                    }
                }
                Some('*') => {
                    chars.next();
                    let mut previous = '\0';
                    for next in chars.by_ref() {
                        if previous == '*' && next == '/' {
                            break;
                        }
                        previous = next;
                    }
                }
                _ => out.push(character),
            }
            continue;
        }
        out.push(character);
    }
    out
}

fn display_path(home: &Path, path: &Path) -> String {
    match path.strip_prefix(home) {
        Ok(rest) if rest.as_os_str().is_empty() => "~".to_string(),
        Ok(rest) => format!("~/{}", rest.display()),
        Err(_) => path.display().to_string(),
    }
}

fn command_exists(binary: &str) -> bool {
    env::var_os("PATH")
        .map(|paths| {
            env::split_paths(&paths).any(|directory| directory.join(binary).is_file())
        })
        .unwrap_or(false)
}

/// Remove this server from the selected agent configs. `agent` is one id or `all`.
pub fn uninstall(
    home: &Path,
    cwd: &Path,
    port: u16,
    agent_filter: Option<&str>,
) -> McpUninstallReport {
    let report = inspect(home, cwd, port);
    let filter = agent_filter.unwrap_or("all");
    let mut removed = Vec::new();
    let mut skipped = Vec::new();
    let mut matched = false;
    for agent in report.agents {
        if filter != "all" && filter != agent.id {
            continue;
        }
        matched = true;
        if !agent.configured {
            skipped.push(removal(&agent, false, "not configured".to_string()));
            continue;
        }
        match remove_agent_config(&agent, cwd) {
            Ok(true) => removed.push(removal(
                &agent,
                true,
                format!("removed{}", comments_note(&agent.source)),
            )),
            Ok(false) => skipped.push(removal(
                &agent,
                false,
                format!("{} is no longer in {}", agent.entry, agent.source),
            )),
            Err(error) => skipped.push(removal(&agent, false, error)),
        }
    }
    if !matched {
        skipped.push(McpRemoval {
            agent: filter.to_string(),
            label: filter.to_string(),
            source: String::new(),
            entry: String::new(),
            removed: false,
            detail: "unknown agent".to_string(),
        });
    }
    McpUninstallReport { removed, skipped }
}

fn removal(agent: &AgentMcpStatus, removed: bool, detail: String) -> McpRemoval {
    McpRemoval {
        agent: agent.id.clone(),
        label: agent.label.clone(),
        source: agent.source.clone(),
        entry: agent.entry.clone(),
        removed,
        detail,
    }
}

fn remove_agent_config(agent: &AgentMcpStatus, cwd: &Path) -> Result<bool, String> {
    if agent.path.as_os_str().is_empty() {
        return Err("the config path is unknown".to_string());
    }
    match agent.id.as_str() {
        "claude-code" => remove_claude(&agent.path, &agent.entry, cwd),
        "opencode" => remove_json_entry(&agent.path, "mcp", &agent.entry, None),
        "pi" | "cursor" | "gemini-cli" | "github-copilot" => {
            remove_json_entry(&agent.path, "mcpServers", &agent.entry, None)
        }
        "codex" => remove_codex(&agent.path, &agent.entry),
        other => Err(format!("uninstall is not implemented for '{other}'")),
    }
}

fn remove_claude(path: &Path, entry: &str, cwd: &Path) -> Result<bool, String> {
    let text = fs::read_to_string(path).map_err(|error| error.to_string())?;
    let text = if path.extension().and_then(|extension| extension.to_str()) == Some("jsonc") {
        strip_jsonc(&text)
    } else {
        text
    };
    let mut value: Value = serde_json::from_str(&text).map_err(|error| error.to_string())?;
    let mut changed = false;
    if let Some(map) = value
        .get_mut("mcpServers")
        .and_then(Value::as_object_mut)
    {
        changed |= map.remove(entry).is_some();
    }
    let cwd_key = cwd.to_string_lossy().to_string();
    if let Some(map) = value
        .get_mut("projects")
        .and_then(|projects| projects.get_mut(&cwd_key))
        .and_then(|project| project.get_mut("mcpServers"))
        .and_then(Value::as_object_mut)
    {
        changed |= map.remove(entry).is_some();
    }
    if !changed {
        return Ok(false);
    }
    let pretty = serde_json::to_string_pretty(&value).map_err(|error| error.to_string())?;
    write_atomic(path, &pretty)?;
    Ok(true)
}

fn remove_json_entry(
    path: &Path,
    container: &str,
    entry: &str,
    _cwd: Option<&Path>,
) -> Result<bool, String> {
    let text = fs::read_to_string(path).map_err(|error| error.to_string())?;
    let text = if path.extension().and_then(|extension| extension.to_str()) == Some("jsonc") {
        strip_jsonc(&text)
    } else {
        text
    };
    let mut value: Value = serde_json::from_str(&text).map_err(|error| error.to_string())?;
    let changed = value
        .get_mut(container)
        .and_then(Value::as_object_mut)
        .map(|map| map.remove(entry).is_some())
        .unwrap_or(false);
    if !changed {
        return Ok(false);
    }
    let pretty = serde_json::to_string_pretty(&value).map_err(|error| error.to_string())?;
    write_atomic(path, &pretty)?;
    Ok(true)
}

fn remove_codex(path: &Path, entry: &str) -> Result<bool, String> {
    let text = fs::read_to_string(path).map_err(|error| error.to_string())?;
    let (out, changed) = strip_codex_section(&text, entry);
    if !changed {
        return Ok(false);
    }
    write_atomic(path, &out)?;
    Ok(true)
}

fn strip_codex_section(text: &str, entry: &str) -> (String, bool) {
    let mut out = String::new();
    let mut skipping = false;
    let mut changed = false;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            let section = trimmed.trim_matches(['[', ']']);
            if codex_section_matches(section, entry) {
                skipping = true;
                changed = true;
                continue;
            }
            skipping = false;
        }
        if !skipping {
            out.push_str(line);
            out.push('\n');
        }
    }
    (out, changed)
}

fn codex_section_matches(section: &str, entry: &str) -> bool {
    let Some(rest) = section.strip_prefix("mcp_servers.") else {
        return false;
    };
    let rest = rest.trim_matches('"');
    rest == entry || rest.starts_with(&format!("{entry}."))
}

fn write_atomic(path: &Path, contents: &str) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let mode = fs::metadata(path)
        .map(|metadata| metadata.permissions().mode() & 0o777)
        .unwrap_or(0o600);
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    let temporary = path.with_extension(format!("tmp-{}-{nonce}", std::process::id()));
    fs::write(&temporary, contents).map_err(|error| error.to_string())?;
    fs::set_permissions(&temporary, fs::Permissions::from_mode(mode))
        .map_err(|error| error.to_string())?;
    if let Err(error) = fs::rename(&temporary, path) {
        let _ = fs::remove_file(&temporary);
        return Err(error.to_string());
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct McpInstallation {
    pub agent: String,
    pub label: String,
    pub source: String,
    pub entry: String,
    pub installed: bool,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct McpInstallReport {
    pub installed: Vec<McpInstallation>,
    pub skipped: Vec<McpInstallation>,
}

impl McpInstallReport {
    pub fn render(&self) -> String {
        let mut out = String::new();
        for installation in &self.installed {
            out.push_str(&format!(
                "Installed {} into {} ({})\n",
                installation.entry, installation.label, installation.source
            ));
        }
        for installation in &self.skipped {
            out.push_str(&format!("Skipped {}: {}\n", installation.label, installation.detail));
        }
        if self.installed.is_empty() && self.skipped.is_empty() {
            out.push_str("Nothing to install.\n");
        }
        out
    }
}

/// Register this server with the selected agent configs. `agent` is one id or `all`.
///
/// `all` only touches agents that are actually present; an explicit id may prepare a config for
/// an agent that is not installed yet.
pub fn install(
    home: &Path,
    cwd: &Path,
    port: u16,
    agent_filter: Option<&str>,
) -> McpInstallReport {
    let report = inspect(home, cwd, port);
    let filter = agent_filter.unwrap_or("all");
    let mut installed = Vec::new();
    let mut skipped = Vec::new();
    let mut matched = false;
    for agent in report.agents {
        if filter != "all" && filter != agent.id {
            continue;
        }
        matched = true;
        if agent.configured {
            skipped.push(installation(&agent, false, "already configured".to_string()));
            continue;
        }
        if filter == "all" && !agent.installed {
            skipped.push(installation(&agent, false, "not installed".to_string()));
            continue;
        }
        match install_agent_config(&agent, home, port) {
            Ok((source, true)) => {
                let mut record = installation(
                    &agent,
                    true,
                    format!("http · {source}{}", comments_note(&source)),
                );
                record.source = source;
                installed.push(record);
            }
            Ok((source, false)) => {
                let mut record = installation(
                    &agent,
                    false,
                    format!("an entry already exists in {source}"),
                );
                record.source = source;
                skipped.push(record);
            }
            Err(error) => skipped.push(installation(&agent, false, error)),
        }
    }
    if !matched {
        skipped.push(McpInstallation {
            agent: filter.to_string(),
            label: filter.to_string(),
            source: String::new(),
            entry: String::new(),
            installed: false,
            detail: "unknown agent".to_string(),
        });
    }
    McpInstallReport { installed, skipped }
}

fn comments_note(source: &str) -> &'static str {
    if source.ends_with(".jsonc") {
        " (comments not preserved)"
    } else {
        ""
    }
}

fn installation(agent: &AgentMcpStatus, installed: bool, detail: String) -> McpInstallation {
    McpInstallation {
        agent: agent.id.clone(),
        label: agent.label.clone(),
        source: agent.source.clone(),
        entry: if agent.entry.is_empty() {
            "astral-skills".to_string()
        } else {
            agent.entry.clone()
        },
        installed,
        detail,
    }
}

fn install_agent_config(
    agent: &AgentMcpStatus,
    home: &Path,
    port: u16,
) -> Result<(String, bool), String> {
    let url = format!("http://127.0.0.1:{port}/mcp");
    let path = if agent.path.as_os_str().is_empty() {
        default_config_path(&agent.id, home)
    } else {
        agent.path.clone()
    };
    let source = display_path(home, &path);
    match agent.id.as_str() {
        "claude-code" => {
            let changed = install_json_entry(
                &path,
                "mcpServers",
                "astral-skills",
                serde_json::json!({ "type": "http", "url": url }),
            )?;
            Ok((source, changed))
        }
        "opencode" => {
            let changed = install_json_entry(
                &path,
                "mcp",
                "astral-skills",
                serde_json::json!({ "type": "remote", "url": url, "enabled": true }),
            )?;
            Ok((source, changed))
        }
        "pi" | "cursor" | "gemini-cli" | "github-copilot" => {
            let changed = install_json_entry(
                &path,
                "mcpServers",
                "astral-skills",
                serde_json::json!({ "url": url }),
            )?;
            Ok((source, changed))
        }
        "codex" => {
            let changed = install_codex(&path, &url)?;
            Ok((source, changed))
        }
        other => Err(format!("install is not implemented for '{other}'")),
    }
}

fn default_config_path(agent: &str, home: &Path) -> PathBuf {
    match agent {
        "claude-code" => home.join(".claude.json"),
        "opencode" => home.join(".config/opencode/opencode.json"),
        "pi" => home.join(".pi/agent/mcp.json"),
        "codex" => home.join(".codex/config.toml"),
        "cursor" => home.join(".cursor/mcp.json"),
        "gemini-cli" => home.join(".gemini/settings.json"),
        "github-copilot" => home.join(".copilot/mcp-config.json"),
        _ => home.join(".astral-mcp.json"),
    }
}

fn install_json_entry(
    path: &Path,
    container: &str,
    entry: &str,
    value: Value,
) -> Result<bool, String> {
    let mut root = if path.is_file() {
        let text = fs::read_to_string(path).map_err(|error| error.to_string())?;
        let text = if path.extension().and_then(|extension| extension.to_str()) == Some("jsonc") {
            strip_jsonc(&text)
        } else {
            text
        };
        serde_json::from_str::<Value>(&text).map_err(|error| error.to_string())?
    } else {
        serde_json::json!({})
    };
    let object = root
        .as_object_mut()
        .ok_or("the config root is not a JSON object")?;
    let map = object
        .entry(container.to_string())
        .or_insert_with(|| serde_json::json!({}));
    let map = map
        .as_object_mut()
        .ok_or("the MCP container is not a JSON object")?;
    if map.get(entry) == Some(&value) {
        return Ok(false);
    }
    map.insert(entry.to_string(), value);
    let pretty = serde_json::to_string_pretty(&root).map_err(|error| error.to_string())?;
    write_atomic(path, &pretty)?;
    Ok(true)
}

fn install_codex(path: &Path, url: &str) -> Result<bool, String> {
    let text = if path.is_file() {
        fs::read_to_string(path).map_err(|error| error.to_string())?
    } else {
        String::new()
    };
    let (mut text, _) = strip_codex_section(&text, "astral-skills");
    if !text.is_empty() && !text.ends_with('\n') {
        text.push('\n');
    }
    text.push_str("[mcp_servers.astral-skills]\n");
    text.push_str(&format!("url = \"{url}\"\n"));
    write_atomic(path, &text)?;
    Ok(true)
}
