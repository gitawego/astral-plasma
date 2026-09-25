use crate::domain::model::{BatteryMetrics, Desktop, GpuMetrics, MemoryMetrics};
use regex::Regex;

pub fn parse_uptime_content(content: &str) -> String {
    if let Some(first_word) = content.split_whitespace().next() {
        if let Ok(secs) = first_word.parse::<f64>() {
            let total_secs = secs as u64;
            let hours = total_secs / 3600;
            let minutes = (total_secs % 3600) / 60;
            if hours > 0 {
                let h_unit = if hours == 1 { "hour" } else { "hours" };
                let m_unit = if minutes == 1 { "minute" } else { "minutes" };
                return format!("up {} {}, {} {}", hours, h_unit, minutes, m_unit);
            } else {
                let m_unit = if minutes == 1 { "minute" } else { "minutes" };
                return format!("up {} {}", minutes, m_unit);
            }
        }
    }
    "up 0 minutes".to_string()
}

pub fn parse_meminfo_content(content: &str) -> f64 {
    let mut total: f64 = 1.0;
    let mut avail: f64 = 0.0;

    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("MemTotal:") {
            if let Some(val_str) = rest.split_whitespace().next() {
                if let Ok(val) = val_str.parse::<f64>() {
                    total = val;
                }
            }
        } else if let Some(rest) = line.strip_prefix("MemAvailable:") {
            if let Some(val_str) = rest.split_whitespace().next() {
                if let Ok(val) = val_str.parse::<f64>() {
                    avail = val;
                }
            }
        }
    }

    if total > 0.0 {
        ((total - avail) / total).clamp(0.0, 1.0)
    } else {
        0.0
    }
}

pub fn parse_meminfo_detailed(content: &str) -> MemoryMetrics {
    let mut total_kb: u64 = 0;
    let mut avail_kb: u64 = 0;
    let mut cached_kb: u64 = 0;
    let mut swap_total_kb: u64 = 0;
    let mut swap_free_kb: u64 = 0;

    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("MemTotal:") {
            if let Some(val) = rest.split_whitespace().next().and_then(|v| v.parse::<u64>().ok()) {
                total_kb = val;
            }
        } else if let Some(rest) = line.strip_prefix("MemAvailable:") {
            if let Some(val) = rest.split_whitespace().next().and_then(|v| v.parse::<u64>().ok()) {
                avail_kb = val;
            }
        } else if let Some(rest) = line.strip_prefix("Cached:") {
            if let Some(val) = rest.split_whitespace().next().and_then(|v| v.parse::<u64>().ok()) {
                cached_kb = val;
            }
        } else if let Some(rest) = line.strip_prefix("SwapTotal:") {
            if let Some(val) = rest.split_whitespace().next().and_then(|v| v.parse::<u64>().ok()) {
                swap_total_kb = val;
            }
        } else if let Some(rest) = line.strip_prefix("SwapFree:") {
            if let Some(val) = rest.split_whitespace().next().and_then(|v| v.parse::<u64>().ok()) {
                swap_free_kb = val;
            }
        }
    }

    let total_bytes = total_kb * 1024;
    let available_bytes = avail_kb * 1024;
    let used_bytes = total_bytes.saturating_sub(available_bytes);
    let cached_bytes = cached_kb * 1024;
    let swap_total_bytes = swap_total_kb * 1024;
    let swap_free_bytes = swap_free_kb * 1024;
    let swap_used_bytes = swap_total_bytes.saturating_sub(swap_free_bytes);

    let usage = if total_bytes > 0 {
        (used_bytes as f64 / total_bytes as f64).clamp(0.0, 1.0)
    } else {
        0.0
    };

    let swap_usage = if swap_total_bytes > 0 {
        (swap_used_bytes as f64 / swap_total_bytes as f64).clamp(0.0, 1.0)
    } else {
        0.0
    };

    MemoryMetrics {
        usage,
        total_bytes,
        used_bytes,
        available_bytes,
        cached_bytes,
        swap_usage,
        swap_total_bytes,
        swap_used_bytes,
    }
}

pub fn parse_cpu_stat(content: &str) -> Option<(u64, u64)> {
    for line in content.lines() {
        if line.starts_with("cpu ") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 5 {
                let mut total: u64 = 0;
                for p in parts.iter().skip(1) {
                    if let Ok(val) = p.parse::<u64>() {
                        total += val;
                    }
                }
                let idle_val = parts[4].parse::<u64>().unwrap_or(0);
                let iowait_val = parts.get(5).and_then(|v| v.parse::<u64>().ok()).unwrap_or(0);
                let idle = idle_val + iowait_val;
                return Some((total, idle));
            }
        }
    }
    None
}

pub fn calculate_cpu_usage(prev: (u64, u64), curr: (u64, u64)) -> f64 {
    let delta_total = curr.0.saturating_sub(prev.0);
    let delta_idle = curr.1.saturating_sub(prev.1);
    if delta_total == 0 {
        0.0
    } else {
        let delta_active = delta_total.saturating_sub(delta_idle);
        (delta_active as f64 / delta_total as f64).clamp(0.0, 1.0)
    }
}

pub fn calculate_cpu_usage_with_state(stat_content: &str, state_path: &std::path::Path) -> f64 {
    let curr_cpu = match parse_cpu_stat(stat_content) {
        Some(c) => c,
        None => return 0.0,
    };

    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);

    let mut usage = 0.0;
    let mut valid_state = false;

    if let Ok(prev_data) = std::fs::read_to_string(state_path) {
        let parts: Vec<&str> = prev_data.split_whitespace().collect();
        if parts.len() >= 3 {
            if let (Ok(prev_total), Ok(prev_idle), Ok(prev_ts)) = (
                parts[0].parse::<u64>(),
                parts[1].parse::<u64>(),
                parts[2].parse::<u64>(),
            ) {
                if now_ms >= prev_ts && (now_ms - prev_ts) >= 50 && (now_ms - prev_ts) <= 15000 {
                    usage = calculate_cpu_usage((prev_total, prev_idle), curr_cpu);
                    valid_state = true;
                }
            }
        }
    }

    if !valid_state {
        if std::path::Path::new("/proc/stat").exists() {
            std::thread::sleep(std::time::Duration::from_millis(80));
            if let Ok(second_stat) = std::fs::read_to_string("/proc/stat") {
                if let Some(second_cpu) = parse_cpu_stat(&second_stat) {
                    usage = calculate_cpu_usage(curr_cpu, second_cpu);
                    let new_now = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_millis() as u64)
                        .unwrap_or(now_ms);
                    let _ = std::fs::write(state_path, format!("{} {} {}\n", second_cpu.0, second_cpu.1, new_now));
                    return usage;
                }
            }
        }
    }

    let _ = std::fs::write(state_path, format!("{} {} {}\n", curr_cpu.0, curr_cpu.1, now_ms));
    usage
}

pub fn parse_intel_gpu_freq(act_str: &str, min_str: &str, max_str: &str) -> f64 {
    let act = act_str.trim().parse::<f64>().unwrap_or(0.0);
    let min = min_str.trim().parse::<f64>().unwrap_or(0.0);
    let max = max_str.trim().parse::<f64>().unwrap_or(0.0);

    if max > min && act >= min {
        ((act - min) / (max - min)).clamp(0.0, 1.0)
    } else {
        0.0
    }
}

pub fn parse_cpu_model(content: &str) -> String {
    for line in content.lines() {
        if line.starts_with("model name") {
            if let Some((_, val)) = line.split_once(':') {
                return val.trim().to_string();
            }
        }
    }
    "Processor".to_string()
}

pub fn parse_cpu_freq_ghz(scaling_cur_freq: Option<&str>, cpuinfo_content: Option<&str>) -> f64 {
    if let Some(khz_str) = scaling_cur_freq {
        if let Ok(khz) = khz_str.trim().parse::<f64>() {
            if khz > 0.0 {
                return (khz / 1_000_000.0 * 100.0).round() / 100.0;
            }
        }
    }
    if let Some(cpuinfo) = cpuinfo_content {
        for line in cpuinfo.lines() {
            if line.starts_with("cpu MHz") {
                if let Some((_, val)) = line.split_once(':') {
                    if let Ok(mhz) = val.trim().parse::<f64>() {
                        return (mhz / 1000.0 * 100.0).round() / 100.0;
                    }
                }
            }
        }
    }
    0.0
}

pub fn parse_cpu_temp(content: &str) -> f64 {
    if let Ok(val) = content.trim().parse::<f64>() {
        let temp = if val > 1000.0 {
            val / 1000.0
        } else {
            val
        };
        return (temp * 10.0).round() / 10.0;
    }
    0.0
}

pub fn parse_loadavg(content: &str) -> (f64, u32, u32) {
    let parts: Vec<&str> = content.split_whitespace().collect();
    let load_1m = parts.first().and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0);
    let mut active = 0;
    let mut total = 0;
    if let Some(proc_str) = parts.get(3) {
        if let Some((act_str, tot_str)) = proc_str.split_once('/') {
            active = act_str.parse::<u32>().unwrap_or(0);
            total = tot_str.parse::<u32>().unwrap_or(0);
        }
    }
    (load_1m, active, total)
}

pub fn parse_battery_uevent(content: &str, profile: &str) -> BatteryMetrics {
    let mut capacity: u32 = 0;
    let mut status = String::from("Discharging");
    let mut voltage_now: f64 = 0.0;
    let mut current_now: f64 = 0.0;
    let mut power_now: f64 = 0.0;
    let mut charge_full: f64 = 0.0;
    let mut charge_full_design: f64 = 0.0;
    let mut energy_full: f64 = 0.0;
    let mut energy_full_design: f64 = 0.0;

    for line in content.lines() {
        if let Some((k, v)) = line.split_once('=') {
            match k.trim() {
                "POWER_SUPPLY_CAPACITY" => {
                    capacity = v.trim().parse::<u32>().unwrap_or(0);
                }
                "POWER_SUPPLY_STATUS" => {
                    status = v.trim().to_string();
                }
                "POWER_SUPPLY_VOLTAGE_NOW" => {
                    voltage_now = v.trim().parse::<f64>().unwrap_or(0.0);
                }
                "POWER_SUPPLY_CURRENT_NOW" => {
                    current_now = v.trim().parse::<f64>().unwrap_or(0.0);
                }
                "POWER_SUPPLY_POWER_NOW" => {
                    power_now = v.trim().parse::<f64>().unwrap_or(0.0);
                }
                "POWER_SUPPLY_CHARGE_FULL" => {
                    charge_full = v.trim().parse::<f64>().unwrap_or(0.0);
                }
                "POWER_SUPPLY_CHARGE_FULL_DESIGN" => {
                    charge_full_design = v.trim().parse::<f64>().unwrap_or(0.0);
                }
                "POWER_SUPPLY_ENERGY_FULL" => {
                    energy_full = v.trim().parse::<f64>().unwrap_or(0.0);
                }
                "POWER_SUPPLY_ENERGY_FULL_DESIGN" => {
                    energy_full_design = v.trim().parse::<f64>().unwrap_or(0.0);
                }
                _ => {}
            }
        }
    }

    let is_charging = status.eq_ignore_ascii_case("charging") || status.eq_ignore_ascii_case("full");
    let voltage_volts = if voltage_now > 0.0 { voltage_now / 1_000_000.0 } else { 0.0 };

    let power_watts = if power_now > 0.0 {
        power_now / 1_000_000.0
    } else if voltage_now > 0.0 && current_now > 0.0 {
        (voltage_now * current_now) / 1_000_000_000_000.0
    } else {
        0.0
    };

    let health_percent = if charge_full_design > 0.0 && charge_full > 0.0 {
        ((charge_full / charge_full_design) * 100.0).round().clamp(0.0, 100.0) as u32
    } else if energy_full_design > 0.0 && energy_full > 0.0 {
        ((energy_full / energy_full_design) * 100.0).round().clamp(0.0, 100.0) as u32
    } else {
        100
    };

    BatteryMetrics {
        percentage: capacity,
        is_charging,
        power_watts: (power_watts * 100.0).round() / 100.0,
        voltage_volts: (voltage_volts * 100.0).round() / 100.0,
        health_percent,
        profile: profile.to_string(),
        state: status,
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PciGpuDevice {
    pub slot: String,
    pub class: String,
    pub vendor: String,
    pub model: String,
    pub is_integrated: bool,
}

pub fn parse_lspci_vmm(content: &str) -> std::collections::HashMap<String, PciGpuDevice> {
    let mut map = std::collections::HashMap::new();
    let mut current_slot = String::new();
    let mut current_class = String::new();
    let mut current_vendor = String::new();
    let mut current_device = String::new();

    let flush = |map: &mut std::collections::HashMap<String, PciGpuDevice>,
                 slot: &mut String,
                 class: &mut String,
                 vendor: &mut String,
                 device: &mut String| {
        if !slot.is_empty() {
            let class_lower = class.to_lowercase();
            if class_lower.contains("vga") || class_lower.contains("3d") || class_lower.contains("display") {
                let is_integrated = slot.contains("00:02.0")
                    || device.to_lowercase().contains("onboard")
                    || (vendor.to_lowercase().contains("intel") && !device.to_lowercase().contains("arc"));
                map.insert(
                    slot.clone(),
                    PciGpuDevice {
                        slot: slot.clone(),
                        class: class.clone(),
                        vendor: vendor.clone(),
                        model: device.clone(),
                        is_integrated,
                    },
                );
            }
        }
        slot.clear();
        class.clear();
        vendor.clear();
        device.clear();
    };

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            flush(&mut map, &mut current_slot, &mut current_class, &mut current_vendor, &mut current_device);
            continue;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            let key = k.trim();
            let val = v.trim();
            match key {
                "Slot" => {
                    flush(&mut map, &mut current_slot, &mut current_class, &mut current_vendor, &mut current_device);
                    current_slot = val.to_string();
                }
                "Class" => current_class = val.to_string(),
                "Vendor" => current_vendor = val.to_string(),
                "Device" => current_device = val.to_string(),
                _ => {}
            }
        }
    }
    flush(&mut map, &mut current_slot, &mut current_class, &mut current_vendor, &mut current_device);
    map
}

pub fn parse_all_nvidia_gpus(content: &str) -> Vec<GpuMetrics> {
    let mut gpus = Vec::new();
    let mut idx = 0;

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let parts: Vec<&str> = line.split(',').map(|s| s.trim()).collect();
        if parts.len() >= 5 {
            let mut pci_slot = String::new();
            let model: String;
            let usage: f64;
            let temperature: f64;
            let mem_used_mb: u64;
            let mem_total_mb: u64;
            let clock_ghz: f64;

            if parts[0].contains(':') {
                // pci.bus_id, name, utilization.gpu, temperature.gpu, memory.used, memory.total, clocks.current.graphics
                let raw_slot = parts[0];
                if raw_slot.len() >= 12 && raw_slot.starts_with("0000") {
                    pci_slot = raw_slot[4..].to_string();
                } else {
                    pci_slot = raw_slot.to_string();
                }
                model = parts.get(1).unwrap_or(&"NVIDIA GPU").to_string();
                let usage_pct = parts.get(2).and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0);
                usage = (usage_pct / 100.0).clamp(0.0, 1.0);
                temperature = parts.get(3).and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0);
                mem_used_mb = parts.get(4).and_then(|v| v.parse::<u64>().ok()).unwrap_or(0);
                mem_total_mb = parts.get(5).and_then(|v| v.parse::<u64>().ok()).unwrap_or(0);
                let clock_mhz = parts.get(6).and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0);
                clock_ghz = (clock_mhz / 1000.0 * 100.0).round() / 100.0;
            } else {
                // Legacy query format: utilization, temp, mem_used, mem_total, model, clock
                let usage_pct = parts[0].parse::<f64>().unwrap_or(0.0);
                usage = (usage_pct / 100.0).clamp(0.0, 1.0);
                temperature = parts[1].parse::<f64>().unwrap_or(0.0);
                mem_used_mb = parts[2].parse::<u64>().unwrap_or(0);
                mem_total_mb = parts[3].parse::<u64>().unwrap_or(0);
                model = parts[4].to_string();
                let clock_mhz = parts.get(5).and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0);
                clock_ghz = (clock_mhz / 1000.0 * 100.0).round() / 100.0;
            }

            gpus.push(GpuMetrics {
                id: format!("gpu-{}", idx),
                index: idx,
                name: format!("GPU {}", idx),
                vendor: "NVIDIA".to_string(),
                model,
                gpu_type: "discrete".to_string(),
                driver: "nvidia".to_string(),
                pci_slot,
                usage,
                temperature,
                memory_used_bytes: mem_used_mb * 1024 * 1024,
                memory_total_bytes: mem_total_mb * 1024 * 1024,
                clock_ghz,
            });
            idx += 1;
        }
    }
    gpus
}

pub fn parse_amdgpu_metrics(
    busy_pct_str: Option<&str>,
    vram_used_str: Option<&str>,
    vram_total_str: Option<&str>,
    temp_milli_str: Option<&str>,
    freq_hz_str: Option<&str>,
) -> GpuMetrics {
    let usage = busy_pct_str
        .and_then(|s| s.trim().parse::<f64>().ok())
        .map(|pct| (pct / 100.0).clamp(0.0, 1.0))
        .unwrap_or(0.0);

    let memory_used_bytes = vram_used_str
        .and_then(|s| s.trim().parse::<u64>().ok())
        .unwrap_or(0);

    let memory_total_bytes = vram_total_str
        .and_then(|s| s.trim().parse::<u64>().ok())
        .unwrap_or(0);

    let temperature = temp_milli_str
        .and_then(|s| s.trim().parse::<f64>().ok())
        .map(|milli| if milli > 1000.0 { milli / 1000.0 } else { milli })
        .unwrap_or(0.0);

    let clock_ghz = freq_hz_str
        .and_then(|s| s.trim().parse::<f64>().ok())
        .map(|hz| {
            if hz > 1_000_000_000.0 {
                (hz / 1_000_000_000.0 * 100.0).round() / 100.0
            } else if hz > 1_000_000.0 {
                (hz / 1_000_000.0 / 1000.0 * 100.0).round() / 100.0
            } else {
                (hz / 1000.0 * 100.0).round() / 100.0
            }
        })
        .unwrap_or(0.0);

    GpuMetrics {
        vendor: "AMD".to_string(),
        driver: "amdgpu".to_string(),
        usage,
        temperature,
        memory_used_bytes,
        memory_total_bytes,
        clock_ghz,
        ..Default::default()
    }
}

pub fn parse_gpu_nvidia_csv(content: &str) -> Option<GpuMetrics> {
    parse_all_nvidia_gpus(content).into_iter().next()
}

pub fn parse_kwin_desktops(output: &str, current_id: &str) -> Vec<Desktop> {
    let re = Regex::new(r#"([0-9]+),\s*"([^"]+)",\s*"([^"]+)""#).unwrap();
    let mut desktops = Vec::new();

    for cap in re.captures_iter(output) {
        let index = cap[1].parse::<u32>().unwrap_or(0);
        let id = cap[2].to_string();
        let name = cap[3].to_string();
        let active = id == current_id;

        desktops.push(Desktop {
            index,
            id,
            name,
            active,
        });
    }

    desktops.sort_by_key(|d| d.index);

    if desktops.is_empty() {
        desktops.push(Desktop {
            index: 0,
            id: "default".to_string(),
            name: "Desktop 1".to_string(),
            active: true,
        });
    }

    desktops
}
