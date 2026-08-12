Read LAYER_COMPOSITING.md first — the agreed design, settled with the product owner. §11 is the build
order. Phases 0 through 4 are done, committed and green. **You are doing phase 5: Tier 1 blend modes
on layers and groups (§7), and §5.2's sandwich with them.** Stop at that phase boundary and report;
the product owner re-scopes there rather than in the middle.

You are the orchestrator. You may delegate to worker sessions and pick the model per task, but **at
most 2 sonnet + 1 opus workers running at any one moment** — this is a token budget, not a
suggestion. If usage crosses 90% the product owner will send a save-your-work prompt; commit what you
have with an honest state-of-play note and stop until they send a continue. Ask them directly if
something is genuinely ambiguous — they answer quickly, and §10 item 3 (whether the pass-through
toggle should ship before phase 5 makes it do anything) is *your phase's* open item, so ask it early.

**Phase 5 is two features in one row, and the sandwich is the risky half.** It rewrites
`CanvasView.reconcileLayers`, and with it onion-skin z-order, the Move tool's floating piece, the fill
preview, and per-layer touch routing. Consider building the blend modes first — they are additive and
testable headlessly — and the sandwich second, against a feature that can demonstrate it. That is the
sequencing §11 already argues for; it is written here because phase 4 made the blend half smaller than
it looks and the temptation to do both at once will be real.

What phase 4 built, so you don't rediscover it:

- `LayerFolder` carries `opacity`, `blendMode`, `isIsolated`, persisted in `FolderManifest` and each
  defaulted to its identity. `alphaMask` is deliberately absent — §6.2 puts a mask on `Layer` and
  `LayerFolder` together in phase 6, and every field decodes with `decodeIfPresent`, so an additive
  field later costs no migration. **Do not batch model fields ahead of the phase that reads them.**
- **`BlendMode` is a one-case enum living in `LayerFolder.swift`**, seeded so the buffer rule could be
  written whole. Phase 5 is where it grows the §7 Tier 1 cases *and* where `Layer` gains one — at
  which point move it to its own file. Note that a new app source used by tests needs pbxproj
  registration (see the gotchas below); putting it in `LayerFolder.swift` was how phase 4 avoided
  that for a type it knew would move.
- **`RenderNode.needsOwnBuffer` is the single rule deciding when a group costs an intermediate
  buffer**, for both backends. It previously existed as two spellings of "opacity is not 1", one per
  backend. Its other two clauses — `blendMode != .normal`, and `isIsolated && enclosesABlend` — are
  written and unreachable today. **Phase 5 is what makes them fire**, which means phase 5 is the first
  time they are actually tested. `enclosesABlend` is deliberately conservative (it keeps descending
  through child groups that will buffer anyway); tighten it beside the first fixture that can tell
  over- from under-allocation apart, not before.
- `toggleFolderVisibility` no longer writes through to descendants; a group's `isVisible` gates its
  subtree. Both backends skip a hidden group *before* the buffer question, so hiding one never forces
  a CPU fallback. `isLayerEffectivelyVisible` / `effectiveOpacity` answer the same question for the
  live canvas, which has no tree to walk.
- Old projects are migrated on load (§10 item 3, decided: migrate). The signal is the absence of
  `opacity` from a folder's JSON, so **`FolderManifest` must keep writing it unconditionally** —
  omitting it when it happens to be 1 would re-arm a one-time migration on every save forever.

**Three things in phase 4 are exactly what phase 5 overturns or finishes.**

1. *`MetalCompositor` declines any request needing a buffer and falls back to CPU.* That was free when
   the only trigger was a faded group. Blend modes are per-pixel math over 4.2M pixels and are the
   entire §5.1 argument for the GPU, so phase 5 has to write the scratch-texture path — plus §5.3's
   texture pool, since the measurement below says intermediates are what hurt.
2. *Group opacity on the live canvas is an approximation, and is documented as one.*
   `effectiveOpacity` folds a group's opacity into each child, which differs from fading the group's
   finished composite wherever children overlap. The sandwich is what makes it exact. When you fix it,
   delete the doc comment saying it is approximate rather than leaving it to rot.
3. *The pass-through toggle ships doing nothing observable.* With every child at `.normal`,
   source-over is associative, so isolation changes no pixel. Phase 5 is when it becomes real — and
   `CompositorParityLogicTests` has isolated-and-pass-through cases asserting byte-identity today that
   **must** stop being identical once a child blends. Update them by hand.

`CompositorParityLogicTests.flatWalkComposite` is still the frozen oracle of what shipped. Phase 4
added `assertCompositesAs(_:asIfFlat:)`, which re-asks the oracle about a *different* document rather
than teaching it about folders — reuse that shape. **Do not relax the oracle to make a failure go
away**; that friction is the point, and blend modes change composited output on purpose.

Gotchas that each cost a cycle:

- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Use an array and `"${SUITES[@]}"`,
  and read `totalTestCount` from `xcresulttool`, never the banner. CLAUDE.md has the recipe.
- **After `simctl erase`, boot the device before `xcodebuild test`** or the runner fails to launch with
  `FBSOpenApplicationServiceErrorDomain Code=1` — an alarming wall of text that means only that the
  device was not up. `xcrun simctl boot <udid>; xcrun simctl bootstatus <udid> -b`. This is new advice;
  CLAUDE.md's triage section tells you to erase and does not tell you to boot.
- **Heavy cases in the fast tier fail an unrelated suite.** A phase-4 perf case allocating ~400 MB of
  intermediates pushed `InterpolationRenderLogicTests.testPreviewIsSubstantiallyCheaperThanFull` from
  0.073 s and passing to 8.98 s and failing, whenever the two shared a runner process. The case was
  dropped rather than kept. If a timing test fails in a suite you did not touch, suspect this first.
- **Read CLAUDE.md's "Triaging a failed XCUITest" before diagnosing any failure.** Erase, re-run the
  single test, treat a clean pass as confirmation. Do not re-run the 22-minute suite to decide.
  `uptime` is useless here — use `top -l 2 -n 0 -s 2 | grep "CPU usage" | tail -1`.
- **Worker worktrees are created at `origin/main`**, which has none of phases 0–5. Both phase-4 workers
  had to `git merge --ff-only` onto the real foundation before starting. Commit your foundation first
  and tell each worker to verify its base with `git merge-base --is-ancestor` before it writes a line.
- **A new app source used by tests** goes in the pbxproj group "App sources shared with
  PaintSoftwareUITests" *and* the `PaintSoftwareUITests` Sources phase, and must contain no SwiftUI
  `View`. Copy how `RenderRequest.swift` is registered.
- **A new `.metal` file needs explicit test-target membership**, and under XCUITest `Bundle.main` is
  the *runner app*, so ask for the library with `Bundle(for:)` — `CompositorMetalEngine` shows both
  halves. `MetalFillEngine` does neither, which is why its GPU path is still XCUITest-only.
- Memory assertions: `phys_footprint` cannot measure retention in this test process. Assert on
  `cgImage.bytesPerRow * height`.
- Vector is the default layer kind, so default names are "Vector N" and `readLayerStrokeCount` reads 0
  on one — use `readVectorMarker(app, layerIndex:)?.strokes`, or `addRasterLayer(app)`.

Numbers worth having before you optimise anything: six layers at 2048² cost **276 ms to snapshot and
84 ms to composite** — the expensive half is building the snapshot, and the sandwich caches
composites, so memoizing `PixelOps.rasterize` per cel version is what addresses the 276 ms if the live
canvas becomes the problem. Six levels of nesting cost **41.6 ms flat, 46.0 ms transparent, 1071.7 ms
once every level buffers** (~25× a whole flat composite, from ~400 MB of intermediates). That last
number is the case for the texture pool and against allocating a buffer you do not need. The GPU's
1189 ms is simulator-bound and is not a verdict on Metal. There is no texture cache because the one
written for phase 2 was measured never hitting; a key that works must come from the model (cel id +
the two `version`s + the two image identities + quality).

Still open, none of them yours unless you want them: the onion skin flattens a cel set at alpha 1
ignoring layer opacity and visibility, so converging it changes what artists see; the project
thumbnail ships transparent-backed on a black gallery; and `makeRenderRequest`'s elision still asks
only `layers[i].isVisible`, so a hidden group's layers are still rasterized before being skipped —
deliberate, because `ancestorFolders` and the tree disagree about containment in a cyclic document and
an elision stricter than the compositing rule drops a layer that should have drawn.

Constraints: follow CLAUDE.md (multi-session protocol, build/test tiers, graphify). Run the fast
`*LogicTests` tier constantly; run the full suite at the phase boundary, and if you skip it say so
plainly rather than implying it passed. Match the surrounding comment density and idiom — this
codebase explains why, not what, and it is worth reading a neighbouring file before writing in it.
Keep the docs short: prune what is done rather than appending status. Append the one-line
SESSION_LOG.md entry (keeping only the last five) and refresh the graphify report.

When phase 5 is done and verified, end by writing the copy-paste prompt for the next session —
whatever is genuinely next, including what you learned that would otherwise be rediscovered, and the
same instruction to write the following session's prompt at the end. Keep it about this long. **Write
it to `nextprompt.md` in the repo root and commit it**, rather than only to a scratchpad: a previous
session left it in a session-scoped temp directory and it had to be recovered from a transcript.
