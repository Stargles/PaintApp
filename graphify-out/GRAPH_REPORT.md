# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-01)

## Corpus Check
- 143 files · ~280,758 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3392 nodes · 9662 edges · 127 communities (119 shown, 8 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1203 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `46e75c1e`
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
- .setCanvasPadding
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- PointCloudIndex
- .warped
- .transparentFormat
- CodingKeys
- BackupManagerLogicTests
- CanvasManager
- CanvasManager
- InterpolationWorkflowLogicTests
- MetalFillEngine
- Brush
- .stampStroke
- PerfBaselineTests
- layers
- FillParams
- TouchCountRecognizer
- .withStructureUndo
- VectorSample
- ViewPreset
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- FloatingPieceOverlayView
- .load
- View
- CGPoint
- StrokeGestureRecognizer
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- Equatable
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- .stampCircle
- SwiftUI
- StrokeGeometry
- CGFloat
- PerfMonitor
- CodingKeys
- Color
- Lattice
- Vector Eraser — Design Plan
- LayerStackCell
- Codable
- SideToolbar
- ARAPLogicTests
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- VectorElement
- Refactor baseline (Stage 0)
- CanvasManager
- VectorCanvasData
- UndoHistory
- CanvasHostView
- PlaybackBoundsCharacterizationTests
- Layer
- PaintSoftware - iPad Drawing and Animation App
- BrushDynamics
- Vector Interpolation — Implementation Plan
- .setUpGestures
- GalleryView
- SelectPanel
- 5. Carry-overs
- Known Issues
- EraserSettingsPanel
- CanvasManager
- LayerRowModel
- GuideStroke
- InterpolationEngineDiagnosticsLogicTests
- ShapeDetector
- InterpolationRefusal
- UIKit
- DrawingView
- BrushBlendMode
- StructureSnapshot
- InterpolateBar
- LayerStackListView.Coordinator
- Atomic
- parallel_test.sh
- .attach
- ManifestSkeleton
- String
- Coordinator
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- VectorStroke
- Usage Guide
- Deterministic
- Multi-Session Protocol
- BrushSettingsPanel
- UIView
- 1. The central problem
- CutOutcome
- ActionsMenu
- LayerStackListView
- .setPinchHighlight
- Kind
- 12. Open work
- ProjectStore.swift
- CopiedCel
- CoreGraphics
- AppVersion
- 2. Data model
- run.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 413 edges
2. `CGFloat` - 346 edges
3. `VectorCanvas` - 112 edges
4. `CanvasManager` - 95 edges
5. `VectorSample` - 94 edges
6. `Lattice` - 91 edges
7. `Coordinator` - 74 edges
8. `ShapeGeometry` - 73 edges
9. `layers` - 73 edges
10. `Brush` - 64 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (127 total, 8 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (47): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+39 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+13 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (18): CanvasFixture, CanvasManager, Int, Layer, StaticString, String, UInt, UUID (+10 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.07
Nodes (40): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+32 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.06
Nodes (43): Hashable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+35 more)

### Community 6 - "CanvasManager"
Cohesion: 0.06
Nodes (36): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .effectiveLoopRange, .hasLoopBoundary, .isFillInAdjustableState, .isShapeFollowingFinger (+28 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (7): Intersection, samples, StrokeGeometryLogicTests, .ramp, StaticString, String, UInt

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (7): VectorEraser, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.13
Nodes (11): Bool, CGAffineTransform, CGRect, CGSize, LayerTransform, VectorCanvas, .elements, .hasCachedImage (+3 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 13 - "ShapeGeometry"
Cohesion: 0.05
Nodes (28): Int, Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom (+20 more)

### Community 14 - ".setCanvasPadding"
Cohesion: 0.31
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 15 - "StrokeCanvasView"
Cohesion: 0.06
Nodes (33): Void, StrokeInput, UITouch, UIView, StrokeStabilizer, .stabilization, Double, NSCoder (+25 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.11
Nodes (18): ARAPRegistration, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty, Result (+10 more)

### Community 19 - ".warped"
Cohesion: 0.14
Nodes (19): CGPathElementType, ContentProvider, Direction, backward, forward, Evaluation, GroupWarp, InterpolationEvaluator (+11 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.14
Nodes (16): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+8 more)

### Community 21 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 22 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 23 - "CanvasManager"
Cohesion: 0.09
Nodes (27): .currentFrame, .currentLayerIndex, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move (+19 more)

### Community 24 - "CanvasManager"
Cohesion: 0.09
Nodes (17): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+9 more)

### Community 25 - "InterpolationWorkflowLogicTests"
Cohesion: 0.10
Nodes (20): cels, InterpolationReferenceOnionSkinSource, OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CGSize, UIColor, UIImage (+12 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "Brush"
Cohesion: 0.16
Nodes (7): Brush, Sweep, Bool, CGRect, ClosedRange, Double, .fixedBrush

### Community 28 - ".stampStroke"
Cohesion: 0.15
Nodes (11): AnyObject, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.18
Nodes (9): BrushStamper, PerfBaselineTests, CanvasManager, Double, Int, String, UIImage, UInt64 (+1 more)

### Community 30 - "layers"
Cohesion: 0.20
Nodes (10): .activeLayerIsVector, CanvasManager, Bool, Int, Cel, .endFrame, Int, UIImage (+2 more)

### Community 31 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 32 - "TouchCountRecognizer"
Cohesion: 0.19
Nodes (10): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+2 more)

### Community 33 - ".withStructureUndo"
Cohesion: 0.16
Nodes (14): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+6 more)

### Community 34 - "VectorSample"
Cohesion: 0.18
Nodes (12): Int64, VectorSample, .point, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool (+4 more)

### Community 35 - "ViewPreset"
Cohesion: 0.16
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.05
Nodes (42): Content, Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder (+34 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 40 - ".load"
Cohesion: 0.17
Nodes (18): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CanvasManager (+10 more)

### Community 41 - "View"
Cohesion: 0.16
Nodes (19): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+11 more)

### Community 42 - "CGPoint"
Cohesion: 0.12
Nodes (7): CGPoint, .length, LatticeLogicTests, Int, StaticString, String, UInt

### Community 43 - "StrokeGestureRecognizer"
Cohesion: 0.35
Nodes (6): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "Equatable"
Cohesion: 0.18
Nodes (13): Equatable, CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding (+5 more)

### Community 47 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.04
Nodes (46): 0. The brief, 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 3. Three candidate engines, 4. The load-bearing decision: an inbetween is *derived*, never *stored* (+38 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.17
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 50 - ".stampCircle"
Cohesion: 0.26
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 51 - "SwiftUI"
Cohesion: 0.11
Nodes (8): Combine, .interpolateButton, InterpolatePanel, .body, .options, CanvasManager, PhotosUI, SwiftUI

### Community 52 - "StrokeGeometry"
Cohesion: 0.14
Nodes (9): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, .dragHandle (+1 more)

### Community 53 - "CGFloat"
Cohesion: 0.08
Nodes (24): Accelerate, cellSize(), cShape(), polyline(), Int, Interpolator, Options, Bool (+16 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - "CodingKeys"
Cohesion: 0.12
Nodes (17): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, id (+9 more)

### Community 56 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "Lattice"
Cohesion: 0.10
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.10
Nodes (20): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 3.1 `StrokeGeometry` (pure functions), 3.2 `StrokeSpatialIndex`, 3. Shared geometry foundation, 4. Per-mode implementation, 5. Tool and UI plumbing, 6. Performance (+12 more)

### Community 59 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 60 - "Codable"
Cohesion: 0.14
Nodes (28): Codable, LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest (+20 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - "ARAPLogicTests"
Cohesion: 0.16
Nodes (6): ARAPInterpolation, ARAPLogicTests, Int, StaticString, String, UInt

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "VectorElement"
Cohesion: 0.12
Nodes (23): Identifiable, CodableColor, .uiColor, kind, Kind, fill, image, stroke (+15 more)

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 69 - "VectorCanvasData"
Cohesion: 0.19
Nodes (12): ElementData, fill, image, stroke, ImageRef, Decoder, Double, Encoder (+4 more)

### Community 70 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.17
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 73 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 74 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.18
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 75 - "BrushDynamics"
Cohesion: 0.14
Nodes (8): BrushDynamics, BrushGrain, Bool, Double, UUID, BrushLibrary, .customBrushesDirectory, URL

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.10
Nodes (20): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4.7 — Engine correctness: what the deformation actually does — ***next, ahead of Phase 5*** (+12 more)

### Community 77 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 78 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 79 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 80 - "5. Carry-overs"
Cohesion: 0.04
Nodes (45): 1. Start-of-session checklist, 2. Current state, 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol (+37 more)

### Community 81 - "Known Issues"
Cohesion: 0.17
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 83 - "CanvasManager"
Cohesion: 0.10
Nodes (16): CanvasManager, .interpolationContentProvider, .interpolationKeyframes, .interpolationTarget, Bool, Cel, CodableColor, Int (+8 more)

### Community 84 - "LayerRowModel"
Cohesion: 0.22
Nodes (12): NSObject, Coordinator, LayerRowModel, .folderID, CanvasManager, Double, Int, Set (+4 more)

### Community 85 - "GuideStroke"
Cohesion: 0.13
Nodes (18): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+10 more)

### Community 86 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.26
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 87 - "ShapeDetector"
Cohesion: 0.25
Nodes (4): ClosedFit, ShapeDetector, Bool, CGRect

### Community 88 - "InterpolationRefusal"
Cohesion: 0.18
Nodes (11): InterpolationRefusal, alreadyInterpolated, .message, notAVectorLayer, notEnoughReferences, referencesAreEmpty, reprojectNotImplemented, targetIsAReference (+3 more)

### Community 89 - "UIKit"
Cohesion: 0.08
Nodes (4): Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "BrushBlendMode"
Cohesion: 0.07
Nodes (30): CaseIterable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+22 more)

### Community 92 - "StructureSnapshot"
Cohesion: 0.23
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 93 - "InterpolateBar"
Cohesion: 0.14
Nodes (16): .body, InterpolateBar, .activeRecipe, .body, .commandRow, .commands, .referenceButton, .referenceSummary (+8 more)

### Community 94 - "LayerStackListView.Coordinator"
Cohesion: 0.19
Nodes (9): IndexPath, DropTarget, between, onto, LayerStackListView.Coordinator, UIView, UIGestureRecognizerDelegate, UISwipeActionsConfiguration (+1 more)

### Community 95 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - ".attach"
Cohesion: 0.26
Nodes (4): Context, UILongPressGestureRecognizer, UIPinchGestureRecognizer, UITableView

### Community 99 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 100 - "String"
Cohesion: 0.07
Nodes (33): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+25 more)

### Community 101 - "Coordinator"
Cohesion: 0.08
Nodes (21): LayerHostView, AppliedTool, CanvasView, Coordinator, InterpolationPreviewKey, Bool, CanvasManager, Color (+13 more)

### Community 108 - "VectorStroke"
Cohesion: 0.16
Nodes (12): image, DabLattice, .range, RenderQuality, full, preview, CGContext, ClosedRange (+4 more)

### Community 109 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 111 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 112 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 113 - "UIView"
Cohesion: 0.16
Nodes (11): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+3 more)

### Community 114 - "1. The central problem"
Cohesion: 0.40
Nodes (5): 1. The central problem, Coverage test, `DabLattice` — how a piece reproduces its parent's dabs, Garbage collection, What shipped instead, and why (Phase 4c, measured; split restored in Phase 4d)

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 117 - "LayerStackListView"
Cohesion: 0.33
Nodes (4): LayerStackListView, Coordinator, Void, UIViewRepresentable

### Community 119 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 120 - "12. Open work"
Cohesion: 0.40
Nodes (5): 12. Open work, GPU rendering, Per-element Move, Still open, The spatial index is rebuilt from scratch on every `invalidate()`

### Community 121 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 122 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 123 - "CoreGraphics"
Cohesion: 0.23
Nodes (3): CoreGraphics, Foundation, Notification.Name

### Community 124 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

### Community 125 - "2. Data model"
Cohesion: 0.50
Nodes (4): 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model

## Knowledge Gaps
- **555 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+550 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `TimelineRowView`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeGeometry`, `.setCanvasPadding`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `.warped`, `.transparentFormat`, `CodingKeys`, `CanvasManager`, `CanvasManager`, `InterpolationWorkflowLogicTests`, `Brush`, `.stampStroke`, `PerfBaselineTests`, `VectorSample`, `StrokeSettingsPanel`, `AnimationTimeline`, `FloatingPieceOverlayView`, `.load`, `CGPoint`, `InterpolationModelLogicTests`, `Equatable`, `RasterLayerTexture`, `.stampCircle`, `StrokeGeometry`, `Color`, `Lattice`, `LayerStackCell`, `SideToolbar`, `ARAPLogicTests`, `CanvasManager`, `BrushDynamics`, `.setUpGestures`, `EraserSettingsPanel`, `CanvasManager`, `LayerRowModel`, `GuideStroke`, `InterpolationEngineDiagnosticsLogicTests`, `ShapeDetector`, `DrawingView`, `InterpolateBar`, `LayerStackListView.Coordinator`, `Coordinator`, `VectorStroke`, `Deterministic`, `UIView`, `ActionsMenu`, `Kind`, `CoreGraphics`?**
  _High betweenness centrality (0.335) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `VectorEraserHybridLogicTests`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeGeometry`, `.setCanvasPadding`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `.warped`, `.transparentFormat`, `CanvasManager`, `CanvasManager`, `InterpolationWorkflowLogicTests`, `Brush`, `.stampStroke`, `PerfBaselineTests`, `layers`, `VectorSample`, `AnimationTimeline`, `FloatingPieceOverlayView`, `ProjectSaveLogicTests`, `Equatable`, `SelectionOverlayView`, `RasterLayerTexture`, `.stampCircle`, `StrokeGeometry`, `CGFloat`, `Lattice`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `CanvasManager`, `VectorCanvasData`, `BrushDynamics`, `.setUpGestures`, `CanvasManager`, `GuideStroke`, `InterpolationEngineDiagnosticsLogicTests`, `ShapeDetector`, `InterpolationRefusal`, `LayerStackListView.Coordinator`, `Coordinator`, `UIView`, `CoreGraphics`?**
  _High betweenness centrality (0.179) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `ColorPickerPanel`, `ShapeGeometry`, `.setCanvasPadding`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `Brush`, `layers`, `.withStructureUndo`, `VectorSample`, `ViewPreset`, `Equatable`, `RasterLayerTexture`, `SwiftUI`, `CGFloat`, `PerfMonitor`, `Codable`, `UndoHistory`, `GuideStroke`, `BrushBlendMode`, `StructureSnapshot`, `String`, `CopiedCel`?**
  _High betweenness centrality (0.106) - this node is a cross-community bridge._
- **Are the 53 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 53 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._