# Graph Report - PaintApp-phase6b-ui  (2026-08-14)

## Corpus Check
- 162 files · ~347,499 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4296 nodes · 13183 edges · 160 communities (147 shown, 13 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1517 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `dbbaabc6`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- cels
- Lattice
- Coordinator
- ShapeGeometry
- CanvasManager
- StrokeGeometryLogicTests
- CanvasManager
- ColorPickerPanel
- Coordinator
- VectorEraserHybridLogicTests
- VectorSample
- UIKit
- ProjectBackupManager
- CodingKeys
- .manager
- VectorCanvas
- PointCloudIndex
- AlphaMask
- CanvasManager
- VectorEraserLogicTests
- .overlappingManager
- StrokeCanvasView
- ShapeOverlayView
- AnimationTimeline
- RenderNode
- CanvasManager
- BrushEngineLogicTests
- ARAPLogicTests
- InterpolationRecipe
- .transparentFormat
- .evaluate
- SandwichLogicTests
- PerfBaselineTests
- CanvasManager
- ParityScenario
- layers
- InterpolationRenderLogicTests
- MetalFillEngine
- Codable
- GuideRow
- InterpolationModelLogicTests
- GuideOverlayView
- PlaybackBoundsCharacterizationTests
- StrokeSettingsPanel
- RasterLayerTexture
- DeformFactorization
- InterpolationEngineDiagnosticsLogicTests
- StrokeSpatialIndex
- BlendMode
- BackupManagerLogicTests
- SaveSnapshot
- XCTestCase
- FillParams
- FloatingPieceOverlayView
- Layer Compositing
- CGPoint
- .load
- TouchCountRecognizer
- .encode
- View
- RenderTreeCharacterizationTests
- CompositorParityLogicTests
- CodingKeys
- GuideStroke
- agent
- .group
- RenderRequest
- LayerStackCell
- ActivePanel
- Composite.metal
- .stampStroke
- InterpolationGuideLogicTests
- ViewPresetCharacterizationTests
- Compositor.swift
- CanvasManager
- CodingKeys
- ContentView
- SwiftUI
- .indices
- .coverage
- .handleTransformGesture
- ObjectTransformOverlayView
- BlockDragCharacterizationTests
- .manager
- Coordinator
- InterpolationRefusal
- Color
- ActionsMenu
- BrushSettingsPanel
- GalleryView
- PerfMonitor
- CanvasManager
- .clearRasterizeCache
- InterpolateBar
- DrawingView
- .arched
- CGFloat
- TimedSample
- CanvasSizePickerView
- bash
- StructureSnapshot
- .withStructureUndo
- LayerRowModel
- SideToolbar
- .draw
- .registerGroups
- UndoHistory
- CanvasHostView
- StrokeGeometry
- CGContextDabTarget
- GuidePath
- SpacingChart
- String
- StrokeStabilizer
- MotionGroup
- LayerStackListView.Coordinator
- 4. Future upgrades — the deferred list
- You are the Orchestrator for the rest of the layer-compositing project
- compositeOver
- Is the brush engine ready for `.ABR` / Procreate brush import?
- MaskSource
- .gpuAndCPU
- StrokeGestureRecognizer
- TransformOverlaySupport.swift
- PaintSoftware - iPad Drawing and Animation App
- SelectPanel
- MotionGroupRow
- Usage Guide
- Known Issues
- .attach
- command
- CutOutcome
- CLAUDE.md
- Layer
- Multi-Session Protocol
- ManifestSkeleton
- MetalCompositor.swift
- VectorScratchRole
- Atomic
- What needs to change
- parallel_test.sh
- Hashable
- Kind
- Performance baseline
- worker-bugfix
- worker-research
- Foundation
- cleanup_session.sh
- screenshot.sh
- .assertPixelsIdentical
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- Gesture
- Phase 6b — §6.5 mask UI / §6.6 lifecycle — worker notes
- .init
- LayerTransform

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 536 edges
2. `CGFloat` - 410 edges
3. `VectorCanvas` - 123 edges
4. `CanvasManager` - 116 edges
5. `layers` - 115 edges
6. `CanvasManager` - 100 edges
7. `VectorSample` - 99 edges
8. `Lattice` - 98 edges
9. `Coordinator` - 90 edges
10. `InterpolationGuideLogicTests` - 90 edges

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

## Communities (160 total, 13 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.05
Nodes (30): FillUITests, LayerUITests, .crossing, Bool, CGVector, Int, String, TimeInterval (+22 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 2 - "Lattice"
Cohesion: 0.09
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 3 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 4 - "ShapeGeometry"
Cohesion: 0.05
Nodes (32): CaseIterable, Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom (+24 more)

### Community 5 - "CanvasManager"
Cohesion: 0.05
Nodes (38): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+30 more)

### Community 6 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (7): Intersection, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 7 - "CanvasManager"
Cohesion: 0.06
Nodes (29): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationOptions (+21 more)

### Community 8 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 9 - "Coordinator"
Cohesion: 0.05
Nodes (36): LayerHostView, Bool, NSCoder, AppliedTool, CanvasView, Coordinator, .sandwichPresentation, InterpolationPreviewKey (+28 more)

### Community 10 - "VectorEraserHybridLogicTests"
Cohesion: 0.12
Nodes (15): ParityReport, .diagnostic, .isExact, RasterVectorParity, Bool, Int, UIImage, VectorStroke (+7 more)

### Community 11 - "VectorSample"
Cohesion: 0.12
Nodes (12): Brush, VectorSample, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser (+4 more)

### Community 12 - "UIKit"
Cohesion: 0.08
Nodes (5): CoreGraphics, Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 13 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 14 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 15 - ".manager"
Cohesion: 0.13
Nodes (5): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 16 - "VectorCanvas"
Cohesion: 0.06
Nodes (54): Identifiable, CodableColor, .uiColor, image, kind, ElementData, fill, image (+46 more)

### Community 17 - "PointCloudIndex"
Cohesion: 0.12
Nodes (16): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+8 more)

### Community 18 - "AlphaMask"
Cohesion: 0.12
Nodes (10): AlphaMask, .isActive, Bool, Float, MaskParityLogicTests, .side, Bool, CanvasManager (+2 more)

### Community 19 - "CanvasManager"
Cohesion: 0.07
Nodes (32): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+24 more)

### Community 20 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 21 - ".overlappingManager"
Cohesion: 0.15
Nodes (5): CanvasManager, Int, StaticString, String, UInt

### Community 22 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (24): StrokeInput, TimeInterval, UITouch, UIView, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+16 more)

### Community 23 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 24 - "AnimationTimeline"
Cohesion: 0.05
Nodes (42): Gesture, LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer (+34 more)

### Community 25 - "RenderNode"
Cohesion: 0.14
Nodes (16): Array, .leafLayerIndices, .needsCompositorOnCanvas, CompositorOp, Content, leaf, node, RenderNode (+8 more)

### Community 26 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 27 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 28 - "ARAPLogicTests"
Cohesion: 0.14
Nodes (6): ARAPInterpolation, ARAPLogicTests, .rigidMotionL, StaticString, String, UInt

### Community 29 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (13): Equatable, CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding (+5 more)

### Community 30 - ".transparentFormat"
Cohesion: 0.05
Nodes (39): IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath, CGRect (+31 more)

### Community 31 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+13 more)

### Community 32 - "SandwichLogicTests"
Cohesion: 0.13
Nodes (6): Battery, SandwichLogicTests, CanvasManager, CGImage, Int, String

### Community 33 - "PerfBaselineTests"
Cohesion: 0.20
Nodes (6): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64

### Community 34 - "CanvasManager"
Cohesion: 0.09
Nodes (17): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+9 more)

### Community 35 - "ParityScenario"
Cohesion: 0.11
Nodes (25): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+17 more)

### Community 36 - "layers"
Cohesion: 0.15
Nodes (10): .activeLayerIsVector, CanvasManager, Bool, CGSize, UIImage, .activeCelIsInBetween, CanvasManager, Bool (+2 more)

### Community 37 - "InterpolationRenderLogicTests"
Cohesion: 0.17
Nodes (10): ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage, UUID (+2 more)

### Community 38 - "MetalFillEngine"
Cohesion: 0.18
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 39 - "Codable"
Cohesion: 0.12
Nodes (32): Codable, Kind, folder, layer, LayerKind, compositing, raster, vector (+24 more)

### Community 40 - "GuideRow"
Cohesion: 0.21
Nodes (9): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+1 more)

### Community 41 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 42 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 43 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 44 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker (+18 more)

### Community 45 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 46 - "DeformFactorization"
Cohesion: 0.10
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 47 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.25
Nodes (4): rest, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 48 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 49 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 50 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 51 - "SaveSnapshot"
Cohesion: 0.14
Nodes (21): CelContent, CodableColor, .color, Color, .codable, LayerContent, ProjectStore, .projectsDirectory (+13 more)

### Community 52 - "XCTestCase"
Cohesion: 0.19
Nodes (8): Layer, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager, String

### Community 53 - "FillParams"
Cohesion: 0.18
Nodes (28): device, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor, gapRadius (+20 more)

### Community 54 - "FloatingPieceOverlayView"
Cohesion: 0.11
Nodes (18): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+10 more)

### Community 55 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 56 - "CGPoint"
Cohesion: 0.13
Nodes (8): CGPoint, .length, .point, LatticeLogicTests, Int, StaticString, String, UInt

### Community 57 - ".load"
Cohesion: 0.17
Nodes (11): CanvasManager, MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString (+3 more)

### Community 58 - "TouchCountRecognizer"
Cohesion: 0.21
Nodes (9): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+1 more)

### Community 59 - ".encode"
Cohesion: 0.19
Nodes (14): MTLTexture, CompositorMetalEngine, ScratchTexturePool, Bool, CGImage, Double, Float, Int (+6 more)

### Community 60 - "View"
Cohesion: 0.15
Nodes (27): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex (+19 more)

### Community 61 - "RenderTreeCharacterizationTests"
Cohesion: 0.20
Nodes (4): StaticString, RenderTreeCharacterizationTests, CanvasManager, String

### Community 62 - "CompositorParityLogicTests"
Cohesion: 0.19
Nodes (6): CanvasFixture, CGSize, UIColor, UIImage, CompositorParityLogicTests, UIColor

### Community 63 - "CodingKeys"
Cohesion: 0.08
Nodes (26): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+18 more)

### Community 64 - "GuideStroke"
Cohesion: 0.12
Nodes (15): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+7 more)

### Community 65 - "agent"
Cohesion: 0.08
Nodes (25): agent, orchestrator, worker-feature, worker-integration, worker-test, worker-ui, model, description (+17 more)

### Community 66 - ".group"
Cohesion: 0.17
Nodes (7): Group, MotionGrouping, Options, Bool, Int, Set, groups

### Community 67 - "RenderRequest"
Cohesion: 0.16
Nodes (18): CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, SandwichRequests, Bool, Cel (+10 more)

### Community 68 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 69 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 70 - "Composite.metal"
Cohesion: 0.28
Nodes (24): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+16 more)

### Community 71 - ".stampStroke"
Cohesion: 0.14
Nodes (14): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+6 more)

### Community 73 - "ViewPresetCharacterizationTests"
Cohesion: 0.11
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 74 - "Compositor.swift"
Cohesion: 0.19
Nodes (19): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+11 more)

### Community 75 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 76 - "CodingKeys"
Cohesion: 0.09
Nodes (22): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, customBrushes (+14 more)

### Community 77 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 78 - "SwiftUI"
Cohesion: 0.09
Nodes (12): Combine, .interpolateButton, GalleryTileView, .body, Void, InterpolatePanel, .body, .groupOverlayOption (+4 more)

### Community 80 - ".coverage"
Cohesion: 0.21
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 81 - ".handleTransformGesture"
Cohesion: 0.31
Nodes (3): CGSize, Void, Recognizer

### Community 82 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 83 - "BlockDragCharacterizationTests"
Cohesion: 0.19
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 84 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 85 - "Coordinator"
Cohesion: 0.17
Nodes (12): NSObject, Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UIView (+4 more)

### Community 86 - "InterpolationRefusal"
Cohesion: 0.13
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 87 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 88 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 89 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 90 - "GalleryView"
Cohesion: 0.21
Nodes (8): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryView, .body, CanvasManager, Void

### Community 91 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 92 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 94 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 95 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 96 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 97 - "CGFloat"
Cohesion: 0.12
Nodes (15): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, ClosedFit (+7 more)

### Community 98 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 99 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 100 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 101 - "StructureSnapshot"
Cohesion: 0.20
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 102 - ".withStructureUndo"
Cohesion: 0.09
Nodes (22): CelLocation, BlendMode, Double, String, UUID, Void, CanvasManager, .activeViewName (+14 more)

### Community 103 - "LayerRowModel"
Cohesion: 0.18
Nodes (10): IndexPath, LayerRowModel, .folderID, .maskSource, BlendMode, Bool, Double, String (+2 more)

### Community 104 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 105 - ".draw"
Cohesion: 0.33
Nodes (8): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 107 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 108 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 109 - "StrokeGeometry"
Cohesion: 0.15
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 110 - "CGContextDabTarget"
Cohesion: 0.25
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 111 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 112 - "SpacingChart"
Cohesion: 0.24
Nodes (3): SpacingChart, .curve, .draggable

### Community 113 - "String"
Cohesion: 0.07
Nodes (27): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+19 more)

### Community 114 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 115 - "MotionGroup"
Cohesion: 0.23
Nodes (9): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 116 - "LayerStackListView.Coordinator"
Cohesion: 0.23
Nodes (7): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 117 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 118 - "You are the Orchestrator for the rest of the layer-compositing project"
Cohesion: 0.18
Nodes (10): At each phase boundary, Deliberately cut, with the answer worked out, Gotchas that each cost a cycle — put these in every worker prompt, Open bug, deliberately not fixed, Phase 6b — the seam is already built, do not rebuild it, Read this first, State, What is left (+2 more)

### Community 119 - "compositeOver"
Cohesion: 0.31
Nodes (11): blendOver(), compositeFill(), compositeMask(), compositeOver(), constant, float4, kernel, uint (+3 more)

### Community 120 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 121 - "MaskSource"
Cohesion: 0.15
Nodes (11): MaskSource, folder, .id, layer, Encoder, UUID, CanvasManager, .renderLeafOrder (+3 more)

### Community 122 - ".gpuAndCPU"
Cohesion: 0.24
Nodes (4): BlendMode, Bool, CGImage, UIImage

### Community 123 - "StrokeGestureRecognizer"
Cohesion: 0.27
Nodes (7): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, UIGestureRecognizer

### Community 124 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 125 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 126 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 127 - "MotionGroupRow"
Cohesion: 0.27
Nodes (7): .body, MotionGroupRow, .body, .colourBakeButton, .wholeFrameNote, CanvasManager, String

### Community 128 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 129 - "Known Issues"
Cohesion: 0.29
Nodes (7): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), `duplicateLayer` drops `blendMode`, and now `alphaMask` too (2026-08-13), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 130 - ".attach"
Cohesion: 0.26
Nodes (4): Context, UILongPressGestureRecognizer, UIPinchGestureRecognizer, UITableView

### Community 131 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 132 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 134 - "Layer"
Cohesion: 0.22
Nodes (8): Layer, BlendMode, Bool, Cel, Double, String, UIImage, UUID

### Community 135 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 136 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 137 - "MetalCompositor.swift"
Cohesion: 0.29
Nodes (6): Metal, BlendMode, .shaderCode, MetalCompositor, UInt32, simd

### Community 138 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 139 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 140 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 141 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 142 - "Hashable"
Cohesion: 0.29
Nodes (6): Hashable, Tool, eraser, fill, pen, pencil

### Community 143 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 144 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 145 - "worker-bugfix"
Cohesion: 0.50
Nodes (4): worker-bugfix, description, mode, model

### Community 146 - "worker-research"
Cohesion: 0.50
Nodes (4): worker-research, description, mode, model

### Community 147 - "Foundation"
Cohesion: 0.12
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 150 - ".assertPixelsIdentical"
Cohesion: 0.40
Nodes (3): CGImage, CGRect, UInt8

### Community 156 - "Gesture"
Cohesion: 0.33
Nodes (6): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut

### Community 157 - "Phase 6b — §6.5 mask UI / §6.6 lifecycle — worker notes"
Cohesion: 0.33
Nodes (5): §6.6 lifecycle — what already existed vs. what was added, Phase 6b — §6.5 mask UI / §6.6 lifecycle — worker notes, Testing, What shipped, and where, Where §6.5/§6.6 as written needed a judgment call

## Knowledge Gaps
- **558 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+553 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `cels`, `Lattice`, `Coordinator`, `ShapeGeometry`, `CanvasManager`, `StrokeGeometryLogicTests`, `CanvasManager`, `Coordinator`, `VectorEraserHybridLogicTests`, `VectorSample`, `CodingKeys`, `Kind`, `VectorCanvas`, `PointCloudIndex`, `CanvasManager`, `VectorEraserLogicTests`, `.overlappingManager`, `StrokeCanvasView`, `ShapeOverlayView`, `AnimationTimeline`, `BrushEngineLogicTests`, `ARAPLogicTests`, `InterpolationRecipe`, `.transparentFormat`, `.evaluate`, `LayerTransform`, `PerfBaselineTests`, `CanvasManager`, `ParityScenario`, `layers`, `InterpolationRenderLogicTests`, `SandwichLogicTests`, `InterpolationModelLogicTests`, `GuideOverlayView`, `StrokeSettingsPanel`, `RasterLayerTexture`, `DeformFactorization`, `InterpolationEngineDiagnosticsLogicTests`, `StrokeSpatialIndex`, `FloatingPieceOverlayView`, `CGPoint`, `.load`, `.group`, `LayerStackCell`, `.stampStroke`, `InterpolationGuideLogicTests`, `CanvasManager`, `.indices`, `.handleTransformGesture`, `.manager`, `Coordinator`, `Color`, `ActionsMenu`, `CanvasManager`, `InterpolateBar`, `DrawingView`, `.arched`, `TimedSample`, `LayerRowModel`, `SideToolbar`, `.draw`, `.registerGroups`, `StrokeGeometry`, `CGContextDabTarget`, `GuidePath`, `SpacingChart`, `String`, `StrokeStabilizer`, `TransformOverlaySupport.swift`?**
  _High betweenness centrality (0.324) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `Lattice`, `Coordinator`, `ShapeGeometry`, `CanvasManager`, `StrokeGeometryLogicTests`, `CanvasManager`, `ColorPickerPanel`, `Coordinator`, `VectorEraserHybridLogicTests`, `VectorSample`, `VectorCanvas`, `PointCloudIndex`, `AlphaMask`, `CanvasManager`, `VectorEraserLogicTests`, `Gesture`, `StrokeCanvasView`, `ShapeOverlayView`, `AnimationTimeline`, `BrushEngineLogicTests`, `ARAPLogicTests`, `InterpolationRecipe`, `.transparentFormat`, `.evaluate`, `LayerTransform`, `PerfBaselineTests`, `CanvasManager`, `ParityScenario`, `layers`, `InterpolationRenderLogicTests`, `GuideOverlayView`, `RasterLayerTexture`, `DeformFactorization`, `InterpolationEngineDiagnosticsLogicTests`, `StrokeSpatialIndex`, `FloatingPieceOverlayView`, `.load`, `.group`, `.stampStroke`, `InterpolationGuideLogicTests`, `.indices`, `.handleTransformGesture`, `ObjectTransformOverlayView`, `.manager`, `CanvasManager`, `.clearRasterizeCache`, `.arched`, `CGFloat`, `TimedSample`, `.registerGroups`, `StrokeGeometry`, `CGContextDabTarget`, `GuidePath`, `String`, `StrokeStabilizer`, `LayerStackListView.Coordinator`, `TransformOverlaySupport.swift`?**
  _High betweenness centrality (0.220) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `.launchIntoEditor`, `cels`, `ShapeGeometry`, `StrokeGeometryLogicTests`, `VectorEraserHybridLogicTests`, `UIKit`, `.manager`, `AlphaMask`, `VectorEraserLogicTests`, `.assertPixelsIdentical`, `BrushEngineLogicTests`, `ARAPLogicTests`, `.transparentFormat`, `SandwichLogicTests`, `PerfBaselineTests`, `ParityScenario`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `PlaybackBoundsCharacterizationTests`, `InterpolationEngineDiagnosticsLogicTests`, `BackupManagerLogicTests`, `CGPoint`, `.load`, `RenderTreeCharacterizationTests`, `CompositorParityLogicTests`, `InterpolationGuideLogicTests`, `ViewPresetCharacterizationTests`, `BlockDragCharacterizationTests`?**
  _High betweenness centrality (0.081) - this node is a cross-community bridge._
- **Are the 57 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 57 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 13 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._