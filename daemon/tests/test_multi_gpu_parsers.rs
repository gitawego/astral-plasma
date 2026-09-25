use astral_plasma::domain::sys_parser::{
    parse_all_nvidia_gpus, parse_amdgpu_metrics, parse_lspci_vmm,
};

#[test]
fn test_parse_lspci_vmm_multi_gpu() {
    let output = r#"
Slot:	0000:00:00.0
Class:	Host bridge
Vendor:	Intel Corporation
Device:	Device 4637

Slot:	0000:00:02.0
Class:	VGA compatible controller
Vendor:	Intel Corporation
Device:	Alder Lake-HX GT1 [UHD Graphics 770]
SVendor:	AIstone Global Limited
SDevice:	Device 1274
Rev:	0c

Slot:	0000:01:00.0
Class:	VGA compatible controller
Vendor:	NVIDIA Corporation
Device:	AD107M [GeForce RTX 4060 Max-Q / Mobile]
SVendor:	AIstone Global Limited
SDevice:	Device 1274
Rev:	a1

Slot:	0000:03:00.0
Class:	3D controller
Vendor:	Advanced Micro Devices, Inc. [AMD/ATI]
Device:	Navi 33 [Radeon RX 7600/7600 XT / 7600M XT]
Rev:	c1
"#;

    let gpus = parse_lspci_vmm(output);
    assert_eq!(gpus.len(), 3);

    let intel = gpus.get("0000:00:02.0").expect("Intel GPU must be parsed");
    assert_eq!(intel.vendor, "Intel Corporation");
    assert_eq!(intel.model, "Alder Lake-HX GT1 [UHD Graphics 770]");
    assert!(intel.is_integrated);

    let nvidia = gpus.get("0000:01:00.0").expect("NVIDIA GPU must be parsed");
    assert_eq!(nvidia.vendor, "NVIDIA Corporation");
    assert_eq!(nvidia.model, "AD107M [GeForce RTX 4060 Max-Q / Mobile]");
    assert!(!nvidia.is_integrated);

    let amd = gpus.get("0000:03:00.0").expect("AMD GPU must be parsed");
    assert_eq!(amd.vendor, "Advanced Micro Devices, Inc. [AMD/ATI]");
    assert_eq!(amd.model, "Navi 33 [Radeon RX 7600/7600 XT / 7600M XT]");
    assert!(!amd.is_integrated);
}

#[test]
fn test_parse_all_nvidia_gpus_multi_line() {
    let csv = r#"
00000000:01:00.0, NVIDIA GeForce RTX 4060 Laptop GPU, 42, 58, 2048, 8188, 1450
00000000:02:00.0, NVIDIA RTX A2000, 15, 45, 512, 4096, 900
"#;

    let gpus = parse_all_nvidia_gpus(csv);
    assert_eq!(gpus.len(), 2);

    let gpu0 = &gpus[0];
    assert_eq!(gpu0.index, 0);
    assert_eq!(gpu0.name, "GPU 0");
    assert_eq!(gpu0.vendor, "NVIDIA");
    assert_eq!(gpu0.model, "NVIDIA GeForce RTX 4060 Laptop GPU");
    assert_eq!(gpu0.gpu_type, "discrete");
    assert_eq!(gpu0.pci_slot, "0000:01:00.0");
    assert!((gpu0.usage - 0.42).abs() < 1e-4);
    assert_eq!(gpu0.temperature, 58.0);
    assert_eq!(gpu0.memory_used_bytes, 2048 * 1024 * 1024);
    assert_eq!(gpu0.memory_total_bytes, 8188 * 1024 * 1024);
    assert_eq!(gpu0.clock_ghz, 1.45);

    let gpu1 = &gpus[1];
    assert_eq!(gpu1.index, 1);
    assert_eq!(gpu1.name, "GPU 1");
    assert_eq!(gpu1.vendor, "NVIDIA");
    assert_eq!(gpu1.model, "NVIDIA RTX A2000");
    assert_eq!(gpu1.gpu_type, "discrete");
    assert_eq!(gpu1.pci_slot, "0000:02:00.0");
    assert!((gpu1.usage - 0.15).abs() < 1e-4);
    assert_eq!(gpu1.temperature, 45.0);
    assert_eq!(gpu1.memory_used_bytes, 512 * 1024 * 1024);
    assert_eq!(gpu1.memory_total_bytes, 4096 * 1024 * 1024);
    assert_eq!(gpu1.clock_ghz, 0.90);
}

#[test]
fn test_parse_amdgpu_metrics_direct() {
    let busy_pct = "35\n";
    let vram_used = "1073741824\n"; // 1 GiB
    let vram_total = "8589934592\n"; // 8 GiB
    let temp_milli = "48000\n"; // 48.0 °C
    let freq_hz = "1200000000\n"; // 1.2 GHz

    let parsed = parse_amdgpu_metrics(
        Some(busy_pct),
        Some(vram_used),
        Some(vram_total),
        Some(temp_milli),
        Some(freq_hz),
    );

    assert_eq!(parsed.usage, 0.35);
    assert_eq!(parsed.temperature, 48.0);
    assert_eq!(parsed.memory_used_bytes, 1073741824);
    assert_eq!(parsed.memory_total_bytes, 8589934592);
    assert_eq!(parsed.clock_ghz, 1.20);
}
