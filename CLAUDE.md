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
  `simctl shutdown` + `erase` the simulator *immediately before* it: leftover parallel clones are
  the cause of nearly every mystery failure. Run `uptime` before diagnosing one.
- `Engine/Deform` compiles standalone with `swiftc` (~5 s a loop) — use it to test engine
  hypotheses instead of a 90 s `xcodebuild test`.

## Deploy to iPad

```bash
source ~/.config/paintapp/.env      # KEYCHAIN_PASSWORD, SIGNING_IDENTITY, PROJECT_DIR, PROJECT_FILE, SCHEME
security unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db
xcodebuild build -project PaintSoftware.xcodeproj -scheme PaintSoftware \
  -destination "generic/platform=iOS" -allowProvisioningUpdates -derivedDataPath build/DerivedData
xcrun devicectl device install app --device E3B83820-DF74-5042-B52B-0D5BA17E4877 <path>.app
```
`~/PaintApp/deploy/deploy.sh` does this but **pulls `main` first**, so it never ships branch work —
run the steps above from the worktree instead. The first `install` often fails with `NWError 54`;
just re-run it. Never pass the device by name (`devicectl`'s columns shift on the space in
"Kevin's iPad") — use the UUID above.

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
