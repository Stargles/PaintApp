# Graph Report - vector-interpolation-keyframes-d484df  (2026-08-05)

## Corpus Check
- 145 files · ~314,011 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3541 nodes · 10340 edges · 146 communities (137 shown, 9 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1276 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `93b7e022`
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
- agent
- StrokeGeometryLogicTests
- ShapeOverlayView
- VectorEraserLogicTests
- VectorCanvas
- BrushEngineLogicTests
- Codable
- CanvasManager
- StrokeCanvasView
- InterpolationRenderLogicTests
- ContentView
- ARAPRegistration
- Coordinator
- .transparentFormat
- CodingKeys
- CGFloat
- CanvasManager
- CanvasManager
- InterpolationMotionGroupLogicTests
- MetalFillEngine
- .warped
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
- CGPoint
- LayerRowModel
- InterpolationModelLogicTests
- .validateProject
- Identifiable
- SelectionOverlayView
- Vector Interpolation — Design Brainstorm
- RasterLayerTexture
- Foundation
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
- bash
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
- GuideStroke
- InterpolationEngineDiagnosticsLogicTests
- ShapeDetector
- InterpolationRefusal
- UIKit
- DrawingView
- .registerGroups
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
- .renderToUIImage
- 5. Workflow and architecture
- 0. The brief
- ShapeDetectorLogicTests
- .setCanvasPadding
- UIView
- Edge
- CutOutcome
- ActionsMenu
- HandleKind
- GalleryView
- InterpolationRecipe
- InterpolationPreviewKey
- 8. Suggested follow-on work
- BrushSettingsPanel
- PointCloudIndex
- Vector Interpolation — Handoff & Session Protocol
- PaintApp
- run.sh
- 3. Session protocol
- CaseIterable
- ManifestSkeleton
- Atomic
- 4. Build and test
- Corner
- main.swift
- command
- InterpolatePanel
- OnionSkinFrame
- 3. Three candidate engines
- .render
- orchestrator
- worker-feature
- worker-research
- worker-test
- 4. Per-mode implementation
- .init
- .init

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 463 edges
2. `CGFloat` - 368 edges
3. `VectorCanvas` - 116 edges
4. `Lattice` - 96 edges
5. `VectorSample` - 95 edges
6. `CanvasManager` - 95 edges
7. `layers` - 81 edges
8. `Coordinator` - 75 edges
9. `ShapeGeometry` - 73 edges
10. `CanvasManager` - 69 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `.body` --calls--> `ContentView`  [INFERRED]
  PaintSoftware/PaintApp.swift → PaintSoftware/ContentView.swift

## Import Cycles
- None detected.

## Communities (146 total, 9 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.07
Nodes (21): CGVector, FillUITests, LayerUITests, PaintUITestCase, Bool, Double, Int, String (+13 more)

### Community 1 - "ParityScenario"
Cohesion: 0.09
Nodes (33): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+25 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.10
Nodes (21): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+13 more)

### Community 3 - ".manager"
Cohesion: 0.05
Nodes (24): OnionSkinSource, PreviousCelOnionSkinSource, CanvasFixture, CanvasManager, Int, Layer, StaticString, String (+16 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.07
Nodes (40): CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool, CanvasManager (+32 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 6 - "CanvasManager"
Cohesion: 0.05
Nodes (44): Hashable, CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .effectiveLoopRange, .hasLoopBoundary, .isFillInAdjustableState (+36 more)

### Community 7 - "agent"
Cohesion: 0.11
Nodes (17): agent, worker-bugfix, worker-integration, worker-ui, model, plugin, $schema, description (+9 more)

### Community 8 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (15): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+7 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.14
Nodes (14): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, ShapeOverlayView (+6 more)

### Community 10 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 11 - "VectorCanvas"
Cohesion: 0.10
Nodes (25): kind, RenderQuality, full, preview, Bool, CGAffineTransform, CGContext, CGRect (+17 more)

### Community 12 - "BrushEngineLogicTests"
Cohesion: 0.18
Nodes (9): BrushEngineLogicTests, Any, CodableColor, Data, Double, String, T, UIColor (+1 more)

### Community 13 - "Codable"
Cohesion: 0.08
Nodes (36): Codable, CodableColor, .uiColor, DabLattice, .range, ElementData, fill, image (+28 more)

### Community 14 - "CanvasManager"
Cohesion: 0.15
Nodes (12): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+4 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.11
Nodes (20): StrokeInput, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas, Bool (+12 more)

### Community 16 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 17 - "ContentView"
Cohesion: 0.20
Nodes (9): AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager, MainActor (+1 more)

### Community 18 - "ARAPRegistration"
Cohesion: 0.14
Nodes (13): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, Result, Similarity (+5 more)

### Community 19 - "Coordinator"
Cohesion: 0.11
Nodes (18): NSObject, AppliedTool, Coordinator, CanvasManager, CGSize, Color, Date, Double (+10 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.13
Nodes (16): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+8 more)

### Community 21 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 22 - "CGFloat"
Cohesion: 0.14
Nodes (10): Brush, CGFloat, VectorSample, Sweep, Bool, CGRect, ClosedRange, Double (+2 more)

### Community 23 - "CanvasManager"
Cohesion: 0.06
Nodes (37): .currentFrame, .currentLayerIndex, String, UUID, Bool, CanvasManager, FloatingPiece, .transformedBounds (+29 more)

### Community 24 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "InterpolationMotionGroupLogicTests"
Cohesion: 0.07
Nodes (19): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+11 more)

### Community 26 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 27 - ".warped"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+13 more)

### Community 28 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 29 - "PerfBaselineTests"
Cohesion: 0.24
Nodes (6): PerfBaselineTests, CanvasManager, Double, String, UInt64, VectorStroke

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
Cohesion: 0.19
Nodes (12): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, ClosedRange, Int (+4 more)

### Community 34 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 35 - ".withStructureUndo"
Cohesion: 0.10
Nodes (15): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, .activeViewName (+7 more)

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
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 40 - ".load"
Cohesion: 0.19
Nodes (16): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CanvasManager (+8 more)

### Community 41 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+10 more)

### Community 42 - "CGPoint"
Cohesion: 0.11
Nodes (8): CGPoint, .length, .point, LatticeLogicTests, Int, StaticString, String, UInt

### Community 43 - "LayerRowModel"
Cohesion: 0.21
Nodes (8): LayerRowModel, .folderID, Bool, Double, String, UIImage, UILongPressGestureRecognizer, UIPinchGestureRecognizer

### Community 44 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 45 - ".validateProject"
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
Cohesion: 0.10
Nodes (20): CGGradient, CGContextDabTarget, DabGradientCache, Key, RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent (+12 more)

### Community 50 - "Foundation"
Cohesion: 0.12
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 51 - "SwiftUI"
Cohesion: 0.20
Nodes (3): Combine, PhotosUI, SwiftUI

### Community 52 - "ShapeGeometry"
Cohesion: 0.11
Nodes (14): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+6 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.10
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 54 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 55 - ".makeUIView"
Cohesion: 0.13
Nodes (7): LayerHostView, CanvasView, Context, Coordinator, LayerTransform, UIImageView, UIViewRepresentable

### Community 56 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 57 - "Lattice"
Cohesion: 0.09
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 58 - "Vector Eraser — Design Plan"
Cohesion: 0.07
Nodes (30): 10. Open items (not blocking Phase 0–1), 11. Moving vector rendering to the GPU, 12. Open work, 1. The central problem, 2.1 The eraser *is* a stroke, 2.2 Unified display list, 2.3 Persistence, 2. Data model (+22 more)

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
Cohesion: 0.13
Nodes (7): ARAPInterpolation, ARAPLogicTests, .rigidMotionL, Int, StaticString, String, UInt

### Community 63 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

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

### Community 69 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 70 - "UndoHistory"
Cohesion: 0.23
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
Cohesion: 0.09
Nodes (23): Conventions for every phase, Explicitly deferred — do not build these, Feature definition of done, Item 1 is done (Session 15, `93b7e02`), Phase 0 — Onion-skin seam and the vector onion-skin bug, Phase 1 — Lattice and ARAP engine (pure logic), Phase 2 — Data model, persistence, undo (feature still inert), Phase 3 — Evaluation, isolated compositing, preview tier (headless) (+15 more)

### Community 77 - ".stampStroke"
Cohesion: 0.13
Nodes (14): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+6 more)

### Community 78 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UIView, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 79 - "View"
Cohesion: 0.13
Nodes (17): .body, MotionGroupRow, .body, .colourBakeButton, .wholeFrameNote, CanvasManager, String, SelectPanel (+9 more)

### Community 80 - "5. Carry-overs"
Cohesion: 0.11
Nodes (19): 5.10 For Phase 5's motion groups, 5.11 What the papers do — and where they do not help, 5.7 The lattice encoding — *answered, kept for the constraint*, 5.8 For Phase 3's evaluator, 5.9 For Phase 4's UI, 5. Carry-overs, From Phase 1, From Phase 2 (+11 more)

### Community 81 - "Known Issues"
Cohesion: 0.14
Nodes (12): `duplicateCel` can create a cel overlapping its immediate neighbour (2026-07-28), Feature audit (2026-07-22) — item 9 still open, Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21), Fill tool: off-center fill vertically mirrored — previously FIXED 2026-07-22, now failing again (2026-07-26), Fix (Stage 4.3), Follow-up: Duplicate is now a silent no-op in that adjacency (low priority, NOT part of Stage 4), Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit, Housekeeping (2026-07-26): 8 items fixed from the 2026-07-22 feature audit (+4 more)

### Community 82 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 83 - "CanvasManager"
Cohesion: 0.10
Nodes (17): CanvasManager, .hasAnonymousWholeFrameGroup, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .motionGroupChips, MotionGroupChip, .id (+9 more)

### Community 84 - "LayerStackListView"
Cohesion: 0.20
Nodes (7): IndexPath, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView

### Community 85 - "GuideStroke"
Cohesion: 0.13
Nodes (17): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+9 more)

### Community 86 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.26
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 87 - "ShapeDetector"
Cohesion: 0.21
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 88 - "InterpolationRefusal"
Cohesion: 0.18
Nodes (12): InterpolationRefusal, alreadyInterpolated, .message, notAVectorLayer, notEnoughReferences, nothingToReproject, referencesAreEmpty, targetIsAReference (+4 more)

### Community 89 - "UIKit"
Cohesion: 0.09
Nodes (5): CoreGraphics, Darwin, LayerTransform, UIKit, XCTest

### Community 90 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 91 - ".registerGroups"
Cohesion: 0.25
Nodes (3): GroupRegistration, RegistrationElement, RegistrationFrame

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
Cohesion: 0.10
Nodes (20): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+12 more)

### Community 101 - "BackupManagerLogicTests"
Cohesion: 0.21
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 109 - "5. Workflow and architecture"
Cohesion: 0.22
Nodes (9): 5.0 The loop in practice, 5.1.1 Tagging: a separate attribute, with a "bake from paint colour" action, 5.1 Motion groups are document-level, not layer-level, 5.2 The lattice, 5.3 Grouping and registration: one hierarchical algorithm serving both workflows, 5.4 Editing at an intermediate frame — the inverse map, 5.5 Interpolating a non-blank frame — two modes, 5.6 Rendering an interpolated cel (+1 more)

### Community 110 - "0. The brief"
Cohesion: 0.40
Nodes (5): 0. The brief, Goal, Key technical & UX edge cases (referenced as "edge case N"), Notes (referenced elsewhere as "requirement N" / "note N"), The workflow, as specified

### Community 111 - "ShapeDetectorLogicTests"
Cohesion: 0.19
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 112 - ".setCanvasPadding"
Cohesion: 0.33
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 113 - "UIView"
Cohesion: 0.16
Nodes (11): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+3 more)

### Community 114 - "Edge"
Cohesion: 0.25
Nodes (5): Edge, bottom, left, right, top

### Community 115 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 116 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 117 - "HandleKind"
Cohesion: 0.13
Nodes (15): HandleKind, axisBottom, axisLeft, axisRight, axisTop, cornerBL, cornerBR, cornerTL (+7 more)

### Community 118 - "GalleryView"
Cohesion: 0.15
Nodes (12): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void (+4 more)

### Community 119 - "InterpolationRecipe"
Cohesion: 0.17
Nodes (14): Equatable, KeyframeInterval, CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit (+6 more)

### Community 120 - "InterpolationPreviewKey"
Cohesion: 0.17
Nodes (8): InterpolationPreviewKey, Bool, Int, Layer, Set, UIGestureRecognizer, UIImage, UUID

### Community 121 - "8. Suggested follow-on work"
Cohesion: 0.20
Nodes (10): 8. Suggested follow-on work, From Phase 1, From Phase 2, From Phase 3, From Phase 4, From Phase 4.5 — noticed while working, From Phase 4.5 — the product owner's own list, From Phase 4.6 — the engine does not do what it is supposed to do (+2 more)

### Community 122 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 123 - "PointCloudIndex"
Cohesion: 0.16
Nodes (9): PointCloudIndex, .isEmpty, Group, MotionGrouping, Options, Bool, Int, Set (+1 more)

### Community 124 - "Vector Interpolation — Handoff & Session Protocol"
Cohesion: 0.22
Nodes (9): 1. Start-of-session checklist, 2. Current state, 6. Session log, 7. Handoff prompt template, History note, Reading budget, Vector Interpolation — Handoff & Session Protocol, What is done (+1 more)

### Community 125 - "PaintApp"
Cohesion: 0.29
Nodes (5): App, task, PaintApp, .body, Scene

### Community 127 - "3. Session protocol"
Cohesion: 0.29
Nodes (7): 3.1 Commit early, commit often, 3.2 The >92% usage handoff, 3.3 Scope discipline — when to stop, 3.4 Subagent budget — hard limits, 3.5 Never silently change a decision, 3. Session protocol, Model and effort, per task shape

### Community 128 - "CaseIterable"
Cohesion: 0.33
Nodes (5): CaseIterable, Kind, line, oval, rectangle

### Community 129 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 130 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 131 - "4. Build and test"
Cohesion: 0.33
Nodes (6): 4. Build and test, After changing code, Build only — fastest possible check that it compiles, Fast run — pure logic only (~1–2 min). Use this constantly., Full run (~22 min, 63 XCUITests). Rarely — at phase boundaries only., Reading a failure

### Community 132 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 133 - "main.swift"
Cohesion: 0.33
Nodes (6): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int

### Community 134 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 135 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 136 - "OnionSkinFrame"
Cohesion: 0.40
Nodes (4): OnionSkinFrame, CGSize, UIColor, UIImage

### Community 137 - "3. Three candidate engines"
Cohesion: 0.33
Nodes (6): 3. Three candidate engines, A. Stroke correspondence + per-stroke interpolation, B. Raster morph (dense warp + cross-dissolve), C. Lattice embedding + ARAP warp — *recommended*, D. Hybrid — lattice motion, correspondence where confident — *recommended as phase 2*, The decision: C as substrate, D per group, artist-overridable

### Community 138 - ".render"
Cohesion: 0.40
Nodes (3): CGSize, UIImage, ThumbnailRenderer

### Community 139 - "orchestrator"
Cohesion: 0.50
Nodes (4): orchestrator, description, mode, model

### Community 140 - "worker-feature"
Cohesion: 0.50
Nodes (4): worker-feature, description, mode, model

### Community 141 - "worker-research"
Cohesion: 0.50
Nodes (4): worker-research, description, mode, model

### Community 142 - "worker-test"
Cohesion: 0.50
Nodes (4): worker-test, description, mode, model

### Community 143 - "4. Per-mode implementation"
Cohesion: 0.50
Nodes (4): 4. Per-mode implementation, Mode 1 — Erase, Mode 2 — Cut points (rewrite of what exists), Mode 3 — Cut to intersection

## Knowledge Gaps
- **566 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+561 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `CaseIterable`, `.launchIntoEditor`, `ParityScenario`, `.manager`, `TimelineRowView`, `main.swift`, `CanvasManager`, `StrokeGeometryLogicTests`, `OnionSkinFrame`, `VectorEraserLogicTests`, `VectorCanvas`, `ShapeOverlayView`, `Codable`, `CanvasManager`, `StrokeCanvasView`, `BrushEngineLogicTests`, `InterpolationRenderLogicTests`, `ARAPRegistration`, `Coordinator`, `.transparentFormat`, `CodingKeys`, `CanvasManager`, `CanvasManager`, `InterpolationMotionGroupLogicTests`, `.warped`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `AnimationTimeline`, `FloatingPieceOverlayView`, `.load`, `CGPoint`, `InterpolationModelLogicTests`, `Identifiable`, `RasterLayerTexture`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `Color`, `Lattice`, `LayerStackCell`, `SideToolbar`, `ARAPLogicTests`, `Coordinator`, `StrokeStabilizer`, `.stampStroke`, `EraserSettingsPanel`, `CanvasManager`, `LayerStackListView`, `GuideStroke`, `InterpolationEngineDiagnosticsLogicTests`, `ShapeDetector`, `UIKit`, `DrawingView`, `.registerGroups`, `Kind`, `InterpolateBar`, `ShapeDetectorLogicTests`, `.setCanvasPadding`, `UIView`, `ActionsMenu`, `InterpolationRecipe`, `InterpolationPreviewKey`, `PointCloudIndex`?**
  _High betweenness centrality (0.316) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `CaseIterable`, `ParityScenario`, `TimelineRowView`, `main.swift`, `CanvasManager`, `ColorPickerPanel`, `StrokeGeometryLogicTests`, `ShapeOverlayView`, `VectorEraserLogicTests`, `VectorCanvas`, `BrushEngineLogicTests`, `CanvasManager`, `StrokeCanvasView`, `InterpolationRenderLogicTests`, `ARAPRegistration`, `Coordinator`, `.transparentFormat`, `CGFloat`, `CanvasManager`, `CanvasManager`, `InterpolationMotionGroupLogicTests`, `.warped`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `layers`, `StrokeSpatialIndex`, `AnimationTimeline`, `FloatingPieceOverlayView`, `InterpolationModelLogicTests`, `.validateProject`, `SelectionOverlayView`, `RasterLayerTexture`, `ShapeGeometry`, `DeformFactorization`, `.makeUIView`, `Lattice`, `ARAPLogicTests`, `ObjectTransformOverlayView`, `StrokeStabilizer`, `.stampStroke`, `LayerStackListView.Coordinator`, `CanvasManager`, `GuideStroke`, `InterpolationEngineDiagnosticsLogicTests`, `ShapeDetector`, `UIKit`, `.registerGroups`, `.renderToUIImage`, `ShapeDetectorLogicTests`, `.setCanvasPadding`, `UIView`, `Edge`, `HandleKind`, `InterpolationRecipe`, `PointCloudIndex`?**
  _High betweenness centrality (0.185) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CanvasManager`, `.transparentFormat`, `CGFloat`, `CanvasManager`, `CanvasManager`, `MetalFillEngine`, `layers`, `CanvasManager`, `.withStructureUndo`, `RasterLayerTexture`, `SwiftUI`, `ShapeGeometry`, `PerfMonitor`, `ProjectManifest`, `MotionGroup`, `UndoHistory`, `GuideStroke`, `.setCanvasPadding`, `InterpolationRecipe`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CGFloat` (e.g. with `.load()` and `.resolvedUIColor()`) actually correct?**
  _`CGFloat` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.flat()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `Lattice` (e.g. with `.visible()` and `.registerGroups()`) actually correct?**
  _`Lattice` has 10 INFERRED edges - model-reasoned connections that need verification._