use crate::domain::ports::{DynResult, SystemdControlPort};
use crate::domain::systemd::ServiceStatus;

#[derive(Clone)]
pub struct SystemdControlUseCase<S: SystemdControlPort> {
    port: S,
}

impl<S: SystemdControlPort> SystemdControlUseCase<S> {
    pub fn new(port: S) -> Self {
        Self { port }
    }

    pub fn get_status(&self) -> DynResult<ServiceStatus> {
        self.port.query_status()
    }

    pub fn install(&self) -> DynResult<ServiceStatus> {
        self.port.install_service()
    }

    pub fn remove(&self) -> DynResult<ServiceStatus> {
        self.port.remove_service()
    }
}
