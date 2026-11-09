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
| **Source** | Where a skill comes from: `owner/repo[#ref]`, a git URL, a local path, or a skills.sh slug that resolves to one of those. |
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
pub enum SourceSpec { Git { url: String, ref: String }, Local { path: PathBuf } }
pub struct RepositoryKey { source: SourceSpec, scope: Scope, targets: Vec<TargetId> }

// domain/skill_targets.rs  (data, not code)
pub struct Target { id: TargetId, label: String,
                    project_dir: String, global_dir: String,
                    link: LinkStyle }          // Relative | Absolute | Copy

// domain/skill_install.rs  (pure)
pub struct LinkRecord { link: PathBuf, target: String, target_id: TargetId,
                        repo: RepositoryKey, skill: SkillId, hash: String,
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
astral-plasma skills search <query> [--source github|skills.sh|local] [--limit N] [--json]
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

```
┌─ Skills ───────────────────────────────────────────────────────────────┐
│ ⌕ find a skill…                    [ GitHub ] [ skills.sh ] [ Local ]  │
│                                       scope: [ Global ⌄ ]  targets: 3   │
├────────────────────────────────────────────────────────────────────────┤
│ owner/repo · 12 skills · ★ 2.4k installs        [ Install all ]        │
│  ├ web-design-guidelines   Design review for UI work      [ Install ]   │
│  ├ secure-llm-apps         OWASP LLM audit checklist      [ Install ]   │
│  └…                                                                    │
├─ Installed ────────────────────────────────────────────────────────────┤
│ ▾ build-with-ai-hq/agent-skills · main@a91f3c2   [on]  ⋯ update/remove  │
│    web-design-guidelines     linked → .agents/.claude   [on]           │
│    secure-llm-apps           disabled                     [off]        │
│ ▸ vercel-labs/skills · main                      [on]  ⋯               │
├─ Doctor ───────────────────────────────────────────────────────────────┤
│ ⚠ 1 unmanaged link in ~/.claude/skills/foo   [adopt] [skip] [remove]   │
└────────────────────────────────────────────────────────────────────────┘
```

- **Repo cards** carry the master toggle and the group actions; skill rows carry per-skill
  toggles and a link-health chip (`linked`, `disabled`, `conflict`, `missing`).
- Toggling is optimistic in the *UI only* — the row shows a pending state until the daemon's
  ledger write returns, then settles from truth. A failure never leaves a green toggle.
- Install progress is real: `resolve → clone → discover → verify → copy → link` as labelled
  steps (the app-platform rule: no fabricated progress).
- Motion uses `Motion` tokens; the repo card expands with the expressive spatial curve, toggles
  use the capsule indicator. Doctor rows are the only place that uses warning colour.

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
| **P0** (½ d) | Verify the unknowns: skills.sh API auth from a desktop client, `npx skills find` behaviour, GitHub search without a token, and this machine's real agent directories. | Findings recorded in Appendix A, one real repo resolved end to end. |
| **P1** (1 d) | Domain: target table, discovery model, ledger, `plan_*`, `FsProbe`, journal. | Full plan-matrix suite green; idempotence and crash-resume asserted. |
| **P2** (1 d) | Git source + install/enable/disable/remove/update/doctor through the CLI, both scopes. | Live: install a 6-skill repo, disable one, disable the repo, remove the repo; `find -xtype l` empty; doctor clean. |
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
