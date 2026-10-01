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

**(101)'s reconnect loop is fixed, merged from `tmp/pingpong`** — one client per laptop by a
server-minted machine id, and an evicted client parks instead of fighting back (docs/STREAM.md
§5.10/§6). MEASURED against the real laptop while the owner's own (then-unpatched) iPad was
mid-loop. Three LAN mDNS bugs on our own side fixed too (multicast joined the wrong interface, the
A record could carry the Tailscale address, `ExclusiveAddressUse`), confirmed at the network layer
on the laptop — **not yet confirmed by Nearby actually listing the laptop on the owner's iPad**,
which needs a build on the device. Stash empty, no simulator debris left behind.

**Full suite at `f509d39`** (fresh erased device, 97.5% idle): **4679 / 4609 passed / 10 failed / 60
skipped, 53.6 min**, 295 classes. Five failures were real and are fixed (a brush-library leak between
UI tests — `-resetBrushLibrary` on each test's first launch; a palette row below the fold since
`f77df00`; `FrameBakeKeyLogicTests`' mask-order test whose 64 attempts were not independent); five
passed in isolation. **The two test-helper commits after it (`87851ca`, `fd1d287`) have not had a full
run** — `87851ca` changes every UI test's first launch, so the next full run is its proof.
`OptionsPanelUITests` is now the heaviest class at 663 s, 212 s of it one test — look for a wait that
runs to its timeout. **Fast tier at close: 4331 / 4327 passed / 0 failed / 4 skipped**, Debug and
Release, reconciled against a static `func test` count — the full UI suite has not been run since
`tmp/pingpong` merged.

**The owner's iPad has `fe036df`** (Release, installed by the re-signer 2026-09-30; profile to
2026-10-08T03:16Z).
**Free-account profiles last seven days and the re-signer only runs while this Mac is awake** — the Mac
slept 2026-09-20 → 23, the profile lapsed, and iOS asked the owner to re-trust the developer. The
certificate itself has not changed since 2026-07-20.

**The laptop streamer was started by hand 2026-09-24 22:34** and has no autostart (TODO (99), as asked);
after a reboot the owner opens it from its desktop icon. A stopped streamer reads on the iPad as a
**timeout** ("did not answer … asleep, off, or not on this network"), not a refusal — docs/STREAM.md §5.9.

## What is left

**The owner's 2026-10-01 brief, (111)–(146), is the queue** — recorded in TODO.md in work order
(number = 110 + the owner's ask number). **Merged so far (session 46):** (117) (118) (130) the dock and
playback survive a pan, (143) (142) (137) (141) (138) (144) (111) the small UI asks and their two
ruled follow-ups, (129) (128) (116) (115) fill-type shapes, the gradient object, Select → Edit, font
faces, (113) (114) fill mend and extension buffer, plus two defects found on the way (the editor
stayed squeezed after the keyboard; taps fell through four bottom panels). **Seventeen items remain.**

**In flight**: an Opus worker on `tmp/offcanvas` — (121) outside-the-canvas as one input path, then
(124)+(145) drawing under a transform layer on the same seam. The cap this session is one Opus *or*
two Sonnet at once, so nothing else runs beside it. **Check `git worktree list` before trusting this.**

**Next, in order**: (125)+(136)+(140) one live-preview mechanism for transform edits (Opus); then
Sonnet lanes — (119) (120) (146), (134) (135), (122) (123), (126) (127) (133), (132), (112); then
(139) and (131) (both ruled; (131) after (128), which has merged).

- **Design notes for (139), (131), (124)** are at `~/PaintWork/design/survey-1001.md` (a read-only
  survey; the rulings in TODO.md override it). The worker brief every lane reads is
  `~/PaintWork/brief-common.md`.
- **Evidence on disk**: `recording-20261001-002122.jsonl` ((132)) and `-002226.jsonl` ((145)) are in
  `~/PaintWork/evidence/`.
- **(101) is folded into (112)**.

**Questions queued for the owner** (they asked not to be asked before 11am EST 2026-10-01; use the
question tool):
1. Select → Edit when a loop catches both a text box and a gradient: topmost wins (shipped), one button
   per object, or refuse and ask for a tighter loop?
2. Fill Mend's reach is twice Gap Closing: keep, a separate Mend Reach slider, or a fixed small reach?
3. While typing, the editor shrinks so the Text panel rides above the keyboard: keep, lift only the
   dock above the keyboard, or let the keyboard cover the panel?

**Settled this pass, not to re-ask**: "Fingers Can Paint" is **off** on the owner's iPad (pencil only);
an effect layer's bar stays up until another layer is selected; the Select menu keeps its one rule line.

**Owner-side, unchanged**: (27) stage 5 and BUGS.md's palette-row question.

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
  tool) — since (129) they lay down solid fill objects, and the gradient is a fill object (128).
- **(105)** — `VectorVideoElement.mappedFrameRate`, frozen at insertion (24 when absent).
- **(86)** — `CanvasManager.maxCanvasExtent(deviceMemoryBudgetBytes:)`, fit ≈42.25 B/px − 288.6 MiB,
  63% margin; 6000 at 1850 MiB, 8000 at twice that.
- **(101)** — `PaintSoftware-Info.plist` carries `NSBonjourServices`; `StreamConnectFailure` is the one
  classification the sheet and the bar read.

## Waiting on the owner

- The device checks above; the palette-row question in BUGS.md. (Answered 2026-09-25: same Wi-Fi, Local
  Network allowed.)
- Granting Xcode Full Disk Access would let builds run from `~/Desktop` again.
- **XCUITest cannot synthesise a Pencil**; the owner has granted device build and deploy.
