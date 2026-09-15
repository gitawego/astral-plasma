use caelestia_daemon::interfaces::api_server::dispatch_http_request;

#[tokio::test]
async fn test_api_status_endpoint() {
    let req = "GET /api/status HTTP/1.1\r\nHost: localhost\r\n\r\n";
    let (code, body) = dispatch_http_request(req).await;
    assert_eq!(code, 200);
    assert!(body.contains("\"ok\":true"));
    assert!(body.contains("caelestia-daemon"));
}

#[tokio::test]
async fn test_api_systemd_status_endpoint() {
    std::env::set_var("CAELESTIA_TEST_MODE", "1");
    let req = "GET /api/systemd/status HTTP/1.1\r\nHost: localhost\r\n\r\n";
    let (code, body) = dispatch_http_request(req).await;
    assert_eq!(code, 200);
    assert!(body.contains("\"installed\":"));
}

#[tokio::test]
async fn test_api_plasma_status_endpoint() {
    std::env::set_var("CAELESTIA_TEST_MODE", "1");
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
