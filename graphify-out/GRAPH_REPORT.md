# Graph Report - laptop-tailscale-connection-78ec13  (2026-08-12)

## Corpus Check
- 158 files · ~315,626 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4016 nodes · 12239 edges · 161 communities (148 shown, 13 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1431 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `14807f2c`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- .launchIntoEditor
- ParityScenario
- Coordinator
- layers
- VectorCanvas
- PerfBaselineTests
- StrokeCanvasView
- bash
- ProjectBackupManager
- StrokeGeometryLogicTests
- ColorPickerPanel
- CanvasManager
- .activeCelIndex
- .manager
- CompositorParityLogicTests
- PointCloudIndex
- VectorEraserLogicTests
- Lattice
- BrushEngineLogicTests
- .transparentFormat
- AnimationTimeline
- .withStructureUndo
- VectorEraserHybridLogicTests
- CanvasManager
- RasterLayerTexture
- InterpolationRenderLogicTests
- SaveSnapshot
- Brush
- InterpolationModelLogicTests
- InterpolationRecipe
- UIKit
- ARAPLogicTests
- .setUpGestures
- .evaluate
- CanvasManager
- ShapeGeometry
- PlaybackBoundsCharacterizationTests
- BrushBlendMode
- Codable
- VectorSample
- StrokeGeometry
- GuideOverlayView
- XCTestCase
- MetalFillEngine
- CanvasManager
- BackupManagerLogicTests
- FillParams
- FloatingPieceOverlayView
- BrushDynamics
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
- .encode
- .manager
- DrawingView
- RenderTreeCharacterizationTests
- CodingKeys
- Color
- BrushSettingsPanel
- BlendMode
- PerfMonitor
- .stampStroke
- CodingKeys
- InterpolateBar
- SelectPanel
- .arched
- DeformFactorization
- CanvasSizePickerView
- RasterizeKey
- MotionGroup
- SideToolbar
- UndoHistory
- ObjectTransformOverlayView
- UIView
- Hashable
- CanvasHostView
- OnionSkinLogicTests
- Equatable
- SpacingCurve
- LayerStackRow
- CGPoint
- .draw
- VectorEraserMode
- RenderNode
- 4. Future upgrades — the deferred list
- DabTarget
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView.Coordinator
- StrokeStabilizer
- .setCanvasPadding
- PaintSoftware - iPad Drawing and Animation App
- LayerStackListView
- Layer
- SwiftUI
- Usage Guide
- CutOutcome
- agent
- InterpolationRefusal
- LayerRowModel
- CLAUDE.md
- Known Issues
- Atomic
- ManifestSkeleton
- ProjectStore.swift
- GalleryView
- What needs to change
- Multi-Session Protocol
- parallel_test.sh
- Composite.metal
- Performance baseline
- InterpolatePanel
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- samples
- MetalCompositor.swift
- GuidePath
- .rasterize
- .menuButton
- TransformMode
- .init
- OnionSkinFrame
- SelectionMode
- command
- compositeOver
- CodingKeys
- CodingKeys
- Compositor.swift
- LayerKind
- orchestrator
- worker-bugfix
- worker-integration
- worker-test
- worker-ui
- .encode

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 535 edges
2. `CGFloat` - 407 edges
3. `VectorCanvas` - 122 edges
4. `layers` - 110 edges
5. `CanvasManager` - 103 edges
6. `CanvasManager` - 100 edges
7. `VectorSample` - 99 edges
8. `Lattice` - 98 edges
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

## Communities (161 total, 13 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 1 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 2 - "ParityScenario"
Cohesion: 0.10
Nodes (32): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+24 more)

### Community 3 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 4 - "layers"
Cohesion: 0.07
Nodes (27): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+19 more)

### Community 5 - "VectorCanvas"
Cohesion: 0.09
Nodes (25): image, kind, Kind, fill, image, stroke, CGAffineTransform, CGRect (+17 more)

### Community 6 - "PerfBaselineTests"
Cohesion: 0.19
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 7 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (28): StrokeInput, TimeInterval, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas (+20 more)

### Community 8 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 9 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 10 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (6): StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 11 - "ColorPickerPanel"
Cohesion: 0.08
Nodes (34): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+26 more)

### Community 12 - "CanvasManager"
Cohesion: 0.06
Nodes (28): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .effectiveLoopRange, .hasLoopBoundary, .isFillInAdjustableState (+20 more)

### Community 13 - ".activeCelIndex"
Cohesion: 0.10
Nodes (21): .activeLayerIsVector, .currentFrame, .currentLayerIndex, .interpolationTarget, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind (+13 more)

### Community 14 - ".manager"
Cohesion: 0.12
Nodes (8): CanvasFixture, CanvasManager, CGSize, Int, UUID, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 15 - "CompositorParityLogicTests"
Cohesion: 0.09
Nodes (16): CGImage, CGRect, UIColor, UIImage, UInt8, CompositorParityLogicTests, BlendMode, Bool (+8 more)

### Community 16 - "PointCloudIndex"
Cohesion: 0.07
Nodes (24): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+16 more)

### Community 17 - "VectorEraserLogicTests"
Cohesion: 0.12
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 18 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 19 - "BrushEngineLogicTests"
Cohesion: 0.16
Nodes (10): BrushEngineLogicTests, Any, CodableColor, Int, String, T, UIColor, UIImage (+2 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.25
Nodes (9): PixelOps, CGPath, CGRect, CGSize, Color, Double, UIColor, UIImage (+1 more)

### Community 21 - "AnimationTimeline"
Cohesion: 0.08
Nodes (25): Gesture, AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .isCollapsed, .layerNameColumn (+17 more)

### Community 22 - ".withStructureUndo"
Cohesion: 0.09
Nodes (21): BlendMode, Double, String, UUID, Void, CanvasManager, .activeViewName, Int (+13 more)

### Community 23 - "VectorEraserHybridLogicTests"
Cohesion: 0.13
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 24 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 26 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 27 - "SaveSnapshot"
Cohesion: 0.15
Nodes (19): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+11 more)

### Community 28 - "Brush"
Cohesion: 0.18
Nodes (8): Brush, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser, Bool

### Community 29 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 30 - "InterpolationRecipe"
Cohesion: 0.18
Nodes (10): InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, Bool, Decoder (+2 more)

### Community 31 - "UIKit"
Cohesion: 0.06
Nodes (10): CoreGraphics, Darwin, Foundation, Notification.Name, AppVersion, .versionString, String, ThumbnailRenderer (+2 more)

### Community 32 - "ARAPLogicTests"
Cohesion: 0.12
Nodes (8): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, StaticString, String, UInt

### Community 33 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 34 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 35 - "CanvasManager"
Cohesion: 0.14
Nodes (11): CanvasManager, Bool, Int, Cel, .endFrame, Int, UIImage, UUID (+3 more)

### Community 36 - "ShapeGeometry"
Cohesion: 0.06
Nodes (27): Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom, left (+19 more)

### Community 37 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 38 - "BrushBlendMode"
Cohesion: 0.09
Nodes (23): CaseIterable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+15 more)

### Community 39 - "Codable"
Cohesion: 0.36
Nodes (16): Codable, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, BlendMode, Bool (+8 more)

### Community 40 - "VectorSample"
Cohesion: 0.13
Nodes (14): Int64, VectorSample, .point, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool (+6 more)

### Community 41 - "StrokeGeometry"
Cohesion: 0.15
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 42 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 43 - "XCTestCase"
Cohesion: 0.19
Nodes (8): Layer, StaticString, String, UInt, XCTestCase, LayerTreeCharacterizationTests, CanvasManager, String

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
Nodes (28): device, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor, gapRadius (+20 more)

### Community 48 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 49 - "BrushDynamics"
Cohesion: 0.15
Nodes (8): BrushDynamics, BrushGrain, Bool, Double, UUID, BrushLibrary, .customBrushesDirectory, URL

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
Cohesion: 0.17
Nodes (12): CodingKey, CodingKeys, boundGroups, id, interval, role, samples, CodingKeys (+4 more)

### Community 54 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 55 - "ViewPresetCharacterizationTests"
Cohesion: 0.12
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 56 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 58 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker (+18 more)

### Community 59 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 60 - "View"
Cohesion: 0.09
Nodes (23): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+15 more)

### Community 61 - "String"
Cohesion: 0.07
Nodes (40): Identifiable, CodableColor, .uiColor, DabLattice, .range, ElementData, fill, image (+32 more)

### Community 62 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 63 - "LayerOptionsPanel"
Cohesion: 0.14
Nodes (24): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex (+16 more)

### Community 64 - "StructureSnapshot"
Cohesion: 0.18
Nodes (6): CanvasManager, StructureSnapshot, Int, Layer, String, guideStrokes

### Community 65 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 67 - "CanvasManager"
Cohesion: 0.15
Nodes (12): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+4 more)

### Community 68 - ".load"
Cohesion: 0.22
Nodes (8): ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString, String, UInt, URL

### Community 69 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 70 - "RenderRequest"
Cohesion: 0.29
Nodes (9): CanvasManager, LayerRenderSource, RenderBackground, RenderRequest, Bool, CGImage, CGSize, Int (+1 more)

### Community 71 - ".encode"
Cohesion: 0.20
Nodes (13): MTLTexture, CompositorMetalEngine, ScratchTexturePool, Bool, CGImage, Double, Float, Int (+5 more)

### Community 72 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 73 - "DrawingView"
Cohesion: 0.08
Nodes (21): Alignment, App, task, AppScreen, editor, gallery, sizePicker, ContentView (+13 more)

### Community 74 - "RenderTreeCharacterizationTests"
Cohesion: 0.22
Nodes (3): RenderTreeCharacterizationTests, CanvasManager, String

### Community 75 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 76 - "Color"
Cohesion: 0.15
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 77 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 78 - "BlendMode"
Cohesion: 0.11
Nodes (18): BlendMode, add, colorBurn, colorDodge, darken, difference, .displayName, hardLight (+10 more)

### Community 79 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, .body, PerfHUDOverlay, .body, .hudBody, .toggleButton (+7 more)

### Community 80 - ".stampStroke"
Cohesion: 0.14
Nodes (12): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+4 more)

### Community 81 - "CodingKeys"
Cohesion: 0.10
Nodes (21): CodingKeys, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps (+13 more)

### Community 82 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 83 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 84 - ".arched"
Cohesion: 0.25
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 85 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 87 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 88 - "RasterizeKey"
Cohesion: 0.18
Nodes (9): ObjectIdentifier, IntPoint, RasterizeCache, RasterizeKey, Bool, Cel, Int, UInt8 (+1 more)

### Community 89 - "MotionGroup"
Cohesion: 0.18
Nodes (11): GroupRegistration, Layer, String, GroupInterpolation, auto, clean, crossFade, MotionGroup (+3 more)

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
Cohesion: 0.20
Nodes (9): Hashable, Tool, eraser, fill, pen, pencil, Tab, color (+1 more)

### Community 95 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 96 - "OnionSkinLogicTests"
Cohesion: 0.24
Nodes (6): OnionSkinSource, PreviousCelOnionSkinSource, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 97 - "Equatable"
Cohesion: 0.18
Nodes (14): Equatable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+6 more)

### Community 98 - "SpacingCurve"
Cohesion: 0.13
Nodes (10): SpacingChart, .curve, .draggable, Kind, easeIn, easeInOut, easeOut, linear (+2 more)

### Community 99 - "LayerStackRow"
Cohesion: 0.14
Nodes (12): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+4 more)

### Community 100 - "CGPoint"
Cohesion: 0.07
Nodes (21): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, CGPoint (+13 more)

### Community 101 - ".draw"
Cohesion: 0.21
Nodes (12): BlendMode, .coreGraphicsBlendMode, CoreGraphicsCompositor, CGBlendMode, CGImage, CGRect, Double, Float (+4 more)

### Community 102 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 103 - "RenderNode"
Cohesion: 0.13
Nodes (19): Array, .leafLayerIndices, CanvasManager, .renderLeafOrder, .renderTree, CompositorOp, stack, Content (+11 more)

### Community 104 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 105 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

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
Cohesion: 0.22
Nodes (8): Layer, BlendMode, Bool, Cel, Double, String, UIImage, UUID

### Community 114 - "SwiftUI"
Cohesion: 0.21
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 115 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 116 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 117 - "agent"
Cohesion: 0.14
Nodes (13): agent, worker-feature, worker-research, model, plugin, $schema, description, mode (+5 more)

### Community 118 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 119 - "LayerRowModel"
Cohesion: 0.16
Nodes (15): NSObject, Coordinator, LayerRowModel, .folderID, BlendMode, Double, Int, Set (+7 more)

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

### Community 125 - "GalleryView"
Cohesion: 0.14
Nodes (12): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void (+4 more)

### Community 126 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 127 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 128 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 129 - "Composite.metal"
Cohesion: 0.42
Nodes (11): float3, blendChannels(), blendColorBurn(), blendColorDodge(), blendHardLight(), blendMultiply(), blendOver(), blendScreen() (+3 more)

### Community 130 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 131 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 140 - "MetalCompositor.swift"
Cohesion: 0.29
Nodes (6): Metal, BlendMode, .shaderCode, MetalCompositor, UInt32, simd

### Community 141 - "GuidePath"
Cohesion: 0.23
Nodes (5): GuidePath, .end, .start, TimeInterval, TimeInterval

### Community 144 - ".menuButton"
Cohesion: 0.32
Nodes (6): .blockMenu, .gapMenu, .loopMenu, ButtonRole, String, Void

### Community 145 - "TransformMode"
Cohesion: 0.22
Nodes (8): TransformMode, .displayName, distort, freeform, .id, .isImplemented, uniform, warp

### Community 147 - "OnionSkinFrame"
Cohesion: 0.28
Nodes (5): OnionSkinFrame, CanvasManager, CGSize, UIColor, UIImage

### Community 148 - "SelectionMode"
Cohesion: 0.25
Nodes (7): SelectionMode, automatic, .displayName, .id, lasso, rectangle, .systemImage

### Community 149 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 150 - "compositeOver"
Cohesion: 0.48
Nodes (7): compositeFill(), compositeOver(), constant, kernel, uint2, texture2d, write

### Community 151 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 152 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, guideIDs, localEdits, mode, references, spacing, t

### Community 153 - "Compositor.swift"
Cohesion: 0.50
Nodes (4): Compositor, CompositorBackend, coreGraphics, metal

### Community 154 - "LayerKind"
Cohesion: 0.40
Nodes (4): LayerKind, compositing, raster, vector

### Community 155 - "orchestrator"
Cohesion: 0.50
Nodes (4): orchestrator, description, mode, model

### Community 156 - "worker-bugfix"
Cohesion: 0.50
Nodes (4): worker-bugfix, description, mode, model

### Community 157 - "worker-integration"
Cohesion: 0.50
Nodes (4): worker-integration, description, mode, model

### Community 158 - "worker-test"
Cohesion: 0.50
Nodes (4): worker-test, description, mode, model

### Community 159 - "worker-ui"
Cohesion: 0.50
Nodes (4): worker-ui, description, mode, model

## Knowledge Gaps
- **513 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+508 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGPoint` to `cels`, `.launchIntoEditor`, `ParityScenario`, `Coordinator`, `layers`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `samples`, `CanvasManager`, `GuidePath`, `.activeCelIndex`, `CompositorParityLogicTests`, `PointCloudIndex`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `OnionSkinFrame`, `VectorEraserHybridLogicTests`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `Brush`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `ARAPLogicTests`, `.setUpGestures`, `.evaluate`, `ShapeGeometry`, `VectorSample`, `StrokeGeometry`, `GuideOverlayView`, `FloatingPieceOverlayView`, `BrushDynamics`, `Coordinator`, `LayerStackCell`, `InterpolationGuideLogicTests`, `StrokeSettingsPanel`, `ShapeOverlayView`, `String`, `CanvasManager`, `.indices`, `CanvasManager`, `.load`, `.manager`, `DrawingView`, `CodingKeys`, `Color`, `.stampStroke`, `InterpolateBar`, `.arched`, `DeformFactorization`, `.path`, `SideToolbar`, `UIView`, `OnionSkinLogicTests`, `Equatable`, `SpacingCurve`, `.draw`, `DabTarget`, `ActionsMenu`, `StrokeStabilizer`, `.setCanvasPadding`, `LayerStackListView`, `LayerRowModel`?**
  _High betweenness centrality (0.329) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `ParityScenario`, `Coordinator`, `layers`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `samples`, `CanvasManager`, `GuidePath`, `.activeCelIndex`, `ColorPickerPanel`, `PointCloudIndex`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `.rasterize`, `VectorEraserHybridLogicTests`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `Brush`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `UIKit`, `ARAPLogicTests`, `.setUpGestures`, `.evaluate`, `ShapeGeometry`, `VectorSample`, `StrokeGeometry`, `GuideOverlayView`, `FloatingPieceOverlayView`, `Coordinator`, `InterpolationGuideLogicTests`, `ShapeOverlayView`, `String`, `.indices`, `CanvasManager`, `.load`, `SelectionOverlayView`, `.manager`, `.stampStroke`, `.arched`, `DeformFactorization`, `.path`, `RasterizeKey`, `ObjectTransformOverlayView`, `UIView`, `Equatable`, `DabTarget`, `LayerStackListView.Coordinator`, `StrokeStabilizer`, `.setCanvasPadding`?**
  _High betweenness centrality (0.200) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `.activeCelIndex`, `TransformMode`, `SelectionMode`, `.withStructureUndo`, `CanvasManager`, `RasterLayerTexture`, `LayerKind`, `Brush`, `InterpolationRecipe`, `CanvasManager`, `ShapeGeometry`, `VectorSample`, `MetalFillEngine`, `StructureSnapshot`, `CanvasManager`, `PerfMonitor`, `MotionGroup`, `UndoHistory`, `Hashable`, `Equatable`, `SpacingCurve`, `CGPoint`, `VectorEraserMode`, `SwiftUI`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 109 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 109 INFERRED edges - model-reasoned connections that need verification._