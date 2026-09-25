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

**Build from `~/PaintWork`, not `~/Desktop`.** Since macOS 26.5.2 `actool` cannot read the Desktop
folder (CLAUDE.md "Build and test", first paragraph), so every worktree lives at
`~/PaintWork/PaintApp-<id>` and Bash calls that run `xcodebuild` need the sandbox off. The owner can
end this by granting Xcode Full Disk Access; nobody has yet. `~/PaintWork/deploy` is a detached
worktree kept for device builds — `git -C ~/PaintWork/deploy checkout --detach origin/main` and build.

**No branches, stash empty, no simulator debris.** Session 45 closed with everything merged and
pushed.

**Full suite at `f509d39`** (fresh erased device, 97.5% idle): **4679 / 4609 passed / 10 failed / 60
skipped, 53.6 min**, 295 classes. Five failures were real and are fixed (a brush-library leak between
UI tests — `-resetBrushLibrary` on each test's first launch; a palette row below the fold since
`f77df00`; `FrameBakeKeyLogicTests`' mask-order test whose 64 attempts were not independent); five
passed in isolation. **The two test-helper commits after it (`87851ca`, `fd1d287`) have not had a full
run** — `87851ca` changes every UI test's first launch, so the next full run is its proof.
`OptionsPanelUITests` is now the heaviest class at 663 s, 212 s of it one test — look for a wait that
runs to its timeout. **Fast tier at close: 4327 / 4323 passed / 0 failed / 4 skipped**, Debug and
Release.

**The owner's iPad has `0e20568`** (Release, installed 2026-09-25; profile to 2026-10-01T01:27Z).
**Free-account profiles last seven days and the re-signer only runs while this Mac is awake** — the Mac
slept 2026-09-20 → 23, the profile lapsed, and iOS asked the owner to re-trust the developer. The
certificate itself has not changed since 2026-07-20.

**The laptop streamer was started by hand 2026-09-24 22:34** and has no autostart (TODO (99), as asked);
after a reboot the owner opens it from its desktop icon. A stopped streamer reads on the iPad as a
**timeout** ("did not answer … asleep, off, or not on this network"), not a refusal — docs/STREAM.md §5.9.

## What is left

**Owner-side, in queue order:**

1. **Feel `0e20568`**: the freeze (a two-finger drag with the Effect menu open now recovers by itself —
   and if the canvas ever repairs a freeze, a badge says so and a `flight-…jsonl` lands in Settings →
   Recordings; send it), the colour picker against the reference, the + and gear icons, Cut/Copy/Paste,
   the rename sheet, the slider % beside the size pop-up, a video at 12 fps, To New Layer's cel span.
2. **(101)**: allow Local Network when iOS asks, then Nearby should list the laptop; a LAN address
   should connect.
3. **BUGS.md's newest entry**: since `f77df00` the colour panel shows one palette row above the fold;
   is that what the owner wants?
4. **(27) stage 5** — unchanged: stream Blender, measure latency, the device tick, Ctrl+V, the
   blend-mode limitation.

**Then ask the owner what to pick up** — the queue is the "Later" features and the deprioritised three.
**16k canvases** would need the display rebuilt around screen-sized tiles; it was offered as a design
conversation, not started.

## What shipped this session

Eleven merges, `cbd248f..0e20568`; causes are in the commit messages and SESSION_LOG's session 45. The
decisions most likely to be tripped over:

- **(110)** — nothing over the canvas is a UIKit popover; `canvasPresentationHost` draws them and
  `AnchoredMenuRouter` alone decides dismissal. `CanvasView.Coordinator.replaceStrandedRecognizers`
  swaps in fresh recognizers 0.1 s after the last lift. The flight recorder is `ActionRecorder`'s ring
  (90 s, 5,000 events, low-rate events only), written on `stranded` / `wedge` / `manual`. **A tap that
  dismisses a picker now also acts on what it lands on.**
- **`DrawingView.openPanelIsStandingDown`** — a canvas touch leaves alone a panel that is hidden only
  because a piece floats (the gate's fix for `c8b93c9` closing the Select panel under a float).
- **(106)** — one hue-angle convention in `ColorMath`, used by drawing, drag and marker; the triangle is
  clipped to its true path at display scale. The panel still opens on Classic (the old Square) because
  a dozen tests reach `colorPanel.svSquare`.
- **(103)** — Rectangle/Ellipse call `beginInteractiveShape` with a default square (there is no shape
  tool); Linear Gradient is `ValueFill.gradient`, not a new layer kind.
- **(105)** — `VectorVideoElement.mappedFrameRate`, frozen at insertion (24 when absent).
- **(86)** — `CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes:)`, fit ≈42.25 B/px − 288.6 MiB,
  63% margin; 6000 at 1850 MiB, 8000 at twice that.
- **(101)** — `PaintSoftware-Info.plist` carries `NSBonjourServices`; `StreamConnectFailure` is the one
  classification the sheet and the bar read.

## Waiting on the owner

- The device checks above; the palette-row question in BUGS.md.
- Granting Xcode Full Disk Access would let builds run from `~/Desktop` again.
- **XCUITest cannot synthesise a Pencil**; the owner has granted device build and deploy.
