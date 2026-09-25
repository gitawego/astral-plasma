use crate::domain::ports::{DynResult, MetricsPort};

pub struct GetMetricsUseCase<T: MetricsPort> {
    port: T,
}

impl<T: MetricsPort> GetMetricsUseCase<T> {
    pub fn new(port: T) -> Self {
        Self { port }
    }

    pub fn execute_json(&self) -> DynResult<String> {
        let metrics = self.port.get_metrics()?;
        let val = serde_json::to_string(&metrics)?;
        Ok(val)
    }
}
