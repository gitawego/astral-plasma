use astral_plasma::application::assistant_service::AssistantService;
use astral_plasma::domain::assistant::{ChatMessage, ChatSession};
use tempfile::tempdir;

#[test]
fn test_session_serialization_deserialization() {
    let session = ChatSession {
        id: "session_12345".to_string(),
        title: "Kernel debugging discussion".to_string(),
        created_at: 1727400000000,
        updated_at: 1727400050000,
        provider: Some("opencode-go".to_string()),
        model: Some("mimo-v2.6-flash".to_string()),
        harness: Some("pi".to_string()),
        messages: vec![
            ChatMessage {
                id: "msg_1".to_string(),
                role: "user".to_string(),
                content: "How do I check kernel logs?".to_string(),
                images: vec![],
                files: vec!["/var/log/dmesg".to_string()],
                tool_calls: vec![],
                timestamp: 1727400000000,
            },
            ChatMessage {
                id: "msg_2".to_string(),
                role: "assistant".to_string(),
                content: "You can run `journalctl -k` or `dmesg`.".to_string(),
                images: vec![],
                files: vec![],
                tool_calls: vec![],
                timestamp: 1727400050000,
            },
        ],
    };

    let json = serde_json::to_string_pretty(&session).expect("Failed to serialize");
    let deserialized: ChatSession = serde_json::from_str(&json).expect("Failed to deserialize");
    assert_eq!(session, deserialized);
}

#[test]
fn test_save_and_get_session() {
    let tmp = tempdir().expect("Failed to create tempdir");
    let svc = AssistantService::with_sessions_dir(tmp.path().to_path_buf());

    let session = ChatSession {
        id: "session_abc".to_string(),
        title: "Test Session".to_string(),
        created_at: 1000,
        updated_at: 2000,
        provider: Some("gemini".to_string()),
        model: Some("gemini-2.5-flash".to_string()),
        harness: Some("pi".to_string()),
        messages: vec![
            ChatMessage {
                id: "m1".to_string(),
                role: "user".to_string(),
                content: "Hello!".to_string(),
                images: vec![],
                files: vec![],
                tool_calls: vec![],
                timestamp: 1000,
            }
        ],
    };

    svc.save_session(&session).expect("Failed to save session");

    let loaded = svc.get_session("session_abc").expect("Failed to load session");
    assert_eq!(loaded.id, "session_abc");
    assert_eq!(loaded.title, "Test Session");
    assert_eq!(loaded.messages.len(), 1);
    assert_eq!(loaded.messages[0].content, "Hello!");

    // Saving session also marks it active automatically
    assert_eq!(svc.get_active_session_id(), Some("session_abc".to_string()));
}

#[test]
fn test_list_sessions_order_by_updated_at() {
    let tmp = tempdir().expect("Failed to create tempdir");
    let svc = AssistantService::with_sessions_dir(tmp.path().to_path_buf());

    let s1 = ChatSession {
        id: "session_old".to_string(),
        title: "Old Session".to_string(),
        created_at: 1000,
        updated_at: 2000,
        provider: None,
        model: None,
        harness: None,
        messages: vec![],
    };
    let s2 = ChatSession {
        id: "session_new".to_string(),
        title: "Newer Session".to_string(),
        created_at: 3000,
        updated_at: 5000,
        provider: None,
        model: None,
        harness: None,
        messages: vec![ChatMessage {
            id: "m".to_string(),
            role: "assistant".to_string(),
            content: "Latest preview message content here".to_string(),
            images: vec![],
            files: vec![],
            tool_calls: vec![],
            timestamp: 5000,
        }],
    };

    svc.save_session(&s1).unwrap();
    svc.save_session(&s2).unwrap();

    let list = svc.list_sessions().expect("Failed to list sessions");
    assert_eq!(list.len(), 2);
    // session_new has updated_at 5000, so it must be first
    assert_eq!(list[0].id, "session_new");
    assert_eq!(list[0].message_count, 1);
    assert_eq!(list[0].last_preview, "Latest preview message content here");
    assert_eq!(list[1].id, "session_old");
}

#[test]
fn test_delete_session_and_active_session_cleanup() {
    let tmp = tempdir().expect("Failed to create tempdir");
    let svc = AssistantService::with_sessions_dir(tmp.path().to_path_buf());

    let s = ChatSession {
        id: "session_to_delete".to_string(),
        title: "Disposable".to_string(),
        created_at: 100,
        updated_at: 200,
        provider: None,
        model: None,
        harness: None,
        messages: vec![],
    };

    svc.save_session(&s).unwrap();
    assert_eq!(svc.get_active_session_id(), Some("session_to_delete".to_string()));

    let deleted = svc.delete_session("session_to_delete").expect("Failed to delete");
    assert!(deleted);

    // Should no longer exist
    assert!(svc.get_session("session_to_delete").is_err());
    // Active session should be cleared
    assert_eq!(svc.get_active_session_id(), None);
}

#[test]
fn test_sanitize_id_security() {
    assert!(AssistantService::sanitize_id("valid_id-123").is_ok());
    assert!(AssistantService::sanitize_id("../evil").is_err());
    assert!(AssistantService::sanitize_id("/etc/passwd").is_err());
    assert!(AssistantService::sanitize_id("").is_err());
    assert!(AssistantService::sanitize_id("hello world").is_err());
}
