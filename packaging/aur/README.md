# AUR package

`astral-plasma-bin` installs the release binary to `/usr/bin/astral-plasma`. The
QML bundle travels inside that binary; the first `astral-plasma run` extracts it
into `~/.local/share/astral-plasma/package`, per user, with no root access.

## Publishing a new version

1. Bump `pkgver` to the release version (the same value as `daemon/Cargo.toml`).
2. Fetch the checksums that the release workflow published:

   ```bash
   makepkg -g >> PKGBUILD   # or: updpkgsums
   ```

   Replace the `'SKIP'` placeholders. A binary package must pin its checksums;
   `SKIP` is only a template convenience.
3. Regenerate `.SRCINFO` and push to the AUR:

   ```bash
   makepkg --printsrcinfo > .SRCINFO
   ```

## Why the package must not self-update

`astral-plasma update status` reports the install method. For this package it
says `package`, because the daemon asks `pacman -Qo` who owns
`/usr/bin/astral-plasma`. The Updates page then shows the version, the compiled
release notes and "Your package manager owns this install; update it with
pacman." - with no apply button. Letting the daemon replace a pacman-owned file
would make the two updaters fight, which is exactly the failure mode
`docs/UPDATES.md` (D9/D19) forbids.

## Removing

```bash
sudo pacman -Rns astral-plasma-bin
```

That removes the binary. Per-user data (settings, the extracted bundle, the AI
harness's sessions) stays until the user removes it; the in-shell
**Updates & About → Uninstall** does that safely, and keeps settings unless
`--purge` is given.
