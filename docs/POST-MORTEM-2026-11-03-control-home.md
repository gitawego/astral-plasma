# Post-Mortem — "Remove Volume And Brightness Control From The Right Sidebar"

> **Status:** Closed — requested change shipped, the wrong first attempt was reverted in full
> **Date:** 2026-11-03
> **Reported by:** user ("remove volume and brightless control, they are at right sidebar")
> **Impact:** one wrong Surface was removed (~1,415 lines) and had to be reverted before the
> correct change (~390 lines) landed. No data loss, no user-visible regression left behind,
> no test ever went red in CI after the revert.
> **Related:** [`docs/LESSONS.md`](../docs/LESSONS.md) §8.11, [`walkthrough.md`](../walkthrough.md)

---

## 1. What was asked

Two screenshots of **the dock's** "Display Brightness" drawer and of the dock's status
column (speaker, brightness, clipboard, bell, battery glyphs), captioned:

> *remove volume and brightless control, they are at right sidebar*

Read literally: *the volume and brightness controls you are showing me are duplicates —
they already exist on the right sidebar, so delete the duplicates.* The screenshots are
the dock; the "right sidebar" is the right-edge rail.

## 2. What was done instead (the failure)

The rail itself (`shell/RightEdgeControl.qml`, `rightEdgeControlWrapper`,
`rightControlSurface`, `blurRightEdgeActive`, the `rightedge` IPC target, `Config`
state) was deleted — i.e. the surface the user explicitly said to keep — while the
dock indicators they pointed at survived. The user's reply was immediate and correct:
*"you remove what i want keep"*.

### 2.1 Why it went wrong (causal chain, not a single slip)

1. **The phrase was disambiguated by repo knowledge, not by the evidence.** In this
   codebase "sidebar" collides: `README.md` calls the **dock** the sidebar
   (`dock/ LeftDock, BarRepeater`), while "right sidebar" plainly named the right rail.
   Both readings were available; the *screenshots* were the tie-breaker and they were
   not used as the subject of the sentence. The user was pointing at what to delete;
   I treated the pointer as context for a different sentence.
2. **"Duplicate" was resolved by seniority, not by the user.** Between two copies of the
   same control, the older one (the rail, commit `a7814d6`) looked like the accidental
   prototype and the dock one looked like "the real one", so the "redundant" surface was
   picked from the code's history instead of from the user's screenshots.
3. **An asymmetric-cost assumption hid the risk.** The change was large (1,415 lines),
   destructive, and never paused for confirmation — but it was "just deleting a
   duplicate", and the cost of *asking* looked bigger than the cost of being wrong.
   It was not: the revert cost a full round trip plus a user's trust.
4. **A green test suite manufactured confidence.** The TDD tests I wrote encoded the
   *wrong* intent, so 140/140 passing proved only that the code matched my misreading.
   Nothing in the suite asked "did you delete the surface the user asked to keep?" —
   because no test could: that is an intent question, not a code question.
5. **"Verified live" verified the wrong thing.** Screenshots confirmed *the change
   behaved as implemented* (rail gone, border continuous). They were never compared
   against *the change as requested* (buildings in the picture still stand).

## 3. Recovery

1. `git checkout -- .`; the deleted `shell/RightEdgeControl.qml` and
   `tests/tst_right_edge_control.qml` came back, and the new helper test was removed.
   `git status` clean, the prep change (nothing had been committed) fully gone.
2. The intent was restated in one line and confirmed before touching code again:
   keep the right rail, remove the dock copies.

## 4. What shipped (second attempt)

| Removed from the dock | Kept |
| --- | --- |
| `audioItem` / `brightnessItem` indicators + hover/click/wheel wiring | Right rail `RightEdgeControl` (sliders, wheel, click-to-mute) |
| `audioSection` / `brightnessSection` in `FusedBottomPopout` (incl. the "Display Brightness" preset card) | Network, Bluetooth, Clock, Battery, Clipboard, Notifications drawers |
| Dead ids in `config/settings.json` and the `Config.qml` fallback list | Existing user settings files (never rewritten) |
| Ghost drawer for retired modes (`config/PopoutModes.js` guard) | Live modes and the rail's `rightedge` IPC |

Discovered on the way (not asked for, but a real defect): a **retired popout mode** slid
out an *empty* glass card, because `UnifiedShell` sizes the wrapper from the active
section's height and the section no longer existed. Fixed behaviourally via a pure module
so the rule is unit-testable without instantiating the Quickshell singleton.

### Tests added
- `tests/tst_dock_audio_brightness_removed.qml` — the dock declares no volume/brightness
  indicator and never binds the two services; the fused popout has no audio/brightness
  section; defaults ship neither id; survivors intact; the rail still drives both services.
  Strips comments and string literals first, so prose cannot satisfy a contract.
- `tests/tst_retired_popout_modes.qml` — drives the pure rule: retired ids inert,
  case-insensitive, cannot hijack an open drawer, live modes pass through.
- `tests/tst_status_icons_stale_filter.qml` — instantiates the real `StatusIconsPage` and
  proves stale ids from a user's file are filtered out of the list and the count.

### Verification
- `make test`: Rust green, **143/143 QML suites green** (incl. the untouched
  `tst_right_edge_control`).
- Live: rail still slides out (`rightedge open`, 62×320 px right-edge diff); remaining dock
  indicators and their drawers still open; `popout open brightness` leaves the screen at its
  steady frame instead of drawing a card; `popout open clock` still opens.

## 5. Where the evidence actually was

The decisive facts were in the original message, not in the repository:

- The **screenshots** show the dock drawer with its title "Display Brightness" and the
  dock's status column. A request that includes a picture is a request about the picture.
- The **caption names the surviving surface** ("they are at right sidebar"), so what is
  in the picture is, by the user's own words, the copy to remove.
- I had already *used* the image (measured its layout) and still acted on a repo-wide
  reading. Having looked at the artefact is not the same as having let it decide.

## 6. Corrective actions

| # | Action | Status |
| --- | --- | --- |
| 1 | **The picture is the subject.** When a request carries a screenshot, the change is to what is *in* it unless the text says otherwise; the caption tells you what to keep. | applied |
| 2 | **Name the two surfaces in the reply before coding.** For any delete/duplicate request, state "I will remove X (the thing in your screenshot) and keep Y" and only then start. If X and Y are near-synonyms in this repo, that sentence is mandatory, not optional. | applied in this turn |
| 3 | **Deletion is a confirmation point.** A destructive change over ~100 lines, or one that removes a user-facing surface, stops for a one-line confirmation even when confident. Reverting is never free: it costs a round trip and the user's trust. | applied |
| 4 | **Green tests never validate intent.** TDD proves the code matches the contract; the contract's fidelity to the request is reviewed separately, against the request text and its artefacts. | recorded here; see `LESSONS.md` §8.11 |
| 5 | **Two similarly-named components must be documented as distinct** — the dock drawer (`FusedBottomPopout`) vs the right-edge rail (`RightEdgeControl`) — so the next "remove the volume thing" cannot resolve to the wrong one. | `LESSONS.md` §8.11 |

## 7. Timeline (Europe/Paris)

| Time | Event |
| --- | --- |
| 19:15 | Request: "remove volume and brightless control, they are at right sidebar" + two dock screenshots |
| 19:16–19:25 | Rail deleted (1,415 lines), tests authored against that reading, suite green, "verified" by screenshot |
| 19:42 | User: *"you didn't fix anything, what have you done ?"*; live screen still shows the dock drawer |
| 19:44 | User: *"you remove what i want keep"* — revert requested |
| 19:45 | Revert: working tree clean, both deleted files restored |
| 19:46–19:52 | Correct change: dock indicators + drawers removed, stale-id filtering, ghost-mode guard, tests, docs |
| 19:56 | `make test` green (143 QML suites), live checks pass |
