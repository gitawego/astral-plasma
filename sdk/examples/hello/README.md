# Hello Astral

The reference fixture for the app platform, and the app `tests/platform_e2e.sh`
drives through `new → dev → test → pack → install → launch → remove`.

- `manifest.json` — the contract (§8.1 of `docs/APPS-PLATFORM-SPEC.md`).
- `shell.qml` — a hosted payload root: `quickshell -p <payload>` starts it.
- Imports `Astral.AppKit` only. Importing `Astral.Kernel` fails inside the
  sandbox by design, and the verifier rejects it at pack time.

Build it the way an author would once the SDK lands (P3):

```bash
astral app new io.github.astral.hello --template surface
astral app dev .        # sandboxed, hot reload
astral app test .       # manifest + boundary lint, QML suites
astral app pack .       # io.github.astral.hello-0.1.0.astralapp
```
