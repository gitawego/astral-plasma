use astral_plasma::domain::sys_parser::{
    calculate_cpu_usage, parse_battery_uevent, parse_cpu_freq_ghz, parse_cpu_model,
    parse_cpu_stat, parse_cpu_temp, parse_gpu_nvidia_csv, parse_loadavg, parse_meminfo_detailed,
    parse_uptime_content,
};

#[test]
fn test_parse_uptime() {
    assert_eq!(parse_uptime_content("3660.12 12345.67"), "up 1 hour, 1 minute");
    assert_eq!(parse_uptime_content("7325.0 12345.0"), "up 2 hours, 2 minutes");
    assert_eq!(parse_uptime_content("120.0 500.0"), "up 2 minutes");
    assert_eq!(parse_uptime_content(""), "up 0 minutes");
}

#[test]
fn test_parse_meminfo_detailed() {
    let meminfo = r#"MemTotal:       32575400 kB
MemFree:         5468916 kB
MemAvailable:   15332048 kB
Buffers:          135272 kB
Cached:         11642912 kB
SwapTotal:      48303096 kB
SwapFree:       47929152 kB
"#;
    let metrics = parse_meminfo_detailed(meminfo);
    assert_eq!(metrics.total_bytes, 32575400 * 1024);
    assert_eq!(metrics.available_bytes, 15332048 * 1024);
    assert_eq!(metrics.used_bytes, (32575400 - 15332048) * 1024);
    assert_eq!(metrics.cached_bytes, 11642912 * 1024);
    assert_eq!(metrics.swap_total_bytes, 48303096 * 1024);
    assert_eq!(metrics.swap_used_bytes, (48303096 - 47929152) * 1024);
    assert!((metrics.usage - (32575400.0 - 15332048.0) / 32575400.0).abs() < 0.001);
    assert!((metrics.swap_usage - (48303096.0 - 47929152.0) / 48303096.0).abs() < 0.001);
}

#[test]
fn test_parse_cpu_stat_and_usage() {
    let stat1 = "cpu  100 20 30 500 10 5 2 0 0 0\ncpu0 50 10 15 250 5 2 1 0 0 0\n";
    let (total1, idle1) = parse_cpu_stat(stat1).expect("failed to parse stat1");
    // total = 100+20+30+500+10+5+2+0+0+0 = 667
    // idle = 500 (idle) + 10 (iowait) = 510
    assert_eq!(total1, 667);
    assert_eq!(idle1, 510);

    let stat2 = "cpu  150 20 50 530 10 5 2 0 0 0\n";
    let (total2, idle2) = parse_cpu_stat(stat2).expect("failed to parse stat2");
    // total = 150+20+50+530+10+5+2 = 767. delta_total = 100
    // idle = 530 + 10 = 540. delta_idle = 30
    // active delta = 70. usage = 70 / 100 = 0.70
    assert_eq!(total2, 767);
    assert_eq!(idle2, 540);

    let usage = calculate_cpu_usage((total1, idle1), (total2, idle2));
    assert!((usage - 0.70).abs() < 0.001);
}

#[test]
fn test_parse_cpu_model() {
    let cpuinfo = r#"processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 151
model name	: 12th Gen Intel(R) Core(TM) i9-12900HX
stepping	: 2
"#;
    assert_eq!(
        parse_cpu_model(cpuinfo),
        "12th Gen Intel(R) Core(TM) i9-12900HX"
    );
}

#[test]
fn test_parse_cpu_freq_ghz() {
    assert!((parse_cpu_freq_ghz(Some("3503194"), None) - 3.503).abs() < 0.01);
    let cpuinfo = "processor : 0\ncpu MHz : 2400.500\n";
    assert!((parse_cpu_freq_ghz(None, Some(cpuinfo)) - 2.400).abs() < 0.01);
}

#[test]
fn test_parse_cpu_temp() {
    assert!((parse_cpu_temp("74000\n") - 74.0).abs() < 0.1);
    assert!((parse_cpu_temp("65.5\n") - 65.5).abs() < 0.1);
}

#[test]
fn test_parse_loadavg() {
    let loadavg = "5.27 5.22 4.70 8/2635 2760223\n";
    let (load_1m, active, total) = parse_loadavg(loadavg);
    assert!((load_1m - 5.27).abs() < 0.001);
    assert_eq!(active, 8);
    assert_eq!(total, 2635);
}

#[test]
fn test_parse_battery_uevent() {
    let uevent = r#"POWER_SUPPLY_NAME=BAT0
POWER_SUPPLY_TYPE=Battery
POWER_SUPPLY_STATUS=Discharging
POWER_SUPPLY_VOLTAGE_NOW=12010000
POWER_SUPPLY_CURRENT_NOW=1500000
POWER_SUPPLY_CHARGE_FULL_DESIGN=4100000
POWER_SUPPLY_CHARGE_FULL=4000000
POWER_SUPPLY_CHARGE_NOW=3000000
POWER_SUPPLY_CAPACITY=75
"#;
    let bat = parse_battery_uevent(uevent, "balanced");
    assert_eq!(bat.percentage, 75);
    assert!(!bat.is_charging);
    assert_eq!(bat.state, "Discharging");
    assert_eq!(bat.profile, "balanced");
    assert!((bat.voltage_volts - 12.01).abs() < 0.01);
    // power_watts: (12010000 * 1500000) / 10^12 = 18.015 W
    assert!((bat.power_watts - 18.015).abs() < 0.05);
    // health: 4000000 / 4100000 * 100 = 97.56% -> rounds to 98%
    assert_eq!(bat.health_percent, 98);
}

#[test]
fn test_parse_gpu_nvidia_csv() {
    let csv = "15, 52, 1024, 8188, NVIDIA GeForce RTX 4060 Laptop GPU, 1425\n";
    let gpu = parse_gpu_nvidia_csv(csv).expect("failed to parse gpu csv");
    assert!((gpu.usage - 0.15).abs() < 0.001);
    assert!((gpu.temperature - 52.0).abs() < 0.1);
    assert_eq!(gpu.memory_used_bytes, 1024 * 1024 * 1024);
    assert_eq!(gpu.memory_total_bytes, 8188 * 1024 * 1024);
    assert_eq!(gpu.model, "NVIDIA GeForce RTX 4060 Laptop GPU");
    assert!((gpu.clock_ghz - 1.425).abs() < 0.01);
}

#[test]
fn test_parse_intel_gpu_freq() {
    use astral_plasma::domain::sys_parser::parse_intel_gpu_freq;
    // act=1150, min=300, max=1550 -> (1150-300)/(1550-300) = 850/1250 = 0.68
    let usage = parse_intel_gpu_freq("1150\n", "300\n", "1550\n");
    assert!((usage - 0.68).abs() < 0.01);

    // act=300 -> 0.0
    let idle = parse_intel_gpu_freq("300\n", "300\n", "1550\n");
    assert_eq!(idle, 0.0);

    // act=1550 -> 1.0
    let full = parse_intel_gpu_freq("1550\n", "300\n", "1550\n");
    assert_eq!(full, 1.0);
}

#[test]
fn test_calculate_cpu_usage_with_state() {
    use astral_plasma::domain::sys_parser::calculate_cpu_usage_with_state;
    let temp_dir = std::env::temp_dir();
    let state_file = temp_dir.join(format!("test_cpu_state_{}.txt", std::process::id()));

    // Write a mock previous state: 1000 total, 800 idle, timestamp 1000ms ago
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64;
    let prev_ts = now.saturating_sub(1000);
    std::fs::write(&state_file, format!("1000 800 {}\n", prev_ts)).unwrap();

    // Now current stat has total 1200, idle 900 (delta total = 200, delta idle = 100, usage = 100/200 = 0.50)
    let stat = "cpu  150 50 100 900 0 0 0 0 0 0\n";
    let usage = calculate_cpu_usage_with_state(stat, &state_file);
    assert!((usage - 0.50).abs() < 0.01);

    // Clean up
    let _ = std::fs::remove_file(state_file);
}

