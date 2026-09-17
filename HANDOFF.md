# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks **in queue order — the top of the list is what to do next**;
[BUGS.md](BUGS.md) is what we find.

## State

**Check `git worktree list` and `git branch -a` first.** `git fetch` before trusting any of this —
`origin/main` is a shared ref.

**No branches, no worktrees, stash empty, no simulator debris.** Session 44 closed with everything
merged and pushed; `main` carries the whole of the owner's 2026-09-16 brief — (68) and (69)–(100) —
except the owner-side sub-points named below. The feature specs now live under [docs/](docs/).

**Fast tier at close: 4280 total / 4276 passed / 0 failed / 4 skipped**, Debug and Release,
reconciled against a static `func test` count at every one of the fourteen merges this session.
**The full UI suite was not run this session** — every merge was a fast tier plus the touched
XCUITests in isolation, serial, on a fresh device. Run it first thing (CLAUDE.md's recipe:
`simctl shutdown all` + `erase` immediately before), triage as CLAUDE.md says, and pull the
per-class table from its xcresult — eleven UI classes gained tests and `LensBlurUITests`,
`GuideUITests`, `VectorLayerEffectUITests`, `LargeCanvasFillUITests`, `SelectionCompositionUITests`,
`FolderMoveLogicTests`' UI twin and the two eraser classes are new.

**The owner's iPad has `6f3c691`** (Release, installed 2026-09-17; profile valid to
2026-09-24T01:04Z) — the regression fixes, onion skin, menus and % sliders, Move/Select, the eraser,
autosave and the round-trip state. **`f42052c` is built** at `build/DerivedData/Build/Products/
Release-iphoneos/PaintSoftware.app` (same profile) and was refused by the device being
`unavailable` — asleep or off the network; install it as soon as `devicectl list devices` says
`available`. It adds the colour picker, effects, the stream fixes and the bounded fill.

**The Windows laptop is deployed and proved.** It woke at the end of the session: the (98)/(99) C#
compiled clean, `dotnet test` 131/131 (the `FileOutboxTests` race fixed and its BUGS entry gone),
`install-streamer.ps1` ran — Start-menu and desktop shortcuts, a **triggerless** `PaintStreamer` task
kept only so `streamer-remote.sh start` can reach kevin's session, and **program-scoped firewall
rules** (TCP 47301, UDP 5353 for mDNS, Private+Public). Those rules are the fix for the owner's "cannot
connect": Windows Firewall silently mints a per-program *Block* rule the first time a headless app
listens and nobody answers its prompt, and it re-triggers on every redeploy; docs/STREAM.md §4 has
it. `stream-client-check.py --host 100.104.85.111` PASSes (24.6 fps, 0 violations) and a second
launch exits silently. The laptop's own Windows Hello PIN is broken (`0x80090011`) — the owner's
problem, not ours, and nothing we deploy needs elevation from kevin.

## What is left

**Owner-side, in queue order — each needs the iPad or the laptop in hand:**

1. **Feel `f42052c`** once it is installed: playback, a pan from the grey, a Move-node release, a
   pinch with a popover open, a raster stroke (the live walk changed for (84)), the hold-to-open
   onion icon, the log size slider (**(79)'s last sub-point: log or linear**), the colour picker's
   tabs (it opens on Square, not Disc, because a dozen existing tests reach into the panel that way —
   a one-line default if the owner wants Disc first), a blob on a vector layer set to Blur (**(92)'s
   ink-as-stencil rule, EFFECT_BACKDROP §2.4, reversible**), and a streaming session without a
   respring (**(97)'s proof** — the simulator cannot stand in for the device's render server).
2. **(86)'s ceiling**: the graded edit probe at 7000² on the iPad (PERFORMANCE.md §22.2 has the
   command) is the only thing that can lift 6000.
3. **(27) stage 5** — unchanged from session 43: stream Blender, measure latency, the device tick
   figure, Ctrl+V into the drop box, the blend-mode limitation.
4. **(97)'s watchdog** — one `0x8BADF00D` report inside a `LazyVStack` that matches
   `BrushEditorScreen.outputColumn`'s shape; not reproduced. A second report in the same view is the
   signal.

**Then the queue is the "Later" features and the deprioritised three** — ask the owner what to pick
up, with the iPad build in front of them.

**If the freeze ever comes back**: turn on Record My Actions at the *start* of the session and stop
after it freezes. Recording #3 began after the wedge and showed the wedged state, not the transition.

## What shipped this session

Fourteen merges, `d7b8334..f42052c`; the causes are in the commit messages and the specs, and the
one-line summary is SESSION_LOG's session 44. The decisions a future session is most likely to trip
over:

- **(68)** — three of the four felt regressions were latent on `94caa67` and reproduced there; only
  the freeze was in the stream build's range. `DecodedFrameRing.insert(_:for:keeping:)`,
  `CanvasTouchOwner` decided at touch-down, the transform recognizers on `CanvasHostView`, and
  presentation dismissal only from a confirmed single touch.
- **(95)** — the selection is one normalised `CGPath` composed by Core Graphics' own booleans
  (`Selection.composed(with:by:within:)`); every consumer reads that one path.
- **(71)** — a folder Move lifts every vector layer in the folder into one `VectorFloat` with
  `parts`; the folder-as-transform-layer behaviour is deleted whole (the transform layer kind keeps
  its five modes).
- **(81)/(82)** — `VectorCanvas.eraserTouchesInk` is the one predicate; universal erase lands only
  on the layers where it erased something, one undo step across them.
- **(85)** — every cutter makes the one lattice piece; `arcOffset` is gone from the wire format (old
  Mode-2 pieces re-roll their scatter once on load — standing permission, TODO.md's "no document has
  to survive").
- **(76)** — `AutosaveClock` (2.5 s after the last edit, 30 s ceiling), held during a live stroke,
  playback, a resize or any pending interactive state; `PackageLedger` clones unchanged cel files
  with `clonefile(2)`; MEASURED 0.3 ms on the main thread. Restore points: one "as opened" per
  session plus a rolling "before last save".
- **(77)** — per-document editor state in `ProjectManifest.editorState`; app-wide tool/size/opacity/
  colour in `EditorPreferences` (`UserDefaults`). `launchIntoEditor` passes `-resetEditorPreferences`.
- **(73)** — one colour model under five tabs; `ColorHistoryStore` written only from `strokeEnded`.
- **(74)/(88)/(92)** — Lens Blur is a 64-sample Vogel disc plus a 16-sample fill pass; Guide is a
  per-pixel grade with `readsAbsolutePosition`; a vector layer's effect is a `MaskSource.ink` mask
  (never persisted) on the grading leaf, `Layer.layerEffect = kind.carriesEffect ? effect : nil`.
- **(97)** — `StreamSurfaceView` draws the stream's window into two reused IOSurfaces; the tick no
  longer hands Core Animation a canvas-sized image. Bake Frame copies pixels; `StreamPicture` is
  shared across an element's copies.
- **(86)** — `FillWindow` bounds every fill buffer to the region (+88 px halo, grown toward what a
  bucket reaches); `fillBudgetBytes`' size refusal is gone; the two allocation traps are refusals
  raising `CanvasNotice.Kind.outOfMemoryToDraw`.

**Owner rulings this pass**: the token-cost rule (one worker per batch, continued in place, ~3 items;
sonnet unless the work is hard); everything else was a decision taken and named as reversible in
the spec it touched.

## Waiting on the owner

- The four device checks above, and a real streaming session from the laptop on `f42052c`+.
- **(79)** log or linear; **(92)**'s rule; the colour picker's opening tab.
- **BUGS.md** carries the watchdog, the `FileOutboxTests` race, the stepped-split timing change, the
  simulator-only keyboard band, and the five `.popover`s.
- **XCUITest cannot synthesise a Pencil**; the owner has granted device build and deploy.
