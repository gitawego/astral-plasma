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

# Run quickshell pointing to this isolated directory
exec quickshell -p "$DIR"
