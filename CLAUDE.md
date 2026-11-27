**Every agent starts at [AGENTS.md](AGENTS.md)** — the read order, the owner's working agreements, the
standing engineering rules and the bar for done, tool-neutral. This file is the build, test, merge and
deploy detail; it binds every agent, not only Claude Code.

# Multi-Session Protocol

Multiple sessions work this repo concurrently, each in its own worktree. Never edit `main` directly.
Assume the tree has moved — `git fetch` before trusting what you remember.

```bash
git fetch origin
git worktree add ../PaintApp-<id> -b tmp/<id> origin/main   # <id> = short descriptive slug
```

Finish and merge (build/test first, or say you couldn't):

```bash
git fetch origin && git rebase origin/main
M=/Users/juliapark/Desktop/Kevin.P/PaintSoftware   # the main worktree; never merge from your own
git -C "$M" merge --ff-only tmp/<id> && git -C "$M" push origin main
git -C "$M" worktree remove ~/PaintWork/PaintApp-<id> && git -C "$M" branch -d tmp/<id>
```
If `--ff-only` fails, rebase again — don't force-push, don't merge-commit. Append one line to
[SESSION_LOG.md](SESSION_LOG.md): `Session N — YYYY-MM-DD: <what changed>`, and drop the oldest so only
the last five remain.

**Real time is a requirement (owner, 2026-11-17).** Every piece of work follows
[docs/SCHEDULER.md](docs/SCHEDULER.md): main never waits and never does canvas-sized work, a touch
outranks everything, stale work is cancelled. A change that breaks a rule there is not done.

**Machine-independent is a requirement (owner, 2026-11-25).** The iPad 9 is the minimum spec, never the
design target: read limits from the machine. See AGENTS.md's standing engineering rules.

## Build and test

**Build from a worktree outside `~/Desktop`.** `actool` cannot read the Desktop folder on macOS 26.5.2
(*"currentDirectoryPath is unexpectedly nil … Operation not permitted"*, `BUILD FAILED` before a line
compiles). Until the owner grants Xcode access (Privacy & Security → Files and Folders / Full Disk
Access), make worktrees under `~/PaintWork/PaintApp-<id>`; merges still run from the main worktree, which
needs no build. Bash tool calls that run `xcodebuild` need the sandbox disabled.

Xcode is at `/Applications/Xcode.app`; `xcodebuild`/`xcrun` are on PATH. Metal shaders need the toolchain
once: `xcodebuild -downloadComponent MetalToolchain`.

**Keep storage lean — delete, do not archive (owner, 2026-11-17).** When a task merges, delete its
worktree, branch, simulator and any evidence, xcresults, logs and device builds it no longer needs; no
archive bundles — `git log` and origin are the history. Keep only what an open TODO item cites, and the one
installed device build `resign_state` names. Evidence goes in one folder per task under `~/PaintWork`
(never loose files in its root), deleted when the item closes. Never touch the owner's artwork, the iPad,
or another live session's worktree or simulator. Aim for 10 GiB free; stop starting runs below 5 GiB.

### Tiers

- **Fast tier (~14 min Debug, ~8 min Release, ~4800 tests)** — the headless `*LogicTests`. Use constantly.
- **Full run (~76 min, 5438 tests, 363 classes)** — XCUITests are 99% of it. Phase boundaries only;
  `simctl shutdown all` + `erase` immediately before (leftover clones cause nearly every mystery failure),
  then `tools/stage-photo-tip.sh <udid>` (the BrushMenu photo-tip test needs its bar as the newest Photos
  item). Run the UI suite on an iPad (9th generation) simulator — the owner's 1080×810 premises fail on the
  13" one.
- Parallel work is distributed per test *class*; the constraint is ideal work per clone (class-seconds ÷ 4),
  not the longest class, and over-splitting costs setup per class. Balance splits on measured seconds,
  never below one test; verify a split by xcresult test count; **pull the per-class table right after a
  full run** (later runs on that `-derivedDataPath` evict the xcresult).
- **Before reading a full run's wall clock**, check `System Failures` in the xcresult and count distinct
  `Clone N of …` in the log: a clone can fail to bootstrap and the banner will not say. A busy machine
  inflates wall clock too.
- **No wall-clock assertions in a four-clone run or the fast tier.** The full suite runs bench files, so
  gate a bench's assertion on an env-var opt-in (`BrushContactSheetBench`, `DabCostBench`'s
  `PAINTAPP_PADCAP`) and print the measurement unconditionally; take four samples before adding headroom or
  naming a cause. Triage a timing failure **warm**, never straight after an erase (4.7× worse).
- **`tearDown` runs even when `setUpWithError` throws `XCTSkip`**: gate an opt-in suite's teardown on a flag
  set past the guard.
- **Some class names differ from their file names** (silently breaking `-only-testing`):
  `SandwichCompositingUITests` and `BlendModesAndCompositorUITests` are in `LayerUITests.swift`,
  `InterpolationWorkflowUITests` in `TimelineAndUndoUITests.swift`, `GalleryRecoveryUITests` in
  `VectorShapeAndRecoveryUITests.swift`, `FillLiveAdjustUITests` in `FillUITests.swift`. Resolve the class
  from the source (snippet below). `InterpolationWorkflowUITests.testInterpolateModeEndToEndFromGestureToScrub`
  (~150 s) goes red under clones and passes alone: environmental until an isolated run says otherwise.

### Simulators, runs and reading results

- Dedicated simulator by UDID: `eraser-mutex-test`, `75C8B97E-47AF-484B-B7D2-CA7EB1B51B03`.
  `-destination name=...` for a device this Mac lacks does **not** error — xcodebuild silently falls back
  (there is no "iPad Pro 13-inch (M4)"; it is an M5).
- `Engine/Deform` compiles standalone with `swiftc` (~5 s a loop) — test engine hypotheses there instead of
  a 90 s `xcodebuild test`.
- **`** TEST SUCCEEDED **` and exit 0 do not mean any test ran, and the log is not the count.** Read the
  count from the xcresult, and reconcile it against a static `func test` count:

  ```bash
  xcrun xcresulttool get test-results summary --path "$(ls -dt build/DerivedData/Logs/Test/*.xcresult | head -1)"
  ```
  `totalTestCount: 0` with `result: "unknown"` is what a malformed `-only-testing` produces. **zsh does not
  word-split unquoted `$VAR`** — build selector lists as an array and pass `"${SUITES[@]}"`. The log's
  per-test line differs serial (`Test Case '-[Suite testName]' passed`) from parallel
  (`Test case 'Suite.testName()' passed on 'Clone 1 of …'`), and parallel lines interleave, so a grep
  count is wrong either way. The whole fast tier, verbatim:

  ```bash
  SUITES=(); for s in $(ls PaintSoftwareUITests/*.swift | xargs -n1 basename | sed 's/\.swift$//' | grep -E "LogicTests$|CharacterizationTests$|^PerfBaselineTests$"); do SUITES+=(-only-testing:PaintSoftwareUITests/$s); done
  xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
    -destination 'platform=iOS Simulator,id=75C8B97E-47AF-484B-B7D2-CA7EB1B51B03' \
    "${SUITES[@]}" -parallel-testing-enabled NO -derivedDataPath build/DerivedData
  ```
  Selectors come from *filenames*: a hand-rebuilt filter that drops `PerfBaselineTests` (the timing
  suite, 53 tests) is blind to performance regressions, and a class in a file of another name never runs.
  Keep one `XCTestCase` per file named after the file.
- **The fast tier runs no XCUITest**, so a branch can be green in Debug *and* Release and still broken
  (persistence tests, `RecordingUITests`). Say in the summary that the UI tier was not run. Cheap checks:

  ```bash
  tools/check-ui-identifiers.py     # no UI test may reach a control by its SF Symbol glyph name
  tools/check-ui-helpers.py         # no UI test may define a helper whose name PaintUITestCase already defines
  ```
  An explicit `accessibilityIdentifier` **replaces** SwiftUI's implicit glyph-derived one, so a glyph name
  is not an identifier the app promises. Give every `XCTAssertTrue` in a shared helper a message (a bare
  `XCTAssertTrue failed` names neither element nor reason).
- **Never write `@testable import PaintSoftware` in `PaintSoftwareUITests`.** It resolves nothing (every
  app source a logic test touches is compiled into that target a second time) and **breaks
  `-configuration Release`** (`ENABLE_TESTABILITY` is Debug-only). **Take a Release fast tier before
  merging anything that adds a test file.**
- **`-parallel-testing-enabled NO` on every run that is not the full suite.** The scheme carries
  `parallelizable = "YES"` (PaintSoftware.xcscheme:48), which is correct for the full run — do not change
  the scheme; clone boots are pure cost for a few classes.
- **A red xcresult is evidence about a binary, not your tree**: `test-without-building` reuses the last
  bundle. Use plain `test` unless you have a reason, and diff the constant a failing test names against the
  value it reports. **The simulator you drive is a binary too** — `simctl install` ships whatever
  `build/DerivedData/.../*.app` last holds (including a mutation run): rebuild between a mutation run and a
  drive, and when a drive contradicts a green test suspect the bundle first.

### A green assertion is only as good as its two operands

- Mutate one fixture cumulatively; a fresh fixture per table row compares allocation addresses
  (`LayerContentVersion` names tiers by `ObjectIdentifier`).
- `Layer.layerEffect` is `kind.carriesEffect ? effect : nil` (value and vector layers only) and
  `Layer.valueFill` is `kind == .value && effect == nil ? fill : nil`; render reads the accessor, so setting
  the field on another kind measures nothing.
- An assertion true by mathematics (noise differs between positions) cannot go red — assert at the pixels.
  Ask: **if this went red, would the code be wrong?** (the hold lives in `AnimationCurve`/`TransformTrack`,
  not `PoseInterpolation.blend`.)
- A cel spanning frames is one bake key — give each frame its own picture. `CompositeProbe` counts
  chunks, not frames. An `XCTNSPredicateExpectation` cannot fire during XCUITest's synchronous drag, so its
  inverted twin passes unconditionally.
- **A harness can take a different path from the artist**: a stroke's ink lands in place, `@Published
  layers` never moves, and `reconcileLayers` (sole caller of `syncFrameBake`, `updateSandwich`,
  `updateOnionSkin`, `updateInterpolationPreviews`) must be triggered by the stroke lift;
  `PlaybackProbe.commitStroke` sends its own `objectWillChange` and hid a lost publish. Check that a probe
  enters the changed path (PERFORMANCE.md §17.1).

### A feature is not finished because its model is correct — drive it

Features have shipped unusable with a green fast tier because every test asserted a stored value
(a correct value drawn in the wrong place; a feature whose only entry needs state only it creates; a
refusal with no notice). For any change with a visible surface:

1. **Drive it in the simulator and look at it**: build, install, launch, perform the gesture, screenshot.
   If you cannot, say so loudly.
2. **Write a cold-start reachability test**: from a new document with no prior state, can the feature be
   reached? Constructing the post-state in a fixture is what let these ship.
3. **Assert what is drawn or exposed**, not only what is stored — at least one assertion must fail if the
   affordance disappears while the model stays correct.
4. **Answer "what does the artist do next?"** at each step in the report. "Read the source" means unfinished.
5. **Drive the app, not the feature**: before a device install, play a scene, pan from the grey, drag and
   release a Move node, draw a stroke — on the device — and say you did. A green full suite says nothing
   about feel. Put these four in the brief, not in the reviewer's head.

### Persistent statics, shared resources and the simulator host

- **The model writes no store (TODO 176):** `AppSettings` is the one `UserDefaults` store (an instance over
  the defaults it is handed; logic tests hand it a suite of their own); only `AppSettingsKeeper`, held by
  `ContentView`, carries a value to a `CanvasManager`. A new app-wide value goes there, never in a model
  `didSet`. `-resetEditorPreferences` and `launchIntoEditor`'s `-resetBrushLibrary` reset it for UI tests.
  **A failure that repeats in a serial batch but not alone is a leak between tests** — ask what the test
  before it persisted.
- **Everything that looks per-session and is not:**
  - **Simulator UDID**: every worktree inherits the UDID above; `simctl shutdown all` + `erase` kills
    another session's run (`Mach error -308 - (ipc/mig) server died` / `Invalid device state`). Check
    `pgrep -x xcodebuild` first; if one is live, wait or use a device of your own, deleted afterwards:

    ```bash
    UDID=$(xcrun simctl create "<slug>" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB \
      com.apple.CoreSimulator.SimRuntime.iOS-26-5) && xcrun simctl boot "$UDID"
    # ... run with -destination "platform=iOS Simulator,id=$UDID" ...
    xcrun simctl delete "$UDID"
    ```
  - **`git stash`** is one stack for every worktree — never use it; commit on your own `tmp/<id>` branch.
  - **`origin/main`** is a shared ref any `git fetch` moves — reset only to a sha you recorded.
  - **Never kill by process name** (`pgrep -f xcodebuild | xargs kill` is machine-wide). Kill only recorded
    PIDs or `pkill -f "$PWD"`. `pgrep -f` counts substrings including its own caller (~3× the runs): use
    `pgrep -x xcodebuild` and a fresh `lsof -a -p <pid> -d cwd`. In cleanup, protect the live run's ancestor
    **chain** plus its own **subtree**, not every ancestor's descendants.
  - **A worker's tree is a workbench** (half-finished edits, deliberate mutations): act on it only after
    its completion notification and harvest *commits*. As the worker, **commit first, mutate second**
    (or mutate a throwaway copy outside any worktree); verify and commit the same bytes.
- **Wrap every run in [tools/simlock.sh](tools/simlock.sh)** — your own device stops you erasing someone
  else's, not starving the machine (5 concurrent runs left 1–3% idle and returned wrong answers):

  ```bash
  tools/simlock.sh xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
    -destination "platform=iOS Simulator,id=$UDID" ... -parallel-testing-enabled NO
  ```
  It holds one of `SIMLOCK_SLOTS` (default 2) for the command's life and reclaims a dead owner's slot.
  Machine load: `top -l 2 -n 0 -s 2 | grep "CPU usage" | tail -1` (`uptime` is not usable here).
- **Waiting: block on one condition inside one command; never poll or queue timers** (polling costs a
  request per check; queued timers left 78 sleeping shells and stale notifications). Background it if you
  want to work meanwhile — the harness re-invokes you:

  ```bash
  until grep -qE "TEST SUCCEEDED|TEST FAILED|BUILD FAILED" /tmp/run.log; do sleep 20; done
  ```
  **Put "block on one wait; do not queue timers; do not spawn subagents" in every brief.**
- **A cluster of failures with no assertion messages is a sick host** (`backboardd`/`testmanagerd`/
  `SimRenderServer` crashes, a runner that won't bootstrap, `Restarting after unexpected exit` in the log):
  re-run whole on a **newly created** device. **A regression fails the same tests twice** — two runs of
  the same bytes failing *disjoint* sets means the run is the variable. Parallel clones also contend with
  each other on a fresh device: failures that pass in a serial re-run are timing, not stale state.
- **A harness that measures growth is measuring its autorelease pool** until proven otherwise: wrap
  measurement loops in `autoreleasepool { }` and prefer counting your own allocations (cache bytes,
  `MTLBuffer.length`) over `phys_footprint`; say so if you use the proxy.

### Triaging a failed XCUITest — do this before suspecting your change

A one-off XCUITest failure is environmental far more often than real; the isolated re-run (30 s, against
22 min) is the confirmation — do not re-run the suite to decide.

```bash
xcrun simctl shutdown all; xcrun simctl erase 75C8B97E-47AF-484B-B7D2-CA7EB1B51B03   # only if no other session is on it
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination 'platform=iOS Simulator,id=75C8B97E-47AF-484B-B7D2-CA7EB1B51B03' \
  -only-testing:PaintSoftwareUITests/<Suite>/<test> \
  -parallel-testing-enabled NO -derivedDataPath build/DerivedData
```

`<Suite>` is the **class**, not the file; a wrong selector reports `Executed 0 tests` +
`** TEST SUCCEEDED **`. Resolve it from the source:

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

Without `-parallel-testing-enabled NO` xcodebuild clones the device even for one test. After a killed
run, sweep strays — clones live in their own device set, so plain `simctl list` never shows them:

```bash
xcrun simctl --set ~/Library/Developer/XCTestDevices list devices
xcrun simctl --set ~/Library/Developer/XCTestDevices delete <udid>     # --set is needed on delete too
```
A duplicated `Clone N of <device>` number is debris from a dead run; sweep after runs finish, never during.

Passes clean → environmental: say so, name the test, move on. Fails clean → it is yours. **Erase is right
for a state flake and the worst case for a timing one** — run a duration assertion warm first. A failure
that also repeats in a serial batch is a leak between tests.

### pbxproj: two branches can mint the same object id

The app target auto-includes sources, but **the UI-test target has an explicit `PBXSourcesBuildPhase`**: a
new *test* file is added to `project.pbxproj` by hand, and so is any app source a logic test touches
(compiled into the test target a second time under its full path: `Effect.swift`,
`InterpolationRecipe.swift`, `ShapeHoldClock.swift`, `AnimationCurve.swift`) — a new type plus its logic
test is four object ids, and a bare-filename lookup finds nothing. Do not take the next sequential id off a
neighbour: two branches minted the same pair and git merged it cleanly while Xcode silently dropped a file
(`cannot find 'X' in scope` in a file nobody touched). After any rebase touching `project.pbxproj`:

```bash
python3 -c "
import re,collections
src=open('PaintSoftware.xcodeproj/project.pbxproj').read()
defs=re.findall(r'^\t\t([0-9A-F]{24}) /\* (.*?) \*/ = \{isa = (\w+)', src, re.M)
c=collections.Counter(d[0] for d in defs)
print([k for k,v in c.items() if v>1])"      # must print []
```

## The Windows laptop — the streamer host for TODO (27), (98), (99)

`desktop-cbr0fl6`, `100.104.85.111` on the tailnet (the iPad is `100.70.220.4`). Reach it with
`ssh -i ~/.ssh/paintapp_windows -o BatchMode=yes PC@100.104.85.111 '<powershell>'` (PowerShell 5.1, `PC` has
a full admin token). **`PC` is the admin SSH logs in as; `kevin` is the person at the screen**, and only
kevin's session can capture it (an SSH-spawned process sees a fake 1024×768 display). The streamer is a
normal program on kevin's side (`Streamer.Tray.exe`, shortcuts; nothing starts it at logon;
`SingleInstanceGuard` named pipe makes a second launch show the running window, replacing an instance that
does not answer within 5 s). The `PaintStreamer` Scheduled Task has an Interactive principal for kevin and
**no trigger** — it is how this Mac reaches kevin's session:

```bash
tools/windows/streamer-remote.sh status|start|stop|log [n]|sources|deploy|test
```

`deploy` tars `streamer/` over (use `COPYFILE_DISABLE=1` or macOS `._*` sidecars break `dotnet publish`),
builds with the .NET 8 SDK at `C:\dotnet`, publishes to `C:\Users\kevin\AppData\Local\PaintStreamer\app`
and restarts the task. GStreamer 1.26.8 is at `C:\Program Files\gstreamer\1.0\msvc_x86_64` (the MSI
series; 1.28 moved to an `.exe`). `winget` fails over SSH; use direct installers. A locked laptop cannot be
captured or unlocked from here (the streamer says "The laptop is locked" and waits). Prove the laptop end
with `tools/stream/stream-client-check.py --host 100.104.85.111` and the iPad end against
`tools/stream/fake-streamer.py --pattern`; STREAM.md §4 is the rest.

## Deploy to iPad

### The install gate — `tools/playcheck.sh <udid>`, green before every install

On an iPad (9th generation) simulator of your own: it erases and boots the device, samples the
simulator's own `backboardd` and the app once a second (`tools/sim-footprint-sampler.sh`, `phys_footprint`
and the kernel's peak) and runs `PlaycheckGateUITests` — the owner's routine on a 5000² five-layer scene at
1080×810 — asserting after every phase `backboardd` ≤ 450 MiB and the app ≤ 1,165 MiB (derivations in the
test's header). `playcheck: GREEN` with exit 0 is the only pass; run through anything else the test fails.
It measures the processes the iPad kills, not a proxy (`LayerContentsCensus` stayed green while
`2891caad` crashed on Play).

```bash
source ~/.config/paintapp/.env      # KEYCHAIN_PASSWORD, SIGNING_IDENTITY, PROJECT_DIR, PROJECT_FILE, SCHEME
security unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db
BUILD_ARGS=(-project PaintSoftware.xcodeproj -scheme PaintSoftware -configuration Release
  -destination "platform=iOS,id=E3B83820-DF74-5042-B52B-0D5BA17E4877" -derivedDataPath build/DerivedData)
xcodebuild clean "${BUILD_ARGS[@]}" || exit 1
xcodebuild build "${BUILD_ARGS[@]}" -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration || exit 1
codesign --verify --deep --strict <path>.app || exit 1
EXP=$(security cms -D -i <path>.app/embedded.mobileprovision | plutil -extract ExpirationDate raw - -o -) || exit 1
EXP_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$EXP" +%s) || exit 1
if [[ $((EXP_EPOCH - $(date +%s))) -lt 3600 ]]; then
  echo "REFUSE: profile expires $EXP — expired or about to, do not install"
  exit 1
fi
xcrun devicectl device install app --device E3B83820-DF74-5042-B52B-0D5BA17E4877 <path>.app
```
**A manual sign does not need the iPad** (it is registered with the team): a
`generic/platform=iOS -allowProvisioningUpdates` Release build mints the profile and `install` works with it
locked; naming the iPad as destination makes Xcode wait for an unlock. Only on *"Your team has no devices
from which to generate a provisioning profile"* name it and pass `-allowProvisioningDeviceRegistration`.
Check the expiry before installing (an expired profile is how "PaintApp is no longer available" recurred).
**No minimum-life floor (owner, 2026-11-16)** — install any verified build. The scheme's LaunchAction stays
Debug; `-configuration Release` is what ships (Debug is 62× slower on the alpha-mask path).
`~/PaintApp/deploy/deploy.sh` **pulls `main` first** and never ships branch work — run the steps above from
the worktree. The first `install` often fails with `NWError 54`; re-run. **`CoreDeviceError 1011` — run
`devicectl list devices` first:**
- **`available (paired)`** → stale tunnel: `xcrun devicectl device info details --device <UUID>`, then
  `install` succeeds.
- **`unavailable`** → asleep, locked or off the network (`info details` answers from cache with a stale
  date); nothing here fixes it — say so, do not retry. Never pass the device by name (columns shift on the
  space in "Kevin's iPad"); use the UUID.

**Auto-resign** ([docs/RESIGN.md](docs/RESIGN.md), `tools/resign/`): *sign* (Mac only) and *install* (iPad
only) are separate stages over `~/.config/paintapp/resign_state`. Sign: when the newest profile is expired
or within 1 h, build Release for `generic/platform=iOS` (fetch best-effort, never downgrading the installed
source), verify, stage in `~/PaintWork/device-*`. Install: whenever the iPad is listed available, install
the staged build and promote it to `LAST_*`. A user LaunchAgent ticks every 5 min; the root LaunchDaemon
hourly, arming `pmset` wakes around expiry. The owner is notified only when he must act. After a **manual**
install, update all four `LAST_*` fields atomically (import a branch commit into `~/PaintApp` first), never
before the install succeeds. Change the script in git, run `bash tools/resign/test-resign.sh`, then
`tools/resign/install.sh` to pin it. Log: `~/.config/paintapp/resign.log`.

Simulator testing runs locally — the Tailscale/SSH `deploy/mac/*` scripts are for the Windows machine.

**Physical-device UI harnesses own every gallery fixture they create.** Create a uniquely named test
folder and scenes at setup, record their exact project IDs/paths, and in teardown/finally (including after
a failure) move only those to Trash through the gallery UI, then verify a fresh ProjectExport inventory.
Never run a reset-heavy simulator-base harness on the owner's iPad; preserve real settings and brush and
palette libraries. No product cleanup hook; never delete unowned or general-named scenes.

## Action recorder — get the bug off the owner's iPad instead of guessing at a simulator

`PaintSoftware/Debug/ActionRecorder.swift` turns the owner's four-second reproduction into one greppable
JSONL file (touches with pencil-vs-finger type and hit target, recognizer transitions, canvas decisions,
model changes, one clock). **Reach for it before spending runs reproducing something you can't.**

- **On**: Settings → **"Record My Actions"**, reproduce, **"Stop Recording"**. The **flight recorder is
  always on** (last 90 s in memory), saving `flight-*.jsonl` when `CanvasTouchAudit` finds the canvas not
  answering a hand (trigger `canvas`; `canvasMiss` names every recognizer then not at rest) or on Settings →
  **"Save Last 90 Seconds"** (cost: PERFORMANCE.md §23).
- **Where**: `Documents/Recordings/recording-yyyyMMdd-HHmmss.jsonl` (and `flight-…`), with Share/Delete in
  Settings. Pull over the cable:

  ```bash
  xcrun devicectl device copy from --device E3B83820-DF74-5042-B52B-0D5BA17E4877 \
    --domain-type appDataContainer --domain-identifier Starg.PaintSoftware \
    --source "Documents/Recordings/<file>" --destination ./
  ```
- A tap on SwiftUI chrome records `"target": null` (no accessibility client on the iPad); canvas and timeline
  touches record fully — use `hitClass` and the next `model` line (`WindowEventTap.resolveTarget`'s doc comment has the
  measurement); record under an XCUITest runner to name every element.

`tools/recording2xcuitest.py <file>.jsonl` drafts an XCUITest from a recording (the tedious 90%; it does
not compile untouched) and refuses to downgrade a pencil touch to a finger, since XCUITest cannot
synthesise a pencil.

## graphify

Prefer over raw grep for orienting.
```bash
graphify update .              # refresh (AST-only, no API cost) — after code changes
graphify query "<question>" ; graphify path "<A>" "<B>" ; graphify explain "<concept>"
```
[graphify-out/GRAPH_REPORT.md](graphify-out/GRAPH_REPORT.md) is tracked; `graph.json`/`graph.html` and
dated snapshot folders are gitignored. Commit a refreshed report when you refresh the graph. A
`PreToolUse` hook ([.claude/hooks/graphify-guard.sh](.claude/hooks/graphify-guard.sh)) nudges toward it;
it resolves `graphify` from PATH and fails open.

## Docs

[HANDOFF.md](HANDOFF.md) is **both the state of the repo and the prompt that starts the next session** —
its first section is the paste block. Keep it one file; rewrite the paste block when you close a pass, do
not append. [TODO.md](TODO.md) is **the owner's asks, live** — record them when they arrive, delete them
when done and merged; [BUGS.md](BUGS.md) is what *we* find. **At most three items in flight at once**,
unless the extras need no simulator. TODO's **"Later"** items (28), (30) each need a design conversation
with the owner before they start.

Specs under [docs/](docs/) — read a spec's rulings rather than re-deriving them, and prune docs rather than
appending status:

- [RENDER.md](docs/RENDER.md) — background baker, on-disk frame store, export (sixteen rulings in §2;
  the knob is the truth, §2.12: a frame that doesn't fit the budget is composited in strips at full size,
  §3.8, `Engine/StripedComposite.swift`, never smaller). **Trap (§3.8): `PixelOps.RasterizeKey`, `MaskResolver.CacheKey` and
  `MetalCompositor`'s `UploadCache.Key` are keyed on the buffer's *size*, so compositing the same content
  into two equally sized buffers collides and returns the first one's pixels.** Memory audit:
  PERFORMANCE.md §13.
- [KEYFRAMES.md](docs/KEYFRAMES.md) — keyframe animation (thirty rulings §2, build order §8; §2.1, §2.23,
  §2.24, §2.28's closing rule superseded and kept). A keyframe is a bare mark; marks ∪ channel keys is
  computed by one accessor, never stored twice; bake is an authoring feature, never a performance
  instruction; `keyframeMarks` is the only storage for §2.26's first step so it stays; posed ink is baked in
  rest space (`StrokeDistort.rest`) and `PixelOps.RasterizeKey` / `LayerContentVersion` carry
  `DerivedCelContent.identity`; a transform key stores a quad; §2.16's Move half stays declined (TODO 37).
- [EFFECT_BACKDROP.md](docs/EFFECT_BACKDROP.md) — what an adjustment layer grades (§6 build order).
  Grading paper makes the composite opaque, and filling paper destroys the alpha Outline/Sobel/Bloom read —
  hence their ink-only input choice.
- [LASSO_FILL.md](docs/LASSO_FILL.md) — the lasso fill algorithm and edge cases.
- [LASSO_MOVE.md](docs/LASSO_MOVE.md) — lasso *move*. **§5 holds thirty-three owner rulings; read it, do
  not re-litigate** (selection by centre line, split strokes become two, one undo step per nudge,
  membership belongs to the selection, on-screen meaning on every frame — `activeVectorMoveTarget`'s
  `celPoseIsResting` refusal is gone — open lasso acts as closed, Freeform stretch scales ink by
  `sqrt(|det|)`).
- [CANVAS_RESIZE.md](docs/CANVAS_RESIZE.md) — TODO (9). Read §0: `setCanvasPadding` is already a
  whole-document crop/expand and `VectorCanvas.mapping(_:throughSimilarity:)` the exact vector scaler.
- [LAYER_TRANSFORM.md](docs/LAYER_TRANSFORM.md) — `VectorCanvas._transform` (adopt with changes).
  **Not the same feature as** [TRANSFORM_LAYER.md](docs/TRANSFORM_LAYER.md), the transformation
  `LayerKind` and its five modes (shipped).
- [VECTOR_INTERPOLATION.md](docs/VECTOR_INTERPOLATION.md) — interpolation decisions (do not research or
  rework it now); [SCHEDULER.md](docs/SCHEDULER.md) / [SCHEDULER_DESIGN.md](docs/SCHEDULER_DESIGN.md) — the
  real-time rules and build order; [STREAM.md](docs/STREAM.md); [RESIGN.md](docs/RESIGN.md);
  [BRUSH.md](docs/BRUSH.md); [ARCHITECTURE_REVIEW.md](docs/ARCHITECTURE_REVIEW.md);
  [BRUSH_ENGINE_EXTENSIBILITY.md](docs/BRUSH_ENGINE_EXTENSIBILITY.md) and
  [REFACTOR_BASELINE.md](docs/REFACTOR_BASELINE.md) (reference).
- [README.md](README.md) — the app and its architecture. [PERFORMANCE.md](PERFORMANCE.md) — ranked
  optimisation programme, work ruled not worth doing, every figure's provenance: read it before optimising
  anything and label any number you add MEASURED or INFERRED.
