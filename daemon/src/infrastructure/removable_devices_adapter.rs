use crate::domain::ports::DynResult;
use crate::domain::removable_devices::{
    match_storage_device_for_notification, parse_lsblk_removable_devices, resolve_device_for_query, select_primary_partition,
    RemovableDevice,
};
use regex::Regex;
use std::process::Command;

pub struct RemovableDevicesAdapter;

impl RemovableDevicesAdapter {
    pub fn new() -> Self {
        Self
    }

    /// Queries the kernel block subsystem via lsblk to find all hotplug/removable storage devices.
    pub fn list_devices(&self) -> DynResult<Vec<RemovableDevice>> {
        let output = Command::new("lsblk")
            .args(["-J", "-o", "NAME,LABEL,MOUNTPOINTS,SIZE,MODEL,RM,TYPE,HOTPLUG"])
            .output()?;

        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(format!("lsblk failed: {}", err).into());
        }

        let json_str = String::from_utf8_lossy(&output.stdout);
        Ok(parse_lsblk_removable_devices(&json_str))
    }

    /// The attached storage device a notification text refers to, or `None` when
    /// it refers to non-storage hardware (mouse, keyboard, headset...).
    pub fn match_storage(&self, text: &str) -> DynResult<Option<RemovableDevice>> {
        let devices = self.list_devices()?;
        Ok(match_storage_device_for_notification(text, &devices).cloned())
    }

    /// Mounts the primary partition of the targeted (or first available) removable device
    /// using standard UDisks2 (udisksctl) and brings up the folder in the default file manager.
    pub fn mount_and_open(&self, target: Option<&str>) -> DynResult<String> {
        let devices = self.list_devices()?;
        if devices.is_empty() {
            return Err("No removable storage devices detected".into());
        }

        let dev = resolve_device_for_query(target.unwrap_or(""), &devices)
            .ok_or_else(|| "Could not match target removable device")?;

        let part = select_primary_partition(dev)
            .ok_or_else(|| "No accessible filesystem partitions found on removable device")?;

        let mountpoint = if part.is_mounted && !part.mountpoints.is_empty() {
            part.mountpoints[0].clone()
        } else {
            // Mount using udisksctl
            let out = Command::new("udisksctl")
                .args(["mount", "-b", &part.device])
                .output()?;

            let out_str = format!(
                "{}\n{}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );

            // Match "Mounted ... at /path" or "already mounted at /path"
            let re = Regex::new(r"(?:Mounted \S+ at|already mounted at)\s+(\S+)")?;
            if let Some(caps) = re.captures(&out_str) {
                let mp = caps.get(1).map(|m| m.as_str().trim_end_matches('.').to_string());
                mp.ok_or_else(|| "Failed to parse mount point from udisksctl")?
            } else if out.status.success() {
                // Query lsblk again to find updated mountpoint
                let updated = self.list_devices()?;
                let updated_dev = resolve_device_for_query(&dev.device, &updated);
                let updated_part = updated_dev.and_then(select_primary_partition);
                if let Some(up) = updated_part {
                    if let Some(m) = up.mountpoints.first() {
                        m.clone()
                    } else {
                        return Err(format!("udisksctl mounted but mountpoint unknown: {}", out_str).into());
                    }
                } else {
                    return Err(format!("udisksctl output: {}", out_str).into());
                }
            } else {
                return Err(format!("Failed to mount {}: {}", part.device, out_str).into());
            }
        };

        // Bring up the folder in the file manager using xdg-open / dolphin
        let _ = Command::new("xdg-open").arg(&mountpoint).spawn();

        Ok(mountpoint)
    }

    /// Safely unmounts all partitions and powers off / ejects the removable drive.
    pub fn safely_remove(&self, target: Option<&str>) -> DynResult<()> {
        let devices = self.list_devices()?;
        if devices.is_empty() {
            return Ok(());
        }

        let dev = resolve_device_for_query(target.unwrap_or(""), &devices)
            .ok_or_else(|| "Could not match target removable device")?;

        // 1. Unmount any mounted partitions
        for part in &dev.partitions {
            if part.is_mounted {
                let _ = Command::new("udisksctl")
                    .args(["unmount", "-b", &part.device])
                    .output();
            }
        }

        // 2. Power off drive (safely parks heads and cuts power)
        let po_res = Command::new("udisksctl")
            .args(["power-off", "-b", &dev.device])
            .output();

        // 3. Fall back to eject if power-off is unsupported
        if let Ok(po) = po_res {
            if !po.status.success() {
                let _ = Command::new("udisksctl")
                    .args(["eject", "-b", &dev.device])
                    .output();
            }
        }

        Ok(())
    }
}
