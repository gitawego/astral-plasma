# AppImage packaging

The AppImage is a single-file delivery container for Astral Plasma. It is not
the installed runtime: `AppRun` copies the payload to

```
~/.local/share/astral-plasma/app/<version>/
```

on first launch and points `app/current` at it. A stable path is mandatory:
KWin's screenshot authorization, `quickshell -p` IPC and KGlobalAccel all
identify the shell by its executable path, which would change on every mount.

## What it contains

| Path | Purpose |
| :--- | :--- |
| `usr/bin/astral-plasma` | The Rust daemon and embedded QML bundle |
| `usr/bin/quickshell` | The Quickshell runtime |
| `usr/bin/appimageupdatetool.AppImage` | Bundled AppImageUpdate CLI |
| `usr/lib/`, `usr/plugins/` | Bundled Qt 6 and Quickshell dependencies |
| `usr/share/astral-plasma/package/` | Shell QML, assets and the first-run wizard |
| `AppRun` | Stable extraction, environment and first-run routing |

## Build

Install the toolchain:

```bash
sudo pacman -S --needed base-devel squashfs-tools patchelf qt6-base qt6-declarative
# linuxdeploy and its Qt plugin:
#   https://github.com/linuxdeploy/linuxdeploy/releases
#   https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases
# appimagetool:
#   https://github.com/AppImage/appimagetool/releases
```

Put `linuxdeploy`, `linuxdeploy-plugin-qt`, `appimagetool`, `patchelf`,
`mksquashfs`, `zsyncmake`, `qmake6`, `quickshell` and `curl` on `PATH`, then:

```bash
./packaging/appimage/build.sh
# or, when bin/astral-plasma is already current:
./packaging/appimage/build.sh --no-build
```

The result is `dist/astral-plasma-<version>-<arch>.AppImage`.

### Release pipeline

`.github/workflows/release.yml` builds the x86_64 AppImage on Ubuntu 24.04 with
Qt 6.8.3 and Quickshell 0.3.2 (built from source), adds the AppImage and its
`.zsync` delta metadata to the release assets and to `SHA256SUMS.txt`. The
managed updater's `latest.json` still points at the raw per-architecture
binaries; AppImage installs update through AppImageUpdate instead (below).

The job pins `linuxdeploy 1-alpha-20251107-1`,
`linuxdeploy-plugin-qt 1-alpha-20250213-1` and `appimagetool 1.9.1` with
SHA-256 checksums; use the same versions locally when reproducing a release.

`NO_STRIP=1` is set deliberately: the linuxdeploy bundled `strip` predates
`.relr.dyn` sections from current Arch binaries, and stripping is not required
for correctness.

### Compatibility

The AppImage bundles Qt and Quickshell but **not glibc**. A build produced on
current Arch requires glibc 2.39 or newer (Ubuntu 24.04, Fedora 40+, current
Arch); it will not start on Ubuntu 22.04 or Debian 12. For a wider audience,
run the same build on the oldest supported distribution with the
Quickshell/Qt toolchain, or build against a compatible sysroot. Test the resulting image on
each target before publishing it.

### FUSE

The first launch needs the AppImage runtime to mount the image. On a system
without FUSE 2, run the image once with

```bash
./astral-plasma-*.AppImage --appimage-extract-and-run
```

After the first run the shell executes from the stable extracted payload, so
FUSE is not needed for the login session.


## First run

The wizard is a normal `FloatingWindow`, not a layer-shell takeover. It offers:

1. **Try** — starts the shell; Plasma panels return when it exits.
2. **Install at login** — writes a user session entry, wrapper and record.
3. **Remove** — removes the AppImage wrapper, payload and session; settings
   stay.

The install command behind the buttons is:

```bash
astral-plasma appimage install --payload "$ASTRAL_APPIMAGE_PAYLOAD" --yes
```

The wrapper lives at `~/.local/share/astral-plasma/bin/astral-plasma` and
resolves `~/.local/share/astral-plasma/app/current/AppRun`. The login entry is
`~/.local/share/wayland-sessions/astral-plasma.desktop` and starts
`kwin_wayland --exit-with-session <wrapper> run`.

## Updates

An AppImage install uses the native AppImageUpdate path, not the managed
binary swap. The image embeds:

```
gh-releases-zsync|gitawego|astral-plasma|latest|astral-plasma-*-x86_64.AppImage.zsync
```

and the release publishes the matching `.zsync` beside the AppImage.
`appimageupdatetool` is bundled in the image, so no system package is needed.

- `astral-plasma update check` runs `appimageupdatetool -j` and caches the
  available version from the assembled zsync URL.
- `astral-plasma update apply --yes` runs `appimageupdatetool -O -r` (zsync
  verifies the download), extracts the new image to `app/<version>/`, switches
  `app/current` atomically, keeps `app/previous`, updates `install.json`, and
  asks the supervisor to restart into the new payload.

The canonical file is kept at `app/astral-plasma.AppImage`; `AppRun` copies it
from `$APPIMAGE` on first launch. Launch the downloaded image once before using
`update check` so this update source exists.

## Verification

```bash
# The AppImage expands without FUSE:
./dist/astral-plasma-*.AppImage --appimage-extract
test -x squashfs-root/AppRun

# The wrapper and record after a test install:
astral-plasma appimage status
```

Do not commit `build/`, `dist/`, or downloaded AppImage tooling; they are
ignored by the repository.
