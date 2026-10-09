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
worktree kept for device builds — `git -C ~/PaintWork/deploy checkout --detach origin/main` and build
with CLAUDE.md's "Deploy to iPad" command (it names the iPad and passes
`-allowProvisioningDeviceRegistration`; without that a free team's portal refuses to mint).

**Session 46 closed 2026-10-08 with the owner's queue empty.** Every ask of (111)–(152) and every ruled
follow-up is merged; nothing is in flight. **Full suite at `4cb36c1`** (fresh erased device, four clones,
97% idle): **5283 / 5221 passed / 3 failed / 59 skipped, 69.2 min**, all three environmental (CLAUDE.md
carries the table). **Fast tier at close: 4790 / 4786 / 0 / 4**, Debug and Release, reconciled.

**The owner's iPad has `2974b33`** — the final tree (Release, installed 2026-10-08, profile to
2026-10-15T04:52Z). The re-signer (`~/PaintApp/deploy/resign.sh`, untracked there) now judges due-ness
only from the installed profile's expiry, skips quietly while it is valid (the portal renews only after
expiry), arms a wake 120 s after expiry, and builds with the device destination; it records its own
installs, not this session's manual ones, so its first run after 2026-10-15T03:52Z will rebuild.

**The laptop streamer** has no autostart (TODO (99)); a stopped streamer reads on the iPad as a timeout.
**`f84776f`'s C# half** (clear a stale pause on connect, idempotent resume) **is merged uncompiled** —
run `tools/windows/streamer-remote.sh deploy` the next time the laptop is on.

## What is left

**Ask the owner what to pick up** — the queue is TODO's deprioritised (22), (10), (37) stage 12 and the
"Later" features (28) audio, (30) video editor, (35) masks, each needing a design conversation first.

**Owner-side, in order:**
1. **The owner has `2974b33` and reports *"feedback is all good so far"* (2026-10-08).** Still unasked, for
   whenever they come up: how (132)'s held stroke ends feel on a direction-following brush (the ink trails
   the pen by up to a quarter of the brush width) and whether a live stroke's interior wants smoothing;
   whether **folder Move** lags on the iPad ((136) did not reproduce in the simulator); whether a newly
   placed gradient should keep opening its colour panel.
2. **(27) stage 5** — stream Blender on the real link, latency, the device tick, Ctrl+V (the
   stream-under-blend limitation is ruled: live then exact when still).

**Engineering notes for the next session:**
- CLAUDE.md's argument for `-parallel-testing-enabled NO` on the fast tier was written when the logic tier
  was ~250 s of work; it now takes 14.4 min Debug / 8.2 min Release. Whether clones would pay for
  themselves there is unmeasured.
- The code still says "keyframe" internally (`KeyframeTarget`, `keyframeMarks`, `KeyframeControl`) — the
  owner ruled (2026-10-08) to leave the names; everything the artist sees says "keys".

## What shipped this session

~120 merges, `9704384..2974b33`; causes are in the commit messages and SESSION_LOG's session 46. The
decisions most likely to be tripped over:

- **One input plane** — `CanvasPlaneView` makes everything outside the paper hit-test as canvas; only
  rendering is clipped ((121)). A canvas finger is watched 80 ms (`CanvasTouchSettle`) before it counts.
- **One source for input under a transform stack** — `inkPose(forLayerID:)` and its pull-back family
  (`layerSpacePoint` / `layerSpacePath` / `placedInLayerSpace`) ((124)).
- **One fast-then-exact live preview** — `LiveTransformEdit` and `SandwichPresentation.next(from:live:held:)`
  serve strokes, transform edits, undo, and the stream (live while the laptop screen moves, exact 0.6 s
  after it stills); the baker is held during an edit ((125)/(136)/(140)/(145)/(112)).
- **Bake** replaces Merge Down's effect/value/transform arms on one core that also runs Bake Animation and
  the Repeat bake ((131)); colours go through `VectorElement.mappingColours`.
- **Keys, not keyframes** — a pose channel is up to eight independent curves (X, Y, Scale X/Y, Rotation,
  Skew, Perspective X/Y); "Add Keys" primes a frame and an edit keys only what changed ((139)).
- **Every menu over the canvas is a `CanvasMenu`/`AnchoredMenu`; no `.popover` remains in Views; Scribble is
  refused app-wide by one hook (`ScribbleRefusal`); every rename is inline (`InlineNameField`).**
- **UI tests**: one dock-aware visible-region rule (`visiblePaperRect`, `rowAboveTheDock`); helpers live
  once in `PaintUITestCase`, enforced by `tools/check-ui-helpers.py`; `waitForPixel` returns nil on timeout.
- **Workers**: the shared brief is `~/PaintWork/brief-common.md`; never continue a worker whose context is
  large (memory `feedback-fresh-agent-over-bloated-continuation`); one end-of-session audit
  (`~/PaintWork/design/audit-1007.md`) instead of per-item reviewers.

## Waiting on the owner

- What to pick up next (the queue above), and the unasked device checks.
- Granting Xcode Full Disk Access would let builds run from `~/Desktop` again.
- **XCUITest cannot synthesise a Pencil**; the owner has granted device build and deploy.
