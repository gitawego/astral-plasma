use crate::domain::ports::{DynResult, MetricsPort};
use serde_json::json;

pub struct GetMetricsUseCase<T: MetricsPort> {
    port: T,
}

impl<T: MetricsPort> GetMetricsUseCase<T> {
    pub fn new(port: T) -> Self {
        Self { port }
    }

    pub fn execute_json(&self) -> DynResult<String> {
        let metrics = self.port.get_metrics()?;
        let val = json!({
            "uptime": metrics.uptime,
            "ram": metrics.ram
        });
        Ok(val.to_string())
    }
}
