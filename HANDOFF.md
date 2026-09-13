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

**No branches, no worktrees, stash empty, no simulator debris.** Session 42 closed at `94caa67`,
19 commits past session 41's `8e2ffff` (87 past session 40's `aff11df`), everything merged and pushed.

**Fast tier at `103d540`: 4029 total / 4026 passed / 0 failed / 3 skipped**, Debug and Release,
reconciled against a static `func test` count at every merge (the constant 3-count gap is three
`private static func testBrush()` helpers).

**Full suite, twice this session, both on a fresh device on an idle machine.** At `8e2ffff`:
**4270 / 4206 / 5 / 59, 48.6 min**, zero crash blocks, all five failures green serially — the eraser-cut
trio CLAUDE.md attributes to clone contention, plus two more. At `103d540`, at close: **4332 / 4268 / 5 / 59, 46.2 min**, zero crash blocks, all five green on the first isolated run and none in both runs' failing sets. CLAUDE.md's class table is
current as of the second run.

**The owner's iPad has `94caa67` on it** (Release, installed 2026-09-13, profile valid to
2026-09-20 04:15Z). The "PaintApp is no longer available" failures — four in two months — are diagnosed
and closed: Xcode had silently dropped the free-account Apple ID session, so no CLI build could mint a
profile and every build reused a downloaded one until it expired. The owner signed
**fealle2000@gmail.com** back in (team `354YBUT74A` — not their personal team); the resign daemon
(`~/PaintApp/deploy/resign.sh`, outside the repo, backed up beside itself) now judges due-ness from the
**installed profile's expiry**, runs **hourly**, refuses a build whose profile did not advance, and
posts a **macOS notification on any FAIL** — so a lapsed sign-in is a same-day click, not a dead app a
week later. CLAUDE.md's deploy steps refuse a profile with under five days left.

## What is left

**The queue is empty of live items.** TODO.md holds only the three the owner deprioritised or dropped —
(22) multi-cel select, (10) linear-light blend, (37) brush importers — and the "Later" features, each of
which needs a design conversation before a line is written. **Ask the owner what to pick up**, with the
iPad build in front of them; do not start (22)/(10)/(37) unprompted.

## What shipped since session 41's close

- **Full suite re-taken** twice (above); the class table is current.
- **(21) closed whole** — the folder graph band (`graphBandExpansion` keyed by `KeyframeTarget`; a
  folder's channels open and edit like a layer's, entered from the timeline name or "Show in Graph
  Editor") and **Bake Animation** (one animated block → one drawing per frame, byte-identical to the
  animated render on both backends, holds kept as one block, one undo step, the confirmation quoting a
  MEASURED 2.4 ms/drawing save cost). The bake's cold-start test found a latent undo display race
  (`DeferredVectorRender.landing`) the fast tier could not see.
- **(63) closed whole** — **Glare** (Streaks / Simple Star / Fog Glow as one entry with a Type picker;
  a single gather pass walking every direction, because the multi-pass contract only hands a pass its
  predecessor; Ghosts recorded as not built) and **Colour Wheels** (Shadows / Midtones / Highlights /
  Global as four real discs on one row, Oklab offsets with partition-of-unity weights, sixteen keyable
  parameters, parity delta 0). `Effect.Kind` is **18 cases**, kernel codes 0–18; the kernel-branch
  coverage sweep now derives its upper bound from the constants.
- **The resign daemon**, above.

**Owner rulings this pass**: Glare stays one entry; picking a folder for the curve editor does not
change the drawing layer; the hourly resign plist installed by the owner.

## Waiting on the owner

- **What to pick up next** — the queue is empty.
- **What they found on the iPad** (`94caa67`).
- **Questions that took a default**, each reversible and recorded where the behaviour lives:
  - Bake: a hold stays one block (or one per frame?); a block inside a folder bakes only its own
    motion; the save cost quoted is this Mac's.
  - Colour Wheels: a drag jumps the dot to the finger (Resolve nudges instead); a tap does nothing;
    reset clears Lum and Strength too; rim chroma 0.15; Midtones peaks at ~99/255 (perceptual middle).
  - Selection editing: Size over mixed widths sets one width (scale together?); Opacity likewise;
    the band shows only once a loop exists.
  - Duplicate Offset: white rim 8 px up-right default; box is the whole canvas; panel closes after
    Adjust Box → Done; all 25 blend modes.
  - Repeat: Move/lasso/text on a repeated frame still see an empty frame, silently.
  - Recolour, Computer Screen, Shake: see TRANSFORM_LAYER §5 and EFFECT_BACKDROP §4 notes.
- **BUGS.md** carries the stepped-split timing change, the simulator-only keyboard band, the five
  `.popover`s, and `BrushEditorUITests`' 586 → 711 → 813 s growth on the same eleven tests.
- **XCUITest cannot synthesise a Pencil**; the owner has granted device build and deploy.
