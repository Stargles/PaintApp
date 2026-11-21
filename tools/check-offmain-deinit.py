#!/usr/bin/env python3
"""No engine object may wait for the main thread to be freed.

    tools/check-offmain-deinit.py <path to PaintSoftware.app>

The app builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, under which a class with no `deinit`
of its own gets an *isolated* one: let go of on a render, bake or fill queue, its deinit is queued
onto the main actor (`swift_task_deinitOnExecutor`) and everything it holds stays allocated until the
main thread runs it. MEASURED 2026-11-21 on the owner's playcheck: six fill sessions' GPU buffers
waiting on a main thread busy with Undo took the app to 2,292 MiB, past the iPad 9's 1,850 MiB.

The test target cannot see this — it compiles the same sources without that isolation default — so
this reads the built app itself: every `__deallocating_deinit` that calls `swift_task_deinitOnExecutor`
is listed, and any of the types below fails the check (declare it `nonisolated`). They are the ones
that hold canvas-sized pictures, GPU buffers or decoded frames and are let go of off the main thread;
a type added to that family is added here. Exit 0 when clean.
"""
import os, subprocess, sys

HEAVY = {
    "VectorCanvas", "StreamPicture", "BoundsDabTarget", "MetalFillSession", "DecodedFrameRing",
    "CelContentPicture", "RasterSurface", "ResolvedMask", "MaskCache", "RasterizeCache",
    "CGContextDabTarget", "PosedDabTarget", "CollectingDabTarget", "ScratchTexturePool", "Capture",
    "FillRenderResult", "CelBand", "UploadCache", "DabImageCache", "DabGradientCache",
    "StrokeSpatialIndex", "FrameBakeStore", "Root", "WeakRoot", "Residency", "LiquifyField", "StrokeScratch",
}
app = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__)
binary = next((p for p in (os.path.join(app, "PaintSoftware.debug.dylib"), os.path.join(app, "PaintSoftware"))
               if os.path.exists(p)), None) or sys.exit(f"no binary in {app}")

hopping, current = set(), None
for line in subprocess.run(["otool", "-tV", binary], capture_output=True, text=True).stdout.splitlines():
    if line.endswith(":") and not line.startswith(("\t", " ")):
        current = line[:-1]
    elif current and current.endswith("CfD") and "swift_task_deinitOnExecutor" in line:
        hopping.add(current)
names = subprocess.run(["xcrun", "swift-demangle", "--simplified"], input="\n".join(sorted(hopping)),
                       capture_output=True, text=True).stdout.split()
types = {n.split(".__deallocating_deinit")[0].split(".")[-1] for n in names if "__deallocating_deinit" in n}

bad = sorted(types & HEAVY)
for t in bad:
    print(f"`{t}` frees its memory on the main thread only — declare it `nonisolated`")
print(f"check-offmain-deinit: {len(types)} types hop to main for their deinit, {len(bad)} of them heavy")
sys.exit(1 if bad else 0)
