use crate::domain::ports::{AppLauncherPort, DynResult};

pub struct LaunchAppUseCase<T: AppLauncherPort> {
    port: T,
}

impl<T: AppLauncherPort> LaunchAppUseCase<T> {
    pub fn new(port: T) -> Self {
        Self { port }
    }

    pub fn execute(&self, target: &str) -> DynResult<()> {
        self.port.launch(target)
    }

    pub fn list_apps(&self) -> DynResult<Vec<crate::domain::ports::AppInfo>> {
        self.port.list_apps()
    }
}
