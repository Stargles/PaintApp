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
