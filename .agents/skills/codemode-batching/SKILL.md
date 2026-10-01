---
name: codemode-batching
description: Batch multi-file scans, cross-suite audits, and large-output filtering in the astral-plasma repo through one codemode script instead of many sequential read/bash calls. Use when a question spans 3 or more files, when auditing all tests/tst_*.qml suites or all dock/popouts modules, when checking one identifier across shell/ dock/ dashboard/ components/ services/ daemon/src/, or when long make test / cargo output must be reduced before it reaches context.
---

# Codemode batching for astral-plasma

Intermediate tool results never enter context — only what the script passes to `text()` does.
That is the whole point: do the fan-out and the filtering inside one script, return a distilled
answer (`file:line`, counts, a short table), and keep the raw corpus out of the transcript.

## Use it when

- A fact must be checked across 3+ files ("where is `blurRegion` set", "which suites touch glass alpha").
- The scope is an entire directory: `tests/tst_*.qml`, `dock/popouts/`, `dashboard/tabs/`, `components/`, `daemon/src/`.
- One identifier or contract must be traced across QML and Rust together (e.g. a theme token in
  `theme/Theme.qml` vs its consumer in `shell/`, or a DBus name in `daemon/src/` vs `services/`).
- A large log or diff needs reduction before it is worth context (see the guardrails below).

## Do not use it when

- A single `bash` or `read` call answers it — the sandbox load is pure overhead.
- Each result must steer the next call (debugging, bisecting a failing suite). Native sequential
  calls adapt; a script is written blind, with every argument fixed before anything is seen.
- A build or test suite must actually run — `make test` / `cargo` belong in a native `bash` call so
  the exit code and tail are directly visible.
- The task is a file edit. See guardrails.

## Recipe

Start the script with an options line; the output budget defaults to 10000 tokens, which is far more
than a distilled answer needs:

```js
// @options: {"max_output_tokens": 700, "timeout_ms": 60000}
```

Available globals: `tools.<name>(args)`, `ALL_TOOLS`, `searchTools()`, `describeTool()`,
`describeNamespace()`, `store()` / `load()` (persist across calls in this session), `text()`,
`image()`, `exit()`, plus the `models` API. There is no filesystem, network, or timers — get file
lists by calling `tools.bash` inside the same script, and note that `grep`, `find`, and `ls` are not
declared tools here, so use `tools.bash` for them. A failed nested call rejects with an `Error`
carrying the tool's error text; use `Promise.allSettled` so one bad path does not sink the batch.

### Example: audit every QML suite

```js
// @options: {"max_output_tokens": 800, "timeout_ms": 120000}
const list = await tools.bash({ command: "ls tests/tst_*.qml" });
const files = list.trim().split("\n").filter(Boolean);
const settled = await Promise.allSettled(files.map(async (f) => {
  const src = await tools.read({ path: f, offset: 1, limit: 6000 });
  const asserts = (src.match(/if \(!/g) ?? []).length;          // suite's own assert() calls
  const mode = src.includes("XMLHttpRequest") ? "reads-src" : "pure-js";
  return `${f.replace("tests/", "")}  asserts=${asserts}  ${mode}`;
}));
const rows = settled.filter((r) => r.status === "fulfilled").map((r) => r.value).sort();
const failed = settled.filter((r) => r.status === "rejected").length;
text(`${rows.length}/${files.length} suites listed (${failed} unreadable)\n${rows.join("\n")}`);
```

### Example: trace one identifier across the tree

```js
// @options: {"max_output_tokens": 600}
const pat = "blurRegion";
const hits = await tools.bash({
  command: `grep -rlF '${pat}' --include='*.qml' --include='*.rs' shell dock dashboard components services daemon/src 2>/dev/null`,
});
const files = hits.trim().split("\n").filter(Boolean);
const out = [];
for (const f of files) {                       // sequential keeps memory flat on large trees
  const src = await tools.read({ path: f, offset: 1, limit: 8000 });
  const n = (src.match(new RegExp(pat, "g")) ?? []).length;
  out.push(`${String(n).padStart(3)}  ${/^tests\//.test(f) ? "test" : "src "}  ${f}`);
}
out.sort((a, b) => parseInt(b) - parseInt(a));
text(`${files.length} files reference ${pat}\n${out.join("\n")}`);
```

## Guardrails

- **Never batch edits through codemode.** Exact-text replacement inside a JS string literal adds an
  escaping layer between the source and `oldText`; a silent mismatch there is a regression. Use the
  native `edit` tool, where edits are visible and diffable in the transcript.
- **Never run `make test` or `cargo` inside a script.** Run them natively (see `AGENTS.md` §3:
  100% pass rate is required, which means the exit code must be inspected). If output needs
  reduction, filter it with a native `bash` pipe, or read a captured log via `tools.read`.
- **Prefer the smallest useful window.** `read` with `offset` + `limit` over whole-file reads;
  aggregate with counts and `file:line` rather than pasting file bodies.
- **Pass `offset` and `limit` explicitly** on every `read` call — the schema requires them.
- **Keep the result cited.** Every claim from a script should carry `file:line` so it can be
  verified with a normal `read` afterwards.
- Bulk reads are safe in parallel. Writes are not; do not fan out `bash` invocations that mutate
  files (`git checkout`, `sed -i`, palette regeneration) inside one script.

## Operational notes

- This skill loads only with project trust. This repository is not currently trusted
  (`~/.pi/agent/trust.json` has no entry for it), so the first launch after this file appears will
  ask; declining leaves the skill inert and nothing else changes.
- Force it when needed with `/skill:codemode-batching`; run `/reload` after editing this file.
- `codemode.mode` stays `"on"` — `"only"` would hide `web_search` and `bg_wait` behind the 3000-token
  catalog budget and add an escaping hazard to every edit.
