use astral_plasma::domain::ports::DynResult;
use astral_plasma::interfaces::cli::run_cli;

#[tokio::main]
async fn main() -> DynResult<()> {
    run_cli().await
}
