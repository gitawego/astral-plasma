//! The small HTTP surface both the REST API and the MCP endpoint share.
//!
//! This is deliberately not a general web server: it reads one request per connection, with a
//! bounded header and body, and writes one response with `Connection: close`. That is enough for
//! the local daemon and for Streamable HTTP, where every JSON-RPC message is its own POST.

use std::collections::BTreeMap;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

use crate::domain::ports::DynResult;

const MAX_HEADER_BYTES: usize = 64 * 1024;
const MAX_BODY_BYTES: usize = 8 * 1024 * 1024;

/// One parsed HTTP request. Header names are lowercased; values keep their case.
#[derive(Debug, Clone)]
pub struct HttpRequest {
    pub method: String,
    pub path: String,
    pub headers: BTreeMap<String, String>,
    pub body: String,
}

impl HttpRequest {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .get(&name.to_ascii_lowercase())
            .map(String::as_str)
    }

    pub fn parse(raw: &str) -> Result<Self, String> {
        let (head, body) = raw
            .split_once("\r\n\r\n")
            .or_else(|| raw.split_once("\n\n"))
            .ok_or("incomplete HTTP request: no header terminator")?;
        let mut lines = head.lines();
        let request_line = lines.next().ok_or("missing HTTP request line")?;
        let mut parts = request_line.split_whitespace();
        let method = parts
            .next()
            .ok_or("missing HTTP method")?
            .to_ascii_uppercase();
        let target = parts.next().ok_or("missing HTTP request target")?;
        let path = target.split(['?', '#']).next().unwrap_or("/").to_string();
        let mut headers = BTreeMap::new();
        for line in lines {
            if let Some((name, value)) = line.split_once(':') {
                headers.insert(name.trim().to_ascii_lowercase(), value.trim().to_string());
            }
        }
        Ok(Self {
            method,
            path,
            headers,
            body: body.to_string(),
        })
    }
}

/// One response. `Content-Length` and `Connection: close` are added by [`HttpResponse::to_http`].
#[derive(Debug, Clone)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: String,
}

impl HttpResponse {
    pub fn json(status: u16, body: String) -> Self {
        Self {
            status,
            headers: vec![(
                "Content-Type".to_string(),
                "application/json; charset=utf-8".to_string(),
            )],
            body,
        }
    }

    pub fn empty(status: u16) -> Self {
        Self {
            status,
            headers: Vec::new(),
            body: String::new(),
        }
    }

    pub fn header(mut self, name: &str, value: &str) -> Self {
        self.headers
            .push((sanitize_header(name), sanitize_header(value)));
        self
    }

    /// The wire form. One request per connection means closing is the frame boundary.
    pub fn to_http(&self) -> String {
        let mut out = format!(
            "HTTP/1.1 {} {}\r\n",
            self.status,
            reason_phrase(self.status)
        );
        for (name, value) in &self.headers {
            out.push_str(name);
            out.push_str(": ");
            out.push_str(value);
            out.push_str("\r\n");
        }
        out.push_str(&format!(
            "Content-Length: {}\r\nConnection: close\r\n\r\n",
            self.body.len()
        ));
        out.push_str(&self.body);
        out
    }
}

fn sanitize_header(value: &str) -> String {
    value.replace(['\r', '\n'], "")
}

fn reason_phrase(status: u16) -> &'static str {
    match status {
        200 => "OK",
        202 => "Accepted",
        204 => "No Content",
        400 => "Bad Request",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        _ => "OK",
    }
}

/// Read one request from a TCP stream, bounded so a bad client cannot exhaust memory.
pub async fn read_request(stream: &mut TcpStream) -> DynResult<String> {
    let mut data = Vec::new();
    let mut buffer = [0u8; 8192];
    let mut header_end = None;
    while data.len() <= MAX_HEADER_BYTES {
        let read = stream.read(&mut buffer).await?;
        if read == 0 {
            break;
        }
        data.extend_from_slice(&buffer[..read]);
        if let Some(end) = header_end_index(&data) {
            header_end = Some(end);
            break;
        }
    }
    let Some(end) = header_end else {
        return Ok(String::from_utf8_lossy(&data).into_owned());
    };

    let header_text = String::from_utf8_lossy(&data[..end]);
    if header_text
        .lines()
        .any(|line| line.trim().eq_ignore_ascii_case("expect: 100-continue"))
    {
        stream
            .write_all(b"HTTP/1.1 100 Continue\r\n\r\n")
            .await?;
        stream.flush().await?;
    }
    let length = content_length(&header_text)
        .unwrap_or(0)
        .min(MAX_BODY_BYTES);
    let target = end + length;
    while data.len() < target {
        let read = stream.read(&mut buffer).await?;
        if read == 0 {
            break;
        }
        data.extend_from_slice(&buffer[..read]);
    }
    Ok(String::from_utf8_lossy(&data).into_owned())
}

fn header_end_index(data: &[u8]) -> Option<usize> {
    for separator in [b"\r\n\r\n".as_slice(), b"\n\n".as_slice()] {
        if let Some(index) = data
            .windows(separator.len())
            .position(|window| window == separator)
        {
            return Some(index + separator.len());
        }
    }
    None
}

fn content_length(headers: &str) -> Option<usize> {
    headers.lines().find_map(|line| {
        let (name, value) = line.split_once(':')?;
        if name.trim().eq_ignore_ascii_case("content-length") {
            value.trim().parse().ok()
        } else {
            None
        }
    })
}

/// Write a response and close. The caller owns the stream for one request only.
pub async fn write_response(stream: &mut TcpStream, response: &HttpResponse) -> DynResult<()> {
    stream.write_all(response.to_http().as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_request_line_headers_and_body_are_parsed() {
        let raw = "POST /mcp?x=1 HTTP/1.1\r\nHost: localhost\r\nMCP-Protocol-Version: 2026-07-28\r\nContent-Length: 2\r\n\r\n{}";
        let request = HttpRequest::parse(raw).unwrap();
        assert_eq!(request.method, "POST");
        assert_eq!(request.path, "/mcp");
        assert_eq!(request.header("mcp-protocol-version"), Some("2026-07-28"));
        assert_eq!(request.body, "{}");
    }

    #[test]
    fn a_response_carries_its_headers_and_length() {
        let response = HttpResponse::json(200, "{}".to_string()).header("Mcp-Session-Id", "abc");
        let wire = response.to_http();
        assert!(wire.starts_with("HTTP/1.1 200 OK\r\n"));
        assert!(wire.contains("Mcp-Session-Id: abc\r\n"));
        assert!(wire.contains("Content-Length: 2\r\n"));
        assert!(wire.ends_with("\r\n\r\n{}"));
    }

    #[test]
    fn header_injection_is_stripped() {
        let response = HttpResponse::empty(200).header("X-Test", "a\r\nInjected: yes");
        assert!(!response.to_http().contains("\r\nInjected: yes"));
    }
}
