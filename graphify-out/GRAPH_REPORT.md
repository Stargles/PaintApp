# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-05)

## Corpus Check
- 145 files · ~304,696 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3520 nodes · 10237 edges · 122 communities (115 shown, 7 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1261 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7a47e950`
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
- StrokeGeometryLogicTests
- ShapeOverlayView
- CGFloat
- VectorCanvas
- BrushEngineLogicTests
- ShapeDetectorLogicTests
- CanvasManager
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- PointCloudIndex
- .setUpGestures
- .transparentFormat
- String
- BackupManagerLogicTests
- CanvasManager
- CanvasManager
- InterpolationMotionGroupLogicTests
- MetalFillEngine
- LayerTreeCharacterizationTests
- .stampStroke
- PerfBaselineTests
- layers
- FillParams
- TouchCountRecognizer
- CanvasManager
- VectorSample
- .withStructureUndo
- ActivePanel
- StrokeSettingsPanel
- AnimationTimeline
- FloatingPieceOverlayView
- .load
- LayerOptionsPanel
- CGPoint
- .manager
- InterpolationModelLogicTests
- ProjectSaveLogicTests
- BrushDynamics
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- .stampCircle
- SwiftUI
- ShapeGeometry
- DeformFactorization
- PerfMonitor
- Coordinator
- Color
- Lattice
- Vector Eraser — Design Plan
- LayerRowModel
- Codable
- SideToolbar
- ARAPLogicTests
- CanvasSizePickerView
- ObjectTransformOverlayView
- Is the brush engine ready for `.ABR` / Procreate brush import?
- Identifiable
- Refactor baseline (Stage 0)
- CodingKeys
- HandleKind
- UndoHistory
- CanvasHostView
- PlaybackBoundsCharacterizationTests
- InterpolationPreviewKey
- PaintSoftware - iPad Drawing and Animation App
- StrokeStabilizer
- Vector Interpolation — Implementation Plan
- VectorEraserMode
- GalleryView
- View
- 5. Carry-overs
- Known Issues
- EraserSettingsPanel
- CanvasManager
- BrushGrain
- Equatable
- InterpolationEngineDiagnosticsLogicTests
- ShapeDetector
- InterpolationRefusal
- UIKit
- DrawingView
- BrushBlendMode
- Kind
- InterpolateBar
- XCTestCase
- Atomic
- VECTOR_INTERPOLATION_HANDOFF.md
- parallel_test.sh
- ProjectStore.swift
- BrushShape
- CodingKeys
- 12. Open work
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- fast_test.sh
- status.sh
- 5. Workflow and architecture
- SelectionMode
- BrushSettingsPanel
- TransformOverlaySupport.swift
- CutOutcome
- ActionsMenu
- InterpolationRecipe
- OnionSkinLogicTests
- 11. Moving vector rendering to the GPU
- .group
- 3. Three candidate engines
- 6. Guide strokes
- run.sh
- AppVersion

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 460 edges
2. `CGFloat` - 365 edges
3. `VectorCanvas` - 116 edges
4. `Lattice` - 95 edges
5. `VectorSample` - 95 edges
6. `CanvasManager` - 95 edges
7. `layers` - 81 edges
8. `Coordinator` - 75 edges
9. `ShapeGeometry` - 73 edges
10. `CanvasManager` - 68 edges

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

## Communities (122 total, 7 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

### Community 1 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (41): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+33 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+13 more)

### Community 3 - "CelCRUDCharacterizationTests"
Cohesion: 0.12
Nodes (6): StaticString, String, UInt, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 4 - "TimelineRowView"
Cohesion: 0.06
Nodes (42): NSObject, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 6 - "CanvasManager"
Cohesion: 0.06
Nodes (33): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .currentFrame, .currentLayerIndex, .effectiveLoopRange, .hasLoopBoundary (+25 more)

### Community 7 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 8 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (15): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+7 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.15
Nodes (14): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, ShapeOverlayView (+6 more)

### Community 10 - "CGFloat"
Cohesion: 0.07
Nodes (16): Brush, Void, CGFloat, Sweep, Bool, CGRect, ClosedRange, Double (+8 more)

### Community 11 - "VectorCanvas"
Cohesion: 0.07
Nodes (45): CodableColor, .uiColor, kind, DabLattice, .range, Kind, fill, image (+37 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 13 - "ShapeDetectorLogicTests"
Cohesion: 0.16
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 14 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (29): StrokeInput, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+21 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.07
Nodes (34): CGPathElementType, ContentProvider, Direction, backward, forward, Evaluation, GroupWarp, InterpolationEvaluator (+26 more)

### Community 17 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 18 - "PointCloudIndex"
Cohesion: 0.10
Nodes (17): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+9 more)

### Community 19 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 20 - ".transparentFormat"
Cohesion: 0.11
Nodes (20): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+12 more)

### Community 21 - "String"
Cohesion: 0.06
Nodes (38): CodingKeys, brush, color, composite, elements, fill, fills, id (+30 more)

### Community 22 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 23 - "CanvasManager"
Cohesion: 0.08
Nodes (28): String, UUID, Bool, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+20 more)

### Community 24 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "InterpolationMotionGroupLogicTests"
Cohesion: 0.07
Nodes (19): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+11 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - "LayerTreeCharacterizationTests"
Cohesion: 0.24
Nodes (4): Layer, LayerTreeCharacterizationTests, CanvasManager, String

### Community 28 - ".stampStroke"
Cohesion: 0.17
Nodes (12): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+4 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.18
Nodes (8): PerfBaselineTests, CanvasManager, Double, Int, String, UIImage, UInt64, VectorStroke

### Community 30 - "layers"
Cohesion: 0.16
Nodes (14): .activeLayerIsVector, .interpolationTarget, CanvasManager, Bool, Int, Cel, .endFrame, Int (+6 more)

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
Cohesion: 0.13
Nodes (13): Int64, VectorSample, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect (+5 more)

### Community 35 - ".withStructureUndo"
Cohesion: 0.08
Nodes (20): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, .activeViewName (+12 more)

### Community 36 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 37 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 38 - "AnimationTimeline"
Cohesion: 0.05
Nodes (43): Content, Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder (+35 more)

### Community 39 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 40 - ".load"
Cohesion: 0.13
Nodes (24): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer, CelContent, LayerContent (+16 more)

### Community 41 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+10 more)

### Community 42 - "CGPoint"
Cohesion: 0.11
Nodes (14): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+6 more)

### Community 43 - ".manager"
Cohesion: 0.17
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 46 - "BrushDynamics"
Cohesion: 0.29
Nodes (3): BrushDynamics, Double, UUID

### Community 47 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 48 - "Vector Interpolation — Design Brainstorm"
Cohesion: 0.08
Nodes (26): 0. The brief, 10. Decisions and remaining questions, 11. How clear is the vision, 12. Sources, 1. The central problem, 2. What the codebase already gives us, 4. The load-bearing decision: an inbetween is *derived*, never *stored*, 7.1 Erasers — mostly already solved (+18 more)

### Community 49 - "RasterLayerTexture"
Cohesion: 0.17
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 50 - ".stampCircle"
Cohesion: 0.25
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 51 - "SwiftUI"
Cohesion: 0.12
Nodes (10): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, PhotosUI (+2 more)

### Community 52 - "ShapeGeometry"
Cohesion: 0.08
Nodes (24): Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom, left (+16 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 55 - "Coordinator"
Cohesion: 0.11
Nodes (16): LayerHostView, AppliedTool, CanvasView, Coordinator, CanvasManager, Color, Context, Coordinator (+8 more)

### Community 56 - "Color"
Cohesion: 0.18
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "Lattice"
Cohesion: 0.09
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.09
Nodes (23): 10. Open items (not blocking Phase 0–1), 1. The central problem, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model, 3.1 `StrokeGeometry` (pure functions), 3.2 `StrokeSpatialIndex` (+15 more)

### Community 59 - "LayerRowModel"
Cohesion: 0.05
Nodes (38): IndexPath, LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String (+30 more)

### Community 60 - "Codable"
Cohesion: 0.22
Nodes (20): Codable, LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest (+12 more)

### Community 61 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 62 - "ARAPLogicTests"
Cohesion: 0.13
Nodes (9): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, .rigidMotionL, StaticString, String (+1 more)

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 65 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 66 - "Identifiable"
Cohesion: 0.10
Nodes (20): Identifiable, .motionGroupChips, MotionGroupChip, .id, Layer, Layer, Bool, Cel (+12 more)

### Community 67 - "Refactor baseline (Stage 0)"
Cohesion: 0.10
Nodes (20): After Stage 0's additions, As measured, 2026-07-28, Counting caveat, if you are reading a text log, Drift against the last recorded baseline, Environment, Full suite, Full-suite baseline, Garbage collection was the accumulating term — fixed (+12 more)

### Community 68 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, guideStrokes (+11 more)

### Community 69 - "HandleKind"
Cohesion: 0.13
Nodes (15): HandleKind, axisBottom, axisLeft, axisRight, axisTop, cornerBL, cornerBR, cornerTL (+7 more)

### Community 70 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 71 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 72 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.17
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 73 - "InterpolationPreviewKey"
Cohesion: 0.17
Nodes (8): InterpolationPreviewKey, Bool, Int, Layer, Set, UIGestureRecognizer, UIImage, UUID

### Community 74 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.12
Nodes (17): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+9 more)

### Community 75 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 76 - "Vector Interpolation — Implementation Plan"
Cohesion: 0.10
Nodes (21): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless), Phase 4.7 — Engine correctness: what the deformation actually does — ***DONE (Session 12)*** (+13 more)

### Community 77 - "VectorEraserMode"
Cohesion: 0.13
Nodes (14): Hashable, Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode (+6 more)

### Community 78 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

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
Cohesion: 0.09
Nodes (17): CanvasManager, .hasAnonymousWholeFrameGroup, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, GroupRegistration, RegistrationElement, Bool (+9 more)

### Community 85 - "Equatable"
Cohesion: 0.18
Nodes (13): Equatable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+5 more)

### Community 86 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.24
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 87 - "ShapeDetector"
Cohesion: 0.21
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 88 - "InterpolationRefusal"
Cohesion: 0.19
Nodes (11): InterpolationRefusal, alreadyInterpolated, .message, notAVectorLayer, notEnoughReferences, referencesAreEmpty, reprojectNotImplemented, targetIsAReference (+3 more)

### Community 89 - "UIKit"
Cohesion: 0.06
Nodes (8): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, ThumbnailRenderer, UIKit, XCTest

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - "BrushBlendMode"
Cohesion: 0.13
Nodes (14): CaseIterable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+6 more)

### Community 92 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 93 - "InterpolateBar"
Cohesion: 0.14
Nodes (15): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .referenceButton, .referenceSummary, .removeButton (+7 more)

### Community 94 - "XCTestCase"
Cohesion: 0.29
Nodes (5): CanvasFixture, CanvasManager, Int, UUID, XCTestCase

### Community 95 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 96 - "VECTOR_INTERPOLATION_HANDOFF.md"
Cohesion: 0.23
Nodes (6): Deploy to iPad, Finish and merge, graphify, Multi-Session Protocol, Remote testing (Tailscale → Mac, no Xcode on this machine), Work in a worktree

### Community 97 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 98 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 99 - "BrushShape"
Cohesion: 0.22
Nodes (9): BrushShape, custom, .displayName, hardRound, .id, pen, pencil, softRound (+1 more)

### Community 100 - "CodingKeys"
Cohesion: 0.08
Nodes (26): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+18 more)

### Community 101 - "12. Open work"
Cohesion: 0.40
Nodes (5): 12. Open work, GPU rendering, Per-element Move, Still open, The spatial index is rebuilt from scratch on every `invalidate()`

### Community 109 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 111 - "SelectionMode"
Cohesion: 0.15
Nodes (11): CanvasManager, Bool, CGSize, UIImage, SelectionMode, automatic, .displayName, .id (+3 more)

### Community 112 - "BrushSettingsPanel"
Cohesion: 0.20
Nodes (10): BrushLibrary, .customBrushesDirectory, URL, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager (+2 more)

### Community 113 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 119 - "InterpolationRecipe"
Cohesion: 0.18
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 121 - "OnionSkinLogicTests"
Cohesion: 0.23
Nodes (6): OnionSkinSource, PreviousCelOnionSkinSource, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 122 - "11. Moving vector rendering to the GPU"
Cohesion: 0.33
Nodes (6): 11. Moving vector rendering to the GPU, The number, The z-order optimisation, when it is needed, What is already on the GPU, What Phase 2 did to keep the door open, Why not now

### Community 123 - ".group"
Cohesion: 0.19
Nodes (6): Group, MotionGrouping, Options, Int, Set, groups

### Community 124 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

### Community 125 - "6. Guide strokes"
Cohesion: 0.40
Nodes (5): 6.1 What they are, 6.2 The controls from requirement 6, 6.3 The data gap, 6.4 Reuse across frames (requirement 7), 6. Guide strokes

### Community 129 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

## Knowledge Gaps
- **562 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+557 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `TimelineRowView`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeDetectorLogicTests`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `.setUpGestures`, `.transparentFormat`, `String`, `CanvasManager`, `CanvasManager`, `InterpolationMotionGroupLogicTests`, `.stampStroke`, `PerfBaselineTests`, `VectorSample`, `StrokeSettingsPanel`, `AnimationTimeline`, `.load`, `CGPoint`, `InterpolationModelLogicTests`, `BrushDynamics`, `RasterLayerTexture`, `.stampCircle`, `ShapeGeometry`, `DeformFactorization`, `Coordinator`, `Color`, `Lattice`, `LayerRowModel`, `SideToolbar`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `InterpolationPreviewKey`, `StrokeStabilizer`, `EraserSettingsPanel`, `CanvasManager`, `BrushGrain`, `Equatable`, `InterpolationEngineDiagnosticsLogicTests`, `ShapeDetector`, `UIKit`, `DrawingView`, `BrushBlendMode`, `Kind`, `InterpolateBar`, `SelectionMode`, `TransformOverlaySupport.swift`, `ActionsMenu`, `InterpolationRecipe`, `OnionSkinLogicTests`, `.group`?**
  _High betweenness centrality (0.317) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `VectorEraserHybridLogicTests`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `CGFloat`, `VectorCanvas`, `BrushEngineLogicTests`, `ShapeDetectorLogicTests`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `PointCloudIndex`, `.setUpGestures`, `.transparentFormat`, `String`, `CanvasManager`, `CanvasManager`, `InterpolationMotionGroupLogicTests`, `.stampStroke`, `PerfBaselineTests`, `layers`, `VectorSample`, `AnimationTimeline`, `FloatingPieceOverlayView`, `InterpolationModelLogicTests`, `ProjectSaveLogicTests`, `SelectionOverlayView`, `RasterLayerTexture`, `.stampCircle`, `ShapeGeometry`, `DeformFactorization`, `Coordinator`, `Lattice`, `LayerRowModel`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `HandleKind`, `StrokeStabilizer`, `CanvasManager`, `BrushGrain`, `Equatable`, `InterpolationEngineDiagnosticsLogicTests`, `ShapeDetector`, `UIKit`, `BrushBlendMode`, `SelectionMode`, `TransformOverlaySupport.swift`, `InterpolationRecipe`, `.group`?**
  _High betweenness centrality (0.191) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CGFloat`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `layers`, `CanvasManager`, `VectorSample`, `.withStructureUndo`, `RasterLayerTexture`, `SwiftUI`, `ShapeGeometry`, `PerfMonitor`, `Codable`, `Identifiable`, `UndoHistory`, `VectorEraserMode`, `Equatable`, `SelectionMode`, `InterpolationRecipe`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `Lattice` (e.g. with `.visible()` and `.registerGroups()`) actually correct?**
  _`Lattice` has 9 INFERRED edges - model-reasoned connections that need verification._