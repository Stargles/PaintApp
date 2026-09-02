# Handoff

<!-- The state of the repo and what to do next. One file: this was two once, and they drifted apart
inside a day because the same state had to be written twice. Rewrite it when you close a pass; do not
append to it. What happened and why belongs in `git log` and in the spec documents — this file says
what is true now and what is next. -->

Read this, then [CLAUDE.md](CLAUDE.md), then the specification for whatever you pick up.
[TODO.md](TODO.md) is the owner's asks; [BUGS.md](BUGS.md) is what we find.

## State

**`main` is `43f839c`.** Every commit of this pass is code or the docs that rule it, so a `git log`
tip further along means another session has moved the tree — `git fetch` before trusting anything
here.

**Fast tier: 2330 declared, 2330 executed, 2327 passed, 0 failed, 3 skipped.** Count it statically at
your own base before trusting any number in a brief, including this one.

**No full suite was run this pass.** It has not run since `41eafa9`, which is now many commits back,
and this pass merged a change to the compositing path. **A full run is the first thing the next
session owes**, and it is a phase boundary in CLAUDE.md's sense: `simctl shutdown all` + `erase`
immediately before it, nothing else on the machine, and **pull the per-class table out of
`xcresulttool` the moment it finishes** — the triage runs that follow evict the xcresult that owns it.

**Two branches are in flight and neither agent had reported when this was written.** Do not merge
either on the strength of this file; a worker's tree is a workbench and only its own completion
report says which bytes are the product.

- `tmp/imagestretch` at `31fd14b` in `../PaintApp-imagestretch` — LASSO_MOVE stage 3c, a placed image
  storing its own shape so it stretches and mirrors.
- `tmp/metalchunk` in `../PaintApp-metalchunk` — the Metal half of the stage 3 pin below.

`git worktree list` and the `tmp/*` tips are the real state of both.

**`PerfBaselineTests.testWhatOneFrameOfTheBoxKnobCosts` is still unresolved** and still needs one
isolated run on a genuinely idle machine. It was not run this pass either. **The reason the machine
is never idle was found and it is not the test suite**: Adobe Creative Cloud's daemons —
`AdobeIPCBroker`, `Adobe Desktop Service`, `Creative Cloud` — were burning ~250% CPU across 8 cores
with no Adobe app open. The owner gave standing permission to kill weighty programs; `pkill` on those
three takes the machine back. `Adobe Desktop Service` is a LaunchDaemon and returns.

## What is being built: TODO (29), the background renderer

[RENDER.md](RENDER.md) is the specification. **§1 is the ask in the owner's own words, §2 is sixteen
rulings, §3 is the design, §5 is the build order.** Read §2 rather than re-deriving it.

**Stages 0 through 3 are merged. Stage 4 — the store and the scheduler (§3.5, §3.6) — is next**: the
bake key, the LZ4 files, the decoded ring, the priority queue, the live canvas and play served from
it, and the timeline's baked-frame indication. MEASURE the compression ratio and the decode time on
the device rather than trusting §3.5's expectation of them.

Stage 3 shipped `Engine/ChunkedComposite.swift`: a frame composites one chunk at a time and the
accumulator crosses each cut as a synthetic leaf appended past the end of the real `sources` array,
so neither backend needed a new mode. `FrameRecipe.composite(budgetBytes:)` is now the one way a
whole frame becomes an image; the eyedropper and `ProjectStore`'s thumbnail go through it.

## What this pass established, and would otherwise be re-derived

- **A chunk continuation keeps the paper in `background` and suppresses only the fill.** §3.4 said to
  pass `background: nil` for chunks after the first, and that is wrong twice: `gradedInkOverPaper`
  lays the paper back down under the graded ink, and `paperInBackdrop` *is* `background != nil`, so
  nilling it makes the `.ink` re-walk silently not happen — a wrong picture with no error, which is
  the failure §3.4 rule 3 exists to prevent. §3.4 carries the correction.
- **The chunk-width formula in §3.4 double-counted.** `peakCompositeTextures` already is
  `2 + depth-pairs + intermediates`, so the stated peak's leading `2 +` charges the root accumulator
  pair twice. It is `N = max(1, budget/textureBytes − 2 − tree.peakCompositeTextures)`, counted in
  leaf sources, with masks inside `N` rather than as a separate 1 B/px term.
- **KEYFRAMES stage 4 is not a prerequisite of stage 5, and the width question is closed.**
  `mapping(_:throughStretch:)` already computes `sqrt(|det|)` verbatim, and for an affine that is
  **exact at every dab** rather than approximate — an affine's determinant does not vary with
  position, so the one scalar `VectorStroke.size` carries *is* the per-dab area root. MEASURED over
  eight poses in `tools/pose_width_ab.swift`. **The rest-space bake is a prerequisite of 5b, Distort**,
  where local scale spans 1.3x to 8.5x across a quad and the best single scalar is wrong by 15%–315%.
- **"Pose through the similarity path and nothing re-phases" is not available.** `stampSpacing`'s 1 pt
  floor makes a *Uniform* shrink re-phase the dab walk too — MEASURED on 19 of 24 frames for a 24 pt
  Hard Round animated 1.0 → 0.3.
- **Two per-frame mapped-stroke paths exist and only one carries the width rule.**
  `InterpolationEvaluator.warped` scales by `thicknessFade` alone. Stage 5 must pose through
  `mapping(_:throughStretch:)`.
- **The clamped-edge scratch window was worse than BUGS.md described it.** The entry said such a dab
  rebuilds the window at an identical rect and proposed comparing the recomputed rect for equality.
  That fix would have skipped the copy and left the real defect: the unclamped rect also fed `wanted`,
  so the window *grew on every dab* — MEASURED from ~140 pt to a full 512 pt canvas in 20 dabs at one
  point. A written-up symptom is not a diagnosis.
- **`CGRect.contains(.null)` is true**, so an off-canvas guard must come before a containment test or
  a fully off-canvas dab passes containment against a stale window.
- **The graphify post-checkout hook titles `GRAPH_REPORT.md` after the *directory*.** A worktree
  commit of it puts `# Graph Report - PaintApp-<slug>` on a tracked file and collides with every other
  branch in flight. Keep it out of branch commits; refresh the graph once from the main worktree.
  **It was not refreshed this pass**, so the tracked report is behind `main`.

## Standing instructions from the owner about how you work

1. **Conserve tokens, and state the size of a multi-agent run before launching it.** Delegate building
   and test runs. Do not delegate thinking you can do.
2. **Documents say what is true. `git log` says how it got that way.** No dates on decisions, no
   "at the owner's instruction", no "this used to be", no narrating which premise an investigation
   overturned.
3. **A replaced path is deleted, not left beside the new one.** RENDER §2.15 in the owner's words:
   *"very clean and non-redundant, with no peculiarities, and no legacy code left by the previous
   functionality."*
4. **At most one investigation agent at a time.** Building is separate; this is about investigations.
5. **Weighty programs may be killed to free the machine.** Standing permission, given 2026-09-02.

## Traps this pass paid for

- **A brief's prescription is a hypothesis, and two of this pass's were refuted by the worker holding
  the code.** Both refutations are in the list above. Invite the refutation explicitly in the brief;
  it is the cheapest review in the project.
- **A stage can ship a hole that every test agrees with.** Stage 3's whole pin runs on CoreGraphics,
  while the app ships `.automatic` and picks Metal for any graded document — and two lines of the
  chunking are Metal-only, one of them a pooled-texture clear whose absence shows the *previous frame*
  underneath. `tmp/metalchunk` is closing it. **Metal is reachable in the fast tier**:
  `CompositorParityLogicTests` hand-lists `Composite.metal` into the UI-test target so the bundle gets
  its own `default.metallib`.
- **Do not act on a worker's tree before its completion notification arrives.** A committed branch tip
  is not a finished agent.

## Everything else open

**The owner's asks** are in TODO. **(21) is unblocked: stage 5, the transform channel, may start** —
§8's 3b row was stale and is corrected, and the width gate is answered above. **Distort is one feature
reachable from two items** — LASSO_MOVE stage 5 and KEYFRAMES 5b — and it is the owner's named next
want. Its raster tier needs nothing that is not merged; **its ink tier wants stage 4's rest-space bake**
by the measurement above, so build raster first rather than shipping a visible width error. It also
collides with `tmp/imagestretch`'s files, so land that branch before starting it.

(31) holds the three large-canvas symptoms; **16383² still cannot be composited at all** and needs a
downscaled display proxy. (32)-(34) are small. (22), (24), (35)-(37) and (26)-(30) are unstarted, and
the last group needs a design conversation each.

**Deferred by the owner, not refused:** scaling the stroke sample gate by zoom, which would fix the 8x
dab explosion when zoomed out. It is a permanent quality trade, so it wants an A/B the owner can look
at, not a number.

**BUGS.md's memory audit** is eleven ranked sites — the scratch-window one is fixed and pruned — plus
PERFORMANCE §9's eight. RENDER §5 stage 7 is where the rest of them land.
