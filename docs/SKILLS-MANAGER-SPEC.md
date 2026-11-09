# Skills Manager

> **Status**: design proposal, nothing implemented.
> **Scope**: an Astral-owned manager for agent skills — discovery across sources,
> repository-scoped install/uninstall, symlink farms that cannot corrupt a home directory,
> and per-skill or per-repository enable/disable.
> **Related**: [`APPS-PLATFORM-SPEC.md`](APPS-PLATFORM-SPEC.md) (the app this ships as, and the
> consent/registry patterns it reuses), [`ARCHITECTURE.md`](ARCHITECTURE.md) §9 (kernel, apps,
> ports), [`LESSONS.md`](LESSONS.md) (what "prove it live" means here).

---

## 1. The problem, stated precisely

The `skills` CLI (Vercel Labs, `npx skills`) treats a skill repository as a bag of folders and
an agent directory as a place to drop them. That works until the filesystem stops being
symmetrical, and then it fails in ways users cannot see or repair:

| Failure | What the user sees | Why it happens |
| --- | --- | --- |
| A stale link survives | The agent still loads a skill that was "removed" | Removal deletes the link it thinks it made, not the link that exists |
| A skill installs twice | Two copies, one stale | `.agents/skills/x` real, `.claude/skills/x` real as well |
| A repo cannot be dropped | `remove owner/repo` leaves skills behind | The lock records *skills*; the filesystem has *links per agent*, and the two drift |
| Our link replaces theirs | A user's own `~/.claude/skills/x` is gone | `symlink()` overwrites; nobody checked what was there first |
| A dangling link loops | Endless resolution or a missing skill | Links were created relative to the wrong base, or the content was garbage-collected |

The fix is not more care in `symlink(2)` calls. It is **modelling the link farm**: decide the
desired state, keep a record of what we created, and apply changes idempotently — the way the
app platform already treats the app registry.

## 2. Goals and non-goals

**Goals**

1. **Search** skills from several sources with one query, and install from any of them.
2. **Repository is a first-class unit**: install, enable, disable, update and remove a whole
   repo, or one skill inside it.
3. **Symlinks that are safe by construction**: atomic, relative, idempotent, verifiable, and
   never destructive to something we did not create.
4. **Enable/disable without re-downloading**: disabling removes links, keeps content;
   enabling restores them.
5. **Everything the GUI shows is the filesystem's truth**, not a cached guess; a "doctor"
   reports drift and can repair it.
6. **Data-driven**: agents (targets), sources, and per-target link styles are configuration,
   not code paths.

**Non-goals**

- Running skills, or deciding whether a skill is safe. We surface signals (audit results when
  a source provides them) and require explicit consent, but review stays human.
- Replacing the agent's own skill discovery. We write the directories they read.
- Windows junctions (documented, not implemented in v1; `copy` is the fallback).

## 3. Vocabulary

| Term | Meaning |
| --- | --- |
| **Skill** | A directory containing `SKILL.md` with YAML frontmatter (`name`, `description`) and optional `scripts/`, `references/`, `assets/`. Identity is `(source, ref, subpath)`. |
| **Source** | Where a skill comes from: a **catalog hit** (GitHub/skills.sh search), an **added source** — a local folder or any git remote — or a one-off URL. |
| **Added source** | A source the user registered by hand (`skills source add …`): a folder on disk (`~/my-skills`) or a git remote (`git@gitlab.corp:team/skills.git#v2`). It is listed, refreshed, and installed from like a catalog hit, and it survives restarts. |
| **Origin** | Where a skill's bytes live: `Store{ref, sha}` for git sources (copied, immutable) or `Local{path}` for a local folder (linked in place, editable). |
| **Credential** | An opaque handle to *how* a private git remote authenticates (git config / SSH agent / `gh` token / a stored GitHub token). The value never enters the ledger, the settings document, a URL, or a log line. |
| **Repository install** | One source at one ref, installed at one scope for a set of targets. The unit of grouping, updating and removal. |
| **Store** | Astral's write-once content directory. The only place skill bytes live. |
| **Link farm** | The agent directories that point into the store. |
| **Target** | An agent and the directory it reads (`claude-code` → `.claude/skills`). |
| **Scope** | `global` (per user) or `project:<path>` (per repository). |
| **Ledger** | The record of every link Astral created. Ownership is defined by it. |
| **Tombstone** | A ledger row for a disabled skill: no link on disk, content kept. |

## 4. Layout on disk

```
$XDG_DATA_HOME/astral-plasma/skills/
  store/<host>/<owner>/<repo>@<ref>/<skill>/…      # content, write-once, hash-verified
  repos/<host>/<owner>/<repo>@<ref>.json           # discovery result: skills + hashes

$XDG_STATE_HOME/astral-plasma/skills/
  ledger.json                                      # every link we created (the source of truth)
  journal/<txid>.json                              # in-flight transaction, for crash recovery
  trash/<txid>/…                                   # replaced/removed items, for 7 days

$XDG_CACHE_HOME/astral-plasma/skills/
  git/<sha256(url@ref)>/                           # shallow clone used for discovery only
```

The **store is immutable**: a new ref means a new directory, so an update can never corrupt a
running agent's skills mid-read. Garbage collection only removes store paths no ledger row
references.

## 5. Domain model

```rust
// domain/skill.rs
pub struct SkillId(String);                       // frontmatter `name`, else directory name
pub struct SkillMeta { id: SkillId, description: String, subpath: String,
                       hash: String, files: u32, bytes: u64 }

// domain/skill_source.rs
pub enum SourceSpec {
    Git  { url: String, ref: Option<String>, subpath: Option<String>, auth: GitAuth },
    Local { path: PathBuf, watch: bool },
}
/// How a remote authenticates. Only `Credential` names a secret, and only by id.
pub enum GitAuth { Configured, SshAgent, Credential(CredentialId), Insecure } // never a stored secret
pub struct Credential { id: CredentialId, label: String, kind: CredentialKind,
                        host: String, // github.com — a token is scoped to a host
                        created: Timestamp, last_ok: Option<Timestamp> }
pub enum CredentialKind { GitHubToken, SshKey }
pub struct RepositoryKey { source: SourceSpec, scope: Scope, targets: Vec<TargetId> }

/// A source the user added by hand. `id` is a stable slug derived from the URL/path,
/// so `skills install --source mine` keeps working when the path moves.
pub struct AddedSource { id: SourceId, label: String, spec: SourceSpec,
                         added: Timestamp, last_seen: Option<Timestamp> }

/// Bytes live either in the immutable store or in a folder the user owns.
pub enum Origin { Store { ref_name: String, sha: String }, Local { path: PathBuf } }

// domain/skill_targets.rs  (data, not code)
pub struct Target { id: TargetId, label: String,
                    project_dir: String, global_dir: String,
                    link: LinkStyle }          // Relative | Absolute | Copy

// domain/skill_install.rs  (pure)
pub struct LinkRecord { link: PathBuf, target: String, target_id: TargetId,
                        repo: RepositoryKey, skill: SkillId, hash: String,
                        origin: Origin,        // store copy, or the user's own folder
                        state: LinkState }     // Linked | Disabled
pub struct Ledger { entries: Vec<LinkRecord>, schema: u32 }

pub enum LinkOp { Create { link: PathBuf, target: String },
                  Replace { link: PathBuf, target: String, expect: String },
                  Remove { link: PathBuf, expect: String } }
pub struct Plan { ops: Vec<LinkOp>, conflicts: Vec<Conflict>, changes: Vec<Change> }

pub fn plan_apply(desired: &[SkillInstall], ledger: &Ledger,
                  probe: &dyn FsProbe) -> Plan;
pub fn plan_disable(ledger: &Ledger, selector: Selector, probe: &dyn FsProbe) -> Plan;
pub fn plan_remove_repo(ledger: &Ledger, repo: &RepositoryKey, probe: &dyn FsProbe) -> Plan;
pub fn plan_update(diff: &RepoDiff, ledger: &Ledger, probe: &dyn FsProbe) -> Plan;
```

`FsProbe` is a port: `lstat`, `read_link`, `read_dir`, `exists_managed`. Production uses
`std::fs` without following symlinks; tests use an in-memory tree. **Every plan is a pure
function of (desired state, ledger, filesystem probe)** — that is what makes the symlink rules
testable instead of hopeful.

## 6. The link algebra

The rules, in the order they matter.

### 6.1 Desired state is a set of (link, target) pairs

For a skill installed for targets `{claude-code, codex}` at global scope:

```
~/.agents/skills/<skill>              -> store/…/<skill>        (canonical, real content? no: a link too)
~/.claude/skills/<skill>              -> ../../.agents/skills/<skill>
```

Every target gets a link. **No target gets a copy** unless its `LinkStyle` is `Copy` (a per-target
setting for agents that do not follow symlinks). The canonical `.agents` entry is a link into the
store, not a copy — one place owns bytes.

### 6.2 Links are relative and computed from the link's own directory

```
relative(from = ~/.claude/skills/<skill>, to = store/…/<skill>)
  = "../../.agents/skills/<skill>"        # when the target is another link
  = "../../../../../…/store/…"            # when linking straight into the store
```

Always `lstat` the final path, never `stat`: a broken link must be *seen* as broken, not
silently treated as absent.

### 6.3 Creation is atomic

```
symlink(target, dir/.astral-<skill>-<rand>) ; rename(.astral-…, dir/<skill>)
```

`rename(2)` is atomic on the same filesystem, so an agent reading the directory sees either the
old state or the new one — never a half-written link. If `rename` fails with `EEXIST`:

| What is at the path | Action |
| --- | --- |
| Nothing | create |
| Our own link (ledger row, target matches) | no-op (idempotent) |
| Our own link, target differs | `Replace`, keeping the old target in the journal |
| A link we did not create | **conflict**: refuse, report, offer "adopt" or "skip" |
| A real directory or file | **conflict**: refuse; never delete user content |

### 6.4 Removal is ownership-checked and non-following

Remove only when **all** of these hold:

1. a ledger row exists for the exact link path, and
2. the path is still a symlink, and
3. `read_link` equals what the ledger recorded.

Otherwise nothing is deleted and the doctor reports the drift ("managed link was replaced by
something else"). Deletion uses `unlink`, never `remove_dir_all`, and never follows a link.

### 6.5 Transactions, journal, and crash recovery

Applying a plan writes `journal/<txid>.json` (the full plan plus progress), performs ops in
order, then rewrites the ledger and deletes the journal. On startup, an existing journal is
resumed (ops are idempotent, so re-running is safe) or rolled back to the pre-plan state. This
is the same discipline as the app registry's crash-safe writer, and it is why "install
interrupted" leaves neither a link nor a ledger row unaccounted for.

### 6.6 Idempotence is a test, not a hope

`apply(plan)` twice must produce zero filesystem changes and zero ledger writes. `plan_*` must
return an empty plan when the world already matches. Both are asserted for every operation.

## 7. Enable, disable, and precedence

| Operation | Filesystem | Ledger | Content |
| --- | --- | --- | --- |
| `disable <skill>` | remove that skill's links | row → `Disabled` (keeps hash) | kept |
| `enable <skill>` | recreate links | row → `Linked` | reused (no fetch) |
| `disable --repo <r>` | remove every link of that repo | its rows → `Disabled` | kept |
| `remove <skill>` | remove links | row deleted | GC'd if unreferenced |
| `remove --repo <r>` | remove every link of the repo | its rows deleted | GC'd if unreferenced |
| `update --repo <r>` | relink changed skills only (new store ref) | rows rewritten with new hash | new ref kept, old GC'd |

**Precedence**: a repository has a default state (`enabled`); a skill may override it. Setting
the repo to disabled disables every skill that has no explicit override; enabling a single skill
inside a disabled repo is allowed and is shown as "1 of 12 enabled". Overrides are stored in the
ledger row's `state`, so the UI and the CLI never disagree about why something is on.

## 8. Sources

Two ways a source enters the manager:

1. **Found** — a catalog hit from the adapters below (GitHub search, skills.sh, local scan).
2. **Added** — the user registers a source explicitly. This is a first-class flow, not a
   fallback: *Add source → Local folder…* / *Add source → Git remote…*, and
   `skills source add` on the CLI. Added sources are persisted (`sources.json`), listed in the
   UI with their last-seen time and skill count, and usable by name (`--source mine`).

### 8.1 Added sources

| Kind | Input | Discovery | Install means |
| --- | --- | --- | --- |
| **Local folder** | any directory (`~/my-skills`, a mounted share, a worktree) | walk for `SKILL.md` (depth limit, ignores `.git`, `node_modules`, `.venv`) | **link in place**: the skill's real bytes stay in the folder; the target link points at `origin/path/<skill>` recorded as `Origin::Local`. Editing the folder is instantly live — this is the development loop. Optionally `--copy` to snapshot into the store instead. |
| **Git remote** | any URL git understands: `https://`, `git@host:team/repo.git`, `ssh://`, `git://`, `file://`, a bare repo, GitLab/Codeberg/self-hosted, plus `owner/repo` shorthand — **public or private** (§8.2) | shallow clone at `ref` (branch, tag or full SHA), then walk | copy into the immutable store as `Origin::Store`, pinned to the resolved SHA |

Both accept `--ref`, `--subpath` (monorepos: `packages/skills/ui`), and `--watch`
(local: re-scan on change and relink; git: only on explicit `update`).

**Authentication reuses what the machine already has** — the SSH agent, `~/.gitconfig`
credential helpers, or `GH_TOKEN` — and can also hold a GitHub token you give it (§8.2). The
manager never stores a secret in a place it does not own, never prompts for one in a hidden way,
and on failure prints git's own message plus the URL that failed (a private repo refusing is not
a bug to hide).

**Why local sources link instead of copy.** Copying a folder under active edit would make the
manager a stale mirror of the truth and turn every save into a manual "update" step. Linking in
place keeps one author of the bytes, so the agent sees the edit immediately. The trade-off is
recorded, not hidden: local skills have no pinned hash, so the UI marks them `local · live`
and the doctor re-checks the path on every pass; a missing folder is a `dangling` finding, and
`--copy` exists for anyone who wants reproducibility instead.

### 8.2 Private repositories and credentials

A private GitHub repo is a supported source, not a special case. Authentication is chosen per
source, and the choice is recorded as a **handle**, never as a value.

| Mode | What happens | When it is the right choice |
| --- | --- | --- |
| `Configured` (default) | git is left to its own devices: `~/.gitconfig` credential helper, `gh auth setup-git`, SSH agent for `git@` URLs | the machine is already set up for this host |
| `Credential(id)` | the manager injects a stored **GitHub fine-grained token** (contents: read) for that host | per-account tokens, CI-like machines, or several GitHub identities |
| `SshAgent` + optional key | `GIT_SSH_COMMAND` pinned to one key (`--ssh-key ~/.ssh/id_work`) | multiple GitHub accounts over SSH |

**Where the token lives.** In the OS keyring through Secret Service (`libsecret`), keyed
`astral-plasma/skills/<host>/<credential-id>`; on this machine `secret-tool` and a running
keyring are present, so that is the default. Only if no keyring is reachable does the manager
offer a `0600` file under `$XDG_STATE_HOME/astral-plasma/skills/credentials/` — and it says so
on screen, because a token on disk without encryption is a choice the user must see. The token is
**never** written to `ledger.json`, `sources.json`, `settings.json`, the journal, a log line, a
`--json` payload, or a git URL.

**How it is passed to git.** Not in the clone URL (it can leak into `.git/config`, `ps`, error
output and reflog). Instead:

```
GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
GIT_CONFIG_VALUE_0=Authorization: Basic base64(x-access-token:<token>)
```

passed through the child's environment only, cleared for the next command, and redacted from
any captured stderr before it reaches the UI. Shallow clone uses `--filter=blob:none` where
supported; private content is copied into the store like any other and never transmitted
anywhere (no telemetry, no skills.sh upload).

**Access check before install.** Adding a source performs `GET /repos/{owner}/{repo}` with the
chosen credential and reports one of four distinct outcomes — *ok*, *token expired*, *no access
to this repo*, *repo not found* (which is also what a private repo looks like without a token).
The dialog shows the result as a line under the URL field, so access is proven **before** the
user commits to installing anything.

**Expiry and revocation.** A `401/403` during a later `update` flips the source to
`needs-auth` with that same sentence and leaves the installed content untouched (a working skill
is not broken by an expired token); `skills auth test <id>` re-checks on demand.

### 8.3 Catalog adapters

`SkillSourcePort` with adapters, all configured by data (`sources.json`), all optional:

| Adapter | Discovery | Install | Availability |
| --- | --- | --- | --- |
| **Git** (`owner/repo[#ref]`, any git URL, `git@…`, local path) | shallow clone at `ref`, walk for `SKILL.md` (stop at a root `SKILL.md` unless `deep: true`) | copy subtree into the store | always |
| **GitHub search** | `GET /search/repositories?q=…+topic:agent-skills`, `GET /search/code?q=filename:SKILL.md` (code search needs a token) | resolves to Git | anonymous, rate-limited; a token (settings or `gh auth token`) raises limits |
| **skills.sh** | `GET /api/v1/skills/search?q=…`, `/curated`, `/skills/{source}/{skill}` (file tree), `/skills/audit/…` | resolves to `source` = `owner/repo` → Git | **requires a Vercel OIDC token**; adapter is off by default with that explanation, and a pasted `skills.sh/...` URL still resolves through GitHub |
| **Local path** | walk a directory | copy into the store | always |

Honest constraint: skills.sh's documented API authenticates with a Vercel OIDC token (per-team,
short-lived) — a desktop app cannot mint one. Three supported answers, in this order:

1. **GitHub-first discovery.** Skills live in git repositories, and skills.sh entries carry
   `source: owner/repo`; searching GitHub finds the same content. skills.sh becomes a
   *reference resolver* (paste a URL → we install from the repo it names).
2. **Opt-in token.** If the user supplies a Vercel OIDC token (or runs `vercel env pull`), the
   skills.sh adapter turns on with its search, curated set and audit results.
3. **CLI bridge (optional).** If `npx` exists, `skills find --json` is used for discovery only —
   never for installation, which is the part this manager exists to replace.

## 9. Consent and trust

A skill is instructions an agent follows with its own permissions, so install shows what it is:

- source and **pinned ref + resolved commit SHA**, file list and sizes, content hash;
- the frontmatter description, and whether the repo is public/verified;
- audit results when a source provides them (skills.sh/Gen/Socket/Snyk), clearly marked as
  *signals, not guarantees*;
- a warning that third-party skills can prompt-inject, linking the review checklist.

Consent is recorded per repository key (A35: consent is a decision with a record). `--accept`
exists for scripts, and the GUI reuses the app-platform consent card.

## 10. CLI

```
astral-plasma skills source add <path|url> [--ref R] [--subpath P] [--watch] [--copy] [--json]
astral-plasma skills source list [--json]
astral-plasma skills source refresh <id> [--json]     # re-scan / re-resolve the remote
astral-plasma skills source remove <id> [--keep-skills]  # forget the source; refuse while it has
                                                        # installed skills unless --keep-skills
astral-plasma skills auth add github --token-stdin [--host github.com] [--label work] [--json]
astral-plasma skills auth list [--json]                 # handles and hosts, never values
astral-plasma skills auth test <id> [--json]             # ok / expired / no-access / not-found
astral-plasma skills auth forget <id>                    # remove the keyring entry
astral-plasma skills search <query> [--source github|skills.sh|local|<added-id>] [--limit N] [--json]
astral-plasma skills inspect <owner/repo[#ref]> [--json]        # discovery + hashes, installs nothing
astral-plasma skills install <source> [--skill NAME|--all] [--target claude-code,codex]
                                     [--scope global|project:PATH] [--accept] [--json]
astral-plasma skills list [--repo] [--target] [--json]
astral-plasma skills enable  <skill>[@repo] | --repo <owner/repo> [--target]
astral-plasma skills disable <skill>[@repo] | --repo <owner/repo> [--target]
astral-plasma skills remove  <skill>[@repo] | --repo <owner/repo> [--purge]
astral-plasma skills update  [--repo <owner/repo>] [--check] [--json]
astral-plasma skills doctor  [--json] [--fix]
astral-plasma skills import  [--from npx-skills] [--dry-run]     # adopt an existing farm
```

Every command is `--json`-capable (the GUI is a client, not a second implementation), and every
mutation prints the plan it applied plus the ledger rows it touched.

## 11. GUI

A new platform app, `org.astralplasma.skills`, with `integrations: [{ "kind": "settingsPage",
"id": "skills" }]`. It renders through the existing design system — nothing new is invented.

### 11.1 The page

```
┌─ Skills ───────────────────────────────────────────────────────────────┐
│ ⌕ find a skill…          [ GitHub ] [ skills.sh ] [ mine ] [ + Add ]   │
│                                    scope: Global ⌄   targets: 3        │
├────────────────────────────────────────────────────────────────────────┤
│ owner/repo · 12 skills · ★ 2.4k installs        [ Install all ]        │
│  ├ web-design-guidelines   Design review for UI work      [ Install ]  │
│  └…                                                                    │
├─ Sources ──────────────────────────────────────────────────────────────┤
│ ▾ mine            ~/my-skills              local · live    12 skills   │
│   work            git@github.com:team/…    main@a91f3c2 · ok          │
│   old             git@github.com:team/…    needs-auth · token expired  │
├─ Installed ────────────────────────────────────────────────────────────┤
│ ▾ build-with-ai-hq/agent-skills · main@a91f3c2   [on]  ⋯ update/remove │
│    web-design-guidelines     linked → .agents/.claude   [on]           │
│    secure-llm-apps           disabled                     [off]        │
│ ▸ vercel-labs/skills · main                      [on]  ⋯               │
├─ Doctor ───────────────────────────────────────────────────────────────┤
│ ⚠ 1 unmanaged link in ~/.claude/skills/foo   [adopt] [skip] [remove]   │
└────────────────────────────────────────────────────────────────────────┘
```

### 11.2 Adding a source

```
┌─ Add source ──────────────────────────────────────────────────────────┐
│ ○ Local folder   ~/my-skills                        [ choose… ]       │
│ ● Git remote     git@github.com:team/private-skills.git               │
│   auth   [ Stored GitHub token · work ⌄ ]   or   [ Use git / SSH ]     │
│   ref    main (default)        subpath  (optional)                     │
│   ✓ access ok · 12 skills found · 4 installed already                  │
│                                                [ Cancel ]  [ Add ]     │
└───────────────────────────────────────────────────────────────────────┘
```

- Access is proven **in the dialog** (`ok`, `token expired`, `no access`, `not found`) and `Add`
  is disabled until it is `ok`, so a private repo is never a failed install that the user has to
  decode from a git error.
- The same dialog serves public repos; the auth selector simply stays on *Use git / SSH*.
- `Local folder` has a *Link live* switch (default on) with a one-line explanation that edits are
  picked up immediately, and a `Copy into store` alternative.

### 11.3 Behaviour

- **Repo/source cards** carry the master toggle and group actions; skill rows carry per-skill
  toggles and a link-health chip (`linked`, `disabled`, `conflict`, `missing`, `local · live`).
- Toggling is optimistic in the *UI only* — the row shows a pending state until the daemon's
  ledger write returns, then settles from truth. A failure never leaves a green toggle.
- Install progress is real: `resolve → auth → clone → discover → verify → copy → link` as
  labelled steps (the app-platform rule: no fabricated progress).
- Motion uses `Motion` tokens; the card expands with the expressive spatial curve, toggles use
  the capsule indicator. Doctor rows are the only place that uses warning colour.
- Nothing secret is ever rendered: `auth` rows show a label and a host, never a token, and the
  token field is write-only (`••••`, paste and forget).

## 12. Failure modes the design answers

| Scenario | Behaviour |
| --- | --- |
| Interrupted install | journal resume on next start; no orphan links, no phantom ledger rows |
| User's own directory at the skill name | conflict, never overwritten; "adopt" records it without touching it |
| Content GC'd while linked | doctor reports "dangling"; link is removed only with consent |
| Two agents pointing at each other | impossible: links always point into the store, one hop |
| Agent moved its directory (config change) | target table is data; `skills doctor` reports links in the old place and offers migration |
| Same skill name from two sources | both installs exist under distinct repo keys; a target cannot hold both, so the planner refuses the second with a named conflict |
| Repo deleted upstream | update reports "source unreachable", keeps the installed content (a working skill is not broken by a dead URL) |
| Private repo, token expired | source marked `needs-auth` with the exact sentence; installed skills keep working |
| Private repo, wrong identity | the access check names it before install (`no access to this repo`), instead of a git error the user must decode |
| Keyring locked at login | source reports `needs-auth · keyring locked`; nothing is installed silently, no token is written to disk as a "fix" |
| Token pasted into a URL | refused by the URL validator; the field says to use the auth selector so the token cannot reach `.git/config` |

## 13. Tests (TDD, per repo rules)

**Domain (no I/O)** — plan matrices: fresh install, correct link already present, wrong target,
unmanaged link, real directory, dangling link, relative-depth cases for every target table
entry; disable/enable round-trip is a no-op on second apply; repo-level operations enumerate
exactly that repo's rows; precedence (repo disabled + skill override); hash parity with the
ecosystem algorithm (sorted path+bytes SHA-256), so hashes are comparable with `skills-lock.json`.

**Application (fake ports)** — crash resume from a mid-plan journal; version bump replaces store
ref and relinks only changed skills; GC keeps referenced content; import adopts a farm without
creating duplicates.

**CLI contract** — `--json` shapes, exit codes, and the sentence each refusal prints.

**QML** — repo grouping, master/child toggle precedence, pending vs settled state, doctor rows,
and the consent card content (source, ref, hash, file count).

**Live** — real installs into a scratch `HOME`, verified with `ls -l`, `readlink`, and an agent
listing the skill; a removed repo must leave no link behind (`find … -xtype l` is empty).

## 14. Phases

| Phase | Content | Gate |
| --- | --- | --- |
| **P0** (½ d) | Verify the unknowns: skills.sh API auth from a desktop client, `npx skills find` behaviour, GitHub search without a token, **Secret Service availability and a private-repo clone through `gh`/a stored token**, and this machine's real agent directories. | Findings recorded in Appendix A, one real repo (public and private) resolved end to end. |
| **P1** (1 d) | Domain: target table, discovery model, ledger, `plan_*`, `FsProbe`, journal. | Full plan-matrix suite green; idempotence and crash-resume asserted. |
| **P2** (1 d) | Git source + credentials (§8.2) + install/enable/disable/remove/update/doctor through the CLI, both scopes. | Live: install a 6-skill repo, disable one, disable the repo, remove the repo; `find -xtype l` empty; doctor clean; a **private** repo installs with a stored token and the token appears in no file, log or argv. |
| **P3** (½ d) | GitHub search adapter (+ optional token), skills.sh adapter behind its token, consent payload. | Search returns a repo and installs from it; without a token skills.sh says exactly why. |
| **P4** (1 d) | The app: Settings → Skills page, daemon socket, grouping, toggles, doctor. | Live screenshots of search, install, repo toggle, doctor; QML suites green. |
| **P5** (½ d) | Update diff/report, ref pinning UI, import from `skills-lock.json`, trash/restore. | Update a pinned repo, see the per-skill diff, restore a removed repo from trash. |

## 15. Open decisions

1. **skills.sh access** — accept the token requirement (opt-in field), or make GitHub the only
   searchable source with skills.sh as URL resolution, or also bridge `npx skills find`?
2. **Default scope** — global (available in every project) or project (committed, shareable)?
   Their CLI defaults to project; this desktop shell may prefer global.
3. **Where the UI lives** — Settings → Skills as the management surface (proposed), plus a
   compact popover from the dock's AI item for installing a skill from a pasted URL?
4. **Adopt existing installs** — should P2's `import` adopt links created by `npx skills`
   (matching their lock's hashes) instead of starting clean? Recommended yes, dry-run first.
5. **Copy fallback** — keep symlink-only, or allow a per-target `Copy` style for agents that do
   not follow links (documented as a target setting either way)?
6. **Credential default for private repos** — rely on `gh auth token` / the SSH agent when they
   exist (zero setup, nothing stored), or always ask for a fine-grained token on first add?
7. **No-keyring fallback** — offer an encrypted-at-rest `0600` file, or refuse and tell the user
   to unlock a keyring? (Proposed: offer, with the warning on screen.)
8. **Local sources: link in place (proposed) or always copy?** Linking makes edits live and
   keeps one author of the bytes; copying makes them reproducible and hash-pinned.
