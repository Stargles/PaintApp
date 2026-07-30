# Multi-Session Protocol

Multiple AI sessions may be working on this repo at the same time, each in its own git worktree. Assume another session could be editing overlapping files right now — don't assume the tree is exactly as you last saw it.

## Starting work

**You must always work in a git worktree. Never make changes directly on `main`.**

1. Pick a unique session ID (e.g. `session-<short-hash>` or a descriptive name like `fix-toolbar-crash`).
2. Create a worktree on a dedicated branch:
   ```bash
   git fetch origin
   git worktree add ../PaintApp-<session-id> -b session/<session-id> origin/main
   ```
3. All your work happens inside that worktree directory. Reference files with their full worktree path.
4. `git fetch && git status` in the worktree before assuming the tree matches what you remember.

## Ending a session / handing off

- Leave the working tree clean — commit everything before finishing. Don't leave uncommitted changes for the next session to inherit or collide with.
- Build/run tests before committing. If the environment can't run them (e.g. no full Xcode CLI tools available), say so explicitly rather than skipping silently.
- Write a real commit message describing what changed and why.
- `git pull --rebase origin main` before pushing if `origin/main` has moved — another session may have pushed while you worked. Resolve conflicts rather than force-pushing over them.
- Append one line to [SESSION_LOG.md](SESSION_LOG.md):

  ```
  Session N — YYYY-MM-DD: changed: <short description>
  ```

  Keep it minimal — a phrase, not a paragraph. Increment N from the last entry in the log.
- After committing, you can remove your local worktree:
  ```bash
  cd /path/to/PaintApp  # back to main
  git worktree remove ../PaintApp-<session-id>
  git branch -d session/<session-id>
  ```

## Remote testing via Tailscale

This Windows machine has no Xcode. Tests must run on the MacBook over Tailscale.

### Prerequisites

- Tailscale running on both machines (same tailnet)
- Mac SSH enabled: System Settings → General → Sharing → Remote Login → ON
- SSH key: `~/.ssh/id_ed25519.pub` on Windows must be in `~/.ssh/authorized_keys` on the Mac
- Mac username: **`juliapark`** (not `kevinpark0807`)
- Wake-on-LAN: run `sudo pmset -a womp 1` on the Mac if you need to wake it from sleep remotely

### Connection

```bash
ssh juliapark@100.70.148.78 "command"
```

### Parallel testing

Each session gets its own isolated worktree + DerivedData + simulator on the Mac, so multiple sessions can test concurrently without conflicts.

**Session ID:** Use the same session ID you created your local worktree with (e.g. `session-<short-hash>` or `fix-toolbar-crash`). Sanitised to `[a-zA-Z0-9_-]`.

**Push first, then test:**
```bash
# 1. Push your branch to origin (from inside your local worktree)
git push origin session/<session-id>

# 2. Run tests on the Mac (parallel-safe)
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/parallel_test.sh <session-id> session/<session-id>"
```

**Run a single test:**
```bash
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/parallel_test.sh <session-id> session/<session-id> testCreateCanvasReachesEditorWithoutFreezing"
```

**Check what's running:**
```bash
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/status.sh"
```

**When done, clean up your session:**
```bash
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/cleanup_session.sh <session-id>"
```

**Emergency — clean up everything:**
```bash
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/cleanup_session.sh --all"
```

The script auto-reclaims simulator locks older than 2 hours (stale/crashed sessions). It waits up to 20 minutes for a free simulator before failing.

**Mac directory layout:**
| Path | Contents |
|------|----------|
| `~/PaintApp` | Main clone (never tested directly) |
| `~/PaintApp-worktrees/<session-id>/` | Per-session worktree |
| `~/PaintApp-derived/<session-id>/` | Per-session DerivedData |
| `/tmp/paintapp-sim-locks/<uuid>/` | Simulator claim locks (atomic mkdir) |
| `/tmp/paintapp-screenshots/` | Simulator screenshots |

### Taking screenshots

The AI can screenshot the simulator on the Mac to see what the app looks like in real time. This uses `xcrun simctl io` under the hood.

**Fetch a screenshot (recommended — saves locally for the Read tool):**
```powershell
.\deploy\mac\screenshot_fetch.ps1 <session-id>
```
This SSHs to the Mac, screenshots the session's locked simulator, SCPs the PNG back to Windows, and prints the local path. Use the Read tool on the returned path to view the image.

**Mac-only (if SSHing directly):**
```bash
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/mac/screenshot.sh <session-id>"
```
Returns the remote path (`/tmp/paintapp-screenshots/...`). Then SCP it back:
```powershell
scp juliapark@100.70.148.78:<remote-path> <local-path>
```

**Requirements:**
- The session must have an active simulator lock (i.e., tests must have been run or simulator claimed)
- The simulator must be booted (it stays booted after `parallel_test.sh` runs)

### Available iPad simulators on the Mac

| Name | UUID |
|------|------|
| iPad Pro 13-inch (M5) | C90F0965-6F87-4FB7-BD97-941E03968E99 |
| iPad Pro 11-inch (M5) | 2AE27426-4D30-465F-9B93-A759CAEA8456 |
| iPad Air 13-inch (M4) | 2728EC30-A6B1-49FF-BFE8-7A71945F631C |
| iPad Air 11-inch (M4) | 37AB7750-D487-46A6-88CA-381462F31107 |
| iPad (A16) | BE6580AC-B13E-4E3B-BA09-45E8EDD43B9B |
| iPad mini (A17 Pro) | A3A42701-53F0-4DE7-93D0-F092605D3354 |

### Notes

- `ssh` commands timeout after 120s by default; UI tests take several minutes — use the `timeout` parameter (e.g. `timeout: 600000` for 10 min).
- If the Mac is asleep, ping it first (`ping 100.70.148.78`). If it doesn't respond and `womp` is enabled, try `tailscale ping --timeout 10s 100.70.148.78` (may send a MagicPacket). Otherwise ask the user to wake it.
- Xcode is at `/Applications/Xcode.app`. `xcodebuild` and `xcrun` are on PATH.
- Metal shader compilation requires the Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`, one-time).

### Deploying to iPad

Build, sign, and install the app on the physical iPad remotely via Tailscale:

```bash
ssh juliapark@100.70.148.78 "bash ~/PaintApp/deploy/deploy.sh"
```

Script does: git pull → unlock keychain → xcodebuild → devicectl install.
Config lives at `~/.config/paintapp/.env` (never commit this).
LaunchAgent `com.paintapp.resign` auto-resigns every 6 days (518400s) to bypass the 7-day free-account expiry.

### Auto-Resign (7-day bypass)

- LaunchAgent: `~/Library/LaunchAgents/com.paintapp.resign.plist`
- Schedule: every 6 days + on login
- Log: `~/.config/paintapp/resign.log`
- Status: `launchctl list | grep paintapp`
- Reload: `launchctl unload ~/Library/LaunchAgents/com.paintapp.resign.plist && launchctl load ~/Library/LaunchAgents/com.paintapp.resign.plist`

### Auto-Resign (7-day bypass)

- LaunchDaemon: `/Library/LaunchDaemons/com.paintapp.resign.plist`
- Schedule: daily at 3:05 AM (runs as root, survives logout)
- Logic: script checks timestamp file; only resigns every 5 days
- Wake: `pmset schedule wakeorpoweron` fires before each resign
- Log: `~/.config/paintapp/resign.log`
- Status: `sudo launchctl list | grep paintapp`
- Reload: `sudo launchctl unload /Library/LaunchDaemons/com.paintapp.resign.plist && sudo launchctl load /Library/LaunchDaemons/com.paintapp.resign.plist`

## graphify

`graphify` builds a queryable knowledge graph of this codebase — god nodes, community structure,
cross-file relationships. Prefer it over raw grep when orienting yourself.

```bash
graphify update .                      # build/refresh the graph (seconds, AST-only, no API cost)
graphify query "<question>"            # scoped subgraph — usually far smaller than grep output
graphify path "<A>" "<B>"              # how two symbols relate
graphify explain "<concept>"           # one focused concept
```

`graphify-out/GRAPH_REPORT.md` is the broad architecture read; use it when query/path/explain don't
surface enough. **Re-run `graphify update .` after changing code** — a stale graph describes files
that no longer exist (it went stale twice during the 2026-07 refactor).

### How it's wired

A `PreToolUse` hook in [.claude/settings.json](.claude/settings.json) reminds sessions to consult
the graph before grepping or reading source. It runs
[.claude/hooks/graphify-guard.sh](.claude/hooks/graphify-guard.sh), which exists because three
things have to hold for a tracked hook in front of every `Bash`/`Grep`/`Read`/`Glob` call:

- **Portable.** `graphify` installs per-user and is usually not on `PATH`, so the hook resolves it
  from `PATH` first, then the known per-user install paths. Never hardcode one absolute path — the
  Windows machine described above has no graphify at all.
- **Fail-open.** If graphify is missing or errors, the hook is a silent no-op and exits 0. It must
  never block a tool call.
- **Self-bootstrapping.** `graphify-out/` is gitignored (`graph.json` is ~11 MB and rewrites
  wholesale on every refresh, so committing it is pure history churn). A fresh clone therefore has
  no graph, and bare `graphify hook-guard` is *silent* in that state — so the wrapper emits its own
  "run `graphify update .`" nudge instead, and sessions self-bootstrap in one command.

Do not commit `graphify-out/`. If the hook's reminders prove too noisy for focused editing work,
narrow the second matcher from `Read|Glob` to `Glob` — that keeps the nudge on discovery (searching
for something) and drops it from targeted access (opening a file you already know you need).
