use crate::domain::model::{BatteryMetrics, CpuMetrics, GpuMetrics, SystemMetrics};
use crate::domain::ports::{DynResult, MetricsPort};
use crate::domain::sys_parser::{
    calculate_cpu_usage_with_state, parse_all_nvidia_gpus, parse_amdgpu_metrics, parse_battery_uevent,
    parse_cpu_freq_ghz, parse_cpu_model, parse_cpu_stat, parse_cpu_temp, parse_intel_gpu_freq,
    parse_loadavg, parse_lspci_vmm, parse_meminfo_detailed, parse_uptime_content,
};
use std::fs;
use std::process::Command;
use std::sync::Mutex;

pub struct ProcMetricsAdapter {
    prev_cpu: Mutex<Option<(u64, u64)>>,
}

impl ProcMetricsAdapter {
    pub fn new() -> Self {
        Self {
            prev_cpu: Mutex::new(None),
        }
    }
}

impl Default for ProcMetricsAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl MetricsPort for ProcMetricsAdapter {
    fn get_metrics(&self) -> DynResult<SystemMetrics> {
        let uptime_content = fs::read_to_string("/proc/uptime").unwrap_or_default();
        let meminfo_content = fs::read_to_string("/proc/meminfo").unwrap_or_default();
        let stat_content = fs::read_to_string("/proc/stat").unwrap_or_default();
        let cpuinfo_content = fs::read_to_string("/proc/cpuinfo").unwrap_or_default();
        let loadavg_content = fs::read_to_string("/proc/loadavg").unwrap_or_default();

        let uptime = parse_uptime_content(&uptime_content);
        let memory = parse_meminfo_detailed(&meminfo_content);
        let ram = memory.usage;

        // CPU calculations with state persistence for CLI invocation ticks
        let state_path = if std::path::Path::new("/dev/shm").exists() {
            std::path::PathBuf::from("/dev/shm/astral_cpu_stat")
        } else {
            std::env::temp_dir().join("astral_cpu_stat")
        };
        let cpu_usage = calculate_cpu_usage_with_state(&stat_content, &state_path);
        if let Some(curr_cpu) = parse_cpu_stat(&stat_content) {
            let mut prev_guard = self.prev_cpu.lock().unwrap();
            *prev_guard = Some(curr_cpu);
        }

        let cpu_model = parse_cpu_model(&cpuinfo_content);
        let scaling_freq_content = fs::read_to_string("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq").ok();
        let frequency_ghz = parse_cpu_freq_ghz(scaling_freq_content.as_deref(), Some(&cpuinfo_content));

        // CPU temperature: check thermal_zone3 (x86_pkg_temp) first, then thermal_zone0
        let temp_content = fs::read_to_string("/sys/class/thermal/thermal_zone3/temp")
            .or_else(|_| fs::read_to_string("/sys/class/thermal/thermal_zone0/temp"))
            .unwrap_or_default();
        let temperature = parse_cpu_temp(&temp_content);

        let (load_1m, _active_threads, threads) = parse_loadavg(&loadavg_content);

        // Process count from /proc
        let mut processes = 0;
        if let Ok(entries) = fs::read_dir("/proc") {
            for entry in entries.flatten() {
                if let Ok(name) = entry.file_name().into_string() {
                    if name.chars().all(|c| c.is_ascii_digit()) {
                        processes += 1;
                    }
                }
            }
        }

        let cpu = CpuMetrics {
            usage: cpu_usage,
            temperature,
            frequency_ghz,
            model: cpu_model,
            processes,
            threads,
            load_1m,
        };

        // Battery calculation
        let battery_uevent = fs::read_to_string("/sys/class/power_supply/BAT0/uevent")
            .or_else(|_| fs::read_to_string("/sys/class/power_supply/BAT1/uevent"))
            .unwrap_or_default();
        let profile = fs::read_to_string("/sys/firmware/acpi/platform_profile")
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|_| "balanced".to_string());
        let battery = if !battery_uevent.is_empty() {
            parse_battery_uevent(&battery_uevent, &profile)
        } else {
            BatteryMetrics {
                percentage: 100,
                is_charging: true,
                power_watts: 0.0,
                voltage_volts: 0.0,
                health_percent: 100,
                profile,
                state: "AC".to_string(),
            }
        };

        // Universal multi-GPU discovery and telemetry with PCI device topology cache
        let pci_cache_path = if std::path::Path::new("/dev/shm").exists() {
            std::path::PathBuf::from("/dev/shm/astral_pci_gpus")
        } else {
            std::env::temp_dir().join("astral_pci_gpus")
        };

        let pci_gpus = if let Ok(cached) = fs::read_to_string(&pci_cache_path) {
            if !cached.trim().is_empty() {
                parse_lspci_vmm(&cached)
            } else {
                fetch_and_cache_lspci(&pci_cache_path)
            }
        } else {
            fetch_and_cache_lspci(&pci_cache_path)
        };

        let mut discovered_gpus = Vec::new();

        // 1. Query NVIDIA GPUs via nvidia-smi
        if let Ok(output) = Command::new("nvidia-smi")
            .args([
                "--query-gpu=pci.bus_id,name,utilization.gpu,temperature.gpu,memory.used,memory.total,clocks.current.graphics",
                "--format=csv,noheader,nounits",
            ])
            .output()
        {
            if output.status.success() {
                let csv = String::from_utf8_lossy(&output.stdout);
                discovered_gpus.extend(parse_all_nvidia_gpus(&csv));
            }
        }

        // 2. Scan DRM cards (/sys/class/drm/cardX)
        if let Ok(drm_entries) = fs::read_dir("/sys/class/drm") {
            for entry in drm_entries.flatten() {
                let file_name = entry.file_name().to_string_lossy().to_string();
                if !file_name.starts_with("card") || file_name.contains('-') {
                    continue;
                }
                let card_num_str = &file_name[4..];
                if card_num_str.parse::<u32>().is_err() {
                    continue;
                }

                let card_path = entry.path();
                let device_path = card_path.join("device");
                if !device_path.exists() {
                    continue;
                }

                let uevent = fs::read_to_string(device_path.join("uevent")).unwrap_or_default();
                let mut pci_slot = String::new();
                let mut driver = String::new();
                for line in uevent.lines() {
                    if let Some((k, v)) = line.split_once('=') {
                        match k.trim() {
                            "PCI_SLOT_NAME" => pci_slot = v.trim().to_string(),
                            "DRIVER" => driver = v.trim().to_string(),
                            _ => {}
                        }
                    }
                }

                // If already parsed via nvidia-smi (matching PCI slot), skip duplicate
                if driver == "nvidia" && discovered_gpus.iter().any(|g| !g.pci_slot.is_empty() && g.pci_slot == pci_slot) {
                    continue;
                }

                let pci_info = pci_gpus.get(&pci_slot);
                let model = pci_info
                    .map(|p| p.model.clone())
                    .unwrap_or_else(|| {
                        if driver == "i915" || driver == "xe" {
                            "Intel Graphics".to_string()
                        } else if driver == "amdgpu" || driver == "radeon" {
                            "AMD Radeon Graphics".to_string()
                        } else {
                            "Graphics Device".to_string()
                        }
                    });

                let is_integrated = pci_info.map(|p| p.is_integrated).unwrap_or_else(|| {
                    pci_slot.contains("00:02.0") || driver == "i915" || driver == "xe"
                });

                if driver == "i915" || driver == "xe" {
                    // Intel DRM telemetry
                    let act_str = fs::read_to_string(card_path.join("gt_act_freq_mhz"))
                        .or_else(|_| fs::read_to_string(card_path.join("gt/gt0/rps_act_freq_mhz")))
                        .unwrap_or_default();
                    let min_str = fs::read_to_string(card_path.join("gt_min_freq_mhz"))
                        .or_else(|_| fs::read_to_string(card_path.join("gt/gt0/rps_min_freq_mhz")))
                        .unwrap_or_default();
                    let max_str = fs::read_to_string(card_path.join("gt_max_freq_mhz"))
                        .or_else(|_| fs::read_to_string(card_path.join("gt/gt0/rps_max_freq_mhz")))
                        .unwrap_or_default();

                    let usage = parse_intel_gpu_freq(&act_str, &min_str, &max_str);
                    let clock_ghz = act_str.trim().parse::<f64>().ok().map(|mhz| (mhz / 1000.0 * 100.0).round() / 100.0).unwrap_or(0.0);

                    // Intel Arc discrete memory or shared memory
                    let lmem_total = fs::read_to_string(card_path.join("lmem_total_bytes"))
                        .ok()
                        .and_then(|s| s.trim().parse::<u64>().ok())
                        .unwrap_or(0);
                    let lmem_avail = fs::read_to_string(card_path.join("lmem_avail_bytes"))
                        .ok()
                        .and_then(|s| s.trim().parse::<u64>().ok())
                        .unwrap_or(0);
                    let mem_used = if lmem_total > lmem_avail { lmem_total - lmem_avail } else { 0 };

                    discovered_gpus.push(GpuMetrics {
                        id: format!("gpu-{}", file_name),
                        index: 0,
                        name: "GPU".to_string(),
                        vendor: "Intel".to_string(),
                        model,
                        gpu_type: if is_integrated { "integrated".to_string() } else { "discrete".to_string() },
                        driver,
                        pci_slot,
                        usage,
                        temperature,
                        memory_used_bytes: mem_used,
                        memory_total_bytes: lmem_total,
                        clock_ghz,
                    });
                } else if driver == "amdgpu" || driver == "radeon" {
                    // AMD DRM telemetry
                    let busy_pct = fs::read_to_string(device_path.join("gpu_busy_percent")).ok();
                    let vram_used = fs::read_to_string(device_path.join("mem_info_vram_used")).ok();
                    let vram_total = fs::read_to_string(device_path.join("mem_info_vram_total")).ok();

                    // Find hwmon for amdgpu
                    let mut temp_str = None;
                    let mut freq_str = None;
                    if let Ok(hwmon_entries) = fs::read_dir(device_path.join("hwmon")) {
                        for h_entry in hwmon_entries.flatten() {
                            let h_path = h_entry.path();
                            if let Ok(t) = fs::read_to_string(h_path.join("temp1_input")) {
                                temp_str = Some(t);
                            }
                            if let Ok(f) = fs::read_to_string(h_path.join("freq1_input")) {
                                freq_str = Some(f);
                            }
                            break;
                        }
                    }

                    let mut amd_metric = parse_amdgpu_metrics(
                        busy_pct.as_deref(),
                        vram_used.as_deref(),
                        vram_total.as_deref(),
                        temp_str.as_deref(),
                        freq_str.as_deref(),
                    );
                    amd_metric.id = format!("gpu-{}", file_name);
                    amd_metric.model = model;
                    amd_metric.gpu_type = if is_integrated { "integrated".to_string() } else { "discrete".to_string() };
                    amd_metric.driver = driver;
                    amd_metric.pci_slot = pci_slot;
                    discovered_gpus.push(amd_metric);
                }
            }
        }

        // Sort: integrated GPUs first, then discrete GPUs by PCI slot
        discovered_gpus.sort_by(|a, b| {
            let a_is_int = a.gpu_type == "integrated";
            let b_is_int = b.gpu_type == "integrated";
            match (a_is_int, b_is_int) {
                (true, false) => std::cmp::Ordering::Less,
                (false, true) => std::cmp::Ordering::Greater,
                _ => a.pci_slot.cmp(&b.pci_slot),
            }
        });

        // Re-index cleanly
        for (i, g) in discovered_gpus.iter_mut().enumerate() {
            g.index = i as u32;
            g.id = format!("gpu-{}", i);
            g.name = format!("GPU {}", i);
        }

        // Backwards compatibility primary GPU:
        // Pick active discrete GPU if in use, else primary GPU, or default
        let primary_gpu = discovered_gpus
            .iter()
            .find(|g| g.gpu_type == "discrete" && g.usage > 0.05)
            .or_else(|| discovered_gpus.iter().find(|g| g.gpu_type == "discrete"))
            .or_else(|| discovered_gpus.first())
            .cloned()
            .unwrap_or_else(|| GpuMetrics {
                model: "Integrated Graphics".to_string(),
                ..Default::default()
            });

        Ok(SystemMetrics {
            uptime,
            ram,
            cpu,
            memory,
            gpu: primary_gpu,
            gpus: discovered_gpus,
            battery,
        })
    }
}

fn fetch_and_cache_lspci(cache_path: &std::path::Path) -> std::collections::HashMap<String, crate::domain::sys_parser::PciGpuDevice> {
    if let Ok(output) = Command::new("lspci").args(["-vmm", "-D"]).output() {
        if output.status.success() {
            let s = String::from_utf8_lossy(&output.stdout).to_string();
            let _ = fs::write(cache_path, &s);
            return parse_lspci_vmm(&s);
        }
    }
    std::collections::HashMap::new()
}

