# You are the Orchestrator for the rest of the layer-compositing project

Not for one phase. **Phases 6 through 9 and the §10 open decisions are yours**, and you carry the
project until they are done or the owner redirects you. Read LAYER_COMPOSITING.md — the agreed
design, settled with the product owner. §11 is the build order; phases 0 through 5b are done,
committed and green on `claude/layer-system-redesign-f9afd9`.

## Read this first, because the last session got it wrong

**Your context is the scarce resource, and it is spent by doing rather than by deciding.** Last
session delegated the three implementation tasks and then did the entire close-out inline — ran the
fast tier, ran the 22-minute full suite, pruned the docs, wrote the session log — and ran out of room
to orchestrate anything past a single phase. Verification and paperwork feel too small to delegate.
They are not; they are exactly what to delegate, because they are well-specified and their output is
a handful of numbers.

What to keep for yourself: **design decisions, scope calls, what to ask the owner, verifying a
worker's numbers, and deciding what happens next.** Everything else goes to a worker — including
docs prunes, session-log entries, graphify refreshes, and test runs. Ask the owner when two readings
of a phase would produce materially different work; do not ask about things §6–§9 already settle.

Delegation limits: **at most 2 sonnet + 1 opus at any one moment.** Opus for design-bearing work
(mask resolution, non-separable blend maths, the node graph); sonnet for measurement, docs, and
mechanical registration. **Branch a worker's worktree from the phase tip, not `origin/main`** — every
worker up to session 26 wasted its first step fast-forwarding. Sessions keep dying on usage limits;
two of the last three did. **A dying worker's uncommitted work is recoverable** (`git -C <worktree>
status`) — commit it as explicitly-unverified WIP rather than leaving it loose, and never let a WIP
commit message claim a test result it did not get.

**Verify numbers, never summaries.** One session recorded a "measured" delta table it had never run;
the truth was 70× larger and was a genuine bug. Read `totalTestCount` from `xcresulttool` yourself.

## State

Fast tier **718/718**. Full XCUITest suite **800: 799 passed, 0 failed, 1 skipped** — the skip is the
FillUITests one already in BUGS.md. `Compositor.backend` is `.coreGraphics`. Working tree clean, no
worker worktrees outstanding.

**The branch has never been merged to `main`,** which sits at `0f740fc`, 27 commits behind. That is
the established pattern across all six phases, not an oversight — but it is now a large unmerged
branch and **worth asking the owner about early**, before it grows through four more phases.

## What is left

| # | work | done when |
|---|---|---|
| **6** | Alpha masks (§6), incl. `MaskParityLogicTests` | raster and vector mask pixel-identically |
| **7** | Tier 2 blend modes | |
| **8** | Compositor nodes: slot-as-folder storage, panel chrome (§4.3) | a 2-input Mix node renders |
| **9** | Tier 3 effects, as layer *and* node (§4.4, §7) | cheap per-pixel set first, then multi-pass |

§10's three open items are yours to close, and two of them resolve inside phases you are running:
the mask threshold (§6.3) is tunable once phase 6 gives something to look at; **"Clip to below" is
phase 6's**, as a mask with an implicit source — §7 lists it in Tier 1 while admitting it is not a
blend, which is why Tier 1 shipped as fourteen modes and not fifteen. The multi-input node ops want a
pass once phase 8's UI exists. The pass-through toggle question (§4.2) is now answerable, since
phase 5 made isolation observable.

**Phase 7 has a known trap.** Tier 2 is Hue/Saturation/Colour/Luminosity — non-separable, needing the
whole RGB triple rather than per-channel maths. Phase 5a established that **CoreGraphics is not the
authority on blend functions**: `CGBlendMode`'s colorDodge, colorBurn and softLight are the PDF 1.4
originals and disagree with W3C Compositing Level 1 by up to 249/255, so the app hand-rolls those
three and follows the spec, which is what Photoshop and CSP do. **Assume Apple's non-separable
versions disagree too, until measured.** Sweep them the way `CompositorParityLogicTests` sweeps Tier 1.

## What phase 5b just built, and the two places phase 6 collides with it

The live canvas shows blended layers. The owner's scope call was **exact at rest, snaps on lift**: at
rest the canvas is one `composite(full)` with every host blanked, byte-identical to the thumbnail;
only while a dab is down does a below/live-host/above trio take over, with the active layer's own
blend and any layers above it rendering Normal until lift. `needsCompositorOnCanvas` is the engage
switch and the risk containment — a document with no blend modes and no faded or isolated group keeps
Core Animation's old flat-sibling path untouched. Rebuilds run off-main; measured at 2048²/six
layers, the snapshot half is 0.1 ms and three composites are ~55 ms, so that async path is
load-bearing and more so at 4000².

Both collisions fail **silently** — no error, no crash:

1. **`layer.mask` is taken on `LayerHostView`.** Blanking installs a contentless `CALayer` there,
   because `isHidden` and `alpha` both make `hitTest` return nil and a blanked *active* host would
   swallow the first touch of every stroke. §6.4 wants the resolved alpha mask as a `CALayer.mask` on
   the **live stroke view** — `host.strokeView`, a different layer, so the two do not fight as
   written. Move phase 6's mask up to the host and either blanking eats the mask or the mask eats
   blanking, depending on order.
2. **The content-version key §6.2 needs already exists.** §9.1's original `contentVersion` was
   deleted in phase 2 after being measured at a zero hit rate — it keyed on the rendered `CGImage`,
   which `PixelOps.rasterize` mints fresh every call. 5b built one keyed on **model** state (cel id,
   both tiers' identity *and* version, fill/baked image identity) in `CanvasView`'s sandwich key.
   Reuse that. Its trap is already handled: a cel id outlives the buffers under it, so reopening a
   project rebuilds every `RasterLayerTexture` with its counter at 0 under the same id, and a
   version-only key would serve pre-edit pixels.

## Cut deliberately, with the answer already worked out

Mid-stroke, layers above the active one render as Normal. Recovering them exactly needs a `backdrop:
CGImage?` on `RenderRequest` honoured by both backends, plus a per-pixel unpremultiply: composite the
above stack over the pre-stroke backdrop `B` to get `R`, take coverage `c` from the same stack over
transparency, emit `αs = c`, `Cs = (R − B(1−c))/c`. **Ask the owner before building it** — whether
that flicker actually bothers them is worth measuring rather than guessing.

## Gotchas that each cost a cycle — put these in every worker prompt

- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Build `-only-testing` flags into a
  shell *array* and pass `"${SUITES[@]}"` — zsh does not word-split an unquoted `$VAR`. Read
  `totalTestCount` from `xcresulttool`, never the banner. CLAUDE.md has the recipe.
- **A new test file needs a `project.pbxproj` edit** — `PaintSoftwareUITests` opts out of
  `PBXFileSystemSynchronizedRootGroup` and hand-lists its sources, so an unregistered file compiles
  nowhere, runs nothing, and still prints green.
- **After `simctl erase` you must `boot`**, or the runner fails behind a wall of
  `FBSOpenApplicationServiceErrorDomain` meaning only "nothing is booted".
- **Read CLAUDE.md's XCUITest triage before diagnosing any failure.** Erase, boot, re-run the single
  test; a clean pass confirms it was environmental. Never re-run the 22-minute suite to decide.
- **Do not add a heavy case to the fast tier.** A phase-4 case allocating ~400 MB pushed
  `InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull` from 0.073 s to 8.98 s,
  and the failure surfaces in an unrelated suite looking nothing like its cause.

## At each phase boundary

Delegate these; do not do them yourself. Full XCUITest suite after `simctl shutdown all` + `erase` +
`boot`, and say plainly if you skip it rather than implying it passed. Prune the shipped sections of
LAYER_COMPOSITING.md — prune what is done rather than appending status. Append the one-line
SESSION_LOG.md entry and drop the oldest so only five remain. Refresh the graphify report and commit
it. Match the codebase's comment density: it explains why, never what.

**Before you run out of context, write the next session's prompt to `nextprompt.md` and commit it** —
addressed to an Orchestrator, covering whatever is genuinely left of phases 6–9 and §10, including
what you learned that would otherwise be rediscovered and this same instruction. Keep it about this
long. Write it *early* rather than at the end; the last two sessions were both cut off mid-phase, and
a handoff written while you still have room is worth more than a complete one you never get to write.
