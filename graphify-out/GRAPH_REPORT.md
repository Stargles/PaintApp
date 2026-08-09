# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-09)

## Corpus Check
- 149 files · ~354,789 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3799 nodes · 11280 edges · 145 communities (135 shown, 10 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1328 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `00172212`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- VectorEraserHybridLogicTests
- ProjectBackupManager
- .manager
- TimelineRowView
- ColorPickerPanel
- CanvasManager
- bash
- StrokeGeometryLogicTests
- HandleKind
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- VectorStroke
- CanvasManager
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- PointCloudIndex
- Coordinator
- .transparentFormat
- CodingKeys
- StrokeGeometry
- CanvasManager
- CanvasManager
- cels
- MetalFillEngine
- .manager
- CGPoint
- PerfBaselineTests
- .activeCelIndex
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
- Lattice
- CGFloat
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- InterpolationGuideLogicTests
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- .evaluate
- UIKit
- ShapeGeometry
- DeformFactorization
- PerfMonitor
- .makeUIView
- Color
- DabTarget
- Vector Eraser — Design Plan
- LayerStackCell
- ProjectManifest
- SideToolbar
- .restLattice
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- TransformMode
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
- .indices
- CodingKeys
- 5. Carry-overs
- Known Issues
- ActionsMenu
- CanvasManager
- CoreGraphics
- Equatable
- InterpolationEngineDiagnosticsLogicTests
- GuideOverlayView
- View
- XCTest
- DrawingView
- .arched
- Tool
- InterpolateBar
- ShapeOverlayView
- TimedSample
- VECTOR_INTERPOLATION_HANDOFF.md
- parallel_test.sh
- 0. The brief
- .registerGroups
- ShapeDetector
- BackupManagerLogicTests
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- InterpolationRefusal
- 5. Workflow and architecture
- OnionSkinLogicTests
- String
- StructureSnapshot
- TransformOverlaySupport.swift
- SelectPanel
- CutOutcome
- GuidePath
- .withInterpolationUndo
- ProjectVersionsView
- InterpolationRecipe
- InterpolationPreviewKey
- 8. Suggested follow-on work
- SpacingChart
- ARAPLogicTests
- 2. Current state
- VectorFillElement
- run.sh
- 3. Session protocol
- Edge
- ManifestSkeleton
- Atomic
- Vector Interpolation — Handoff & Session Protocol
- LayerStackRow
- Identifiable
- BrushShape
- Layer
- BrushSettingsPanel
- EraserSettingsPanel
- Corner
- InterpolatePanel
- ProjectStore.swift
- VectorScratchRole
- Deterministic
- 3. Three candidate engines
- 12. Open work

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 531 edges
2. `CGFloat` - 402 edges
3. `VectorCanvas` - 116 edges
4. `CanvasManager` - 100 edges
5. `Lattice` - 98 edges
6. `CanvasManager` - 98 edges
7. `layers` - 98 edges
8. `VectorSample` - 97 edges
9. `InterpolationGuideLogicTests` - 90 edges
10. `Coordinator` - 78 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (145 total, 10 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (48): CustomStringConvertible, UIImage, UInt8, Backdrop, fill, image, none, Gesture (+40 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.10
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.06
Nodes (41): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+33 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (41): CanvasManager, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+33 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (7): Intersection, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 9 - "HandleKind"
Cohesion: 0.13
Nodes (15): HandleKind, axisBottom, axisLeft, axisRight, axisTop, cornerBL, cornerBR, cornerTL (+7 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.11
Nodes (18): kind, Bool, CGAffineTransform, CGRect, CGSize, VectorCanvas, .elements, .fills (+10 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 13 - "VectorStroke"
Cohesion: 0.09
Nodes (30): image, DabLattice, .range, ElementData, fill, image, stroke, ImageRef (+22 more)

### Community 14 - "CanvasManager"
Cohesion: 0.09
Nodes (15): CanvasManager, Bool, CGSize, UIImage, CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale (+7 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (24): StrokeInput, TimeInterval, UITouch, UIView, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+16 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.14
Nodes (15): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+7 more)

### Community 19 - "Coordinator"
Cohesion: 0.11
Nodes (17): AppliedTool, Coordinator, CanvasManager, CGSize, Color, Date, Double, NSLayoutConstraint (+9 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.12
Nodes (20): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+12 more)

### Community 21 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 22 - "StrokeGeometry"
Cohesion: 0.15
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 23 - "CanvasManager"
Cohesion: 0.14
Nodes (14): CanvasManager, FloatingPiece, .transformedBounds, FloatingTransform, .affineTransform, Selection, Bool, CGAffineTransform (+6 more)

### Community 24 - "CanvasManager"
Cohesion: 0.12
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 28 - "CGPoint"
Cohesion: 0.14
Nodes (7): CGPoint, .length, LatticeLogicTests, Int, StaticString, String, UInt

### Community 29 - "PerfBaselineTests"
Cohesion: 0.23
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 30 - ".activeCelIndex"
Cohesion: 0.13
Nodes (12): .interpolationTarget, CanvasManager, Bool, Int, Cel, .endFrame, Int, UIImage (+4 more)

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 33 - "CanvasManager"
Cohesion: 0.16
Nodes (14): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+6 more)

### Community 34 - "StrokeSpatialIndex"
Cohesion: 0.19
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 35 - "ViewPreset"
Cohesion: 0.21
Nodes (7): CanvasManager, Int, String, Bool, String, UUID, ViewPreset

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, move (+9 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.07
Nodes (32): Content, Gesture, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight, .dragHandle, .frameLabel (+24 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.12
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 40 - ".load"
Cohesion: 0.11
Nodes (25): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CanvasManager (+17 more)

### Community 41 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+10 more)

### Community 42 - "Lattice"
Cohesion: 0.09
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 43 - "CGFloat"
Cohesion: 0.14
Nodes (17): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Brush, CGFloat (+9 more)

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.23
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 47 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.08
Nodes (26): 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 6.1 What they are, 6.2 The controls from requirement 6 (+18 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.15
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 50 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 51 - "UIKit"
Cohesion: 0.10
Nodes (8): Combine, FloatingPieceKind, duplicate, move, ThumbnailRenderer, PhotosUI, SwiftUI, UIKit

### Community 52 - "ShapeGeometry"
Cohesion: 0.12
Nodes (14): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+6 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - ".makeUIView"
Cohesion: 0.12
Nodes (7): LayerHostView, NSCoder, CanvasView, Context, Coordinator, LayerTransform, UIImageView

### Community 56 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.07
Nodes (29): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 1. The central problem, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions) (+21 more)

### Community 59 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 60 - "ProjectManifest"
Cohesion: 0.14
Nodes (27): LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest, LayerManifest (+19 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - ".restLattice"
Cohesion: 0.12
Nodes (8): ARAPInterpolation, Interpolator, Options, Bool, Int, StaticString, String, UInt

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "TransformMode"
Cohesion: 0.09
Nodes (20): CaseIterable, Kind, line, oval, rectangle, SelectionMode, automatic, .displayName (+12 more)

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, id (+10 more)

### Community 69 - "ShapeDetectorLogicTests"
Cohesion: 0.14
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
Cohesion: 0.08
Nodes (31): IndexPath, NSObject, Coordinator, DropTarget, between, onto, LayerRowModel, .folderID (+23 more)

### Community 74 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.12
Nodes (17): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+9 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.07
Nodes (27): Commit — not a phase, and built between 6 and 7 *(done, Session 17)*, Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Item 1 is done (Session 15, `93b7e02`), Items 2 and 3 are done (Session 16, `ebbaa4a` and the commit after it), Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic) (+19 more)

### Community 77 - ".stampStroke"
Cohesion: 0.11
Nodes (13): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+5 more)

### Community 79 - "CodingKeys"
Cohesion: 0.08
Nodes (26): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+18 more)

### Community 80 - "5. Carry-overs"
Cohesion: 0.07
Nodes (29): 5.10 For Phase 5's motion groups, 5.11 What the papers do — and where they do not help, 5.12 Where a liquify at *t* is stored — §8 item 25's design question, answered, 5.13 "Lasso transform at *t*" — what it turned out to be, and why it is a refusal, 5.14 Commit's fidelity — the decision, and what it costs, 5.15 Run `uptime` before diagnosing a failed full run — it is the cheapest signal and no earlier entry mentions it, 5.16 What the trajectory constraint actually is, and why it is not what §6.1 says, 5.17 One resolver for both the evaluation and the memo — the `InterpolationPreviewKey` rule, generalised (+21 more)

### Community 81 - "Known Issues"
Cohesion: 0.14
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 82 - "ActionsMenu"
Cohesion: 0.12
Nodes (17): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+9 more)

### Community 83 - "CanvasManager"
Cohesion: 0.07
Nodes (26): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+18 more)

### Community 84 - "CoreGraphics"
Cohesion: 0.15
Nodes (7): CoreGraphics, Foundation, LayerTransform, Notification.Name, AppVersion, .versionString, String

### Community 85 - "Equatable"
Cohesion: 0.19
Nodes (12): Equatable, Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval (+4 more)

### Community 86 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 87 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 88 - "View"
Cohesion: 0.19
Nodes (12): GuideRow, .averagingNote, .body, CanvasManager, .body, MotionGroupRow, .body, .colourBakeButton (+4 more)

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 92 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 93 - "InterpolateBar"
Cohesion: 0.11
Nodes (19): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .guideButton, .hasASpacingChart (+11 more)

### Community 94 - "ShapeOverlayView"
Cohesion: 0.14
Nodes (14): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, ShapeOverlayView (+6 more)

### Community 95 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 96 - "VECTOR_INTERPOLATION_HANDOFF.md"
Cohesion: 0.23
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "0. The brief"
Cohesion: 0.40
Nodes (5): 0. The brief, Goal, Key technical & UX edge cases (referenced as "edge case N"), Notes (referenced elsewhere as "requirement N" / "note N"), The workflow, as specified

### Community 99 - ".registerGroups"
Cohesion: 0.25
Nodes (3): GroupRegistration, RegistrationElement, RegistrationFrame

### Community 100 - "ShapeDetector"
Cohesion: 0.19
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 101 - "BackupManagerLogicTests"
Cohesion: 0.18
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 108 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 109 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 110 - "OnionSkinLogicTests"
Cohesion: 0.22
Nodes (6): OnionSkinSource, PreviousCelOnionSkinSource, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 111 - "String"
Cohesion: 0.11
Nodes (13): BrushDynamics, BrushGrain, Bool, Double, UUID, BrushLibrary, .customBrushesDirectory, URL (+5 more)

### Community 112 - "StructureSnapshot"
Cohesion: 0.26
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 113 - "TransformOverlaySupport.swift"
Cohesion: 0.18
Nodes (10): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+2 more)

### Community 114 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 117 - ".withInterpolationUndo"
Cohesion: 0.16
Nodes (11): Layer, String, Void, GroupInterpolation, auto, clean, crossFade, MotionGroup (+3 more)

### Community 118 - "ProjectVersionsView"
Cohesion: 0.47
Nodes (4): ProjectVersionsView, RecentlyDeletedView, .body, Void

### Community 119 - "InterpolationRecipe"
Cohesion: 0.12
Nodes (18): Codable, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, Kind, easeIn, easeInOut (+10 more)

### Community 120 - "InterpolationPreviewKey"
Cohesion: 0.19
Nodes (8): InterpolationPreviewKey, Bool, Int, Layer, Set, UIGestureRecognizer, UIImage, UUID

### Community 121 - "8. Suggested follow-on work"
Cohesion: 0.17
Nodes (12): 8. Suggested follow-on work, From Phase 1, From Phase 2, From Phase 3, From Phase 4, From Phase 4.5 — noticed while working, From Phase 4.5 — the product owner's own list, From Phase 4.6 — the engine does not do what it is supposed to do (+4 more)

### Community 122 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 123 - "ARAPLogicTests"
Cohesion: 0.14
Nodes (9): Group, MotionGrouping, Options, Bool, Int, Set, groups, ARAPLogicTests (+1 more)

### Community 124 - "2. Current state"
Cohesion: 0.50
Nodes (4): 2. Current state, History note, What is done, What is next

### Community 125 - "VectorFillElement"
Cohesion: 0.21
Nodes (10): CodableColor, .uiColor, CGPath, Data, UIColor, VectorFillElement, .cgPath, .uiColor (+2 more)

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

### Community 131 - "Vector Interpolation — Handoff & Session Protocol"
Cohesion: 0.18
Nodes (11): 1. Start-of-session checklist, 4. Build and test, 6. Session log, 7. Handoff prompt template, After changing code, Build only — fastest possible check that it compiles, Fast run — pure logic only (~1–2 min). Use this constantly., Full run (~22 min, 63 XCUITests). Rarely — at phase boundaries only. (+3 more)

### Community 132 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 133 - "Identifiable"
Cohesion: 0.20
Nodes (10): Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+2 more)

### Community 134 - "BrushShape"
Cohesion: 0.22
Nodes (9): BrushShape, custom, .displayName, hardRound, .id, pen, pencil, softRound (+1 more)

### Community 135 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 136 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 137 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 138 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 139 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 140 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 141 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 143 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

### Community 144 - "12. Open work"
Cohesion: 0.40
Nodes (5): 12. Open work, GPU rendering, Per-element Move, Still open, The spatial index is rebuilt from scratch on every `invalidate()`

## Knowledge Gaps
- **597 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+592 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `TimelineRowView`, `CanvasManager`, `StrokeGeometryLogicTests`, `EraserSettingsPanel`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `VectorStroke`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `Deterministic`, `PointCloudIndex`, `Coordinator`, `.transparentFormat`, `CodingKeys`, `StrokeGeometry`, `CanvasManager`, `CanvasManager`, `cels`, `.manager`, `CGPoint`, `PerfBaselineTests`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `AnimationTimeline`, `FloatingPieceOverlayView`, `.load`, `Lattice`, `InterpolationModelLogicTests`, `InterpolationGuideLogicTests`, `RasterLayerTexture`, `.evaluate`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `Color`, `DabTarget`, `LayerStackCell`, `SideToolbar`, `.restLattice`, `TransformMode`, `ShapeDetectorLogicTests`, `LayerRowModel`, `StrokeStabilizer`, `.stampStroke`, `.indices`, `ActionsMenu`, `CanvasManager`, `CoreGraphics`, `InterpolationEngineDiagnosticsLogicTests`, `GuideOverlayView`, `DrawingView`, `.arched`, `InterpolateBar`, `ShapeOverlayView`, `TimedSample`, `.registerGroups`, `ShapeDetector`, `OnionSkinLogicTests`, `String`, `TransformOverlaySupport.swift`, `GuidePath`, `InterpolationRecipe`, `InterpolationPreviewKey`, `SpacingChart`, `ARAPLogicTests`?**
  _High betweenness centrality (0.329) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `Edge`, `VectorEraserHybridLogicTests`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `StrokeGeometryLogicTests`, `HandleKind`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `VectorStroke`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `Coordinator`, `.transparentFormat`, `StrokeGeometry`, `CanvasManager`, `CanvasManager`, `cels`, `.manager`, `PerfBaselineTests`, `.activeCelIndex`, `StrokeSpatialIndex`, `AnimationTimeline`, `FloatingPieceOverlayView`, `Lattice`, `CGFloat`, `ProjectSaveLogicTests`, `InterpolationGuideLogicTests`, `SelectionOverlayView`, `RasterLayerTexture`, `.evaluate`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `DabTarget`, `.restLattice`, `ObjectTransformOverlayView`, `TransformMode`, `ShapeDetectorLogicTests`, `LayerRowModel`, `StrokeStabilizer`, `.stampStroke`, `.indices`, `CanvasManager`, `CoreGraphics`, `InterpolationEngineDiagnosticsLogicTests`, `GuideOverlayView`, `.arched`, `ShapeOverlayView`, `TimedSample`, `.registerGroups`, `ShapeDetector`, `String`, `TransformOverlaySupport.swift`, `GuidePath`, `InterpolationRecipe`, `ARAPLogicTests`?**
  _High betweenness centrality (0.202) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `.manager` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `BackupManagerLogicTests`, `ShapeDetectorLogicTests`, `PlaybackBoundsCharacterizationTests`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `InterpolationModelLogicTests`, `InterpolationGuideLogicTests`, `OnionSkinLogicTests`, `InterpolationRenderLogicTests`, `ProjectSaveLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `cels`, `ARAPLogicTests`, `CGPoint`, `PerfBaselineTests`?**
  _High betweenness centrality (0.078) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `Lattice` (e.g. with `.visible()` and `.registerGroups()`) actually correct?**
  _`Lattice` has 10 INFERRED edges - model-reasoned connections that need verification._