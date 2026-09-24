use astral_plasma::domain::model::*;
use astral_plasma::domain::ports::*;
use std::collections::HashMap;

#[test]
fn test_desktop_session_snapshot_schema_roundtrip() {
    let mut capabilities = HashMap::new();
    capabilities.insert(
        "workspaceSwitch".to_string(),
        Capability {
            available: true,
            mode: Some("dispatcher".to_string()),
            reason: None,
            owner: Some("compositor".to_string()),
        },
    );
    capabilities.insert(
        "backgroundBlur".to_string(),
        Capability {
            available: true,
            mode: Some("region".to_string()),
            reason: None,
            owner: None,
        },
    );
    capabilities.insert(
        "focusRestore".to_string(),
        Capability {
            available: false,
            mode: None,
            reason: Some("not-supported".to_string()),
            owner: None,
        },
    );

    let output = Output {
        id: "DP-1".to_string(),
        name: "DisplayPort-0".to_string(),
        geometry: OutputGeometry {
            x: 0,
            y: 0,
            width: 2560,
            height: 1600,
        },
        scale: 1.0,
        refresh_rate: 165.0,
        focused: true,
        primary: true,
    };

    let workspace = Workspace {
        id: "1".to_string(),
        name: "1".to_string(),
        index: 1,
        output_id: Some("DP-1".to_string()),
        active: true,
    };

    let window = Window {
        id: "win-123".to_string(),
        title: "Ghostty".to_string(),
        app_name: "Ghostty".to_string(),
        icon_name: "com.mitchellh.ghostty".to_string(),
        material_icon: "terminal".to_string(),
        app_id: "com.mitchellh.ghostty".to_string(),
        desktop_file: "com.mitchellh.ghostty".to_string(),
        is_active: true,
        is_maximized: false,
        is_fullscreen: false,
    };

    let snapshot = DesktopSessionSnapshot {
        schema_version: 1,
        session_id: "sess-abc".to_string(),
        revision: 42,
        connection: SessionConnectionState::Connected,
        profile: "hyprland".to_string(),
        focused_output_id: Some("DP-1".to_string()),
        outputs: vec![output],
        workspaces: vec![workspace],
        windows: vec![window],
        capabilities,
        last_updated: 1727196000000,
    };

    let json = serde_json::to_string(&snapshot).expect("serialize snapshot");
    assert!(json.contains(r#""schemaVersion":1"#));
    assert!(json.contains(r#""sessionId":"sess-abc""#));
    assert!(json.contains(r#""connection":"connected""#));
    assert!(json.contains(r#""profile":"hyprland""#));
    assert!(json.contains(r#""refreshRate":165.0"#));
    assert!(json.contains(r#""outputId":"DP-1""#));

    let deserialized: DesktopSessionSnapshot =
        serde_json::from_str(&json).expect("deserialize snapshot");
    assert_eq!(deserialized.schema_version, 1);
    assert_eq!(deserialized.connection, SessionConnectionState::Connected);
    assert_eq!(deserialized.outputs.len(), 1);
    assert_eq!(deserialized.outputs[0].refresh_rate, 165.0);
    assert_eq!(deserialized.workspaces.len(), 1);
    assert!(deserialized.capabilities.get("workspaceSwitch").unwrap().available);
    assert!(!deserialized.capabilities.get("focusRestore").unwrap().available);
}

#[test]
fn test_action_result_status_and_intent_contracts() {
    let intent = UserIntent {
        request_id: "req-1".to_string(),
        kind: "activate-window".to_string(),
        target: serde_json::json!({ "windowId": "win-123" }),
        parameters: serde_json::json!({}),
    };

    let applied_res = ActionResult {
        request_id: intent.request_id.clone(),
        status: ActionStatus::Applied,
        message_key: "window-activated".to_string(),
        details: serde_json::json!({ "windowId": "win-123" }),
        revision: 43,
    };

    let json = serde_json::to_string(&applied_res).unwrap();
    assert!(json.contains(r#""status":"applied""#));
    assert!(json.contains(r#""messageKey":"window-activated""#));

    let unsupported_res = ActionResult {
        request_id: "req-2".to_string(),
        status: ActionStatus::Unsupported,
        message_key: "action-unsupported-in-profile".to_string(),
        details: serde_json::json!({ "feature": "kwin-script-focus" }),
        revision: 44,
    };
    let json_unsupported = serde_json::to_string(&unsupported_res).unwrap();
    assert!(json_unsupported.contains(r#""status":"unsupported""#));
}

#[test]
fn test_canonical_desktop_events_serialization() {
    let ev1 = DesktopEvent::WorkspaceActivated {
        id: "2".to_string(),
        output_id: Some("DP-1".to_string()),
    };
    let json1 = serde_json::to_string(&ev1).unwrap();
    assert!(json1.contains(r#""type":"WorkspaceActivated""#));
    assert!(json1.contains(r#""id":"2""#));

    let ev2 = DesktopEvent::SessionConnectionChanged {
        state: SessionConnectionState::Degraded,
    };
    let json2 = serde_json::to_string(&ev2).unwrap();
    assert!(json2.contains(r#""type":"SessionConnectionChanged""#));
    assert!(json2.contains(r#""state":"degraded""#));

    let parsed: DesktopEvent = serde_json::from_str(&json1).unwrap();
    match parsed {
        DesktopEvent::WorkspaceActivated { id, output_id } => {
            assert_eq!(id, "2");
            assert_eq!(output_id, Some("DP-1".to_string()));
        }
        _ => panic!("Unexpected event variant"),
    }
}

// Contract fixture: verifies DesktopSessionPort trait mockability and behavior
struct MockDesktopSessionPort {
    snapshot: DesktopSessionSnapshot,
}

impl DesktopSessionPort for MockDesktopSessionPort {
    fn get_snapshot(&self) -> DynResult<DesktopSessionSnapshot> {
        Ok(self.snapshot.clone())
    }

    fn get_capabilities(&self) -> DynResult<HashMap<String, Capability>> {
        Ok(self.snapshot.capabilities.clone())
    }

    fn execute_intent(&self, intent: UserIntent) -> DynResult<ActionResult> {
        if intent.kind == "unsupported-op" {
            Ok(ActionResult {
                request_id: intent.request_id,
                status: ActionStatus::Unsupported,
                message_key: "unsupported".to_string(),
                details: serde_json::json!({}),
                revision: self.snapshot.revision,
            })
        } else {
            Ok(ActionResult {
                request_id: intent.request_id,
                status: ActionStatus::Applied,
                message_key: "success".to_string(),
                details: serde_json::json!({}),
                revision: self.snapshot.revision + 1,
            })
        }
    }
}

#[test]
fn test_desktop_session_port_contract() {
    let mock = MockDesktopSessionPort {
        snapshot: DesktopSessionSnapshot {
            schema_version: 1,
            session_id: "test".to_string(),
            revision: 10,
            connection: SessionConnectionState::Connected,
            profile: "hyprland".to_string(),
            focused_output_id: None,
            outputs: vec![],
            workspaces: vec![],
            windows: vec![],
            capabilities: HashMap::new(),
            last_updated: 0,
        },
    };

    let snap = mock.get_snapshot().unwrap();
    assert_eq!(snap.revision, 10);

    let res_ok = mock
        .execute_intent(UserIntent {
            request_id: "1".to_string(),
            kind: "switch-workspace".to_string(),
            target: serde_json::json!({ "id": "2" }),
            parameters: serde_json::json!({}),
        })
        .unwrap();
    assert_eq!(res_ok.status, ActionStatus::Applied);

    let res_bad = mock
        .execute_intent(UserIntent {
            request_id: "2".to_string(),
            kind: "unsupported-op".to_string(),
            target: serde_json::json!({}),
            parameters: serde_json::json!({}),
        })
        .unwrap();
    assert_eq!(res_bad.status, ActionStatus::Unsupported);
}

#[test]
fn test_desktop_factory_detection() {
    use astral_plasma::infrastructure::desktop_factory::{
        detect_compositor, detect_profile, CompositorKind, EnvironmentProfile,
    };

    let comp = detect_compositor();
    let prof = detect_profile();
    assert!(comp == CompositorKind::KWin || comp == CompositorKind::Hyprland);
    assert!(
        prof == EnvironmentProfile::Kde
            || prof == EnvironmentProfile::Hyprland
            || prof == EnvironmentProfile::Omarchy
    );
}

