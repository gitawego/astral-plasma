//! MCP status and uninstall: the probe and the agent-config edits.
//!
//! The tests use a dead port for the status checks so they never depend on the developer's
//! running shell, and a local mock for the protocol probe.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::path::PathBuf;
use std::thread;

use astral_plasma::application::mcp_status;

struct Fixture {
    _dir: tempfile::TempDir,
    home: PathBuf,
    cwd: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("home");
        let cwd = dir.path().join("repo");
        std::fs::create_dir_all(&home).unwrap();
        std::fs::create_dir_all(&cwd).unwrap();
        Self { _dir: dir, home, cwd }
    }

    fn write(&self, path: &str, contents: &str) {
        let path = self.home.join(path);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, contents).unwrap();
    }

    fn read(&self, path: &str) -> String {
        std::fs::read_to_string(self.home.join(path)).unwrap()
    }
}

fn port() -> u16 {
    1
}

fn url() -> String {
    format!("http://127.0.0.1:{}/mcp", port())
}

#[test]
fn status_reads_every_supported_agent_and_uninstall_removes_only_our_entry() {
    let fixture = Fixture::new();
    let url = url();
    fixture.write(
        ".claude.json",
        &format!(
            r#"{{"mcpServers":{{"astral-skills":{{"type":"http","url":"{url}"}},"other":{{"url":"http://example.com/mcp"}}}}}}"#
        ),
    );
    fixture.write(
        ".config/opencode/opencode.json",
        &format!(
            r#"{{"mcp":{{"astral-skills":{{"type":"remote","url":"{url}"}},"other":{{"type":"remote","url":"http://example.com/mcp"}}}}}}"#
        ),
    );
    fixture.write(
        ".pi/agent/mcp.json",
        &format!(
            r#"{{"mcpServers":{{"astral-skills":{{"url":"{url}"}},"other":{{"url":"http://example.com/mcp"}}}}}}"#
        ),
    );
    fixture.write(
        ".codex/config.toml",
        &format!(
            "[mcp_servers.astral-skills]\nurl = \"{url}\"\n\n[mcp_servers.other]\nurl = \"http://example.com/mcp\"\n"
        ),
    );
    fixture.write(
        ".cursor/mcp.json",
        &format!(r#"{{"mcpServers":{{"astral-skills":{{"url":"{url}"}}}}}}"#),
    );
    fixture.write(
        ".gemini/settings.json",
        &format!(r#"{{"mcpServers":{{"astral-skills":{{"url":"{url}"}}}}}}"#),
    );
    fixture.write(
        ".copilot/mcp-config.json",
        &format!(r#"{{"mcpServers":{{"astral-skills":{{"url":"{url}"}}}}}}"#),
    );

    let report = mcp_status::inspect(&fixture.home, &fixture.cwd, port());
    assert_eq!(report.agents.len(), 7);
    assert_eq!(report.configured_count, 7, "{:?}", report.agents);
    assert_eq!(report.installed_count, 7);
    assert!(report.all_supported_configured);
    assert_eq!(report.server.state, "down", "port 1 has no server");

    let removal = mcp_status::uninstall(&fixture.home, &fixture.cwd, port(), Some("all"));
    assert_eq!(removal.removed.len(), 7, "{:?}", removal);
    assert!(removal.removed.iter().all(|entry| entry.removed));

    let pi = fixture.read(".pi/agent/mcp.json");
    assert!(!pi.contains("astral-skills"), "{pi}");
    assert!(pi.contains("example.com"), "the sibling entry survives: {pi}");

    let opencode = fixture.read(".config/opencode/opencode.json");
    assert!(!opencode.contains("astral-skills"), "{opencode}");
    assert!(opencode.contains("example.com"), "{opencode}");

    let codex = fixture.read(".codex/config.toml");
    assert!(!codex.contains("astral-skills"), "{codex}");
    assert!(codex.contains("[mcp_servers.other]"), "the sibling section survives: {codex}");

    let after = mcp_status::inspect(&fixture.home, &fixture.cwd, port());
    assert_eq!(after.configured_count, 0, "{:?}", after.agents);
}

#[test]
fn claude_project_scope_is_detected_and_removed() {
    let fixture = Fixture::new();
    let url = url();
    let cwd = fixture.cwd.to_string_lossy();
    fixture.write(
        ".claude.json",
        &format!(
            r#"{{"mcpServers":{{}},"projects":{{"{cwd}":{{"mcpServers":{{"astral-skills":{{"type":"http","url":"{url}"}}}}}}}}}}"#
        ),
    );

    let report = mcp_status::inspect(&fixture.home, &fixture.cwd, port());
    let claude = report
        .agents
        .iter()
        .find(|agent| agent.id == "claude-code")
        .unwrap();
    assert!(claude.configured, "{claude:?}");
    assert_eq!(claude.entry, "astral-skills");

    let removal = mcp_status::uninstall(&fixture.home, &fixture.cwd, port(), Some("claude-code"));
    assert_eq!(removal.removed.len(), 1, "{removal:?}");
    let text = fixture.read(".claude.json");
    assert!(!text.contains("astral-skills"), "{text}");
}

#[test]
fn an_unknown_agent_is_reported_not_ignored() {
    let fixture = Fixture::new();
    let removal = mcp_status::uninstall(&fixture.home, &fixture.cwd, port(), Some("no-such-agent"));
    assert!(removal.removed.is_empty());
    assert_eq!(removal.skipped.len(), 1);
    assert_eq!(removal.skipped[0].detail, "unknown agent");
}

#[test]
fn a_live_mock_is_reported_up_with_its_tools() {
    let (port, server) = mock_server(vec![
        r#"{"jsonrpc":"2.0","id":1,"result":{"supportedVersions":["2026-07-28"],"_meta":{"io.modelcontextprotocol/serverInfo":{"name":"astral-skills"}}}}"#,
        r#"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"skill_search"},{"name":"skill_load"}]}}"#,
    ]);
    let status = mcp_status::probe_server(port);
    server.join().unwrap();
    assert_eq!(status.state, "up", "{status:?}");
    assert_eq!(status.protocol.as_deref(), Some("2026-07-28"));
    assert_eq!(status.tools, vec!["skill_search", "skill_load"]);
}

#[test]
fn a_foreign_service_on_the_port_is_not_called_astral_skills() {
    let (port, server) = mock_server(vec![
        r#"{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"something-else"}}}"#,
        r#"{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"something-else"}}}"#,
    ]);
    let status = mcp_status::probe_server(port);
    server.join().unwrap();
    assert_eq!(status.state, "wrong-service", "{status:?}");
    assert!(status.reachable);
}

fn mock_server(responses: Vec<&'static str>) -> (u16, thread::JoinHandle<()>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let port = listener.local_addr().unwrap().port();
    let handle = thread::spawn(move || {
        for response in responses {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut content_length = 0usize;
            loop {
                let mut line = String::new();
                if reader.read_line(&mut line).unwrap() == 0 {
                    break;
                }
                if line == "\r\n" || line == "\n" {
                    break;
                }
                if line.to_ascii_lowercase().starts_with("content-length:") {
                    content_length = line
                        .split_once(':')
                        .and_then(|(_, value)| value.trim().parse().ok())
                        .unwrap_or(0);
                }
            }
            let mut body = vec![0u8; content_length];
            reader.read_exact(&mut body).unwrap();
            let wire = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                response.len(),
                response
            );
            let mut stream = stream;
            stream.write_all(wire.as_bytes()).unwrap();
        }
    });
    (port, handle)
}


#[test]
fn install_writes_an_agent_entry_and_is_idempotent() {
    let fixture = Fixture::new();
    let report = mcp_status::install(&fixture.home, &fixture.cwd, port(), Some("pi"));
    assert_eq!(report.installed.len(), 1, "{report:?}");
    assert!(report.installed[0].installed);
    assert_eq!(report.installed[0].source, "~/.pi/agent/mcp.json");
    let config = fixture.read(".pi/agent/mcp.json");
    assert!(config.contains("astral-skills"), "{config}");
    assert!(config.contains("http://127.0.0.1:1/mcp"), "{config}");

    let status = mcp_status::inspect(&fixture.home, &fixture.cwd, port());
    let pi = status.agents.iter().find(|agent| agent.id == "pi").unwrap();
    assert!(pi.configured, "{pi:?}");

    let again = mcp_status::install(&fixture.home, &fixture.cwd, port(), Some("pi"));
    assert!(again.installed.is_empty());
    assert_eq!(again.skipped[0].detail, "already configured");
}

#[test]
fn install_updates_an_entry_that_points_at_the_wrong_port() {
    let fixture = Fixture::new();
    fixture.write(
        ".pi/agent/mcp.json",
        r#"{"mcpServers":{"astral-skills":{"url":"http://127.0.0.1:9999/mcp"}}}"#,
    );
    let before = mcp_status::inspect(&fixture.home, &fixture.cwd, port());
    let pi = before.agents.iter().find(|agent| agent.id == "pi").unwrap();
    assert!(!pi.configured, "a different port is not this endpoint: {pi:?}");

    let report = mcp_status::install(&fixture.home, &fixture.cwd, port(), Some("pi"));
    assert_eq!(report.installed.len(), 1, "{report:?}");
    let config = fixture.read(".pi/agent/mcp.json");
    assert!(config.contains("http://127.0.0.1:1/mcp"), "{config}");
    assert!(!config.contains("9999"), "{config}");
}
