# Multi-Session Protocol

Multiple sessions may work this repo concurrently, each in its own worktree. Never edit `main` directly. Assume the tree has moved — `git fetch` before trusting what you remember.

## Work in a worktree

```bash
git fetch origin
git worktree add ../PaintApp-<id> -b tmp/<id> origin/main   # <id> = short descriptive slug
```
All edits happen inside that directory. `tmp/<id>` is throwaway — it dies with the worktree.

## Finish and merge

```bash
# inside the worktree: commit everything, build/test first (say so if you can't)
git fetch origin && git rebase origin/main
cd ../PaintApp && git merge --ff-only tmp/<id> && git push origin main
git worktree remove ../PaintApp-<id> && git branch -d tmp/<id>
```
If `--ff-only` fails, rebase again — don't force-push, don't merge-commit.
Append one line to [SESSION_LOG.md](SESSION_LOG.md): `Session N — YYYY-MM-DD: <what changed>`.

## Remote testing (Tailscale → Mac, no Xcode on this machine)

Mac: `juliapark@100.70.148.78` (key auth, `~/.ssh/id_ed25519.pub` → Mac's `authorized_keys`). Wake if asleep: ping first; if silent, `tailscale ping --timeout 10s 100.70.148.78`, else ask the user. `womp` is on.

Each session gets an isolated worktree + DerivedData + simulator on the Mac — safe to run concurrently.

```bash
git push origin tmp/<id>
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/parallel_test.sh <id> tmp/<id> [testName]"
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/status.sh"
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/cleanup_session.sh <id>"       # when done
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/cleanup_session.sh --all"      # emergency
```
Stale sim locks (`/tmp/paintapp-sim-locks/<uuid>/`) auto-reclaim after 2h; script waits up to 20 min for a free simulator. UI tests run long — pass `timeout: 600000` on the ssh call.

**Screenshots:** `.\deploy\mac\screenshot_fetch.ps1 <id>` (Windows, SCPs back locally, then `Read` the path). Direct: `ssh ... "bash ~/PaintApp/deploy/mac/screenshot.sh <id>"` → `scp` the returned path. Needs an active sim lock + booted simulator.

**iPad simulators:**
| Name | UUID |
|---|---|
| iPad Pro 13" (M5) | C90F0965-6F87-4FB7-BD97-941E03968E99 |
| iPad Pro 11" (M5) | 2AE27426-4D30-465F-9B93-A759CAEA8456 |
| iPad Air 13" (M4) | 2728EC30-A6B1-49FF-BFE8-7A71945F631C |
| iPad Air 11" (M4) | 37AB7750-D487-46A6-88CA-381462F31107 |
| iPad (A16) | BE6580AC-B13E-4E3B-BA09-45E8EDD43B9B |
| iPad mini (A17 Pro) | A3A42701-53F0-4DE7-93D0-F092605D3354 |

Xcode: `/Applications/Xcode.app` (`xcodebuild`/`xcrun` on PATH). Metal shaders need the toolchain once: `xcodebuild -downloadComponent MetalToolchain`.

## Deploy to iPad

```bash
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/deploy.sh"   # pull → unlock keychain → build → install
```
Config: `~/.config/paintapp/.env` on the Mac (never commit). Auto-resign (7-day free-account cert expiry):
- `/Library/LaunchDaemons/com.paintapp.resign.plist` — daily 3:05 AM as root, resigns every 5 days, wakes via `pmset schedule wakeorpoweron`.
- Log: `~/.config/paintapp/resign.log`. Status: `sudo launchctl list | grep paintapp`. Reload: unload/load that plist.

## graphify

Prefer over raw grep for orienting in this codebase.
```bash
graphify update .              # refresh (AST-only, no API cost) — do this after code changes
graphify query "<question>"
graphify path "<A>" "<B>"
graphify explain "<concept>"
```
[graphify-out/GRAPH_REPORT.md](graphify-out/GRAPH_REPORT.md) is tracked (19KB md — useful with no graphify installed, e.g. the Windows machine); `graph.json`/`graph.html` are gitignored, regenerated blobs. Commit a refreshed `GRAPH_REPORT.md` when you refresh the graph.

A `PreToolUse` hook ([.claude/hooks/graphify-guard.sh](.claude/hooks/graphify-guard.sh)) nudges toward graphify before `Bash`/`Grep`/`Read`/`Glob`. Resolves `graphify` from PATH or known per-user install paths — never hardcode one. Fails open (no-op) if missing. If a fresh clone has no graph yet, it prints a "run `graphify update .`" nudge instead of the normal query reminder. Too noisy during focused edits? Narrow its second matcher from `Read|Glob` to `Glob` — keeps the nudge on discovery, drops it from targeted reads.
