# Theme Updates, Installation and Restart Specification

> **Status**: P0–P6 implemented and covered by tests, with one deliberate
> exception: release signatures are verified when a release carries one, but they
> are not yet *required*, because no release key has been published (see D13 and
> §12). Everything else below is live code, not a proposal.
> **Scope**: how an installed Astral Plasma learns about a release, installs it,
> restarts itself without disturbing the desktop, rolls back when the new build
> does not come up, shows what changed, and how a non-technical user installs
> and removes the whole thing.
> **Related**: [`docs/KDE-INTEGRATION.md`](KDE-INTEGRATION.md) (claim/restore
> lifecycle), [`docs/HYPRLAND-OMARCHY-SPEC.md`](HYPRLAND-OMARCHY-SPEC.md)
> (profiles), [`AGENTS.md`](../AGENTS.md) §4 (no fabricated content), §4c
> (never claim a fix without proof).

---

## 1. Problem statement

Two independent defects, discovered while studying this tree, are the reason
this document exists:

1. **A release cannot be installed.** `.github/workflows/release.yml` packages
   `bin/astral-plasma`, `README.md`, `LICENSE`, `DESIGN.md`, `install.sh` and
   `uninstall.sh`. The QML tree is embedded in the binary, not shipped beside
   it, and `install.sh` only symlinks *the directory it runs from* into
   `~/.config/quickshell`. Running that installer from a release tarball
   therefore produces a symlink to a directory with no `shell.qml`. Only a git
   checkout that builds itself works today.
2. **Nothing can update, and the unit bypasses the supervisor.** The only
   version string in the product is `env!("CARGO_PKG_VERSION")` in
   `interfaces/api_server.rs`; there is no update code, no release manifest, and
   no HTTP client in the daemon. Separately,
   `domain::systemd::generate_unit_file_content()` writes
   `ExecStart=<quickshell> -p <dir>`, which skips `astral-plasma run` — and with
   it the Plasma claim, the shortcut journal and the restore-on-exit path that
   `cli.rs` steps 3→6 implement.

So this is not "add a checkbox". It is: make an install exist, give it one
owner, give it a restart path that does not flash the user's desktop, and give
it a way back.

---

## 2. Decision summary

| # | Decision | Choice |
| :-- | :--- | :--- |
| D1 | Update payload | **Monolithic**: QML stays embedded in the binary; an update replaces the binary and re-extracts the bundle. No split archive, so binary and QML can never desync. |
| D2 | Install path | **One-line installer** as the primary documented path, self-contained under `~/.local/share/astral-plasma/`, **no sudo**, no symlink into `~/.config/quickshell` unless explicitly requested. AUR is the second path. |
| D3 | Consent | **Notify + one-click apply** by default. "Install updates automatically" is opt-in and off. Prereleases opt-in. |
| D4 | Discovery | Daemon polls `latest.json` ~60 s after login then every 6 h, `ETag` cached, "Check now" available. Offline-safe, no telemetry. |
| D5 | Restart | **Rolling restart owned by `astral-plasma run`**: stage → quit shell → swap → replace binary → `execv` self → respawn, holding the Plasma claim throughout. Never a Quickshell hot reload for a real update. |
| D6 | Health / rollback | New build must answer `quickshell ipc -p <dir> show` **and** write a `boot-ok` marker within 20 s. Two consecutive failures → automatic rollback to `package.prev` + `bin/astral-plasma.prev`. Exactly one previous version is kept. |
| D7 | What's New | `CHANGELOG.json` **compiled into the binary**, generated from `docs/releases/<version>.json`; shown once per version in a curtain and permanently in the Updates page. |
| D8 | Update UI | New Settings page **"Updates & About"** (version, channel, check, changelog, revert, uninstall) with a nav dot when an update is pending; curtain is a 3-line summary layered over the existing **Downloads manager** window, which owns real progress and the log. |
| D9 | Who updates | Installed bundles only. Git checkouts get an "a newer release exists" hint, never a write. AUR/pacman installs are **owned by the package manager** and offer no apply button (D19). |
| D10 | Staging | Extract into a sibling `package.next` **outside** the watched `-p` path; swap by rename only while the shell is down. |
| D11 | Refusals | Refuse to apply while the session is locked, a download is active, an AI turn streams, or a voice session is live. Retry automatically on unlock/idle. |
| D12 | Migrations | Timestamped, idempotent, per-user Rust migrations with markers under `~/.local/state/astral-plasma/migrations/`, run by the supervisor before the shell starts. |
| D13 | Trust | HTTPS only (an explicit `http://` mirror URL is the only downgrade), size cap, size + SHA-256 verified against the manifest before use. A `signature` in the manifest is verified with `minisign` against `ASTRAL_PLASMA_MINISIGN_KEY`; a claimed-but-unverifiable signature is refused. Making signatures *mandatory* waits for the release key to be published. |
| D14 | Safety rails | Update lock, free-space precheck computed from the staged size, sleep inhibitor, per-apply transcript. |
| D15 | Third-party themes | Data only (JSON palette + assets), never QML. Archetypes stay first-party and compiled-in. Non-goal here; recorded as a rule. |
| D16 | Removal scope | Artifacts only. AI sessions, the Plasma/shortcut backups, download history, caches and settings survive an uninstall; `--purge` removes caches and settings too. |
| D17 | Adoption source | The running executable, never a stale checkout build — and a cargo `target/debug` build is refused outright rather than installed as someone's daily shell. |
| D18 | Discovery owner | The daemon checks ~60 s after login and every 6 h (`astral-plasma run` spawns the timer); the shell only reads `update status`, so a closed Settings page cannot stop discovery. |
| D19 | One owner | `pacman -Qo` ownership beats the install record: a package-managed binary is reported as `package` and never written, even if a managed record exists. |

---

## 3. Goals and non-goals

### Goals

- `curl … | bash` on a clean Arch/KDE box installs a working shell in one step,
  and `Settings → Updates & About → Uninstall` removes it without a terminal.
- A user on v0.1.3 sees "v0.2.0 is available", reads three real highlights,
  clicks once, watches real progress, and 2–5 s later is on v0.2.0 **without
  ever seeing plasmashell reappear**.
- A build that fails to start returns the user to the previous version
  automatically, with the reason stated in the UI.
- Every install records who owns it (`managed`, `package`, `checkout`), so two
  updaters never fight over the same files.
- Existing installs (git checkout symlinked into `~/.config/quickshell`) migrate
  to the managed layout without losing settings or touching their checkout.

### Non-goals

- Delta/bsdiff patching (21 MB is acceptable; revisit only if releases get much
  larger).
- Silent unattended updates by default.
- Updating the Omarchy **host**; the hosted plugin rides `omarchy-shell`'s own
  reload and only re-copies its three files.
- Third-party theme installation (see D15).

**Boundary with app updates.** This document owns the *platform* lifecycle: one
kernel release, one artifact, one restart, one `boot-ok` gate (D6), one
`install.json`. Apps have their own lifecycle — version, compatibility window,
update/pin/downgrade, per-app rollback — specified in
[`APPS-PLATFORM-SPEC.md`](APPS-PLATFORM-SPEC.md) §8.5. A platform release ships
app *baselines* and reconciles them; it never forcibly overwrites a newer
installed app version.

---

## 4. Domain language

Additions to [`CONTEXT.md`](../CONTEXT.md), in the update context:

- **Install Method** — recorded fact naming who owns the installed files:
  `managed` (this feature), `package` (pacman/AUR), `checkout` (git clone).
  Never inferred at update time from file layout alone.
- **Release Manifest** — `latest.json`, published per release, the only thing
  the daemon reads to decide whether an update exists.
- **Update Candidate** — a manifest entry that is strictly newer than the
  running version and on the selected channel.
- **Apply Plan** — the concrete, preflight-checked sequence for one candidate:
  download URL, verified digest, staged target, refusals that currently apply.
- **Bundle** — the extracted QML package for one version, identified by the
  version that produced it.
- **Staged Bundle** — a fully extracted bundle in `package.next`, not yet live.
- **Health Marker** — `boot-ok` written by the new QML once it is actually
  running, carrying its version.
- **Update Channel** — `stable` (default) or `beta`.

Existing terms `Claim`, `Hand-back` and `Profile` keep their meaning from
`HYPRLAND-OMARCHY-SPEC.md` §4; this feature consumes them, it does not redefine
them.

---

## 5. Data contracts

### 5.1 `latest.json` (release asset)

```json
{
  "schema": 1,
  "version": "0.2.0",
  "channel": "stable",
  "published_at": "2026-11-08T00:00:00Z",
  "min_quickshell": "0.3.0",
  "highlights": ["…", "…", "…"],
  "changelog": "https://github.com/gitawego/astral-plasma/releases/tag/v0.2.0",
  "artifacts": {
    "x86_64":  { "url": "…/astral-plasma-linux-x86_64",        "sha256": "…", "size": 21800000 },
    "aarch64": { "url": "…/astral-plasma-linux-aarch64",       "sha256": "…", "size": 21400000 }
  },
  "signature": null
}
```

- Unknown fields are ignored, so `signature` becomes required later without a
  version bump to the client.
- A manifest whose `version` is not strictly newer than the running one is not
  an update; downgrades are only ever explicit (`rollback`).

### 5.2 Install record — `~/.local/share/astral-plasma/install.json`

```json
{ "schema": 1, "method": "managed", "version": "0.1.3", "channel": "stable",
  "installed_at": "2026-11-08T00:00:00Z", "owner_package": null }
```

Written by the installer, rewritten by every successful apply, read by the
Updates page and by the applier before it touches anything.

### 5.3 Update state — `~/.local/state/astral-plasma/update.json`

Last check result, `ETag`, timestamps, pending candidate, last apply outcome and
last failure reason. This file is a cache; deleting it must be harmless.

### 5.4 Changelog — `docs/releases/<version>.json`

```json
{ "version": "0.2.0", "date": "2026-11-08",
  "highlights": ["…", "…", "…"],
  "sections": [{ "title": "Fixes", "items": ["…"] }] }
```

Compiled into the binary (`include_dir!` of `docs/releases/`), rendered by the
Updates page. CI fails the release when the file is missing, when its `version`
disagrees with the tag, or when `highlights` is absent (an explicitly empty list
is allowed and must be deliberate).

---

## 6. Ports and adapters

`daemon/src/domain/ports.rs` gains narrow traits, each with a fake, so the whole
update path is testable without a network or a live desktop:

| Port | Adapter | Fake |
| :--- | :--- | :--- |
| `UpdateSourcePort` (fetch manifest, download artifact → verified bytes on disk) | GitHub release asset over `ureq` + rustls | local fixture server / temp files |
| `PackageOwnershipPort` (who owns this executable) | `pacman -Qo`, install record | recorded enum |
| `SleepInhibitorPort` | `systemd-inhibit` / logind | no-op |
| `FreeSpacePort` | `statvfs` on the staging filesystem | fixed values |
| `SessionLockPort` | `qdbus6 org.kde.ScreenSaver GetActive` | scripted states |
| `BundleApplyPort` (stage, swap, replace binary) | filesystem renames under the data dir | temp root |

`ClockPort` already exists in spirit for restart auditing; reuse it rather than
adding another time source.

---

## 7. Lifecycle

### 7.1 Check

1. `astral-plasma run` starts; after 60 s (randomized ±15 s) the first check
   runs, then every 6 h. Manual `astral-plasma update check` bypasses the timer.
2. Skip entirely when the install method is `package` or `checkout`.
3. Fetch `latest.json` with the stored `ETag`; `304` → no change.
4. Compare semver against the running version and channel; write
   `update.json`; expose the candidate over the existing API/IPC for the shell
   to show as a badge.

### 7.2 Apply preflight (all refusals must be named, not silent)

| Refusal | Detection | Behaviour |
| :--- | :--- | :--- |
| Session locked | `SessionLockPort` | defer, apply on unlock |
| Download in flight | existing download service state | defer, apply when idle |
| AI turn streaming / voice session live | assistant + voice service state | defer, apply when idle |
| Under free space | `FreeSpacePort` vs staged size + 32 MB | refuse with the numbers |
| Another apply running | update lock file | refuse and report who holds it |
| Package-owned | install record / `pacman -Qo` | no apply control at all |

### 7.3 Apply

1. Acquire the update lock, take the sleep inhibitor, open the transcript.
2. Download the artifact to `~/.cache/astral-plasma/update/<version>/`, verify
   size and SHA-256 (and signature in P6), write `bin/astral-plasma.next`.
3. Extract the embedded bundle **from the new binary** into `package.next`
   (`astral-plasma.next extract <staging>`), so what ships is what runs.
4. Show the curtain ("Restarting Astral Plasma…"); close popouts.
5. Ask the running shell to quit (`quickshell ipc -p <dir> call shell quit`) and
   wait for the process to exit.
6. Rename: `package` → `package.prev`, `package.next` → `package`; replace
   `bin/astral-plasma` (old copy → `.prev`). The `-p` path string is unchanged,
   so IPC, desktop entries and the unit keep addressing one instance.
7. Write the same-boot **claim handoff marker** and `execv` the new binary with
   the original arguments. On start it sees the marker, knows the Plasma claim
   is already this session's, and neither re-disables panels nor re-binds
   shortcuts.
8. Spawn `quickshell -p <dir>`; wait up to 20 s for `ipc show` **and** the
   `boot-ok` marker for the new version.
9. Success → clear `boot-ok`, write the install record, keep `.prev`, notify
   "Updated to v0.2.0", show the curtain once.

### 7.4 Failure → rollback

Two failed starts (fresh failure counter in the state dir) trigger: swap
`.prev` back into place, `execv` the previous binary, write the failure reason
into `update.json`, and surface it — the Updates page shows "v0.2.0 did not
start: <reason>. Rolled back to v0.1.3." Never loop.

### 7.5 Package-owned and checkout installs

- `package`: check still runs; the page shows the version, the changelog and
  "Your package manager owns this install." No apply.
- `checkout`: show "v0.2.0 is available" with the `git pull` command; never
  write into the working tree.

---

## 8. Install layout

```
~/.local/bin/astral-plasma                     -> ../share/astral-plasma/bin/astral-plasma
~/.local/share/astral-plasma/
  bin/astral-plasma                             (current)
  bin/astral-plasma.prev                        (one previous, kept for rollback)
  package/                                      (extracted bundle, the shell's -p)
  package.prev/
  install.json
~/.local/state/astral-plasma/                   update.json, boot-ok, migrations/, update.log
~/.config/astral-plasma/settings.json           user settings, never touched by an update
```

- `install.sh`/one-liner: verify `quickshell`, download or use the local binary,
  `install` into `bin/`, `extract` into `package/`, write `install.json`,
  optionally install desktop entries and the Wayland session, generate the
  palette; never sudo, never overwrite settings.
- Systemd unit `ExecStart` becomes **`<bin>/astral-plasma run`**, giving service
  installs the claim/restore/health path for the first time. Migration 001
  rewrites an existing unit that still says `quickshell -p`.
- `uninstall.sh` and the in-shell uninstall remove: symlink, bin, packages,
  state/cache/data, unit, desktop entries, session file, shortcuts, KWin script;
  they stop the shell first and refuse to run while a migration is mid-flight.
  **Implemented as**: artifacts (binary, bundle, rollback copy, `install.json`,
  unit, entries) are removed; user data (AI sessions, Plasma/shortcut backups,
  download history, caches, settings) is kept, with `--purge` removing caches and
  settings. The data directory is removed only when it ends up empty.

---

## 9. Migrations

- Location: `daemon/src/application/migrations/`, one module per migration,
  named `<epoch>_<slug>`.
- Contract: run by the supervisor before spawning the shell; idempotent; a
  marker in `~/.local/state/astral-plasma/migrations/<name>` records completion;
  a failure blocks the start with a stated reason rather than half-migrating.
- `astral-plasma migrate --pending` exists for diagnostics and tests.
- Migration 001 migrates the legacy layout described in §1: copy the extracted
  bundle and binary to the managed paths, rewrite the unit, preserve
  `~/.config/astral-plasma/settings.json`, and leave the git checkout untouched.
  A one-time notice tells the user the desktop now updates itself.

---

## 10. UI surfaces

1. **Settings → Updates & About** (`settings_gui/pages/UpdatesPage.qml`):
   current version and channel, install method, pending candidate with
   highlights, "Check now", "Update", full changelog from the compiled
   `CHANGELOG.json`, "Revert to previous version", "Uninstall Astral Plasma"
   (typed confirmation), and the last rollback reason when there is one.
2. **Nav dot** on that page while a candidate is pending.
3. **Curtain** (`shell/UpdateCurtain.qml`): compact, centred, real stages
   (verifying → extracting → restarting → ready), auto-dismiss, once per
   version, "See everything" opens the page. No fabricated percentages.
4. **Downloads manager**: an "Astral update" task with byte progress, stage
   label, transcript path and retry — the single progress surface (D8).
5. **Update log**: `~/.local/state/astral-plasma/update.log`, truncated per
   apply, linked from the page.

---

## 11. Tests

Rust (`daemon/tests/`, isolated by `make test-rust`'s XDG redirection):

- `test_update_manifest.rs` — schema parsing, unknown fields, semver ordering,
  channel filtering, downgrade refusal.
- `test_update_selection.rs` — candidate selection, refusals table, deferral
  reasons, free-space arithmetic.
- `test_update_verify.rs` — digest/size mismatch aborts before any swap;
  truncated download; fixture server.
- `test_update_apply.rs` — stage/swap/replace order; `-p` path stability;
  `.prev` retention; failure injects → rollback → reason recorded.
- `test_update_migrations.rs` — every migration is idempotent, marker written
  once, failure blocks start.
- `test_install_layout.rs` — one-liner layout, no sudo, settings preserved,
  legacy symlink migrated, unit rewritten to `astral-plasma run`.
- `test_update_ownership.rs` — `package`/`checkout` installs expose no apply.

QML (`tests/tst_*.qml`, offscreen):

- `tst_updates_page.qml` — pending/idle/package/checkout/rollback-stated states.
- `tst_update_curtain.qml` — once-per-version semantics, stage text comes from
  the model, never invents progress.

Gates per phase: `make test` exits 0 with `PASS:` and no `FAIL:` (AGENTS §3.4);
visual proof for the page and the curtain captured outside the repo after the
restart actually works (§7).

---

## 12. Phases

| Phase | Content | Exit gate |
| :--- | :--- | :--- |
| **P0 — release truth** ✅ | Ship a tarball that can install: installer extracts the bundle, `latest.json` generated in CI from the tag + `docs/releases/<version>.json`, CI fails on a missing/mismatched changelog file. | A downloaded vX tarball installs on a clean user and runs. |
| **P1 — layout + migrations** ✅ | Managed layout, `install.json`, one-liner installer, in-shell uninstall, migrations engine, migration 001, unit `ExecStart` fix. | Legacy symlink install migrates; `make test` green. |
| **P2 — check** ✅ | `update check/status`, curl adapter + ETag, state file, package/checkout detection, daemon-side timer. | Fixture server drives all manifest cases. |
| **P3 — apply & restart** ✅ | Lock, preflight, download, verify, staging, swap, claim handoff, `execv`, IPC health check, two-attempt retry, rollback, manual revert. | Process-level proof that a staged binary is swapped and executed with the claim intact; live desktop restart still to be observed on a real update. |
| **P4 — UI** ✅ | Updates page (version, update, notes, maintenance), nav entry, restart curtain (records the shown version as seen). Pending-update dot deferred. | Offscreen suite covers every state; live capture taken. |
| **P5 — what's new** ✅ | `docs/releases/*.json` compiled into the binary, `astral-plasma changelog`, page rendering, `lastSeenVersion` recorded. Auto-opening the notes once per version deferred to the curtain. | Notes shown match the running version. |
| **P6 — distribution** ✅ (signature enforcement pending a key) | AUR `astral-plasma-bin` template, pacman ownership detection, signature verification when present. | Package installs report `package` and offer no apply; signed manifests are verified, unsigned ones are accepted until the key ships. |

### What P0 and P1 actually changed

- `install.sh` installs into `~/.local/share/astral-plasma/{bin,package}` and
  delegates the layout to `astral-plasma install`; it can build from a checkout,
  install a given binary, or download + checksum-verify a release. It no longer
  symlinks the checkout into `~/.config/quickshell`.
- `uninstall.sh` delegates removal to `astral-plasma uninstall`, then removes
  only the KDE shortcuts and Omarchy plugin directory that a binary must not
  change unasked.
- `astral-plasma install`, `uninstall`, and `migrate [--pending]` exist as CLI
  commands; `run` executes pending migrations before it claims the desktop.
- The systemd unit runs `<bin> astral-plasma run` and pins
  `ASTRAL_PLASMA_PACKAGE_DIR`, so a service install finally gets the claim,
  shortcut journal and restore-on-exit path.
- Migration `001_adopt_legacy_install` adopts a symlinked checkout: it copies the
  running executable, extracts the matching bundle, writes the owner record and
  rewrites a Quickshell-only unit. It never moves or deletes the checkout, and
  never removes `~/.config/quickshell`.
- Release notes are authored (`docs/releases/<version>.json`) and both
  `scripts/release.sh` and CI refuse a tag without them; the publish job emits
  `latest.json` with per-arch URLs, sizes and SHA-256 digests.

P0 and P1 fixed a user-visible defect (no release was installable, and a service
install bypassed its own supervisor). P3's mechanism is proven at process level
(staged binary swapped, `execv`ed, version recorded, request consumed once); the
remaining proof is observing one real desktop update, which no test can stand in
for.

### What P2–P6 shipped

- `astral-plasma update status|check|apply|revert|seen`, plus `changelog`. The
  daemon owns discovery (60 s after login, then every 6 h) and the shell only
  reads the result.
- Manifest rules are pure and tested: schema, semver ordering with prereleases,
  channel acceptance, per-architecture artifacts, `min_quickshell`, digest and
  size bounds. Unknown fields are ignored so a newer release stays installable.
- Transport is `curl` (already a hard dependency of the installer): protocol
  pinned by scheme, ETag/`304`, connect and transfer timeouts, `--max-filesize`,
  then size and SHA-256 checked against the manifest before anything is staged.
- `apply` refuses on a package-managed or checkout install, while the session is
  locked, while another apply holds the lock, below the free-space floor, or when
  an update is already staged. It writes `bin/astral-plasma.next`, then a restart
  request, then asks the shell to exit.
- The supervisor performs the swap: `bin/astral-plasma` → `.prev`, staged → live,
  record updated, then `execv` of the new binary with the pid preserved so the
  same-boot claim handoff still covers it. Quickshell is restarted twice before a
  rollback is attempted; a rollback restores `.prev`, records why, and execs it.
- `update revert` puts the previous release back and restarts into it; the
  Updates page exposes it only for a `managed` install.
- `install.json` gained optional app-record fields (`digest`, `trust`,
  `publisher_key`, `grants`) so the app platform can reuse the struct per app
  without a schema change (see §14).
- AUR `astral-plasma-bin` installs to `/usr/bin`; `pacman -Qo` then makes the
  daemon report `package`, which is what stops two updaters writing one file.

---

## 13. Notes from Omarchy (reference, not adopted wholesale)

| Concern | Omarchy | Astral (this spec) |
| :--- | :--- | :--- |
| Update trigger | pacman + `checkupdates`, guarded ALPM hook | `latest.json` poll; package-owned installs defer to pacman |
| "Themes" | user git repos pulled by `omarchy-theme-update` | shipped with the binary; user themes are a non-goal (D15) |
| Shell restart | unconditional after every update; refuses while locked | same, driven by `astral-plasma run` with claim retention |
| Hot reload | guarded against during transactions | never used for an update; staged swap instead |
| Migrations | epoch-named shell scripts + per-user markers | same contract, in Rust |
| What's new | none — release notes only | compiled changelog + once-per-version curtain |
| Rollback | snapper snapshot (filesystem-wide) | previous bundle + previous binary retained by the updater |

---

## 14. Compatibility with the app platform

`docs/APPS-PLATFORM-SPEC.md` builds on this document ("install/update
ownership"). The pieces that must not drift:

| APPS-PLATFORM-SPEC expectation | What this design provides |
| :--- | :--- |
| `~/.local/share/astral-plasma/{bin,package,install.json}` (§11.1) | Exactly this layout; the installer and the updater both write it. |
| Per-app `install.json` "mirrors `InstallRecord`" (§11.1) | `InstallRecord` carries optional `digest`, `trust`, `publisher_key` and `grants`, so an app record is the same struct, not a second schema. |
| `apps.json`, `apps/<id>/`, `catalogs/` as siblings | Nothing here writes or removes them: the updater swaps `package/` only, and uninstall removes only what an install created, deleting `data_dir` only when it is empty. |
| "Core update … store apps survive" (§11.3) | A core update replaces the binary and re-extracts `package/`; app directories are untouched. |
| "Migrations: legacy installs get a registry" (§P5) | The migrations engine is the vehicle: `apps/0002_<slug>`-style modules register in `application::migrations::registry`, run per user, and block the start if they fail. |
| `astral` alias (A17) | The product commands (`install`, `uninstall`, `migrate`, `update`, `changelog`) are product-level; the `astral` alias can forward all of them unchanged. |
| Update consent (A18) | Permission changes belong to the app record; the product updater never merges app grants, so a new permission set cannot be accepted silently by a core update. |

