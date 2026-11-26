# S2 worker notes (delete before merge)
sim: see ~/PaintWork/s2.udid
## Findings
- Q2 premise refuted: FrameBakeKey encodes residencyID (UUID() per instance) + version counters => keys do not survive a launch.
## Done
- v2 store (BakeFile.swift tiles+half level), BakeDiskLimit, level-aware baker/ring/canvas, under-picture in belowView at rest; logic tests green (t2: 299 tests 0 failed)
- KeptBakes.swift written (not wired yet): kept set = <Projects>/.bakes.nosync/<id>/<res>/<manifest-token>/<frame>.pbk, adopt (clonefile+digest patch) at first baker after load, promote at save
## Next
(done 1,2,4) 1 format v2 (FrameBakeStore tiles+levels) 2 level-aware ring/baker/canvas 3 under-picture 4 disk limit 5 keep setting
