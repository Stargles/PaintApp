# Graph Report - PaintApp-phase6b-live  (2026-08-14)

## Corpus Check
- 162 files · ~349,574 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4302 nodes · 13186 edges · 158 communities (149 shown, 9 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1493 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5b33eef0`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- cels
- VectorEraserHybridLogicTests
- Coordinator
- CanvasManager
- ShapeGeometry
- layers
- String
- InterpolationRecipe
- ColorPickerPanel
- StrokeGeometryLogicTests
- VectorCanvas
- .transparentFormat
- Coordinator
- .manager
- MaskParityLogicTests
- CanvasManager
- UIKit
- Lattice
- StrokeCanvasView
- ProjectBackupManager
- ARAPLogicTests
- PointCloudIndex
- PerfBaselineTests
- VectorEraserLogicTests
- CGPoint
- Codable
- ShapeOverlayView
- BrushEngineLogicTests
- CompositorParityLogicTests
- SandwichLogicTests
- InterpolationRenderLogicTests
- DeformFactorization
- CanvasManager
- InterpolationEvaluator
- AnimationTimeline
- VectorSample
- CanvasManager
- BackupManagerLogicTests
- .solidImage
- GuideOverlayView
- PlaybackBoundsCharacterizationTests
- StrokeSettingsPanel
- BlendMode
- .withStructureUndo
- StrokeSpatialIndex
- CanvasManager
- SaveSnapshot
- FillParams
- FloatingPieceOverlayView
- Layer Compositing
- .stampStroke
- .load
- TouchCountRecognizer
- MetalFillEngine
- .encode
- RenderRequest
- RasterLayerTexture
- LayerOptionsPanel
- LayerTreeCharacterizationTests
- RenderTreeCharacterizationTests
- ProjectManifest
- CodingKeys
- LayerRowModel
- agent
- LayerStackCell
- ActivePanel
- CGFloat
- Composite.metal
- InterpolationGuideLogicTests
- GuideStroke
- MaskSource
- View
- ViewPresetCharacterizationTests
- Compositor.swift
- CanvasManager
- CodingKeys
- ContentView
- .coverage
- .makeUIView
- InterpolationEngineDiagnosticsLogicTests
- SelectionOverlayView
- BlockDragCharacterizationTests
- PerfMonitor
- SwiftUI
- CodingKeys
- TimedSample
- .setUpGestures
- .manager
- InterpolationRefusal
- RenderNode
- Color
- BrushSettingsPanel
- .indices
- StructureSnapshot
- InterpolateBar
- GalleryView
- DrawingView
- .registerGroups
- .arched
- CanvasSizePickerView
- DabTarget
- bash
- ShapeDetector
- SideToolbar
- LayerStackRow
- UndoHistory
- ObjectTransformOverlayView
- .draw
- ViewPreset
- CanvasHostView
- XCTestCase
- LayerStackListView
- SpacingChart
- MotionGroup
- LayerStackListView.Coordinator
- TransformOverlaySupport.swift
- GuidePath
- StrokeStabilizer
- SelectPanel
- 1. `MaskResolver` at 2048² — the measurement
- 4. Future upgrades — the deferred list
- You are the Orchestrator for the rest of the layer-compositing project
- compositeOver
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- MotionGrouping
- Layer
- PaintSoftware - iPad Drawing and Animation App
- MetalCompositor.swift
- .menuButton
- Usage Guide
- Known Issues
- command
- CutOutcome
- Kind
- InterpolatePanel
- CLAUDE.md
- Multi-Session Protocol
- ManifestSkeleton
- CodingKeys
- VectorScratchRole
- Atomic
- What needs to change
- parallel_test.sh
- Corner
- Performance baseline
- worker-bugfix
- worker-research
- CopiedCel
- AppVersion
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 538 edges
2. `CGFloat` - 410 edges
3. `VectorCanvas` - 123 edges
4. `layers` - 114 edges
5. `CanvasManager` - 105 edges
6. `CanvasManager` - 100 edges
7. `VectorSample` - 99 edges
8. `Lattice` - 98 edges
9. `Coordinator` - 94 edges
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

## Communities (158 total, 9 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.05
Nodes (30): FillUITests, LayerUITests, .crossing, Bool, CGVector, Int, String, TimeInterval (+22 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 2 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (48): CustomStringConvertible, UIImage, UInt8, Backdrop, fill, image, none, Gesture (+40 more)

### Community 3 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 4 - "CanvasManager"
Cohesion: 0.05
Nodes (44): CanvasManager, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex (+36 more)

### Community 5 - "ShapeGeometry"
Cohesion: 0.06
Nodes (23): Int, Edge, bottom, left, right, top, FollowFrame, ShapeGeometry (+15 more)

### Community 6 - "layers"
Cohesion: 0.08
Nodes (25): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+17 more)

### Community 7 - "String"
Cohesion: 0.04
Nodes (51): CaseIterable, Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+43 more)

### Community 8 - "InterpolationRecipe"
Cohesion: 0.07
Nodes (23): Equatable, CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding (+15 more)

### Community 9 - "ColorPickerPanel"
Cohesion: 0.06
Nodes (43): Hashable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+35 more)

### Community 10 - "StrokeGeometryLogicTests"
Cohesion: 0.07
Nodes (10): Intersection, StrokeGeometry, Bool, Int, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString (+2 more)

### Community 11 - "VectorCanvas"
Cohesion: 0.09
Nodes (24): kind, Bool, CGAffineTransform, CGContext, CGPath, CGRect, CGSize, LayerTransform (+16 more)

### Community 12 - ".transparentFormat"
Cohesion: 0.09
Nodes (24): IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath, CGRect (+16 more)

### Community 13 - "Coordinator"
Cohesion: 0.07
Nodes (25): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, Coordinator, .sandwichPresentation, InterpolationPreviewKey (+17 more)

### Community 14 - ".manager"
Cohesion: 0.12
Nodes (8): CanvasFixture, CanvasManager, CGSize, Int, UUID, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 15 - "MaskParityLogicTests"
Cohesion: 0.10
Nodes (11): AlphaMask, .isActive, Bool, Float, MaskParityLogicTests, .side, Bool, CanvasManager (+3 more)

### Community 16 - "CanvasManager"
Cohesion: 0.08
Nodes (28): String, UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+20 more)

### Community 17 - "UIKit"
Cohesion: 0.06
Nodes (8): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, ThumbnailRenderer, UIKit, XCTest

### Community 18 - "Lattice"
Cohesion: 0.09
Nodes (23): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+15 more)

### Community 19 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (25): StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+17 more)

### Community 20 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 21 - "ARAPLogicTests"
Cohesion: 0.11
Nodes (8): ARAPInterpolation, groups, ARAPLogicTests, .rigidMotionL, Int, StaticString, String, UInt

### Community 22 - "PointCloudIndex"
Cohesion: 0.12
Nodes (16): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+8 more)

### Community 23 - "PerfBaselineTests"
Cohesion: 0.14
Nodes (9): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UIImage, UInt64 (+1 more)

### Community 24 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 25 - "CGPoint"
Cohesion: 0.13
Nodes (7): CGPoint, .length, LatticeLogicTests, Int, StaticString, String, UInt

### Community 26 - "Codable"
Cohesion: 0.09
Nodes (34): Codable, CodableColor, .uiColor, DabLattice, .range, ElementData, fill, image (+26 more)

### Community 27 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+21 more)

### Community 28 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 29 - "CompositorParityLogicTests"
Cohesion: 0.13
Nodes (8): CompositorParityLogicTests, Bool, CanvasManager, Int, StaticString, String, UIImage, UInt

### Community 30 - "SandwichLogicTests"
Cohesion: 0.13
Nodes (6): Battery, SandwichLogicTests, CanvasManager, CGImage, Int, String

### Community 31 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 32 - "DeformFactorization"
Cohesion: 0.09
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 33 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 34 - "InterpolationEvaluator"
Cohesion: 0.11
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, InterpolationEvaluator (+13 more)

### Community 35 - "AnimationTimeline"
Cohesion: 0.08
Nodes (25): Gesture, AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .isCollapsed, .layerNameColumn (+17 more)

### Community 36 - "VectorSample"
Cohesion: 0.17
Nodes (10): Brush, VectorSample, .point, Sweep, Bool, CGRect, ClosedRange, Double (+2 more)

### Community 37 - "CanvasManager"
Cohesion: 0.09
Nodes (15): CanvasManager, Bool, CGSize, UIImage, CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale (+7 more)

### Community 38 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 39 - ".solidImage"
Cohesion: 0.13
Nodes (8): CGImage, CGRect, UIColor, UIImage, UInt8, BlendMode, CGImage, UIColor

### Community 40 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 41 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 42 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker (+18 more)

### Community 43 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 44 - ".withStructureUndo"
Cohesion: 0.16
Nodes (10): .interpolationTarget, CanvasManager, Bool, Int, Void, Cel, .endFrame, Int (+2 more)

### Community 45 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 46 - "CanvasManager"
Cohesion: 0.12
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 47 - "SaveSnapshot"
Cohesion: 0.15
Nodes (19): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+11 more)

### Community 48 - "FillParams"
Cohesion: 0.18
Nodes (28): device, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor, gapRadius (+20 more)

### Community 49 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 50 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 51 - ".stampStroke"
Cohesion: 0.14
Nodes (12): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+4 more)

### Community 52 - ".load"
Cohesion: 0.22
Nodes (8): ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString, String, UInt, URL

### Community 53 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 54 - "MetalFillEngine"
Cohesion: 0.18
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 55 - ".encode"
Cohesion: 0.19
Nodes (14): MTLTexture, CompositorMetalEngine, ScratchTexturePool, Bool, CGImage, Double, Float, Int (+6 more)

### Community 56 - "RenderRequest"
Cohesion: 0.15
Nodes (18): CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, SandwichRequests, Bool, Cel (+10 more)

### Community 57 - "RasterLayerTexture"
Cohesion: 0.16
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 58 - "LayerOptionsPanel"
Cohesion: 0.14
Nodes (24): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex (+16 more)

### Community 59 - "LayerTreeCharacterizationTests"
Cohesion: 0.20
Nodes (7): Layer, StaticString, String, UInt, LayerTreeCharacterizationTests, CanvasManager, String

### Community 60 - "RenderTreeCharacterizationTests"
Cohesion: 0.22
Nodes (3): RenderTreeCharacterizationTests, CanvasManager, String

### Community 61 - "ProjectManifest"
Cohesion: 0.20
Nodes (20): LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest, LayerManifest (+12 more)

### Community 62 - "CodingKeys"
Cohesion: 0.08
Nodes (26): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+18 more)

### Community 63 - "LayerRowModel"
Cohesion: 0.16
Nodes (15): NSObject, Coordinator, LayerRowModel, .folderID, BlendMode, Double, Int, Set (+7 more)

### Community 64 - "agent"
Cohesion: 0.08
Nodes (25): agent, orchestrator, worker-feature, worker-integration, worker-test, worker-ui, model, description (+17 more)

### Community 65 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 66 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 67 - "CGFloat"
Cohesion: 0.15
Nodes (12): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, Capsule (+4 more)

### Community 68 - "Composite.metal"
Cohesion: 0.28
Nodes (24): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+16 more)

### Community 70 - "GuideStroke"
Cohesion: 0.14
Nodes (10): Void, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+2 more)

### Community 71 - "MaskSource"
Cohesion: 0.15
Nodes (12): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, CanvasManager (+4 more)

### Community 72 - "View"
Cohesion: 0.14
Nodes (17): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+9 more)

### Community 73 - "ViewPresetCharacterizationTests"
Cohesion: 0.12
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

### Community 78 - ".coverage"
Cohesion: 0.22
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 79 - ".makeUIView"
Cohesion: 0.12
Nodes (9): AppliedTool, CanvasView, Color, Context, Coordinator, Double, LayerTransform, UIView (+1 more)

### Community 80 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.23
Nodes (4): rest, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 81 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 82 - "BlockDragCharacterizationTests"
Cohesion: 0.21
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 83 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 84 - "SwiftUI"
Cohesion: 0.13
Nodes (8): Combine, CodableColor, .color, Color, .codable, CodableColor, PhotosUI, SwiftUI

### Community 85 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 86 - "TimedSample"
Cohesion: 0.14
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 87 - ".setUpGestures"
Cohesion: 0.15
Nodes (7): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, Void, Recognizer, UIRotationGestureRecognizer

### Community 88 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 89 - "InterpolationRefusal"
Cohesion: 0.16
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 90 - "RenderNode"
Cohesion: 0.15
Nodes (16): Array, .leafLayerIndices, .needsCompositorOnCanvas, CompositorOp, Content, leaf, node, RenderNode (+8 more)

### Community 91 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 92 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 94 - "StructureSnapshot"
Cohesion: 0.18
Nodes (6): CanvasManager, StructureSnapshot, Int, Layer, String, guideStrokes

### Community 95 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 96 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 97 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 98 - ".registerGroups"
Cohesion: 0.23
Nodes (3): GroupRegistration, RegistrationElement, RegistrationFrame

### Community 99 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 100 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 101 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 102 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 103 - "ShapeDetector"
Cohesion: 0.28
Nodes (4): ClosedFit, ShapeDetector, Bool, CGRect

### Community 104 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 105 - "LayerStackRow"
Cohesion: 0.14
Nodes (12): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+4 more)

### Community 106 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 107 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 108 - ".draw"
Cohesion: 0.33
Nodes (8): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 109 - "ViewPreset"
Cohesion: 0.21
Nodes (7): CanvasManager, Int, String, Bool, String, UUID, ViewPreset

### Community 110 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 111 - "XCTestCase"
Cohesion: 0.22
Nodes (7): OnionSkinSource, PreviousCelOnionSkinSource, XCTestCase, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 112 - "LayerStackListView"
Cohesion: 0.18
Nodes (8): IndexPath, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView, UIViewRepresentable

### Community 113 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 114 - "MotionGroup"
Cohesion: 0.22
Nodes (9): String, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 115 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 116 - "TransformOverlaySupport.swift"
Cohesion: 0.18
Nodes (10): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+2 more)

### Community 117 - "GuidePath"
Cohesion: 0.24
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 118 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 119 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 120 - "1. `MaskResolver` at 2048² — the measurement"
Cohesion: 0.17
Nodes (11): 1. `MaskResolver` at 2048² — the measurement, 2. §6.4 — what the live mask has to be resolved against, 3. What shipped, Alignment — checked, not assumed, Does it actually agree with the compositor?, How much of that is `-Onone`, Known gaps, none of them mine to close, Phase 6b — §6.4 live feedback while drawing (+3 more)

### Community 121 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 122 - "You are the Orchestrator for the rest of the layer-compositing project"
Cohesion: 0.18
Nodes (10): At each phase boundary, Deliberately cut, with the answer worked out, Gotchas that each cost a cycle — put these in every worker prompt, Open bug, deliberately not fixed, Phase 6b — the seam is already built, do not rebuild it, Read this first, State, What is left (+2 more)

### Community 123 - "compositeOver"
Cohesion: 0.31
Nodes (11): blendOver(), compositeFill(), compositeMask(), compositeOver(), constant, float4, kernel, uint (+3 more)

### Community 124 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 125 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 126 - "MotionGrouping"
Cohesion: 0.39
Nodes (5): Group, MotionGrouping, Options, Int, Set

### Community 127 - "Layer"
Cohesion: 0.22
Nodes (8): Layer, BlendMode, Bool, Cel, Double, String, UIImage, UUID

### Community 128 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 129 - "MetalCompositor.swift"
Cohesion: 0.29
Nodes (6): Metal, BlendMode, .shaderCode, MetalCompositor, UInt32, simd

### Community 130 - ".menuButton"
Cohesion: 0.32
Nodes (6): .blockMenu, .gapMenu, .loopMenu, ButtonRole, String, Void

### Community 131 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 132 - "Known Issues"
Cohesion: 0.29
Nodes (7): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), `duplicateLayer` drops `blendMode`, and now `alphaMask` too (2026-08-13), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 133 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 134 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 135 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 136 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 138 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 139 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 140 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, boundGroups, id, interval, role, samples

### Community 141 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 142 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 143 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 144 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 145 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 146 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 147 - "worker-bugfix"
Cohesion: 0.50
Nodes (4): worker-bugfix, description, mode, model

### Community 148 - "worker-research"
Cohesion: 0.50
Nodes (4): worker-research, description, mode, model

### Community 149 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 150 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

## Knowledge Gaps
- **561 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+556 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `cels`, `VectorEraserHybridLogicTests`, `Coordinator`, `CanvasManager`, `ShapeGeometry`, `layers`, `String`, `InterpolationRecipe`, `Kind`, `StrokeGeometryLogicTests`, `VectorCanvas`, `.transparentFormat`, `Coordinator`, `MaskParityLogicTests`, `CanvasManager`, `UIKit`, `Lattice`, `StrokeCanvasView`, `ARAPLogicTests`, `PointCloudIndex`, `PerfBaselineTests`, `VectorEraserLogicTests`, `CGPoint`, `Codable`, `ShapeOverlayView`, `BrushEngineLogicTests`, `CompositorParityLogicTests`, `SandwichLogicTests`, `InterpolationRenderLogicTests`, `DeformFactorization`, `InterpolationEvaluator`, `AnimationTimeline`, `VectorSample`, `CanvasManager`, `GuideOverlayView`, `StrokeSettingsPanel`, `StrokeSpatialIndex`, `CanvasManager`, `FloatingPieceOverlayView`, `.stampStroke`, `.load`, `RasterLayerTexture`, `LayerRowModel`, `LayerStackCell`, `InterpolationGuideLogicTests`, `CanvasManager`, `.makeUIView`, `InterpolationEngineDiagnosticsLogicTests`, `CodingKeys`, `TimedSample`, `.setUpGestures`, `.manager`, `Color`, `.indices`, `InterpolateBar`, `DrawingView`, `.registerGroups`, `.arched`, `DabTarget`, `ShapeDetector`, `SideToolbar`, `.draw`, `XCTestCase`, `LayerStackListView`, `SpacingChart`, `TransformOverlaySupport.swift`, `GuidePath`, `StrokeStabilizer`, `ActionsMenu`, `MotionGrouping`?**
  _High betweenness centrality (0.317) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `VectorEraserHybridLogicTests`, `Coordinator`, `CanvasManager`, `ShapeGeometry`, `layers`, `String`, `InterpolationRecipe`, `ColorPickerPanel`, `StrokeGeometryLogicTests`, `VectorCanvas`, `.transparentFormat`, `Coordinator`, `MaskParityLogicTests`, `CanvasManager`, `UIKit`, `Lattice`, `StrokeCanvasView`, `ARAPLogicTests`, `PointCloudIndex`, `PerfBaselineTests`, `VectorEraserLogicTests`, `ShapeOverlayView`, `BrushEngineLogicTests`, `InterpolationRenderLogicTests`, `DeformFactorization`, `InterpolationEvaluator`, `AnimationTimeline`, `VectorSample`, `CanvasManager`, `GuideOverlayView`, `.withStructureUndo`, `StrokeSpatialIndex`, `CanvasManager`, `FloatingPieceOverlayView`, `.stampStroke`, `.load`, `RasterLayerTexture`, `CGFloat`, `InterpolationGuideLogicTests`, `.makeUIView`, `InterpolationEngineDiagnosticsLogicTests`, `SelectionOverlayView`, `TimedSample`, `.setUpGestures`, `.manager`, `.indices`, `.registerGroups`, `.arched`, `DabTarget`, `ShapeDetector`, `ObjectTransformOverlayView`, `LayerStackListView.Coordinator`, `TransformOverlaySupport.swift`, `GuidePath`, `StrokeStabilizer`, `MotionGrouping`?**
  _High betweenness centrality (0.211) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `.launchIntoEditor`, `cels`, `VectorEraserHybridLogicTests`, `ShapeGeometry`, `InterpolationRecipe`, `StrokeGeometryLogicTests`, `.manager`, `MaskParityLogicTests`, `UIKit`, `ARAPLogicTests`, `PerfBaselineTests`, `VectorEraserLogicTests`, `CGPoint`, `BrushEngineLogicTests`, `CompositorParityLogicTests`, `SandwichLogicTests`, `InterpolationRenderLogicTests`, `BackupManagerLogicTests`, `.solidImage`, `PlaybackBoundsCharacterizationTests`, `.load`, `LayerTreeCharacterizationTests`, `RenderTreeCharacterizationTests`, `InterpolationGuideLogicTests`, `ViewPresetCharacterizationTests`, `InterpolationEngineDiagnosticsLogicTests`, `BlockDragCharacterizationTests`?**
  _High betweenness centrality (0.076) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 13 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 113 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 113 INFERRED edges - model-reasoned connections that need verification._