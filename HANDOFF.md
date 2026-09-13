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

**No branches, no worktrees, stash empty, no simulator debris.** Session 43 closed with everything
merged and pushed; `main` carries (64)–(67) and the whole of (27) through stage 4.

**Fast tier at close: 4119 total / 4116 passed / 0 failed / 3 skipped**, Debug and Release,
reconciled against a static `func test` count at every merge (the constant 3-count gap is three
`private static func testBrush()` helpers).

**Full suite at close, fresh erased device, idle machine: 4428 / 4364 passed / 5 failed / 59 skipped, 52.7 min, zero crash blocks — two cut tests a state flake (fail warm at session 42's close too, pass after an erase), fill-adjust and Colour Wheels green warm in isolation, and one real one: (65)'s own test read a lazily-realised menu row without scrolling to it, fixed in the test.** CLAUDE.md's class table was
not re-taken this pass — five UI classes gained tests (`OptionsPanelUITests`,
`BlendModesAndCompositorUITests`, `TransformLayerModesUITests`, `TransformLayerSpanUITests`, and the
new one-test `StreamScreenUITests`); pull the per-class table from the next full run's xcresult.

**The owner's iPad has `d398588`** — `main` at session 43's close, Release, installed 2026-09-13,
with the whole of (27) through stage 4 including file transfer; profile valid to 2026-09-20 04:15Z.

**The Windows laptop is set up and streaming.** `desktop-cbr0fl6`, `100.104.85.111` on the tailnet,
SSH as `PC` with `~/.ssh/paintapp_windows`; the streamer runs as the `PaintStreamer` scheduled task in
`kevin`'s desktop session, remembers `monitor:0`, and says "The laptop is locked" while it is.
`tools/windows/streamer-remote.sh {start|stop|status|log|sources|deploy|test}` drives it from this
Mac. CLAUDE.md has the section; STREAM.md §4 has everything else.

## What is left

**(27) is built through stage 4 and needs the owner** — STREAM.md §7 stage 5 and TODO.md's checklist:
stream Blender to the iPad and rotoscope over it; measure end-to-end latency on the real link; take
the device tick figure; try Ctrl+V into the drop box; rule on the blend-mode limitation. Nothing in
it can be done from this Mac alone.

**Then the queue is empty again** — (22), (10) and (37) are deprioritised or dropped by the owner, and
the "Later" features each need a design conversation. **Ask the owner what to pick up**, with the
iPad build in front of them.

## What shipped since session 42's close

- **(27) — the stream layer, stages 0–4**, one day from brief to iPad. Design in STREAM.md (§2 is the
  owner's twelve rulings; §3 the wire protocol both programs implement; §6 the defaults taken). The
  Windows streamer (`streamer/`: `Streamer.Core` with no UI and no statics so a future Windows build
  of the paint app can host it, `Streamer.Tray` in WPF, 103 xunit tests) captures a monitor or one
  window through Windows.Graphics.Capture via GStreamer and encodes on the laptop's QuickSync. The
  iPad side is a sixth `VectorElement` case in an ordinary vector layer, decoded by VideoToolbox off
  the main thread, redrawn by a ≤30 Hz tick costing **0.2–0.5 ms** (simulator), with a bar that shows
  Live / Frozen / Reconnecting… / Not streaming — <reason>, Freeze, and Bake Frame (`splitCel` twice
  and a swap, one undo step). The last picture is saved with the document; files go both ways
  (drop box or Ctrl+V on the laptop → a new layer; Export → Send to Computer → the laptop's folder).
  **Five things only the build could find**: a per-tick version bump would have re-baked the frame to
  disk 30×/s (`committedVersion` is the seam); Windows capture is damage-driven, so a still screen
  sends nothing and the keyframe rule became "restart the capture"; the laptop's display sleeps in
  60 s and capture goes black unless held awake; `OpenInputDesktop` reports a locked laptop as
  unlocked (the `LogonUI` check is what works); and a stream under a blend mode or effect cannot be
  live at 46–73 ms a tick, so the bar says so.
- **(64)** the transform layer's per-mode settings open in the bottom dock (`TransformSettingsBar`,
  the code moved not copied); **(65)** HSV Shift is one menu entry with Colorize as its toggle;
  **(66)** the effect and blend menus have section headers (real `Section("…")` titles, confirmed
  drawn); **(67)** bottom-docked panels survive a two-finger pan — `StrokeGestureRecognizer.
  onSingleTouchBegan` fires only for a confirmed single touch, and `CanvasManager.canvasTouchLanded`
  is split from `canvasInteractionBegan`.
- **`tools/windows/`** — `enable-ssh.ps1` (OpenSSH Server + the Mac's key, one paste as admin),
  `install-streamer.ps1`, `streamer.ps1`, `streamer-remote.sh`; **`tools/stream/`** — the Python
  reference server and the conformance client both real ends are proved against.

**Owner rulings this pass**: the four (27) answers above; the concurrency cap for workers, set per
session and not recorded.

## Waiting on the owner

- **Everything in (27)'s stage 5** — they are the only one who can sit at the laptop and the iPad.
- **What they found on the iPad** with the stream build, and after the reinstall from `main`.
- **Questions that took a default**, each reversible and recorded in STREAM.md §6 or the code:
  - The stream cel runs from the current frame to the end of the scene; a dropped PNG joins the
    *active* layer (which is the stream layer if that is what is selected) — `insertImage`'s rule.
  - Freeze is not an undo step; Bake Frame is one; neighbours keep the stream id, the baked cel is
    re-identified; undo of a bake made while frozen restores the frozen flag.
  - One paused connection per document to the last-used laptop, even with no stream layer.
  - Port 47301, admitted only from Tailscale addresses; ~6 Mbit/s, GOP 60, `qsvh264enc`.
  - Console-disconnect is reported as "locked"; the outbox folder puts failed sends under `refused\`.
- **BUGS.md** carries the stepped-split timing change, the simulator-only keyboard band, the five
  `.popover`s, `BrushEditorUITests`' growth, and a `FileOutboxTests` race seen once in four runs on
  the laptop (a chip was filed).
- **XCUITest cannot synthesise a Pencil**; the owner has granted device build and deploy.
