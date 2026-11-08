#!/usr/bin/env bash
# Sign a release manifest so installed shells can verify it.
#
#   scripts/astral-sign.sh <latest.json> [secret-key]
#
# The signature is written back into the manifest's `signature` field, because the
# daemon verifies the document it downloaded (one file, one hash, one signature).
# Generate the key pair once, then keep the secret key out of the repository:
#
#   minisign -G -p packaging/keys/astral-plasma.pub -s ~/.minisign/astral-plasma.key
#
# and put the *contents* of the secret key file into the repository secret
# MINISIGN_SECRET_KEY. The public key belongs in `packaging/keys/` and, once
# accepted, in `PINNED_MINISIGN_KEY` (daemon/src/infrastructure/update_source.rs)
# so no environment variable is needed for users.
#
# Turning enforcement on is a separate, deliberate step:
#
#   ASTRAL_PLASMA_REQUIRE_SIGNATURE=1     (in the daemon's environment)
#
# Until then an unsigned release is installable and a *signed* one is still
# verified when it arrives.
set -euo pipefail

MANIFEST="${1:?usage: astral-sign.sh <latest.json> [secret-key]}"
KEY="${2:-${MINISIGN_SECRET_KEY_FILE:-$HOME/.minisign/astral-plasma.key}}"

[ -f "$MANIFEST" ] || { echo "[!] No manifest at $MANIFEST" >&2; exit 1; }
[ -f "$KEY" ] || { echo "[!] No signing key at $KEY (minisign -G to create one)" >&2; exit 1; }
command -v minisign >/dev/null 2>&1 || { echo "[!] minisign is not installed" >&2; exit 1; }

# -S: sign the file itself (not a pre-hashed input), -m: manifest mode.
minisign -Sm "$MANIFEST" -s "$KEY" >/dev/null
SIGNATURE_FILE="${MANIFEST}.minisig"
[ -f "$SIGNATURE_FILE" ] || { echo "[!] minisign produced no signature" >&2; exit 1; }

python3 - "$MANIFEST" "$SIGNATURE_FILE" <<'PY'
import json, sys
manifest_path, signature_path = sys.argv[1], sys.argv[2]
signature = open(signature_path).read()
manifest = json.load(open(manifest_path))
manifest["signature"] = signature
with open(manifest_path, "w") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
print(f"[✓] Signed {manifest_path} ({len(signature.splitlines())} line signature)")
PY

# The detached file is not shipped; the signature travels inside the manifest.
rm -f "$SIGNATURE_FILE"
