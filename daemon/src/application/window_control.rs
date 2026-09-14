use crate::domain::ports::{DynResult, WindowManagerPort};

pub struct WindowControlUseCase<T: WindowManagerPort> {
    port: T,
}

impl<T: WindowManagerPort> WindowControlUseCase<T> {
    pub fn new(port: T) -> Self {
        Self { port }
    }

    pub fn activate(&self, id: &str) -> DynResult<()> {
        self.port.activate_window(id)
    }

    pub fn close(&self, id: &str) -> DynResult<()> {
        self.port.close_window(id)
    }
}
