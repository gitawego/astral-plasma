# Skills Manager

> **Status**: P0–P6 implemented, including the MCP find-and-load surface.
> **Scope**: an Astral-owned manager for agent skills — discovery across sources,
> repository-scoped install/uninstall, symlink farms that cannot corrupt a home directory,
> per-skill or per-repository enable/disable, and an MCP server that can load a skill into a
> session without installing it.
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
6. **Adopt what is already on the machine**: a farm built by `npx skills` can be imported
   (hashes matched, nothing rewritten) instead of duplicated or stranded (D4).
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
  store/<host>/<owner>/<repo>/<ref>@<sha12>/<skill>/…   # content, write-once, hash-verified
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

/// Where the bytes came from. `Adopted` is a farm `npx skills` created, recorded so we may
/// unlink it later without ever claiming we created it (D4).
pub enum Origin { Store { ref_name: String, sha: String }, Local { path: PathBuf },
                  Adopted { by: String, hash: String } }

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
| `Configured` (default) | git is left to its own devices: `~/.gitconfig` credential helper, `gh auth setup-git`, SSH agent for `git@` URLs | the machine is already set up for this host — **tried first, always** (D6) |
| `Credential(id)` | the manager injects a stored **GitHub fine-grained token** (contents: read) for that host | per-account tokens, CI-like machines, or several GitHub identities |
| `SshAgent` + optional key | `GIT_SSH_COMMAND` pinned to one key (`--ssh-key ~/.ssh/id_work`) | multiple GitHub accounts over SSH |

**Where the token lives.** In the OS keyring through Secret Service (`libsecret`), keyed
`astral-plasma/skills/<host>/<credential-id>`; on this machine `secret-tool` and a running
keyring are present, so that is the default. If no keyring is reachable the manager **refuses to
store** the token and points at `GH_TOKEN` in the environment instead (D7) — an unencrypted token
on disk is a worse outcome than an inconvenient one. The token is **never** written to
`ledger.json`, `sources.json`, `settings.json`, the journal, a log line, a `--json` payload, or a
git URL.

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

**Access check before install.** Adding a source first tries the machine's own credentials
(D6); only a refusal leads to the token prompt. The check is `GET /repos/{owner}/{repo}` with the
credential in use and reports one of four distinct outcomes — *ok*, *token expired*, *no access
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
| **skills.sh** | `GET /api/search?q=…` — public, the endpoint their CLI uses; the richer `/api/v1/*` family (audits, file trees, curated) requires a Vercel OIDC token and is optional | resolves to `source` = `owner/repo` → Git | **no token** for search; the authenticated extras stay unused |
| **Local path** | walk a directory | copy into the store | always |

How skills.sh is searched: **the public `/api/search` endpoint** (`{ skills: [{ id, name,
   source, installs }] }`), which is what the official CLI calls and which returns results without
   any credential. The *documented* `/api/v1/*` family — file trees, audits, the curated set —
   authenticates with a per-team Vercel OIDC token a desktop app cannot mint, so those extras are
   optional and unused; search itself never asks the user for anything.

Because every hit carries `source: owner/repo`, installation is always git: the catalog is a
discovery surface, and the repository is the thing we verify and pin.

## 9. Consent and trust

A skill is instructions an agent follows with its own permissions, so install shows what it is:

- source and **pinned ref + resolved commit SHA**, file list and sizes, content hash;
- the frontmatter description, and whether the repo is public/verified;
- audit results when a source provides them (skills.sh/Gen/Socket/Snyk), clearly marked as
  *signals, not guarantees*;
- a warning that third-party skills can prompt-inject, linking the review checklist.

Consent is recorded per repository key (A35: consent is a decision with a record). `--accept`
exists for scripts, and the GUI reuses the app-platform consent card. An **adopted** farm is not
consent (D4): it is listed as `adopted · unverified` with its on-disk hash until the user reviews
it, and adoption never rewrites the files it found.

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
astral-plasma skills install <source|url> [--skill NAME|--all]
                                     [--target claude-code,codex] [--copy-target NAME]
                                     [--scope project:PATH] [--accept] [--json]
                                     # scope defaults to global (D2); targets default to the
                                     # agents detected on this machine (D9)
astral-plasma skills list [--repo] [--target] [--json]
astral-plasma skills enable  <skill>[@repo] | --repo <owner/repo> [--target]
astral-plasma skills disable <skill>[@repo] | --repo <owner/repo> [--target]
astral-plasma skills remove  <skill>[@repo] | --repo <owner/repo> [--purge]
astral-plasma skills update  [--repo <owner/repo>] [--check] [--json]
astral-plasma skills doctor  [--json] [--fix]
astral-plasma skills import  [--from npx-skills] [--dry-run|--apply]  # adopt what already exists (D4)
astral-plasma skills mcp                             # MCP: --http (Streamable HTTP) or --stdio; find + load, never install
```

Every command is `--json`-capable (the GUI is a client, not a second implementation), and every
mutation prints the plan it applied plus the ledger rows it touched.

## 11. GUI

A new platform app, `org.astralplasma.skills`, with `integrations: [{ "kind": "settingsPage",
"id": "skills" }]`. It renders through the existing design system — nothing new is invented.

### 11.1 The page

```
┌─ Skills ───────────────────────────────────────────────────────────────┐
│ ⌕ find a skill…  or paste a repo/URL…   [ GitHub ] [ skills.sh ] [ + Add ] │
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

## 12b. MCP: find and load without installing

`astral-plasma skills mcp` is a Model Context Protocol server. **Streamable HTTP is the primary
transport**: the running shell (and `astral-plasma serve`) exposes `POST
http://127.0.0.1:8942/mcp`, and `astral-plasma skills mcp --http [--port N]` runs the same
endpoint standalone. Stdio (`astral-plasma skills mcp` or `--stdio`) remains for clients that
launch a command rather than connect to a URL. It is an **additional** discovery and loading
surface, not a replacement for installation: links and the ledger remain the way a skill becomes
available to an agent that only reads its own skill directory.

### 12b.1 Why "load" is a tool result

MCP has no API that injects text into the model's context from outside a request. The protocol's
only channel is the response to a tool call, so `skill_load` returns the skill's `SKILL.md` as a
content block; that response **is** the load. No file is written to the project, the agent
directories, the store, or the ledger. The server keeps the loaded skill's bytes in memory for
the life of the process, which is exactly the "current session" boundary. Restarting the server
forgets loaded skills; the source can be loaded again.

### 12b.2 Tools

| Tool | Input | Returns | Mutates |
| --- | --- | --- | --- |
| `skill_search` | `query`, `source` (`github`, `skills.sh`, `all`, `added`, or one added source id), `limit` | catalog hit or skill rows: `source`, `name`, `description`, `installs`, `url`, `kind`, `trust` | nothing |
| `skill_inspect` | `source` (owner/repo, git URL, folder, or added id) | `source`, `id`, commit SHA, ref, and each skill's id, description, hash, file count, bytes, `installed` | nothing |
| `skill_load` | `source`, `skill` | metadata + the skill's `SKILL.md` verbatim; `handle` is `<sourceId>:<skill>`, `files` is the manifest | no project, agent, store or ledger change; a git fetch may refresh the XDG cache |
| `skill_read` | `handle`, `path` relative to the skill root | file text, or a base64 JSON envelope for binary content | nothing |

`skill_inspect` and `skill_load` accept the same source syntax as the CLI, plus the stable id an
added source already has. `skill_search` with `source: "added"` scans every added source and
filters by a case-insensitive match on the skill id or description; naming one added id scans
only that source. A git source is fetched for the scan; a local source is walked live (D8).

The server is dual-era: it advertises `2026-07-28` through `server/discover` and serves
per-request `_meta` statelessly, while continuing to answer the `initialize` handshake for
`2025-11-25`, `2025-06-18`, `2025-03-26` and `2024-11-05`. Every request is independent; a
request with a modern `_meta` gets `resultType: "complete"` and the server identity in its
`_meta`. An unsupported modern version gets `-32022` with the list of supported revisions.
`tools/list` and `tools/call` keep the same shape in both eras.

Over Streamable HTTP, every JSON-RPC message is its own `POST /mcp`; responses are
`application/json` (the transport permits JSON or an SSE stream, and these tools have no progress
to stream). The modern headers are validated against the body: `MCP-Protocol-Version` must match
`params._meta`, `Mcp-Method` must match `method`, and `Mcp-Name` must match `params.name` for
`tools/call`; a mismatch is `400` with `-32020`. Unknown modern methods are `404` with `-32601`.
Legacy `initialize` returns an `Mcp-Session-Id`, later requests may carry it, and `DELETE /mcp`
ends it. `GET /mcp` is `405`: this server has no server-initiated stream. A foreign `Origin` is
`403`, and the endpoint binds loopback only.

The server also answers `ping`, ignores notifications without replying, and returns tool
failures in-band (`isError: true`) rather than turning them into JSON-RPC errors. Stdio carries
only JSON-RPC; diagnostics go to stderr.

### 12b.3 Limits and trust

- A `SKILL.md` over 1 MiB is refused rather than truncated: half a skill's instructions are worse
  than an error.
- One `skill_read` file is capped at 512 KiB. Binary files are returned as
  `{encoding:"base64", …}` rather than lossy text.
- `skill_read` accepts only normal, relative POSIX components; `..`, absolute paths, backslashes
  and NUL are refused, so one loaded skill cannot read another skill's files or the host's.
- A git source is fetched through the existing shallow-clone cache under
  `$XDG_CACHE_HOME/astral-plasma/skills/git`; the store and ledger stay untouched.
- Loading a third-party skill gives its instructions to the model. The server's `instructions`
  tell the client to load only requested or clearly relevant skills and to weigh their content
  against the user's request; the tools are annotated `readOnlyHint: true`. Consent for a
  *persistent* install is still the install flow's job (§9).

### 12b.4 Client configuration

The endpoint is live while the shell runs, or while `astral-plasma serve` runs:

```
http://127.0.0.1:8942/mcp
```

Claude Code:

```bash
claude mcp add --transport http astral-skills http://127.0.0.1:8942/mcp
```

Pi (the Copilot harness):

```bash
pi mcp add astral-skills --url http://127.0.0.1:8942/mcp
```

Claude Desktop, Cursor and other `mcpServers` JSON clients:

```json
{
  "mcpServers": {
    "astral-skills": {
      "type": "http",
      "url": "http://127.0.0.1:8942/mcp"
    }
  }
}
```

Codex (`~/.codex/config.toml`):

```toml
[mcp_servers.astral-skills]
url = "http://127.0.0.1:8942/mcp"
```

OpenCode (`opencode.json`):

```json
{
  "mcp": {
    "astral-skills": {
      "type": "remote",
      "url": "http://127.0.0.1:8942/mcp",
      "enabled": true
    }
  }
}
```

When the shell is not running, start the same endpoint alone:

```bash
astral-plasma skills mcp --http --port 8942
```

If the port is already in use, nothing silently moves: `skills mcp --http` exits with the
sentence naming the port, and the shell logs the bind failure instead of pretending `/mcp`
exists. Point the client at the process that already owns the URL, choose another standalone
port, or set `ASTRAL_API_PORT` for the shell and configure the client to the same URL. A fixed
URL in a client is configuration, so an automatic fallback port would be worse than a clear
failure.

Clients that can only launch a child process use the stdio fallback:

```bash
claude mcp add astral-skills -- astral-plasma skills mcp --stdio
pi mcp add astral-skills -- astral-plasma skills mcp --stdio
```

The server uses the `$HOME`/`$XDG_*` of the process that runs it: the shell for `/mcp`, or the
process that starts `skills mcp --http`. A sandboxed client connecting over HTTP sees the server
process's added sources, not its own; the MCP server and the install manager read one ledger.

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

**MCP contract** — the `server/discover` probe, a stateless modern request marked
`resultType: "complete"`, an unsupported version error, initialize/tools-list/ping, tool errors
in-band, notifications unanswered, stdout pure JSON-RPC, a local and a git skill loaded without a
link or ledger row, `skill_read` returning a reference, and traversal (`../`) refused.
`daemon/tests/test_skill_mcp.rs` drives the stdio binary; `daemon/tests/test_mcp_http.rs` drives
the Streamable HTTP endpoint: session mint/validation/delete, header/body mismatch (`-32020`),
unknown method (`404`/`-32601`), `202` notifications, `405` GET, foreign-Origin `403`, and a real
TCP socket.

**QML** — repo grouping, master/child toggle precedence, pending vs settled state, doctor rows,
and the consent card content (source, ref, hash, file count).

**Live** — real installs into a scratch `HOME`, verified with `ls -l`, `readlink`, and an agent
listing the skill; a removed repo must leave no link behind (`find … -xtype l` is empty).

## 14. Phases

Status: **P0–P6 implemented**, each with the tests named in §13 and the live checks recorded in
Appendix B.

| Phase | Content | Gate |
| --- | --- | --- |
| **P0** (½ d) ✅ | Verify the unknowns: skills.sh API auth from a desktop client (D1), GitHub search without a token, pasted-URL resolution, **Secret Service availability and a private-repo clone through `gh`/a stored token** (D6/D7), and this machine's real agent directories (D9). | Findings recorded in Appendix A, one real repo (public and private) resolved end to end, and the detected target list printed. |
| **P1** (1 d) ✅ | Domain: target table, discovery model, ledger, `plan_*`, `FsProbe`, journal. | Full plan-matrix suite green; idempotence and crash-resume asserted. |
| **P2** (1 d) ✅ | Git source + credentials (§8.2) + install/enable/disable/remove/update/doctor through the CLI, global default and project scope, plus `import` (D4, dry-run first). | Live: install a 6-skill repo, disable one, disable the repo, remove the repo; `find -xtype l` empty; doctor clean; a **private** repo installs with a stored token and the token appears in no file, log or argv. |
| **P3** (½ d) ✅ | GitHub repository search and skills.sh's public `/api/search` (both tokenless), consent payload. | Search returns a repo and installs from it from either source; a pasted skills.sh URL resolves through GitHub. |
| **P4** (1 d) ✅ | The app: Settings → Skills page, daemon socket, grouping, toggles, doctor. | Live screenshots of search, install, repo toggle, doctor; QML suites green. |
| **P5** (½ d) ✅ | Update diff/report, ref pinning UI, one-deep rollback (D11), trash/restore. | Update a pinned repo, see the per-skill diff, roll back one ref, restore a removed repo from trash. |
| **P6** (½ d) ✅ | MCP: Streamable HTTP at `POST /mcp` (primary) and stdio; search, inspect, load and read; session-only loading; no project mutation. | `test_mcp_http.rs` (session lifecycle, header validation, Origin, real socket) and `test_skill_mcp.rs` (stdio protocol) both green; a local skill loads without a link or ledger row, a git skill reads without a store copy, traversal is refused; the install suites stay green. |

## 15. Decisions

Settled here so implementation has no open questions. Each is reversible; each says why.

| # | Decision | Why |
| --- | --- | --- |
| **D1** | **Both catalogs are searched, neither needs a token.** GitHub uses `/search/repositories`; skills.sh uses `/api/search` — the endpoint its own CLI calls, which is public. A pasted `skills.sh/...` URL also resolves through GitHub. No `npx skills` bridge. | The documented `/api/v1/*` family requires a per-team Vercel OIDC token, which sent the first implementation to a GitHub-only fallback. Their CLI's own search proved there is a public endpoint; using it is simpler for the user and removes a refusal that should never have existed. |
| **D2** | **Global scope by default**; project scope available as `--scope project:PATH`. | A shell is not inside a repository: the GUI has no cwd, so "install for this project" has no referent there. Globals are the manager's inventory; project scope stays a CLI affordance for terminal-in-repo work. |
| **D3** | **One management surface: Settings → Skills.** No dock popover in v1; the page carries a paste-URL install box. | The dock item is already a quota surface, and a second, smaller manager would be a second set of states to keep true. A URL box covers the "just install this one" case without one. |
| **D4** | **Adopt existing installs** (`skills import --from npx-skills`), dry-run by default, entries recorded as `Origin::Adopted`. | Users already have farms built by `npx skills`. Starting clean would strand them or, worse, duplicate every skill. Adoption hashes what is on disk and only ever unlinks what it recorded. |
| **D5** | **Symlinks by default; `Copy` is a per-target opt-in** (`--copy-target claude-code`). | Every relevant agent follows symlinks (Claude Code, Codex, Cursor, Gemini, Copilot, OpenCode). Copying is the exception for an agent that does not, and it must be the user's choice because it breaks the "one author of the bytes" property. |
| **D6** | **Credentials: prove the machine first.** Try git's own configuration, the SSH agent and `gh auth token`; only when that fails offer to store a token in the keyring. | The zero-setup path is the common case, and asking for a secret before knowing one is needed trains people to paste secrets into dialogs. |
| **D7** | **No plaintext token fallback.** Without a reachable keyring the manager refuses to store a token, and instead points at `GH_TOKEN` in the environment. | An unencrypted token on disk is a worse outcome than an inconvenient one. The environment variable is a supported, explicit alternative that leaves nothing behind. |
| **D8** | **Local sources link in place** (`--copy` per source is available). | The reason to add a folder is that you are editing it: a copy would make the manager a stale mirror and turn every save into a manual update. Remotes stay immutable-store copies. |
| **D9** | **Targets default to detected agents** (a target whose agent config exists), shown as a count and overridable with `--target`. | Installing to 79 directories when four agents exist is noise; installing to none because the user forgot a flag is a silent no-op. Detection plus an explicit count is honest either way. |
| **D10** | **Keep the ecosystem's canonical layout**: `.agents/skills` remains the canonical link farm, `.claude/skills` links into it, and content is addressed by hash the same way `skills-lock.json` does. | Users run both tools and several agents read those paths. Interop is worth more than a private layout, and matching their hash function lets us adopt and compare installs. |
| **D11** | **One-deep rollback**: an update keeps the previous store ref until the next successful update. | Updating a skill should be recoverable for a day without a full version-history store. Two refs per repository is a bounded cost. |
| **D12** | **No telemetry, no uploads.** | Skills are user content; nothing about them leaves the machine. |
| **D13** | **MCP loads beside install, not instead of it.** `skills mcp` returns a skill's `SKILL.md` in a tool result and keeps it only for the server's lifetime; the link farm, ledger, store and consent flow are unchanged. | An agent that only reads its own skill directory still needs an install; a session that needs one skill should not have to mutate a project to try it. Both paths share search and inspection, and differ only in whether bytes are linked. |
| **D14** | **Streamable HTTP at `POST /mcp` is the primary MCP transport; stdio remains as a fallback.** The shell's existing localhost API server mounts the endpoint, and `skills mcp --http` runs it standalone. | A URL-based client cannot launch a child process, and the shell already has a loopback HTTP server. Both transports share one `McpServer` handler, so tool behaviour cannot drift between them. |

---

## Appendix A — P0 findings (measured on this machine, 2026-11-09)

| Question | Result |
| --- | --- |
| GitHub repository search without a token | **works** (`/search/repositories`, 2 855 hits for `agent skills SKILL.md`), anonymous and rate-limited; a token raises it |
| skills.sh API without a token | `/api/v1/*` → **401** `authentication_required` (Vercel OIDC); **`/api/search?q=…` → 200** with `{ skills: [{ id, name, source, installs }] }`, the endpoint the official CLI uses — the public path D1 now takes |
| `gh auth token` | present (`gho_…`) → the zero-setup credential path (D6) is real |
| Secret Service | `secret-tool store`/`lookup` round-trip works → keyring storage (D7) is available |
| git | 2.56.0 |
| Agent directories present | `~/.claude/skills`, `~/.agents/skills`, `~/.config/opencode/skills`, `~/.copilot/skills`, `~/.pi/agent/skills`, `~/.codex/skills`; `~/.gemini/skills` and `~/.cursor/skills` absent (D9 detection has something to detect) |
| Private repo reachable through `gh` | yes (`relay-ssh`, `PRIVATE`) → the P2 private-repo gate is testable |
| Existing farm | `~/.agents/skills` holds **real directories** plus **absolute-path symlinks into a working checkout**; `~/.claude/skills` mixes a **real directory** (`agents-sdk/`) with symlinks into `.agents`; one **dangling link** (`~/.claude/skills/od-contribute`); `~/.agents/.skill-lock.json` exists (20 KB) |

The last row is the design's problem statement, on disk, today: two ownership models in one
tree, a link that outlived its target, and a canonical directory that is sometimes real content
and sometimes a link elsewhere. It is also the acceptance material for `skills import` (D4):
mixed real/link farms, absolute and relative links, and a dangling entry are the cases the
importer and the doctor must classify — not tidy fixtures.

---

## Appendix B — What the implementation found

Bugs the tests caught, in the order they appeared. Each one was a design assumption that the
filesystem disagreed with.

| Finding | Why it existed | What it changed |
| --- | --- | --- |
| The ledger was written to `~/.local/state/skills` | `SkillPaths::from_env` appended `skills/…` to the XDG root without the product directory | paths now include `astral-plasma`; the shell's `Paths.skillsLedgerPath` and the daemon agree, so the page's file watch actually fires |
| `skills remove --source <id>` removed nothing | the positional parser took the flag's *value* as a skill name | one parser that skips value flags, pinned by `test_skill_cli.rs` |
| A disabled skill was reported as `missing` by the doctor | a disabled row has no link by design | the doctor respects the recorded state |
| An adopted farm read as `replaced` | a real directory is the correct state for an adopted skill | `Origin::Adopted` is understood by the planner and the doctor (content hash instead), and disabling moves it to the trash |
| Rollback linked a farm at the version directory | the store path ends in the skill (`…@sha/skill`), and the helper dropped the last component | the previous version is `<ref>@<prev12>/<skill>` |
| Rolling back twice bounced between the same pair | the swap recorded the *new* current instead of the one just left | the pre-rollback origin becomes the next target |
| A repository row read `0 of 0 enabled` | `Array.isArray` is false for a QML list proxy | `listOf()` normalises both shapes |
| The settings page could not see `AppStates` | a relative import and a module import are two singleton registrations (C.13), and the offscreen runner cannot resolve the module at all | the shell passes `integrations` down as data; no settings file imports the host |
| Every offscreen suite broke when a `qmldir` appeared in `Kernel/services` | a directory import becomes a module import, which instantiates Quickshell singletons eagerly | the directory stays `qmldir`-free; only `Host` is a module |
| A local source remembered `--copy` only if typed again | `install` re-parsed the input instead of the recorded source | an already-added source's spec (copy, watch, ref) is reused |
| The MCP server only spoke the `initialize` handshake | the current revision (`2026-07-28`) is stateless and a modern client probes `server/discover`; it would never send `initialize` | the server is dual-era: `server/discover`, per-request `_meta`, `resultType: "complete"` and `-32022` for an unknown version, while `2025-11-25` and earlier still negotiate normally |

Appendix A's observation that the machine already had a **mixed** farm (real directories, relative
links, an absolute link into a checkout, one dangling link) was the acceptance material for
`import`: adoption classifies and records all four shapes without rewriting any of them.

### B.2 Two follow-ups found while finishing the settings surface

| Finding | Why | Fix |
| --- | --- | --- |
| The AI dock item stayed hidden while the app was **enabled** | the dock imported the `Host` directory relatively to ask `AppStates.integrationEnabled(...)`, which is a second singleton registration with no data (C.13) | the dock reads the pushed boolean `AiTokenService.appEnabled`; the shell derives it from `isEnabled(app) && integrationEnabled("dockItem","ai")`, so the declaration still decides and there is one instance |
| A private repository failed with "could not read Username" although `gh` was authenticated | `SkillContext::auth` consulted only the keyring and the environment, not the machine's `gh` token — D6 says prove the machine first | ambient credentials (`GH_TOKEN`/`ASTRAL_SKILLS_TOKEN`, then `gh auth token`) are tried before the keyring; verified against a real private repository (46 skills discovered, nothing installed) |

| The two catalogs looked identical, and the old list stayed under the new tab | the row rendered `source` as its title, which is the repository for both kinds, and switching catalogs did not clear `results` while the search box was empty | a hit now carries a `repo`/`skill` badge, shows the skill as the title when it is one, names its repository as context, and the action reads Install repo / Install skill; changing the catalog clears the list first and only re-searches when there is a query |
| skills.sh search was refused as "needs a Vercel OIDC token" | only the documented `/api/v1/*` family was tested; the CLI's own `find` calls a different, public endpoint | `/api/search?q=…` is used, no credential asked for; the wrong refusal is now a regression test (`skills_sh_search_does_not_ask_for_a_token`) |

`--copy-target` is wired end to end as well: it flips the named targets to `LinkStyle::Copy`, the planner emits copy operations for them, disabling moves a copy to the trash instead of deleting it, and a test asserts that the canonical target still links while the copy target holds real files.
