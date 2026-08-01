# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-01)

## Corpus Check
- 140 files · ~270,477 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3350 nodes · 9508 edges · 126 communities (120 shown, 6 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1190 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `1685b2be`
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
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- ShapeGeometry
- SelectionMode
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- PointCloudIndex
- CGPoint
- .transparentFormat
- CodingKeys
- BackupManagerLogicTests
- CanvasManager
- CanvasManager
- InterpolationWorkflowLogicTests
- MetalFillEngine
- CGFloat
- .stampStroke
- PerfBaselineTests
- layers
- FillParams
- TouchCountRecognizer
- CanvasManager
- VectorSample
- LayerFolder
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- FloatingPieceOverlayView
- .load
- View
- Lattice
- LayerStackCell
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- InterpolationRecipe
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- DabTarget
- UIKit
- StrokeGeometry
- DeformFactorization
- PerfMonitor
- CodingKeys
- Color
- Coordinator
- Vector Eraser — Design Plan
- LayerRowModel
- Codable
- SideToolbar
- ARAPLogicTests
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- ShapeDetectorLogicTests
- Refactor baseline (Stage 0)
- CanvasManager
- VectorFillElement
- UndoHistory
- CanvasHostView
- PlaybackBoundsCharacterizationTests
- ShapeDetector
- PaintSoftware - iPad Drawing and Animation App
- StrokeStabilizer
- Vector Interpolation — Implementation Plan
- samples
- GalleryView
- SelectPanel
- 5. Carry-overs
- Known Issues
- InterpolatePanel
- CanvasManager
- 5. Workflow and architecture
- Equatable
- VectorEraserMode
- MotionGroup
- EraserSettingsPanel
- CoreGraphics
- DrawingView
- Identifiable
- .withStructureUndo
- InterpolateBar
- String
- Atomic
- VECTOR_INTERPOLATION_HANDOFF.md
- parallel_test.sh
- LayerStackRow
- ManifestSkeleton
- CodingKeys
- .setUpGestures
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- VectorImageElement
- Edge
- .group
- 11. Moving vector rendering to the GPU
- BrushSettingsPanel
- TransformOverlaySupport.swift
- 1. The central problem
- CutOutcome
- ActionsMenu
- 0. The brief
- PaintApp
- Kind
- CodingKeys
- ProjectStore.swift
- 7. Edge cases from the brief
- Tool
- AppVersion
- AppliedTool

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 394 edges
2. `CGFloat` - 336 edges
3. `VectorCanvas` - 112 edges
4. `CanvasManager` - 95 edges
5. `VectorSample` - 94 edges
6. `Lattice` - 89 edges
7. `Coordinator` - 74 edges
8. `ShapeGeometry` - 73 edges
9. `layers` - 72 edges
10. `Brush` - 64 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  PaintSoftware/PaintApp.swift → PaintSoftware/ContentView.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (126 total, 6 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.05
Nodes (52): CaseIterable, CustomStringConvertible, UUID, Kind, line, oval, rectangle, Backdrop (+44 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+13 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.06
Nodes (43): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+35 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 6 - "CanvasManager"
Cohesion: 0.06
Nodes (33): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .effectiveLoopRange, .hasLoopBoundary, .isFillInAdjustableState, .isShapeFollowingFinger (+25 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (8): Intersection, Deterministic, StrokeGeometryLogicTests, .ramp, StaticString, String, UInt, UInt64

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (28): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+20 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.12
Nodes (7): CGRect, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.10
Nodes (21): kind, transform, Bool, CGAffineTransform, CGRect, CGSize, VectorCanvas, .elements (+13 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 13 - "ShapeGeometry"
Cohesion: 0.09
Nodes (19): Corner, bottomLeft, bottomRight, topLeft, topRight, FollowFrame, ShapeGeometry, .boundingRect (+11 more)

### Community 14 - "SelectionMode"
Cohesion: 0.16
Nodes (11): CanvasManager, Bool, CGSize, UIImage, SelectionMode, automatic, .displayName, .id (+3 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (22): StrokeInput, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+14 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.08
Nodes (30): CGPathElementType, ContentProvider, Direction, backward, forward, Evaluation, GroupWarp, InterpolationEvaluator (+22 more)

### Community 17 - "ContentView"
Cohesion: 0.20
Nodes (9): AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager, MainActor (+1 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.16
Nodes (13): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+5 more)

### Community 19 - "CGPoint"
Cohesion: 0.13
Nodes (8): CGPoint, .length, .point, LatticeLogicTests, Int, StaticString, String, UInt

### Community 20 - ".transparentFormat"
Cohesion: 0.11
Nodes (20): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+12 more)

### Community 21 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, brush, color, composite, elements, fill, fills, id (+10 more)

### Community 22 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 23 - "CanvasManager"
Cohesion: 0.07
Nodes (31): Void, Layer, Bool, Cel, Double, String, UIImage, UUID (+23 more)

### Community 24 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "InterpolationWorkflowLogicTests"
Cohesion: 0.11
Nodes (16): cels, InterpolationReferenceOnionSkinSource, OnionSkinSource, PreviousCelOnionSkinSource, InterpolationWorkflowLogicTests, CanvasManager, Cel, Int (+8 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "CGFloat"
Cohesion: 0.16
Nodes (8): Brush, CGFloat, Sweep, Bool, ClosedRange, Double, VectorEraser, .fixedBrush

### Community 28 - ".stampStroke"
Cohesion: 0.16
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.23
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 30 - "layers"
Cohesion: 0.18
Nodes (10): .activeLayerIsVector, CanvasManager, Bool, Int, Cel, .endFrame, Int, UIImage (+2 more)

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 33 - "CanvasManager"
Cohesion: 0.19
Nodes (12): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, ClosedRange, Int (+4 more)

### Community 34 - "VectorSample"
Cohesion: 0.19
Nodes (11): Int64, VectorSample, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect (+3 more)

### Community 35 - "LayerFolder"
Cohesion: 0.11
Nodes (14): CanvasManager, .activeViewName, Int, String, LayerFolder, Bool, String, UUID (+6 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, interpolate (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.07
Nodes (32): Content, Gesture, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight, .dragHandle, .frameLabel (+24 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 40 - ".load"
Cohesion: 0.17
Nodes (18): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CanvasManager (+10 more)

### Community 41 - "View"
Cohesion: 0.17
Nodes (18): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .header (+10 more)

### Community 42 - "Lattice"
Cohesion: 0.09
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 43 - "LayerStackCell"
Cohesion: 0.11
Nodes (11): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+3 more)

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (14): InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit (+6 more)

### Community 47 - "SelectionOverlayView"
Cohesion: 0.18
Nodes (9): SelectionOverlayView, .isCapturingGestures, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer, UITapGestureRecognizer (+1 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.07
Nodes (27): 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 3. Three candidate engines, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 6.1 What they are (+19 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 50 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 51 - "UIKit"
Cohesion: 0.10
Nodes (9): Combine, Darwin, FloatingPieceKind, duplicate, move, ThumbnailRenderer, PhotosUI, SwiftUI (+1 more)

### Community 52 - "StrokeGeometry"
Cohesion: 0.15
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 53 - "DeformFactorization"
Cohesion: 0.09
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, guideStrokes (+11 more)

### Community 56 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "Coordinator"
Cohesion: 0.09
Nodes (18): LayerHostView, CanvasView, Coordinator, InterpolationPreviewKey, Bool, CanvasManager, Context, Coordinator (+10 more)

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.09
Nodes (23): 10. Open items (not blocking Phase 0–1), 12. Open work, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions), 3.2 `StrokeSpatialIndex` (+15 more)

### Community 59 - "LayerRowModel"
Cohesion: 0.08
Nodes (30): IndexPath, .body, Coordinator, DropTarget, between, onto, LayerRowModel, .folderID (+22 more)

### Community 60 - "Codable"
Cohesion: 0.22
Nodes (20): Codable, LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest (+12 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - "ARAPLogicTests"
Cohesion: 0.16
Nodes (5): ARAPInterpolation, ARAPLogicTests, StaticString, String, UInt

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "ShapeDetectorLogicTests"
Cohesion: 0.16
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 69 - "VectorFillElement"
Cohesion: 0.12
Nodes (21): CodableColor, .uiColor, DabLattice, .range, StrokeComposite, erase, paint, CGPath (+13 more)

### Community 70 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.17
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 73 - "ShapeDetector"
Cohesion: 0.19
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 74 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.12
Nodes (17): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+9 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.12
Nodes (17): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4 — Interpolate mode UI, references, slider, Generate — *first usable milestone* (+9 more)

### Community 78 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 79 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 80 - "5. Carry-overs"
Cohesion: 0.05
Nodes (40): 1. Start-of-session checklist, 2. Current state, 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol (+32 more)

### Community 81 - "Known Issues"
Cohesion: 0.14
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 82 - "InterpolatePanel"
Cohesion: 0.11
Nodes (16): .panelView, FillSettingsPanel, .body, CanvasManager, Color, InterpolatePanel, .activeRecipe, .body (+8 more)

### Community 83 - "CanvasManager"
Cohesion: 0.12
Nodes (11): CanvasManager, .interpolationContentProvider, .interpolationKeyframes, Bool, Cel, Int, Set, UIImage (+3 more)

### Community 84 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 85 - "Equatable"
Cohesion: 0.18
Nodes (15): Equatable, Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval (+7 more)

### Community 86 - "VectorEraserMode"
Cohesion: 0.12
Nodes (15): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized (+7 more)

### Community 87 - "MotionGroup"
Cohesion: 0.13
Nodes (17): InterpolationRefusal, .message, notAVectorLayer, notEnoughReferences, referencesAreEmpty, reprojectNotImplemented, targetIsAReference, CodableColor (+9 more)

### Community 88 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 89 - "CoreGraphics"
Cohesion: 0.09
Nodes (5): CoreGraphics, Foundation, LayerTransform, Notification.Name, XCTest

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "Identifiable"
Cohesion: 0.07
Nodes (27): Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+19 more)

### Community 92 - ".withStructureUndo"
Cohesion: 0.13
Nodes (9): .currentFrame, .currentLayerIndex, Bool, CanvasManager, StructureSnapshot, Int, Layer, String (+1 more)

### Community 93 - "InterpolateBar"
Cohesion: 0.14
Nodes (15): .body, InterpolateBar, .activeRecipe, .body, .referenceButton, .referenceSummary, .status, .targetCelIsEmpty (+7 more)

### Community 94 - "String"
Cohesion: 0.14
Nodes (16): ElementData, fill, image, stroke, ImageRef, Kind, fill, image (+8 more)

### Community 95 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 96 - "VECTOR_INTERPOLATION_HANDOFF.md"
Cohesion: 0.23
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 99 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 100 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKey, CodingKeys, boundGroups, id, interval, role, samples, CodingKeys (+11 more)

### Community 101 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 108 - "VectorImageElement"
Cohesion: 0.23
Nodes (7): RenderQuality, full, preview, CGContext, LayerTransform, UIImage, VectorImageElement

### Community 109 - "Edge"
Cohesion: 0.25
Nodes (5): Edge, bottom, left, right, top

### Community 110 - ".group"
Cohesion: 0.18
Nodes (7): Group, MotionGrouping, Options, Int, Set, groups, Int

### Community 111 - "11. Moving vector rendering to the GPU"
Cohesion: 0.33
Nodes (6): 11. Moving vector rendering to the GPU, The number, The z-order optimisation, when it is needed, What is already on the GPU, What Phase 2 did to keep the door open, Why not now

### Community 112 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 113 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 114 - "1. The central problem"
Cohesion: 0.40
Nodes (5): 1. The central problem, Coverage test, `DabLattice` — how a piece reproduces its parent's dabs, Garbage collection, What shipped instead, and why (Phase 4c, measured; split restored in Phase 4d)

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 117 - "0. The brief"
Cohesion: 0.40
Nodes (5): 0. The brief, Goal, Key technical & UX edge cases (referenced as "edge case N"), Notes (referenced elsewhere as "requirement N" / "note N"), The workflow, as specified

### Community 118 - "PaintApp"
Cohesion: 0.29
Nodes (5): App, task, PaintApp, .body, Scene

### Community 119 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 120 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 121 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 122 - "7. Edge cases from the brief"
Cohesion: 0.40
Nodes (5): 7.1 Erasers — mostly already solved, 7.2 Topological mismatch, 7.3 Fills, 7.4 Range interpolation (future), 7. Edge cases from the brief

### Community 123 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 124 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

### Community 125 - "AppliedTool"
Cohesion: 0.50
Nodes (3): AppliedTool, Color, Double

## Knowledge Gaps
- **548 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+543 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `TimelineRowView`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeGeometry`, `SelectionMode`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `CGPoint`, `.transparentFormat`, `CanvasManager`, `CanvasManager`, `InterpolationWorkflowLogicTests`, `.stampStroke`, `PerfBaselineTests`, `VectorSample`, `StrokeSettingsPanel`, `AnimationTimeline`, `.load`, `Lattice`, `LayerStackCell`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `RasterLayerTexture`, `DabTarget`, `StrokeGeometry`, `DeformFactorization`, `Color`, `Coordinator`, `LayerRowModel`, `SideToolbar`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `ShapeDetectorLogicTests`, `CanvasManager`, `VectorFillElement`, `ShapeDetector`, `StrokeStabilizer`, `samples`, `CanvasManager`, `Equatable`, `EraserSettingsPanel`, `CoreGraphics`, `DrawingView`, `Identifiable`, `InterpolateBar`, `.setUpGestures`, `VectorImageElement`, `.group`, `TransformOverlaySupport.swift`, `ActionsMenu`, `Kind`, `AppliedTool`?**
  _High betweenness centrality (0.332) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `VectorEraserHybridLogicTests`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeGeometry`, `SelectionMode`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `.transparentFormat`, `CanvasManager`, `CanvasManager`, `InterpolationWorkflowLogicTests`, `CGFloat`, `.stampStroke`, `PerfBaselineTests`, `layers`, `VectorSample`, `AnimationTimeline`, `FloatingPieceOverlayView`, `Lattice`, `ProjectSaveLogicTests`, `SelectionOverlayView`, `RasterLayerTexture`, `DabTarget`, `StrokeGeometry`, `DeformFactorization`, `Coordinator`, `LayerRowModel`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `ShapeDetectorLogicTests`, `CanvasManager`, `ShapeDetector`, `StrokeStabilizer`, `samples`, `CanvasManager`, `Equatable`, `CoreGraphics`, `Identifiable`, `.setUpGestures`, `VectorImageElement`, `Edge`, `.group`, `TransformOverlaySupport.swift`?**
  _High betweenness centrality (0.182) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `ShapeGeometry`, `SelectionMode`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `CGFloat`, `layers`, `CanvasManager`, `VectorSample`, `LayerFolder`, `RasterLayerTexture`, `UIKit`, `PerfMonitor`, `Codable`, `UndoHistory`, `Equatable`, `VectorEraserMode`, `MotionGroup`, `.withStructureUndo`, `Tool`?**
  _High betweenness centrality (0.117) - this node is a cross-community bridge._
- **Are the 53 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 53 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._