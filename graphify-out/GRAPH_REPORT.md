# Graph Report - laptop-tailscale-connection-78ec13  (2026-08-11)

## Corpus Check
- 157 files · ~295,979 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3870 nodes · 11781 edges · 143 communities (132 shown, 11 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1385 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2eb3eb3e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- .launchIntoEditor
- ParityScenario
- Coordinator
- CanvasManager
- VectorCanvas
- PerfBaselineTests
- StrokeCanvasView
- bash
- ProjectBackupManager
- CGPoint
- ColorPickerPanel
- CanvasManager
- FloatingPiece
- .manager
- CompositorParityLogicTests
- PointCloudIndex
- VectorEraserLogicTests
- Lattice
- BrushEngineLogicTests
- .transparentFormat
- AnimationTimeline
- ViewPreset
- VectorEraserHybridLogicTests
- CanvasManager
- RasterLayerTexture
- InterpolationRenderLogicTests
- .load
- StrokeGeometryLogicTests
- InterpolationRecipe
- .evaluate
- UIKit
- ARAPLogicTests
- .setUpGestures
- .analyse
- layers
- ShapeGeometry
- PlaybackBoundsCharacterizationTests
- BrushBlendMode
- ProjectManifest
- StrokeSpatialIndex
- VectorSample
- GuideOverlayView
- LayerTreeCharacterizationTests
- MetalFillEngine
- CanvasManager
- BackupManagerLogicTests
- FillParams
- FloatingPieceOverlayView
- CanvasManager
- TouchCountRecognizer
- Coordinator
- Layer Compositing
- CodingKeys
- ActivePanel
- ViewPresetCharacterizationTests
- LayerStackCell
- InterpolationGuideLogicTests
- StrokeSettingsPanel
- ShapeOverlayView
- View
- String
- CanvasManager
- LayerOptionsPanel
- StructureSnapshot
- BlockDragCharacterizationTests
- .indices
- CanvasManager
- ProjectSaveLogicTests
- SelectionOverlayView
- RenderRequest
- CompositorMetalEngine
- .manager
- ContentView
- XCTestCase
- Foundation
- Color
- EraserSettingsPanel
- InterpolationEngineDiagnosticsLogicTests
- PerfMonitor
- .stampStroke
- CodingKeys
- InterpolateBar
- SelectPanel
- .arched
- CGFloat
- TimedSample
- CanvasSizePickerView
- SwiftUI
- MotionGroup
- SideToolbar
- UndoHistory
- ObjectTransformOverlayView
- TransformOverlaySupport.swift
- Tool
- CanvasHostView
- OnionSkinLogicTests
- .assertCut
- SpacingChart
- LayerStackRow
- Coordinator
- .composite
- TransformMode
- RenderNode
- 4. Future upgrades — the deferred list
- CGContextDabTarget
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView.Coordinator
- StrokeStabilizer
- .refreshUndoRedoState
- PaintSoftware - iPad Drawing and Animation App
- LayerStackListView
- Layer
- VectorScratchRole
- Usage Guide
- CutOutcome
- DrawingView
- BrushSettingsPanel
- LayerRowModel
- CLAUDE.md
- Known Issues
- Atomic
- ManifestSkeleton
- ProjectStore.swift
- ProjectSummary
- What needs to change
- Multi-Session Protocol
- parallel_test.sh
- Kind
- Performance baseline
- InterpolatePanel
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- Deterministic
- MetalCompositor.swift
- FillAxis

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 533 edges
2. `CGFloat` - 407 edges
3. `VectorCanvas` - 122 edges
4. `layers` - 107 edges
5. `CanvasManager` - 100 edges
6. `CanvasManager` - 99 edges
7. `Lattice` - 98 edges
8. `VectorSample` - 98 edges
9. `InterpolationGuideLogicTests` - 90 edges
10. `Coordinator` - 79 edges

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

## Communities (143 total, 11 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 1 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 2 - "ParityScenario"
Cohesion: 0.09
Nodes (33): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+25 more)

### Community 3 - "Coordinator"
Cohesion: 0.06
Nodes (43): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+35 more)

### Community 4 - "CanvasManager"
Cohesion: 0.05
Nodes (39): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+31 more)

### Community 5 - "VectorCanvas"
Cohesion: 0.06
Nodes (50): AnyObject, Identifiable, DabTarget, CodableColor, .uiColor, image, kind, DabLattice (+42 more)

### Community 6 - "PerfBaselineTests"
Cohesion: 0.19
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 7 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (25): StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+17 more)

### Community 8 - "bash"
Cohesion: 0.05
Nodes (63): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+55 more)

### Community 9 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+13 more)

### Community 10 - "CGPoint"
Cohesion: 0.09
Nodes (8): CGPoint, .length, LatticeLogicTests, Int, StaticString, String, UInt, .samples

### Community 11 - "ColorPickerPanel"
Cohesion: 0.08
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 12 - "CanvasManager"
Cohesion: 0.05
Nodes (40): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .effectiveLoopRange, .hasLoopBoundary, .isFillInAdjustableState (+32 more)

### Community 13 - "FloatingPiece"
Cohesion: 0.12
Nodes (19): FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform, Selection (+11 more)

### Community 14 - ".manager"
Cohesion: 0.13
Nodes (5): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 15 - "CompositorParityLogicTests"
Cohesion: 0.11
Nodes (15): CanvasFixture, CGImage, CGRect, CGSize, UIColor, UIImage, UInt8, CompositorParityLogicTests (+7 more)

### Community 16 - "PointCloudIndex"
Cohesion: 0.11
Nodes (16): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+8 more)

### Community 17 - "VectorEraserLogicTests"
Cohesion: 0.18
Nodes (3): VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 18 - "Lattice"
Cohesion: 0.05
Nodes (39): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+31 more)

### Community 19 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.15
Nodes (15): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+7 more)

### Community 21 - "AnimationTimeline"
Cohesion: 0.07
Nodes (31): Gesture, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .gapMenu (+23 more)

### Community 22 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 23 - "VectorEraserHybridLogicTests"
Cohesion: 0.13
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 24 - "CanvasManager"
Cohesion: 0.14
Nodes (11): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+3 more)

### Community 25 - "RasterLayerTexture"
Cohesion: 0.16
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 26 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 27 - ".load"
Cohesion: 0.15
Nodes (19): BrushLibrary, .customBrushesDirectory, URL, CelContent, LayerContent, ProjectStore, .projectsDirectory, SaveSnapshot (+11 more)

### Community 28 - "StrokeGeometryLogicTests"
Cohesion: 0.11
Nodes (6): StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 29 - "InterpolationRecipe"
Cohesion: 0.06
Nodes (37): Codable, Equatable, Hashable, GuideRole, both, timing, trajectory, GuideStroke (+29 more)

### Community 30 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 31 - "UIKit"
Cohesion: 0.08
Nodes (5): CoreGraphics, Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 32 - "ARAPLogicTests"
Cohesion: 0.11
Nodes (8): ARAPInterpolation, groups, ARAPLogicTests, .rigidMotionL, Int, StaticString, String, UInt

### Community 33 - ".setUpGestures"
Cohesion: 0.14
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 34 - ".analyse"
Cohesion: 0.29
Nodes (6): Group, MotionGrouping, Options, Bool, Int, Set

### Community 35 - "layers"
Cohesion: 0.12
Nodes (14): .activeLayerIsVector, .currentFrame, .currentLayerIndex, .activeCelIsInBetween, CanvasManager, Bool, Int, Void (+6 more)

### Community 36 - "ShapeGeometry"
Cohesion: 0.05
Nodes (28): Int, Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom (+20 more)

### Community 37 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 38 - "BrushBlendMode"
Cohesion: 0.07
Nodes (28): CaseIterable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+20 more)

### Community 39 - "ProjectManifest"
Cohesion: 0.14
Nodes (27): LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest, LayerManifest (+19 more)

### Community 40 - "StrokeSpatialIndex"
Cohesion: 0.18
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 41 - "VectorSample"
Cohesion: 0.09
Nodes (18): Brush, VectorSample, .point, Capsule, .boundingBox, StrokeGeometry, Bool, CGRect (+10 more)

### Community 42 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 43 - "LayerTreeCharacterizationTests"
Cohesion: 0.21
Nodes (5): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String

### Community 44 - "MetalFillEngine"
Cohesion: 0.18
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 45 - "CanvasManager"
Cohesion: 0.16
Nodes (16): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+8 more)

### Community 46 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 47 - "FillParams"
Cohesion: 0.18
Nodes (28): device, float4, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+20 more)

### Community 48 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 49 - "CanvasManager"
Cohesion: 0.26
Nodes (5): CanvasManager, Bool, Int, UIImage, UUID

### Community 50 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 51 - "Coordinator"
Cohesion: 0.08
Nodes (23): LayerHostView, AppliedTool, CanvasView, Coordinator, InterpolationPreviewKey, Bool, CanvasManager, Color (+15 more)

### Community 52 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 53 - "CodingKeys"
Cohesion: 0.08
Nodes (26): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+18 more)

### Community 54 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, move (+9 more)

### Community 55 - "ViewPresetCharacterizationTests"
Cohesion: 0.12
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 56 - "LayerStackCell"
Cohesion: 0.12
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 58 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 59 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 60 - "View"
Cohesion: 0.13
Nodes (17): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+9 more)

### Community 61 - "String"
Cohesion: 0.07
Nodes (35): CodingKeys, brush, color, composite, elements, fill, fills, id (+27 more)

### Community 62 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 63 - "LayerOptionsPanel"
Cohesion: 0.16
Nodes (17): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .header (+9 more)

### Community 64 - "StructureSnapshot"
Cohesion: 0.18
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 65 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 67 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 68 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 69 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 70 - "RenderRequest"
Cohesion: 0.21
Nodes (12): Leaf, MetalCompositor, Double, CanvasManager, LayerRenderSource, RenderBackground, RenderRequest, Bool (+4 more)

### Community 71 - "CompositorMetalEngine"
Cohesion: 0.27
Nodes (8): MTLTexture, CompositorMetalEngine, CGImage, Int, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice

### Community 72 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 73 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 74 - "XCTestCase"
Cohesion: 0.21
Nodes (7): StaticString, String, UInt, XCTestCase, RenderTreeCharacterizationTests, CanvasManager, String

### Community 75 - "Foundation"
Cohesion: 0.15
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 76 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 77 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 78 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 79 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 80 - ".stampStroke"
Cohesion: 0.13
Nodes (12): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+4 more)

### Community 81 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, id (+10 more)

### Community 82 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 83 - "SelectPanel"
Cohesion: 0.11
Nodes (16): .body, MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void, SelectPanel (+8 more)

### Community 84 - ".arched"
Cohesion: 0.25
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 85 - "CGFloat"
Cohesion: 0.10
Nodes (13): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, ClosedFit (+5 more)

### Community 86 - "TimedSample"
Cohesion: 0.12
Nodes (8): GuidePath, .end, .start, TimeInterval, TimeInterval, TimedSample, .point, TimeInterval

### Community 87 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 88 - "SwiftUI"
Cohesion: 0.18
Nodes (3): Combine, PhotosUI, SwiftUI

### Community 89 - "MotionGroup"
Cohesion: 0.19
Nodes (10): GroupRegistration, Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor (+2 more)

### Community 90 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 91 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 92 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 93 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 94 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 95 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 96 - "OnionSkinLogicTests"
Cohesion: 0.16
Nodes (10): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CGSize, UIColor, UIImage, OnionSkinLogicTests, Bool (+2 more)

### Community 97 - ".assertCut"
Cohesion: 0.27
Nodes (3): ClosedRange, StaticString, UInt

### Community 98 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 99 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 100 - "Coordinator"
Cohesion: 0.26
Nodes (8): NSObject, Coordinator, CanvasManager, Int, Set, UIView, UUID, UITableViewDiffableDataSource

### Community 101 - ".composite"
Cohesion: 0.27
Nodes (7): Compositor, CompositorBackend, coreGraphics, metal, CoreGraphicsCompositor, CGImage, CGRect

### Community 102 - "TransformMode"
Cohesion: 0.22
Nodes (8): TransformMode, .displayName, distort, freeform, .id, .isImplemented, uniform, warp

### Community 103 - "RenderNode"
Cohesion: 0.15
Nodes (16): Array, .leafLayerIndices, CanvasManager, .renderLeafOrder, .renderTree, CompositorOp, stack, Content (+8 more)

### Community 104 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 105 - "CGContextDabTarget"
Cohesion: 0.25
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 106 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 107 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 108 - "LayerStackListView.Coordinator"
Cohesion: 0.29
Nodes (6): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 109 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 110 - ".refreshUndoRedoState"
Cohesion: 0.21
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 111 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 112 - "LayerStackListView"
Cohesion: 0.16
Nodes (9): IndexPath, .body, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView (+1 more)

### Community 113 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 114 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 115 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 116 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 117 - "DrawingView"
Cohesion: 0.25
Nodes (7): Alignment, DrawingView, .panelAlignment, Bool, CanvasManager, UUID, Void

### Community 118 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 119 - "LayerRowModel"
Cohesion: 0.18
Nodes (9): LayerRowModel, .folderID, Bool, Double, String, UIGestureRecognizer, UIImage, UILongPressGestureRecognizer (+1 more)

### Community 121 - "Known Issues"
Cohesion: 0.33
Nodes (6): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 122 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 123 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 124 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 125 - "ProjectSummary"
Cohesion: 0.14
Nodes (14): ProjectSummary, Date, ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView (+6 more)

### Community 126 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 127 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 128 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 129 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 130 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 131 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 141 - "FillAxis"
Cohesion: 0.50
Nodes (4): FillAxis, edgeOverlap, gapClosing, threshold

## Knowledge Gaps
- **490 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+485 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `Kind`, `.launchIntoEditor`, `Coordinator`, `CanvasManager`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `ParityScenario`, `CGPoint`, `Deterministic`, `CanvasManager`, `FloatingPiece`, `CompositorParityLogicTests`, `PointCloudIndex`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `VectorEraserHybridLogicTests`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `.load`, `StrokeGeometryLogicTests`, `InterpolationRecipe`, `.evaluate`, `ARAPLogicTests`, `.setUpGestures`, `.analyse`, `ShapeGeometry`, `BrushBlendMode`, `StrokeSpatialIndex`, `VectorSample`, `GuideOverlayView`, `Coordinator`, `LayerStackCell`, `InterpolationGuideLogicTests`, `StrokeSettingsPanel`, `ShapeOverlayView`, `String`, `CanvasManager`, `.indices`, `CanvasManager`, `.manager`, `Color`, `EraserSettingsPanel`, `InterpolationEngineDiagnosticsLogicTests`, `.stampStroke`, `InterpolateBar`, `.arched`, `TimedSample`, `SideToolbar`, `ObjectTransformOverlayView`, `TransformOverlaySupport.swift`, `OnionSkinLogicTests`, `.assertCut`, `SpacingChart`, `Coordinator`, `.composite`, `CGContextDabTarget`, `ActionsMenu`, `StrokeStabilizer`, `.refreshUndoRedoState`, `LayerStackListView`, `DrawingView`?**
  _High betweenness centrality (0.329) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `ParityScenario`, `Coordinator`, `CanvasManager`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `ColorPickerPanel`, `CanvasManager`, `FloatingPiece`, `PointCloudIndex`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `VectorEraserHybridLogicTests`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `StrokeGeometryLogicTests`, `InterpolationRecipe`, `.evaluate`, `ARAPLogicTests`, `.setUpGestures`, `.analyse`, `layers`, `ShapeGeometry`, `StrokeSpatialIndex`, `VectorSample`, `GuideOverlayView`, `FloatingPieceOverlayView`, `Coordinator`, `InterpolationGuideLogicTests`, `ShapeOverlayView`, `.indices`, `CanvasManager`, `ProjectSaveLogicTests`, `SelectionOverlayView`, `.manager`, `InterpolationEngineDiagnosticsLogicTests`, `.stampStroke`, `.arched`, `CGFloat`, `TimedSample`, `ObjectTransformOverlayView`, `TransformOverlaySupport.swift`, `.assertCut`, `CGContextDabTarget`, `LayerStackListView.Coordinator`, `StrokeStabilizer`, `.refreshUndoRedoState`?**
  _High betweenness centrality (0.221) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `cels`, `.launchIntoEditor`, `ParityScenario`, `PerfBaselineTests`, `CGPoint`, `.manager`, `CompositorParityLogicTests`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `VectorEraserHybridLogicTests`, `InterpolationRenderLogicTests`, `StrokeGeometryLogicTests`, `InterpolationRecipe`, `UIKit`, `ARAPLogicTests`, `ShapeGeometry`, `PlaybackBoundsCharacterizationTests`, `LayerTreeCharacterizationTests`, `BackupManagerLogicTests`, `ViewPresetCharacterizationTests`, `InterpolationGuideLogicTests`, `BlockDragCharacterizationTests`, `ProjectSaveLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `OnionSkinLogicTests`?**
  _High betweenness centrality (0.097) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 106 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 106 INFERRED edges - model-reasoned connections that need verification._