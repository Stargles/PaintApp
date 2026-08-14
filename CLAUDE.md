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
- **Full run (~22 min)** — XCUITests are 99% of the runtime. Phase boundaries only, and
  `simctl shutdown all` + `erase` the simulator *immediately before* it: leftover parallel clones
  are the cause of nearly every mystery failure.
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
  ```

### Triaging a failed XCUITest — do this before suspecting your change

A one-off XCUITest failure here is environmental far more often than it is real, and re-running the
full suite to check costs 22 minutes for an answer a 30-second run gives. **The isolated re-run is
the confirmation. Do not re-run the suite to decide whether a failure was real.**

```bash
xcrun simctl shutdown all; xcrun simctl erase 75C8B97E-47AF-484B-B7D2-CA7EB1B51B03
xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination 'platform=iOS Simulator,id=75C8B97E-47AF-484B-B7D2-CA7EB1B51B03' \
  -only-testing:PaintSoftwareUITests/<Suite>/<test> -derivedDataPath build/DerivedData
```

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
instead. The first `install` often fails with `NWError 54`; just re-run it. Never pass the device by
name (`devicectl`'s columns shift on the space in "Kevin's iPad") — use the UUID above.

Auto-resign for the 7-day free-account cert: `/Library/LaunchDaemons/com.paintapp.resign.plist`
(daily 3:05 AM as root, resigns every 5 days). Log: `~/.config/paintapp/resign.log`.

Simulator testing runs locally too — the Tailscale/SSH `deploy/mac/*` scripts are for the Windows
machine, not this Mac.

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

[README.md](README.md) is the app and its architecture. [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md)
is the interpolation feature — settled decisions and the future-upgrade list. [BUGS.md](BUGS.md) is
open issues only. [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) and
[REFACTOR_BASELINE.md](REFACTOR_BASELINE.md) are reference. Keep them short: prune what is done
rather than appending status.
