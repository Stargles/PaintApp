# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-08)

## Corpus Check
- 148 files · ~342,818 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3692 nodes · 10882 edges · 133 communities (127 shown, 6 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1278 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `dfb19f2f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- ParityScenario
- ProjectBackupManager
- .manager
- TimelineRowView
- ColorPickerPanel
- CanvasManager
- bash
- CGPoint
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- Codable
- CanvasManager
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- PointCloudIndex
- Coordinator
- .transparentFormat
- CodingKeys
- VectorSample
- CanvasManager
- CanvasManager
- cels
- MetalFillEngine
- InterpolationGuideLogicTests
- LatticeLogicTests
- PerfBaselineTests
- layers
- FillParams
- TouchCountRecognizer
- CanvasManager
- StrokeSpatialIndex
- ViewPreset
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- FloatingPieceOverlayView
- .load
- LayerOptionsPanel
- CGFloat
- .attach
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- VectorEraserHybridLogicTests
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- InterpolationEvaluator
- SwiftUI
- ShapeGeometry
- DeformFactorization
- PerfMonitor
- .makeUIView
- Color
- .rgbaPixels
- Vector Eraser — Design Plan
- LayerStackCell
- ProjectManifest
- SideToolbar
- ARAPLogicTests
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- VectorEraserMode
- Refactor baseline (Stage 0)
- CodingKeys
- ShapeDetectorLogicTests
- UndoHistory
- CanvasHostView
- PlaybackBoundsCharacterizationTests
- LayerRowModel
- PaintSoftware - iPad Drawing and Animation App
- StrokeStabilizer
- Vector Interpolation — Implementation Plan
- .stampStroke
- LayerStackListView.Coordinator
- CodingKeys
- 5. Carry-overs
- Known Issues
- EraserSettingsPanel
- CanvasManager
- LayerStackListView
- Equatable
- InterpolationEngineDiagnosticsLogicTests
- GuideOverlayView
- Kind
- UIKit
- DrawingView
- CodingKeys
- Tool
- InterpolateBar
- EndpointHandle
- 1. The central problem
- VECTOR_INTERPOLATION_HANDOFF.md
- parallel_test.sh
- 0. The brief
- 6. Guide strokes
- ShapeDetector
- BackupManagerLogicTests
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- InterpolationRefusal
- 5. Workflow and architecture
- 7. Edge cases from the brief
- BrushBlendMode
- StructureSnapshot
- TransformOverlaySupport.swift
- View
- CutOutcome
- ActionsMenu
- MotionGroup
- GalleryView
- InterpolationRecipe
- InterpolationPreviewKey
- 8. Suggested follow-on work
- MotionGrouping
- Vector Interpolation — Handoff & Session Protocol
- run.sh
- 3. Session protocol
- Edge
- ManifestSkeleton
- Atomic
- 4. Build and test
- .setCanvasPadding
- Corner
- .handlePinch

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 503 edges
2. `CGFloat` - 389 edges
3. `VectorCanvas` - 116 edges
4. `Lattice` - 98 edges
5. `VectorSample` - 97 edges
6. `CanvasManager` - 95 edges
7. `layers` - 89 edges
8. `CanvasManager` - 81 edges
9. `Coordinator` - 77 edges
10. `ShapeGeometry` - 73 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (133 total, 6 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 1 - "ParityScenario"
Cohesion: 0.09
Nodes (34): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+26 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+13 more)

### Community 3 - ".manager"
Cohesion: 0.05
Nodes (24): OnionSkinSource, PreviousCelOnionSkinSource, CanvasFixture, CanvasManager, Int, Layer, StaticString, String (+16 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.06
Nodes (42): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (39): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .hasLoopBoundary (+31 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "CGPoint"
Cohesion: 0.07
Nodes (15): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+7 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.09
Nodes (25): CALayer, CornerHandle, EdgeHandle, HandleInfo, HandleKind, axisBottom, axisLeft, axisRight (+17 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.08
Nodes (9): StaticString, String, UInt, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests (+1 more)

### Community 11 - "VectorCanvas"
Cohesion: 0.07
Nodes (28): Evaluation, Bool, Double, VectorEraser, kind, Kind, fill, image (+20 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.19
Nodes (9): BrushEngineLogicTests, Any, CodableColor, Data, Double, String, T, UIColor (+1 more)

### Community 13 - "Codable"
Cohesion: 0.07
Nodes (41): Codable, ContentProvider, Identifiable, CGSize, UIImage, CodableColor, .uiColor, DabLattice (+33 more)

### Community 14 - "CanvasManager"
Cohesion: 0.21
Nodes (8): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage

### Community 15 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (31): StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+23 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.12
Nodes (16): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+8 more)

### Community 19 - "Coordinator"
Cohesion: 0.11
Nodes (17): AppliedTool, Coordinator, CanvasManager, CGSize, Color, Date, Double, NSLayoutConstraint (+9 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.12
Nodes (20): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+12 more)

### Community 21 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 22 - "VectorSample"
Cohesion: 0.12
Nodes (14): Brush, VectorSample, Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange (+6 more)

### Community 23 - "CanvasManager"
Cohesion: 0.05
Nodes (43): String, UUID, Void, Layer, Bool, Cel, Double, String (+35 more)

### Community 24 - "CanvasManager"
Cohesion: 0.08
Nodes (18): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+10 more)

### Community 25 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "InterpolationGuideLogicTests"
Cohesion: 0.08
Nodes (18): GuidePath, .end, .start, GuideSet, .isEmpty, Bool, CGVector, Int (+10 more)

### Community 28 - "LatticeLogicTests"
Cohesion: 0.16
Nodes (5): LatticeLogicTests, Int, StaticString, String, UInt

### Community 29 - "PerfBaselineTests"
Cohesion: 0.21
Nodes (8): PerfBaselineTests, CanvasManager, Double, Int, String, UIImage, UInt64, VectorStroke

### Community 30 - "layers"
Cohesion: 0.13
Nodes (15): .activeLayerIsVector, .activeCelIsInBetween, .guideRefusal, .interpolationTarget, Bool, CanvasManager, Bool, Int (+7 more)

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 33 - "CanvasManager"
Cohesion: 0.18
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, ClosedRange, Int (+5 more)

### Community 34 - "StrokeSpatialIndex"
Cohesion: 0.17
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 35 - "ViewPreset"
Cohesion: 0.16
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.05
Nodes (43): Content, Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder (+35 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 40 - ".load"
Cohesion: 0.11
Nodes (26): BrushLibrary, .customBrushesDirectory, URL, CelContent, CodableColor, .color, Color, .codable (+18 more)

### Community 41 - "LayerOptionsPanel"
Cohesion: 0.16
Nodes (17): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .header (+9 more)

### Community 42 - "CGFloat"
Cohesion: 0.08
Nodes (23): CGFloat, vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds (+15 more)

### Community 43 - ".attach"
Cohesion: 0.36
Nodes (3): Context, UILongPressGestureRecognizer, UITableView

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 47 - "SelectionOverlayView"
Cohesion: 0.18
Nodes (9): SelectionOverlayView, .isCapturingGestures, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer, UITapGestureRecognizer (+1 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.09
Nodes (22): 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 3. Three candidate engines, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 8. Performance — the real constraint (+14 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 50 - "InterpolationEvaluator"
Cohesion: 0.14
Nodes (18): CGPathElementType, Direction, backward, forward, fromRest, GroupWarp, InterpolationEvaluator, LocalEditPlan (+10 more)

### Community 51 - "SwiftUI"
Cohesion: 0.11
Nodes (9): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, PhotosUI (+1 more)

### Community 52 - "ShapeGeometry"
Cohesion: 0.10
Nodes (15): Int, FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed (+7 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.12
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - ".makeUIView"
Cohesion: 0.12
Nodes (7): LayerHostView, CanvasView, Context, Coordinator, LayerTransform, UIImage, UIImageView

### Community 56 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - ".rgbaPixels"
Cohesion: 0.15
Nodes (10): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor, Int (+2 more)

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.07
Nodes (29): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 12. Open work, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions) (+21 more)

### Community 59 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 60 - "ProjectManifest"
Cohesion: 0.21
Nodes (19): LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest, LayerManifest (+11 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - "ARAPLogicTests"
Cohesion: 0.09
Nodes (11): ARAPInterpolation, Interpolator, Options, Bool, groups, ARAPLogicTests, .rigidMotionL, Int (+3 more)

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, guideStrokes (+11 more)

### Community 69 - "ShapeDetectorLogicTests"
Cohesion: 0.19
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 70 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.17
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 73 - "LayerRowModel"
Cohesion: 0.22
Nodes (11): Coordinator, LayerRowModel, .folderID, CanvasManager, Double, Int, Set, String (+3 more)

### Community 74 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.12
Nodes (17): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+9 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.08
Nodes (26): Commit — not a phase, and built between 6 and 7 *(done, Session 17)*, Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Item 1 is done (Session 15, `93b7e02`), Items 2 and 3 are done (Session 16, `ebbaa4a` and the commit after it), Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic) (+18 more)

### Community 77 - ".stampStroke"
Cohesion: 0.15
Nodes (13): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+5 more)

### Community 78 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (8): IndexPath, DropTarget, between, onto, LayerStackListView.Coordinator, UIView, UISwipeActionsConfiguration, UITableViewDelegate

### Community 79 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+12 more)

### Community 80 - "5. Carry-overs"
Cohesion: 0.07
Nodes (28): 5.10 For Phase 5's motion groups, 5.11 What the papers do — and where they do not help, 5.12 Where a liquify at *t* is stored — §8 item 25's design question, answered, 5.13 "Lasso transform at *t*" — what it turned out to be, and why it is a refusal, 5.14 Commit's fidelity — the decision, and what it costs, 5.15 Run `uptime` before diagnosing a failed full run — it is the cheapest signal and no earlier entry mentions it, 5.16 What the trajectory constraint actually is, and why it is not what §6.1 says, 5.17 One resolver for both the evaluation and the memo — the `InterpolationPreviewKey` rule, generalised (+20 more)

### Community 81 - "Known Issues"
Cohesion: 0.14
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 83 - "CanvasManager"
Cohesion: 0.08
Nodes (21): CanvasManager, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .motionGroupChips, .visibleGuideStrokes (+13 more)

### Community 84 - "LayerStackListView"
Cohesion: 0.29
Nodes (5): .body, LayerStackListView, Coordinator, Void, UIViewRepresentable

### Community 85 - "Equatable"
Cohesion: 0.18
Nodes (13): Equatable, Hashable, Intersection, GuideRole, both, timing, trajectory, GuideStroke (+5 more)

### Community 86 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 87 - "GuideOverlayView"
Cohesion: 0.14
Nodes (9): GuideOverlayView, CGPath, CGRect, NSCoder, UIEvent, Bool, UIEvent, TransformOverlayView (+1 more)

### Community 88 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 89 - "UIKit"
Cohesion: 0.06
Nodes (10): CoreGraphics, Darwin, Foundation, Notification.Name, AppVersion, .versionString, String, ThumbnailRenderer (+2 more)

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, boundGroups, id, interval, role, samples

### Community 92 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 93 - "InterpolateBar"
Cohesion: 0.12
Nodes (18): .body, InterpolateBar, .activeRecipe, .body, .commandRow, .commands, .commitButton, .guideButton (+10 more)

### Community 94 - "EndpointHandle"
Cohesion: 0.67
Nodes (3): EndpointHandle, end, start

### Community 95 - "1. The central problem"
Cohesion: 0.40
Nodes (5): 1. The central problem, Coverage test, `DabLattice` — how a piece reproduces its parent's dabs, Garbage collection, What shipped instead, and why (Phase 4c, measured; split restored in Phase 4d)

### Community 96 - "VECTOR_INTERPOLATION_HANDOFF.md"
Cohesion: 0.23
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "0. The brief"
Cohesion: 0.40
Nodes (5): 0. The brief, Goal, Key technical & UX edge cases (referenced as "edge case N"), Notes (referenced elsewhere as "requirement N" / "note N"), The workflow, as specified

### Community 99 - "6. Guide strokes"
Cohesion: 0.40
Nodes (5): 6.1 What they are, 6.2 The controls from requirement 6, 6.3 The data gap, 6.4 Reuse across frames (requirement 7), 6. Guide strokes

### Community 100 - "ShapeDetector"
Cohesion: 0.25
Nodes (4): ClosedFit, ShapeDetector, Bool, CGRect

### Community 101 - "BackupManagerLogicTests"
Cohesion: 0.15
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 108 - "InterpolationRefusal"
Cohesion: 0.16
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 109 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 110 - "7. Edge cases from the brief"
Cohesion: 0.40
Nodes (5): 7.1 Erasers — mostly already solved, 7.2 Topological mismatch, 7.3 Fills, 7.4 Range interpolation (future), 7. Edge cases from the brief

### Community 111 - "BrushBlendMode"
Cohesion: 0.06
Nodes (28): CaseIterable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+20 more)

### Community 112 - "StructureSnapshot"
Cohesion: 0.23
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 113 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 114 - "View"
Cohesion: 0.14
Nodes (16): MotionGroupRow, .body, .colourBakeButton, .wholeFrameNote, CanvasManager, String, SelectPanel, .body (+8 more)

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 117 - "MotionGroup"
Cohesion: 0.15
Nodes (11): GroupRegistration, RegistrationFrame, Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup (+3 more)

### Community 118 - "GalleryView"
Cohesion: 0.16
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 119 - "InterpolationRecipe"
Cohesion: 0.18
Nodes (11): InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve, Bool (+3 more)

### Community 120 - "InterpolationPreviewKey"
Cohesion: 0.19
Nodes (8): InterpolationPreviewKey, Bool, Int, Layer, Set, UIGestureRecognizer, UIImage, UUID

### Community 121 - "8. Suggested follow-on work"
Cohesion: 0.17
Nodes (12): 8. Suggested follow-on work, From Phase 1, From Phase 2, From Phase 3, From Phase 4, From Phase 4.5 — noticed while working, From Phase 4.5 — the product owner's own list, From Phase 4.6 — the engine does not do what it is supposed to do (+4 more)

### Community 123 - "MotionGrouping"
Cohesion: 0.39
Nodes (5): Group, MotionGrouping, Options, Int, Set

### Community 124 - "Vector Interpolation — Handoff & Session Protocol"
Cohesion: 0.22
Nodes (9): 1. Start-of-session checklist, 2. Current state, 6. Session log, 7. Handoff prompt template, History note, Reading budget, Vector Interpolation — Handoff & Session Protocol, What is done (+1 more)

### Community 127 - "3. Session protocol"
Cohesion: 0.29
Nodes (7): 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol, Model and effort, per task shape

### Community 128 - "Edge"
Cohesion: 0.25
Nodes (5): Edge, bottom, left, right, top

### Community 129 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 130 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 131 - "4. Build and test"
Cohesion: 0.33
Nodes (6): 4. Build and test, After changing code, Build only — fastest possible check that it compiles, Fast run — pure logic only (~1–2 min). Use this constantly., Full run (~22 min, 63 XCUITests). Rarely — at phase boundaries only., Reading a failure

### Community 132 - ".setCanvasPadding"
Cohesion: 0.33
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 138 - "Corner"
Cohesion: 0.22
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 139 - ".handlePinch"
Cohesion: 0.29
Nodes (3): Bool, UIGestureRecognizer, UIPinchGestureRecognizer

## Knowledge Gaps
- **588 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+583 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `ParityScenario`, `.manager`, `.setCanvasPadding`, `TimelineRowView`, `CanvasManager`, `CGPoint`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `Codable`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `Coordinator`, `.transparentFormat`, `CodingKeys`, `VectorSample`, `CanvasManager`, `CanvasManager`, `cels`, `InterpolationGuideLogicTests`, `LatticeLogicTests`, `PerfBaselineTests`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `AnimationTimeline`, `FloatingPieceOverlayView`, `.load`, `InterpolationModelLogicTests`, `VectorEraserHybridLogicTests`, `RasterLayerTexture`, `InterpolationEvaluator`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `Color`, `.rgbaPixels`, `LayerStackCell`, `SideToolbar`, `ARAPLogicTests`, `ShapeDetectorLogicTests`, `LayerRowModel`, `StrokeStabilizer`, `.stampStroke`, `LayerStackListView.Coordinator`, `EraserSettingsPanel`, `CanvasManager`, `Equatable`, `InterpolationEngineDiagnosticsLogicTests`, `GuideOverlayView`, `Kind`, `DrawingView`, `InterpolateBar`, `ShapeDetector`, `BrushBlendMode`, `TransformOverlaySupport.swift`, `ActionsMenu`, `MotionGroup`, `InterpolationRecipe`, `InterpolationPreviewKey`, `MotionGrouping`?**
  _High betweenness centrality (0.293) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `Edge`, `ParityScenario`, `.setCanvasPadding`, `ColorPickerPanel`, `CanvasManager`, `TimelineRowView`, `ShapeOverlayView`, `Corner`, `VectorEraserLogicTests`, `VectorCanvas`, `Codable`, `CanvasManager`, `StrokeCanvasView`, `BrushEngineLogicTests`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `Coordinator`, `.transparentFormat`, `VectorSample`, `CanvasManager`, `CanvasManager`, `cels`, `InterpolationGuideLogicTests`, `LatticeLogicTests`, `PerfBaselineTests`, `layers`, `StrokeSpatialIndex`, `AnimationTimeline`, `FloatingPieceOverlayView`, `CGFloat`, `InterpolationModelLogicTests`, `ProjectSaveLogicTests`, `VectorEraserHybridLogicTests`, `SelectionOverlayView`, `RasterLayerTexture`, `InterpolationEvaluator`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `.rgbaPixels`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `ShapeDetectorLogicTests`, `StrokeStabilizer`, `.stampStroke`, `LayerStackListView.Coordinator`, `CanvasManager`, `Equatable`, `InterpolationEngineDiagnosticsLogicTests`, `GuideOverlayView`, `UIKit`, `ShapeDetector`, `BrushBlendMode`, `TransformOverlaySupport.swift`, `MotionGroup`, `InterpolationRecipe`, `MotionGrouping`?**
  _High betweenness centrality (0.220) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `.setCanvasPadding`, `VectorSample`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `layers`, `CanvasManager`, `ViewPreset`, `CGFloat`, `RasterLayerTexture`, `SwiftUI`, `ShapeGeometry`, `PerfMonitor`, `ProjectManifest`, `VectorEraserMode`, `UndoHistory`, `Equatable`, `Tool`, `StructureSnapshot`, `MotionGroup`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `Lattice` (e.g. with `.visible()` and `.registerGroups()`) actually correct?**
  _`Lattice` has 10 INFERRED edges - model-reasoned connections that need verification._