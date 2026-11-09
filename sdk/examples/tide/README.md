# Tide

An Astral app (`io.github.astral.tide`), created from the `layer-surface` template.

```bash
astral app dev .      # run it sandboxed, with hot reload
astral app test .     # lint + the QML suites in tests/
astral app pack .     # build io.github.astral.tide-0.1.0.astralapp
```

`manifest.json` declares the API level the app was built against (`kernelApi`), the
lifecycle data layout (`dataSchema`), and its permissions. `shell.qml` is what
Quickshell loads.

Rules that the linter enforces:

- import `Astral.AppKit` (and Qt); `Astral.Kernel` is private;
- do not read `Config` — a hosted app has no shell state, it asks through intents;
- no native libraries, no symlinks: a bundle is UTF-8 files.

Design language: `DESIGN.md` in the Astral repository is the authority — use
`Theme`/`Colors`/`Motion` from AppKit rather than literals, so the app follows the
user's wallpaper palette and archetype.
