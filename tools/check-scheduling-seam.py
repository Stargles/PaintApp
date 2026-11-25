#!/usr/bin/env python3
"""The scheduler's one seam (SCHEDULER_DESIGN.md §2).

1. The core, PaintSoftware/Engine/Scheduling/, is platform-free: no Dispatch, Thread, UIKit, Metal,
   ProcessInfo or sysctl. It carries to another platform with another Executor.
2. Only PaintSoftware/Platform/AppleExecutor.swift may make a queue or fan out across cores
   (`DispatchQueue(`, `concurrentPerform`) — except the files in ALLOWLIST, which spelled them before
   the scheduler existed and move onto it in S3–S7. The list only shrinks: a file that no longer
   needs its entry is reported, so the entry is deleted with the change that freed it.

Exit 0 when clean. Run from the repository root.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE = ROOT / "PaintSoftware/Engine/Scheduling"
SEAM = {"PaintSoftware/Platform/AppleExecutor.swift"}
CORE_FORBIDDEN = re.compile(r"\b(import (Dispatch|UIKit|Metal|QuartzCore|SwiftUI)|DispatchQueue|Thread\b|ProcessInfo|sysctl)")
QUEUE = re.compile(r"DispatchQueue\(|concurrentPerform")
ALLOWLIST = set((ROOT / "tools/scheduling-seam-allowlist.txt").read_text().split())

problems = []
for path in sorted(CORE.glob("*.swift")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        code = line.split("//", 1)[0]
        if CORE_FORBIDDEN.search(code):
            problems.append(f"{path.relative_to(ROOT)}:{number}: the scheduler core must stay platform-free: {line.strip()}")

spellers = set()
for path in sorted((ROOT / "PaintSoftware").rglob("*.swift")):
    relative = str(path.relative_to(ROOT))
    if any(QUEUE.search(line.split("//", 1)[0]) for line in path.read_text().splitlines()):
        spellers.add(relative)
for relative in sorted(spellers - ALLOWLIST - SEAM):
    problems.append(f"{relative}: makes a queue or fans out outside the seam — submit to Scheduler.shared instead")
for relative in sorted(ALLOWLIST - spellers):
    problems.append(f"{relative}: no longer needs its allowlist entry — delete it from tools/scheduling-seam-allowlist.txt")

print("\n".join(problems) if problems else f"scheduling seam: clean ({len(ALLOWLIST)} files still to move onto the scheduler)")
sys.exit(1 if problems else 0)
