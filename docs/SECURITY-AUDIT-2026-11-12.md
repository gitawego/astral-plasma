# Security Audit — 2026-11-12

**Status:** complete. No real credential was found in the working tree or in any reachable
commit. Dependency advisories were found and fixed. Git history was **not** rewritten; §5 says
why.

## 1. Scope

- Working tree, all 411 commits, `main`, tags `v0.1.0`–`v0.1.3`, commit messages, and all 3,720
  Git objects (including unreachable blobs).
- 223 Rust dependencies from `daemon/Cargo.lock`.
- The new Streamable HTTP MCP surface, its stdio sibling, and the skills credential paths.
- 37 tracked screenshots (OCR).

## 2. Secret scan

| Check | Result |
| --- | --- |
| `gitleaks dir` (working tree) | 0 findings after hardening; 1 false positive before |
| `gitleaks git --log-opts=--all` (408 commits, 339 MB) | 43 findings, all the same false positive; 0 after the commit-scoped `.gitleaksignore` |
| Custom regex scan of the tree and every Git blob (before hardening) | only test fixtures and one doc-comment URL pattern |
| Commit-message scan | 0 |
| `.env`, `*.pem`, `*.key`, `id_rsa`, credential-store files in history | none |
| OCR of 37 screenshots for token/email patterns | 0 |
| Unreachable Git objects | same test fixtures only |

The scan covered OpenAI/Anthropic/OpenRouter-style `sk-…` keys, GitHub/GitLab tokens, AWS and
Google API keys, Slack tokens, private keys, JWTs, bearer headers, URLs with userinfo, password
assignments, and environment-variable assignments with long values. No live credential was used
to validate a finding; classification is by provenance, test comments, and naming.

## 3. Findings

### 3.1 False positive: DSH browser-session test vector

`tests/tst_dsh_auth.qml` used `base64url(bytes(range(32)))` as a deterministic HMAC test key.
It looked like a base64 credential to gitleaks but was never a secret. The current test computes
the bytes and calls `DshAuth.bytesToBase64Url(...)`, so no credential-shaped literal remains.

The 43 historical fingerprints are recorded in [`.gitleaksignore`](../.gitleaksignore) with a
commit-scoped comment. A real secret introduced by a new commit does not match those
fingerprints and is still reported.

### 3.2 Credential-shaped test fixtures

`daemon/tests/test_tool_scanners.rs`, `tests/tst_ai_page.qml`, and `tests/tst_dsh_auth.qml`
contained synthetic values such as `sk-cp-minimax-zcode-12345`. They were renamed to
`test-…` values (`test-minimax-zcode-key-12345`, etc.) so future audits do not chase them. The
scanner behaviour and assertions are unchanged.

### 3.3 Dependency vulnerabilities (fixed)

`cargo audit` found five vulnerable crate versions. They were updated inside their existing
semver ranges:

| Crate | Before | After | Advisory |
| --- | --- | --- | --- |
| `rustls` | 0.23.45 | 0.23.46 | RUSTSEC-2026-0346/0347/0348/0349 |
| `rustls-webpki` | 0.103.15 | 0.103.16 | RUSTSEC-2026-0382 |
| `rustix` | 1.1.4 | 1.1.6 | RUSTSEC-2026-0486 |
| `tokio` | 1.53.1 | 1.54.1 | RUSTSEC-2026-0386 |
| `async-executor` | 1.14.0 (yanked) | 1.14.1 | yanked crate |

After the updates `cargo audit` reports **0 vulnerabilities**. Three unmaintained warnings remain:
`zbus_names 4.3.5`, `zvariant 5.15.1`, and `zvariant_derive 5.15.1`, all transitive through
`zbus 5.19`. RustSec has no fixed upgrade; removing them requires a `zbus` 6 migration, which is
a separate API change. They are warnings, not known vulnerabilities.

### 3.4 MCP Streamable HTTP review

The endpoint is loopback-only (`127.0.0.1`), validates `Origin` (localhost/127.0.0.1/[::1] only),
caps headers at 64 KiB and bodies at 8 MiB, validates `MCP-Protocol-Version`, `Mcp-Method` and
`Mcp-Name` against the JSON body, rejects unknown modern methods with `404`/`-32601`, and keeps
legacy sessions in memory. `skill_read` accepts only normal relative paths; `..`, absolute paths,
backslashes and NUL are refused. The endpoint has no authentication or TLS, which is appropriate
for a loopback desktop service but means any local process can call it. Exposing it on a
non-loopback interface would require authentication first.

### 3.5 Credential handling

- Skill git credentials come from the environment, `gh`, or Secret Service; no plaintext fallback
  and no token in URLs, argv, the ledger, or `--json` payloads. Error paths redact bearer tokens.
- The release signing key is read from `MINISIGN_SECRET_KEY`/a local file; only the public key is
  tracked (`packaging/keys/astral-plasma.pub`).
- Runtime AI credentials live in the user's own config/state, not in this repository.

### 3.6 Credentials in process arguments (fixed)

Two paths put secrets in `argv`, where `ps` and `/proc/<pid>/cmdline` expose them:

| Path | Before | After |
| --- | --- | --- |
| AI account add | QML ran `ai add-account <provider> <credential>`; the CLI also accepted a positional credential | QML sets `ASTRAL_AI_CREDENTIAL` and passes `--credential-env`; scripts use `--credential-stdin`; a positional credential is refused |
| Wi-Fi connect | `nmcli dev wifi connect <ssid> password <psk>` | `nmcli connection add` without a secret, then `nmcli connection up ... passwd-file <0600 file>`; the file is removed by a drop guard, and errors redact the PSK |

The CLI paths now refuse a positional Wi-Fi password and require `--password-env`
(`ASTRAL_WIFI_PASSWORD`) or `--password-stdin`. A same-user process can still read an environment
variable from `/proc/<pid>/environ`; that is a deliberate trade-off for a local desktop service,
not a repository leak.

### 3.7 Credential files were world-readable (fixed)

The AI account store wrote `accounts/<provider>/*.json` and `credentials.json` with the default
umask (0644 in the audit environment), and the directories were 0755. On a multi-user machine
with a traversable home directory, another user could read stored provider credentials.

The store now writes credential files atomically with 0600 and creates account directories 0700.
`ensure_storage_migrated` repairs an existing tree on startup, including the one-time copy from
`~/.config/token-tracker`, and refuses to follow symlinks while doing so. The regression test is
`credential_files_and_directories_are_owner_only` in
`daemon/tests/test_ai_quota_self_contained.rs`.


## 4. Hardening changes

- [`AGENTS.md` §4d](../AGENTS.md) now makes both rules explicit: no hard-coded/fabricated
  content, no secrets in Git, rotate-and-rewrite after a leak, scan before push.
- [`.gitignore`](../.gitignore) covers `.env*`, private keys, credential stores, and local secret
  files.
- [`.gitleaksignore`](../.gitleaksignore) documents the commit-scoped false positives.
- Test fixtures are unmistakably synthetic; the DSH vector is computed.
- AI credentials and Wi-Fi passwords no longer travel in `argv`; see §3.6.
- AI account files and directories are now 0600/0700, with startup repair; see §3.7.
- `daemon/Cargo.lock` carries the patched dependency versions.

## 5. Why the history was not rewritten

Rewriting was authorised only **if an issue was found**. No real secret was found. A history
rewrite would change every commit hash and all four tags, force-push `main`, and invalidate every
existing clone — for a deterministic test vector and synthetic test fixtures. That is destructive
without a security benefit, so it was not done.

If a real secret is ever found:

1. Rotate/revoke it first; assume it is compromised.
2. Rewrite the affected refs (`git filter-repo --replace-text` or equivalent).
3. Force-push `main` and tags, and tell every clone owner to re-clone.
4. Re-run `gitleaks git --log-opts=--all` and confirm the fingerprint is gone.

## 6. Residual risks

- AI provider credentials are still stored in the user's config tree (now 0600/0700) because the
  quota/refresh paths need them without an interactive keyring unlock. Moving them to Secret
  Service is a worthwhile follow-up, not a repository leak.
- `zbus_names`, `zvariant`, and `zvariant_derive` are unmaintained upstream with no fixed upgrade;
  removing them requires a `zbus` 6 migration.
- The MCP HTTP endpoint is loopback-only and has no authentication/TLS. That is appropriate for a
  local desktop service; exposing it beyond loopback requires auth first.
- A same-user process can read environment variables and process memory; the fixes remove
  world-readable files and argv exposure, not same-user access.
- OCR covered the 37 tracked screenshots, not images that existed only in older commits.

## 7. Verification

```text
$ gitleaks dir
no leaks found

$ gitleaks git --log-opts=--all
408 commits scanned ... no leaks found   # with the documented .gitleaksignore

$ cargo audit --file daemon/Cargo.lock
0 vulnerabilities
3 allowed warnings (unmaintained zbus_names / zvariant / zvariant_derive)

$ make test
exit 0 — 1334 Rust tests, 169 QML suites, app boundaries clean
```

The test counts are the post-audit run; the QML and Rust suites are re-run after the fixture and
lockfile changes.
