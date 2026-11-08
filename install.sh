#!/bin/bash
# Install Astral Plasma into a self-contained, self-updating layout.
#
#   From a checkout:   ./install.sh
#   From a tarball:    ./install.sh
#   From a binary:     ./install.sh --from /path/to/astral-plasma
#   Over the network:  curl -fsSL https://raw.githubusercontent.com/gitawego/astral-plasma/main/install.sh | bash
#
# This script only creates the install: the binary, its QML bundle, and the
# record naming who owns them. Updates afterwards come from the shell itself
# (Settings → Updates & About), so nothing here has to be run again.
#
# It never uses sudo, never rewrites your settings, and never replaces
# ~/.config/quickshell. An older install living there is adopted by the shell's
# own migration, which copies and never moves.
set -euo pipefail

APP_NAME="Astral Plasma"
REPO="gitawego/astral-plasma"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DATA_DIR="$DATA_HOME/astral-plasma"
BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
CHANNEL="stable"
METHOD="managed"
SOURCE_BIN=""
DRY_RUN=0
IS_OMARCHY=0
WORK_DIR=""

cleanup() {
    [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
    return 0
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Install Astral Plasma.

Usage: ./install.sh [OPTIONS]

Options:
  --from <path>     Install the given astral-plasma binary instead of building
                    or downloading one.
  --channel <name>  Release channel to follow: stable (default) or beta.
  --method <name>   Install method recorded for the updater:
                    managed (default), package, or checkout.
  --omarchy         Install as an Omarchy plugin instead of a managed session.
  --dry-run         Print what would happen and exit.
  -h, --help        Show this help.

Requirements: quickshell 0.3.0 or newer.  No root access is used.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --from) SOURCE_BIN="${2:?--from needs a path}"; shift 2 ;;
        --channel) CHANNEL="${2:?--channel needs a value}"; shift 2 ;;
        --method) METHOD="${2:?--method needs a value}"; shift 2 ;;
        --omarchy) IS_OMARCHY=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[!] Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# Resolve this script's directory when it was run from a file. A piped install
# (`curl | bash`) has no directory at all, so every local lookup below tolerates
# an empty tree.
HERE=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
    HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
fi
if [ -z "$HERE" ] && [ -f "${PWD:-}/shell.qml" ]; then
    HERE="$PWD"
fi

echo "=== Installing $APP_NAME ==="

if ! command -v quickshell >/dev/null 2>&1; then
    echo "[!] Quickshell is not installed. Install it first: sudo pacman -S quickshell" >&2
    exit 1
fi

case "$METHOD" in
    managed|package|checkout) ;;
    *) echo "[!] Unknown --method '$METHOD' (expected managed, package or checkout)" >&2; exit 2 ;;
esac

# --- 1. Omarchy: the plugin path is owned by omarchy-shell, not by us ---------
if [ "$IS_OMARCHY" -eq 1 ] || [ -n "${OMARCHY_SESSION_ID:-}" ] || [ -n "${OMARCHY_DIR:-}" ] || [ -n "${OMARCHY_SESSION:-}" ]; then
    echo "[*] Detected Omarchy. Installing as an Omarchy plugin..."
    if [ -z "$SOURCE_BIN" ] || [ ! -x "$SOURCE_BIN" ]; then
        if [ -n "$HERE" ] && [ -x "$HERE/bin/astral-plasma" ]; then
            SOURCE_BIN="$HERE/bin/astral-plasma"
        elif [ -n "$HERE" ] && [ -f "$HERE/daemon/Cargo.toml" ]; then
            echo "[*] Building the daemon..."
            make -C "$HERE" build
            SOURCE_BIN="$HERE/bin/astral-plasma"
        fi
    fi
    if [ -z "$SOURCE_BIN" ] || [ ! -x "$SOURCE_BIN" ]; then
        echo "[!] No binary to install. Pass --from <path>." >&2
        exit 1
    fi
    "$SOURCE_BIN" omarchy install
    echo "[✓] Installed into the Omarchy plugins directory"
    echo "    Restart omarchy-shell to load the plugin."
    exit 0
fi

# --- 2. Helpers for reading the release manifest ------------------------------
# python3 or jq, whichever the machine has; parsing JSON with sed is how an
# installer silently installs the wrong architecture.
json_get() {
    local file="$1"; shift
    if command -v python3 >/dev/null 2>&1; then
        python3 -c '
import json, sys
node = json.load(open(sys.argv[1]))
for key in sys.argv[2:]:
    if not isinstance(node, dict) or key not in node:
        print("")
        sys.exit(0)
    node = node[key]
print(node if not isinstance(node, (dict, list)) else json.dumps(node))
' "$file" "$@"
        return
    fi
    local expr="" key
    for key in "$@"; do
        expr="${expr}.${key}"
    done
    jq -r "$expr // empty" "$file"
}

download_binary() {
    local arch manifest url sha expected
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) echo "[!] Unsupported architecture: $arch" >&2; exit 1 ;;
    esac

    if ! command -v python3 >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
        echo "[!] python3 or jq is required to read the release manifest." >&2
        exit 1
    fi

    WORK_DIR="$(mktemp -d)"
    manifest="https://github.com/$REPO/releases/latest/download/latest.json"

    echo "[*] Reading release manifest..."
    curl -fsSL --proto '=https' --max-time 30 "$manifest" -o "$WORK_DIR/latest.json"

    url="$(json_get "$WORK_DIR/latest.json" artifacts "$arch" url)"
    expected="$(json_get "$WORK_DIR/latest.json" artifacts "$arch" sha256)"
    if [ -z "$url" ]; then
        echo "[!] The release has no artifact for $arch." >&2
        exit 1
    fi

    echo "[*] Downloading $(json_get "$WORK_DIR/latest.json" version) for $arch..."
    curl -fL --proto '=https' --max-time 600 "$url" -o "$WORK_DIR/astral-plasma"

    sha="$(sha256sum "$WORK_DIR/astral-plasma" | cut -d' ' -f1)"
    if [ "$sha" != "$expected" ]; then
        echo "[!] Checksum mismatch for $url - refusing to install." >&2
        echo "    expected: $expected" >&2
        echo "    got:      $sha" >&2
        exit 1
    fi
    chmod 755 "$WORK_DIR/astral-plasma"
    SOURCE_BIN="$WORK_DIR/astral-plasma"
}

# --- 3. Find a binary to install ---------------------------------------------
if [ -z "$SOURCE_BIN" ]; then
    if [ -n "$HERE" ] && [ -x "$HERE/bin/astral-plasma" ]; then
        SOURCE_BIN="$HERE/bin/astral-plasma"
    elif [ -n "$HERE" ] && [ -f "$HERE/daemon/Cargo.toml" ]; then
        echo "[*] Building the daemon..."
        make -C "$HERE" build
        SOURCE_BIN="$HERE/bin/astral-plasma"
    else
        download_binary
    fi
fi

[ -x "$SOURCE_BIN" ] || { echo "[!] $SOURCE_BIN is not executable." >&2; exit 1; }

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] would install $SOURCE_BIN into $DATA_DIR/bin/astral-plasma"
    echo "[dry-run] would extract the bundle into $DATA_DIR/package"
    echo "[dry-run] would record method=$METHOD channel=$CHANNEL in $DATA_DIR/install.json"
    exit 0
fi

# --- 4. Place the binary ------------------------------------------------------
mkdir -p "$DATA_DIR/bin"
# Copy then rename: a crash mid-copy must not leave a truncated executable where
# the unit and the session launcher expect a working one.
install -m 755 "$SOURCE_BIN" "$DATA_DIR/bin/astral-plasma.new"
mv -f "$DATA_DIR/bin/astral-plasma.new" "$DATA_DIR/bin/astral-plasma"

# --- 5. Bundle + owner record, decided by the binary itself -------------------
# One implementation of the layout: an update performs these same steps, so a
# first install and a later update cannot disagree about where the bundle lives.
"$DATA_DIR/bin/astral-plasma" install --method "$METHOD" --channel "$CHANNEL" >/dev/null

mkdir -p "$BIN_HOME"
ln -sfn "$DATA_DIR/bin/astral-plasma" "$BIN_HOME/astral-plasma"

echo "[✓] Installed to $DATA_DIR"
echo "    command: $BIN_HOME/astral-plasma"

# --- 6. Palette (checkout only) ----------------------------------------------
if [ -n "$HERE" ] && [ -x "$HERE/scripts/generate_palette.sh" ] && command -v matugen >/dev/null 2>&1; then
    bash "$HERE/scripts/generate_palette.sh" >/dev/null 2>&1 || true
fi

# --- 7. What the user needs to know ------------------------------------------
if [ -e "$HOME/.config/quickshell" ]; then
    echo ""
    echo "[*] ~/.config/quickshell already exists and was left untouched."
    echo "    An older install there is adopted on the shell's first start;"
    echo "    Settings → Updates shows what was adopted and offers removal."
fi

echo ""
echo "=== Installation complete ==="
echo "Start it now:             $BIN_HOME/astral-plasma run"
echo "Install the session/unit: Settings → System & Services"
echo "Updates from here on:     Settings → Updates & About"
echo "Remove everything:        $BIN_HOME/astral-plasma uninstall --yes"
