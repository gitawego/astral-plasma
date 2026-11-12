use astral_plasma::domain::branding;
use astral_plasma::interfaces::api_server::dispatch_http_request;

#[tokio::test]
async fn test_api_status_endpoint() {
    let req = "GET /api/status HTTP/1.1\r\nHost: localhost\r\n\r\n";
    let (code, body) = dispatch_http_request(req).await;
    assert_eq!(code, 200);
    assert!(body.contains("\"ok\":true"));
    assert!(body.contains("astral-plasma"));
}

#[tokio::test]
async fn test_api_systemd_status_endpoint() {
    std::env::set_var(branding::ENV_TEST_MODE, "1");
    let req = "GET /api/systemd/status HTTP/1.1\r\nHost: localhost\r\n\r\n";
    let (code, body) = dispatch_http_request(req).await;
    assert_eq!(code, 200);
    assert!(body.contains("\"installed\":"));
}

#[tokio::test]
async fn test_api_plasma_status_endpoint() {
    std::env::set_var(branding::ENV_TEST_MODE, "1");
    let req = "GET /api/plasma/status HTTP/1.1\r\nHost: localhost\r\n\r\n";
    let (code, body) = dispatch_http_request(req).await;
    assert_eq!(code, 200);
    assert!(body.contains("\"panels\":"));
}

#[tokio::test]
async fn test_api_404_endpoint() {
    let req = "GET /nonexistent HTTP/1.1\r\nHost: localhost\r\n\r\n";
    let (code, body) = dispatch_http_request(req).await;
    assert_eq!(code, 404);
    assert!(body.contains("Not Found"));
}

#[tokio::test]
async fn the_api_server_names_an_occupied_port_instead_of_stealing_it() {
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let error = astral_plasma::interfaces::api_server::run_api_server(port)
        .await
        .unwrap_err()
        .to_string();
    assert!(error.contains("already in use"), "got: {error}");
    assert!(error.contains("ASTRAL_API_PORT"), "the sentence names the override: {error}");
}

#[tokio::test]
async fn the_api_server_start_is_idempotent_when_our_endpoint_is_already_up() {
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let mock = tokio::spawn(async move {
        // First connection is the liveness probe; second carries /api/status.
        for _ in 0..2 {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut buffer = [0u8; 1024];
            let _ = tokio::io::AsyncReadExt::read(&mut stream, &mut buffer).await;
            let body = r#"{"ok":true,"name":"astral-plasma","version":"test"}"#;
            let wire = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = tokio::io::AsyncWriteExt::write_all(&mut stream, wire.as_bytes()).await;
        }
    });

    let result = astral_plasma::interfaces::api_server::run_api_server_if_needed(port).await;
    mock.abort();
    assert!(result.is_ok(), "{result:?}");
}

#[tokio::test]
async fn the_api_server_start_names_a_foreign_listener() {
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let mock = tokio::spawn(async move {
        for _ in 0..2 {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut buffer = [0u8; 1024];
            let _ = tokio::io::AsyncReadExt::read(&mut stream, &mut buffer).await;
            let body = r#"{"error":"not astral"}"#;
            let wire = format!(
                "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = tokio::io::AsyncWriteExt::write_all(&mut stream, wire.as_bytes()).await;
        }
    });

    let error = astral_plasma::interfaces::api_server::run_api_server_if_needed(port)
        .await
        .unwrap_err()
        .to_string();
    mock.abort();
    assert!(error.contains("already in use"), "got: {error}");
}
