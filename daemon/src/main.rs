use caelestia_daemon::domain::ports::DynResult;
use caelestia_daemon::interfaces::cli::run_cli;

#[tokio::main]
async fn main() -> DynResult<()> {
    run_cli().await
}
