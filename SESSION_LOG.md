# Session Log

Format: `Session N — YYYY-MM-DD: changed: <short description>`
Append one line per session, minimal wording. See [CLAUDE.md](CLAUDE.md) for the full protocol.

Session 1 — 2026-07-20: changed: Added project gallery/persistence, fixed canvas creation freeze, timeline/gesture bugs, added UI test target
Session 2 — 2026-07-20: changed: Fixed bottom (non-topmost) layer swallowing touches when active; added UI regression test
Session 3 — 2026-07-20: changed: Rewrote animation timeline resize/reposition/scrub as UIKit gesture recognizers (SwiftUI DragGesture composition was unreliable there); all 7 UI tests pass
Session 4 — 2026-07-21: changed: Added Select tool (lasso/rectangle/automatic) and Move tool (PowerPoint-style transform box, mirror/rotate90/mode bar, duplicate/fill/clear); fixed an infinite render loop from reassigning PKDrawing mid-render; all 9 UI tests pass. Built in worktree select-move-tool, not yet merged with the concurrent object-layer work
