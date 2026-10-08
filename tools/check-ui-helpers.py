#!/usr/bin/env python3
"""No UI test file may define a function or type whose name `PaintUITestCase` already defines.

**The blind spot this covers.** A helper written beside the test that needs it looks harmless, and
the base class's helper of the same name is two hundred lines away in another file. 2026-10-07: the
audit found `waitForPixel` copied into four UI-test classes, every copy a little different — one
handed back its *last reading* when the wait timed out, so ten `XCTAssertNotNil(waitForPixel(...))`
assertions could not go red — and `RecolorUITests` and `LayerBakeUITests` carried a third and
fourth shape of it. A test cannot tell which one it is calling by the name, and the copy that is
wrong is the one nobody reads.

    tools/check-ui-helpers.py          # exit 0 clean, 1 with findings

It compares names, not signatures, on purpose: the copies above all had different parameter lists.
A helper that genuinely differs takes a name that says how (`waitUntilNoInk(in:)`, not another
`waitUntilBlank`), so a reader never has to open the file to learn which of two it is.

Scope, stated so nobody trusts it further than it goes: it reads declarations (`func`, `struct`,
`class`, `enum`, `typealias`, `protocol`) in files that hold a `PaintUITestCase` subclass or extend
it, against the non-private members of `PaintUITestCase` itself. It cannot see a *behavioural* copy
under a new name, a helper another base class defines, or a `private` helper in the base (which no
subclass can collide with). An `override` is the one legitimate re-declaration and is skipped.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "PaintSoftwareUITests"
BASE_FILE = TESTS / "PaintUITestCase.swift"
BASE_CLASS = "PaintUITestCase"

DECLARATION = re.compile(
    r'^(?P<indent>\s*)(?:@\w+(?:\([^)]*\))?\s+)*'
    r'(?P<modifiers>(?:(?:private|fileprivate|public|internal|final|static|override|class|lazy)\s+)*)'
    r'(?P<kind>func|struct|class|enum|typealias|protocol)\s+(?P<name>\w+)'
)
SUBCLASS = re.compile(r'\bclass\s+(\w+)\s*:\s*(\w+)')
EXTENSION = re.compile(r'^extension\s+' + BASE_CLASS + r'\b', re.M)


def read(path):
    return path.read_text(encoding="utf-8", errors="replace")


def base_members():
    """Non-private member names declared directly in the body of `class PaintUITestCase`."""
    names = {}
    inside = False
    for number, line in enumerate(read(BASE_FILE).splitlines(), 1):
        if re.match(r'^class\s+' + BASE_CLASS + r'\b', line):
            inside = True
            continue
        if inside and line.startswith("}"):
            break
        match = DECLARATION.match(line) if inside else None
        if not match or len(match["indent"]) != 4:
            continue
        modifiers = match["modifiers"]
        if any(word in modifiers for word in ("private", "fileprivate", "override")):
            continue
        names.setdefault(match["name"], number)
    return names


def ui_test_subclasses(files):
    """`PaintUITestCase` and every class that inherits from it, directly or through another."""
    parents = {}
    for text in files.values():
        for name, parent in SUBCLASS.findall(text):
            parents[name] = parent
    family = {BASE_CLASS}
    grew = True
    while grew:
        grew = False
        for name, parent in parents.items():
            if parent in family and name not in family:
                family.add(name)
                grew = True
    return family


def main():
    members = base_members()
    files = {path: read(path) for path in sorted(TESTS.glob("*.swift")) if path != BASE_FILE}
    family = ui_test_subclasses(files)

    findings = []
    for path, text in files.items():
        declares_subclass = any(name in family and parent in family
                                for name, parent in SUBCLASS.findall(text))
        if not (declares_subclass or EXTENSION.search(text)):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            match = DECLARATION.match(line)
            if match and match["name"] in members and "override" not in match["modifiers"]:
                findings.append((path.relative_to(ROOT), number, match["kind"], match["name"]))

    if not findings:
        print(f"OK — no UI test redefines a PaintUITestCase helper ({len(members)} non-private members).")
        return 0

    print(f"{len(findings)} UI-test declaration(s) named like a PaintUITestCase helper:\n")
    for path, number, kind, name in findings:
        print(f"  {path}:{number}  {kind} {name}  (PaintUITestCase.swift:{members[name]})")
    print("\nUse the base class's helper, extend it there if it is missing something, or — if this one\n"
          "is a different thing — give it a name that says how it differs.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
