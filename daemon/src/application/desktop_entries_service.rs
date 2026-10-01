use crate::domain::desktop_entries::DesktopIntegrationStatus;
use crate::domain::ports::{DesktopIntegrationPort, DynResult};

#[derive(Clone)]
pub struct DesktopEntriesUseCase<P: DesktopIntegrationPort> {
    port: P,
}

impl<P: DesktopIntegrationPort> DesktopEntriesUseCase<P> {
    pub fn new(port: P) -> Self {
        Self { port }
    }

    pub fn get_status(&self) -> DynResult<DesktopIntegrationStatus> {
        self.port.query_status()
    }

    pub fn install(&self) -> DynResult<DesktopIntegrationStatus> {
        self.port.install_desktop_entries()
    }

    pub fn remove(&self) -> DynResult<DesktopIntegrationStatus> {
        self.port.remove_desktop_entries()
    }
}
