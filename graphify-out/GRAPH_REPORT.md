# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-05)

## Corpus Check
- 145 files · ~322,159 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3571 nodes · 10499 edges · 129 communities (122 shown, 7 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1298 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `f2fced52`
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
- StrokeGeometryLogicTests
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- VectorStroke
- CanvasManager
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- ARAPLogicTests
- Coordinator
- .transparentFormat
- CodingKeys
- CGFloat
- String
- CanvasManager
- cels
- MetalFillEngine
- VectorElement
- VectorEraserHybridLogicTests
- PerfBaselineTests
- layers
- FillParams
- TouchCountRecognizer
- CanvasManager
- StrokeSpatialIndex
- .withStructureUndo
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- FloatingPieceOverlayView
- .load
- LayerOptionsPanel
- Lattice
- LayerRowModel
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- Identifiable
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- Foundation
- UIKit
- ShapeGeometry
- DeformFactorization
- PerfMonitor
- .makeUIView
- Color
- .stampCircle
- Vector Eraser — Design Plan
- LayerStackCell
- Codable
- SideToolbar
- .restLattice
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- VectorEraserMode
- Refactor baseline (Stage 0)
- CodingKeys
- CodingKeys
- UndoHistory
- CanvasHostView
- PlaybackBoundsCharacterizationTests
- Coordinator
- PaintSoftware - iPad Drawing and Animation App
- StrokeStabilizer
- Vector Interpolation — Implementation Plan
- .stampStroke
- LayerStackListView.Coordinator
- View
- 5. Carry-overs
- Known Issues
- EraserSettingsPanel
- CanvasManager
- LayerStackListView
- Equatable
- CGPoint
- DabLattice
- 12. Open work
- CoreGraphics
- DrawingView
- CopiedCel
- Kind
- InterpolateBar
- Layer
- LayerStackRow
- VECTOR_INTERPOLATION_HANDOFF.md
- parallel_test.sh
- ProjectStore.swift
- VectorScratchRole
- CodingKeys
- BackupManagerLogicTests
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- 5. Workflow and architecture
- 0. The brief
- TransformOverlaySupport.swift
- CutOutcome
- ActionsMenu
- GalleryView
- InterpolationRecipe
- InterpolationPreviewKey
- 8. Suggested follow-on work
- BrushSettingsPanel
- .analyse
- Vector Interpolation — Handoff & Session Protocol
- run.sh
- 3. Session protocol
- ManifestSkeleton
- Atomic
- 4. Build and test
- main.swift
- InterpolatePanel
- 3. Three candidate engines
- .init

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 479 edges
2. `CGFloat` - 373 edges
3. `VectorCanvas` - 116 edges
4. `Lattice` - 98 edges
5. `VectorSample` - 96 edges
6. `CanvasManager` - 95 edges
7. `layers` - 84 edges
8. `Coordinator` - 75 edges
9. `ShapeGeometry` - 73 edges
10. `CanvasManager` - 72 edges

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

## Communities (129 total, 7 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

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
Cohesion: 0.06
Nodes (44): Hashable, CelLocation, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+36 more)

### Community 6 - "CanvasManager"
Cohesion: 0.06
Nodes (30): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .hasLoopBoundary (+22 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (7): Intersection, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 9 - "ShapeOverlayView"
Cohesion: 0.07
Nodes (30): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+22 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (7): VectorEraser, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.09
Nodes (15): Brush, Void, Double, Bool, CGAffineTransform, CGRect, CGSize, LayerTransform (+7 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 13 - "VectorStroke"
Cohesion: 0.09
Nodes (29): CodableColor, .uiColor, ElementData, fill, image, stroke, ImageRef, RenderQuality (+21 more)

### Community 14 - "CanvasManager"
Cohesion: 0.09
Nodes (15): CanvasManager, Bool, CGSize, UIImage, CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale (+7 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.12
Nodes (20): StrokeInput, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas, Bool (+12 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.07
Nodes (32): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+24 more)

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "ARAPLogicTests"
Cohesion: 0.09
Nodes (17): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+9 more)

### Community 19 - "Coordinator"
Cohesion: 0.11
Nodes (17): AppliedTool, Coordinator, CanvasManager, CGSize, Color, Date, Double, NSLayoutConstraint (+9 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.12
Nodes (20): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+12 more)

### Community 21 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, brush, color, composite, elements, fill, fills, id (+10 more)

### Community 22 - "CGFloat"
Cohesion: 0.12
Nodes (15): CGFloat, VectorSample, Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange (+7 more)

### Community 23 - "String"
Cohesion: 0.06
Nodes (41): CaseIterable, Kind, line, oval, rectangle, String, UUID, Void (+33 more)

### Community 24 - "CanvasManager"
Cohesion: 0.12
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "VectorElement"
Cohesion: 0.14
Nodes (18): image, kind, Kind, fill, image, stroke, Int, UIImage (+10 more)

### Community 28 - "VectorEraserHybridLogicTests"
Cohesion: 0.13
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.22
Nodes (8): BrushStamper, PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 30 - "layers"
Cohesion: 0.18
Nodes (11): .activeLayerIsVector, .interpolationTarget, CanvasManager, Bool, Int, Cel, .endFrame, Int (+3 more)

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 33 - "CanvasManager"
Cohesion: 0.18
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+5 more)

### Community 34 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 35 - ".withStructureUndo"
Cohesion: 0.08
Nodes (21): UUID, CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager (+13 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.07
Nodes (32): Content, Gesture, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight, .dragHandle, .frameLabel (+24 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.17
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 40 - ".load"
Cohesion: 0.19
Nodes (16): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CanvasManager (+8 more)

### Community 41 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+10 more)

### Community 42 - "Lattice"
Cohesion: 0.06
Nodes (25): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+17 more)

### Community 43 - "LayerRowModel"
Cohesion: 0.21
Nodes (8): LayerRowModel, .folderID, Bool, Double, String, UIImage, UILongPressGestureRecognizer, UIPinchGestureRecognizer

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.21
Nodes (8): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "Identifiable"
Cohesion: 0.07
Nodes (27): Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+19 more)

### Community 47 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.08
Nodes (26): 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 6.1 What they are, 6.2 The controls from requirement 6 (+18 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 50 - "Foundation"
Cohesion: 0.13
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 51 - "UIKit"
Cohesion: 0.14
Nodes (7): Combine, Darwin, ThumbnailRenderer, PhotosUI, QuartzCore, SwiftUI, UIKit

### Community 52 - "ShapeGeometry"
Cohesion: 0.05
Nodes (32): ClosedFit, ShapeDetector, Bool, CGRect, Int, Corner, bottomLeft, bottomRight (+24 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.12
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 55 - ".makeUIView"
Cohesion: 0.14
Nodes (7): LayerHostView, NSCoder, CanvasView, Context, Coordinator, LayerTransform, UIImageView

### Community 56 - "Color"
Cohesion: 0.18
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - ".stampCircle"
Cohesion: 0.26
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.07
Nodes (29): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 1. The central problem, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions) (+21 more)

### Community 59 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 60 - "Codable"
Cohesion: 0.22
Nodes (20): Codable, LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest (+12 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - ".restLattice"
Cohesion: 0.12
Nodes (10): ARAPInterpolation, Interpolator, Options, Bool, .triangles, LatticeTriangle, Int, StaticString (+2 more)

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

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

### Community 69 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 70 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.17
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 73 - "Coordinator"
Cohesion: 0.32
Nodes (6): Coordinator, CanvasManager, Int, Set, UUID, UITableViewDiffableDataSource

### Community 74 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.12
Nodes (17): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+9 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.08
Nodes (24): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Item 1 is done (Session 15, `93b7e02`), Items 2 and 3 are done (Session 16, `ebbaa4a` and the commit after it), Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert) (+16 more)

### Community 77 - ".stampStroke"
Cohesion: 0.16
Nodes (11): AnyObject, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 78 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UIView, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 79 - "View"
Cohesion: 0.13
Nodes (17): .body, MotionGroupRow, .body, .colourBakeButton, .wholeFrameNote, CanvasManager, String, SelectPanel (+9 more)

### Community 80 - "5. Carry-overs"
Cohesion: 0.09
Nodes (22): 5.10 For Phase 5's motion groups, 5.11 What the papers do — and where they do not help, 5.12 Where a liquify at *t* is stored — §8 item 25's design question, answered, 5.13 "Lasso transform at *t*" — what it turned out to be, and why it is a refusal, 5.7 The lattice encoding — *answered, kept for the constraint*, 5.8 For Phase 3's evaluator, 5.9 For Phase 4's UI, 5. Carry-overs (+14 more)

### Community 81 - "Known Issues"
Cohesion: 0.14
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 83 - "CanvasManager"
Cohesion: 0.05
Nodes (42): CanvasManager, .activeCelIsInBetween, .hasAnonymousWholeFrameGroup, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .motionGroupChips, GroupRegistration (+34 more)

### Community 84 - "LayerStackListView"
Cohesion: 0.20
Nodes (7): IndexPath, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView

### Community 85 - "Equatable"
Cohesion: 0.18
Nodes (13): Equatable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+5 more)

### Community 86 - "CGPoint"
Cohesion: 0.19
Nodes (7): CGPoint, .length, .point, .rigidMotionL, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 87 - "DabLattice"
Cohesion: 0.60
Nodes (3): DabLattice, .range, ClosedRange

### Community 88 - "12. Open work"
Cohesion: 0.40
Nodes (5): 12. Open work, GPU rendering, Per-element Move, Still open, The spatial index is rebuilt from scratch on every `invalidate()`

### Community 89 - "CoreGraphics"
Cohesion: 0.08
Nodes (3): CoreGraphics, LayerTransform, XCTest

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 92 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 93 - "InterpolateBar"
Cohesion: 0.14
Nodes (15): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .referenceButton, .referenceSummary, .removeButton (+7 more)

### Community 94 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 95 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 96 - "VECTOR_INTERPOLATION_HANDOFF.md"
Cohesion: 0.23
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 99 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 100 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKey, CodingKeys, boundGroups, id, interval, role, samples, CodingKeys (+11 more)

### Community 101 - "BackupManagerLogicTests"
Cohesion: 0.17
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 109 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 110 - "0. The brief"
Cohesion: 0.40
Nodes (5): 0. The brief, Goal, Key technical & UX edge cases (referenced as "edge case N"), Notes (referenced elsewhere as "requirement N" / "note N"), The workflow, as specified

### Community 113 - "TransformOverlaySupport.swift"
Cohesion: 0.18
Nodes (10): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+2 more)

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 118 - "GalleryView"
Cohesion: 0.16
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 119 - "InterpolationRecipe"
Cohesion: 0.18
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 120 - "InterpolationPreviewKey"
Cohesion: 0.17
Nodes (8): InterpolationPreviewKey, Bool, Int, Layer, Set, UIGestureRecognizer, UIImage, UUID

### Community 121 - "8. Suggested follow-on work"
Cohesion: 0.18
Nodes (11): 8. Suggested follow-on work, From Phase 1, From Phase 2, From Phase 3, From Phase 4, From Phase 4.5 — noticed while working, From Phase 4.5 — the product owner's own list, From Phase 4.6 — the engine does not do what it is supposed to do (+3 more)

### Community 122 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 123 - ".analyse"
Cohesion: 0.29
Nodes (6): Group, MotionGrouping, Options, Bool, Int, Set

### Community 124 - "Vector Interpolation — Handoff & Session Protocol"
Cohesion: 0.22
Nodes (9): 1. Start-of-session checklist, 2. Current state, 6. Session log, 7. Handoff prompt template, History note, Reading budget, Vector Interpolation — Handoff & Session Protocol, What is done (+1 more)

### Community 127 - "3. Session protocol"
Cohesion: 0.29
Nodes (7): 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol, Model and effort, per task shape

### Community 129 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 130 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 131 - "4. Build and test"
Cohesion: 0.33
Nodes (6): 4. Build and test, After changing code, Build only — fastest possible check that it compiles, Fast run — pure logic only (~1–2 min). Use this constantly., Full run (~22 min, 63 XCUITests). Rarely — at phase boundaries only., Reading a failure

### Community 133 - "main.swift"
Cohesion: 0.33
Nodes (6): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int

### Community 135 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 137 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

## Knowledge Gaps
- **571 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+566 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `ParityScenario`, `.manager`, `TimelineRowView`, `main.swift`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `VectorStroke`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `ARAPLogicTests`, `Coordinator`, `.transparentFormat`, `String`, `CanvasManager`, `cels`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `AnimationTimeline`, `FloatingPieceOverlayView`, `.load`, `Lattice`, `InterpolationModelLogicTests`, `Identifiable`, `RasterLayerTexture`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `Color`, `.stampCircle`, `LayerStackCell`, `SideToolbar`, `.restLattice`, `ObjectTransformOverlayView`, `Coordinator`, `StrokeStabilizer`, `.stampStroke`, `EraserSettingsPanel`, `CanvasManager`, `LayerStackListView`, `Equatable`, `CGPoint`, `DabLattice`, `CoreGraphics`, `DrawingView`, `Kind`, `InterpolateBar`, `TransformOverlaySupport.swift`, `ActionsMenu`, `InterpolationRecipe`, `InterpolationPreviewKey`, `.analyse`?**
  _High betweenness centrality (0.264) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `ParityScenario`, `TimelineRowView`, `main.swift`, `CanvasManager`, `ColorPickerPanel`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `ARAPLogicTests`, `Coordinator`, `.transparentFormat`, `CGFloat`, `String`, `CanvasManager`, `cels`, `VectorElement`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `layers`, `StrokeSpatialIndex`, `AnimationTimeline`, `FloatingPieceOverlayView`, `Lattice`, `InterpolationModelLogicTests`, `ProjectSaveLogicTests`, `Identifiable`, `SelectionOverlayView`, `RasterLayerTexture`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `.stampCircle`, `.restLattice`, `ObjectTransformOverlayView`, `StrokeStabilizer`, `.stampStroke`, `LayerStackListView.Coordinator`, `CanvasManager`, `Equatable`, `CoreGraphics`, `TransformOverlaySupport.swift`, `InterpolationRecipe`, `.analyse`?**
  _High betweenness centrality (0.217) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `ColorPickerPanel`, `VectorCanvas`, `CanvasManager`, `CGFloat`, `String`, `CanvasManager`, `MetalFillEngine`, `layers`, `.withStructureUndo`, `RasterLayerTexture`, `UIKit`, `ShapeGeometry`, `PerfMonitor`, `Codable`, `VectorEraserMode`, `UndoHistory`, `CanvasManager`, `Equatable`, `CopiedCel`, `InterpolationRecipe`?**
  _High betweenness centrality (0.109) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `Lattice` (e.g. with `.visible()` and `.registerGroups()`) actually correct?**
  _`Lattice` has 10 INFERRED edges - model-reasoned connections that need verification._