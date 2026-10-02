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

**The owner's 2026-10-01 asks, (111)–(152), are the queue** — TODO.md, in work order (111–146 are
110 + the owner's ask number; 147–152 came in a second message the same day). **Session 46 merged**
(117) (118) (130) (143) (142) (137) (141) (138) (144) (111) (129) (128) (116) (115) (113) (114) (121)
(124) (145) (120) (119) (146) (134) (122) (123) (148) (150) (152), every ruled follow-up on them, the
Oklab gradient, and defects found on the way (three UI reds bisected to this session's merges and
fixed; the keyboard squeeze; panel touch fall-through). **The owner's iPad has `c8562ca`** (installed
2026-10-01); everything after it is not on the device yet.

**(125)+(136)+(140) merged** (`854a727`): one live-preview mechanism (`LiveTransformEdit`) for transform
edits, the baker held until release, the plain-layer fast picture. **Folder Move's lag did not reproduce
in the simulator — measure it on the iPad.** The cap is one Opus *or* two Sonnet.
**Check `git worktree list` before trusting this.**

**Next, in order** (fresh Sonnet workers, two at a time — never continue a worker whose context is
large): the text follow-ups + (147) tap-select; (149) primed Add shapes; (151) 15° rotate snap + angle;
(135) folder Move all frames / this cel; (126) (127) (133) export and padding; (132) brush ends (recording
in `~/PaintWork/evidence/`); (112) stream paused; then (139) and (131) (ruled). **Then the full UI suite**
— not run this session; the taller timeline moved the dock 125 pt and may break tap-by-position tests —
triaged by a Sonnet worker, and **one** Sonnet audit of the session's whole diff for leftover code,
duplicated mechanisms and bolted-on fixes (the owner rejected per-item reviewers as too costly).

- **Design notes for (139), (131)** are at `~/PaintWork/design/survey-1001.md` (rulings in TODO.md
  override it). The brief every worker reads is `~/PaintWork/brief-common.md`.
- **Questions for the owner**: none open — the 2026-10-02 batch is answered and recorded in TODO's
  "Rulings of 2026-10-02" entry. After the next install, ask how (132)'s held stroke ends feel (the ink
  trails the pen by up to a quarter of the brush width) and whether a live stroke's interior wants
  smoothing too.
- **The laptop streamer needs `tools/windows/streamer-remote.sh deploy`** when the laptop is on:
  `f84776f`'s C# half (clear a stale pause on connect, idempotent resume) is merged uncompiled.

**Settled this pass, not to re-ask**: "Fingers Can Paint" is **off** on the owner's iPad (pencil only);
an effect layer's bar stays up until another layer is selected; the Select menu keeps its one rule line;
Fill Mend's reach stays twice Gap Closing; the editor keeps shrinking above the keyboard while typing.

**Owner-side, unchanged**: (27) stage 5 (the blend-mode limitation is ruled: keep it).

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
