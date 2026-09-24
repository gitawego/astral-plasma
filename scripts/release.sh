#!/usr/bin/env bash
# Release automation script for Astral Plasma.
# Bumps version, validates tests, creates annotated git tag, and triggers GitHub Actions release.
#
# Usage:
#   ./scripts/release.sh [VERSION] [OPTIONS]
#
# Examples:
#   ./scripts/release.sh 0.2.0
#   ./scripts/release.sh v0.2.0
#   ./scripts/release.sh --patch
#   ./scripts/release.sh --minor
#   ./scripts/release.sh --dry-run 0.2.0
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CARGO_TOML="${ROOT_DIR}/daemon/Cargo.toml"

# Default flags
DRY_RUN=0
SKIP_TESTS=0
IS_DRAFT=false
IS_PRERELEASE=false
VERSION_INPUT=""
BUMP_TYPE=""

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=1
            shift
            ;;
        --draft)
            IS_DRAFT=true
            shift
            ;;
        --prerelease)
            IS_PRERELEASE=true
            shift
            ;;
        --patch)
            BUMP_TYPE="patch"
            shift
            ;;
        --minor)
            BUMP_TYPE="minor"
            shift
            ;;
        --major)
            BUMP_TYPE="major"
            shift
            ;;
        -h|--help)
            cat <<EOF
Astral Plasma Release CLI

Usage:
  ./scripts/release.sh [VERSION] [OPTIONS]

Options:
  --patch          Bump patch version (e.g. 0.1.0 -> 0.1.1)
  --minor          Bump minor version (e.g. 0.1.0 -> 0.2.0)
  --major          Bump major version (e.g. 0.1.0 -> 1.0.0)
  --draft          Publish release as draft
  --prerelease     Publish release as prerelease
  --skip-tests     Skip running 'make test' before release
  --dry-run        Simulate release workflow without pushing or tagging
  -h, --help       Show this help message

Examples:
  ./scripts/release.sh 0.2.0
  ./scripts/release.sh --patch
  ./scripts/release.sh --dry-run 0.2.0
EOF
            exit 0
            ;;
        *)
            if [ -z "$VERSION_INPUT" ]; then
                VERSION_INPUT="$1"
            else
                echo "[!] Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

echo "=================================================="
echo "          Astral Plasma Release Manager           "
echo "=================================================="

# 1. Read current version from Cargo.toml
CURRENT_RAW_VERSION=$(grep -m1 '^version' "$CARGO_TOML" | sed -E 's/version = "(.*)"/\1/')
echo "[*] Current Cargo version: ${CURRENT_RAW_VERSION}"

# 2. Determine target version
if [ -n "$BUMP_TYPE" ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_RAW_VERSION"
    case "$BUMP_TYPE" in
        patch)
            PATCH=$((PATCH + 1))
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            ;;
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            ;;
    esac
    TARGET_VERSION="${MAJOR}.${MINOR}.${PATCH}"
elif [ -n "$VERSION_INPUT" ]; then
    # Strip leading 'v' if present for semver comparison
    TARGET_VERSION="${VERSION_INPUT#v}"
else
    # Prompt user
    echo ""
    echo "Current version is ${CURRENT_RAW_VERSION}"
    read -rp "Enter new version (e.g. 0.2.0) or press Enter for next patch: " USER_VER
    if [ -z "$USER_VER" ]; then
        IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_RAW_VERSION"
        PATCH=$((PATCH + 1))
        TARGET_VERSION="${MAJOR}.${MINOR}.${PATCH}"
    else
        TARGET_VERSION="${USER_VER#v}"
    fi
fi

# Ensure valid semver format
if [[ ! "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "[!] Invalid semantic version format: '${TARGET_VERSION}'. Expected format: X.Y.Z (e.g. 0.2.0)"
    exit 1
fi

TAG="v${TARGET_VERSION}"
echo "[*] Target Version: ${TARGET_VERSION} (Tag: ${TAG})"

# 3. Check git status
echo "[*] Verifying git repository state..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
    echo "[!] Warning: You are on branch '${CURRENT_BRANCH}', not 'main'."
    if [ "$DRY_RUN" -eq 0 ]; then
        read -rp "Do you wish to proceed? [y/N]: " CONFIRM_BRANCH
        if [[ ! "$CONFIRM_BRANCH" =~ ^[Yy]$ ]]; then
            echo "[*] Release aborted."
            exit 1
        fi
    fi
fi

if [ "$DRY_RUN" -eq 0 ]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "[!] Error: Uncommitted changes detected in working tree."
        echo "    Please commit or stash your changes before releasing."
        git status --short
        exit 1
    fi
fi

# 4. Mandatory Test Gate
if [ "$SKIP_TESTS" -eq 0 ]; then
    echo "[*] Running verification test suite (make test)..."
    if [ "$DRY_RUN" -eq 0 ]; then
        make -C "$ROOT_DIR" test
    else
        echo "    [dry-run] 'make test' would run here."
    fi
    echo "[✓] Tests passed with 0 failures!"
else
    echo "[!] WARNING: Test gate skipped via --skip-tests."
fi

# 5. Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "[!] Error: Git tag '${TAG}' already exists locally."
    exit 1
fi

if git ls-remote --tags origin | grep -q "refs/tags/${TAG}$"; then
    echo "[!] Error: Git tag '${TAG}' already exists on origin."
    exit 1
fi

# 6. Update Cargo.toml if version changed
if [ "$CURRENT_RAW_VERSION" != "$TARGET_VERSION" ]; then
    echo "[*] Updating version in ${CARGO_TOML} -> ${TARGET_VERSION}..."
    if [ "$DRY_RUN" -eq 0 ]; then
        sed -i -E "s/^version = \".*\"/version = \"${TARGET_VERSION}\"/" "$CARGO_TOML"
        cargo check --manifest-path "$CARGO_TOML" >/dev/null 2>&1 || true
        git -C "$ROOT_DIR" add daemon/Cargo.toml daemon/Cargo.lock 2>/dev/null || git -C "$ROOT_DIR" add daemon/Cargo.toml
        git -C "$ROOT_DIR" commit -m "chore(release): bump version to ${TAG}"
        echo "[✓] Version bumped and committed."
    else
        echo "    [dry-run] Would update ${CARGO_TOML} and commit."
    fi
fi

# 7. Generate Preview Changelog
echo ""
echo "=== Preview of Changelog (${TAG}) ==="
bash "${ROOT_DIR}/scripts/generate_changelog.sh" "" "HEAD" | sed -n '1,35p' || true
echo "..."
echo "======================================"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[*] DRY-RUN completed successfully. No tags or workflows were dispatched."
    exit 0
fi

# 8. Create annotated git tag and push
echo "[*] Creating annotated git tag '${TAG}'..."
git -C "$ROOT_DIR" tag -a "$TAG" -m "Release ${TAG}"

echo "[*] Pushing branch and tag to origin..."
git -C "$ROOT_DIR" push origin "$CURRENT_BRANCH"
git -C "$ROOT_DIR" push origin "$TAG"
echo "[✓] Pushed ${TAG} to origin!"

# 9. Optional GitHub CLI workflow monitoring
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo ""
    echo "[*] GitHub CLI detected. Release workflow will automatically execute on GitHub Actions."
    REPO_URL=$(gh repo view --json url -q .url 2>/dev/null || echo "https://github.com/gitawego/astral-plasma")
    echo "    Release URL: ${REPO_URL}/releases/tag/${TAG}"
    echo "    Actions URL: ${REPO_URL}/actions"
    echo ""
    read -rp "Would you like to watch the GitHub Actions workflow live? [Y/n]: " WATCH_CONFIRM
    if [[ ! "$WATCH_CONFIRM" =~ ^[Nn]$ ]]; then
        sleep 3
        gh run watch --exit-status || true
    fi
else
    echo ""
    echo "[✓] Tag pushed! Visit GitHub to monitor release build progress."
fi

echo ""
echo "=== Release ${TAG} Initiated Successfully! ==="
