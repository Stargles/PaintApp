# Session Log

Format: `Session N — YYYY-MM-DD: changed: <short description>`
Append one line per session, minimal wording. See [CLAUDE.md](CLAUDE.md) for the full protocol.

Session 1 — 2026-07-20: changed: Added project gallery/persistence, fixed canvas creation freeze, timeline/gesture bugs, added UI test target
Session 2 — 2026-07-20: changed: Fixed bottom (non-topmost) layer swallowing touches when active; added UI regression test
Session 3 — 2026-07-20: changed: Rewrote animation timeline resize/reposition/scrub as UIKit gesture recognizers (SwiftUI DragGesture composition was unreliable there); all 7 UI tests pass
Session 4 — 2026-07-20: changed: Replaced full-bleed photo import with object layers (movable/scalable/rotatable via on-canvas handles); see commit message for UI-test caveat
Session 5 — 2026-07-20: changed: Fixed deleteLayer wrong-active-layer bug and a publish-during-view-update hang/crash on delete; hardened LayerRow index access; added 2 UI regression tests
