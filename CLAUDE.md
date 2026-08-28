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

**The floor is now one test**: `InterpolationWorkflowUITests.testInterpolateModeEndToEndFromGestureToScrub`
is 189 s and sits alone in its own class precisely so it starts immediately. Going meaningfully below
~3 min means decomposing that one test, not splitting further.

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

- **A red xcresult is evidence about a *binary*, not about your working tree** — the same trap as the
  banner, pointing the other way. `test-without-building` reuses whatever bundle was last compiled,
  so editing a source file and re-running it tests the *old* code while reporting against the new
  commit. Session 24 spent an opus worker "fixing" three effects that were already correct: a Sobel
  divisor of 4 had been changed to `1/√20` before the commit, but the failing run predated the
  rebuild, and every reported byte (128 where 114 was wanted, 90 where 81 was) is exactly the ratio
  `√20/4 = 1.118` between the two constants. Before debugging a numeric failure, diff the constant
  the test names against the value it reports — that is thirty seconds and it settles which of the
  two you are looking at. Use plain `test` (which builds) unless you have a reason not to.

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

### Two branches can mint the same pbxproj object id, and git will merge them happily

The app target auto-includes sources via `PBXFileSystemSynchronizedRootGroup`, but **the UI-test
target has an explicit `PBXSourcesBuildPhase`**, so a new *test* file must be added to
`project.pbxproj` by hand. Two branches each adding one therefore each invent an object id — and on
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

[ROADMAP.md](ROADMAP.md) is **what comes after TODO.md** — the owner's six long-term features, given
unprompted on 2026-08-28 so that architecture decided now is not decided blind, quoted verbatim and
mapped onto the seam each one already has in this tree. **Nothing in it is designed, and every item ends
with the conversation it needs**, because the owner asked to be prompted before any of them is built.
Read it before a decision that would be expensive to reverse. Three of its findings are why it exists:
keyframes are further along than they sound — `SpacingCurve` already *is* arbitrary easing and `fps` is
already persisted with only its UI missing; **a video element inherits whatever Move stage 3c decides
about `VectorImageElement.transform`**, which is the one live coupling to today's list; and **export
does not exist in any form**, so item (5) is greenfield and its real blocker is that `makeRenderRequest`
drops interpolated in-betweens. It also rescues the "transformation layer" future shape out of
`SESSION_LOG.md`'s Session 70 entry, which is the oldest of the five the log keeps and rolls off next.

[EFFECT_BACKDROP.md](EFFECT_BACKDROP.md) is the specification for what an adjustment layer grades — the canvas paper is a `UIView` painted *behind* the composite, so every effect and blend mode is masked to the artist's own ink. **Fully ruled 2026-08-27; §6 is the build order and §2 is the two consequences that are inherent rather than incidental**: an effect that grades the paper makes the composite opaque, which is why the Behind onion skin moves above it in z-order; and filling paper into the accumulator destroys the alpha that Outline, Sobel and Bloom read as shape, which is what the ink-only input exists for. **Bloom and Sobel each get an artist-facing choice of input — Sobel's new default changes how it looks in existing documents.**
[LASSO_FILL.md](LASSO_FILL.md) is the lasso fill specification — the algorithm, its name in the literature, the edge cases decided, and what shipped applications do.
[LASSO_MOVE.md](LASSO_MOVE.md) is the lasso *move* specification — splitting strokes and fills at the selection boundary so only what is inside travels, and how much of it the vector eraser and the raster floating piece already built. **Its §5 is twenty-five owner rulings settled across four dates between 2026-08-21 and 2026-08-28; do not re-litigate any of them.** That count was "six" here until 2026-08-28 and had been stale for a week, which is worth knowing because this line is what a session reads *instead of* the file — and it went stale again within the day, at §5.22, and again at §5.24 and §5.25 later the same day, which is the argument for reading §5 rather than this sentence. The load-bearing ones: a lasso move moves **only what is inside the loop** (Move with no selection still moves the whole cel, which is correct as it stands); a split stroke becomes **two independent strokes**; selection is **by the centre line**, knowingly, so a thick stroke whose spine is outside the loop does not move; undo is **one step per nudge**, which covers the whole-layer transform too; the lassoed part **floats with move nodes and bakes on commit**, which is `FloatingPiece`'s existing lifecycle; a Freeform stretch scales ink by **`sqrt(|det|)`**, the map's area root, so the stretch arm reduces to the similarity arm exactly at `aspect == 1`; §5.19-21: the Move box **stays axis-aligned** with no automatic tilt, a stretch made about a hand-turned box **records the axis it was made about** (which completes the box's transform to a general affine rather than extending it), and turning the box **costs no undo step** — a deliberate exception to §5.5, not an amendment to it; and §5.23-24, the newest: in the Touching and Enclosed membership modes text and placed images follow the mode via their own quad rather than the centre rule, which stays for Cut, choosing Enclosed and catching nothing says so, unlike §5.9's silent empty lasso, because there the paper was blank and here the rule excluded a loop full of ink; and §5.25, that **Clear cuts at the loop** like the raster arm and like the fills it already cut, rather than deleting every element the loop touches.
[CANVAS_RESIZE.md](CANVAS_RESIZE.md) is the canvas-resize specification — TODO item (9), the crop/expand and scale-to-fit modes, and the arithmetic of the letterbox map. **Read its §0 before touching anything on that path: `setCanvasPadding` is already a whole-document crop/expand and `VectorCanvas.mapping(_:throughSimilarity:)` is already the exact vector scaler, so the feature is mostly joining two things that exist.** Its §2 lays out the coupling to TODO item (8) with the cost of each option and **recommends** — not rules — that the fixed-point coordinate width be a property of the *format* rather than of the canvas extent, so that a resize re-encodes nothing; §6 is answered in full (2026-08-28).
[LAYER_TRANSFORM.md](LAYER_TRANSFORM.md) is the ruling on `VectorCanvas._transform` — whether a vector cel should carry an affine at all, or store every object in canvas coordinates. **Verdict: adopt, with changes** — eleven of its sixteen entry points invert it away again, and it carries three unfiled defects (ink drawn on a shrunk cel is clipped away, a scaled-up cel is a bitmap magnify, and interpolation drops the transform entirely). Its §6 is the honest answer to the bit-width question that started it: **the ruling buys no bits.** That §6 once concluded "(8)'s settled 24 stays 24" and this line repeated it; both are stale. 24 was the live decision for four minutes on 2026-08-26 before `35b541c` settled **16 bits an axis**, and §6 carries its own correction. The stale text was this line.
[README.md](README.md) is the app and its architecture. [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md)
is the interpolation feature — settled decisions and the future-upgrade list. [BUGS.md](BUGS.md) is
open issues only. [PERFORMANCE.md](PERFORMANCE.md) is the ranked optimisation programme, the work
ruled *not* worth doing, and every figure's provenance — read it before optimising anything, and
label any number you add MEASURED or INFERRED. [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) and
[REFACTOR_BASELINE.md](REFACTOR_BASELINE.md) are reference. Keep them short: prune what is done
rather than appending status.
