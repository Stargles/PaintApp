# Multi-Session Protocol

Multiple AI sessions may be working on this repo at the same time, each in its own git worktree. Assume another session could be editing overlapping files right now — don't assume the tree is exactly as you last saw it.

## Starting work

- Run `git fetch && git status` before assuming the working tree matches what you remember.
- If another session is (or might be) active in this same directory, use a git worktree instead of sharing it (`EnterWorktree` tool if available, otherwise `git worktree add`).

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
