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

    pub fn login_gemini_oauth(&self, email_hint: Option<&str>) -> DynResult<String> {
        self.adapter
            .login_gemini_oauth(email_hint)
            .map_err(|e| e.into())
    }

    pub fn remove_account(&self, provider_id: &str, target_id_or_email: &str) -> DynResult<String> {
        self.adapter
            .remove_account(provider_id, target_id_or_email)
            .map_err(|e| e.into())
    }

    pub fn add_account(
        &self,
        provider_id: &str,
        credential: &str,
        label: Option<&str>,
        is_session: bool,
    ) -> DynResult<String> {
        self.adapter
            .add_account(provider_id, credential, label, is_session)
            .map_err(|e| e.into())
    }

    pub fn list_accounts(&self, provider_id: Option<&str>) -> DynResult<serde_json::Value> {
        self.adapter
            .list_accounts(provider_id)
            .map_err(|e| e.into())
    }
}

