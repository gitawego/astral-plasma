use crate::domain::ai_quota::AiQuotaSnapshot;
use crate::domain::ports::DynResult;
use crate::infrastructure::ai_quota_adapter::AiQuotaAdapter;
use std::sync::Arc;

pub struct AiQuotaUseCase {
    adapter: Arc<AiQuotaAdapter>,
}

impl Default for AiQuotaUseCase {
    fn default() -> Self {
        Self {
            adapter: Arc::new(AiQuotaAdapter::new()),
        }
    }
}

impl AiQuotaUseCase {
    pub fn new(adapter: Arc<AiQuotaAdapter>) -> Self {
        Self { adapter }
    }

    pub fn get_status(&self, warning_thr: f64, critical_thr: f64, force_refresh: bool) -> DynResult<AiQuotaSnapshot> {
        Ok(self.adapter.get_snapshot(warning_thr, critical_thr, force_refresh))
    }

    pub fn switch_gemini_account(&self, target_id_or_email: &str) -> DynResult<String> {
        self.adapter
            .switch_gemini_account(target_id_or_email)
            .map_err(|e| e.into())
    }
}
