# Graph Report - sandwich-split-5b1  (2026-08-12)

## Corpus Check
- 158 files · ~320,937 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4067 nodes · 12388 edges · 148 communities (138 shown, 10 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1438 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2efcdafc`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- cels
- CanvasManager
- VectorEraserHybridLogicTests
- Lattice
- CGPoint
- Coordinator
- .transparentFormat
- CanvasManager
- CompositorParityLogicTests
- .manager
- Brush
- ColorPickerPanel
- StrokeCanvasView
- .rasterize
- Coordinator
- PointCloudIndex
- VectorCanvas
- ProjectBackupManager
- VectorEraserLogicTests
- UIKit
- ShapeOverlayView
- VectorStroke
- BrushEngineLogicTests
- StrokeGeometryLogicTests
- ARAPLogicTests
- CanvasManager
- layers
- SandwichLogicTests
- InterpolationRenderLogicTests
- PerfBaselineTests
- .evaluate
- InterpolationRecipe
- CanvasManager
- FloatingPieceOverlayView
- RasterLayerTexture
- BackupManagerLogicTests
- AnimationTimeline
- .load
- InterpolationModelLogicTests
- SwiftUI
- PlaybackBoundsCharacterizationTests
- StrokeSettingsPanel
- StrokeGeometry
- .withStructureUndo
- View
- XCTestCase
- StrokeSpatialIndex
- GuideOverlayView
- CGFloat
- DeformFactorization
- FillParams
- Layer Compositing
- .stampStroke
- TouchCountRecognizer
- SideToolbar
- MetalFillEngine
- RenderTreeCharacterizationTests
- LayerOptionsPanel
- LayerRowModel
- .group
- LayerStackCell
- ActivePanel
- .encode
- SaveSnapshot
- InterpolationGuideLogicTests
- VectorSample
- RenderNode
- .draw
- ViewPresetCharacterizationTests
- Foundation
- CanvasManager
- ContentView
- .indices
- .eraseHybrid
- CodingKeys
- .setUpGestures
- SelectionOverlayView
- CodingKeys
- BlockDragCharacterizationTests
- .manager
- GuideStroke
- CodingKeys
- GalleryView
- InterpolationEngineDiagnosticsLogicTests
- PerfMonitor
- BlendMode
- ProjectManifest
- InterpolateBar
- .arched
- TimedSample
- VectorEraserMode
- CanvasSizePickerView
- DabTarget
- bash
- LayerStackRow
- ObjectTransformOverlayView
- LayerStackListView
- agent
- RenderRequest
- Layer
- UndoHistory
- CanvasHostView
- GuidePath
- SpacingChart
- LayerStackListView.Coordinator
- Composite.metal
- 4. Future upgrades — the deferred list
- StrokeStabilizer
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- .setCanvasPadding
- TransformOverlaySupport.swift
- PaintSoftware - iPad Drawing and Animation App
- MetalCompositor.swift
- .menuButton
- BrushSettingsPanel
- Usage Guide
- nextprompt.md
- command
- compositeOver
- CutOutcome
- Kind
- InterpolatePanel
- CLAUDE.md
- Known Issues
- Multi-Session Protocol
- ManifestSkeleton
- CodingKeys
- Atomic
- What needs to change
- parallel_test.sh
- Corner
- Edge
- Performance baseline
- orchestrator
- worker-bugfix
- worker-feature
- worker-research
- worker-test
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- .encode

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 535 edges
2. `CGFloat` - 408 edges
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

## Communities (148 total, 10 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (47): CanvasManager, .guideChips, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .motionGroupChips (+39 more)

### Community 3 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (49): CustomStringConvertible, UUID, UIImage, UInt8, Backdrop, fill, image, none (+41 more)

### Community 4 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 5 - "CGPoint"
Cohesion: 0.07
Nodes (24): CGPoint, .length, ClosedFit, ShapeDetector, Bool, CGRect, Int, FollowFrame (+16 more)

### Community 6 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 7 - ".transparentFormat"
Cohesion: 0.05
Nodes (39): ObjectIdentifier, IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath (+31 more)

### Community 8 - "CanvasManager"
Cohesion: 0.05
Nodes (42): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .effectiveLoopRange, .hasLoopBoundary, .isFillInAdjustableState (+34 more)

### Community 9 - "CompositorParityLogicTests"
Cohesion: 0.09
Nodes (18): CanvasFixture, CGImage, CGRect, CGSize, UIColor, UIImage, UInt8, CompositorParityLogicTests (+10 more)

### Community 10 - ".manager"
Cohesion: 0.11
Nodes (6): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int

### Community 11 - "Brush"
Cohesion: 0.05
Nodes (41): CaseIterable, Identifiable, Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten (+33 more)

### Community 12 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 13 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (30): StrokeInput, TimeInterval, UITouch, UIView, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+22 more)

### Community 14 - ".rasterize"
Cohesion: 0.08
Nodes (28): .currentFrame, .currentLayerIndex, CodableColor, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+20 more)

### Community 15 - "Coordinator"
Cohesion: 0.08
Nodes (21): LayerHostView, NSCoder, CanvasView, Coordinator, InterpolationPreviewKey, Bool, CanvasManager, Context (+13 more)

### Community 16 - "PointCloudIndex"
Cohesion: 0.12
Nodes (16): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+8 more)

### Community 17 - "VectorCanvas"
Cohesion: 0.09
Nodes (28): image, kind, Kind, fill, image, stroke, RenderQuality, full (+20 more)

### Community 18 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+13 more)

### Community 19 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (7): VectorEraser, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 20 - "UIKit"
Cohesion: 0.07
Nodes (5): CoreGraphics, Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 21 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 22 - "VectorStroke"
Cohesion: 0.08
Nodes (31): CodableColor, .uiColor, DabLattice, .range, ElementData, fill, image, stroke (+23 more)

### Community 23 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 24 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (7): Intersection, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 25 - "ARAPLogicTests"
Cohesion: 0.12
Nodes (8): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, StaticString, String, UInt

### Community 26 - "CanvasManager"
Cohesion: 0.09
Nodes (18): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+10 more)

### Community 27 - "layers"
Cohesion: 0.13
Nodes (17): .activeLayerIsVector, .activeCelIsInBetween, .guideRefusal, .interpolationTarget, .linkableGuideStrokes, CanvasManager, Bool, Int (+9 more)

### Community 28 - "SandwichLogicTests"
Cohesion: 0.13
Nodes (6): Battery, SandwichLogicTests, CanvasManager, CGImage, Int, String

### Community 29 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 30 - "PerfBaselineTests"
Cohesion: 0.19
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 31 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 32 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (17): Codable, Equatable, CelRef, InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed (+9 more)

### Community 33 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 34 - "FloatingPieceOverlayView"
Cohesion: 0.10
Nodes (19): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+11 more)

### Community 35 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 36 - "BackupManagerLogicTests"
Cohesion: 0.15
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 37 - "AnimationTimeline"
Cohesion: 0.09
Nodes (24): Gesture, AnimationTimeline, .collapsedBar, .contentHeight, .frameLabel, .isCollapsed, .layerNameColumn, .loopButton (+16 more)

### Community 38 - ".load"
Cohesion: 0.17
Nodes (11): CanvasManager, MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString (+3 more)

### Community 39 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 40 - "SwiftUI"
Cohesion: 0.08
Nodes (19): Alignment, Combine, DrawingView, .panelAlignment, .panelView, Bool, CanvasManager, UUID (+11 more)

### Community 41 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 42 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker (+18 more)

### Community 43 - "StrokeGeometry"
Cohesion: 0.15
Nodes (9): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, .dragHandle (+1 more)

### Community 44 - ".withStructureUndo"
Cohesion: 0.11
Nodes (13): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, Int (+5 more)

### Community 45 - "View"
Cohesion: 0.09
Nodes (23): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+15 more)

### Community 46 - "XCTestCase"
Cohesion: 0.17
Nodes (9): Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager (+1 more)

### Community 47 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 48 - "GuideOverlayView"
Cohesion: 0.13
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 49 - "CGFloat"
Cohesion: 0.09
Nodes (17): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, CanvasManager (+9 more)

### Community 50 - "DeformFactorization"
Cohesion: 0.12
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 51 - "FillParams"
Cohesion: 0.18
Nodes (28): device, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor, gapRadius (+20 more)

### Community 52 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 53 - ".stampStroke"
Cohesion: 0.14
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 54 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 55 - "SideToolbar"
Cohesion: 0.09
Nodes (23): .body, SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager (+15 more)

### Community 56 - "MetalFillEngine"
Cohesion: 0.18
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 57 - "RenderTreeCharacterizationTests"
Cohesion: 0.22
Nodes (3): RenderTreeCharacterizationTests, CanvasManager, String

### Community 58 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (23): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex (+15 more)

### Community 59 - "LayerRowModel"
Cohesion: 0.16
Nodes (15): NSObject, Coordinator, LayerRowModel, .folderID, BlendMode, Double, Int, Set (+7 more)

### Community 60 - ".group"
Cohesion: 0.17
Nodes (7): Group, MotionGrouping, Options, Int, Set, groups, Int

### Community 61 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 62 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 63 - ".encode"
Cohesion: 0.20
Nodes (13): MTLTexture, CompositorMetalEngine, ScratchTexturePool, Bool, CGImage, Double, Float, Int (+5 more)

### Community 64 - "SaveSnapshot"
Cohesion: 0.18
Nodes (16): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+8 more)

### Community 66 - "VectorSample"
Cohesion: 0.21
Nodes (7): VectorSample, .point, Sweep, Bool, CGRect, ClosedRange, samples

### Community 67 - "RenderNode"
Cohesion: 0.13
Nodes (20): Array, .leafLayerIndices, .needsCompositorOnCanvas, CanvasManager, .renderLeafOrder, .renderTree, CompositorOp, stack (+12 more)

### Community 68 - ".draw"
Cohesion: 0.16
Nodes (16): BlendMode, .coreGraphicsBlendMode, Compositor, CompositorBackend, coreGraphics, metal, CoreGraphicsCompositor, CGBlendMode (+8 more)

### Community 69 - "ViewPresetCharacterizationTests"
Cohesion: 0.12
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 70 - "Foundation"
Cohesion: 0.10
Nodes (10): Foundation, Notification.Name, CodableColor, .color, Color, .codable, CodableColor, AppVersion (+2 more)

### Community 71 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 72 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 74 - ".eraseHybrid"
Cohesion: 0.20
Nodes (4): Double, Bool, CGContext, CGRect

### Community 75 - "CodingKeys"
Cohesion: 0.10
Nodes (21): CodingKeys, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps (+13 more)

### Community 76 - ".setUpGestures"
Cohesion: 0.14
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 77 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 78 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+12 more)

### Community 79 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 80 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 81 - "GuideStroke"
Cohesion: 0.18
Nodes (10): Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+2 more)

### Community 82 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 83 - "GalleryView"
Cohesion: 0.14
Nodes (12): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void (+4 more)

### Community 84 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 85 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 86 - "BlendMode"
Cohesion: 0.11
Nodes (18): BlendMode, add, colorBurn, colorDodge, darken, difference, .displayName, hardLight (+10 more)

### Community 87 - "ProjectManifest"
Cohesion: 0.39
Nodes (14): CelManifest, FolderManifest, LayerManifest, ProjectManifest, BlendMode, Bool, CodableColor, Date (+6 more)

### Community 88 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 89 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 90 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 91 - "VectorEraserMode"
Cohesion: 0.12
Nodes (16): Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode, cutPoints (+8 more)

### Community 92 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 93 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 94 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 95 - "LayerStackRow"
Cohesion: 0.14
Nodes (12): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+4 more)

### Community 96 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 97 - "LayerStackListView"
Cohesion: 0.16
Nodes (9): IndexPath, .body, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView (+1 more)

### Community 98 - "agent"
Cohesion: 0.14
Nodes (13): agent, worker-integration, worker-ui, model, plugin, $schema, description, mode (+5 more)

### Community 99 - "RenderRequest"
Cohesion: 0.29
Nodes (10): CanvasManager, LayerRenderSource, RenderBackground, RenderRequest, SandwichRequests, Bool, CGImage, CGSize (+2 more)

### Community 100 - "Layer"
Cohesion: 0.14
Nodes (12): Layer, BlendMode, Bool, Cel, Double, String, UIImage, UUID (+4 more)

### Community 101 - "UndoHistory"
Cohesion: 0.23
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 102 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 103 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 104 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 105 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 106 - "Composite.metal"
Cohesion: 0.42
Nodes (11): float3, blendChannels(), blendColorBurn(), blendColorDodge(), blendHardLight(), blendMultiply(), blendOver(), blendScreen() (+3 more)

### Community 107 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 108 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 109 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 110 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 111 - ".setCanvasPadding"
Cohesion: 0.33
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 112 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 113 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 114 - "MetalCompositor.swift"
Cohesion: 0.29
Nodes (6): Metal, BlendMode, .shaderCode, MetalCompositor, UInt32, simd

### Community 115 - ".menuButton"
Cohesion: 0.32
Nodes (6): .blockMenu, .gapMenu, .loopMenu, ButtonRole, String, Void

### Community 116 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 117 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 118 - "nextprompt.md"
Cohesion: 0.29
Nodes (6): Gotchas that each cost a cycle, State, The finding worth carrying forward, The sandwich, and what it will cost you, What phase 5a built, so you don't rediscover it, Why phase 5 is only half done

### Community 119 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 120 - "compositeOver"
Cohesion: 0.48
Nodes (7): compositeFill(), compositeOver(), constant, kernel, uint2, texture2d, write

### Community 121 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 122 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 123 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 125 - "Known Issues"
Cohesion: 0.33
Nodes (6): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 126 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 127 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 128 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, boundGroups, id, interval, role, samples

### Community 129 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 130 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 131 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 132 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 133 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 134 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 135 - "orchestrator"
Cohesion: 0.50
Nodes (4): orchestrator, description, mode, model

### Community 136 - "worker-bugfix"
Cohesion: 0.50
Nodes (4): worker-bugfix, description, mode, model

### Community 137 - "worker-feature"
Cohesion: 0.50
Nodes (4): worker-feature, description, mode, model

### Community 138 - "worker-research"
Cohesion: 0.50
Nodes (4): worker-research, description, mode, model

### Community 139 - "worker-test"
Cohesion: 0.50
Nodes (4): worker-test, description, mode, model

## Knowledge Gaps
- **519 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+514 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `cels`, `CanvasManager`, `VectorEraserHybridLogicTests`, `Lattice`, `CGPoint`, `Coordinator`, `.transparentFormat`, `CanvasManager`, `CompositorParityLogicTests`, `Brush`, `StrokeCanvasView`, `.rasterize`, `Coordinator`, `PointCloudIndex`, `VectorCanvas`, `VectorEraserLogicTests`, `ShapeOverlayView`, `VectorStroke`, `BrushEngineLogicTests`, `StrokeGeometryLogicTests`, `ARAPLogicTests`, `CanvasManager`, `SandwichLogicTests`, `InterpolationRenderLogicTests`, `PerfBaselineTests`, `.evaluate`, `InterpolationRecipe`, `FloatingPieceOverlayView`, `RasterLayerTexture`, `AnimationTimeline`, `.load`, `InterpolationModelLogicTests`, `SwiftUI`, `StrokeSettingsPanel`, `StrokeGeometry`, `StrokeSpatialIndex`, `GuideOverlayView`, `DeformFactorization`, `.stampStroke`, `SideToolbar`, `LayerRowModel`, `.group`, `LayerStackCell`, `InterpolationGuideLogicTests`, `VectorSample`, `.draw`, `CanvasManager`, `.indices`, `.eraseHybrid`, `.setUpGestures`, `.manager`, `CodingKeys`, `InterpolationEngineDiagnosticsLogicTests`, `InterpolateBar`, `.arched`, `TimedSample`, `VectorEraserMode`, `DabTarget`, `LayerStackListView`, `GuidePath`, `SpacingChart`, `StrokeStabilizer`, `ActionsMenu`, `.setCanvasPadding`, `TransformOverlaySupport.swift`, `Kind`?**
  _High betweenness centrality (0.344) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `CanvasManager`, `VectorEraserHybridLogicTests`, `Lattice`, `Coordinator`, `.transparentFormat`, `CanvasManager`, `.manager`, `Brush`, `ColorPickerPanel`, `StrokeCanvasView`, `.rasterize`, `Coordinator`, `PointCloudIndex`, `VectorCanvas`, `VectorEraserLogicTests`, `ShapeOverlayView`, `BrushEngineLogicTests`, `StrokeGeometryLogicTests`, `ARAPLogicTests`, `CanvasManager`, `layers`, `InterpolationRenderLogicTests`, `PerfBaselineTests`, `.evaluate`, `InterpolationRecipe`, `FloatingPieceOverlayView`, `RasterLayerTexture`, `AnimationTimeline`, `.load`, `InterpolationModelLogicTests`, `StrokeGeometry`, `StrokeSpatialIndex`, `GuideOverlayView`, `CGFloat`, `DeformFactorization`, `.stampStroke`, `.group`, `InterpolationGuideLogicTests`, `VectorSample`, `.indices`, `.eraseHybrid`, `.setUpGestures`, `SelectionOverlayView`, `.manager`, `InterpolationEngineDiagnosticsLogicTests`, `.arched`, `TimedSample`, `DabTarget`, `ObjectTransformOverlayView`, `GuidePath`, `LayerStackListView.Coordinator`, `StrokeStabilizer`, `.setCanvasPadding`, `TransformOverlaySupport.swift`?**
  _High betweenness centrality (0.176) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CanvasManager`, `CGPoint`, `Brush`, `.rasterize`, `CanvasManager`, `layers`, `InterpolationRecipe`, `RasterLayerTexture`, `SwiftUI`, `.withStructureUndo`, `CGFloat`, `MetalFillEngine`, `VectorSample`, `GuideStroke`, `PerfMonitor`, `TimedSample`, `VectorEraserMode`, `Layer`, `UndoHistory`, `SpacingChart`, `.setCanvasPadding`?**
  _High betweenness centrality (0.088) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 109 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 109 INFERRED edges - model-reasoned connections that need verification._