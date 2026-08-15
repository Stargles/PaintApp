# Graph Report - PaintApp-valuelayer  (2026-08-15)

## Corpus Check
- 169 files · ~423,272 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4860 nodes · 15061 edges · 161 communities (151 shown, 10 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1617 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2ce64b67`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- cels
- CGFloat
- VectorCanvas
- XCTestCase
- CGPoint
- Lattice
- AlphaMask
- .manager
- Coordinator
- VectorEraserHybridLogicTests
- CompositorParityLogicTests
- layers
- Brush
- ProjectBackupManager
- PointCloudIndex
- UIKit
- CanvasManager
- .setBakedContent
- .stampStroke
- ColorPickerPanel
- MetalFillEngine
- CodingKeys
- Coordinator
- StrokeCanvasView
- ShapeOverlayView
- SandwichLogicTests
- VectorEraserLogicTests
- AnimationTimeline
- .withStructureUndo
- .apply
- BrushEngineLogicTests
- Effect
- EffectMultiPassLogicTests
- Codable
- ARAPLogicTests
- SaveSnapshot
- ProjectSaveLogicTests
- PerfBaselineTests
- ValueLayerLogicTests
- CanvasManager
- InterpolationRenderLogicTests
- CanvasManager
- RasterLayerTexture
- View
- .evaluate
- Layer
- agent
- .encode
- GuideOverlayView
- MaskSource
- LayerStackCell
- InterpolationModelLogicTests
- ProjectManifest
- FolderOptionsPanel
- PlaybackBoundsCharacterizationTests
- StrokeSettingsPanel
- Composite.metal
- DeformFactorization
- StrokeSpatialIndex
- BlendMode
- FillParams
- CodingKey
- LayerHostView
- TouchCountRecognizer
- .arched
- FloatingPieceOverlayView
- .activeCelIndex
- CanvasManager
- InterpolationGuideLogicTests
- EffectParityLogicTests
- CodingKeys
- BackupManagerLogicTests
- ActivePanel
- .group
- .transparentFormat
- SwiftUI
- Compositor.swift
- .indices
- CanvasManager
- GuideStroke
- ContentView
- RenderRequest
- ObjectTransformOverlayView
- SelectionOverlayView
- PerfMonitor
- read
- CompositorOp
- .makeUIView
- LayerRowModel
- BlockDragCharacterizationTests
- CodingKeys
- StructureSnapshot
- BrushSettingsPanel
- InterpolationRefusal
- InterpolateBar
- InterpolationEngineDiagnosticsLogicTests
- DrawingView
- EffectParams
- .draw
- Kind
- TimedSample
- LayerStackRow
- RasterizeKey
- CanvasSizePickerView
- Layer Compositing
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- CompositorRole
- Coordinator
- bash
- SpacingChart
- UndoHistory
- .refreshUndoRedoState
- CanvasHostView
- CGContextDabTarget
- LayerStackListView
- Cel
- MotionGroup
- StrokeStabilizer
- RenderNode
- 4. Future upgrades — the deferred list
- CLAUDE.md
- GuidePath
- ActionsMenu
- Known Issues
- Next session — the layer-compositing project, after the phase 8/9a checkpoint
- GradientStop
- LayerStackListView.Coordinator
- TransformMode
- .row
- TransformOverlaySupport.swift
- PaintSoftware - iPad Drawing and Animation App
- SelectionMode
- Usage Guide
- Multi-Session Protocol
- 6. Alpha masks
- command
- CutOutcome
- ManifestSkeleton
- 4. The render tree
- .warped
- ProjectStore.swift
- VectorScratchRole
- ProjectVersionsView
- Atomic
- parallel_test.sh
- Corner
- Edge
- FillAxis
- AppVersion
- SandwichPresentation
- Kind
- cleanup_session.sh
- screenshot.sh
- .init
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 539 edges
2. `CGFloat` - 412 edges
3. `VectorCanvas` - 123 edges
4. `CanvasManager` - 123 edges
5. `layers` - 117 edges
6. `Effect` - 110 edges
7. `VectorSample` - 100 edges
8. `CanvasManager` - 100 edges
9. `Lattice` - 98 edges
10. `Coordinator` - 95 edges

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

## Communities (161 total, 10 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.05
Nodes (30): FillUITests, LayerUITests, .crossing, Bool, CGVector, Int, String, TimeInterval (+22 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 2 - "CGFloat"
Cohesion: 0.05
Nodes (24): CGFloat, VectorSample, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect (+16 more)

### Community 3 - "VectorCanvas"
Cohesion: 0.05
Nodes (60): Identifiable, CodableColor, .uiColor, image, kind, DabLattice, .range, ElementData (+52 more)

### Community 4 - "XCTestCase"
Cohesion: 0.05
Nodes (26): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGSize, UIColor, UIImage, Layer (+18 more)

### Community 5 - "CGPoint"
Cohesion: 0.06
Nodes (32): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+24 more)

### Community 6 - "Lattice"
Cohesion: 0.06
Nodes (28): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+20 more)

### Community 7 - "AlphaMask"
Cohesion: 0.06
Nodes (27): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8, AlphaMask (+19 more)

### Community 8 - ".manager"
Cohesion: 0.07
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 9 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 10 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (39): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+31 more)

### Community 11 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 12 - "layers"
Cohesion: 0.07
Nodes (28): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+20 more)

### Community 13 - "Brush"
Cohesion: 0.04
Nodes (50): CaseIterable, Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+42 more)

### Community 14 - "ProjectBackupManager"
Cohesion: 0.10
Nodes (23): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+15 more)

### Community 15 - "PointCloudIndex"
Cohesion: 0.11
Nodes (17): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+9 more)

### Community 16 - "UIKit"
Cohesion: 0.06
Nodes (8): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, ThumbnailRenderer, UIKit, XCTest

### Community 17 - "CanvasManager"
Cohesion: 0.06
Nodes (28): CanvasManager, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex (+20 more)

### Community 18 - ".setBakedContent"
Cohesion: 0.14
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 19 - ".stampStroke"
Cohesion: 0.07
Nodes (26): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+18 more)

### Community 20 - "ColorPickerPanel"
Cohesion: 0.08
Nodes (32): Palette, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID, Bool, Color (+24 more)

### Community 21 - "MetalFillEngine"
Cohesion: 0.08
Nodes (30): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool (+22 more)

### Community 22 - "CodingKeys"
Cohesion: 0.06
Nodes (36): CodingKeys, amount, angleDegrees, brightness, contrast, gamma, hueDegrees, inputBlack (+28 more)

### Community 23 - "Coordinator"
Cohesion: 0.08
Nodes (23): Coordinator, .sandwichPresentation, InterpolationPreviewKey, SandwichKey, CanvasManager, CGImage, CGSize, Date (+15 more)

### Community 24 - "StrokeCanvasView"
Cohesion: 0.11
Nodes (22): StrokeInput, TimeInterval, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas (+14 more)

### Community 25 - "ShapeOverlayView"
Cohesion: 0.07
Nodes (30): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+22 more)

### Community 26 - "SandwichLogicTests"
Cohesion: 0.12
Nodes (6): Battery, SandwichLogicTests, CanvasManager, CGImage, Int, String

### Community 27 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 28 - "AnimationTimeline"
Cohesion: 0.07
Nodes (34): Gesture, Content, leaf, node, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight (+26 more)

### Community 29 - ".withStructureUndo"
Cohesion: 0.08
Nodes (23): BlendMode, Double, UUID, Void, CanvasManager, .activeViewName, Int, String (+15 more)

### Community 30 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 31 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 32 - "Effect"
Cohesion: 0.10
Nodes (28): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, params, Curves, Effect (+20 more)

### Community 33 - "EffectMultiPassLogicTests"
Cohesion: 0.14
Nodes (7): .weights, EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 34 - "Codable"
Cohesion: 0.12
Nodes (19): Codable, CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, Kind, easeIn (+11 more)

### Community 35 - "ARAPLogicTests"
Cohesion: 0.12
Nodes (9): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, Int, StaticString, String (+1 more)

### Community 36 - "SaveSnapshot"
Cohesion: 0.10
Nodes (26): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+18 more)

### Community 37 - "ProjectSaveLogicTests"
Cohesion: 0.16
Nodes (10): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+2 more)

### Community 38 - "PerfBaselineTests"
Cohesion: 0.17
Nodes (8): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 39 - "ValueLayerLogicTests"
Cohesion: 0.12
Nodes (9): PaletteColor, .color, CanvasManager, CGImage, Int, UIColor, UIImage, ValueLayerLogicTests (+1 more)

### Community 40 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 41 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 42 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+9 more)

### Community 43 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 44 - "View"
Cohesion: 0.09
Nodes (26): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+18 more)

### Community 45 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, GuideSet, .isEmpty, Bool, Direction, backward, forward (+14 more)

### Community 46 - "Layer"
Cohesion: 0.07
Nodes (28): Hashable, LayerContentVersion, Cel, ObjectIdentifier, UUID, CelLocation, Layer, .compositingEffect (+20 more)

### Community 47 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 48 - ".encode"
Cohesion: 0.17
Nodes (18): BlendMode, .shaderCode, CompositorMetalEngine, MetalCompositor, ScratchTexturePool, Bool, CGImage, Double (+10 more)

### Community 49 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): points, Editing, handles, none, spacing, Grip, Guide, GuideOverlayView (+9 more)

### Community 50 - "MaskSource"
Cohesion: 0.11
Nodes (16): Kind, folder, layer, MaskSource, folder, .id, layer, Decoder (+8 more)

### Community 51 - "LayerStackCell"
Cohesion: 0.09
Nodes (11): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+3 more)

### Community 52 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 53 - "ProjectManifest"
Cohesion: 0.15
Nodes (22): role, LayerKind, compositing, raster, value, vector, CelManifest, CodableColor (+14 more)

### Community 54 - "FolderOptionsPanel"
Cohesion: 0.13
Nodes (27): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel, .body (+19 more)

### Community 55 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 56 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker (+18 more)

### Community 57 - "Composite.metal"
Cohesion: 0.21
Nodes (31): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+23 more)

### Community 58 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 59 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 60 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 61 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 62 - "CodingKey"
Cohesion: 0.07
Nodes (29): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+21 more)

### Community 63 - "LayerHostView"
Cohesion: 0.12
Nodes (8): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, NSCoder, Bool, UIGestureRecognizer

### Community 64 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 66 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (13): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+5 more)

### Community 67 - ".activeCelIndex"
Cohesion: 0.17
Nodes (7): .interpolationTarget, CanvasManager, Bool, Int, CopiedCel, Int, UIImage

### Community 68 - "CanvasManager"
Cohesion: 0.14
Nodes (11): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+3 more)

### Community 69 - "InterpolationGuideLogicTests"
Cohesion: 0.19
Nodes (3): InterpolationGuideLogicTests, CanvasManager, VectorStroke

### Community 70 - "EffectParityLogicTests"
Cohesion: 0.20
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 71 - "CodingKeys"
Cohesion: 0.08
Nodes (26): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+18 more)

### Community 72 - "BackupManagerLogicTests"
Cohesion: 0.17
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 73 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 74 - ".group"
Cohesion: 0.18
Nodes (6): Group, MotionGrouping, Options, Int, Set, groups

### Community 75 - ".transparentFormat"
Cohesion: 0.25
Nodes (9): PixelOps, CGPath, CGRect, CGSize, Color, Double, UIColor, UIImage (+1 more)

### Community 76 - "SwiftUI"
Cohesion: 0.11
Nodes (9): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, PhotosUI (+1 more)

### Community 77 - "Compositor.swift"
Cohesion: 0.19
Nodes (19): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+11 more)

### Community 79 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 80 - "GuideStroke"
Cohesion: 0.14
Nodes (14): CodingKeys, boundGroups, id, interval, samples, GuideRole, both, timing (+6 more)

### Community 81 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 82 - "RenderRequest"
Cohesion: 0.23
Nodes (12): CanvasManager, LayerRenderSource, RenderBackground, RenderRequest, SandwichRequests, Bool, CGImage, CGSize (+4 more)

### Community 83 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

### Community 84 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 85 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 86 - "read"
Cohesion: 0.36
Nodes (20): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+12 more)

### Community 87 - "CompositorOp"
Cohesion: 0.13
Nodes (15): Arity, fixed, variadic, Array, .leafLayerIndices, .needsCompositorOnCanvas, CompositorOp, .arity (+7 more)

### Community 88 - ".makeUIView"
Cohesion: 0.13
Nodes (8): AppliedTool, CanvasView, Color, Context, Coordinator, Double, LayerTransform, UIImageView

### Community 89 - "LayerRowModel"
Cohesion: 0.15
Nodes (12): LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, Bool, Double, String (+4 more)

### Community 90 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 91 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 92 - "StructureSnapshot"
Cohesion: 0.16
Nodes (6): CanvasManager, StructureSnapshot, Int, Layer, String, guideStrokes

### Community 93 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 94 - "InterpolationRefusal"
Cohesion: 0.15
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 95 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 96 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.30
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 97 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 98 - "EffectParams"
Cohesion: 0.12
Nodes (17): EffectParams, amount, brightness, contrast, hueTurns, intensity, isMonochrome, levels (+9 more)

### Community 99 - ".draw"
Cohesion: 0.32
Nodes (8): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 100 - "Kind"
Cohesion: 0.12
Nodes (17): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+9 more)

### Community 101 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 102 - "LayerStackRow"
Cohesion: 0.12
Nodes (15): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+7 more)

### Community 103 - "RasterizeKey"
Cohesion: 0.18
Nodes (9): IntPoint, RasterizeCache, RasterizeKey, Bool, Cel, Int, ObjectIdentifier, UInt8 (+1 more)

### Community 104 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 105 - "Layer Compositing"
Cohesion: 0.12
Nodes (16): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 5.1 GPU, via Metal, 5.2 The sandwich, 5.3 Performance (+8 more)

### Community 106 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 107 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 108 - "CompositorRole"
Cohesion: 0.13
Nodes (11): K, KeyedDecodingContainer, CodingKeys, kind, mixMode, op, CompositorRole, node (+3 more)

### Community 109 - "Coordinator"
Cohesion: 0.26
Nodes (8): NSObject, Coordinator, CanvasManager, Int, Set, UIView, UUID, UITableViewDiffableDataSource

### Community 110 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 111 - "SpacingChart"
Cohesion: 0.17
Nodes (4): SpacingChart, .curve, .draggable, stops

### Community 112 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 113 - ".refreshUndoRedoState"
Cohesion: 0.22
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 114 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 115 - "CGContextDabTarget"
Cohesion: 0.27
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 116 - "LayerStackListView"
Cohesion: 0.18
Nodes (8): IndexPath, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView, UIViewRepresentable

### Community 117 - "Cel"
Cohesion: 0.27
Nodes (8): CGSize, Layer, String, Cel, .endFrame, Int, UIImage, UUID

### Community 118 - "MotionGroup"
Cohesion: 0.21
Nodes (10): GroupRegistration, Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor (+2 more)

### Community 119 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 120 - "RenderNode"
Cohesion: 0.21
Nodes (8): RenderNode, .enclosesABlend, .ignoringVisibility, .leafLayerIndices, .needsOwnBuffer, .opIsBlending, Double, BlendMode

### Community 121 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 122 - "CLAUDE.md"
Cohesion: 0.24
Nodes (5): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands, Session Log

### Community 123 - "GuidePath"
Cohesion: 0.25
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 124 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 125 - "Known Issues"
Cohesion: 0.20
Nodes (10): A green backend-parity test does not prove both backends ran (2026-08-15), Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22) (+2 more)

### Community 126 - "Next session — the layer-compositing project, after the phase 8/9a checkpoint"
Cohesion: 0.20
Nodes (8): Before you run out of context, If you delegate, Machine and test-run discipline — each of these cost a cycle, Next session — the layer-compositing project, after the phase 8/9a checkpoint, Open with the product owner — do not decide these alone, The hazard this project keeps producing, in five different disguises, Three things carried forward as UNPROVEN — check before you trust them, What is actually left

### Community 127 - "GradientStop"
Cohesion: 0.27
Nodes (6): value, levels, .lookupTable, GradientStop, CodableColor, UInt8

### Community 128 - "LayerStackListView.Coordinator"
Cohesion: 0.29
Nodes (6): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 129 - "TransformMode"
Cohesion: 0.22
Nodes (8): TransformMode, .displayName, distort, freeform, .id, .isImplemented, uniform, warp

### Community 130 - ".row"
Cohesion: 0.28
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 131 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 132 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 133 - "SelectionMode"
Cohesion: 0.25
Nodes (7): SelectionMode, automatic, .displayName, .id, lasso, rectangle, .systemImage

### Community 134 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 135 - "Multi-Session Protocol"
Cohesion: 0.29
Nodes (7): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Why the full run is 26 minutes when the work is only ~9

### Community 136 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 137 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 138 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 139 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 140 - "4. The render tree"
Cohesion: 0.33
Nodes (6): 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes, 4.4 Effects are both a layer and a node, 4.5 Value layers, 4. The render tree

### Community 142 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 143 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 144 - "ProjectVersionsView"
Cohesion: 0.47
Nodes (4): ProjectVersionsView, RecentlyDeletedView, .body, Void

### Community 145 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 146 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 147 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 148 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 149 - "FillAxis"
Cohesion: 0.50
Nodes (4): FillAxis, edgeOverlap, gapClosing, threshold

### Community 150 - "AppVersion"
Cohesion: 0.50
Nodes (3): AppVersion, .versionString, String

### Community 151 - "SandwichPresentation"
Cohesion: 0.50
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 152 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

## Knowledge Gaps
- **648 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+643 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `cels`, `VectorCanvas`, `XCTestCase`, `CGPoint`, `Lattice`, `TransformOverlaySupport.swift`, `AlphaMask`, `Coordinator`, `VectorEraserHybridLogicTests`, `CompositorParityLogicTests`, `layers`, `Brush`, `.warped`, `PointCloudIndex`, `UIKit`, `CanvasManager`, `.setBakedContent`, `.stampStroke`, `Coordinator`, `StrokeCanvasView`, `ShapeOverlayView`, `SandwichLogicTests`, `VectorEraserLogicTests`, `AnimationTimeline`, `.apply`, `BrushEngineLogicTests`, `Codable`, `ARAPLogicTests`, `ProjectSaveLogicTests`, `PerfBaselineTests`, `InterpolationRenderLogicTests`, `CanvasManager`, `RasterLayerTexture`, `.evaluate`, `GuideOverlayView`, `LayerStackCell`, `InterpolationModelLogicTests`, `StrokeSettingsPanel`, `DeformFactorization`, `StrokeSpatialIndex`, `LayerHostView`, `.arched`, `FloatingPieceOverlayView`, `CanvasManager`, `InterpolationGuideLogicTests`, `.group`, `.transparentFormat`, `.indices`, `CanvasManager`, `ObjectTransformOverlayView`, `.makeUIView`, `CodingKeys`, `InterpolateBar`, `InterpolationEngineDiagnosticsLogicTests`, `DrawingView`, `.draw`, `TimedSample`, `SideToolbar`, `Coordinator`, `SpacingChart`, `.refreshUndoRedoState`, `CGContextDabTarget`, `LayerStackListView`, `StrokeStabilizer`, `GuidePath`, `ActionsMenu`?**
  _High betweenness centrality (0.305) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `LayerStackListView.Coordinator`, `cels`, `CGFloat`, `VectorCanvas`, `TransformOverlaySupport.swift`, `Lattice`, `AlphaMask`, `.manager`, `Coordinator`, `VectorEraserHybridLogicTests`, `layers`, `Brush`, `.warped`, `PointCloudIndex`, `UIKit`, `CanvasManager`, `.stampStroke`, `ColorPickerPanel`, `Coordinator`, `StrokeCanvasView`, `ShapeOverlayView`, `VectorEraserLogicTests`, `AnimationTimeline`, `BrushEngineLogicTests`, `Codable`, `ARAPLogicTests`, `ProjectSaveLogicTests`, `PerfBaselineTests`, `InterpolationRenderLogicTests`, `CanvasManager`, `RasterLayerTexture`, `.evaluate`, `GuideOverlayView`, `InterpolationModelLogicTests`, `DeformFactorization`, `StrokeSpatialIndex`, `LayerHostView`, `.arched`, `FloatingPieceOverlayView`, `.activeCelIndex`, `CanvasManager`, `InterpolationGuideLogicTests`, `.group`, `.transparentFormat`, `.indices`, `ObjectTransformOverlayView`, `SelectionOverlayView`, `.makeUIView`, `InterpolationEngineDiagnosticsLogicTests`, `TimedSample`, `RasterizeKey`, `.refreshUndoRedoState`, `CGContextDabTarget`, `StrokeStabilizer`, `GuidePath`?**
  _High betweenness centrality (0.160) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `TransformMode`, `CGFloat`, `CGPoint`, `SelectionMode`, `Brush`, `.stampStroke`, `MetalFillEngine`, `FillAxis`, `.withStructureUndo`, `Codable`, `CanvasManager`, `RasterLayerTexture`, `Layer`, `MaskSource`, `ProjectManifest`, `.activeCelIndex`, `CanvasManager`, `SwiftUI`, `GuideStroke`, `PerfMonitor`, `CompositorOp`, `StructureSnapshot`, `TimedSample`, `SpacingChart`, `UndoHistory`, `.refreshUndoRedoState`, `Cel`, `MotionGroup`?**
  _High betweenness centrality (0.083) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._