# Graph Report - PaintApp-maskui  (2026-08-15)

## Corpus Check
- 170 files · ~433,815 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4939 nodes · 15315 edges · 162 communities (150 shown, 12 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1639 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `de51d807`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- CGFloat
- CanvasManager
- .manager
- InterpolationRecipe
- CanvasManager
- Coordinator
- .transparentFormat
- XCTestCase
- CompositorParityLogicTests
- StrokeGeometryLogicTests
- ProjectBackupManager
- VectorEraserHybridLogicTests
- String
- Codable
- CGPoint
- AlphaMask
- AnimationTimeline
- layers
- UIKit
- PointCloudIndex
- ColorPickerPanel
- Coordinator
- EffectLayerLogicTests
- .drawLine
- StrokeCanvasView
- EffectMultiPassLogicTests
- Lattice
- PaintUITestCase
- .apply
- MetalFillEngine
- CanvasManager
- ProjectSaveLogicTests
- SaveSnapshot
- VectorCanvas
- ShapeOverlayView
- BrushEngineLogicTests
- VectorStroke
- SandwichLogicTests
- MaskSource
- Brush
- VectorEraserLogicTests
- PerfBaselineTests
- CanvasManager
- LayerHostView
- .launchIntoEditor
- StrokeSettingsPanel
- View
- InterpolationEvaluator
- ARAPLogicTests
- ProjectManifest
- ValueLayerLogicTests
- InterpolationRenderLogicTests
- DeformFactorization
- .encode
- RasterLayerTexture
- agent
- LayerStackCell
- Composite.metal
- VectorSample
- GuideOverlayView
- PlaybackBoundsCharacterizationTests
- Equatable
- BlendMode
- EffectParityLogicTests
- FillParams
- .coverage
- TouchCountRecognizer
- SwiftUI
- CodingKeys
- ActivePanel
- InterpolationGuideLogicTests
- RasterVectorParityLogicTests
- XCUIApplication
- CodingKey
- .group
- FloatingPieceOverlayView
- Effect
- GuideRow
- read
- .stampStroke
- Compositor.swift
- .indices
- MaskGuardLogicTests
- CanvasManager
- ActionsMenu
- ContentView
- LayerRowModel
- ObjectTransformOverlayView
- SelectionOverlayView
- PerfMonitor
- EffectParams
- .arched
- .renderSources
- Kind
- BlockDragCharacterizationTests
- SandwichCompositingUITests
- CodingKeys
- BackupManagerLogicTests
- InterpolationEngineDiagnosticsLogicTests
- BrushDynamics
- StructureSnapshot
- TimedSample
- RenderNode
- InterpolateBar
- DrawingView
- RenderRequest
- Layer
- CanvasSizePickerView
- DabTarget
- Layer Compositing
- ViewPreset
- SideToolbar
- .manager
- Is the brush engine ready for `.ABR` / Procreate brush import?
- CompositorRole
- Coordinator
- bash
- UndoHistory
- LayerStackListView
- SpacingChart
- CanvasHostView
- LayerStackListView.Coordinator
- TransformOverlaySupport.swift
- StrokeStabilizer
- SelectPanel
- 4. Future upgrades — the deferred list
- CLAUDE.md
- CanvasManager
- Known Issues
- Next session — the layer-compositing project, after the phase 8/9a checkpoint
- BrushBlendMode
- .row
- BrushShape
- GuidePath
- PaintSoftware - iPad Drawing and Animation App
- VectorEraserMode
- Usage Guide
- Multi-Session Protocol
- 6. Alpha masks
- command
- CutOutcome
- ManifestSkeleton
- 4. The render tree
- Tool
- VectorScratchRole
- Atomic
- ToolPanelsUITests
- Gesture
- CaseIterable
- parallel_test.sh
- CopiedCel
- SandwichPresentation
- cleanup_session.sh
- screenshot.sh
- .init
- .bytes
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 539 edges
2. `CGFloat` - 412 edges
3. `Effect` - 124 edges
4. `VectorCanvas` - 123 edges
5. `CanvasManager` - 123 edges
6. `layers` - 117 edges
7. `VectorSample` - 100 edges
8. `CanvasManager` - 100 edges
9. `Lattice` - 98 edges
10. `Coordinator` - 95 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (162 total, 12 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 1 - "CGFloat"
Cohesion: 0.04
Nodes (37): Sample, Void, CGFloat, ClosedFit, ShapeDetector, Bool, CGRect, Int (+29 more)

### Community 2 - "CanvasManager"
Cohesion: 0.05
Nodes (40): Identifiable, CanvasManager, .guideChips, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+32 more)

### Community 3 - ".manager"
Cohesion: 0.07
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 4 - "InterpolationRecipe"
Cohesion: 0.05
Nodes (38): Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+30 more)

### Community 5 - "CanvasManager"
Cohesion: 0.04
Nodes (49): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+41 more)

### Community 6 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 7 - ".transparentFormat"
Cohesion: 0.05
Nodes (45): RenderQuality, full, preview, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move (+37 more)

### Community 8 - "XCTestCase"
Cohesion: 0.07
Nodes (15): Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager (+7 more)

### Community 9 - "CompositorParityLogicTests"
Cohesion: 0.09
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 10 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (15): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+7 more)

### Community 11 - "ProjectBackupManager"
Cohesion: 0.09
Nodes (23): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+15 more)

### Community 12 - "VectorEraserHybridLogicTests"
Cohesion: 0.09
Nodes (23): CustomStringConvertible, UUID, ParityPixel, .description, ParityReport, .diagnostic, .isExact, ParityScenario (+15 more)

### Community 13 - "String"
Cohesion: 0.05
Nodes (47): CodingKeys, boundGroups, id, interval, samples, Kind, easeIn, easeInOut (+39 more)

### Community 14 - "Codable"
Cohesion: 0.05
Nodes (49): Codable, Kind, folder, layer, CodingKeys, amount, angleDegrees, brightness (+41 more)

### Community 15 - "CGPoint"
Cohesion: 0.09
Nodes (14): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+6 more)

### Community 16 - "AlphaMask"
Cohesion: 0.09
Nodes (10): AlphaMask, .isActive, Bool, Int, MaskParityLogicTests, .side, Bool, CanvasManager (+2 more)

### Community 17 - "AnimationTimeline"
Cohesion: 0.05
Nodes (46): Gesture, FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID (+38 more)

### Community 18 - "layers"
Cohesion: 0.09
Nodes (14): .activeLayerIsVector, CanvasManager, Bool, CGSize, UIImage, .activeCelIsInBetween, .guideRefusal, .interpolationTarget (+6 more)

### Community 19 - "UIKit"
Cohesion: 0.06
Nodes (10): CoreGraphics, Darwin, Foundation, Notification.Name, AppVersion, .versionString, String, ThumbnailRenderer (+2 more)

### Community 20 - "PointCloudIndex"
Cohesion: 0.11
Nodes (17): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+9 more)

### Community 21 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (35): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+27 more)

### Community 22 - "Coordinator"
Cohesion: 0.07
Nodes (23): AppliedTool, CanvasView, Coordinator, .sandwichPresentation, CanvasManager, CGSize, Color, Context (+15 more)

### Community 23 - "EffectLayerLogicTests"
Cohesion: 0.13
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 24 - ".drawLine"
Cohesion: 0.12
Nodes (10): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, EraserAndPersistenceUITests (+2 more)

### Community 25 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (22): StrokeInput, TimeInterval, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas (+14 more)

### Community 26 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 27 - "Lattice"
Cohesion: 0.10
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 28 - "PaintUITestCase"
Cohesion: 0.10
Nodes (11): FillLiveAdjustUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests, TimelineGestureUITests (+3 more)

### Community 29 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 30 - "MetalFillEngine"
Cohesion: 0.09
Nodes (28): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool (+20 more)

### Community 31 - "CanvasManager"
Cohesion: 0.08
Nodes (21): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+13 more)

### Community 32 - "ProjectSaveLogicTests"
Cohesion: 0.13
Nodes (13): CanvasManager, MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set (+5 more)

### Community 33 - "SaveSnapshot"
Cohesion: 0.08
Nodes (30): BrushLibrary, .customBrushesDirectory, URL, CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary (+22 more)

### Community 34 - "VectorCanvas"
Cohesion: 0.09
Nodes (26): image, kind, Kind, fill, image, stroke, CGAffineTransform, CGContext (+18 more)

### Community 35 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+21 more)

### Community 36 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 37 - "VectorStroke"
Cohesion: 0.09
Nodes (30): CodableColor, .uiColor, DabLattice, .range, ElementData, fill, image, stroke (+22 more)

### Community 38 - "SandwichLogicTests"
Cohesion: 0.12
Nodes (6): Battery, SandwichLogicTests, CanvasManager, CGImage, Int, String

### Community 39 - "MaskSource"
Cohesion: 0.08
Nodes (27): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, Arity (+19 more)

### Community 40 - "Brush"
Cohesion: 0.14
Nodes (10): Brush, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser, Bool (+2 more)

### Community 41 - "VectorEraserLogicTests"
Cohesion: 0.13
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 42 - "PerfBaselineTests"
Cohesion: 0.17
Nodes (8): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 43 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 44 - "LayerHostView"
Cohesion: 0.08
Nodes (16): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, NSCoder, InterpolationPreviewKey, SandwichKey (+8 more)

### Community 45 - ".launchIntoEditor"
Cohesion: 0.18
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 46 - "StrokeSettingsPanel"
Cohesion: 0.08
Nodes (33): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+25 more)

### Community 47 - "View"
Cohesion: 0.13
Nodes (30): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel, .body (+22 more)

### Community 48 - "InterpolationEvaluator"
Cohesion: 0.11
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 49 - "ARAPLogicTests"
Cohesion: 0.14
Nodes (6): ARAPInterpolation, ARAPLogicTests, Int, StaticString, String, UInt

### Community 50 - "ProjectManifest"
Cohesion: 0.13
Nodes (23): LayerContentVersion, Cel, ObjectIdentifier, UUID, role, Decoder, ValueFill, CelManifest (+15 more)

### Community 51 - "ValueLayerLogicTests"
Cohesion: 0.14
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 52 - "InterpolationRenderLogicTests"
Cohesion: 0.17
Nodes (10): ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage, UUID (+2 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.10
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 54 - ".encode"
Cohesion: 0.16
Nodes (19): BlendMode, .shaderCode, CompositorMetalEngine, MetalCompositor, ScratchTexturePool, Bool, CGImage, Double (+11 more)

### Community 55 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 56 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 57 - "LayerStackCell"
Cohesion: 0.09
Nodes (11): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+3 more)

### Community 58 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 59 - "VectorSample"
Cohesion: 0.13
Nodes (14): Int64, VectorSample, .point, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool (+6 more)

### Community 60 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 61 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 62 - "Equatable"
Cohesion: 0.15
Nodes (23): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, CurvePoint, Curves (+15 more)

### Community 63 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 64 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 65 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 66 - ".coverage"
Cohesion: 0.14
Nodes (8): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8, UIImage

### Community 67 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 68 - "SwiftUI"
Cohesion: 0.09
Nodes (14): Combine, CodableColor, .color, Color, .codable, CodableColor, .interpolateButton, InterpolatePanel (+6 more)

### Community 69 - "CodingKeys"
Cohesion: 0.08
Nodes (26): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+18 more)

### Community 70 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 72 - "RasterVectorParityLogicTests"
Cohesion: 0.14
Nodes (17): Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave, .label (+9 more)

### Community 73 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 74 - "CodingKey"
Cohesion: 0.08
Nodes (24): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+16 more)

### Community 75 - ".group"
Cohesion: 0.18
Nodes (6): Group, MotionGrouping, Options, Int, Set, groups

### Community 76 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 77 - "Effect"
Cohesion: 0.11
Nodes (12): UInt8, Effect, .displayName, .kind, .kindCode, .params, .passes, .reshapesCoverage (+4 more)

### Community 78 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 79 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 80 - ".stampStroke"
Cohesion: 0.19
Nodes (9): BrushStamper, DabRNG, DiscardedDabTarget, Bool, CGBlendMode, ClosedRange, Double, UIColor (+1 more)

### Community 81 - "Compositor.swift"
Cohesion: 0.19
Nodes (19): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+11 more)

### Community 83 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 84 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 85 - "ActionsMenu"
Cohesion: 0.12
Nodes (17): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+9 more)

### Community 86 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 87 - "LayerRowModel"
Cohesion: 0.14
Nodes (15): Kind, compositorNode, group, layer, LayerRowModel, .folderID, .isFolder, .maskSource (+7 more)

### Community 88 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

### Community 89 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 90 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 91 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 92 - ".arched"
Cohesion: 0.23
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 93 - ".renderSources"
Cohesion: 0.22
Nodes (11): CanvasManager, LayerRenderSource, RenderBackground, SandwichRequests, Bool, CGImage, CGSize, Int (+3 more)

### Community 94 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 95 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 96 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 97 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 98 - "BackupManagerLogicTests"
Cohesion: 0.21
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 99 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 100 - "BrushDynamics"
Cohesion: 0.18
Nodes (5): BrushDynamics, BrushGrain, Bool, Double, UUID

### Community 101 - "StructureSnapshot"
Cohesion: 0.18
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 102 - "TimedSample"
Cohesion: 0.17
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 103 - "RenderNode"
Cohesion: 0.16
Nodes (11): Content, leaf, node, RenderNode, .enclosesABlend, .ignoringVisibility, .leafLayerIndices, .needsOwnBuffer (+3 more)

### Community 104 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 105 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 106 - "RenderRequest"
Cohesion: 0.34
Nodes (9): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, RenderRequest (+1 more)

### Community 107 - "Layer"
Cohesion: 0.12
Nodes (16): Layer, .compositingEffect, .hasNoDrawingSurface, .isFillReference, .valueFill, BlendMode, Bool, Cel (+8 more)

### Community 108 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 109 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 110 - "Layer Compositing"
Cohesion: 0.12
Nodes (16): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 5.1 GPU, via Metal, 5.2 The sandwich, 5.3 Performance (+8 more)

### Community 111 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 112 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 114 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 115 - "CompositorRole"
Cohesion: 0.13
Nodes (11): K, KeyedDecodingContainer, CodingKeys, kind, mixMode, op, CompositorRole, node (+3 more)

### Community 116 - "Coordinator"
Cohesion: 0.26
Nodes (8): NSObject, Coordinator, CanvasManager, Int, Set, UIView, UUID, UITableViewDiffableDataSource

### Community 117 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 118 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 119 - "LayerStackListView"
Cohesion: 0.16
Nodes (9): IndexPath, .body, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView (+1 more)

### Community 120 - "SpacingChart"
Cohesion: 0.19
Nodes (4): SpacingChart, .curve, .draggable, stops

### Community 121 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 122 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (7): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 123 - "TransformOverlaySupport.swift"
Cohesion: 0.18
Nodes (10): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+2 more)

### Community 124 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 125 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 126 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 127 - "CLAUDE.md"
Cohesion: 0.24
Nodes (5): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands, Session Log

### Community 128 - "CanvasManager"
Cohesion: 0.22
Nodes (8): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage

### Community 129 - "Known Issues"
Cohesion: 0.20
Nodes (10): A green backend-parity test does not prove both backends ran (2026-08-15), Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22) (+2 more)

### Community 130 - "Next session — the layer-compositing project, after the phase 8/9a checkpoint"
Cohesion: 0.20
Nodes (8): Before you run out of context, If you delegate, Machine and test-run discipline — each of these cost a cycle, Next session — the layer-compositing project, after the phase 8/9a checkpoint, Open with the product owner — do not decide these alone, The hazard this project keeps producing, in five different disguises, Three things carried forward as UNPROVEN — check before you trust them, What is actually left

### Community 131 - "BrushBlendMode"
Cohesion: 0.20
Nodes (9): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+1 more)

### Community 132 - ".row"
Cohesion: 0.29
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 133 - "BrushShape"
Cohesion: 0.22
Nodes (9): BrushShape, custom, .displayName, hardRound, .id, pen, pencil, softRound (+1 more)

### Community 134 - "GuidePath"
Cohesion: 0.31
Nodes (4): GuidePath, .end, .start, TimeInterval

### Community 135 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 136 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 137 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 138 - "Multi-Session Protocol"
Cohesion: 0.29
Nodes (7): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Why the full run is 26 minutes when the work is only ~9

### Community 139 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 140 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 141 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 142 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 143 - "4. The render tree"
Cohesion: 0.33
Nodes (6): 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes, 4.4 Effects are both a layer and a node, 4.5 Value layers, 4. The render tree

### Community 144 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 145 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 146 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 148 - "Gesture"
Cohesion: 0.33
Nodes (6): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut

### Community 149 - "CaseIterable"
Cohesion: 0.40
Nodes (5): CaseIterable, Kind, line, oval, rectangle

### Community 150 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 151 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 152 - "SandwichPresentation"
Cohesion: 0.50
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

## Knowledge Gaps
- **654 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+649 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `CanvasManager`, `CanvasManager`, `InterpolationRecipe`, `CanvasManager`, `GuidePath`, `.transparentFormat`, `Coordinator`, `CompositorParityLogicTests`, `StrokeGeometryLogicTests`, `VectorEraserHybridLogicTests`, `String`, `CGPoint`, `AnimationTimeline`, `layers`, `PointCloudIndex`, `Coordinator`, `EffectLayerLogicTests`, `StrokeCanvasView`, `Lattice`, `PaintUITestCase`, `.apply`, `CanvasManager`, `ProjectSaveLogicTests`, `VectorCanvas`, `ShapeOverlayView`, `BrushEngineLogicTests`, `VectorStroke`, `SandwichLogicTests`, `Brush`, `VectorEraserLogicTests`, `PerfBaselineTests`, `LayerHostView`, `.launchIntoEditor`, `StrokeSettingsPanel`, `InterpolationEvaluator`, `ARAPLogicTests`, `InterpolationRenderLogicTests`, `DeformFactorization`, `RasterLayerTexture`, `LayerStackCell`, `VectorSample`, `GuideOverlayView`, `.coverage`, `InterpolationGuideLogicTests`, `XCUIApplication`, `.group`, `.stampStroke`, `.indices`, `CanvasManager`, `ActionsMenu`, `ObjectTransformOverlayView`, `.arched`, `SandwichCompositingUITests`, `CodingKeys`, `InterpolationEngineDiagnosticsLogicTests`, `BrushDynamics`, `TimedSample`, `InterpolateBar`, `DrawingView`, `RenderRequest`, `DabTarget`, `SideToolbar`, `Coordinator`, `LayerStackListView`, `SpacingChart`, `TransformOverlaySupport.swift`, `StrokeStabilizer`?**
  _High betweenness centrality (0.267) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `CanvasManager`, `CGFloat`, `CanvasManager`, `.manager`, `InterpolationRecipe`, `CanvasManager`, `GuidePath`, `.transparentFormat`, `Coordinator`, `cels`, `StrokeGeometryLogicTests`, `VectorEraserHybridLogicTests`, `AlphaMask`, `AnimationTimeline`, `layers`, `PointCloudIndex`, `ColorPickerPanel`, `Coordinator`, `Gesture`, `StrokeCanvasView`, `Lattice`, `CanvasManager`, `ProjectSaveLogicTests`, `VectorCanvas`, `ShapeOverlayView`, `BrushEngineLogicTests`, `VectorStroke`, `Brush`, `VectorEraserLogicTests`, `PerfBaselineTests`, `InterpolationEvaluator`, `ARAPLogicTests`, `InterpolationRenderLogicTests`, `DeformFactorization`, `RasterLayerTexture`, `VectorSample`, `GuideOverlayView`, `.coverage`, `InterpolationGuideLogicTests`, `RasterVectorParityLogicTests`, `.group`, `FloatingPieceOverlayView`, `.stampStroke`, `.indices`, `ObjectTransformOverlayView`, `SelectionOverlayView`, `.arched`, `InterpolationEngineDiagnosticsLogicTests`, `BrushDynamics`, `TimedSample`, `DabTarget`, `.manager`, `LayerStackListView.Coordinator`, `TransformOverlaySupport.swift`, `StrokeStabilizer`?**
  _High betweenness centrality (0.162) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `cels`, `CGFloat`, `.manager`, `InterpolationRecipe`, `.transparentFormat`, `CompositorParityLogicTests`, `StrokeGeometryLogicTests`, `VectorEraserHybridLogicTests`, `CGPoint`, `AlphaMask`, `UIKit`, `EffectLayerLogicTests`, `EffectMultiPassLogicTests`, `PaintUITestCase`, `ProjectSaveLogicTests`, `BrushEngineLogicTests`, `SandwichLogicTests`, `VectorEraserLogicTests`, `PerfBaselineTests`, `ARAPLogicTests`, `ValueLayerLogicTests`, `InterpolationRenderLogicTests`, `PlaybackBoundsCharacterizationTests`, `EffectParityLogicTests`, `InterpolationGuideLogicTests`, `RasterVectorParityLogicTests`, `MaskGuardLogicTests`, `BlockDragCharacterizationTests`, `BackupManagerLogicTests`, `InterpolationEngineDiagnosticsLogicTests`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._