# Multi-Session Protocol

Multiple sessions may work this repo concurrently, each in its own worktree. Never edit `main`
directly. Assume the tree has moved — `git fetch` before trusting what you remember.

```bash
git fetch origin
git worktree add ../PaintApp-<id> -b tmp/<id> origin/main   # <id> = short descriptive slug
```

Finish and merge (build/test first, or say you couldn't):

```bash
git fetch origin && git rebase origin/main
cd ../PaintApp && git merge --ff-only tmp/<id> && git push origin main
git worktree remove ../PaintApp-<id> && git branch -d tmp/<id>
```
If `--ff-only` fails, rebase again — don't force-push, don't merge-commit. Append one line to
[SESSION_LOG.md](SESSION_LOG.md): `Session N — YYYY-MM-DD: <what changed>`, and drop the oldest so
only the last five remain — `git log` is the real history.

## Build and test

Xcode lives at `/Applications/Xcode.app`; `xcodebuild`/`xcrun` are on PATH. Metal shaders need the
toolchain once: `xcodebuild -downloadComponent MetalToolchain`.

- **Fast tier (~1–2 min)** — the pure-logic `*LogicTests` run headless. Use constantly.
- **Full run (~26 min)** — XCUITests are 99% of the runtime. Phase boundaries only, and
  `simctl shutdown all` + `erase` the simulator *immediately before* it: leftover parallel clones
  are the cause of nearly every mystery failure.

### Why the full run costs what it does

**`xcodebuild` distributes parallel work per test *class*, never per test**, so a class is
indivisible and the longest one sets the critical path. That is the whole cost model, and it is why
class granularity — not worker count — is the lever.

Measured 2026-08-15, before and after splitting the six heavy UI classes into three each:

| | tests | wall clock |
|---|---|---|
| six indivisible UI classes | 961 | 25.7 min |
| eighteen | 1023 | **18.8 min** |

Before the split four clones received 482 / 324 / 74 / **44** tests and two sat idle on the home
screen while the last ground on; ~1,950 s of the run lived in six classes (ToolsAndSelection 424 s,
TimelineAndUndo 392 s, VectorShapeAndRecovery 389 s, VectorEraser 357 s, Fill 277 s, Layer 107 s)
against ~250 s for every logic test together.

**That was true and is no longer.** Measured again 2026-08-29 on the full run at `0717ed6` — **2221
tests in 25.6 min**, which is where the suite sat *before* the 2026-08-15 split. The gain was not lost to
general slowness; **one class ate it**:

| class | seconds | tests |
|---|---|---|
| **`LayerPanelUITests`** | **517** | 19 |
| `SelectionAndMoveUITests` | 337 | 10 |
| `SandwichCompositingUITests` | 307 | 10 |
| `BlendModesAndCompositorUITests` | 275 | 8 |
| `CuttingModesUITests` | 188 | 4 |
| `PerfBaselineTests` | 183 | 53 |

3,607 class-seconds total, so four clones have ~15 min of ideal work in them — and the run takes 25.6
because **a class is indivisible and `LayerPanelUITests` alone is 517 s**, 2.7x the 189 s test that used
to be the floor. The lever is the same one that worked before: split that class (it lives in
`LayerUITests.swift`, which already holds three), and the floor falls back toward ~190 s. Note it is
*also* the class that produced this run's one environmental red, which is what a class held that long
under parallel clones tends to do.

**Re-taken 2026-08-29 at `4b86966` and it holds** — **2274 tests in 22.3 min, 0 failed, 6 skipped**, the
first full run in several passes with no environmental red either. `LayerPanelUITests` **515 s / 19**,
`SelectionAndMoveUITests` 327 / 10, `SandwichCompositingUITests` 297 / 10,
`BlendModesAndCompositorUITests` 222 / 8, `CuttingModesUITests` 177 / 4, `PerfBaselineTests` 173 / 53,
plus two the earlier table did not carry — `EraserAndPersistenceUITests` 171 / 7 and
`TimelineGestureUITests` 144 / 7. 3,542 class-seconds, so four clones hold ~15 min of ideal work against
a 22.3 min run and **the gap is still one indivisible class**. The 25.6 → 22.3 move is variance, not
structure: nothing was split.

**`LayerPanelUITests` was cut on 2026-08-29 and that floor is gone.** It is three classes now, still in
`LayerUITests.swift` (which therefore holds five): `LayerStackUITests` — the shape of the stack, add /
delete / reorder / swipe; `LayerFolderAndMaskMenuUITests` — folders, what a drop onto one resolves to,
and the mask sub-menu that opens from a folder's options as well as a layer's; and
`LayerPanelControlsUITests` — the panel's controls rather than its contents, the views dropdown through
the effect settings bar to the colour swatches. MEASURED serially on a dedicated device, 19 tests,
0 failed, counted from the xcresult:

| class | seconds | tests |
|---|---|---|
| `LayerFolderAndMaskMenuUITests` | 190 | 7 |
| `LayerPanelControlsUITests` | 174 | 7 |
| `LayerStackUITests` | 159 | 5 |

523 s in total against **534 s measured for the same 19 tests as one class immediately before the cut**,
so the work is unchanged and only its granularity moved. **The longest of the three is 190 s against
515 s**, which drops this file below `SelectionAndMoveUITests` and makes *that*, at 327 s, the suite's
new floor.

**MEASURED 2026-09-02 at `35c0db6`, on an idle machine — 2482 tests in 21.7 min, 2474 passed, 2 failed,
6 skipped.** Both failures re-ran clean in isolation (48 s and 140 s) and are environmental, not
findings. Freshly erased simulator, under `simlock`, nothing else running.

| class | seconds | tests |
|---|---|---|
| **`SandwichCompositingUITests`** | **356** | 10 |
| `SelectionAndMoveUITests` | 309 | 10 |
| `BlendModesAndCompositorUITests` | 259 | 8 |
| `LayerPanelControlsUITests` | 238 | 7 |
| `LayerFolderAndMaskMenuUITests` | 196 | 7 |
| `CuttingModesUITests` | 170 | 4 |
| `EraserAndPersistenceUITests` | 169 | 7 |
| `PerfBaselineTests` | 164 | 54 |
| `LayerStackUITests` | 162 | 5 |
| `GraphEditorUITests` / `GraphEditorGestureUITests` | 142 / 138 | 7 / 3 |

**3,794 class-seconds across 109 classes. Four clones hold 15.8 min of ideal work against a 21.7 min
run, and the longest class is 5.9 min — so the gap is NOT the indivisible-class story this section told
from 2026-08-15 to 2026-08-29.** About 5.9 min, ~37% over ideal, is scheduling: clone boot, per-class
setup, and the tail where classes run out before the clones do. **That is where the lever is now.**
Splitting further cannot recover it and past some point makes it worse, because every new class pays its
own setup — INFERRED from the arithmetic, and the experiment nobody has run is a full suite with the
class count deliberately *reduced*.

**`SandwichCompositingUITests` is the longest class and again one of the two that red**, which is what
this file predicts of a class held long under parallel clones. It has been the next split candidate
across three consecutive full runs and has not moved; splitting it buys at most the difference between
356 s and the ~309 s class behind it, which is why nobody has.

**Two failing tests, two classes whose names differ from their files** — `SandwichCompositingUITests`
lives in `LayerUITests.swift` and `InterpolationWorkflowUITests` in `TimelineAndUndoUITests.swift`. A
selector built from the filename matches nothing and reports `** TEST SUCCEEDED **`. Resolve the class
from the source every time; the snippet below does it.

**A run measured against a busy machine is not a measurement, and this section nearly recorded one.**
The first attempt ran concurrently with a research workflow whose agents read files and compiled with
`swiftc`. It reported **28.5 min** — four minutes worse — while its per-class seconds came out at 3,864
against the clean run's 3,893, i.e. within noise. **Contention cost wall clock through scheduling and
left the per-test durations almost untouched**, so the class table looked right while the headline was
wrong by four minutes. That is the banner-versus-count trap wearing yet another costume: measure the
suite on an idle machine, or do not write the number down.

**Balance a split on measured seconds, not on test count**, which is why these are 5/7/7 and not 6/6/7:
`testRepeatedAddDeleteLayersDoesNotCrashOrFreeze` measured 71 s and then 58 s on two runs — a seventh of
the old class in one test — so the class holding it earns two fewer. It is also this file's real
remaining floor, because **no split goes below one test**: ~60 s is the limit here and a fourth class
would buy almost nothing.

**A second class was split the same day, and it is the more instructive one because it grew under
observation.** `GraphEditorUITests` was ~40 s when the graph editor's first stage created it, and three
stages later it was a MEASURED **271 s across 10 tests** — the suite's second-longest class, behind only
`SelectionAndMoveUITests`. Nothing went wrong: each stage added two or three tests to the obvious place,
and every one of them pays a fixture cost (there is no shorter way to author an animated channel than two
keyframe marks plus a slider drag). It is now `GraphEditorUITests` (7 tests / **133 s**) and
`GraphEditorGestureUITests` (3 / **136 s**) in the same file — 269 s of work against 271 s before, so the
split cost nothing and the work now occupies two clones. **The lesson is that a class grows past the floor
while nobody is looking**: `LayerPanelUITests` had to be *discovered* at 515 s, and this one would have
been discovered later at a worse number. Re-take the class table when you add UI tests to an existing
class, not when the suite feels slow.

`testInterpolateModeEndToEndFromGestureToScrub` is **MEASURED at 150 s run alone** (2026-08-30), so it
is half of its class's floor by itself and decomposing it is still what going below ~3 min would need.
The next class worth cutting is `SandwichCompositingUITests` at 344 s. **Re-take this table rather than
trusting it — it has now gone stale twice, been confirmed once, and been acted on once.**

**MEASURED at `04099a9` on an idle machine — 2759 tests, 2752 passed, 1 failed, 6 skipped.** The one
failure, `BlendModesAndCompositorUITests`' `testHidingFolderHidesContentsOnCanvasAndReshowingRestoresThem`,
**passed clean in isolation** and is environmental. That run followed a pass that rewrote the compositing
path — the bake store, the scheduler, striped rendering, the live canvas served from disk, export.

| class | seconds | tests |
|---|---|---|
| `SelectionAndMoveUITests` | 336 | 10 |
| `SandwichCompositingUITests` | 330 | 10 |
| **`BlendModesAndCompositorUITests`** | **311** | 8 |
| `LayerFolderAndMaskMenuUITests` | 240 | 7 |
| `PerfBaselineTests` | 233 | 56 |
| `LayerPanelControlsUITests` | 214 | 7 |
| `LayerStackUITests` | 165 | 5 |
| `EraserAndPersistenceUITests` | 163 | 7 |
| `CuttingModesUITests` | 161 | 4 |
| `GraphEditorUITests` / `GraphEditorGestureUITests` | 157 / 143 | 7 / 3 |

**4,206 class-seconds across 129 classes**, against 3,794 across 109 at `35c0db6` — the cost of ~280 new
tests, which is close to free per test.

**The shape of the problem has changed, and this section should stop looking for one long class.** From
2026-08-15 to 2026-08-29 the lever was always a single indivisible class: `LayerPanelUITests` at 515 s,
then `SandwichCompositingUITests` at 356 s. **The top three are now within 25 seconds of each other at
~330 s**, so no split buys anything — cutting the longest just makes the second-longest the floor. Four
clones hold ~17.5 min of ideal work; whatever the gap to wall clock is, it is scheduling and per-class
setup, not one class. **Splitting further now makes it worse**, because every new class pays its own
setup, and the class count has already grown 109 → 129.

If you split a class again, **verify by test count from the xcresult** — a test that stops running
still prints green — and take the count *before* you merge as well as after: a split branch cut
before something was deleted will silently resurrect it, and the count is the only signal.
- Use the dedicated simulator by UDID: `eraser-mutex-test`,
  `75C8B97E-47AF-484B-B7D2-CA7EB1B51B03`. Passing `-destination name=...` for a device this Mac
  doesn't have (there is no "iPad Pro 13-inch (M4)" — it is an M5) does **not** error; xcodebuild
  silently falls back, and you spend the run wondering what you tested.
- `Engine/Deform` compiles standalone with `swiftc` (~5 s a loop) — use it to test engine
  hypotheses instead of a 90 s `xcodebuild test`.
- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran.** Read the count, never the banner:

  ```bash
  xcrun xcresulttool get test-results summary --path "$(ls -dt build/DerivedData/Logs/Test/*.xcresult | head -1)"
  ```
  `totalTestCount: 0` with `result: "unknown"` is what a malformed `-only-testing` produces — and the
  shell is the usual cause, because **zsh does not word-split unquoted `$VAR`**. Building a list of
  flags into a string and passing `$SUITES` sends xcodebuild one long bogus argument, which it
  ignores while reporting success. Use an array and `"${SUITES[@]}"`. The whole fast tier is:

  ```bash
  SUITES=(); for s in $(ls PaintSoftwareUITests/*.swift | xargs -n1 basename | sed 's/\.swift$//' | grep -E "LogicTests$|CharacterizationTests$|^PerfBaselineTests$"); do SUITES+=(-only-testing:PaintSoftwareUITests/$s); done
  xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
    -destination 'platform=iOS Simulator,id=75C8B97E-47AF-484B-B7D2-CA7EB1B51B03' \
    "${SUITES[@]}" -parallel-testing-enabled NO -derivedDataPath build/DerivedData
  ```
  **The selectors are built from *filenames*, and that loses tests silently in two directions.** Both
  fired on 2026-09-02, in one session, in opposite ways. A filter hand-rebuilt as
  `"LogicTests$|CharacterizationTests$"` drops the third alternate and with it **`PerfBaselineTests`,
  53 tests** — and that is specifically the *timing* suite, so a hand-rolled fast-tier filter is blind
  to performance regressions by construction. In the other direction, a *class* placed in a file of
  another name never runs at all: `-only-testing:` names the file's stem, so the class is not selected
  and nothing says so. Both report `** TEST SUCCEEDED **` with a plausible-looking count. Use the
  command above verbatim, keep one `XCTestCase` per file with the class named after the file, and
  reconcile the xcresult's `totalTestCount` against a static `func test` count at your own head — the
  arithmetic is what catches it, and nothing else will.

  **`-parallel-testing-enabled NO` on every run that is not the full suite.** The scheme carries
  `parallelizable = "YES"` (PaintSoftware.xcscheme:48) and that is correct — it is the whole cost
  model above — but clones only earn their keep when there are many classes to distribute across
  them. The logic tier is ~250 s of work total, so the clone boots cost more than they save, and
  this section already warns that leftover clones cause "nearly every mystery failure".

- **The log's per-test line is spelled differently in a parallel run than in a serial one**, so a grep
  that counts one silently reports **zero** for the other. Serial prints
  `Test Case '-[Suite testName]' passed`; parallel prints
  `Test case 'Suite.testName()' passed on 'Clone 1 of …'` — different case, different shape, no
  brackets. Counting a live parallel run with the serial pattern reads as a run that has started no
  tests at all, which looks exactly like a hang; that cost one session a wrong diagnosis of a healthy
  run twenty-five minutes in. It is the banner-versus-count trap again, so the answer is the same one:
  **for a finished run read `xcresulttool`, never the log.** The log counts disagreed with the
  xcresult on the very run that prompted this note (1914 against 1925) because a clone's output
  interleaves and a line can be split.

- **Pull the per-class table immediately after a full run, before running anything else against that
  `-derivedDataPath`.** Xcode keeps only a handful of recent `Test-*.xcresult` bundles per derived-data
  path, so the five single-test triage runs that follow a full suite evict the full run's own bundle —
  and the table this file keeps asking to be re-taken is then unrecoverable. Reconstructing it by
  summing each test's reported seconds out of the console log is not a substitute: it is a
  log-reconstruction of a number the xcresult owns, and on a parallel run the log's per-test lines
  interleave and split.

- **A red xcresult is evidence about a *binary*, not about your working tree** — the same trap as the
  banner, pointing the other way. `test-without-building` reuses whatever bundle was last compiled,
  so editing a source file and re-running it tests the *old* code while reporting against the new
  commit. Session 24 spent an opus worker "fixing" three effects that were already correct: a Sobel
  divisor of 4 had been changed to `1/√20` before the commit, but the failing run predated the
  rebuild, and every reported byte (128 where 114 was wanted, 90 where 81 was) is exactly the ratio
  `√20/4 = 1.118` between the two constants. Before debugging a numeric failure, diff the constant
  the test names against the value it reports — that is thirty seconds and it settles which of the
  two you are looking at. Use plain `test` (which builds) unless you have a reason not to.

  **And the simulator you are *driving* is a binary too, which is the same trap pointed at the
  screenshot.** `simctl install` ships whatever `build/DerivedData/.../*.app` currently holds, and
  that is the last thing any `xcodebuild` wrote to that path — including the run you used to
  mutation-test an assertion. Session 26 reverted a deliberate `depth: 0` mutation, installed without
  rebuilding, drew with the brush, and spent a cycle diagnosing a shipped defect that existed only in
  the installed bundle. **Rebuild between a mutation run and a drive**, and when a drive contradicts a
  green test about the same code, suspect the bundle before the code.

**MEASURED at `8a4f156` — 3048 tests, 3042 passed, 0 failed, 6 skipped, and no environmental red at all**,
which is rare enough here to be worth stating. The wall clock was 24.9 min but **that number is not a
measurement**: two logic-tier runs were queued alongside it under `simlock`. Per this section's own 2026-08-29
finding, contention costs wall clock through scheduling and leaves per-test durations almost untouched, so
the class table below is usable and the headline is not.

| class | seconds | tests |
|---|---|---|
| `SandwichCompositingUITests` | 343 | 10 |
| `SelectionAndMoveUITests` | 285 | 10 |
| `BlendModesAndCompositorUITests` | 265 | 8 |
| `PerfBaselineTests` | 228 | 56 |
| `EraserAndPersistenceUITests` | 197 | 7 |
| `GraphEditorGestureUITests` | 196 | 4 |
| `LayerFolderAndMaskMenuUITests` | 192 | 7 |
| `LayerPanelControlsUITests` | 184 | 7 |
| `CuttingModesUITests` | 160 | 4 |
| `GraphEditorUITests` | 158 | 7 |

**4,238 class-seconds across 149 classes**, against 4,206 across 129 at `04099a9` — so ~290 new tests cost
about 30 class-seconds, which is close to free per test and the same conclusion that measurement reached.
**The top three are still within 80 s of each other**, so the "one indivisible class sets the floor" story
that held from 2026-08-15 to 2026-08-29 remains dead: splitting the longest just promotes the second. Four
clones hold 17.7 min of ideal work. **`GraphEditorGestureUITests` is the one to watch** — 196 s across only
**4** tests, the worst seconds-per-test on the board, and this file has twice recorded a graph-editor class
growing past the floor while nobody looked.

**MEASURED at `77430e1` on an idle machine with the simulator erased first — 3159 tests, 3139 passed, 1
failed, 19 skipped, 24:47.** The one failure, `InterpolationWorkflowUITests`'
`testInterpolateModeEndToEndFromGestureToScrub`, passed clean in isolation and is environmental; it is
this file's own longest-single-test at ~150 s and lives in a class whose name differs from its file.

| class | seconds | tests |
|---|---|---|
| `SelectionAndMoveUITests` | 335 | 10 |
| `BlendModesAndCompositorUITests` | 295 | 8 |
| `LayerFolderAndMaskMenuUITests` | 273 | 7 |
| `SandwichCompositingUITests` | 246 | 10 |
| `PerfBaselineTests` | 235 | 57 |
| **`GraphEditorGestureUITests`** | **217** | **4** |
| `LayerPanelControlsUITests` | 213 | 8 |
| `CuttingModesUITests` | 165 | 4 |
| `EraserAndPersistenceUITests` | 162 | 7 |
| `LayerStackUITests` | 160 | 5 |

**4,283 class-seconds across 155 classes**, against 4,238 across 149 at `8a4f156` — so ~190 new tests cost
about 45 class-seconds, the fourth consecutive run to find a new test close to free. Four clones hold 17.8
min of ideal work against 24.8 min of wall clock, and **the top four classes are spread across 90 seconds**,
so there is still no single long class to split and the 2026-08-15 lever remains dead.

**`GraphEditorGestureUITests` is the one to watch and is now the worst seconds-per-test on the board** —
217 s across **four** tests, 54 s each. This file has twice recorded a graph-editor class growing past the
floor while nobody looked, and this is the third time it has drifted up. It is not the critical path, so
splitting it buys nothing today; re-take this table when the next graph-editor test is added.

**MEASURED at `7605169` on an idle machine with the simulator erased first — 3212 tests, 3192 passed, 1
failed, 19 skipped, 25:02.** The one failure is `InterpolationWorkflowUITests`'
`testInterpolateModeEndToEndFromGestureToScrub` **again** — the same test as at `77430e1` — and it
**passed clean in isolation** again. That is now twice in consecutive full runs, so it is worth saying
plainly: this test is the suite's longest single test at ~150 s, it lives in a class whose name differs
from its file, and it is the one that reds under parallel clones. Treat a red there as environmental
until an isolated run says otherwise, and do not bisect it.

| class | seconds | tests |
|---|---|---|
| `SandwichCompositingUITests` | 346 | 10 |
| `SelectionAndMoveUITests` | 274 | 10 |
| `PerfBaselineTests` | 261 | 57 |
| `BlendModesAndCompositorUITests` | 233 | 8 |
| `LayerPanelControlsUITests` | 226 | 8 |
| `GraphEditorGestureUITests` | 206 | 4 |
| `LayerFolderAndMaskMenuUITests` | 192 | 7 |
| `EraserAndPersistenceUITests` | 163 | 7 |
| `CuttingModesUITests` | 162 | 4 |
| `LayerStackUITests` | 161 | 5 |

**4,236 class-seconds across 158 classes**, against 4,283 across 155 at `77430e1` — so ~53 new tests cost
**less than nothing** measurable, the fifth consecutive run to find a new test close to free. Four clones
hold 17.7 min of ideal work against 25.0 min of wall clock, and the top five classes are spread across
120 seconds, so there is still no single long class to split.

**`GraphEditorGestureUITests` has stopped drifting** — 206 s across 4 tests against 217 s at `77430e1`,
so the third rise this file recorded was noise rather than a trend, and the watch on it can relax. The
one to watch instead is **`LayerPanelControlsUITests`**, 226 s across 8 where it was 213 across 8: the
same class, the same tests, thirteen seconds slower. That is the shape of a class growing under
observation, and this file has twice recorded one being discovered late.


**MEASURED at `032efa1` on an idle machine with the simulator erased first — 3241 tests, 3222 passed,
**0 failed**, 19 skipped, 28:55.** A full run with no environmental red at all is rare enough here to be
worth stating, and it is the second in this file's history. graphify's background rebuild — which the
post-commit hook fires and which is the obvious suspect for a busy machine — last ran 84 minutes before
the suite started, so this is an idle-machine number.

| class | seconds | tests |
|---|---|---|
| `SelectionAndMoveUITests` | 398 | 10 |
| `PerfBaselineTests` | 352 | 57 |
| `SandwichCompositingUITests` | 265 | 10 |
| `BlendModesAndCompositorUITests` | 259 | 8 |
| `LayerPanelControlsUITests` | 229 | 8 |
| `LayerFolderAndMaskMenuUITests` | 201 | 7 |
| `EraserAndPersistenceUITests` | 199 | 7 |
| `CuttingModesUITests` | 187 | 4 |
| `ToolPanelsUITests` | 173 | 10 |
| `LayerStackUITests` | 165 | 5 |

**4,537 class-seconds across 160 classes**, against 4,236 across 158 at `7605169` — **+301 s for +29
tests, which breaks the "a new test is close to free" run this file had recorded five times.** Only 98 s
of that is the new work (`BrushMenuUITests`, 5 tests, ~20 s each, and they are dear because each is a
cold start with the library file deleted). **The other ~200 s is on classes that did not change**, and it
is not a slowdown: `SelectionAndMoveUITests` rose 274 → 398 on the same ten tests while
`SandwichCompositingUITests` fell 346 → 265 on the same ten. **Per-class seconds are not independent of
which classes a clone is co-scheduled with**, so at 160 classes across four clones that pairing is itself
a source of variance — which means this table's individual rows are noisier than they look and only the
total is worth trending. Read a single class's rise as a signal only when it repeats.

### A green assertion is only as good as its two operands

Three failures of this shape landed in one day, and none of them looks wrong while you read it.

**A table that builds a fresh fixture per row is comparing allocation addresses.** `LayerContentVersion`
names a cel's tiers by `ObjectIdentifier`, so two `CanvasManager`s differ in every leaf *before* anything
is mutated. A per-field table built that way — one manager per row, digests compared across them —
**passed with the field under test deleted from the encoder it was written to pin.** Mutate one fixture
cumulatively, so a row's difference is attributable to the row.

**`Layer.layerEffect` is `kind == .value ? effect : nil`, and the render path reads the accessor, not the
field.** So `layers[0].effect = …` on a raster layer reaches neither the tree nor the content version:
forty rows of an effect table were setting nothing. `Layer.valueFill` is `kind == .value && effect == nil
? fill : nil` and is inert the same way for a layer already in effect mode. Setting a field the shipped
code does not read is the commonest way a fixture measures nothing.

**And an assertion can be true of mathematics rather than of your code.** A test written to pin the
grain artifact compared `BrushStamper.grainAlphaMultiplier` sampled at a stroke's *rest* points against
the same function at its *posed* points, and required them to differ. That is the position-dependence
of a noise field — **true by definition, under any implementation whatever**, including the one that
fixes the bug. It could not have gone red. The right operands were one level down, where the pixels
are: the dab **alphas** two poses of one stroke actually stamp. When an assertion would hold for any
correct program *and* any incorrect one, it is measuring a definition, not a behaviour.

**And an assertion can be true at the wrong *level*, which is the one that does real damage.** The four
above measure nothing, so they merely fail to help. This one helps in the wrong direction: a **passing**
test asserted `PoseInterpolation.blend(a, b, t: -0.4) == a`, captioned *"before the first key is a
hold"*. The hold is real — but it lives one level up, in `AnimationCurve` and `TransformTrack`'s segment
clamp, so a channel never hands `blend` an out-of-range `t` off either end. The test pinned a guarantee
its own caller already makes, and in doing so **froze a defect underneath it for the length of a stage**:
`blend` clamped where its doc says twice that it extrapolates, and an overshooting handle *inside* a
segment was silently flattened. It could go red; it was simply about the wrong function. So the question
to ask of an assertion is not only "can this go red" but **"if this went red, would the code be wrong?"**

**A fixture can be eaten by the optimisation it is testing.** The obvious ten-frame document for
RENDER §2.16 — one cel spanning frames 2–6, edit it, count re-renders — measures nothing, because that
cel *is* a hold, so those five frames are one bake key and one composite. Every frame needs its own
picture before "five frames re-rendered" is expressible at all.

And `CompositeProbe` counts calls to `Compositor.composite`, which since chunking means **chunks, not
frames**. Pin "one small frame is one composite" as its own test rather than assuming it inside five
others.

**And an expectation can be unevaluatable during the very action it is timed against.** An
`XCTNSPredicateExpectation` built before an XCUITest drag cannot fire during it, because XCUITest's drag
is synchronous — so the affirmative test times out, and its **inverted twin passes unconditionally**,
whatever the app does. That is how a "no readout appears on a sideways drag" test can be green against
an app that shows one on every drag. If an assertion's window closes before the behaviour it names can
occur, it is measuring the harness.

### A feature is not finished because its model is correct — drive it before you call it done

**Three features shipped to the owner's iPad in one pass that could not be used at all**, and the owner
found all three in about a minute. Every one had a green fast tier, mutation-tested assertions, and a
worker report describing it as complete. The owner, afterwards:

> *"these bugs makes features unusable and thus unfinished, where as if I did not step in and test it, it
> would have gotten marked as fully done. Even a quick one minuite test could have found out these things."*

**The common cause is structural, not carelessness.** Every test in this repo reaches the model directly
and asserts a **stored value**. Not one asserted what is *drawn*, or whether an artist can *reach* the
feature. So the suite was blind to an entire class of defect by construction, and the more rigorous the
worker, the more confidently it reported done.

**Case 1 — a correct value drawn in the wrong place.** Dragging a node in the graph editor wrote the right
number and the node did not move. `Channel.axis` auto-ranges to the channel's own live key values, so with
**two** keys — the ordinary case, a Move at A and a Move at B — both are extremes and `t` is 0 and 1 *always*.
The axis rescales by exactly what the drag changed and the dot lands back under the finger. Every assertion
in the suite was on the value, and the value was never wrong.

**Case 2 — a feature whose only entry point requires state that only that entry point can create.** A fresh
transformation layer has an empty track; the graph editor lists only channels that carry a curve; the
channel-list row is the only thing that says Move is the verb. So you must Move to get a channel, and the
channel is the only thing that tells you to Move. The model was correct at every step and the loop was
closed nowhere. **Look for this shape specifically** — it is invisible to any test that starts by
constructing the state the artist cannot reach.

**Case 3 — a refusal with no notice.** `beginContainerPoseMove` returned false and its caller discarded the
`Bool`: no float, no highlight, nothing said. This file already has a section on that, reached by a new door.

So, in addition to the two-operands rule above, for any change with a visible surface:

1. **Drive it in the simulator and look at it.** Build, install, launch, perform the gesture, screenshot.
   This is available to agents and takes a minute. If you cannot, say so loudly rather than skipping it.
2. **Write a cold-start reachability test.** From a new document with no prior state, can the feature be
   reached? Constructing the post-state in a fixture and asserting on it is what let all three of these ship.
3. **Assert what is drawn or exposed, not only what is stored.** At least one assertion must fail if the
   affordance disappears while the model stays correct.
4. **Answer "what does the artist do next?"** at each step, in the report. If any step's answer is "read the
   source", the feature is unfinished.

**The bar is the orchestrator's to set, and this one was set wrong.** The briefs for all three asked for
round trips, cache keys, mutation tests and refutations, and got them. None asked whether a person could
use the result. Put these four in the brief, not in the reviewer's head.

### A static that writes through to `UserDefaults` outlives the test that set it

`CanvasManager.renderResolution` persists on every set, so it is process-wide **and survives into the
next run in the simulator container**. A suite that left it on `.half` produced **15 reds in a later fast
tier**, across `EffectLayerLogicTests` and `PerfBaselineTests`, every one a half-resolution artifact of a
*previous* run — reported, reasonably, as failures of the code under test. Pin it in `setUp` and restore
what was there in `tearDown`, exactly as suites already do for `Compositor.backend`. It is that same
restore rule reached through a door nobody had checked, and the persistence is what makes it worse: the
damage shows up in a *different* suite, on a *later* run, with nothing pointing back.

### The simulator subsystem degrades over a long session, and it looks like your code

MEASURED across one heavy session (2026-09-05, dozens of runs and several created/deleted devices), the
host's simulator daemons became unreliable in **two different disguises**, both of which read as a
finding and were not:

- **The shared device refused to bootstrap a test runner at all** — *"Early unexpected exit … Test
  crashed with signal kill before establishing connection"* — on every run, while the same test passed
  seconds later on a freshly created device. `simctl erase`, reboot and detaching the simulator panel
  did not fix it; a later `erase` did. The device kept launching and driving the app fine throughout;
  it was only the XCUITest runner that would not attach.
- **`backboardd`, `testmanagerd` and `SimRenderServer` crashed mid-run**, taking **8 tests** down with
  them across two unrelated suites. The tell is in the log — three `Restarting after unexpected exit,
  crash, or test timeout` blocks — and **no failing test emitted an assertion line**. A full re-run on a
  fresh device came back 0 failed.

**So a cluster of failures with no assertion messages is a sick host, not a broken change**, and the
cheap confirmation is a whole re-run on a **newly created** device rather than an isolated re-run of
each failure: isolation confirms one test, and what you want to know is whether the *run* was sound.
Creating and deleting a device costs about a minute and settles it.

### Triaging a failed XCUITest — do this before suspecting your change

A one-off XCUITest failure here is environmental far more often than it is real, and re-running the
full suite to check costs 22 minutes for an answer a 30-second run gives. **The isolated re-run is
the confirmation. Do not re-run the suite to decide whether a failure was real.**

```bash
xcrun simctl shutdown all; xcrun simctl erase 75C8B97E-47AF-484B-B7D2-CA7EB1B51B03
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination 'platform=iOS Simulator,id=75C8B97E-47AF-484B-B7D2-CA7EB1B51B03' \
  -only-testing:PaintSoftwareUITests/<Suite>/<test> \
  -parallel-testing-enabled NO -derivedDataPath build/DerivedData
```

**`<Suite>` is the test *class*, not the file it lives in, and for the classes you are most likely to
be triaging those two names are different.** The 2026-08-15 split that took the full suite from 25.7 to
18.8 minutes cut six heavy UI files into three classes each **without renaming the files**, so
`VectorShapeAndRecoveryUITests.swift` holds `GalleryRecoveryUITests` among others, `LayerUITests.swift`
holds `BlendModesAndCompositorUITests`, and `FillUITests.swift` holds `FillLiveAdjustUITests`. Deriving
the suite name from the filename produces a selector that matches nothing — and **that failure is
silent and reads as success**: `Executed 0 tests, with 0 failures` followed by `** TEST SUCCEEDED **`
and exit 0. It is the same trap as the banner-versus-count one above, reached by a different door, and
it cost a session one four-test triage run on 2026-08-27. Resolve the class from the source before
building the selector:

```bash
python3 -c "
import re,glob,sys
t=sys.argv[1]
for f in glob.glob('PaintSoftwareUITests/*.swift'):
    cls=None
    for line in open(f):
        m=re.match(r'\s*(?:final\s+)?class\s+(\w+)', line)
        if m: cls=m.group(1)
        if 'func '+t+'(' in line: print(cls, f)" <testName>
```

**`-parallel-testing-enabled NO` is not optional here**, and its absence is what the owner was
watching when they asked why running one test spawns three iPads: the scheme is parallelizable, so
xcodebuild clones the device even for a single test, and the clone boots are pure cost when there is
one class to distribute. Measured 2026-08-15, same test, twice: without the flag it ran on `Clone 1
of eraser-mutex-test`; with it, on `eraser-mutex-test` itself (the xcresult's `deviceId` is the UDID
above), and the string "Clone" appears nowhere in the run. **Do not change the scheme** — the full
suite is 18.8 min *because of* that setting.

If a run is killed mid-flight, sweep for strays before blaming the next failure on your change:

```bash
xcrun simctl --set ~/Library/Developer/XCTestDevices list devices          # clones live HERE
xcrun simctl --set ~/Library/Developer/XCTestDevices delete <udid>
```

**`xcrun simctl list devices | grep -i clone` finds nothing, ever** — the advice this file gave until
2026-08-16, and it cannot work: `xcodebuild` creates clones in its own device set at
`~/Library/Developer/XCTestDevices`, not the default one. The failure is silent and reads as success.
The owner was looking at eight iPad windows while three separate `simctl` sweeps and an agent's own
cleanup check all reported zero clones; the five it could not see were a live full-suite run, and the
sixth was a shutdown `Clone 3 of eraser-mutex-test` left by a killed run some time earlier. `--set` is
the whole fix, and it is needed on `delete` as well as `list`.

**A duplicated clone number is the tell for debris.** One healthy run numbers its clones 1..N once, so
two rows both named `Clone 1 of <device>` means one belongs to a run that died. If a run is live,
leave them alone — you cannot tell from the name which of the two is which, and deleting the wrong
one kills a suite mid-flight. Sweep after runs finish, not during.
A run that finishes normally tears its own clones down — both runs above left zero behind — so
anything this finds is debris from a run that did not.

**One simulator, many worktrees: check who else is on it before you erase it.** The multi-session
protocol at the top gives each session its own worktree but they all inherit the same UDID from this
file, and `simctl shutdown all` + `erase` is not scoped to the caller — it kills whatever another
session is running on that device *and* takes your own run down with it. It surfaces as
`Mach error -308 - (ipc/mig) server died` or `Invalid device state`, which reads exactly like a flaky
simulator and is not. Session 25 lost three runs to it before looking:

```bash
pgrep -fl xcodebuild                                   # another session's test run?
```
If one is live, either wait for it or take a device of your own and leave theirs alone:

```bash
UDID=$(xcrun simctl create "<slug>" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5) && xcrun simctl boot "$UDID"
# ... run with -destination "platform=iOS Simulator,id=$UDID" ...
xcrun simctl delete "$UDID"                            # when you are done
```

**Never kill by process name. `pgrep -f xcodebuild | xargs kill` is machine-wide, and it is the same
trap as the shared UDID and the shared stash wearing a third costume.** An agent sweeping for *its own*
strays on 2026-08-27 killed the orchestrator's verification run instead. The damage does not announce
itself as a kill: the first attempt died with **exit 144 and no xcodebuild output at all**, and the
retry produced **`Mach error -308 - (ipc/mig) server died` with `passedTests: 0`** — which is the
signature this file already attributes to *contention*, so it was diagnosed as a loaded machine and the
run was restarted into the same hazard. Two runs and a wrong diagnosis. Kill only PIDs you recorded when
you started the process, or `pkill -f "$PWD"` scoped to your own worktree path; and read a `-308` as
"someone touched my device", of which contention is only one cause.

**And `pgrep -f` does not count processes, it counts *substrings* — including its own caller.** A run
is a chain: the zsh wrapper, the `simlock.sh` bash, and the real binary all carry the string, so
`pgrep -f xcodebuild | wc -l` reads about **3x** the number of runs, and a `grep` for the pattern matches
the grep. On 2026-08-29 a worker built a wait gate on that count requiring it to reach **zero**, which it
never could — it was counting itself — and then attributed the load to a session whose worktree had been
merged and deleted an hour earlier, because it reused a stale `lsof` cwd read instead of re-taking it.
The same family as reading the banner instead of the count: **a proxy was measured and reported as the
thing.** Use `pgrep -x xcodebuild` for the count and an `lsof -a -p <pid> -d cwd` read, taken *now*, for
whose it is.

**Cleaning up after that is its own trap, and the obvious filter matches everything.** Protecting a live
run by walking a seed's ancestors *and then all of their descendants* protects the entire tree, because
every shell shares one Claude parent — measured at **962 processes protected out of 962**. The correct
set is the seed's ancestor **chain** plus the seed's own **subtree**: 13.

**Tell a worker how to wait, not just what to wait for.** Asked to hold until the machine was quiet, that
same worker polled — and queued each poll as a *background task*, leaving **78 shells** sleeping 1800 to
2700 seconds. They cost no CPU and fire a stale completion notification each, which reads as a stream of
finished work that has not happened. A brief that says "wait" should say **block on one wait; do not queue
timers**.

**A device of your own stops you erasing someone else's. It does not stop you starving the machine —
wrap every run in [tools/simlock.sh](tools/simlock.sh).**

```bash
tools/simlock.sh xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination "platform=iOS Simulator,id=$UDID" ... -parallel-testing-enabled NO
```

`pgrep` above is a check, not a lock, and it fails precisely when it matters: several sessions each
look, each see an idle machine, and all start at once. Measured 2026-08-16 with every session
correctly holding its own device — 8 cores, 5 booted simulators, 5 concurrent `xcodebuild` runs,
**1–3% idle**. At that load a suite does not merely run slowly, **it returns wrong answers**: the same
shape-hold test passed and failed on the same binary depending on contention, and an agent spent a
cycle tuning a timing constant against what was actually CPU starvation. That is the banner-vs-count
trap in a new costume — a red result that is evidence about the machine, not about the code.

`simlock.sh` holds one of `SIMLOCK_SLOTS` (default 2) for the life of the command, queues when they
are taken, and reclaims a slot whose owner died so one `^C` cannot wedge the machine for everyone
after. It needs no daemon and no cleanup. Raise the slot count only on a machine with more cores;
two is sized for this one, where the full suite already fans out to four clones of its own.

**The erase is right for a state flake and is the WORST case for a timing one**, and that asymmetry
cost a session an hour on 2026-09-05. A wall-clock assertion measured **43 ms** warm in the suite,
**95.8 ms** cold in-suite, and **207 ms** on the first run after a `simctl erase` — so the isolated
re-run this section prescribes failed **4.7× worse than the suite had**, and read as confirmation of a
real regression in a branch that had not touched the code being timed. The same test then passed 28/28
twice on a warm device. **So before erasing, ask what the failing assertion is about**: if it names a
duration, run it warm first and erase only if it still fails. Better, do not put a wall-clock assertion
in the fast tier at all — the bench files are excluded by filename and exist for exactly this.

Passes clean → environmental. Say so in the summary, name the test, and move on; it is not a
finding and does not need a fix. Fails clean → now it is yours, and you have a 30-second loop to
debug it in instead of a 22-minute one.

The erase is the whole trick: session 23 watched `testDroppingFolderOntoFolderNestsIt` fail twice
and pass three times, and the split was exactly whether the simulator had been erased first —
nothing to do with the code under test. Two of those five runs were spent bisecting against the
previous commit for a regression that did not exist.

**`uptime` is not a usable signal on this Mac** and earlier guidance to check it was wrong. Its load
average is a slowly-decaying artifact of simulator churn: it read 404, then 382, with zero booted
simulators, zero uninterruptible processes, and 94.6% idle CPU. Read the real number instead:

```bash
top -l 2 -n 0 -s 2 | grep "CPU usage" | tail -1
```

### A subagent's worktree is not yours to commit, and the tree you verified is not the tree you push

On 2026-08-28 an orchestrator watched a worker's test run finish, grepped its worktree, saw the change
was clean, and committed / merged / pushed it — **and deleted the worker's worktree and branch** while
the worker was still running. What it pushed contained `leaked.rotation += float.frame.boxAngle`, two
lines the worker had just written **on purpose**: it was mutation-testing its own new test, checking a
guard could actually catch the defect it guards against. `main` shipped with the exact bug the feature
exists to prevent, and the commit message said "it reaches no geometry at all". The worker recovered
its own work, reverted, and hardened — three commits where there should have been one.

Two separate mistakes, and the second is the interesting one.

**Do not act on a worker's tree before its completion notification arrives.** A finished *test run* is
not a finished *agent*; the run is one step, and the most dangerous edits come after it. There is a
notification for this and it is the only signal that means what you want.

**And a green check is evidence about the tree that existed when you ran it.** This file already warns
that a *red* xcresult is evidence about a binary rather than about your working tree. The same hazard
runs the other way and nothing warned about that: the grep was true when it ran and false four minutes
later, because someone else was still typing. Verification and commit must be the same instant on the
same bytes — `git show <sha>:<path>` after the fact, not a grep before it.

**The general rule, because mutation testing is not the only way to lose here:** a worker's working
tree is a *workbench*, not a deliverable. It legitimately holds half-finished edits, deliberate
poison, scratch harnesses and debug printf. Only the worker knows which bytes are the product. Harvest
its *commits*, or wait for it to say it is done. If you are the worker: **commit first and mutate
second**, or mutate in a throwaway copy outside any worktree, because a mutation on disk is
indistinguishable from the implementation to anyone who picks that tree up.

### `git stash` is per-repository, not per-worktree

An agent working in `../PaintApp-<id>` used `git stash push`/`pop` to park its edits between test runs, and the
`pop` landed **`stash@{0}` from a completely different session** — "Abandoned vector-interpolation index
snapshot, 134 commits behind origin/main" — into its tree as ~45 conflicted files. Nothing was lost (both stash
entries survived, and the agent reset to its branch tip and re-applied its own changes), but the recovery cost a
cycle and it could as easily have been committed by an agent that did not look.

The stash is a single stack on the repository. Every worktree shares it, and `pop` takes whatever is on top
regardless of which worktree pushed it. **Do not use `git stash` in this repo at all.** To park work, commit it
on your own `tmp/<id>` branch — a commit you amend or reset later is free, and it cannot be picked up by anyone
else. This is the same class of hazard as the shared simulator UDID above: a tool that looks per-session and is
actually machine-wide.

### `origin/main` is a shared ref, so `git reset --hard/--mixed origin/main` is not a stable target

Any session's `git fetch` updates the *repository's* `origin/main`, including sessions in other
worktrees. An agent that reset to it mid-task on 2026-09-02 found it had moved under them and staged a
revert of all nine files another session had just merged — caught in `git status`, nothing lost, but it
would have been an invisible revert inside an otherwise ordinary commit. Reset to a **recorded sha**
you took yourself, or to your own branch tip, never to a name that another process can repoint. Same
family as the shared stash above and the shared simulator UDID.

### Two branches can mint the same pbxproj object id, and git will merge them happily

The app target auto-includes sources via `PBXFileSystemSynchronizedRootGroup`, but **the UI-test
target has an explicit `PBXSourcesBuildPhase`**, so a new *test* file must be added to
`project.pbxproj` by hand.

**And so must the app file it tests, which is a second entry pair nobody expects.** A logic test in
`PaintSoftwareUITests` cannot reach app types by `@testable import`, so any app source a logic test
touches is compiled into the test target *a second time* and needs its own `PBXFileReference` plus
`PBXBuildFile` — see `Effect.swift`, `InterpolationRecipe.swift`, `ShapeHoldClock.swift` and
`AnimationCurve.swift`, all listed by full path rather than by bare filename. **So a new type plus its
logic test is four object ids, not two**, and a check that looks up a bare filename finds nothing and
reads as a missing entry when the entry is there under its path. Two branches each adding one therefore each invent an object id — and on
2026-08-16 two of them independently invented the *same* pair,
`B2C3D4E5F6001122334455F1`/`F2`, one for `StrokeSampleGate.swift` and one for `ShapeHoldClock.swift`.

Git merged that without a conflict, because the two definitions are on different lines. Xcode then
resolves a duplicate id to whichever definition comes later, which **silently dropped
`StrokeSampleGate.swift` from the test target**. The build failed with `cannot find
'StrokeSampleGate' in scope` in a test file nobody on either branch had touched — an error pointing
at neither change, on a merge git reported as clean.

Before adding a pbxproj entry, check the id is not already taken, and prefer one derived from the
file name over a hand-typed sequence:

**Do not take the next sequential id off a neighbouring entry** — that is what makes two branches
collide, since both are counting from the same base. After any rebase that touches `project.pbxproj`,
check for duplicates:

```bash
python3 -c "
import re,collections
src=open('PaintSoftware.xcodeproj/project.pbxproj').read()
defs=re.findall(r'^\t\t([0-9A-F]{24}) /\* (.*?) \*/ = \{isa = (\w+)', src, re.M)
c=collections.Counter(d[0] for d in defs)
print([k for k,v in c.items() if v>1])"      # must print []
```
If a merge produces a "cannot find X in scope" for a symbol neither branch touched, suspect this
before suspecting the code. It is the same family as the `@discardableResult` merge in
[BUGS.md](BUGS.md): two changes to different lines that compose into a defect neither had alone.

## Deploy to iPad

```bash
source ~/.config/paintapp/.env      # KEYCHAIN_PASSWORD, SIGNING_IDENTITY, PROJECT_DIR, PROJECT_FILE, SCHEME
security unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db
xcodebuild build -project PaintSoftware.xcodeproj -scheme PaintSoftware -configuration Release \
  -destination "generic/platform=iOS" -allowProvisioningUpdates -derivedDataPath build/DerivedData
xcrun devicectl device install app --device E3B83820-DF74-5042-B52B-0D5BA17E4877 <path>.app
```
The scheme's LaunchAction stays Debug (Xcode's Run button is for development); `-configuration
Release` above is what makes the shipped build the one that's actually optimised — Debug measured
62x slower than Release on the alpha-mask render path. `~/PaintApp/deploy/deploy.sh` does this but
**pulls `main` first**, so it never ships branch work — run the steps above from the worktree
instead. The first `install` often fails with `NWError 54`; just re-run it. **`CoreDeviceError 1011` — "unable to locate a device matching the requested device
identifier" — has two causes, and `devicectl list devices` tells them apart. Always run it first.**
- **`available (paired)`** → a stale tunnel, not a missing iPad. `xcrun devicectl device info details
  --device <UUID>` re-establishes it (watch `lastConnectionDate` move) and the next `install`
  succeeds; retrying `install` alone does not, so it reads like a dead device and is not one.
- **`unavailable`** → the iPad really is unreachable: asleep, locked, or off the network. `info
  details` still answers from cache with a *stale* `lastConnectionDate`, so it looks like it worked
  and the install fails anyway. Nothing on this Mac fixes it — the owner has to wake the device. Say
  so rather than retrying; three attempts cost a minute and prove nothing. Never pass the device by
name (`devicectl`'s columns shift on the space in "Kevin's iPad") — use the UUID above.

Auto-resign for the 7-day free-account cert: `/Library/LaunchDaemons/com.paintapp.resign.plist`
(daily 3:05 AM as root, resigns every 5 days). Log: `~/.config/paintapp/resign.log`.

Simulator testing runs locally too — the Tailscale/SSH `deploy/mac/*` scripts are for the Windows
machine, not this Mac.

## Action recorder — get the bug off the owner's iPad instead of guessing at a simulator

The owner can reproduce a device-only bug in four seconds; an agent poking a simulator cannot
reproduce it at all. `PaintSoftware/Debug/ActionRecorder.swift` turns those four seconds into one
greppable JSONL file. **Reach for it before spending runs trying to reproduce something the owner
saw and you can't** — the fill-tool gesture bug in [BUGS.md](BUGS.md) is exactly that shape.

**Turning it on**: Actions menu → **"Record My Actions"**, in its own section just below the
pencil-only toggle. Reproduce the bug, then **"Stop Recording"**. Off by default and free when off — the
`UIWindow.sendEvent` interception is *uninstalled* on stop, not merely flag-checked, so the drawing
path pays one static `Bool` load per hook site and nothing else.

**Where recordings land**: `Documents/Recordings/recording-yyyyMMdd-HHmmss.jsonl`, inside the app
container. The Actions menu lists them with Share and Delete, so the owner can AirDrop one straight
out. To pull one over the cable instead:

```bash
xcrun devicectl device copy from --device E3B83820-DF74-5042-B52B-0D5BA17E4877 \
  --domain-type appDataContainer --domain-identifier Starg.PaintSoftware \
  --source "Documents/Recordings/<file>" --destination ./
```

**What is in it**: every touch with its pencil-vs-finger type and hit-test target, every gesture
recognizer state transition, every answer `shouldRequireFailureOf` gave and who it named, model
changes and canvas transforms — all on one clock, so cause sits beside effect.

**Its one real limitation, and it is not a missing identifier in the app.** A tap on SwiftUI chrome
records its *position* but not the control's identifier (`"target": null`), because **iOS only builds
SwiftUI's accessibility identities when an accessibility client is attached to the process** — which
there isn't, on the owner's own iPad. Canvas and timeline touches are UIKit and record fully. When you
read a file full of nulls: the `hitClass` and the `model` line just after the touch usually name what
was tapped, and the emitted window-normalised coordinate still replays. Record with an XCUITest runner
attached if you need every element named. `WindowEventTap.resolveTarget`'s doc comment carries the
measurement.

`tools/recording2xcuitest.py <file>.jsonl` turns a recording into a **draft** XCUITest — the tedious
90% (which element, what order, how far apart), not something that compiles untouched. It refuses to
downgrade a pencil touch to a finger, because XCUITest cannot synthesise a pencil at all and a quiet
downgrade would give a green test for a broken app.

## graphify

Prefer over raw grep for orienting.
```bash
graphify update .              # refresh (AST-only, no API cost) — after code changes
graphify query "<question>" ; graphify path "<A>" "<B>" ; graphify explain "<concept>"
```
[graphify-out/GRAPH_REPORT.md](graphify-out/GRAPH_REPORT.md) is tracked; `graph.json`/`graph.html`
and dated snapshot folders are gitignored blobs. Commit a refreshed report when you refresh the
graph. A `PreToolUse` hook ([.claude/hooks/graphify-guard.sh](.claude/hooks/graphify-guard.sh))
nudges toward it; it resolves `graphify` from PATH and fails open if missing.

## Docs

[HANDOFF.md](HANDOFF.md) is **both the state of the repo and the prompt that starts the next
session** — its first section is the block to paste. It used to be two files, HANDOFF.md and
nextprompt.md, and they drifted apart inside a single day because the same state had to be written
twice. Keep it one file. Rewrite the paste block when you close a pass; do not append to it.

[TODO.md](TODO.md) is **the owner's asks, live** — record them there when they arrive and delete them
when they are done and merged, not when a branch exists. It is the counterpart to [BUGS.md](BUGS.md),
which is for what *we* find. **At most three items in flight at once**, unless the extras need no
simulator; the cap is about the machine, not the plan (see `tools/simlock.sh` and what five concurrent
runs did to this Mac).

[TODO.md](TODO.md)'s **"Later"** section holds the long-term features — items (26)-(28) and (30).
**Each needs a design conversation with the owner before it starts**, and an item built from its TODO
entry alone was built wrong.

[RENDER.md](RENDER.md) is the rendering specification — TODO item (29), the background baker that replaces live main-thread compositing, the on-disk frame store, and export. **Its §2 is sixteen owner rulings; read them rather than re-deriving them.** The knob is the truth (§2.12): a frame whose textures do not fit the budget is composited in **horizontal strips** at full size (§3.8, `Engine/StripedComposite.swift`) and never at a smaller one — `CompositorBudget.affordableSize` is deleted. **§3.8 carries the trap that reaches past this feature: three memos — `PixelOps.RasterizeKey`, `MaskResolver.CacheKey` and `MetalCompositor`'s `UploadCache.Key` — are keyed on the buffer's *size*, so any future work that composites the same content into two equally sized buffers collides on one entry and gets the first one's pixels, silently.** The third of those has no CoreGraphics counterpart and was found only by running the byte-for-byte pin on the second backend.
[KEYFRAMES.md](KEYFRAMES.md) is the keyframe-animation specification — TODO item (21), designed 2026-08-28. **Its §2 is twenty-eight owner rulings; read them rather than re-deriving them, and §8 is the build order.** Four of them (§2.1, §2.23, §2.24 and §2.28's closing rule) are **superseded and kept**: the owner reversed their own Animate-mode ruling on 2026-08-29 and §2.26/§2.27 replaced it with the keyframe-mark workflow — a keyframe is a bare mark in time, an edit between two marks holds its previous value, and the *next* mark commits it. §2.28 then settles what "a keyframe" *is* against the model: the **union** of the explicit marks and every frame a channel keys on, computed by one accessor and never stored twice — three device reports were the same divergence between those two lists, and **the third one found that §2.28's own closing rule was the cause**: it let a mark and a key both live at one frame, the graph editor could not repair that, and a dragged node left its mark behind as an indicator with no node. A mark a key lands on is dropped now. `keyframeMarks` itself cannot go — it is the only storage for §2.26's first step. The three that shape everything else: a transform key stores a **quad** from day one so Distort lands later with no migration; posed ink is drawn by **baking the dab walk in rest space** and mapping dab centres per frame, which removes the shimmer *and* the per-sample-width problem together; and **bake is an authoring feature, never a performance instruction** — smooth playback comes from a disk-backed frame cache, which is RENDER.md §3.5-3.7's store rather than §4.6's span-scoped design and is merged. **Stages 4 and 5 are both merged.** `PixelOps.RasterizeKey` and `LayerContentVersion` both carry `DerivedCelContent.identity`, so a posed frame cannot composite from a stale un-posed image; and the rest-space dab bake removed the grain boil, so the test that pinned that artefact is retired rather than red. **§2.16's Move half stays declined** and belongs to the brush overhaul, TODO (37). What remains of (21) is stages 5b, 6, 7, 8 and 10.
[EFFECT_BACKDROP.md](EFFECT_BACKDROP.md) is the specification for what an adjustment layer grades — the canvas paper is a `UIView` painted *behind* the composite, so every effect and blend mode is masked to the artist's own ink. **Fully ruled 2026-08-27; §6 is the build order and §2 is the two consequences that are inherent rather than incidental**: an effect that grades the paper makes the composite opaque, which is why the Behind onion skin moves above it in z-order; and filling paper into the accumulator destroys the alpha that Outline, Sobel and Bloom read as shape, which is what the ink-only input exists for. **Bloom and Sobel each get an artist-facing choice of input — Sobel's new default changes how it looks in existing documents.**
[LASSO_FILL.md](LASSO_FILL.md) is the lasso fill specification — the algorithm, its name in the literature, the edge cases decided, and what shipped applications do.
[LASSO_MOVE.md](LASSO_MOVE.md) is the lasso *move* specification — splitting strokes and fills at the selection boundary so only what is inside travels, and how much of it the vector eraser and the raster floating piece already built. **Its §5 is twenty-six owner rulings settled across five dates between 2026-08-21 and 2026-08-29; do not re-litigate any of them.** That count was "six" here until 2026-08-28 and had been stale for a week, which is worth knowing because this line is what a session reads *instead of* the file — and it went stale again within the day, at §5.22, and again at §5.24 and §5.25 later the same day, which is the argument for reading §5 rather than this sentence. The load-bearing ones: a lasso move moves **only what is inside the loop** (Move with no selection still moves the whole cel, which is correct as it stands); a split stroke becomes **two independent strokes**; selection is **by the centre line**, knowingly, so a thick stroke whose spine is outside the loop does not move; undo is **one step per nudge**, which covers the whole-layer transform too; the lassoed part **floats with move nodes and bakes on commit**, which is `FloatingPiece`'s existing lifecycle; a Freeform stretch scales ink by **`sqrt(|det|)`**, the map's area root, so the stretch arm reduces to the similarity arm exactly at `aspect == 1`; §5.19-21: the Move box **stays axis-aligned** with no automatic tilt, a stretch made about a hand-turned box **records the axis it was made about** (which completes the box's transform to a general affine rather than extending it), and turning the box **costs no undo step** — a deliberate exception to §5.5, not an amendment to it; and §5.23-24, the newest: in the Touching and Enclosed membership modes text and placed images follow the mode via their own quad rather than the centre rule, which stays for Cut, choosing Enclosed and catching nothing says so, unlike §5.9's silent empty lasso, because there the paper was blank and here the rule excluded a loop full of ink; and §5.25, that under Cut **Clear cuts at the loop** like the raster arm and like the fills it already cut, rather than deleting every element the loop touches; and §5.26, that **membership belongs to the selection rather than to Move** — the picker lives in the Select panel and **all three consumers obey it with no exception, Move and Recolour and Clear** (which supersedes §5.25's fixing of Clear on Cut), and the owner's word *"enclosed"* in that ask means the mode the app calls **Cut**, the only one that splits.
[CANVAS_RESIZE.md](CANVAS_RESIZE.md) is the canvas-resize specification — TODO item (9), the crop/expand and scale-to-fit modes, and the arithmetic of the letterbox map. **Read its §0 before touching anything on that path: `setCanvasPadding` is already a whole-document crop/expand and `VectorCanvas.mapping(_:throughSimilarity:)` is already the exact vector scaler, so the feature is mostly joining two things that exist.** Its §2 lays out the coupling to TODO item (8) with the cost of each option and **recommends** — not rules — that the fixed-point coordinate width be a property of the *format* rather than of the canvas extent, so that a resize re-encodes nothing; §6 is answered in full (2026-08-28).
[LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) is the ruling on `VectorCanvas._transform` — whether a vector cel should carry an affine at all, or store every object in canvas coordinates. **Verdict: adopt, with changes** — eleven of its sixteen entry points invert it away again, and it carries three unfiled defects (ink drawn on a shrunk cel is clipped away, a scaled-up cel is a bitmap magnify, and interpolation drops the transform entirely). Its §6 is the honest answer to the bit-width question that started it: **the ruling buys no bits.** That §6 once concluded "(8)'s settled 24 stays 24" and this line repeated it; both are stale. 24 was the live decision for four minutes on 2026-08-26 before `35b541c` settled **16 bits an axis**, and §6 carries its own correction. The stale text was this line.
[README.md](README.md) is the app and its architecture. [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md)
is the interpolation feature — settled decisions and the future-upgrade list. [BUGS.md](BUGS.md) is
open issues only. [PERFORMANCE.md](PERFORMANCE.md) is the ranked optimisation programme, the work
ruled *not* worth doing, and every figure's provenance — read it before optimising anything, and
label any number you add MEASURED or INFERRED. [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) and
[REFACTOR_BASELINE.md](REFACTOR_BASELINE.md) are reference. Keep them short: prune what is done
rather than appending status.
