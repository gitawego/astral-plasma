#!/bin/bash
# Safe live testing script - runs without modifying KDE Plasma system config
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo " Starting Astral Plasma Shell (Dev Preview)"
echo " Safe mode: does NOT modify your existing desktop settings."
echo " Press Ctrl+C at any time to exit safely."
echo "=========================================================="

# Generate initial dynamic palette if needed
bash "$DIR/scripts/generate_palette.sh" || true

# Ensure astral-plasma daemon binary is built
if [ ! -f "$DIR/bin/astral-plasma" ]; then
    echo "[*] Building astral-plasma daemon binary..."
    cargo build --release --manifest-path "$DIR/daemon/Cargo.toml"
    mkdir -p "$DIR/bin"
    cp -f "$DIR/daemon/target/release/astral-plasma" "$DIR/bin/astral-plasma"
fi

# Run quickshell pointing to this isolated directory
exec quickshell -p "$DIR"
