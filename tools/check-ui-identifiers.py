#!/usr/bin/env python3
"""No UI test may reach a control by its SF Symbol glyph name.

**The blind spot this covers.** The fast tier selects logic suites by filename, so it cannot run a
single XCUITest — a branch can be green in Debug *and* Release and still ship a UI suite that reaches
nothing. This is one cheap text check that sees into it, for one defect that has already happened.

2026-09-07: `ed7c8f4` gave the gallery button an explicit `accessibilityIdentifier`. An explicit
identifier **replaces** the implicit one SwiftUI derives from `Image(systemName:)`, so the two helpers
reaching that button by `"square.grid.2x2"` stopped matching anything. Three persistence tests went
red — `GalleryRecoveryUITests`' backup-restore and trash-restore, and
`EraserAndPersistenceUITests.testSaveAndReloadPersistsStrokesAcrossAppRelaunch` — none of them near
the persistence code they exist to guard, and all three with a bare `XCTAssertTrue failed`.

**A glyph name is not an identifier the app promises.** It is what SwiftUI falls back to *while no
identifier is set*, so a test that uses one is depending on the absence of one — and adding an
identifier, which is always an improvement, silently becomes a breaking change. Every control this
suite drives has, or can have, a real identifier.

    tools/check-ui-identifiers.py          # exit 0 clean, 1 with findings

Scope, stated so nobody trusts it further than it goes: it compares two sets of string literals and
nothing else. It cannot see an identifier attached to the wrong control, one on a view that never
appears, or any assertion about behaviour. It says a locator is *stable*, not that a test is right.
A general "does this identifier exist" check was tried first and abandoned: identifiers reach their
views through `identifier:` parameters on a dozen helper views, so the naive version reported 186
false positives. This one reports exactly the hazard it names.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "PaintSoftware"
TESTS = ROOT / "PaintSoftwareUITests"

# Every SF Symbol the app draws. `systemName:` is the SwiftUI/UIKit spelling; `system:` is
# `TopToolbar.iconButton`'s, and it is the one the 2026-09-07 defect came in through — a sweep that
# checked only `systemName:` found nothing and read as an all-clear.
GLYPH = re.compile(r'\b(?:systemName|system|systemImage):\s*"([^"\\]+)"')

# How a test looks an element up by name. Only the subscript form: a predicate query names a label or
# a pattern, which is a different question.
QUERY = re.compile(
    r'\.(?:buttons|images|otherElements|staticTexts|switches|tables|cells|textFields|sliders|'
    r'segmentedControls|steppers|scrollViews|collectionViews|navigationBars|alerts|sheets)'
    r'\[\s*"([^"\\]*)"\s*\]'
)


def main():
    glyphs = set()
    for path in sorted(APP.rglob("*.swift")):
        glyphs.update(GLYPH.findall(path.read_text(encoding="utf-8", errors="replace")))

    findings = []
    for path in sorted(TESTS.rglob("*.swift")):
        for number, line in enumerate(
                path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            for name in QUERY.findall(line):
                if name in glyphs:
                    findings.append((path.relative_to(ROOT), number, name))

    if not findings:
        print(f"OK — no UI test reaches a control by a glyph name ({len(glyphs)} SF Symbols in the app).")
        return 0

    print(f"{len(findings)} UI-test lookup(s) by SF Symbol glyph name:\n")
    for path, number, name in findings:
        print(f"  {path}:{number}  queries {name!r}")
    print("\nThat is SwiftUI's implicit identifier, which exists only while the control has no explicit\n"
          "one. Give the control an accessibilityIdentifier and query that instead.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
