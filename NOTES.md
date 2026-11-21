# nov21-budget — SCHEDULER stage 3 (one budget) — worker notes
- Sim: E782351D-8D64-4873-94AD-16FF50C95C8A (nov21-budget, iPad 9). Evidence ~/PaintWork/nov21-budget-evidence/
- Baseline gate at ee0e672d: RED, enter peak 1725 MiB, steady 1248; app 64 MiB before scene.
- Design: Engine/MemoryBudget.swift (shared, 0.48 x app limit = 888 MiB on iPad 9). Entries (shown/current/cache,
  LRU) + Grants (lane answer/soon/later). PixelOps.drawImage renders into buffer, grant lives with pixels.
  VectorRenderCache + flatten memo = uncharged handles; ring frames = charged .current; RasterResidency = share 1/2 + .shown charge.
  hasHeadroom retired -> MemoryBudget.shared.makeRoom / valveAllows / availableOverrideBytes.
  Vector-only flatten passes the canvas memo through (no copy). Bake step runs in .later lane.
- Next: fix MemoryBudgetLogicTests, build, gate, fast tier.
