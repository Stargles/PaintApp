# Session Log

Format: `Session N — YYYY-MM-DD: changed: <short description>`
Append one line per session, minimal wording. See [CLAUDE.md](CLAUDE.md) for the full protocol.

Session 1 — 2026-07-20: changed: Added project gallery/persistence, fixed canvas creation freeze, timeline/gesture bugs, added UI test target
Session 2 — 2026-07-20: changed: Fixed bottom (non-topmost) layer swallowing touches when active; added UI regression test
Session 3 — 2026-07-20: changed: Rewrote animation timeline resize/reposition/scrub as UIKit gesture recognizers (SwiftUI DragGesture composition was unreliable there); all 7 UI tests pass
Session 4 — 2026-07-20: changed: Replaced full-bleed photo import with object layers (movable/scalable/rotatable via on-canvas handles); see commit message for UI-test caveat
Session 5 — 2026-07-20: changed: Fixed deleteLayer wrong-active-layer bug and a publish-during-view-update hang/crash on delete; hardened LayerRow index access; added 2 UI regression tests
Session 6 — 2026-07-21: changed: none — investigated reported flakiness in 3 UI tests (edge-handle drags, bottom-layer draw), could not reproduce in 39+ runs across 5 simulators/both old and current main; root cause is very likely cross-session simulator-device contention (see a32c91d), not a gesture-technique defect
Session 7 — 2026-07-20: changed: Added smart fill tool (gap-closing flood fill, cross-layer masking, antialiasing-seam fix); builds clean, but interactive UI tests couldn't be run in this environment (no touch/automation access)
Session 8 — 2026-07-21: changed: Added Select tool (lasso/rectangle/automatic) and Move tool (PowerPoint-style transform box, mirror/rotate90/mode bar, duplicate/fill/clear); fixed an infinite render loop from reassigning PKDrawing mid-render; all 9 UI tests pass. Built in worktree select-move-tool, not yet merged with the concurrent object-layer/fill-tool work
Session 9 — 2026-07-21: changed: Merged claude/unruffled-pare-44b444, fill-tool, and select-move-tool into main (worktree-fix-layer-delete was already fully contained). Reconciled fill-tool's Cel.fillImage with select-move-tool's Cel.bakedImage (parallel raster layers neither branch knew about the other's), fixed a field-rename compile break in FloodFillEngine.swift, and fixed a fill-panel slider-identifier ambiguity that was masking a UI test bug. 13/14 UI tests pass; disabled testFillToolBridgesOpenContourGapWhenGapClosingEnabled pending further investigation — see BUGS.md
