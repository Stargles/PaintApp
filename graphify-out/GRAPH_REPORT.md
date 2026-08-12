# Graph Report - laptop-tailscale-connection-78ec13  (2026-08-11)

## Corpus Check
- 157 files · ~305,166 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3916 nodes · 11964 edges · 147 communities (136 shown, 11 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1414 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `c7a47a0b`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- .launchIntoEditor
- RasterVectorParityLogicTests
- Coordinator
- CanvasManager
- VectorCanvas
- PerfBaselineTests
- StrokeCanvasView
- bash
- ProjectBackupManager
- CGPoint
- Palette
- CanvasManager
- CanvasManager
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
- ProjectStore
- VectorSample
- InterpolationModelLogicTests
- InterpolationRecipe
- UIKit
- ARAPLogicTests
- .setUpGestures
- .analyse
- layers
- ShapeDetectorLogicTests
- PlaybackBoundsCharacterizationTests
- BrushBlendMode
- Codable
- StrokeSpatialIndex
- StrokeGeometryLogicTests
- GuideOverlayView
- XCTestCase
- MetalFillEngine
- CanvasManager
- BackupManagerLogicTests
- FillParams
- FloatingPieceOverlayView
- ShapeGeometry
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
- .load
- SelectionOverlayView
- RenderRequest
- CompositorMetalEngine
- .manager
- ContentView
- RenderTreeCharacterizationTests
- AppVersion
- Color
- SwiftUI
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
- ColorPickerPanel
- MotionGroup
- SideToolbar
- UndoHistory
- ObjectTransformOverlayView
- UIView
- Hashable
- CanvasHostView
- OnionSkinLogicTests
- Equatable
- SpacingChart
- LayerStackRow
- ShapeDetector
- .composite
- VectorEraserMode
- RenderNode
- 4. Future upgrades — the deferred list
- CGContextDabTarget
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView.Coordinator
- StrokeStabilizer
- .setCanvasPadding
- PaintSoftware - iPad Drawing and Animation App
- LayerStackListView
- Layer
- VectorScratchRole
- Usage Guide
- CutOutcome
- DrawingView
- InterpolationRefusal
- LayerRowModel
- CLAUDE.md
- Known Issues
- Atomic
- ManifestSkeleton
- ProjectStore.swift
- SaveSnapshot
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
- .registerGroups
- MetalCompositor.swift
- GuidePath
- Edge
- .menuButton
- Corner
- .init

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 533 edges
2. `CGFloat` - 407 edges
3. `VectorCanvas` - 122 edges
4. `layers` - 109 edges
5. `CanvasManager` - 101 edges
6. `CanvasManager` - 100 edges
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

## Communities (147 total, 11 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 1 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 2 - "RasterVectorParityLogicTests"
Cohesion: 0.12
Nodes (19): Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave, .label (+11 more)

### Community 3 - "Coordinator"
Cohesion: 0.06
Nodes (43): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+35 more)

### Community 4 - "CanvasManager"
Cohesion: 0.07
Nodes (24): CanvasManager, .guideChips, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .motionGroupChips (+16 more)

### Community 5 - "VectorCanvas"
Cohesion: 0.07
Nodes (45): Identifiable, CodableColor, .uiColor, image, kind, DabLattice, .range, Kind (+37 more)

### Community 6 - "PerfBaselineTests"
Cohesion: 0.19
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 7 - "StrokeCanvasView"
Cohesion: 0.11
Nodes (22): StrokeInput, TimeInterval, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas (+14 more)

### Community 8 - "bash"
Cohesion: 0.05
Nodes (63): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+55 more)

### Community 9 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 10 - "CGPoint"
Cohesion: 0.11
Nodes (9): CGPoint, .length, .point, Intersection, LatticeLogicTests, Int, StaticString, String (+1 more)

### Community 11 - "Palette"
Cohesion: 0.16
Nodes (16): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+8 more)

### Community 12 - "CanvasManager"
Cohesion: 0.04
Nodes (47): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+39 more)

### Community 13 - "CanvasManager"
Cohesion: 0.06
Nodes (35): String, UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+27 more)

### Community 14 - ".manager"
Cohesion: 0.13
Nodes (5): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 15 - "CompositorParityLogicTests"
Cohesion: 0.10
Nodes (15): CanvasFixture, CGImage, CGRect, CGSize, UIColor, UIImage, UInt8, CompositorParityLogicTests (+7 more)

### Community 16 - "PointCloudIndex"
Cohesion: 0.14
Nodes (15): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+7 more)

### Community 17 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 18 - "Lattice"
Cohesion: 0.08
Nodes (30): CodingKeys, activeCells, cellSize, cols, originX, originY, rows, vertices (+22 more)

### Community 19 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.12
Nodes (19): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+11 more)

### Community 21 - "AnimationTimeline"
Cohesion: 0.08
Nodes (25): Gesture, AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .isCollapsed, .layerNameColumn (+17 more)

### Community 22 - "ViewPreset"
Cohesion: 0.19
Nodes (8): CanvasManager, .activeViewName, Int, String, Bool, String, UUID, ViewPreset

### Community 23 - "VectorEraserHybridLogicTests"
Cohesion: 0.11
Nodes (21): CustomStringConvertible, ParityPixel, .description, ParityReport, .diagnostic, .isExact, ParityScenario, RasterVectorParity (+13 more)

### Community 24 - "CanvasManager"
Cohesion: 0.09
Nodes (18): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+10 more)

### Community 25 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 26 - "InterpolationRenderLogicTests"
Cohesion: 0.07
Nodes (32): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, InterpolationEvaluator (+24 more)

### Community 27 - "ProjectStore"
Cohesion: 0.18
Nodes (9): BrushLibrary, .customBrushesDirectory, URL, ProjectStore, .projectsDirectory, CanvasManager, MainActor, URL (+1 more)

### Community 28 - "VectorSample"
Cohesion: 0.17
Nodes (9): Brush, VectorSample, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser (+1 more)

### Community 29 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 30 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (11): InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve, Bool (+3 more)

### Community 31 - "UIKit"
Cohesion: 0.06
Nodes (8): Combine, CoreGraphics, Darwin, Foundation, Notification.Name, ThumbnailRenderer, UIKit, XCTest

### Community 32 - "ARAPLogicTests"
Cohesion: 0.11
Nodes (7): ARAPInterpolation, groups, ARAPLogicTests, Int, StaticString, String, UInt

### Community 33 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 34 - ".analyse"
Cohesion: 0.33
Nodes (6): Group, MotionGrouping, Options, Bool, Int, Set

### Community 35 - "layers"
Cohesion: 0.20
Nodes (9): .activeLayerIsVector, .activeCelIsInBetween, .guideRefusal, .interpolationTarget, .linkableGuideStrokes, CanvasManager, Bool, Int (+1 more)

### Community 36 - "ShapeDetectorLogicTests"
Cohesion: 0.16
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 37 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 38 - "BrushBlendMode"
Cohesion: 0.08
Nodes (23): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+15 more)

### Community 39 - "Codable"
Cohesion: 0.20
Nodes (22): Codable, BlendMode, normal, LayerKind, compositing, raster, vector, CelManifest (+14 more)

### Community 40 - "StrokeSpatialIndex"
Cohesion: 0.17
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 41 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (17): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, samples (+9 more)

### Community 42 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 43 - "XCTestCase"
Cohesion: 0.17
Nodes (9): Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager (+1 more)

### Community 44 - "MetalFillEngine"
Cohesion: 0.18
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 45 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 46 - "BackupManagerLogicTests"
Cohesion: 0.18
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 47 - "FillParams"
Cohesion: 0.18
Nodes (28): device, float4, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+20 more)

### Community 48 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 49 - "ShapeGeometry"
Cohesion: 0.11
Nodes (14): FollowFrame, ShapeGeometry, .boundingRect, .center, .cgPath, .constrained, .isClosed, .outlineLength (+6 more)

### Community 50 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 51 - "Coordinator"
Cohesion: 0.07
Nodes (24): LayerHostView, NSCoder, AppliedTool, CanvasView, Coordinator, InterpolationPreviewKey, Bool, CanvasManager (+16 more)

### Community 52 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 53 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKey, CodingKeys, boundGroups, id, interval, role, samples, CodingKeys (+11 more)

### Community 54 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, adjust, brush, color, eraser, fill, move (+9 more)

### Community 55 - "ViewPresetCharacterizationTests"
Cohesion: 0.12
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 56 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 58 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 59 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 60 - "View"
Cohesion: 0.14
Nodes (17): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+9 more)

### Community 61 - "String"
Cohesion: 0.07
Nodes (35): CodingKeys, brush, color, composite, elements, fill, fills, id (+27 more)

### Community 62 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 63 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (22): .layerPanelRail, FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex (+14 more)

### Community 64 - "StructureSnapshot"
Cohesion: 0.19
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 65 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 67 - "CanvasManager"
Cohesion: 0.21
Nodes (8): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage

### Community 68 - ".load"
Cohesion: 0.22
Nodes (8): ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString, String, UInt, URL

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

### Community 74 - "RenderTreeCharacterizationTests"
Cohesion: 0.22
Nodes (3): RenderTreeCharacterizationTests, CanvasManager, String

### Community 75 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

### Community 76 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 77 - "SwiftUI"
Cohesion: 0.09
Nodes (17): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+9 more)

### Community 78 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.30
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 79 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 80 - ".stampStroke"
Cohesion: 0.13
Nodes (14): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+6 more)

### Community 81 - "CodingKeys"
Cohesion: 0.09
Nodes (21): CodingKeys, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps (+13 more)

### Community 82 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 83 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 84 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 85 - "CGFloat"
Cohesion: 0.06
Nodes (26): Accelerate, bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Interpolator (+18 more)

### Community 86 - "TimedSample"
Cohesion: 0.20
Nodes (3): TimedSample, .point, TimeInterval

### Community 87 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 88 - "ColorPickerPanel"
Cohesion: 0.12
Nodes (18): ColorPickerPanel, .body, .colorTab, .currentColor, .hexRow, .hueSlider, .palettesTab, .renameAlertBinding (+10 more)

### Community 89 - "MotionGroup"
Cohesion: 0.23
Nodes (9): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 90 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 91 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 92 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 93 - "UIView"
Cohesion: 0.16
Nodes (11): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+3 more)

### Community 94 - "Hashable"
Cohesion: 0.18
Nodes (10): Hashable, CelLocation, Tool, eraser, fill, pen, pencil, Tab (+2 more)

### Community 95 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 96 - "OnionSkinLogicTests"
Cohesion: 0.24
Nodes (6): OnionSkinSource, PreviousCelOnionSkinSource, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 97 - "Equatable"
Cohesion: 0.17
Nodes (12): Equatable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+4 more)

### Community 98 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 99 - "LayerStackRow"
Cohesion: 0.14
Nodes (12): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+4 more)

### Community 100 - "ShapeDetector"
Cohesion: 0.19
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 101 - ".composite"
Cohesion: 0.27
Nodes (7): Compositor, CompositorBackend, coreGraphics, metal, CoreGraphicsCompositor, CGImage, CGRect

### Community 102 - "VectorEraserMode"
Cohesion: 0.10
Nodes (19): CaseIterable, Kind, line, oval, rectangle, Bool, VectorEraserMode, cutPoints (+11 more)

### Community 103 - "RenderNode"
Cohesion: 0.14
Nodes (18): Array, .leafLayerIndices, CanvasManager, .renderLeafOrder, .renderTree, CompositorOp, stack, Content (+10 more)

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
Cohesion: 0.21
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 109 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 110 - ".setCanvasPadding"
Cohesion: 0.36
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 111 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 112 - "LayerStackListView"
Cohesion: 0.18
Nodes (8): IndexPath, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView, UIViewRepresentable

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
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 118 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 119 - "LayerRowModel"
Cohesion: 0.17
Nodes (14): NSObject, Coordinator, LayerRowModel, .folderID, Double, Int, Set, String (+6 more)

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

### Community 125 - "SaveSnapshot"
Cohesion: 0.11
Nodes (24): CelContent, LayerContent, ProjectSummary, SaveSnapshot, Bool, CGSize, Date, Double (+16 more)

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

### Community 138 - ".registerGroups"
Cohesion: 0.22
Nodes (3): GroupRegistration, RegistrationElement, RegistrationFrame

### Community 141 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 143 - "Edge"
Cohesion: 0.25
Nodes (5): Edge, bottom, left, right, top

### Community 144 - ".menuButton"
Cohesion: 0.32
Nodes (6): .blockMenu, .gapMenu, .loopMenu, ButtonRole, String, Void

### Community 145 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

## Knowledge Gaps
- **497 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+492 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `Kind`, `.launchIntoEditor`, `Coordinator`, `CanvasManager`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `RasterVectorParityLogicTests`, `CGPoint`, `.registerGroups`, `CanvasManager`, `GuidePath`, `CanvasManager`, `CompositorParityLogicTests`, `PointCloudIndex`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `VectorEraserHybridLogicTests`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `VectorSample`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `ARAPLogicTests`, `.setUpGestures`, `.analyse`, `ShapeDetectorLogicTests`, `BrushBlendMode`, `StrokeSpatialIndex`, `StrokeGeometryLogicTests`, `GuideOverlayView`, `FloatingPieceOverlayView`, `ShapeGeometry`, `Coordinator`, `LayerStackCell`, `InterpolationGuideLogicTests`, `StrokeSettingsPanel`, `ShapeOverlayView`, `String`, `CanvasManager`, `.indices`, `CanvasManager`, `.load`, `.manager`, `Color`, `SwiftUI`, `InterpolationEngineDiagnosticsLogicTests`, `.stampStroke`, `InterpolateBar`, `.arched`, `TimedSample`, `SideToolbar`, `UIView`, `OnionSkinLogicTests`, `Equatable`, `SpacingChart`, `ShapeDetector`, `.composite`, `VectorEraserMode`, `CGContextDabTarget`, `ActionsMenu`, `StrokeStabilizer`, `.setCanvasPadding`, `LayerStackListView`, `DrawingView`, `LayerRowModel`?**
  _High betweenness centrality (0.313) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `RasterVectorParityLogicTests`, `Coordinator`, `CanvasManager`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `.registerGroups`, `CanvasManager`, `GuidePath`, `CanvasManager`, `Edge`, `PointCloudIndex`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `VectorEraserHybridLogicTests`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `VectorSample`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `UIKit`, `ARAPLogicTests`, `.setUpGestures`, `.analyse`, `layers`, `ShapeDetectorLogicTests`, `BrushBlendMode`, `StrokeSpatialIndex`, `StrokeGeometryLogicTests`, `GuideOverlayView`, `FloatingPieceOverlayView`, `ShapeGeometry`, `Coordinator`, `InterpolationGuideLogicTests`, `ShapeOverlayView`, `String`, `.indices`, `CanvasManager`, `.load`, `SelectionOverlayView`, `.manager`, `InterpolationEngineDiagnosticsLogicTests`, `.stampStroke`, `.arched`, `CGFloat`, `TimedSample`, `ColorPickerPanel`, `ObjectTransformOverlayView`, `UIView`, `Equatable`, `ShapeDetector`, `VectorEraserMode`, `CGContextDabTarget`, `LayerStackListView.Coordinator`, `StrokeStabilizer`, `.setCanvasPadding`?**
  _High betweenness centrality (0.234) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CanvasManager`, `ViewPreset`, `CanvasManager`, `RasterLayerTexture`, `VectorSample`, `InterpolationRecipe`, `UIKit`, `layers`, `Codable`, `MetalFillEngine`, `ShapeGeometry`, `StructureSnapshot`, `PerfMonitor`, `CGFloat`, `TimedSample`, `MotionGroup`, `UndoHistory`, `Hashable`, `Equatable`, `SpacingChart`, `VectorEraserMode`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 108 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 108 INFERRED edges - model-reasoned connections that need verification._