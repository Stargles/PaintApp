# Graph Report - agent-ae1e170ddae5aad1d  (2026-08-11)

## Corpus Check
- 157 files · ~307,002 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3939 nodes · 12013 edges · 136 communities (126 shown, 10 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1426 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `e1182ce7`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- cels
- InterpolationGuideLogicTests
- CGFloat
- VectorCanvas
- Lattice
- Coordinator
- CGPoint
- ARAPLogicTests
- Coordinator
- CanvasManager
- VectorSample
- CanvasManager
- ColorPickerPanel
- bash
- CanvasManager
- UIKit
- ParityScenario
- ProjectBackupManager
- .manager
- CompositorParityLogicTests
- StrokeCanvasView
- ShapeOverlayView
- layers
- BrushEngineLogicTests
- PerfBaselineTests
- .transparentFormat
- .evaluate
- VectorEraserHybridLogicTests
- InterpolationRenderLogicTests
- DeformFactorization
- CodingKeys
- CanvasManager
- Brush
- CanvasManager
- InterpolationRecipe
- AnimationTimeline
- RasterLayerTexture
- InterpolationModelLogicTests
- SaveSnapshot
- PlaybackBoundsCharacterizationTests
- StrokeSettingsPanel
- GuideOverlayView
- XCTestCase
- .restLattice
- BackupManagerLogicTests
- FillParams
- Layer Compositing
- LayerRowModel
- .load
- TouchCountRecognizer
- MetalFillEngine
- RenderTreeCharacterizationTests
- LayerOptionsPanel
- ObjectTransformOverlayView
- VectorEraser
- LayerStackCell
- ActivePanel
- MotionGroup
- FloatingPieceOverlayView
- View
- ViewPresetCharacterizationTests
- StrokeSpatialIndex
- CanvasManager
- ContentView
- InterpolationRefusal
- CodingKeys
- SelectionOverlayView
- PerfMonitor
- SwiftUI
- RenderNode
- BlockDragCharacterizationTests
- Codable
- ProjectStore
- GuideStroke
- Color
- BrushSettingsPanel
- InterpolationEngineDiagnosticsLogicTests
- BlendMode
- CanvasManager
- InterpolateBar
- DrawingView
- StructureSnapshot
- ViewPreset
- LayerStackRow
- CanvasSizePickerView
- .registerGroups
- RenderRequest
- SideToolbar
- .stampDab
- UndoHistory
- BrushShape
- CGContextDabTarget
- CompositorMetalEngine
- CanvasHostView
- Layer
- LayerStackListView.Coordinator
- OnionSkinLogicTests
- StrokeStabilizer
- SelectPanel
- 4. Future upgrades — the deferred list
- .composite
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- TransformOverlaySupport.swift
- PaintSoftware - iPad Drawing and Animation App
- .setCanvasPadding
- VectorEraserMode
- .menuButton
- Usage Guide
- .tableView
- CodingKeys
- CodingKeys
- Kind
- InterpolatePanel
- CLAUDE.md
- Known Issues
- Multi-Session Protocol
- ManifestSkeleton
- VectorScratchRole
- Atomic
- What needs to change
- parallel_test.sh
- Performance baseline
- MetalCompositor.swift
- AppVersion
- cleanup_session.sh
- screenshot.sh
- .init
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- .encode

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 533 edges
2. `CGFloat` - 407 edges
3. `VectorCanvas` - 122 edges
4. `layers` - 110 edges
5. `CanvasManager` - 103 edges
6. `CanvasManager` - 100 edges
7. `Lattice` - 98 edges
8. `VectorSample` - 98 edges
9. `InterpolationGuideLogicTests` - 90 edges
10. `Coordinator` - 79 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (136 total, 10 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 2 - "InterpolationGuideLogicTests"
Cohesion: 0.05
Nodes (22): GuideHandles, GuidePath, .end, .start, GuideSet, .isEmpty, SpacingChart, .curve (+14 more)

### Community 3 - "CGFloat"
Cohesion: 0.04
Nodes (42): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Sample, Void (+34 more)

### Community 4 - "VectorCanvas"
Cohesion: 0.06
Nodes (50): AnyObject, Identifiable, DabTarget, CodableColor, .uiColor, image, kind, DabLattice (+42 more)

### Community 5 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 6 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 7 - "CGPoint"
Cohesion: 0.07
Nodes (15): CGPoint, .length, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect (+7 more)

### Community 8 - "ARAPLogicTests"
Cohesion: 0.08
Nodes (24): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+16 more)

### Community 9 - "Coordinator"
Cohesion: 0.06
Nodes (32): LayerHostView, AppliedTool, CanvasView, Coordinator, InterpolationPreviewKey, Bool, CanvasManager, CGSize (+24 more)

### Community 10 - "CanvasManager"
Cohesion: 0.05
Nodes (40): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .effectiveLoopRange, .hasLoopBoundary, .isFillInAdjustableState (+32 more)

### Community 11 - "VectorSample"
Cohesion: 0.07
Nodes (13): VectorSample, .point, Deterministic, StaticString, String, UInt, UInt64, ClosedRange (+5 more)

### Community 12 - "CanvasManager"
Cohesion: 0.07
Nodes (24): CanvasManager, .guideChips, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .motionGroupChips (+16 more)

### Community 13 - "ColorPickerPanel"
Cohesion: 0.06
Nodes (44): Hashable, CelLocation, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+36 more)

### Community 14 - "bash"
Cohesion: 0.05
Nodes (63): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+55 more)

### Community 15 - "CanvasManager"
Cohesion: 0.07
Nodes (34): .currentFrame, .currentLayerIndex, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move (+26 more)

### Community 16 - "UIKit"
Cohesion: 0.06
Nodes (8): CoreGraphics, Darwin, Foundation, DiscardedDabTarget, Notification.Name, ThumbnailRenderer, UIKit, XCTest

### Community 17 - "ParityScenario"
Cohesion: 0.09
Nodes (33): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+25 more)

### Community 18 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 19 - ".manager"
Cohesion: 0.13
Nodes (5): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 20 - "CompositorParityLogicTests"
Cohesion: 0.10
Nodes (15): CanvasFixture, CGImage, CGRect, CGSize, UIColor, UIImage, UInt8, CompositorParityLogicTests (+7 more)

### Community 21 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (23): StrokeInput, TimeInterval, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster (+15 more)

### Community 22 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 23 - "layers"
Cohesion: 0.12
Nodes (15): .activeLayerIsVector, .activeCelIsInBetween, .guideRefusal, .interpolationTarget, .linkableGuideStrokes, CanvasManager, Bool, Int (+7 more)

### Community 24 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 25 - "PerfBaselineTests"
Cohesion: 0.18
Nodes (8): BrushStamper, PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 26 - ".transparentFormat"
Cohesion: 0.12
Nodes (19): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+11 more)

### Community 27 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 28 - "VectorEraserHybridLogicTests"
Cohesion: 0.13
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 29 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 30 - "DeformFactorization"
Cohesion: 0.09
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 31 - "CodingKeys"
Cohesion: 0.08
Nodes (31): CodingKeys, brush, color, composite, elements, fill, fills, id (+23 more)

### Community 32 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 33 - "Brush"
Cohesion: 0.09
Nodes (21): Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+13 more)

### Community 34 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 35 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (13): Equatable, CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding (+5 more)

### Community 36 - "AnimationTimeline"
Cohesion: 0.08
Nodes (25): Gesture, AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .isCollapsed, .layerNameColumn (+17 more)

### Community 37 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 38 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 39 - "SaveSnapshot"
Cohesion: 0.11
Nodes (24): CelContent, LayerContent, ProjectSummary, SaveSnapshot, Bool, CGSize, Date, Double (+16 more)

### Community 40 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 41 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker (+18 more)

### Community 42 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 43 - "XCTestCase"
Cohesion: 0.17
Nodes (9): Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager (+1 more)

### Community 44 - ".restLattice"
Cohesion: 0.14
Nodes (5): ARAPInterpolation, Int, StaticString, String, UInt

### Community 45 - "BackupManagerLogicTests"
Cohesion: 0.18
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 46 - "FillParams"
Cohesion: 0.18
Nodes (28): device, float4, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+20 more)

### Community 47 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 48 - "LayerRowModel"
Cohesion: 0.14
Nodes (18): NSObject, Coordinator, LayerRowModel, .folderID, LayerStackListView, Bool, Coordinator, Double (+10 more)

### Community 49 - ".load"
Cohesion: 0.22
Nodes (8): ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString, String, UInt, URL

### Community 50 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 51 - "MetalFillEngine"
Cohesion: 0.18
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 52 - "RenderTreeCharacterizationTests"
Cohesion: 0.22
Nodes (3): RenderTreeCharacterizationTests, CanvasManager, String

### Community 53 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (23): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex (+15 more)

### Community 54 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 55 - "VectorEraser"
Cohesion: 0.15
Nodes (11): CutOutcome, cut, missed, unchanged, IntersectionDriver, Sweep, Bool, CGRect (+3 more)

### Community 56 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 57 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 58 - "MotionGroup"
Cohesion: 0.10
Nodes (21): CodingKey, Layer, CodingKeys, boundGroups, id, interval, role, samples (+13 more)

### Community 59 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 60 - "View"
Cohesion: 0.14
Nodes (17): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+9 more)

### Community 61 - "ViewPresetCharacterizationTests"
Cohesion: 0.12
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 62 - "StrokeSpatialIndex"
Cohesion: 0.19
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 63 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 64 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 65 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 66 - "CodingKeys"
Cohesion: 0.10
Nodes (21): CodingKeys, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps (+13 more)

### Community 67 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 68 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 69 - "SwiftUI"
Cohesion: 0.13
Nodes (8): Combine, CodableColor, .color, Color, .codable, CodableColor, PhotosUI, SwiftUI

### Community 70 - "RenderNode"
Cohesion: 0.14
Nodes (18): Array, .leafLayerIndices, CanvasManager, .renderLeafOrder, .renderTree, CompositorOp, stack, Content (+10 more)

### Community 71 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 72 - "Codable"
Cohesion: 0.37
Nodes (15): Codable, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, Bool, CodableColor (+7 more)

### Community 73 - "ProjectStore"
Cohesion: 0.18
Nodes (9): BrushLibrary, .customBrushesDirectory, URL, ProjectStore, .projectsDirectory, CanvasManager, MainActor, URL (+1 more)

### Community 74 - "GuideStroke"
Cohesion: 0.18
Nodes (9): GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool, Decoder (+1 more)

### Community 75 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 76 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 77 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 78 - "BlendMode"
Cohesion: 0.11
Nodes (18): BlendMode, add, colorBurn, colorDodge, darken, difference, .displayName, hardLight (+10 more)

### Community 79 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 80 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 81 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 82 - "StructureSnapshot"
Cohesion: 0.19
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 83 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 84 - "LayerStackRow"
Cohesion: 0.13
Nodes (12): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+4 more)

### Community 85 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 86 - ".registerGroups"
Cohesion: 0.25
Nodes (3): GroupRegistration, RegistrationElement, RegistrationFrame

### Community 87 - "RenderRequest"
Cohesion: 0.21
Nodes (12): Leaf, MetalCompositor, Double, CanvasManager, LayerRenderSource, RenderBackground, RenderRequest, Bool (+4 more)

### Community 88 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 89 - ".stampDab"
Cohesion: 0.24
Nodes (6): DabRNG, Bool, CGBlendMode, Double, UIColor, UInt64

### Community 90 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 91 - "BrushShape"
Cohesion: 0.14
Nodes (14): CaseIterable, BrushShape, custom, .displayName, hardRound, .id, pen, pencil (+6 more)

### Community 92 - "CGContextDabTarget"
Cohesion: 0.25
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 93 - "CompositorMetalEngine"
Cohesion: 0.27
Nodes (8): MTLTexture, CompositorMetalEngine, CGImage, Int, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice

### Community 94 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 95 - "Layer"
Cohesion: 0.15
Nodes (11): Layer, Bool, Cel, Double, String, UIImage, UUID, LayerKind (+3 more)

### Community 96 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (7): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 97 - "OnionSkinLogicTests"
Cohesion: 0.24
Nodes (6): OnionSkinSource, PreviousCelOnionSkinSource, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 98 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 99 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 100 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 101 - ".composite"
Cohesion: 0.27
Nodes (7): Compositor, CompositorBackend, coreGraphics, metal, CoreGraphicsCompositor, CGImage, CGRect

### Community 102 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 103 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 104 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 105 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 106 - ".setCanvasPadding"
Cohesion: 0.36
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 107 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 108 - ".menuButton"
Cohesion: 0.32
Nodes (6): .blockMenu, .gapMenu, .loopMenu, ButtonRole, String, Void

### Community 109 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 110 - ".tableView"
Cohesion: 0.33
Nodes (4): IndexPath, Context, UISwipeActionsConfiguration, UITableView

### Community 111 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 112 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, guideIDs, localEdits, mode, references, spacing, t

### Community 113 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 114 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 116 - "Known Issues"
Cohesion: 0.33
Nodes (6): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 117 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 118 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 119 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 120 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 121 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 122 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 123 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 125 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

## Knowledge Gaps
- **511 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+506 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `cels`, `InterpolationGuideLogicTests`, `VectorCanvas`, `Lattice`, `Coordinator`, `CGPoint`, `ARAPLogicTests`, `Coordinator`, `CanvasManager`, `VectorSample`, `CanvasManager`, `CanvasManager`, `ParityScenario`, `CompositorParityLogicTests`, `StrokeCanvasView`, `ShapeOverlayView`, `BrushEngineLogicTests`, `PerfBaselineTests`, `.transparentFormat`, `.evaluate`, `VectorEraserHybridLogicTests`, `InterpolationRenderLogicTests`, `DeformFactorization`, `CodingKeys`, `CanvasManager`, `Brush`, `InterpolationRecipe`, `AnimationTimeline`, `RasterLayerTexture`, `InterpolationModelLogicTests`, `StrokeSettingsPanel`, `GuideOverlayView`, `.restLattice`, `LayerRowModel`, `.load`, `ObjectTransformOverlayView`, `VectorEraser`, `LayerStackCell`, `StrokeSpatialIndex`, `CanvasManager`, `Color`, `InterpolationEngineDiagnosticsLogicTests`, `CanvasManager`, `InterpolateBar`, `DrawingView`, `.registerGroups`, `SideToolbar`, `.stampDab`, `CGContextDabTarget`, `OnionSkinLogicTests`, `StrokeStabilizer`, `.composite`, `ActionsMenu`, `TransformOverlaySupport.swift`, `.setCanvasPadding`, `.tableView`, `Kind`?**
  _High betweenness centrality (0.313) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `InterpolationGuideLogicTests`, `CGFloat`, `VectorCanvas`, `Lattice`, `Coordinator`, `ARAPLogicTests`, `Coordinator`, `CanvasManager`, `VectorSample`, `CanvasManager`, `ColorPickerPanel`, `CanvasManager`, `UIKit`, `ParityScenario`, `StrokeCanvasView`, `ShapeOverlayView`, `layers`, `BrushEngineLogicTests`, `PerfBaselineTests`, `.transparentFormat`, `.evaluate`, `VectorEraserHybridLogicTests`, `InterpolationRenderLogicTests`, `DeformFactorization`, `CodingKeys`, `CanvasManager`, `InterpolationRecipe`, `AnimationTimeline`, `RasterLayerTexture`, `InterpolationModelLogicTests`, `GuideOverlayView`, `.restLattice`, `.load`, `ObjectTransformOverlayView`, `VectorEraser`, `FloatingPieceOverlayView`, `StrokeSpatialIndex`, `SelectionOverlayView`, `InterpolationEngineDiagnosticsLogicTests`, `CanvasManager`, `.registerGroups`, `.stampDab`, `CGContextDabTarget`, `LayerStackListView.Coordinator`, `StrokeStabilizer`, `TransformOverlaySupport.swift`, `.setCanvasPadding`?**
  _High betweenness centrality (0.241) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `InterpolationGuideLogicTests`, `CGFloat`, `VectorSample`, `ColorPickerPanel`, `CanvasManager`, `layers`, `CanvasManager`, `Brush`, `InterpolationRecipe`, `RasterLayerTexture`, `MetalFillEngine`, `MotionGroup`, `PerfMonitor`, `SwiftUI`, `GuideStroke`, `StructureSnapshot`, `ViewPreset`, `UndoHistory`, `Layer`, `VectorEraserMode`?**
  _High betweenness centrality (0.083) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 109 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 109 INFERRED edges - model-reasoned connections that need verification._