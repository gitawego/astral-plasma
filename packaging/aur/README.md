# AUR package

`astral-plasma-bin` installs the release binary to `/usr/bin/astral-plasma`. The
QML bundle travels inside that binary; the first `astral-plasma run` extracts it
into `~/.local/share/astral-plasma/package`, per user, with no root access.

The package page is:

```
https://aur.archlinux.org/packages/astral-plasma-bin
```

## Layout

Only these files belong in the AUR Git repository:

| File | Purpose |
| :--- | :--- |
| `PKGBUILD` | The package recipe. Source of truth in this checkout. |
| `.SRCINFO` | Generated metadata from `makepkg --printsrcinfo`; the AUR reads this. |
| `.gitignore` | Keeps `src/`, `pkg/` and built packages out of Git. |

`src/`, `pkg/`, `.pkg.tar.zst` and downloaded tarballs are build artifacts and
must never be pushed.

## Before the first publication

1. Create an account at <https://aur.archlinux.org/register/>.
2. Add your public SSH key under **My Account → SSH Public Key**.
3. Install the packaging tools:

   ```bash
   sudo pacman -S --needed base-devel pacman-contrib namcap
   ```

4. Confirm the package name is still free:

   ```bash
   curl -fsSL 'https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=astral-plasma-bin'
   ```

   An empty `results` array means it is available.

5. Check that the release assets named in `PKGBUILD` exist and that their
   checksums match the release's `SHA256SUMS.txt`. `updpkgsums` does this for
   you, but it will silently accept a replaced asset: compare the values with
   the GitHub release before publishing.

## Verify the package locally

Run from this directory:

```bash
updpkgsums                                # refresh checksums from the release
makepkg --printsrcinfo > .SRCINFO         # refresh the AUR metadata
makepkg -f                                # build the package
namcap PKGBUILD
namcap astral-plasma-bin-*.pkg.tar.zst
```

`makepkg` must run as your normal user, never as root. The build downloads the
x86_64 release binary (about 18 MB) and writes the package next to the
`PKGBUILD`.

The package can be inspected without installing it:

```bash
bsdtar -tvf astral-plasma-bin-*.pkg.tar.zst
pacman -Qip astral-plasma-bin-*.pkg.tar.zst
```

## First publication

AUR packages are ordinary Git repositories. The first push creates the package
page; there is no review queue and no separate registration form.

```bash
git clone ssh://aur@aur.archlinux.org/astral-plasma-bin.git
cd astral-plasma-bin

cp /path/to/astral-plasma/packaging/aur/PKGBUILD .
cp /path/to/astral-plasma/packaging/aur/.gitignore .
makepkg --printsrcinfo > .SRCINFO

git add PKGBUILD .SRCINFO .gitignore
git commit -m "Initial import: astral-plasma-bin 0.1.3-1"
git branch -M master
git push origin master
```

The AUR user in the URL is always `aur`, not your account name. Cloning a new
package reports an empty repository; that is expected. After the push, check
the package page and test the user-facing install path:

```bash
yay -S astral-plasma-bin
# or
paru -S astral-plasma-bin
```

## Publishing a new version

Update the version in `PKGBUILD`, then regenerate the checksums and metadata:

```bash
sed -i 's/^pkgver=.*/pkgver=0.1.4/' PKGBUILD
updpkgsums
makepkg --printsrcinfo > .SRCINFO
makepkg -f
namcap PKGBUILD
```

Commit and push from the AUR clone:

```bash
git add PKGBUILD .SRCINFO
git commit -m "Update to 0.1.4"
git push
```

Bump `pkgrel` (`1` → `2`) when only the packaging changes and `pkgver` stays the
same. Never force-push published history.

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
