//! The `astral-plasma skills mcp` stdio server, exercised as an MCP client exercises it.
//!
//! The point of this surface is that finding and loading a skill must not install anything: no
//! link in an agent directory, no ledger row, no store copy. A skill is fetched, returned in the
//! tool result, and forgotten when the session ends. The tests below therefore assert the
//! protocol *and* the absence of the install side effects, because "it worked" would otherwise
//! hide a second, unwanted management path.

use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use serde_json::{json, Value};

struct Sandbox {
    dir: tempfile::TempDir,
}

impl Sandbox {
    fn new() -> Self {
        Self {
            dir: tempfile::tempdir().unwrap(),
        }
    }

    fn home(&self) -> PathBuf {
        self.dir.path().join("home")
    }

    fn source(&self) -> PathBuf {
        let root = self.dir.path().join("my-skills");
        for (id, description) in [("alpha", "first"), ("beta", "second")] {
            let dir = root.join(id);
            std::fs::create_dir_all(dir.join("references")).unwrap();
            std::fs::write(
                dir.join("SKILL.md"),
                format!("---\nname: {id}\ndescription: {description}\n---\n# {id}\n"),
            )
            .unwrap();
        }
        std::fs::write(root.join("alpha/references/checklist.md"), "- one\n- two\n").unwrap();
        root
    }

    fn ledger(&self) -> PathBuf {
        self.dir
            .path()
            .join("state/astral-plasma/skills/ledger.json")
    }

    fn run_cli(&self, args: &[&str]) -> (bool, String) {
        let home = self.home();
        std::fs::create_dir_all(&home).unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_astral-plasma"))
            .args(args)
            .env("HOME", &home)
            .env("XDG_DATA_HOME", self.dir.path().join("data"))
            .env("XDG_STATE_HOME", self.dir.path().join("state"))
            .env("XDG_CACHE_HOME", self.dir.path().join("cache"))
            .output()
            .expect("the binary runs");
        (
            output.status.success(),
            format!(
                "{}{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            ),
        )
    }

    /// One complete stdio conversation: every request is written before stdin closes, then the
    /// child's responses are read to EOF. The server must exit cleanly on EOF.
    fn mcp(&self, requests: &[Value]) -> (Vec<Value>, String) {
        let home = self.home();
        std::fs::create_dir_all(&home).unwrap();
        let mut child = Command::new(env!("CARGO_BIN_EXE_astral-plasma"))
            .args(["skills", "mcp"])
            .env("HOME", &home)
            .env("XDG_DATA_HOME", self.dir.path().join("data"))
            .env("XDG_STATE_HOME", self.dir.path().join("state"))
            .env("XDG_CACHE_HOME", self.dir.path().join("cache"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("the MCP server starts");

        {
            let stdin = child.stdin.as_mut().expect("stdin is piped");
            for request in requests {
                writeln!(stdin, "{}", serde_json::to_string(request).unwrap()).unwrap();
            }
        }
        drop(child.stdin.take());

        let output = child.wait_with_output().expect("the MCP server exits");
        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
        assert!(
            output.status.success(),
            "the server must exit 0 on EOF; stderr: {stderr}"
        );
        let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
        let responses: Vec<Value> = stdout
            .lines()
            .filter(|line| !line.trim().is_empty())
            .map(|line| {
                serde_json::from_str(line)
                    .unwrap_or_else(|error| panic!("stdout is not pure JSON-RPC ({error}): {line}"))
            })
            .collect();
        (responses, stderr)
    }
}

fn initialize(id: u64) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": { "name": "astral-test", "version": "0.0.0" }
        }
    })
}

fn initialized() -> Value {
    json!({ "jsonrpc": "2.0", "method": "notifications/initialized" })
}

fn result_text(response: &Value) -> &str {
    response["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_else(|| panic!("no text content in {response}"))
}

fn result_json(response: &Value) -> Value {
    serde_json::from_str(result_text(response)).unwrap_or_else(|error| {
        panic!(
            "tool result is not JSON ({error}): {}",
            result_text(response)
        )
    })
}

fn by_id(responses: &[Value], id: u64) -> &Value {
    responses
        .iter()
        .find(|response| response["id"] == id)
        .unwrap_or_else(|| panic!("no response with id {id}: {responses:?}"))
}

#[test]
fn mcp_finds_and_loads_a_skill_without_installing_it() {
    let sandbox = Sandbox::new();
    let source = sandbox.source();
    let source_str = source.to_str().unwrap();

    let (responses, stderr) = sandbox.mcp(&[
        initialize(1),
        initialized(),
        json!({ "jsonrpc": "2.0", "id": 2, "method": "tools/list" }),
        json!({
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": { "name": "skill_inspect", "arguments": { "source": source_str } }
        }),
        json!({
            "jsonrpc": "2.0", "id": 4, "method": "tools/call",
            "params": { "name": "skill_load", "arguments": { "source": source_str, "skill": "alpha" } }
        }),
        json!({
            "jsonrpc": "2.0", "id": 5, "method": "tools/call",
            "params": {
                "name": "skill_read",
                "arguments": { "handle": "local-my-skills:alpha", "path": "references/checklist.md" }
            }
        }),
        json!({
            "jsonrpc": "2.0", "id": 6, "method": "tools/call",
            "params": {
                "name": "skill_read",
                "arguments": { "handle": "local-my-skills:alpha", "path": "../beta/SKILL.md" }
            }
        }),
        json!({
            "jsonrpc": "2.0", "id": 7, "method": "tools/call",
            "params": { "name": "no_such_tool", "arguments": {} }
        }),
    ]);

    let init = by_id(&responses, 1);
    assert_eq!(init["result"]["protocolVersion"], "2025-06-18");
    assert!(
        init["result"]["capabilities"]["tools"].is_object(),
        "{init}"
    );
    assert_eq!(init["result"]["serverInfo"]["name"], "astral-skills");

    let listed = by_id(&responses, 2);
    let tools: Vec<&str> = listed["result"]["tools"]
        .as_array()
        .expect("tools are an array")
        .iter()
        .filter_map(|tool| tool["name"].as_str())
        .collect();
    for expected in ["skill_search", "skill_inspect", "skill_load", "skill_read"] {
        assert!(tools.contains(&expected), "missing {expected}: {tools:?}");
    }

    let inspected = by_id(&responses, 3);
    assert_eq!(inspected["result"]["isError"], false, "{inspected}");
    let inspected = result_json(inspected);
    let ids: Vec<&str> = inspected["skills"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|skill| skill["id"].as_str())
        .collect();
    assert_eq!(ids, vec!["alpha", "beta"]);

    let loaded = by_id(&responses, 4);
    assert_eq!(loaded["result"]["isError"], false, "{loaded}");
    let metadata = result_json(loaded);
    assert_eq!(metadata["handle"], "local-my-skills:alpha");
    assert_eq!(metadata["name"], "alpha");
    assert!(
        metadata["files"]
            .as_array()
            .unwrap()
            .iter()
            .any(|file| file["path"] == "references/checklist.md"),
        "{metadata}"
    );
    let manifest = loaded["result"]["content"][1]["text"].as_str().unwrap();
    assert!(manifest.contains("# alpha"), "{manifest}");

    let read = by_id(&responses, 5);
    assert_eq!(read["result"]["isError"], false, "{read}");
    assert_eq!(result_text(read), "- one\n- two\n");

    let traversal = by_id(&responses, 6);
    assert_eq!(
        traversal["result"]["isError"], true,
        "a traversal must be refused: {traversal}"
    );
    assert!(
        !result_text(traversal).contains("# beta"),
        "no sibling leaked: {traversal}"
    );

    let unknown = by_id(&responses, 7);
    assert_eq!(unknown["result"]["isError"], true, "{unknown}");

    assert!(
        !sandbox.home().join(".agents/skills").exists(),
        "loading must not link into the canonical farm"
    );
    assert!(
        !sandbox.home().join(".claude/skills").exists(),
        "loading must not link into any agent directory"
    );
    assert!(
        !sandbox.ledger().exists(),
        "loading must not write a ledger: {:?}",
        sandbox.ledger()
    );
    assert!(
        stderr.is_empty(),
        "the protocol owns stdout; stderr stays quiet: {stderr}"
    );
}

#[test]
fn mcp_searches_added_sources_without_fetching_a_catalog() {
    let sandbox = Sandbox::new();
    let source = sandbox.source();
    let (ok, output) = sandbox.run_cli(&["skills", "source", "add", source.to_str().unwrap()]);
    assert!(ok, "adding a source failed: {output}");

    let (responses, _) = sandbox.mcp(&[
        initialize(1),
        initialized(),
        json!({
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {
                "name": "skill_search",
                "arguments": { "query": "alph", "source": "local-my-skills" }
            }
        }),
        json!({
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": {
                "name": "skill_search",
                "arguments": { "query": "", "source": "added" }
            }
        }),
    ]);

    let by_id_2 = by_id(&responses, 2);
    assert_eq!(by_id_2["result"]["isError"], false, "{by_id_2}");
    let hits = result_json(by_id_2);
    assert_eq!(hits["hits"].as_array().unwrap().len(), 1, "{hits}");
    assert_eq!(hits["hits"][0]["name"], "alpha");
    assert_eq!(hits["hits"][0]["source"], "local-my-skills");

    let by_id_3 = by_id(&responses, 3);
    let all = result_json(by_id_3);
    let names: Vec<&str> = all["hits"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|hit| hit["name"].as_str())
        .collect();
    assert_eq!(names, vec!["alpha", "beta"]);
}

#[test]
fn mcp_reports_protocol_errors_and_never_replies_to_notifications() {
    let sandbox = Sandbox::new();
    let home = sandbox.home();
    std::fs::create_dir_all(&home).unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_astral-plasma"))
        .args(["skills", "mcp"])
        .env("HOME", &home)
        .env("XDG_DATA_HOME", sandbox.dir.path().join("data"))
        .env("XDG_STATE_HOME", sandbox.dir.path().join("state"))
        .env("XDG_CACHE_HOME", sandbox.dir.path().join("cache"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    {
        let stdin = child.stdin.as_mut().unwrap();
        writeln!(stdin, "this is not json").unwrap();
        writeln!(
            stdin,
            "{}",
            json!({"jsonrpc":"2.0","method":"notifications/initialized"})
        )
        .unwrap();
        writeln!(
            stdin,
            "{}",
            json!({"jsonrpc":"2.0","id":9,"method":"no/such/method"})
        )
        .unwrap();
        writeln!(
            stdin,
            "{}",
            json!({"jsonrpc":"2.0","id":10,"method":"ping"})
        )
        .unwrap();
    }
    drop(child.stdin.take());
    let output = child.wait_with_output().unwrap();
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let responses: Vec<Value> = stdout
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str(line).unwrap_or_else(|_| panic!("not JSON: {line}")))
        .collect();
    assert_eq!(
        responses.len(),
        3,
        "one parse error, one method error, one pong: {stdout}"
    );
    assert_eq!(responses[0]["error"]["code"], -32700);
    assert_eq!(responses[1]["error"]["code"], -32601);
    assert_eq!(
        responses[2]["result"],
        json!({}),
        "ping answers an empty result"
    );
}

#[test]
fn mcp_supports_the_current_stateless_discover_probe() {
    let sandbox = Sandbox::new();
    let (responses, _) = sandbox.mcp(&[
        json!({
            "jsonrpc": "2.0", "id": 1, "method": "server/discover",
            "params": {
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
                    "io.modelcontextprotocol/clientCapabilities": {}
                }
            }
        }),
        json!({
            "jsonrpc": "2.0", "id": 2, "method": "tools/list",
            "params": {
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
                    "io.modelcontextprotocol/clientCapabilities": {}
                }
            }
        }),
    ]);

    let discover = by_id(&responses, 1);
    assert_eq!(discover["result"]["resultType"], "complete");
    assert!(discover["result"]["supportedVersions"]
        .as_array()
        .unwrap()
        .iter()
        .any(|version| version == "2026-07-28"));
    assert_eq!(
        discover["result"]["_meta"]["io.modelcontextprotocol/serverInfo"]["name"],
        "astral-skills"
    );

    let listed = by_id(&responses, 2);
    assert_eq!(listed["result"]["resultType"], "complete");
    assert_eq!(listed["result"]["tools"].as_array().unwrap().len(), 4);
}
