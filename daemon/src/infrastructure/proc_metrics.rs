use crate::domain::model::SystemMetrics;
use crate::domain::ports::{DynResult, MetricsPort};
use crate::domain::sys_parser::{parse_meminfo_content, parse_uptime_content};
use std::fs;

pub struct ProcMetricsAdapter;

impl ProcMetricsAdapter {
    pub fn new() -> Self {
        Self
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

        let uptime = parse_uptime_content(&uptime_content);
        let ram = parse_meminfo_content(&meminfo_content);

        Ok(SystemMetrics { uptime, ram })
    }
}
