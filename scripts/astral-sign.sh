#!/usr/bin/env bash
# Sign a release manifest so installed shells can verify it.
#
#   scripts/astral-sign.sh <latest.json> [secret-key]
#
# Produces a *detached* signature beside the manifest (`latest.json.minisig`).
# It is deliberately not injected into the manifest: a signature computed over a
# document cannot be written into that document without changing the bytes it
# signed.
#
# Generate the key pair once, then keep the secret key out of the repository:
#
#   minisign -G -p packaging/keys/astral-plasma.pub -s ~/.minisign/astral-plasma.key
#
# (or `rsign generate -p … -s … -W` when only the Rust-compatible tool is
# available; the formats are the same).
#
# Put the *contents* of the secret key file into the repository secret
# MINISIGN_SECRET_KEY. The public key belongs in `packaging/keys/` and in
# `PINNED_MINISIGN_KEY` (daemon/src/infrastructure/update_source.rs).
#
# Requiring signatures is a separate, deliberate step:
#
#   ASTRAL_PLASMA_REQUIRE_SIGNATURE=1     (in the daemon's environment)
#
# Verification needs no tool on the user's machine: the daemon verifies in-process.
set -euo pipefail

MANIFEST="${1:?usage: astral-sign.sh <latest.json> [secret-key]}"
KEY="${2:-${MINISIGN_SECRET_KEY_FILE:-$HOME/.minisign/astral-plasma.key}}"

[ -f "$MANIFEST" ] || { echo "[!] No manifest at $MANIFEST" >&2; exit 1; }
[ -f "$KEY" ] || { echo "[!] No signing key at $KEY (minisign -G to create one)" >&2; exit 1; }

# minisign is the reference tool; rsign is the pure-Rust compatible one.
if command -v minisign >/dev/null 2>&1; then
    minisign -Sm "$MANIFEST" -s "$KEY" >/dev/null
elif command -v rsign >/dev/null 2>&1; then
    rsign sign -s "$KEY" -W "$MANIFEST" >/dev/null
else
    echo "[!] Neither minisign nor rsign is installed; cannot sign." >&2
    exit 1
fi

SIGNATURE_FILE="${MANIFEST}.minisig"
[ -f "$SIGNATURE_FILE" ] || { echo "[!] No signature was produced" >&2; exit 1; }

echo "[✓] Signed ${MANIFEST} -> ${SIGNATURE_FILE}"
