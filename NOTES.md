# nov21-budget — SCHEDULER stage 3 (one budget) — worker notes
- Sim: E782351D-8D64-4873-94AD-16FF50C95C8A (nov21-budget, iPad 9). Evidence ~/PaintWork/nov21-budget-evidence/
- Baseline gate at ee0e672d: RED, enter peak 1725 MiB, steady 1248; app 64 MiB before scene.
- Design: Engine/MemoryBudget.swift (shared, 0.48 x app limit = 888 MiB on iPad 9). Entries (shown/current/cache,
  LRU) + Grants (lane answer/soon/later). PixelOps.drawImage renders into buffer, grant lives with pixels.
  VectorRenderCache + flatten memo = uncharged handles; ring frames = charged .current; RasterResidency = share 1/2 + .shown charge.
  hasHeadroom retired -> MemoryBudget.shared.makeRoom / valveAllows / availableOverrideBytes.
  Vector-only flatten passes the canvas memo through (no copy). Bake step runs in .later lane.
- Next: fix MemoryBudgetLogicTests, build, gate, fast tier.
- g9 GREEN at 0.48 (peak 1139, budget peak 887) -> retuned to 0.45 (832 MiB). Running green1..3.
- Fixed along the way: entry deinit deadlock (deinit inside budget lock) -> forget via forgetLock;
  bake waits for room (3 frames) before starting, defers on refusal; ring .current only while playing;
  decoded frames admitted for pixel lifetime; CPU compositor/strip/flat-stack/fill reference -> drawImage.
- Left: fast tier Debug+Release, check scripts, drive draw/Move, TODO/PERFORMANCE/SCHEDULER docs.
- g9..green3 GREEN x3 at 0.48 (1138-1142 peak). mutations A/B all caught. fast tier running.
