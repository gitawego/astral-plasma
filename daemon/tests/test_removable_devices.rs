use astral_plasma::domain::removable_devices::{
    parse_lsblk_removable_devices, resolve_device_for_query, select_primary_partition,
};

const LSBLK_SAMPLE: &str = r#"{
   "blockdevices": [
      {
         "name": "sda",
         "label": null,
         "mountpoints": [],
         "size": "119,2G",
         "model": "EAGET SSD Device",
         "rm": false,
         "type": "disk",
         "hotplug": true,
         "children": [
            {
               "name": "sda1",
               "label": "Ventoy",
               "mountpoints": [],
               "size": "119,2G",
               "model": null,
               "rm": false,
               "type": "part",
               "hotplug": true
            },{
               "name": "sda2",
               "label": "VTOYEFI",
               "mountpoints": [],
               "size": "32M",
               "model": null,
               "rm": false,
               "type": "part",
               "hotplug": true
            }
         ]
      },{
         "name": "zram0",
         "label": "zram0",
         "mountpoints": [
             "[SWAP]"
         ],
         "size": "31,1G",
         "model": null,
         "rm": false,
         "type": "disk",
         "hotplug": false
      },{
         "name": "nvme0n1",
         "label": null,
         "mountpoints": [],
         "size": "953,9G",
         "model": "SSD",
         "rm": false,
         "type": "disk",
         "hotplug": false,
         "children": [
            {
               "name": "nvme0n1p2",
               "label": null,
               "mountpoints": [
                   "/mnt/data"
               ],
               "size": "953,9G",
               "model": null,
               "rm": false,
               "type": "part",
               "hotplug": false
            }
         ]
      }
   ]
}"#;

#[test]
fn test_parse_lsblk_filters_only_hotplug_devices() {
    let devices = parse_lsblk_removable_devices(LSBLK_SAMPLE);
    assert_eq!(devices.len(), 1, "Only hotplug device sda should be parsed");

    let dev = &devices[0];
    assert_eq!(dev.device, "/dev/sda");
    assert_eq!(dev.model.as_deref(), Some("EAGET SSD Device"));
    assert_eq!(dev.partitions.len(), 2);

    let part1 = &dev.partitions[0];
    assert_eq!(part1.device, "/dev/sda1");
    assert_eq!(part1.label.as_deref(), Some("Ventoy"));
    assert_eq!(part1.is_mounted, false);

    let part2 = &dev.partitions[1];
    assert_eq!(part2.device, "/dev/sda2");
    assert_eq!(part2.label.as_deref(), Some("VTOYEFI"));
    assert_eq!(part2.is_mounted, false);
}

#[test]
fn test_select_primary_partition_prefers_data_over_efi() {
    let devices = parse_lsblk_removable_devices(LSBLK_SAMPLE);
    let dev = &devices[0];

    let primary = select_primary_partition(dev).expect("Primary partition must exist");
    assert_eq!(
        primary.device, "/dev/sda1",
        "Primary partition must be sda1 (Ventoy data partition), not EFI boot"
    );
    assert_eq!(primary.label.as_deref(), Some("Ventoy"));
}

#[test]
fn test_resolve_device_for_query() {
    let devices = parse_lsblk_removable_devices(LSBLK_SAMPLE);

    // Empty query matches first device
    let res = resolve_device_for_query("", &devices);
    assert!(res.is_some());
    assert_eq!(res.unwrap().device, "/dev/sda");

    // Query with device model
    let res = resolve_device_for_query("EAGET SSD Device has been connected", &devices);
    assert!(res.is_some());
    assert_eq!(res.unwrap().device, "/dev/sda");

    // Query with partition label
    let res = resolve_device_for_query("Ventoy", &devices);
    assert!(res.is_some());
    assert_eq!(res.unwrap().device, "/dev/sda");
}
