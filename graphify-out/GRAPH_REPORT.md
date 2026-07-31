# Graph Report - vector-interpolation-keyframes-d484df  (2026-07-31)

## Corpus Check
- 137 files · ~256,471 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3175 nodes · 8997 edges · 130 communities (124 shown, 6 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 1126 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `f6986dfc`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- VectorEraserHybridLogicTests
- ProjectBackupManager
- CelCRUDCharacterizationTests
- TimelineRowView
- ColorPickerPanel
- CanvasManager
- bash
- CGPoint
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- ShapeGeometry
- BrushBlendMode
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- PointCloudIndex
- SelectionMode
- .transparentFormat
- CodingKeys
- .setUpGestures
- CanvasManager
- CanvasManager
- OnionSkinLogicTests
- MetalFillEngine
- VectorSample
- .stampStroke
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
- View
- Lattice
- LayerStackCell
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- Codable
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- CGContextDabTarget
- UIKit
- .warped
- DeformFactorization
- PerfMonitor
- CodingKeys
- Color
- LatticeLogicTests
- Vector Eraser — Design Plan
- LayerRowModel
- ProjectManifest
- SideToolbar
- .restLattice
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView.Coordinator
- Refactor baseline (Stage 0)
- CanvasManager
- VectorFillElement
- UndoHistory
- CanvasHostView
- Layer
- Vector Eraser — Resume Here
- Known Issues
- StrokeStabilizer
- Vector Interpolation — Implementation Plan
- LayerTreeCharacterizationTests
- GalleryView
- SelectPanel
- Vector Interpolation — Handoff & Session Protocol
- .manager
- BrushSettingsPanel
- CanvasManager
- 5. Workflow and architecture
- Equatable
- VectorEraserMode
- String
- EraserSettingsPanel
- CoreGraphics
- DrawingView
- CGFloat
- 3. Three candidate engines
- VectorElement
- VectorCanvasData
- Atomic
- parallel_test.sh
- .update
- Matrix2x2
- agent
- Coordinator
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- .render
- PaintApp
- ARAPLogicTests
- command
- CGRect
- UIView
- XCTestCase
- CutOutcome
- ActionsMenu
- Multi-Session Protocol
- .assertXs
- Kind
- Zone
- ProjectStore.swift
- 7. Edge cases from the brief
- orchestrator
- worker-bugfix
- worker-feature
- worker-integration
- worker-research
- worker-test
- 4. Per-mode implementation

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 387 edges
2. `CGFloat` - 325 edges
3. `VectorCanvas` - 112 edges
4. `VectorSample` - 93 edges
5. `Lattice` - 88 edges
6. `CanvasManager` - 88 edges
7. `ShapeGeometry` - 73 edges
8. `Coordinator` - 72 edges
9. `layers` - 65 edges
10. `Brush` - 64 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  PaintSoftware/PaintApp.swift → PaintSoftware/ContentView.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (130 total, 6 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (44): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+36 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, name, Cel, Layer, ManifestSkeleton, ProjectBackup, .id (+30 more)

### Community 3 - "CelCRUDCharacterizationTests"
Cohesion: 0.14
Nodes (6): StaticString, String, UInt, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 4 - "TimelineRowView"
Cohesion: 0.12
Nodes (21): Coordinator, Segment, CanvasManager, ClosedRange, Context, Coordinator, Int, UILongPressGestureRecognizer (+13 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.06
Nodes (44): Hashable, CelLocation, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+36 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (41): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .isFillInAdjustableState (+33 more)

### Community 7 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 8 - "CGPoint"
Cohesion: 0.09
Nodes (13): CGPoint, .length, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect (+5 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.10
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.14
Nodes (11): Bool, CGAffineTransform, CGRect, CGSize, LayerTransform, VectorCanvas, .elements, .hasCachedImage (+3 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 13 - "ShapeGeometry"
Cohesion: 0.05
Nodes (28): Int, Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom (+20 more)

### Community 14 - "BrushBlendMode"
Cohesion: 0.06
Nodes (31): CaseIterable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+23 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.07
Nodes (30): Void, StrokeInput, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+22 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 17 - "ContentView"
Cohesion: 0.20
Nodes (9): AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager, MainActor (+1 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.16
Nodes (12): ARAPRegistration, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty, Result (+4 more)

### Community 19 - "SelectionMode"
Cohesion: 0.15
Nodes (11): CanvasManager, Bool, CGSize, UIImage, SelectionMode, automatic, .displayName, .id (+3 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.15
Nodes (15): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+7 more)

### Community 21 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 22 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 23 - "CanvasManager"
Cohesion: 0.08
Nodes (28): String, UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+20 more)

### Community 24 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "OnionSkinLogicTests"
Cohesion: 0.18
Nodes (9): OnionSkinFrame, PreviousCelOnionSkinSource, CanvasManager, UIColor, UIImage, OnionSkinLogicTests, Bool, UIImage (+1 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "VectorSample"
Cohesion: 0.15
Nodes (11): Brush, VectorSample, .point, Sweep, Bool, CGRect, ClosedRange, Double (+3 more)

### Community 28 - ".stampStroke"
Cohesion: 0.14
Nodes (14): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+6 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.23
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 30 - "layers"
Cohesion: 0.26
Nodes (6): .activeLayerIsVector, Bool, CanvasManager, Bool, Int, layers

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
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 35 - ".withStructureUndo"
Cohesion: 0.10
Nodes (13): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, Int (+5 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, move (+9 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.07
Nodes (29): Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer (+21 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 40 - ".load"
Cohesion: 0.20
Nodes (16): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CanvasManager (+8 more)

### Community 41 - "View"
Cohesion: 0.16
Nodes (19): ButtonRole, .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow (+11 more)

### Community 42 - "Lattice"
Cohesion: 0.08
Nodes (29): CodingKeys, activeCells, cellSize, cols, originX, originY, rows, vertices (+21 more)

### Community 43 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.21
Nodes (8): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "Codable"
Cohesion: 0.16
Nodes (16): Codable, samples, InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed, .referencedCels (+8 more)

### Community 47 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.08
Nodes (26): 0. The brief, 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 6.1 What they are (+18 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 50 - "CGContextDabTarget"
Cohesion: 0.25
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 51 - "UIKit"
Cohesion: 0.14
Nodes (7): Combine, Darwin, ThumbnailRenderer, PhotosUI, QuartzCore, SwiftUI, UIKit

### Community 52 - ".warped"
Cohesion: 0.14
Nodes (18): CGPathElementType, ContentProvider, Direction, backward, forward, Evaluation, GroupWarp, InterpolationEvaluator (+10 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.22
Nodes (9): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Double, Int, Int32, SparseMatrix_Double (+1 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 55 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, cels, customBrushes, fps (+12 more)

### Community 56 - "Color"
Cohesion: 0.18
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "LatticeLogicTests"
Cohesion: 0.15
Nodes (5): LatticeLogicTests, Int, StaticString, String, UInt

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.08
Nodes (25): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 1. The central problem, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions) (+17 more)

### Community 59 - "LayerRowModel"
Cohesion: 0.11
Nodes (23): IndexPath, NSObject, Coordinator, LayerRowModel, .folderID, LayerStackListView, Bool, CanvasManager (+15 more)

### Community 60 - "ProjectManifest"
Cohesion: 0.21
Nodes (19): LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest, LayerManifest (+11 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - ".restLattice"
Cohesion: 0.14
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

### Community 66 - "LayerStackListView.Coordinator"
Cohesion: 0.19
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UIView, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 69 - "VectorFillElement"
Cohesion: 0.15
Nodes (17): Identifiable, CodableColor, .uiColor, DabLattice, .range, CGContext, CGPath, ClosedRange (+9 more)

### Community 70 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 73 - "Vector Eraser — Resume Here"
Cohesion: 0.15
Nodes (13): 1. Per-element Move, 2. The spatial index is rebuilt from scratch on every `invalidate()`, 3. GPU rendering, Carry-overs still open, Environment correction (important, saves 10 minutes), Mode 1, as it actually is, Multi-session protocol reminder, Next session: start here (+5 more)

### Community 74 - "Known Issues"
Cohesion: 0.06
Nodes (29): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+21 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.12
Nodes (17): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4 — Interpolate mode UI, references, slider, Generate — *first usable milestone* (+9 more)

### Community 77 - "LayerTreeCharacterizationTests"
Cohesion: 0.24
Nodes (4): Layer, LayerTreeCharacterizationTests, CanvasManager, String

### Community 78 - "GalleryView"
Cohesion: 0.21
Nodes (7): GalleryTileView, .body, Void, GalleryView, .body, CanvasManager, Void

### Community 79 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 80 - "Vector Interpolation — Handoff & Session Protocol"
Cohesion: 0.06
Nodes (33): 1. Start-of-session checklist, 2. Current state, 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol (+25 more)

### Community 81 - ".manager"
Cohesion: 0.18
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 82 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 83 - "CanvasManager"
Cohesion: 0.15
Nodes (10): CanvasManager, Bool, Cel, CodableColor, Int, Set, String, UUID (+2 more)

### Community 84 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 85 - "Equatable"
Cohesion: 0.19
Nodes (14): Equatable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+6 more)

### Community 86 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 87 - "String"
Cohesion: 0.08
Nodes (30): CodingKey, StrokeComposite, erase, paint, CodingKeys, boundGroups, id, interval (+22 more)

### Community 88 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 89 - "CoreGraphics"
Cohesion: 0.07
Nodes (7): CoreGraphics, Foundation, Notification.Name, AppVersion, .versionString, String, XCTest

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "CGFloat"
Cohesion: 0.10
Nodes (8): Constraint, CGFloat, ClosedFit, ShapeDetector, Bool, CGRect, LayerTransform, .samples

### Community 92 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

### Community 93 - "VectorElement"
Cohesion: 0.15
Nodes (14): kind, Kind, fill, image, stroke, Int, .fills, .images (+6 more)

### Community 94 - "VectorCanvasData"
Cohesion: 0.19
Nodes (12): ElementData, fill, image, stroke, ImageRef, Decoder, Double, Encoder (+4 more)

### Community 95 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - ".update"
Cohesion: 0.16
Nodes (10): CelBlockView, Kind, cel, gap, Bool, Cel, String, UIGestureRecognizer (+2 more)

### Community 99 - "Matrix2x2"
Cohesion: 0.23
Nodes (5): Matrix2x2, .determinant, .isFinite, .polar, Bool

### Community 100 - "agent"
Cohesion: 0.20
Nodes (9): agent, worker-ui, model, plugin, $schema, description, mode, model (+1 more)

### Community 101 - "Coordinator"
Cohesion: 0.08
Nodes (21): LayerHostView, AppliedTool, CanvasView, Coordinator, Bool, CanvasManager, Color, Context (+13 more)

### Community 108 - ".render"
Cohesion: 0.36
Nodes (5): image, RenderQuality, full, preview, UIImage

### Community 109 - "PaintApp"
Cohesion: 0.29
Nodes (5): App, task, PaintApp, .body, Scene

### Community 110 - "ARAPLogicTests"
Cohesion: 0.21
Nodes (7): Group, MotionGrouping, Options, Int, Set, groups, ARAPLogicTests

### Community 111 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 113 - "UIView"
Cohesion: 0.16
Nodes (11): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+3 more)

### Community 114 - "XCTestCase"
Cohesion: 0.29
Nodes (5): CanvasFixture, CanvasManager, Int, UUID, XCTestCase

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.33
Nodes (7): ActionsMenu, .body, .paddingControl, CanvasManager, Double, PhotosPickerItem, String

### Community 117 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 118 - ".assertXs"
Cohesion: 0.33
Nodes (3): StaticString, String, UInt

### Community 119 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 120 - "Zone"
Cohesion: 0.40
Nodes (5): Zone, body, gap, leftHandle, rightHandle

### Community 121 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 122 - "7. Edge cases from the brief"
Cohesion: 0.40
Nodes (5): 7.1 Erasers — mostly already solved, 7.2 Topological mismatch, 7.3 Fills, 7.4 Range interpolation (future), 7. Edge cases from the brief

### Community 123 - "orchestrator"
Cohesion: 0.50
Nodes (4): orchestrator, description, mode, model

### Community 124 - "worker-bugfix"
Cohesion: 0.50
Nodes (4): worker-bugfix, description, mode, model

### Community 125 - "worker-feature"
Cohesion: 0.50
Nodes (4): worker-feature, description, mode, model

### Community 126 - "worker-integration"
Cohesion: 0.50
Nodes (4): worker-integration, description, mode, model

### Community 127 - "worker-research"
Cohesion: 0.50
Nodes (4): worker-research, description, mode, model

### Community 128 - "worker-test"
Cohesion: 0.50
Nodes (4): worker-test, description, mode, model

### Community 129 - "4. Per-mode implementation"
Cohesion: 0.50
Nodes (4): 4. Per-mode implementation, Mode 1 — Erase, Mode 2 — Cut points (rewrite of what exists), Mode 3 — Cut to intersection

## Knowledge Gaps
- **518 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+513 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `TimelineRowView`, `CanvasManager`, `CGPoint`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeGeometry`, `BrushBlendMode`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `SelectionMode`, `.transparentFormat`, `CodingKeys`, `.setUpGestures`, `CanvasManager`, `CanvasManager`, `OnionSkinLogicTests`, `VectorSample`, `.stampStroke`, `PerfBaselineTests`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `AnimationTimeline`, `FloatingPieceOverlayView`, `.load`, `Lattice`, `LayerStackCell`, `InterpolationModelLogicTests`, `Codable`, `RasterLayerTexture`, `CGContextDabTarget`, `.warped`, `DeformFactorization`, `Color`, `LatticeLogicTests`, `LayerRowModel`, `SideToolbar`, `.restLattice`, `CanvasManager`, `VectorFillElement`, `StrokeStabilizer`, `CanvasManager`, `Equatable`, `EraserSettingsPanel`, `DrawingView`, `.update`, `Matrix2x2`, `Coordinator`, `ARAPLogicTests`, `UIView`, `ActionsMenu`, `.assertXs`, `Kind`?**
  _High betweenness centrality (0.308) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `VectorEraserHybridLogicTests`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeGeometry`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `SelectionMode`, `.transparentFormat`, `.setUpGestures`, `CanvasManager`, `CanvasManager`, `VectorSample`, `.stampStroke`, `PerfBaselineTests`, `layers`, `StrokeSpatialIndex`, `FloatingPieceOverlayView`, `Lattice`, `InterpolationModelLogicTests`, `ProjectSaveLogicTests`, `Codable`, `SelectionOverlayView`, `RasterLayerTexture`, `CGContextDabTarget`, `.warped`, `DeformFactorization`, `LatticeLogicTests`, `.restLattice`, `ObjectTransformOverlayView`, `LayerStackListView.Coordinator`, `CanvasManager`, `StrokeStabilizer`, `Equatable`, `CoreGraphics`, `CGFloat`, `VectorCanvasData`, `.update`, `Matrix2x2`, `Coordinator`, `.render`, `ARAPLogicTests`, `UIView`?**
  _High betweenness centrality (0.173) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `ColorPickerPanel`, `ShapeGeometry`, `SelectionMode`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `VectorSample`, `layers`, `CanvasManager`, `.withStructureUndo`, `RasterLayerTexture`, `UIKit`, `PerfMonitor`, `ProjectManifest`, `UndoHistory`, `Equatable`, `VectorEraserMode`, `String`, `CGFloat`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Are the 53 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 53 INFERRED edges - model-reasoned connections that need verification._
- **Are the 7 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `VectorSample` (e.g. with `.warped()` and `.cancelShapeDetection()`) actually correct?**
  _`VectorSample` has 14 INFERRED edges - model-reasoned connections that need verification._