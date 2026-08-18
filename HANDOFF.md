# Handoff — 2026-08-18

Written winding down at the session's usage limit. **Verify before trusting it** — `git log`,
`git worktree list` and [TODO.md](TODO.md) are the live state. Read [CLAUDE.md](CLAUDE.md) first, then
TODO.md (the owner's asks), [PERFORMANCE.md](PERFORMANCE.md) (new, and the largest thing this pass
produced) and [BUGS.md](BUGS.md).

`main` is at **1178 tests in the fast tier**, 1175 passed / 3 skipped / 0 failed. Six branches merged
this pass; one is still open — `tmp/lasso` — and it is the thing to start on.

## The one thing to read first

**A live owner bug is half-solved and its fix is specified but not written.** The lasso fill fills the
entire canvas when the artist circles something. The owner has ruled on what it should do instead, a
research workflow was still running when this was written, and the diagnosis branch has already
committed a characterization test pinning the wrong behaviour. **Start there.** Details below under
"tmp/lasso".

## What merged

- **The onion skin panel**, with the device numbers that settled it (§ below).
- **The app-switch save gate** — the owner's "returning from another app freezes for a few seconds".
- **[PERFORMANCE.md](PERFORMANCE.md)** — the ranked programme from a ten-agent investigation.
- **Add Text stage 1a** — the menu row and the mode, landing alone as the plan specified.
- **The oval/partial-oval unification**, all six stages.
- **[LASSO_FILL.md](LASSO_FILL.md)** — the specification for the open bug.

## The two owner answers that did more than any analysis

Both were free, and each settled a question that reading code had not.

**"Exactly where I left off."** Asked whether the app returns in place or on the Gallery after the
freeze, the owner said in place. Nothing in this app restores state, so a real relaunch provably lands
on the Gallery — which rules out a jetsam kill and leaves the app's own main-thread work. That found
the cause (a scene-phase guard with no direction check firing three full saves per app switch, one on
the return leg) **and demoted the entire memory programme**, which had been sized against the
hypothesis their answer disconfirmed.

**"4096×4096."** The 17 fps report was measured at 4K, not at their usual 2048×1024. So the area model
holds, one investigation loses its motivation, and the `.overlay` rewrite — which the recalibration had
demoted as "dramatic at 4K, and nobody works at 4K" — turns out to be the canvas the owner's own worst
experience came from. BUGS.md now pins the canvas size to that report; its absence is what caused the
ambiguity.

**The lesson, and it has now happened three times: ask the owner before building.** It is in MEMORY.md
already and it keeps paying.

## Onion skin: what the device settled

Re-run on the owner's iPad 9 in Release, at **2048×1024 as well as 4096²** — the perf tests hard-coded
4K and the ruling turned on the owner's real canvas.

| 2048×1024 | composite | 2 skins | 10 skins |
|---|---|---|---|
| Full | 2048×1024 | 37.4 ms | 237.1 ms |
| Half | 1024×512 | 9.4 ms | 59.8 ms |
| Quarter | 768×384 | 5.4 ms | 33.9 ms |

At 4096²: Full 311.3 / 1953.8 ms, Half 79.9 / 486.2, Quarter 19.3 / 120.6.

- **The `skins5 > skins10` inversion was a cold CPU, confirmed.** `skins5Cold` 98.8 ms against 56.2 ms
  warm, and the warm series is monotonic (6.1 / 56.2 / 118.8). The new assertion passed rather than
  firing.
- **Cost is calculable**: 11.5 ms per megapixel per skin at ten skins, 9.2 at two, holding within 3%
  across both canvases and all three options. That is what the panel's caution estimates from.
- **The device is ~1.3× the simulator for this workload**, not the ~1.1× previously recorded.
- **Unexplained, and left that way**: per-skin cost *rises* with skin count (9.2 → 11.5). A fixed
  per-composite overhead predicts the opposite. It changes no decision.
- The owner ruled **"Both"** on the Full question: the picker names each option's real composite size,
  and a caution appears only when the estimate crosses 250 ms.
- **Found while closing out, and it is in BUGS.md**: at Full, `OnionSkinRasterCache` falls through to
  the compositor's shared cache with canvas-sized entries — exactly the eviction it exists to prevent.
  Full's real cost at 4096² is ~2.9 s per drawing change, not 1954 ms. The owner's canvas is unaffected.

## Open: `tmp/lasso` — the live owner bug

Worktree `../PaintApp-lasso`, at `51575f6`. **Two commits, both safe, no behaviour change yet.**

The owner: *"Lasso tool is not working as intended. When i circle something the entire canvas gets
filled."*

**It is the design, not a defect — and the design breaks the tool's own gesture.** `Fill.metal:186`
seeds every open pixel under the loop and nothing bounds the flood; the only combine is a union
(`MetalFillEngine.swift:335-338`). The step the design missed: **"circle something" means drawing
*around* it, so the loop necessarily encircles paper outside the shape, and that paper is a seed.**
Measured on a *perfectly closed* box, same tool, same artwork, only which side of the outline the loop
was drawn on differing: loop around the shape fills **1.000** of the canvas; loop inside it, 0.338. No
setting recovers it. Everything shipped because every prior assertion sampled individual pixels and
none asked *how much*.

**The owner's ruling**, across two answers: the loop is a hard wall; the fill is bounded by the artwork
inside and should not reach the loop; a loop well outside a shape leaves the ring blank. They added:
*"the lasso fill may have to be an entirely different algorithm than the normal fill"*, asked for
research into Clip Studio Paint and others, and proposed **flooding the outside from the loop and
inverting**.

**The invert formulation is validated and cheap.** Production change is roughly one character in
`Fill.metal:186` (`!= 0` → `== 0`) plus swapping the final union for an intersect-with-complement.
Multi-pixel seeding already exists; the winding mask is already available at both stages; gap closing
already runs before the flood and needs no move; the antialiasing error moves to the *far* side of the
line, which is an improvement — but **`fillExpand` (default 2) would then push the fill 2 px past the
artwork and wants to be 0 for this mode.**

**Two consequences the owner has not seen yet and should**:
1. The real cost is not just "blank paper fills nothing" — it is *any loop that does not wholly contain
   an artwork-enclosed region fills nothing.* A loop drawn **inside** a shape fills 0 (today: the whole
   shape). A loop **crossing** the outline fills 0.0022. The artist must enclose the whole shape, every
   time.
2. **Isolated line art gets painted with no region around it.** On a two-compartment scene the result is
   the dividing line painted and *neither* compartment filled. A connected-component filter — drop
   components containing no non-wall pixel — fixes this and the bare-outline case together.

**The research landed and is merged as [LASSO_FILL.md](LASSO_FILL.md).** Read it before writing any
code — it is the specification. The headline: the owner's proposal is, word for word, steps 1-2 of
Krita's shipped *Enclose and Fill*, whose design document is explicitly an analysis and recreation of
Clip Studio Paint's tool. Its formal name is morphological hole filling (Vincent 1993; Soille §6.3),
with the artist's loop substituted for the image border.

**One thing I got wrong and the research corrected**: I proposed adding a connected-component filter to
stop isolated line art being painted with nothing around it. **Do not add it.** A face's eyes are walled
off by their own ink, so they are unreachable from the loop and fill along with the face — which is the
direct consequence of the owner's "all inner lines are filled over", since painting over the eye
outlines necessarily paints their interiors. A component filter would make the eyes behave differently
from the face and puts a branch back into a rule that does not need one.

Tests that must change with the fix are enumerated in the agent's report and in the branch: six
characterizations plus five existing assertions that pin the old contract, and three load-bearing doc
comments (`CanvasManager+Fill.swift:275-289`, `Fill.metal:165-178`, `Tool.swift:66-78`).

## The oval unification merged after this was first written

All six stages, `ShapeDetectorLogicTests` 48 → 67, fast tier 1178. Kept here because two facts about it
are worth carrying and are not obvious from the diff.

**The model is two defaulted scalars on `ShapeGeometry`** — where on the outline the pen started, and
the **signed, never-wrapped** fraction it turned through. Not reducing that mod 1 is the whole trick:
seam crossing, direction and overshoot stop being cases and become the number itself.

**Eccentric angle, and the snap proves it.** The two-finger snap is an anisotropic scale mapping the
point at eccentric angle `t` on the ellipse to the same `t` on the circle, exactly, for every `t` — so
the drawn portion survives with zero new code in `constrained`. Polar angle is not invariant (106.77 pt
of slip on a 4:1 oval). **A test asserting only "a quarter oval snaps to a quarter circle" passes under
both**, so the sweep tests an interior angle deliberately; do not simplify that test away.

Two things to watch if this area is touched again: `testRejectsRandomScribble` now survives on the
length gate alone (fit error 0.1399 against a 0.16 ceiling), so if it ever creeps, **tighten the length
gate, not the error gate** — the error gate's calibration is what keeps rectangles working. And the
conic fit changed every oval's fit, not only partial ones; 50 jittered shapes gave zero kind
disagreements, and full ovals now come out slightly smaller and more accurate.

**Open for the owner**: a double-traced ellipse detects as a *rectangle* (the oval is rejected at ratio
2.00 and the rectangle runner-up wins). Pre-existing, verified against the prior commit, not a
regression. And there are no arc-end handles, which the design flagged as the most likely thing they
overrule.

## Still queued

Add Text stages 1b onward (**Stage 2 is already on main — do not build it**; ADD_TEXT.md now says so),
the perf programme's Tier A (six changes remain after the save gate), the gallery-exit wait, and the
`.overlay` rewrite.

## Two questions the owner still owes

- **Save semantics** when a project loaded with something unreadable: may saving overwrite the good
  original, refuse, or prompt? Unchanged from the last handoff; still blocking nothing.
- **Which faces belong in the font picker's favourites strip.** Needed by an Add Text stage that builds
  the panel's contents, not by stage 1a.

## Process, this pass

- **`git merge --ff-only` run from inside the branch's own worktree prints "Already up to date" and
  merges nothing.** Success-shaped output for a no-op. I did it three times before noticing. Run merges
  from the main worktree, as their own command, with `git branch --show-current` in front.
- **The agent scratchpad is not session-private**, despite being documented as such. Two agents wrote
  the same log filename and clobbered each other; one lost a run and misdiagnosed a failure. Prefix
  scratch files per agent.
- **A device test run fails with "Timed out while enabling automation mode" if the iPad is locked**, and
  reports as a test failure with zero tests run. Ask the owner to unlock, then re-run.
- **Verify numbers, trust mechanisms.** A citation audit of the performance investigation found every
  *mechanism* real, a third of the line numbers drifted, and four figures labelled "measured on device"
  that appear nowhere in the tree — inherited from the saved workflow script's own ground text, since
  corrected. The same audit on ADD_TEXT.md found ten drifted references, one naming the wrong file.
