# Graph Report - agent-a706093d3723b2844  (2026-08-11)

## Corpus Check
- 156 files · ~299,465 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3891 nodes · 11865 edges · 149 communities (137 shown, 12 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1410 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9e8d55b9`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- .launchIntoEditor
- Coordinator
- CanvasManager
- Coordinator
- CanvasManager
- ColorPickerPanel
- bash
- Lattice
- StrokeGeometryLogicTests
- ProjectBackupManager
- ParityScenario
- .manager
- PointCloudIndex
- ARAPLogicTests
- VectorCanvas
- VectorSample
- String
- CGPoint
- ShapeOverlayView
- CompositorParityLogicTests
- StrokeCanvasView
- CanvasManager
- BrushEngineLogicTests
- VectorEraserLogicTests
- CanvasManager
- UIKit
- InterpolationRenderLogicTests
- .withStructureUndo
- .transparentFormat
- PerfBaselineTests
- .evaluate
- ShapeGeometry
- layers
- CanvasManager
- Codable
- InterpolationRecipe
- RasterLayerTexture
- VectorEraserHybridLogicTests
- AnimationTimeline
- InterpolationModelLogicTests
- PlaybackBoundsCharacterizationTests
- DeformFactorization
- BrushDynamics
- .load
- GuideOverlayView
- ShapeDetectorLogicTests
- FillParams
- Layer Compositing
- TouchCountRecognizer
- XCTestCase
- MetalFillEngine
- BackupManagerLogicTests
- .stampStroke
- ObjectTransformOverlayView
- LayerTreeCharacterizationTests
- CodingKeys
- LayerOptionsPanel
- LayerStackCell
- ActivePanel
- LayerRowModel
- InterpolationGuideLogicTests
- StrokeSettingsPanel
- CGFloat
- FloatingPieceOverlayView
- StrokeSpatialIndex
- View
- ViewPresetCharacterizationTests
- ShapeDetector
- CanvasManager
- CodingKeys
- ContentView
- BrushBlendMode
- .indices
- SelectionOverlayView
- BlockDragCharacterizationTests
- .manager
- GuideStroke
- InterpolationRefusal
- RenderNode
- Color
- BrushSettingsPanel
- OnionSkinLogicTests
- PerfMonitor
- .splitStroke
- CodingKeys
- SelectionMode
- InterpolateBar
- GalleryView
- InterpolationEngineDiagnosticsLogicTests
- ProjectSaveLogicTests
- DrawingView
- .arched
- CanvasSizePickerView
- SwiftUI
- RenderRequest
- SideToolbar
- TimedSample
- LayerStackRow
- Foundation
- CompositorMetalEngine
- UndoHistory
- CanvasHostView
- CGContextDabTarget
- LayerStackListView
- GuidePath
- SpacingChart
- LayerStackListView.Coordinator
- .analyse
- StrokeStabilizer
- MotionGroup
- CanvasManager
- SelectPanel
- 4. Future upgrades — the deferred list
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- .composite
- TransformOverlaySupport.swift
- PaintSoftware - iPad Drawing and Animation App
- Edge
- Layer
- .menuButton
- EraserSettingsPanel
- Usage Guide
- CutOutcome
- Kind
- InterpolatePanel
- CLAUDE.md
- Known Issues
- Multi-Session Protocol
- ManifestSkeleton
- ProjectStore.swift
- VectorScratchRole
- Atomic
- What needs to change
- parallel_test.sh
- Performance baseline
- MetalCompositor.swift
- CopiedCel
- cleanup_session.sh
- screenshot.sh
- .init
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- ThumbnailRenderer.swift

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

## Communities (149 total, 12 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 1 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 2 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 3 - "CanvasManager"
Cohesion: 0.06
Nodes (27): CanvasManager, .guideChips, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .motionGroupChips (+19 more)

### Community 4 - "Coordinator"
Cohesion: 0.06
Nodes (31): LayerHostView, NSCoder, AppliedTool, CanvasView, Coordinator, InterpolationPreviewKey, Bool, CanvasManager (+23 more)

### Community 5 - "CanvasManager"
Cohesion: 0.05
Nodes (38): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+30 more)

### Community 6 - "ColorPickerPanel"
Cohesion: 0.06
Nodes (43): Hashable, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+35 more)

### Community 7 - "bash"
Cohesion: 0.05
Nodes (63): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+55 more)

### Community 8 - "Lattice"
Cohesion: 0.07
Nodes (26): Interpolator, Options, Bool, vertices, DeformedCellIndex, Hit, Lattice, .cellCount (+18 more)

### Community 9 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (9): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, Int, StrokeGeometryLogicTests (+1 more)

### Community 10 - "ProjectBackupManager"
Cohesion: 0.10
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 11 - "ParityScenario"
Cohesion: 0.09
Nodes (33): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+25 more)

### Community 12 - ".manager"
Cohesion: 0.13
Nodes (5): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 13 - "PointCloudIndex"
Cohesion: 0.11
Nodes (15): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+7 more)

### Community 14 - "ARAPLogicTests"
Cohesion: 0.11
Nodes (8): ARAPInterpolation, groups, ARAPLogicTests, .rigidMotionL, Int, StaticString, String, UInt

### Community 15 - "VectorCanvas"
Cohesion: 0.09
Nodes (26): image, kind, Kind, fill, image, stroke, RenderQuality, full (+18 more)

### Community 16 - "VectorSample"
Cohesion: 0.12
Nodes (11): Brush, VectorSample, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser (+3 more)

### Community 17 - "String"
Cohesion: 0.09
Nodes (33): Identifiable, CodableColor, .uiColor, ElementData, fill, image, stroke, ImageRef (+25 more)

### Community 18 - "CGPoint"
Cohesion: 0.14
Nodes (8): CGPoint, .length, .point, LatticeLogicTests, Int, StaticString, String, UInt

### Community 19 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 20 - "CompositorParityLogicTests"
Cohesion: 0.11
Nodes (15): CanvasFixture, CGImage, CGRect, CGSize, UIColor, UIImage, UInt8, CompositorParityLogicTests (+7 more)

### Community 21 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (22): StrokeInput, TimeInterval, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas (+14 more)

### Community 22 - "CanvasManager"
Cohesion: 0.08
Nodes (20): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+12 more)

### Community 23 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 24 - "VectorEraserLogicTests"
Cohesion: 0.13
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 25 - "CanvasManager"
Cohesion: 0.09
Nodes (26): Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform (+18 more)

### Community 26 - "UIKit"
Cohesion: 0.09
Nodes (5): CoreGraphics, Darwin, LayerTransform, UIKit, XCTest

### Community 27 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 28 - ".withStructureUndo"
Cohesion: 0.09
Nodes (15): CanvasManager, StructureSnapshot, Int, Layer, String, Void, CanvasManager, .activeViewName (+7 more)

### Community 29 - ".transparentFormat"
Cohesion: 0.14
Nodes (15): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+7 more)

### Community 30 - "PerfBaselineTests"
Cohesion: 0.19
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 31 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, InterpolationEvaluator (+13 more)

### Community 32 - "ShapeGeometry"
Cohesion: 0.09
Nodes (19): Corner, bottomLeft, bottomRight, topLeft, topRight, FollowFrame, ShapeGeometry, .boundingRect (+11 more)

### Community 33 - "layers"
Cohesion: 0.15
Nodes (14): .activeLayerIsVector, .activeCelIsInBetween, .guideRefusal, .interpolationTarget, .linkableGuideStrokes, CanvasManager, Bool, Int (+6 more)

### Community 34 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 35 - "Codable"
Cohesion: 0.14
Nodes (30): Codable, BlendMode, normal, LayerKind, compositing, raster, vector, CelManifest (+22 more)

### Community 36 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (13): Equatable, CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding (+5 more)

### Community 37 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 38 - "VectorEraserHybridLogicTests"
Cohesion: 0.17
Nodes (8): VectorStroke, Bool, Double, Int, StaticString, UInt, VectorStroke, VectorEraserHybridLogicTests

### Community 39 - "AnimationTimeline"
Cohesion: 0.08
Nodes (25): Gesture, AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .isCollapsed, .layerNameColumn (+17 more)

### Community 40 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 41 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 42 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 43 - "BrushDynamics"
Cohesion: 0.09
Nodes (17): BrushDynamics, BrushGrain, BrushShape, custom, .displayName, hardRound, .id, pen (+9 more)

### Community 44 - ".load"
Cohesion: 0.16
Nodes (18): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, Bool, CanvasManager (+10 more)

### Community 45 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 46 - "ShapeDetectorLogicTests"
Cohesion: 0.16
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 47 - "FillParams"
Cohesion: 0.18
Nodes (28): device, float4, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+20 more)

### Community 48 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 49 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 50 - "XCTestCase"
Cohesion: 0.21
Nodes (7): StaticString, String, UInt, XCTestCase, RenderTreeCharacterizationTests, CanvasManager, String

### Community 51 - "MetalFillEngine"
Cohesion: 0.18
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 52 - "BackupManagerLogicTests"
Cohesion: 0.19
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 53 - ".stampStroke"
Cohesion: 0.15
Nodes (13): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+5 more)

### Community 54 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 55 - "LayerTreeCharacterizationTests"
Cohesion: 0.21
Nodes (5): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String

### Community 56 - "CodingKeys"
Cohesion: 0.08
Nodes (26): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+18 more)

### Community 57 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (22): .layerPanelRail, FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex (+14 more)

### Community 58 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 59 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 60 - "LayerRowModel"
Cohesion: 0.17
Nodes (14): NSObject, Coordinator, LayerRowModel, .folderID, Double, Int, Set, String (+6 more)

### Community 62 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 63 - "CGFloat"
Cohesion: 0.15
Nodes (12): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, ClosedRange (+4 more)

### Community 64 - "FloatingPieceOverlayView"
Cohesion: 0.17
Nodes (11): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+3 more)

### Community 65 - "StrokeSpatialIndex"
Cohesion: 0.19
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 66 - "View"
Cohesion: 0.13
Nodes (17): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+9 more)

### Community 67 - "ViewPresetCharacterizationTests"
Cohesion: 0.12
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 68 - "ShapeDetector"
Cohesion: 0.17
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 69 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 70 - "CodingKeys"
Cohesion: 0.09
Nodes (21): CodingKeys, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps (+13 more)

### Community 71 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 72 - "BrushBlendMode"
Cohesion: 0.10
Nodes (20): CaseIterable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+12 more)

### Community 74 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 75 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 76 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 77 - "GuideStroke"
Cohesion: 0.17
Nodes (10): GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool, Decoder (+2 more)

### Community 78 - "InterpolationRefusal"
Cohesion: 0.16
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 79 - "RenderNode"
Cohesion: 0.15
Nodes (16): Array, .leafLayerIndices, CanvasManager, .renderLeafOrder, .renderTree, CompositorOp, stack, Content (+8 more)

### Community 80 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 81 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 82 - "OnionSkinLogicTests"
Cohesion: 0.15
Nodes (10): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CGSize, UIColor, UIImage, OnionSkinLogicTests, Bool (+2 more)

### Community 83 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 84 - ".splitStroke"
Cohesion: 0.13
Nodes (5): Deterministic, StaticString, String, UInt, UInt64

### Community 85 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, brush, color, composite, elements, fill, fills, id (+10 more)

### Community 86 - "SelectionMode"
Cohesion: 0.14
Nodes (11): CanvasManager, Bool, CGSize, UIImage, SelectionMode, automatic, .displayName, .id (+3 more)

### Community 87 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 88 - "GalleryView"
Cohesion: 0.15
Nodes (12): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void (+4 more)

### Community 89 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.30
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 90 - "ProjectSaveLogicTests"
Cohesion: 0.25
Nodes (6): ProjectSaveLogicTests, Bool, CanvasManager, Cel, String, URL

### Community 91 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 92 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 93 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 94 - "SwiftUI"
Cohesion: 0.17
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 95 - "RenderRequest"
Cohesion: 0.21
Nodes (12): Leaf, MetalCompositor, Double, CanvasManager, LayerRenderSource, RenderBackground, RenderRequest, Bool (+4 more)

### Community 96 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 97 - "TimedSample"
Cohesion: 0.20
Nodes (3): TimedSample, .point, TimeInterval

### Community 98 - "LayerStackRow"
Cohesion: 0.14
Nodes (12): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+4 more)

### Community 99 - "Foundation"
Cohesion: 0.14
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 100 - "CompositorMetalEngine"
Cohesion: 0.27
Nodes (8): MTLTexture, CompositorMetalEngine, CGImage, Int, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice

### Community 101 - "UndoHistory"
Cohesion: 0.23
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 102 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 103 - "CGContextDabTarget"
Cohesion: 0.27
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 104 - "LayerStackListView"
Cohesion: 0.18
Nodes (8): IndexPath, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView, UIViewRepresentable

### Community 105 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 106 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 107 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 108 - ".analyse"
Cohesion: 0.29
Nodes (6): Group, MotionGrouping, Options, Bool, Int, Set

### Community 109 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 110 - "MotionGroup"
Cohesion: 0.23
Nodes (9): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 111 - "CanvasManager"
Cohesion: 0.21
Nodes (8): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage

### Community 112 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 113 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 114 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 115 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 116 - ".composite"
Cohesion: 0.27
Nodes (7): Compositor, CompositorBackend, coreGraphics, metal, CoreGraphicsCompositor, CGImage, CGRect

### Community 117 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 118 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 119 - "Edge"
Cohesion: 0.25
Nodes (5): Edge, bottom, left, right, top

### Community 120 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 121 - ".menuButton"
Cohesion: 0.32
Nodes (6): .blockMenu, .gapMenu, .loopMenu, ButtonRole, String, Void

### Community 122 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 123 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 124 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 125 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 126 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 128 - "Known Issues"
Cohesion: 0.33
Nodes (6): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 129 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 130 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 131 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 132 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 133 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 134 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 135 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 136 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 138 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

## Knowledge Gaps
- **495 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+490 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `.launchIntoEditor`, `Coordinator`, `CanvasManager`, `Coordinator`, `CanvasManager`, `Lattice`, `StrokeGeometryLogicTests`, `ParityScenario`, `PointCloudIndex`, `ARAPLogicTests`, `VectorCanvas`, `VectorSample`, `String`, `CGPoint`, `ShapeOverlayView`, `CompositorParityLogicTests`, `StrokeCanvasView`, `CanvasManager`, `BrushEngineLogicTests`, `VectorEraserLogicTests`, `CanvasManager`, `UIKit`, `InterpolationRenderLogicTests`, `.transparentFormat`, `PerfBaselineTests`, `.evaluate`, `ShapeGeometry`, `InterpolationRecipe`, `RasterLayerTexture`, `VectorEraserHybridLogicTests`, `AnimationTimeline`, `InterpolationModelLogicTests`, `DeformFactorization`, `BrushDynamics`, `.load`, `GuideOverlayView`, `ShapeDetectorLogicTests`, `.stampStroke`, `ObjectTransformOverlayView`, `LayerStackCell`, `LayerRowModel`, `InterpolationGuideLogicTests`, `StrokeSettingsPanel`, `StrokeSpatialIndex`, `ShapeDetector`, `CanvasManager`, `BrushBlendMode`, `.indices`, `.manager`, `GuideStroke`, `Color`, `OnionSkinLogicTests`, `.splitStroke`, `SelectionMode`, `InterpolateBar`, `InterpolationEngineDiagnosticsLogicTests`, `DrawingView`, `.arched`, `SideToolbar`, `TimedSample`, `CGContextDabTarget`, `LayerStackListView`, `GuidePath`, `SpacingChart`, `.analyse`, `StrokeStabilizer`, `CanvasManager`, `ActionsMenu`, `.composite`, `TransformOverlaySupport.swift`, `EraserSettingsPanel`, `Kind`?**
  _High betweenness centrality (0.318) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `Coordinator`, `CanvasManager`, `Coordinator`, `CanvasManager`, `ColorPickerPanel`, `Lattice`, `StrokeGeometryLogicTests`, `ParityScenario`, `PointCloudIndex`, `ARAPLogicTests`, `VectorCanvas`, `VectorSample`, `String`, `ShapeOverlayView`, `StrokeCanvasView`, `CanvasManager`, `BrushEngineLogicTests`, `VectorEraserLogicTests`, `CanvasManager`, `UIKit`, `InterpolationRenderLogicTests`, `.transparentFormat`, `PerfBaselineTests`, `.evaluate`, `ShapeGeometry`, `layers`, `InterpolationRecipe`, `RasterLayerTexture`, `VectorEraserHybridLogicTests`, `AnimationTimeline`, `InterpolationModelLogicTests`, `DeformFactorization`, `BrushDynamics`, `GuideOverlayView`, `ShapeDetectorLogicTests`, `.stampStroke`, `ObjectTransformOverlayView`, `InterpolationGuideLogicTests`, `CGFloat`, `FloatingPieceOverlayView`, `StrokeSpatialIndex`, `ShapeDetector`, `BrushBlendMode`, `.indices`, `SelectionOverlayView`, `.manager`, `GuideStroke`, `SelectionMode`, `InterpolationEngineDiagnosticsLogicTests`, `ProjectSaveLogicTests`, `.arched`, `TimedSample`, `CGContextDabTarget`, `GuidePath`, `LayerStackListView.Coordinator`, `.analyse`, `StrokeStabilizer`, `CanvasManager`, `TransformOverlaySupport.swift`, `Edge`?**
  _High betweenness centrality (0.237) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `cels`, `.launchIntoEditor`, `StrokeGeometryLogicTests`, `ParityScenario`, `.manager`, `ARAPLogicTests`, `CGPoint`, `CompositorParityLogicTests`, `BrushEngineLogicTests`, `VectorEraserLogicTests`, `UIKit`, `InterpolationRenderLogicTests`, `PerfBaselineTests`, `VectorEraserHybridLogicTests`, `InterpolationModelLogicTests`, `PlaybackBoundsCharacterizationTests`, `ShapeDetectorLogicTests`, `BackupManagerLogicTests`, `LayerTreeCharacterizationTests`, `InterpolationGuideLogicTests`, `ViewPresetCharacterizationTests`, `BlockDragCharacterizationTests`, `OnionSkinLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `ProjectSaveLogicTests`?**
  _High betweenness centrality (0.104) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 108 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 108 INFERRED edges - model-reasoned connections that need verification._