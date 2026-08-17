# Handoff — 2026-08-16

Written at the end of a UX-feedback pass. **Verify everything here before trusting it** — the previous
handoff file was deleted this session precisely because it had gone stale, and this one decays the same
way. `git log`, `git worktree list` and [TODO.md](TODO.md) are the live state; this is orientation.

Read [CLAUDE.md](CLAUDE.md) first, then [TODO.md](TODO.md) (the owner's asks) and [BUGS.md](BUGS.md)
(what we found).

## The one genuinely new capability: you can test on the owner's iPad

This landed late and changes how you should work. Automation mode is enabled on the device, so
`xcodebuild test` runs there directly:

```bash
source ~/.config/paintapp/.env
security unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db
tools/simlock.sh xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -configuration Release -destination "platform=iOS,id=E3B83820-DF74-5042-B52B-0D5BA17E4877" \
  -only-testing:PaintSoftwareUITests/PerfBaselineTests \
  -allowProvisioningUpdates -derivedDataPath build/DerivedDataDevice
```

`PerfBaselineTests` completes there in **14 seconds**. Prefer it over the simulator for anything
performance- or touch-related.

**Why it matters, with the numbers that prove it.** Every performance conclusion reached from the
simulator this session was wrong by a wide margin, because the simulator borrows a Mac's GPU. Measured
on the device, 6 layers at 2048²:

| | CoreGraphics | Metal |
|---|---|---|
| plain stack | 41.6 ms | **102.5 ms** |
| with one grade | 240.3 ms | **30.3 ms** |
| per-layer slope | 4.4 ms | **2.2 ms** |
| fixed per-frame | **3.9 ms** | 7.3 ms |
| peak memory | **382.6 MB** | 462.9 MB |

The simulator had said Metal was ~16–375× faster and led to "flip the default to Metal". The device
says Metal is **half the per-layer cost but nearly double the fixed cost** — so it loses on simple
documents and wins enormously on graded ones. The right shape is a predicate, not a default. That
correction is in flight on `tmp/compperf`.

## Branch state

`main` is pushed and green (fast tier ~974 tests, 0 failures). Two branches are live and **not**
merged; both were being actively worked when this was written, so re-read their tips:

- **`tmp/compperf`** (8 commits ahead) — Metal compositing, device-aware memory budget, render-resolution
  option. Fixed a real 4K crash: the owner's scene (4096², vector + bloom + blur) holds **six
  canvas-sized textures = 384 MiB**, of which only the 64 MiB upload cache had any budget. `CompositorBudget`
  now sizes composites to `physicalMemory/16` (192 MiB on the owner's iPad 9, capping 4096² to 2896²).
  Also found: `PixelOps`' flatten memo was capped at 24 *entries* — **1.61 GB at 4096²** — and its
  memory-warning observer did not exist despite the doc comment claiming it.
  **Open before merge:** the Metal-vs-CoreGraphics predicate above, and the 17 fps question below.
- **`tmp/shapefix`** (7 commits ahead, tip `1a6e05f`) — shape gesture fixes. Handles now sized in screen points (they
  were in canvas points, drawing at 4.4 pt on a fitted canvas — that is the owner's "faint blue line,
  no nodes"). Oval handles rotate with the diametrically opposite node anchored, verified headless at
  1420 cases / 7020 assertions. Pinch-from-centre fixed. Smart-shape hold measured in `UITouch.timestamp`
  rather than wall clock. **Open before merge:** device confirmation of the snap fix, including a
  resting-palm test.
- `tmp/devicebuild` is a throwaway integration branch for building onto the iPad. Its BUGS.md conflicts
  were resolved by keeping both sides; **do not merge it anywhere**.

## The two open bugs, with what is already known

**17 fps drawing on a 4K canvas.** The owner tested render resolution at 50% and saw **no change**,
which rules out the compositor — the option demonstrably works (52.7 → 12.0 ms for three composites).
The device run points at `vector layer render | firstRender=70.0ms  cachedRender=0.0ms` at 2048²: the
owner draws *on* a vector layer, so each update invalidates that render, and the resolution option
scales the compositor but not the vector rasterization. Unconfirmed.

**Snap does not engage** (pen down, shape formed, add a finger). Root cause found: every canvas view
left `UIView.isMultipleTouchEnabled` at its `false` default — *"the view receives only the first touch
event in a multitouch sequence"* — so the finger, arriving 0.4 s later in its own event, was dropped
before any recognizer saw it. Two ActionRecorder captures were needed to establish this; both are in
`~/Downloads/recording-2026081*.jsonl`. The same fact explains why `StrokeGestureRecognizer.failTrackedStroke`
had never been reached (BUGS.md), since that path needs a later-arriving second touch.

**The fix makes palm rejection load-bearing for the first time**: a palm was previously harmless only
because UIKit discarded it. It now arrives and must be refused by touch type. Test with a resting hand.

**Do not read `tmp/shapefix`'s green suite as evidence the snap fix is safe.** Its full run is 1086
tests / 1079 passed / 2 failed / 5 skipped, but **every surface the fix touches is unreachable by
XCUITest**: the rewritten `touchesBegan` branch only runs when a second touch arrives in a *later*
event, and every synthetic two-finger gesture in this repo has been measured arriving in a single one.
So the suite could not have caught a regression here either — its value is the surrounding surface,
which is clean. The two failures (`ModePickerUITests` menu tap, and the 189 s
`testInterpolateModeEndToEndFromGestureToScrub`) were re-run isolated on an erased device: **both
passed, 0 failures.** Environmental. **The device is the only real test of this fix.**

## Process, learned expensively here

- **`tools/simlock.sh` wraps every `xcodebuild`.** Five concurrent runs took this 8-core Mac to 1–3%
  idle, and at that load suites do not merely run slowly — **they return wrong answers**. The same
  shape-hold test passed and failed on the same binary depending on contention, and three separate
  results this session had to be thrown away and re-measured.
- **Three items in flight at most** (TODO.md). The lock bounds the machine; nothing bounds the plan but
  this rule.
- **Agents park waiting on test runs without committing.** Read their worktree directly — `git log`,
  `git status`, the log file — instead of waiting for a resume round-trip. **Read, do not write.**
  Committing into a live agent's worktree races with its own commit; it happened here (`1a6e05f`), the
  agent correctly refused to assume the unexplained commit was benign and spent a cycle verifying its
  diff and parent. Nothing was lost, but the next one might be. If work must be secured, message the
  agent to commit it.
- **Agents do not delete their simulators even when told to.** Sweep both device sets yourself;
  clones live in `~/Library/Developer/XCTestDevices` and `xcrun simctl list devices | grep -i clone`
  **cannot see them** (fixed in CLAUDE.md this session).
- **Check for duplicate pbxproj object ids after any rebase** — two branches minted the same pair here
  and git merged them silently, dropping a file from the test target with an error naming a symbol
  neither branch had touched. Detector is in CLAUDE.md.
- **The owner's behavioural reports are high-quality evidence.** They corrected two diagnoses and one
  design this session. When a report names a duration, grep for that number: "a 0.8 s lag spike" turned
  out to be the shape-hold constant elapsing, not a stall — the thing suspected of stalling was
  measured at **0.43 ms**.

## Blocked on the owner

Nothing right now. Two device checks were outstanding and both came back: the pencil delivers ~59
events/second while held still (confirming the pen-clock hold design), and the 4K scene crashes
(fixed, pending re-test). The six shape questions are answered and recorded in TODO.md's done list.
