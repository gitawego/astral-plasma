use astral_plasma::domain::ports::DynResult;
use astral_plasma::interfaces::cli::run_cli;

#[tokio::main]
async fn main() {
    // Every refusal in this codebase is written as a sentence for a person (a typed
    // error, never a debug dump). Printing `{:?}` would have shown
    // `Revoked { id: "…" }` instead of the sentence explaining the revocation.
    if let Err(error) = run_cli().await {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
