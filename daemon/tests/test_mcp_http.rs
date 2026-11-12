//! The Streamable HTTP transport, exercised as an MCP client exercises it.
//!
//! The stdio suite proves the protocol; this one proves the transport: one POST per JSON-RPC
//! message, `application/json` responses, the legacy `Mcp-Session-Id` lifecycle, the modern
//! `MCP-Protocol-Version`/`Mcp-Method`/`Mcp-Name` headers, and the security rules that make a
//! localhost server safe to leave running.

use std::path::PathBuf;
use std::sync::Arc;

use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

use astral_plasma::application::skill_manager::SkillContext;
use astral_plasma::infrastructure::skill_fs::SkillPaths;
use astral_plasma::interfaces::http::{HttpRequest, HttpResponse};
use astral_plasma::interfaces::mcp_server::{serve_http, HttpMcp};

struct Fixture {
    dir: tempfile::TempDir,
    ctx: SkillContext,
    source: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        let paths = SkillPaths::new(
            dir.path().join("data"),
            dir.path().join("state"),
            dir.path().join("cache"),
        );
        let mut ctx = SkillContext::new(paths, 1_000);
        ctx.home = home;
        let source = dir.path().join("my-skills");
        for (id, description) in [("alpha", "first"), ("beta", "second")] {
            let skill = source.join(id);
            std::fs::create_dir_all(skill.join("references")).unwrap();
            std::fs::write(
                skill.join("SKILL.md"),
                format!("---\nname: {id}\ndescription: {description}\n---\n# {id}\n"),
            )
            .unwrap();
        }
        std::fs::write(
            source.join("alpha/references/checklist.md"),
            "- one\n- two\n",
        )
        .unwrap();
        Self { dir, ctx, source }
    }

    fn state(&self) -> HttpMcp {
        HttpMcp::new(self.ctx.clone())
    }

    fn source_str(&self) -> &str {
        self.source.to_str().unwrap()
    }

    fn home(&self) -> PathBuf {
        self.dir.path().join("home")
    }

    fn ledger(&self) -> PathBuf {
        self.dir
            .path()
            .join("state/astral-plasma/skills/ledger.json")
    }
}

fn request(method: &str, path: &str, headers: &[(&str, &str)], body: Value) -> HttpRequest {
    HttpRequest {
        method: method.to_string(),
        path: path.to_string(),
        headers: headers
            .iter()
            .map(|(name, value)| (name.to_ascii_lowercase(), value.to_string()))
            .collect(),
        body: serde_json::to_string(&body).unwrap(),
    }
}

fn header<'a>(response: &'a HttpResponse, name: &str) -> Option<&'a str> {
    response
        .headers
        .iter()
        .find(|(header, _)| header.eq_ignore_ascii_case(name))
        .map(|(_, value)| value.as_str())
}

fn response_json(response: &HttpResponse) -> Value {
    serde_json::from_str(&response.body)
        .unwrap_or_else(|error| panic!("response is not JSON ({error}): {}", response.body))
}

fn initialize() -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": { "name": "http-test", "version": "0.0.0" }
        }
    })
}

fn modern_meta() -> Value {
    json!({
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {}
    })
}

#[tokio::test]
async fn http_initializes_legacy_requests_with_a_session_id() {
    let fixture = Fixture::new();
    let state = fixture.state();

    let response = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("Accept", "application/json, text/event-stream"),
                ("MCP-Protocol-Version", "2025-11-25"),
            ],
            initialize(),
        ))
        .await;
    assert_eq!(response.status, 200, "{}", response.body);
    let session = header(&response, "mcp-session-id")
        .expect("initialize must mint a session id")
        .to_string();
    assert_eq!(
        response_json(&response)["result"]["protocolVersion"],
        "2025-11-25"
    );

    let listed = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2025-11-25"),
                ("Mcp-Session-Id", &session),
            ],
            json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" }),
        ))
        .await;
    assert_eq!(listed.status, 200, "{}", listed.body);
    assert_eq!(
        response_json(&listed)["result"]["tools"]
            .as_array()
            .unwrap()
            .len(),
        4
    );

    let unknown = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2025-11-25"),
                ("Mcp-Session-Id", "not-a-session"),
            ],
            json!({ "jsonrpc": "2.0", "id": 3, "method": "tools/list" }),
        ))
        .await;
    assert_eq!(unknown.status, 404, "{}", unknown.body);
    assert_eq!(response_json(&unknown)["error"]["code"], -32600);
}

#[tokio::test]
async fn http_serves_the_modern_discover_and_validates_mirrored_headers() {
    let fixture = Fixture::new();
    let state = fixture.state();

    let discover = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2026-07-28"),
                ("Mcp-Method", "server/discover"),
            ],
            json!({
                "jsonrpc": "2.0", "id": 4, "method": "server/discover",
                "params": { "_meta": modern_meta() }
            }),
        ))
        .await;
    assert_eq!(discover.status, 200, "{}", discover.body);
    let body = response_json(&discover);
    assert_eq!(body["result"]["resultType"], "complete");
    assert!(body["result"]["supportedVersions"]
        .as_array()
        .unwrap()
        .iter()
        .any(|version| version == "2026-07-28"));

    let mismatch = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2026-07-28"),
                ("Mcp-Method", "tools/call"),
            ],
            json!({
                "jsonrpc": "2.0", "id": 5, "method": "tools/list",
                "params": { "_meta": modern_meta() }
            }),
        ))
        .await;
    assert_eq!(mismatch.status, 400, "{}", mismatch.body);
    assert_eq!(response_json(&mismatch)["error"]["code"], -32020);

    let unsupported = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "1900-01-01"),
                ("Mcp-Method", "tools/list"),
            ],
            json!({
                "jsonrpc": "2.0", "id": 6, "method": "tools/list",
                "params": { "_meta": {
                    "io.modelcontextprotocol/protocolVersion": "1900-01-01",
                    "io.modelcontextprotocol/clientCapabilities": {}
                }}
            }),
        ))
        .await;
    assert_eq!(unsupported.status, 400, "{}", unsupported.body);
    assert_eq!(response_json(&unsupported)["error"]["code"], -32022);

    let unknown = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2026-07-28"),
                ("Mcp-Method", "no/such/method"),
            ],
            json!({
                "jsonrpc": "2.0", "id": 6, "method": "no/such/method",
                "params": { "_meta": modern_meta() }
            }),
        ))
        .await;
    assert_eq!(unknown.status, 404, "{}", unknown.body);
    assert_eq!(response_json(&unknown)["error"]["code"], -32601);

    let no_capabilities = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2026-07-28"),
                ("Mcp-Method", "tools/list"),
            ],
            json!({
                "jsonrpc": "2.0", "id": 7, "method": "tools/list",
                "params": { "_meta": {
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28"
                }}
            }),
        ))
        .await;
    assert_eq!(no_capabilities.status, 400, "{}", no_capabilities.body);
    assert_eq!(response_json(&no_capabilities)["error"]["code"], -32602);
}

#[tokio::test]
async fn http_loads_and_reads_a_skill_without_installing_it() {
    let fixture = Fixture::new();
    let state = fixture.state();

    let loaded = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2026-07-28"),
                ("Mcp-Method", "tools/call"),
                ("Mcp-Name", "skill_load"),
            ],
            json!({
                "jsonrpc": "2.0", "id": 7, "method": "tools/call",
                "params": {
                    "_meta": modern_meta(),
                    "name": "skill_load",
                    "arguments": { "source": fixture.source_str(), "skill": "alpha" }
                }
            }),
        ))
        .await;
    assert_eq!(loaded.status, 200, "{}", loaded.body);
    let body = response_json(&loaded);
    assert_eq!(body["result"]["isError"], false, "{body}");
    let metadata: Value =
        serde_json::from_str(body["result"]["content"][0]["text"].as_str().unwrap()).unwrap();
    assert_eq!(metadata["handle"], "local-my-skills:alpha");
    assert!(body["result"]["content"][1]["text"]
        .as_str()
        .unwrap()
        .contains("# alpha"));

    let read = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2026-07-28"),
                ("Mcp-Method", "tools/call"),
                ("Mcp-Name", "skill_read"),
            ],
            json!({
                "jsonrpc": "2.0", "id": 8, "method": "tools/call",
                "params": {
                    "_meta": modern_meta(),
                    "name": "skill_read",
                    "arguments": {
                        "handle": "local-my-skills:alpha",
                        "path": "references/checklist.md"
                    }
                }
            }),
        ))
        .await;
    assert_eq!(read.status, 200, "{}", read.body);
    let body = response_json(&read);
    assert_eq!(body["result"]["content"][0]["text"], "- one\n- two\n");

    assert!(!fixture.home().join(".agents/skills").exists());
    assert!(!fixture.home().join(".claude/skills").exists());
    assert!(!fixture.ledger().exists());
}

#[tokio::test]
async fn http_answers_notifications_with_202_and_ends_sessions_with_delete() {
    let fixture = Fixture::new();
    let state = fixture.state();

    let initialized = state
        .handle(request(
            "POST",
            "/mcp",
            &[("Content-Type", "application/json")],
            json!({ "jsonrpc": "2.0", "method": "notifications/initialized" }),
        ))
        .await;
    assert_eq!(initialized.status, 202);
    assert!(initialized.body.is_empty());

    let response = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2025-11-25"),
            ],
            initialize(),
        ))
        .await;
    let session = header(&response, "mcp-session-id").unwrap().to_string();

    let deleted = state
        .handle(request(
            "DELETE",
            "/mcp",
            &[("Mcp-Session-Id", &session)],
            Value::Null,
        ))
        .await;
    assert_eq!(deleted.status, 204);

    let after = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("MCP-Protocol-Version", "2025-11-25"),
                ("Mcp-Session-Id", &session),
            ],
            json!({ "jsonrpc": "2.0", "id": 9, "method": "tools/list" }),
        ))
        .await;
    assert_eq!(after.status, 404);

    let get = state.handle(request("GET", "/mcp", &[], Value::Null)).await;
    assert_eq!(get.status, 405, "the modern endpoint has no GET stream");
    assert_eq!(header(&get, "allow"), Some("POST, DELETE, OPTIONS"));
}

#[tokio::test]
async fn http_rejects_a_foreign_origin_and_echoes_a_local_one() {
    let fixture = Fixture::new();
    let state = fixture.state();

    let foreign = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("Origin", "https://evil.example"),
            ],
            initialize(),
        ))
        .await;
    assert_eq!(foreign.status, 403, "{}", foreign.body);

    let local = state
        .handle(request(
            "POST",
            "/mcp",
            &[
                ("Content-Type", "application/json"),
                ("Origin", "http://localhost:8942"),
                ("MCP-Protocol-Version", "2025-11-25"),
            ],
            initialize(),
        ))
        .await;
    assert_eq!(local.status, 200, "{}", local.body);
    assert_eq!(
        header(&local, "access-control-allow-origin"),
        Some("http://localhost:8942")
    );
}

#[tokio::test]
async fn http_transport_works_over_a_real_socket() {
    let fixture = Fixture::new();
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let addr = listener.local_addr().unwrap();
    let state = Arc::new(fixture.state());
    let server = tokio::spawn(serve_http(listener, state));

    let body = serde_json::to_string(&initialize()).unwrap();
    let request = format!(
        "POST /mcp HTTP/1.1\r\n\
         Host: 127.0.0.1\r\n\
         Content-Type: application/json\r\n\
         Accept: application/json, text/event-stream\r\n\
         MCP-Protocol-Version: 2025-11-25\r\n\
         Content-Length: {}\r\n\
         Connection: close\r\n\r\n{}",
        body.len(),
        body
    );

    let mut stream =
        tokio::time::timeout(std::time::Duration::from_secs(5), TcpStream::connect(addr))
            .await
            .expect("connect timed out")
            .unwrap();
    stream.write_all(request.as_bytes()).await.unwrap();
    let mut response = Vec::new();
    tokio::time::timeout(
        std::time::Duration::from_secs(5),
        stream.read_to_end(&mut response),
    )
    .await
    .expect("response timed out")
    .unwrap();
    let response = String::from_utf8_lossy(&response);
    assert!(response.starts_with("HTTP/1.1 200 OK"), "{response}");
    assert!(
        response.to_ascii_lowercase().contains("mcp-session-id:"),
        "{response}"
    );
    assert!(response.contains("2025-11-25"), "{response}");

    server.abort();
}

#[tokio::test]
async fn a_port_already_in_use_is_named_not_silently_replaced() {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let error = astral_plasma::interfaces::mcp_server::run_http(port)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("already in use"), "got: {error}");
    assert!(error.contains(&port.to_string()), "the sentence names the port: {error}");
    assert!(error.contains("--port"), "and the way out: {error}");
}
