use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemovablePartition {
    pub device: String,
    pub name: String,
    pub label: Option<String>,
    pub size: String,
    pub mountpoints: Vec<String>,
    pub is_mounted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemovableDevice {
    pub device: String,
    pub name: String,
    pub model: Option<String>,
    pub size: String,
    pub is_hotplug: bool,
    pub partitions: Vec<RemovablePartition>,
}

#[derive(Debug, Deserialize)]
struct LsblkBlockDevice {
    name: String,
    #[serde(default)]
    label: Option<String>,
    #[serde(default)]
    mountpoints: Vec<String>,
    #[serde(default)]
    size: Option<String>,
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    rm: Option<bool>,
    #[serde(default)]
    #[serde(rename = "type")]
    device_type: Option<String>,
    #[serde(default)]
    hotplug: Option<bool>,
    #[serde(default)]
    children: Vec<LsblkBlockDevice>,
}

#[derive(Debug, Deserialize)]
struct LsblkRoot {
    #[serde(default)]
    blockdevices: Vec<LsblkBlockDevice>,
}

/// Parses the JSON output of `lsblk -J -o NAME,LABEL,MOUNTPOINTS,SIZE,MODEL,RM,TYPE,HOTPLUG`
/// and filters for hotplug/removable media devices and their partitions.
pub fn parse_lsblk_removable_devices(json_str: &str) -> Vec<RemovableDevice> {
    let root: LsblkRoot = match serde_json::from_str(json_str) {
        Ok(r) => r,
        Err(_) => return Vec::new(),
    };

    let mut result = Vec::new();

    for dev in root.blockdevices {
        let is_hotplug = dev.hotplug.unwrap_or(false);
        let is_rm = dev.rm.unwrap_or(false);
        let dev_type = dev.device_type.as_deref().unwrap_or("");

        // Skip non-disk devices, loopback, zram, swap
        if dev.name.starts_with("loop") || dev.name.starts_with("zram") || dev_type == "rom" {
            continue;
        }

        // Must be marked hotplug or removable
        if !is_hotplug && !is_rm {
            continue;
        }

        let full_dev_path = if dev.name.starts_with('/') {
            dev.name.clone()
        } else {
            format!("/dev/{}", dev.name)
        };

        let mut partitions = Vec::new();

        if dev.children.is_empty() {
            // Unpartitioned block device with filesystem directly on it
            let mountpoints: Vec<String> = dev
                .mountpoints
                .into_iter()
                .filter(|m| !m.is_empty() && m != "[SWAP]")
                .collect();
            let is_mounted = !mountpoints.is_empty();

            partitions.push(RemovablePartition {
                device: full_dev_path.clone(),
                name: dev.name.clone(),
                label: dev.label,
                size: dev.size.clone().unwrap_or_default(),
                mountpoints,
                is_mounted,
            });
        } else {
            for child in dev.children {
                let child_type = child.device_type.as_deref().unwrap_or("");
                if child_type == "part" || child_type.is_empty() {
                    let child_path = if child.name.starts_with('/') {
                        child.name.clone()
                    } else {
                        format!("/dev/{}", child.name)
                    };

                    let mountpoints: Vec<String> = child
                        .mountpoints
                        .into_iter()
                        .filter(|m| !m.is_empty() && m != "[SWAP]")
                        .collect();
                    let is_mounted = !mountpoints.is_empty();

                    partitions.push(RemovablePartition {
                        device: child_path,
                        name: child.name,
                        label: child.label,
                        size: child.size.unwrap_or_default(),
                        mountpoints,
                        is_mounted,
                    });
                }
            }
        }

        result.push(RemovableDevice {
            device: full_dev_path,
            name: dev.name,
            model: dev.model,
            size: dev.size.unwrap_or_default(),
            is_hotplug: is_hotplug || is_rm,
            partitions,
        });
    }

    result
}

/// Selects the primary data partition for a removable device.
/// Prioritizes:
/// 1. Mounted partition (if already mounted)
/// 2. Non-EFI partition with a filesystem / user label
/// 3. Largest partition by size
pub fn select_primary_partition<'a>(device: &'a RemovableDevice) -> Option<&'a RemovablePartition> {
    if device.partitions.is_empty() {
        return None;
    }

    // 1. If already mounted, prefer the mounted partition
    if let Some(mounted) = device.partitions.iter().find(|p| p.is_mounted) {
        return Some(mounted);
    }

    // 2. Filter out EFI / boot partitions if other partitions exist
    let non_efi: Vec<&RemovablePartition> = device
        .partitions
        .iter()
        .filter(|p| {
            let label = p.label.as_deref().unwrap_or("").to_uppercase();
            !label.contains("EFI") && !label.contains("BOOT")
        })
        .collect();

    if let Some(&first_non_efi) = non_efi.first() {
        return Some(first_non_efi);
    }

    // Fall back to first partition
    device.partitions.first()
}

/// Matches a removable device against an optional query string (e.g. from notification text or body).
/// If query is empty or matches multiple, returns the first removable device.
pub fn resolve_device_for_query<'a>(
    query: &str,
    devices: &'a [RemovableDevice],
) -> Option<&'a RemovableDevice> {
    if devices.is_empty() {
        return None;
    }

    let q = query.trim().to_lowercase();
    if q.is_empty() {
        return devices.first();
    }

    for dev in devices {
        if dev.device.to_lowercase().contains(&q) || dev.name.to_lowercase().contains(&q) {
            return Some(dev);
        }
        if let Some(ref model) = dev.model {
            if q.contains(&model.to_lowercase()) || model.to_lowercase().contains(&q) {
                return Some(dev);
            }
        }
        for part in &dev.partitions {
            if let Some(ref label) = part.label {
                if q.contains(&label.to_lowercase()) || label.to_lowercase().contains(&q) {
                    return Some(dev);
                }
            }
        }
    }

    devices.first()
}

/// Strictly matches a device-connected notification against the attached
/// removable *storage* devices.
///
/// Unlike [`resolve_device_for_query`] there is no fallback to the first
/// device: a "USB Device Detected" notification for a mouse or keyboard names
/// hardware with no block device, and must resolve to nothing so that no
/// storage actions (open in file manager, safely remove) are offered for it.
/// The kernel's block layer, not the notification wording, is the ground truth.
pub fn match_storage_device_for_notification<'a>(
    text: &str,
    devices: &'a [RemovableDevice],
) -> Option<&'a RemovableDevice> {
    let q = text.trim().to_lowercase();
    if q.is_empty() {
        return None;
    }
    devices.iter().find(|dev| {
        let named = |s: &str| {
            let s = s.trim().to_lowercase();
            !s.is_empty() && q.contains(&s)
        };
        dev.model.as_deref().is_some_and(named)
            || named(&dev.device)
            || dev.partitions.iter().any(|p| p.label.as_deref().is_some_and(named))
    })
}
