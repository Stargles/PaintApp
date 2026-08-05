# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-05)

## Corpus Check
- 145 files · ~303,165 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3510 nodes · 10195 edges · 130 communities (123 shown, 7 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1255 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `f868e4dc`
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
- ShapeDetectorLogicTests
- CanvasManager
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- PointCloudIndex
- Coordinator
- .transparentFormat
- CodingKeys
- BackupManagerLogicTests
- CanvasManager
- CanvasManager
- InterpolationMotionGroupLogicTests
- MetalFillEngine
- CGFloat
- .stampStroke
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
- CGPoint
- VectorEraserHybridLogicTests
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- BrushDynamics
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- DabTarget
- SwiftUI
- ShapeGeometry
- DeformFactorization
- PerfMonitor
- .makeUIView
- Color
- Lattice
- Vector Eraser — Design Plan
- LayerStackCell
- ProjectManifest
- SideToolbar
- ARAPLogicTests
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- MotionGroup
- Refactor baseline (Stage 0)
- CodingKeys
- VectorStroke
- UndoHistory
- CanvasHostView
- PlaybackBoundsCharacterizationTests
- Layer
- PaintSoftware - iPad Drawing and Animation App
- StrokeStabilizer
- Vector Interpolation — Implementation Plan
- LayerRowModel
- GalleryView
- View
- 5. Carry-overs
- Known Issues
- EraserSettingsPanel
- CanvasManager
- Coordinator
- Equatable
- InterpolationEngineDiagnosticsLogicTests
- ShapeDetector
- InterpolationRefusal
- UIKit
- DrawingView
- Identifiable
- StructureSnapshot
- InterpolateBar
- LayerStackListView.Coordinator
- Atomic
- VECTOR_INTERPOLATION_HANDOFF.md
- parallel_test.sh
- .registerGroups
- BrushShape
- CodingKeys
- Corner
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- String
- 5. Workflow and architecture
- Edge
- .setCanvasPadding
- BrushSettingsPanel
- TransformOverlaySupport.swift
- main.swift
- CutOutcome
- ActionsMenu
- LayerStackListView
- ManifestSkeleton
- InterpolationRecipe
- CodingKeys
- CoreGraphics
- 11. Moving vector rendering to the GPU
- .group
- 3. Three candidate engines
- 6. Guide strokes
- run.sh
- 7. Edge cases from the brief
- .resampled
- AppVersion

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 459 edges
2. `CGFloat` - 365 edges
3. `VectorCanvas` - 115 edges
4. `Lattice` - 95 edges
5. `VectorSample` - 95 edges
6. `CanvasManager` - 95 edges
7. `layers` - 80 edges
8. `Coordinator` - 74 edges
9. `ShapeGeometry` - 73 edges
10. `CanvasManager` - 67 edges

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

## Communities (130 total, 7 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

### Community 1 - "ParityScenario"
Cohesion: 0.09
Nodes (33): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+25 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (20): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+12 more)

### Community 3 - ".manager"
Cohesion: 0.05
Nodes (24): OnionSkinSource, PreviousCelOnionSkinSource, CanvasFixture, CanvasManager, Int, Layer, StaticString, String (+16 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.07
Nodes (40): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+32 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.06
Nodes (43): Hashable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+35 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (41): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .hasLoopBoundary (+33 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (15): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+7 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.10
Nodes (25): kind, Kind, fill, image, stroke, CGAffineTransform, CGRect, CGSize (+17 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 13 - "ShapeDetectorLogicTests"
Cohesion: 0.18
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 14 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (28): StrokeInput, UITouch, UIView, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster (+20 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.08
Nodes (30): CGPathElementType, ContentProvider, Direction, backward, forward, Evaluation, GroupWarp, InterpolationEvaluator (+22 more)

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.13
Nodes (15): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+7 more)

### Community 19 - "Coordinator"
Cohesion: 0.08
Nodes (24): NSObject, AppliedTool, Coordinator, InterpolationPreviewKey, Bool, CanvasManager, CGSize, Color (+16 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.12
Nodes (20): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+12 more)

### Community 21 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 22 - "BackupManagerLogicTests"
Cohesion: 0.17
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 23 - "CanvasManager"
Cohesion: 0.07
Nodes (32): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+24 more)

### Community 24 - "CanvasManager"
Cohesion: 0.09
Nodes (17): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+9 more)

### Community 25 - "InterpolationMotionGroupLogicTests"
Cohesion: 0.08
Nodes (19): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+11 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "CGFloat"
Cohesion: 0.13
Nodes (10): Brush, CGFloat, VectorSample, Sweep, Bool, CGRect, ClosedRange, Double (+2 more)

### Community 28 - ".stampStroke"
Cohesion: 0.13
Nodes (12): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+4 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.18
Nodes (8): PerfBaselineTests, CanvasManager, Double, Int, String, UIImage, UInt64, VectorStroke

### Community 30 - "layers"
Cohesion: 0.16
Nodes (11): .activeLayerIsVector, CanvasManager, Bool, Int, Void, Cel, .endFrame, Int (+3 more)

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

### Community 35 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.06
Nodes (37): Content, Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder (+29 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 40 - ".load"
Cohesion: 0.14
Nodes (21): CelContent, CodableColor, .color, Color, .codable, LayerContent, ProjectStore, .projectsDirectory (+13 more)

### Community 41 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+10 more)

### Community 42 - "CGPoint"
Cohesion: 0.13
Nodes (8): CGPoint, .length, .point, LatticeLogicTests, Int, StaticString, String, UInt

### Community 43 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.21
Nodes (8): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "BrushDynamics"
Cohesion: 0.14
Nodes (8): BrushDynamics, BrushGrain, Bool, Double, UUID, BrushLibrary, .customBrushesDirectory, URL

### Community 47 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.10
Nodes (21): 0. The brief, 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 8. Performance — the real constraint (+13 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.16
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 50 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 51 - "SwiftUI"
Cohesion: 0.11
Nodes (8): Combine, .interpolateButton, InterpolatePanel, .body, .options, CanvasManager, PhotosUI, SwiftUI

### Community 52 - "ShapeGeometry"
Cohesion: 0.10
Nodes (19): CaseIterable, FollowFrame, Kind, line, oval, rectangle, ShapeGeometry, .boundingRect (+11 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - ".makeUIView"
Cohesion: 0.12
Nodes (8): LayerHostView, NSCoder, CanvasView, Context, Coordinator, LayerTransform, UIImageView, UIViewRepresentable

### Community 56 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "Lattice"
Cohesion: 0.09
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.07
Nodes (28): 10. Open items (not blocking Phase 0–1), 12. Open work, 1. The central problem, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions) (+20 more)

### Community 59 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 60 - "ProjectManifest"
Cohesion: 0.14
Nodes (27): LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest, LayerManifest (+19 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - "ARAPLogicTests"
Cohesion: 0.11
Nodes (10): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, .rigidMotionL, Int, StaticString (+2 more)

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "MotionGroup"
Cohesion: 0.21
Nodes (9): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, guideStrokes (+11 more)

### Community 69 - "VectorStroke"
Cohesion: 0.12
Nodes (23): CodableColor, .uiColor, DabLattice, .range, RenderQuality, full, preview, StrokeComposite (+15 more)

### Community 70 - "UndoHistory"
Cohesion: 0.23
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
Cohesion: 0.12
Nodes (17): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+9 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.10
Nodes (21): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4.7 — Engine correctness: what the deformation actually does — ***DONE (Session 12)*** (+13 more)

### Community 77 - "LayerRowModel"
Cohesion: 0.21
Nodes (8): LayerRowModel, .folderID, Bool, Double, String, UIImage, UILongPressGestureRecognizer, UIPinchGestureRecognizer

### Community 78 - "GalleryView"
Cohesion: 0.15
Nodes (12): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void (+4 more)

### Community 79 - "View"
Cohesion: 0.13
Nodes (17): .body, MotionGroupRow, .body, .colourBakeButton, .wholeFrameNote, CanvasManager, String, SelectPanel (+9 more)

### Community 80 - "5. Carry-overs"
Cohesion: 0.04
Nodes (48): 1. Start-of-session checklist, 2. Current state, 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol (+40 more)

### Community 81 - "Known Issues"
Cohesion: 0.14
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 83 - "CanvasManager"
Cohesion: 0.10
Nodes (17): CanvasManager, .hasAnonymousWholeFrameGroup, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .interpolationTarget, .motionGroupChips, MotionGroupChip (+9 more)

### Community 84 - "Coordinator"
Cohesion: 0.32
Nodes (6): Coordinator, CanvasManager, Int, Set, UUID, UITableViewDiffableDataSource

### Community 85 - "Equatable"
Cohesion: 0.19
Nodes (15): Codable, Equatable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval (+7 more)

### Community 86 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 87 - "ShapeDetector"
Cohesion: 0.25
Nodes (4): ClosedFit, ShapeDetector, Bool, CGRect

### Community 88 - "InterpolationRefusal"
Cohesion: 0.23
Nodes (8): InterpolationRefusal, alreadyInterpolated, .message, notAVectorLayer, notEnoughReferences, referencesAreEmpty, reprojectNotImplemented, targetIsAReference

### Community 89 - "UIKit"
Cohesion: 0.11
Nodes (4): Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "Identifiable"
Cohesion: 0.20
Nodes (10): Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+2 more)

### Community 92 - "StructureSnapshot"
Cohesion: 0.23
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 93 - "InterpolateBar"
Cohesion: 0.14
Nodes (15): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .referenceButton, .referenceSummary, .removeButton (+7 more)

### Community 94 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UIView, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 95 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 96 - "VECTOR_INTERPOLATION_HANDOFF.md"
Cohesion: 0.23
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - ".registerGroups"
Cohesion: 0.18
Nodes (5): GroupRegistration, RegistrationElement, RegistrationFrame, Cel, Int

### Community 99 - "BrushShape"
Cohesion: 0.22
Nodes (9): BrushShape, custom, .displayName, hardRound, .id, pen, pencil, softRound (+1 more)

### Community 100 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+12 more)

### Community 101 - "Corner"
Cohesion: 0.22
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 108 - "String"
Cohesion: 0.18
Nodes (12): ElementData, fill, image, stroke, ImageRef, Decoder, Encoder, VectorCanvasData (+4 more)

### Community 109 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 110 - "Edge"
Cohesion: 0.25
Nodes (5): Edge, bottom, left, right, top

### Community 111 - ".setCanvasPadding"
Cohesion: 0.39
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 112 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 113 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 114 - "main.swift"
Cohesion: 0.33
Nodes (6): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.14
Nodes (15): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+7 more)

### Community 117 - "LayerStackListView"
Cohesion: 0.20
Nodes (7): IndexPath, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView

### Community 118 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 119 - "InterpolationRecipe"
Cohesion: 0.11
Nodes (20): InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, Kind (+12 more)

### Community 120 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, boundGroups, id, interval, role, samples

### Community 121 - "CoreGraphics"
Cohesion: 0.11
Nodes (4): CoreGraphics, Foundation, LayerTransform, Notification.Name

### Community 122 - "11. Moving vector rendering to the GPU"
Cohesion: 0.33
Nodes (6): 11. Moving vector rendering to the GPU, The number, The z-order optimisation, when it is needed, What is already on the GPU, What Phase 2 did to keep the door open, Why not now

### Community 123 - ".group"
Cohesion: 0.21
Nodes (6): Group, MotionGrouping, Options, Int, Set, groups

### Community 124 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

### Community 125 - "6. Guide strokes"
Cohesion: 0.40
Nodes (5): 6.1 What they are, 6.2 The controls from requirement 6, 6.3 The data gap, 6.4 Reuse across frames (requirement 7), 6. Guide strokes

### Community 127 - "7. Edge cases from the brief"
Cohesion: 0.40
Nodes (5): 7.1 Erasers — mostly already solved, 7.2 Topological mismatch, 7.3 Fills, 7.4 Range interpolation (future), 7. Edge cases from the brief

### Community 129 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

## Knowledge Gaps
- **561 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+556 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `ParityScenario`, `.resampled`, `.manager`, `TimelineRowView`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeDetectorLogicTests`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `Coordinator`, `.transparentFormat`, `CodingKeys`, `CanvasManager`, `CanvasManager`, `InterpolationMotionGroupLogicTests`, `.stampStroke`, `PerfBaselineTests`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `AnimationTimeline`, `.load`, `CGPoint`, `VectorEraserHybridLogicTests`, `InterpolationModelLogicTests`, `BrushDynamics`, `RasterLayerTexture`, `DabTarget`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `Color`, `Lattice`, `LayerStackCell`, `SideToolbar`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `VectorStroke`, `StrokeStabilizer`, `EraserSettingsPanel`, `CanvasManager`, `Coordinator`, `Equatable`, `InterpolationEngineDiagnosticsLogicTests`, `ShapeDetector`, `DrawingView`, `InterpolateBar`, `.registerGroups`, `.setCanvasPadding`, `TransformOverlaySupport.swift`, `main.swift`, `ActionsMenu`, `LayerStackListView`, `InterpolationRecipe`, `CoreGraphics`, `.group`?**
  _High betweenness centrality (0.326) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `.resampled`, `ParityScenario`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeDetectorLogicTests`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `Coordinator`, `.transparentFormat`, `CanvasManager`, `CanvasManager`, `InterpolationMotionGroupLogicTests`, `CGFloat`, `.stampStroke`, `PerfBaselineTests`, `layers`, `StrokeSpatialIndex`, `AnimationTimeline`, `FloatingPieceOverlayView`, `VectorEraserHybridLogicTests`, `InterpolationModelLogicTests`, `ProjectSaveLogicTests`, `BrushDynamics`, `SelectionOverlayView`, `RasterLayerTexture`, `DabTarget`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `Lattice`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `StrokeStabilizer`, `CanvasManager`, `Equatable`, `InterpolationEngineDiagnosticsLogicTests`, `ShapeDetector`, `LayerStackListView.Coordinator`, `.registerGroups`, `Corner`, `Edge`, `.setCanvasPadding`, `TransformOverlaySupport.swift`, `main.swift`, `CoreGraphics`, `.group`?**
  _High betweenness centrality (0.231) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CanvasManager`, `MotionGroup`, `ViewPreset`, `ColorPickerPanel`, `UndoHistory`, `ProjectManifest`, `.setCanvasPadding`, `RasterLayerTexture`, `SwiftUI`, `ShapeGeometry`, `Equatable`, `PerfMonitor`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `CGFloat`, `StructureSnapshot`, `layers`?**
  _High betweenness centrality (0.102) - this node is a cross-community bridge._
- **Are the 53 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 53 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `Lattice` (e.g. with `.visible()` and `.registerGroups()`) actually correct?**
  _`Lattice` has 9 INFERRED edges - model-reasoned connections that need verification._