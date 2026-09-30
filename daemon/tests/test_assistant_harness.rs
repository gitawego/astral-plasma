use astral_plasma::application::assistant_service::AssistantService;
use astral_plasma::domain::assistant::ToolCallProposal;
use astral_plasma::infrastructure::assistant_harness::runtime_provisioner::RuntimeProvisioner;
use astral_plasma::infrastructure::crash_monitor::CrashMonitor;

#[test]
fn test_harness_discovery_and_skills() {
    let service = AssistantService::new();
    let harnesses = service.list_harnesses();
    assert!(!harnesses.is_empty(), "Must list available harnesses");

    let pi_harness = harnesses.iter().find(|h| h.id == "pi");
    assert!(pi_harness.is_some(), "Pi harness must be reported");

    let skills = service.list_skills();
    assert!(!skills.is_empty(), "Must discover predefined skills");

    let has_sys_diag = skills.iter().any(|s| s.name == "system-diagnostics");
    assert!(has_sys_diag, "Must discover system-diagnostics skill");
}

#[test]
fn test_runtime_provisioning_status() {
    let status = RuntimeProvisioner::get_status();
    // On the development host, pi is present and packages were installed
    assert!(status.pi_executable.is_some(), "Pi should be detected on host");
    assert!(status.has_mcp_support, "pi built-in MCP should be available");
    assert!(status.has_subagents, "pi-subagents should be installed");
}

#[test]
fn test_tool_safety_classification() {
    // Read-only commands are safe
    let (d1, s1) = ToolCallProposal::assess_safety("journalctl -n 20");
    assert!(!d1 && !s1);

    // Destructive or sudo commands require approval
    let (d2, s2) = ToolCallProposal::assess_safety("sudo pacman -Syu");
    assert!(d2 && s2);

    let (d3, s3) = ToolCallProposal::assess_safety("kill -9 9999");
    assert!(d3 && !s3);
}

#[test]
fn test_crash_monitor_scan() {
    let crashes = CrashMonitor::scan_recent_crashes(3);
    // Scan runs without panicking
    println!("Detected {} crash incidents", crashes.len());
}

#[test]
fn test_provider_and_model_listing() {
    let service = AssistantService::new();
    let providers = service.list_providers();
    assert!(!providers.is_empty(), "Must return discovered providers");

    let opencode = providers.iter().find(|p| p.id == "opencode-go");
    assert!(opencode.is_some(), "Must list opencode-go provider");

    let gemini = providers.iter().find(|p| p.id == "gemini");
    assert!(gemini.is_some(), "Must list gemini provider");
    assert!(!gemini.unwrap().models.is_empty(), "Gemini must have models listed");

    let claude = providers.iter().find(|p| p.id == "claude");
    assert!(claude.is_some(), "Claude must have models listed");
}
