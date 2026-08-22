# Graph Report - PaintApp-collar  (2026-08-22)

## Corpus Check
- 242 files · ~779,515 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 7267 nodes · 22178 edges · 224 communities (209 shown, 15 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2211 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `de471ee6`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CGPoint
- cels
- CanvasManager
- InterpolationGuideLogicTests
- CanvasManager
- InterpolationRecipe
- VectorCanvas
- LassoFillLogicTests
- .manager
- VectorEraserHybridLogicTests
- Lattice
- ProjectBackupManager
- AlphaMask
- BrushBlendMode
- Coordinator
- .solidImage
- StrokeGeometryLogicTests
- HistoryActionLabel
- PerfBaselineTests
- String
- StrokeCanvasView
- VectorCanvasData
- TextFrame
- AnimationTimeline
- Codable
- ProjectStore
- UIKit
- SandwichLogicTests
- VectorEraserLogicTests
- ProjectSaveLogicTests
- .setBakedContent
- StrokeGestureRecognizer
- StrokeGeometry
- ProjectManifest
- ShapeDetector
- ARAPLogicTests
- CompositorMetalEngine
- LayerTreeCharacterizationTests
- SelectionOverlayView
- EffectMultiPassLogicTests
- .refreshUndoRedoState
- ShapeOverlayView
- .drawLine
- Effect
- .launchIntoEditor
- BrushEngineLogicTests
- CanvasManager
- CodingKeys
- layers
- TextTransformLogicTests
- CanvasManager
- RenderTreeCharacterizationTests
- CanvasManager
- Fill.metal
- View
- TextOverlayView
- PaintUITestCase
- TextBakeCharacterizationTests
- DeformFactorization
- RasterLayerTexture
- InterpolationRenderLogicTests
- LayerStackCell
- LayerContentVersion
- FontResolveLogicTests
- .rows
- XCTestCase
- FillBoundaryLogicTests
- VectorCanvasDataLogicTests
- RenderNode
- VectorEraserMode
- CanvasNotice
- agent
- ActionRecorder
- EyedropperLogicTests
- GalleryOpenState
- PlaybackBoundsCharacterizationTests
- SaveDamageGateLogicTests
- Composite.metal
- Typography
- .transparentFormat
- GuideOverlayView
- Binding
- ColorPickerPanel
- InterpolationEvaluator
- StrokeSpatialIndex
- MetalFillSession
- MaskSource
- BlendMode
- ObjectTransformOverlayView
- OnionSkinSettings
- ContentView
- TextTransformOverlayView
- .apply
- FloatingPieceOverlayView
- Brush
- TimelineRowView
- VectorSample
- InterpolationModelLogicTests
- DrawingView
- TextHitTestLogicTests
- ProjectLoadDamage
- SpacingChart
- EffectParityLogicTests
- Known Issues
- EffectPipelines
- VectorTransformUndoLogicTests
- OnionSkinPanel
- ActivePanel
- .image
- .compositeSize
- FillGestureRestartLogicTests
- XCUIApplication
- WindowEventTap
- .rasterize
- VectorPreviewPlanLogicTests
- SwiftUI
- Layer Compositing
- Compositor.swift
- GuideRow
- CodingKeys
- Gesture
- .attach
- read
- BrushStamper
- PinchMergeGateLogicTests
- MaskGuardLogicTests
- CanvasManager
- CurveEditor
- UInt8
- 1. The decisions
- CodingKeys
- LayerRowModel
- CaseIterable
- OnionSkinLogicTests
- Coordinator
- CanvasTransformFreezeUITests
- EffectParams
- ShapeHoldClock
- Kind
- .makeUIView
- TextSettingsPanel
- SandwichCompositingUITests
- TimelineLayoutKeyLogicTests
- Recording
- RenderRequest
- CGFloat
- .reconcileLayers
- .lassoFill
- BlockDragCharacterizationTests
- InterpolationEngineDiagnosticsLogicTests
- PaintSoftware - iPad Drawing and Animation App
- 1. The decisions
- PerfMonitor
- .rasterize
- InterpolateBar
- CGContextDabTarget
- CanvasPresentation
- .backfillMissingThumbnails
- UndoHistory
- InterpolationRefusal
- CGRect
- CanvasPresentationLogicTests
- .performDrag
- Foundation
- StructureSnapshot
- ViewPreset
- CanvasSizePickerView
- TextRecipeCodableLogicTests
- SideToolbar
- MenuInterruptionUITests
- SelectionPersistenceLogicTests
- LayerStackListView.Coordinator
- bash
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- .sample
- CanvasHostView
- .relayout
- Performance
- TimelineLayoutKey
- TransformOverlaySupport.swift
- CLAUDE.md
- Lasso Fill — Specification
- SelectionOverlayLogicTests
- StrokeStabilizer
- SelectPanel
- Handle
- 4. Future upgrades — the deferred list
- Every dismissible presentation, and whether a stroke under it breaks
- Handoff — 2026-08-22
- .sampledColor
- Kind
- .frames
- Multi-Session Protocol
- .textureBudgetBytes
- CutOutcome
- .row
- TextRecipe
- Kind
- Edge
- command
- JSONValue
- ToolPanelsUITests
- ManifestSkeleton
- RecordingWriter
- MenuRequest
- CompositeProbe
- Atomic
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- parallel_test.sh
- Performance baseline
- TODO
- Kind
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- .init
- .bytes
- presentation-census.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 796 edges
2. `CGFloat` - 573 edges
3. `CanvasManager` - 170 edges
4. `VectorCanvas` - 159 edges
5. `Effect` - 149 edges
6. `layers` - 126 edges
7. `VectorSample` - 125 edges
8. `Coordinator` - 121 edges
9. `ShapeGeometry` - 109 edges
10. `CanvasManager` - 100 edges

## Surprising Connections (you probably didn't know these)
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `PerfBaselineTests` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (224 total, 15 thin omitted)

### Community 0 - "CGPoint"
Cohesion: 0.06
Nodes (29): CGPoint, .length, Int, Corner, bottomLeft, bottomRight, topLeft, topRight (+21 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (64): Never, Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+56 more)

### Community 3 - "InterpolationGuideLogicTests"
Cohesion: 0.07
Nodes (13): GuideHandles, GuideSet, .isEmpty, Bool, Int, TimedSample, .point, InterpolationGuideLogicTests (+5 more)

### Community 4 - "CanvasManager"
Cohesion: 0.06
Nodes (29): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+21 more)

### Community 5 - "InterpolationRecipe"
Cohesion: 0.10
Nodes (22): GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool, Decoder (+14 more)

### Community 6 - "VectorCanvas"
Cohesion: 0.07
Nodes (46): Identifiable, UUID, VectorTextElement, CodableColor, .uiColor, image, ImageRef, Kind (+38 more)

### Community 7 - "LassoFillLogicTests"
Cohesion: 0.17
Nodes (6): LassoFillLogicTests, .loopAroundEverything, CanvasManager, CGRect, TimeInterval, UIImage

### Community 8 - ".manager"
Cohesion: 0.07
Nodes (9): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool, CanvasManager (+1 more)

### Community 9 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (41): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+33 more)

### Community 10 - "Lattice"
Cohesion: 0.06
Nodes (28): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+20 more)

### Community 11 - "ProjectBackupManager"
Cohesion: 0.08
Nodes (27): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+19 more)

### Community 12 - "AlphaMask"
Cohesion: 0.08
Nodes (12): AlphaMask, .isActive, Bool, Decoder, Int, MaskParityLogicTests, .side, Bool (+4 more)

### Community 13 - "BrushBlendMode"
Cohesion: 0.07
Nodes (26): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+18 more)

### Community 14 - "Coordinator"
Cohesion: 0.06
Nodes (34): SandwichFullKey, Coordinator, .canvasContentScale, .isLassoFilling, .sandwichPresentation, InterpolationPreviewKey, OnionSkinKey, SandwichKey (+26 more)

### Community 15 - ".solidImage"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 16 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (6): samples, StrokeGeometryLogicTests, .ramp, StaticString, String, UInt

### Community 17 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 18 - "PerfBaselineTests"
Cohesion: 0.11
Nodes (8): PerfBaselineTests, Bool, CanvasManager, CGSize, Double, String, UInt64, VectorStroke

### Community 19 - "String"
Cohesion: 0.03
Nodes (75): CodingKey, Error, CodingKeys, activeCells, cellSize, cols, originX, originY (+67 more)

### Community 20 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (25): CAShapeLayer, StrokeInput, TimeInterval, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+17 more)

### Community 21 - "VectorCanvasData"
Cohesion: 0.09
Nodes (25): ElementData, fill, image, stroke, text, KindProbe, LossySlot, LossyValue (+17 more)

### Community 22 - "TextFrame"
Cohesion: 0.09
Nodes (21): Int, Basis, Corner, bottomLeft, bottomRight, topLeft, topRight, Mode (+13 more)

### Community 23 - "AnimationTimeline"
Cohesion: 0.04
Nodes (50): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+42 more)

### Community 24 - "Codable"
Cohesion: 0.06
Nodes (43): Codable, CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma (+35 more)

### Community 25 - "ProjectStore"
Cohesion: 0.09
Nodes (38): CFAbsoluteTime, CelContent, DecodedCel, DecodedCels, LayerContent, LoadProfile, .millisecondsPerCel, .thumbnailShare (+30 more)

### Community 26 - "UIKit"
Cohesion: 0.07
Nodes (8): CoreGraphics, CoreText, Darwin, TextMeasure, LayerTransform, simd, UIKit, XCTest

### Community 27 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 28 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (7): VectorEraser, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 29 - "ProjectSaveLogicTests"
Cohesion: 0.10
Nodes (14): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase (+6 more)

### Community 30 - ".setBakedContent"
Cohesion: 0.12
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 31 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 32 - "StrokeGeometry"
Cohesion: 0.13
Nodes (9): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+1 more)

### Community 33 - "ProjectManifest"
Cohesion: 0.06
Nodes (41): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+33 more)

### Community 34 - "ShapeDetector"
Cohesion: 0.23
Nodes (4): ClosedFit, ShapeDetector, Bool, CGRect

### Community 35 - "ARAPLogicTests"
Cohesion: 0.06
Nodes (28): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+20 more)

### Community 36 - "CompositorMetalEngine"
Cohesion: 0.09
Nodes (33): Admission, admitted, noHeadroom, overBudget, Attempt, image, unavailable, underPressure (+25 more)

### Community 37 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (7): Layer, UInt, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 38 - "SelectionOverlayView"
Cohesion: 0.09
Nodes (22): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, SelectionOverlayView, .isCapturingGestures (+14 more)

### Community 39 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 40 - ".refreshUndoRedoState"
Cohesion: 0.07
Nodes (18): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage (+10 more)

### Community 41 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 42 - ".drawLine"
Cohesion: 0.12
Nodes (10): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement (+2 more)

### Community 43 - "Effect"
Cohesion: 0.08
Nodes (35): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+27 more)

### Community 44 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, UndoAndLayerHistoryUITests

### Community 45 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 46 - "CanvasManager"
Cohesion: 0.07
Nodes (32): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+24 more)

### Community 47 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 48 - "layers"
Cohesion: 0.12
Nodes (16): .activeLayerIsVector, .activeCelIsInBetween, CanvasManager, Bool, Int, Cel, .endFrame, .isCertainlyBlank (+8 more)

### Community 49 - "TextTransformLogicTests"
Cohesion: 0.10
Nodes (11): TextFrameDrag, .clamped, Bool, CanvasManager, CGRect, CGSize, Int, StaticString (+3 more)

### Community 50 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 51 - "RenderTreeCharacterizationTests"
Cohesion: 0.14
Nodes (7): StaticString, String, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 52 - "CanvasManager"
Cohesion: 0.10
Nodes (22): CanvasManager, .fillEdgeOverlap, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel (+14 more)

### Community 53 - "Fill.metal"
Cohesion: 0.17
Nodes (41): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+33 more)

### Community 54 - "View"
Cohesion: 0.14
Nodes (29): View, .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex (+21 more)

### Community 55 - "TextOverlayView"
Cohesion: 0.09
Nodes (18): RenderKey, Bool, CGPath, CGRect, CGSize, NSCoder, Set, String (+10 more)

### Community 56 - "PaintUITestCase"
Cohesion: 0.13
Nodes (9): HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, SelectionAndMoveUITests, GalleryRecoveryUITests (+1 more)

### Community 57 - "TextBakeCharacterizationTests"
Cohesion: 0.17
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 58 - "DeformFactorization"
Cohesion: 0.07
Nodes (19): Accelerate, ARAPInterpolation, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization (+11 more)

### Community 59 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (14): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+6 more)

### Community 60 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (12): StrokeComposite, erase, paint, fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor (+4 more)

### Community 61 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+4 more)

### Community 62 - "LayerContentVersion"
Cohesion: 0.09
Nodes (25): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderResolution, full, half (+17 more)

### Community 63 - "FontResolveLogicTests"
Cohesion: 0.09
Nodes (23): FontFace, .descriptor, .id, FontFamilyGroup, .id, FontLibrary, FontProvider, FontResolution (+15 more)

### Community 64 - ".rows"
Cohesion: 0.11
Nodes (27): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+19 more)

### Community 65 - "XCTestCase"
Cohesion: 0.11
Nodes (11): CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor (+3 more)

### Community 66 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 67 - "VectorCanvasDataLogicTests"
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 68 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 69 - "VectorEraserMode"
Cohesion: 0.07
Nodes (24): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+16 more)

### Community 70 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 71 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 72 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 73 - "EyedropperLogicTests"
Cohesion: 0.09
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 74 - "GalleryOpenState"
Cohesion: 0.11
Nodes (17): GalleryOpenState, .isBusy, Bool, UUID, ProjectVersionsView, RecentlyDeletedView, .body, Void (+9 more)

### Community 75 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 76 - "SaveDamageGateLogicTests"
Cohesion: 0.16
Nodes (10): SaveDamageGateLogicTests, Any, CanvasManager, Data, StaticString, String, UInt, URL (+2 more)

### Community 77 - "Composite.metal"
Cohesion: 0.21
Nodes (31): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+23 more)

### Community 78 - "Typography"
Cohesion: 0.12
Nodes (18): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGRect (+10 more)

### Community 79 - ".transparentFormat"
Cohesion: 0.11
Nodes (23): Hashable, CelLocation, IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey (+15 more)

### Community 80 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 81 - "Binding"
Cohesion: 0.07
Nodes (39): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+31 more)

### Community 82 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+29 more)

### Community 83 - "InterpolationEvaluator"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, InterpolationEvaluator (+13 more)

### Community 84 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 85 - "MetalFillSession"
Cohesion: 0.19
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 86 - "MaskSource"
Cohesion: 0.15
Nodes (12): MaskSource, folder, .id, layer, Encoder, UUID, Void, CanvasManager (+4 more)

### Community 87 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 88 - "ObjectTransformOverlayView"
Cohesion: 0.04
Nodes (44): Handle, body, bottomLeft, bottomRight, .isCorner, .isDrawn, rotation, topLeft (+36 more)

### Community 89 - "OnionSkinSettings"
Cohesion: 0.17
Nodes (13): .gradientStops, OnionSkinOpacityRamp, OnionSkinSettings, Side, .id, next, previous, .step (+5 more)

### Community 90 - "ContentView"
Cohesion: 0.09
Nodes (18): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+10 more)

### Community 91 - "TextTransformOverlayView"
Cohesion: 0.12
Nodes (16): Bool, CALayer, CGRect, NSCoder, Set, UIEvent, UITouch, Void (+8 more)

### Community 92 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 93 - "FloatingPieceOverlayView"
Cohesion: 0.10
Nodes (19): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+11 more)

### Community 94 - "Brush"
Cohesion: 0.12
Nodes (9): Brush, Sweep, Bool, CGRect, ClosedRange, Double, Bool, Set (+1 more)

### Community 95 - "TimelineRowView"
Cohesion: 0.13
Nodes (17): Kind, cel, gap, Segment, Cel, Int, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 96 - "VectorSample"
Cohesion: 0.16
Nodes (6): VectorSample, VectorStroke, CountingDabTarget, StrokeSampleGateLogicTests, UInt64, Tremor

### Community 97 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 98 - "DrawingView"
Cohesion: 0.07
Nodes (23): ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void, DamagedSaveBanner (+15 more)

### Community 99 - "TextHitTestLogicTests"
Cohesion: 0.18
Nodes (6): Bool, CGAffineTransform, CGSize, String, VectorStroke, TextHitTestLogicTests

### Community 100 - "ProjectLoadDamage"
Cohesion: 0.13
Nodes (18): LayerDamage, .isEmpty, .itemPhrase, .total, ProjectLoadDamage, .isDamaged, .itemCount, .summary (+10 more)

### Community 101 - "SpacingChart"
Cohesion: 0.11
Nodes (10): GuidePath, .end, .start, SpacingChart, .curve, .draggable, CGVector, Range (+2 more)

### Community 102 - "EffectParityLogicTests"
Cohesion: 0.20
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 103 - "Known Issues"
Cohesion: 0.08
Nodes (26): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), Cleanup opportunities, Drawing on a vector layer at 4K was capped at ~19 fps by the live stroke preview — FIXED 2026-08-20, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicate rasterizes a vector layer, silently (2026-08-21) (+18 more)

### Community 104 - "EffectPipelines"
Cohesion: 0.13
Nodes (17): Metal, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue (+9 more)

### Community 105 - "VectorTransformUndoLogicTests"
Cohesion: 0.24
Nodes (8): CanvasManager, CGAffineTransform, Int, LayerTransform, StaticString, String, UInt, VectorTransformUndoLogicTests

### Community 106 - "OnionSkinPanel"
Cohesion: 0.10
Nodes (22): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+14 more)

### Community 107 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 108 - ".image"
Cohesion: 0.15
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 109 - ".compositeSize"
Cohesion: 0.19
Nodes (4): .resolutionNoteText, OnionSkinBudget, CGSize, Int

### Community 110 - "FillGestureRestartLogicTests"
Cohesion: 0.22
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 111 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 112 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 114 - "VectorPreviewPlanLogicTests"
Cohesion: 0.13
Nodes (11): Bool, String, VectorPreviewPlan, VectorScratchRole, none, overlay, replacement, .traceName (+3 more)

### Community 115 - "SwiftUI"
Cohesion: 0.12
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 116 - "Layer Compositing"
Cohesion: 0.07
Nodes (29): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+21 more)

### Community 117 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 118 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 119 - "CodingKeys"
Cohesion: 0.07
Nodes (27): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+19 more)

### Community 120 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 121 - ".attach"
Cohesion: 0.21
Nodes (5): IndexPath, Context, UIPinchGestureRecognizer, UISwipeActionsConfiguration, UITableView

### Community 122 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 123 - "BrushStamper"
Cohesion: 0.11
Nodes (15): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+7 more)

### Community 124 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 125 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 126 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 127 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 128 - "UInt8"
Cohesion: 0.15
Nodes (5): CGPath, ClosedRange, Int, UInt64, UInt8

### Community 129 - "1. The decisions"
Cohesion: 0.10
Nodes (21): 0. How much of this already exists, 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, 6. Open risks, A fill is a `CGPath`, and cutting a chunk out of it is two Core Graphics calls (+13 more)

### Community 130 - "CodingKeys"
Cohesion: 0.10
Nodes (21): CodingKeys, brush, color, composite, elements, fill, fills, id (+13 more)

### Community 131 - "LayerRowModel"
Cohesion: 0.13
Nodes (20): DispatchWorkItem, .body, Coordinator, LayerRowModel, .folderID, .isFolder, .maskSource, LayerStackListView (+12 more)

### Community 132 - "CaseIterable"
Cohesion: 0.07
Nodes (28): CaseIterable, Kind, line, oval, rectangle, Decoder, Colouring, .id (+20 more)

### Community 133 - "OnionSkinLogicTests"
Cohesion: 0.11
Nodes (12): CelSpan, .end, OnionSkinPlanner, OnionSkinSettingsSource, OnionSkinSource, Bool, OnionSkinLogicTests, Bool (+4 more)

### Community 134 - "Coordinator"
Cohesion: 0.17
Nodes (9): BlockDrag, CelBlockView, Coordinator, Bool, CanvasManager, Coordinator, UIImage, Void (+1 more)

### Community 135 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 136 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 137 - "ShapeHoldClock"
Cohesion: 0.21
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 138 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 139 - ".makeUIView"
Cohesion: 0.13
Nodes (8): AppliedTool, CanvasView, Color, Context, Coordinator, Double, UIColor, UIViewRepresentable

### Community 140 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 141 - "SandwichCompositingUITests"
Cohesion: 0.25
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 142 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.27
Nodes (3): CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 143 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 144 - "RenderRequest"
Cohesion: 0.16
Nodes (15): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, CacheKey, MaskCache (+7 more)

### Community 145 - "CGFloat"
Cohesion: 0.10
Nodes (14): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, StrokeSampleGate (+6 more)

### Community 146 - ".reconcileLayers"
Cohesion: 0.12
Nodes (6): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, TimeInterval

### Community 147 - ".lassoFill"
Cohesion: 0.20
Nodes (3): Bool, Double, Float

### Community 148 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 149 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.25
Nodes (4): rest, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 150 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.11
Nodes (19): A project that opened with something unreadable, Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features (+11 more)

### Community 151 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 152 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 153 - ".rasterize"
Cohesion: 0.20
Nodes (6): LassoFillMask, Float, Int, SIMD4, UInt8, mask

### Community 154 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 155 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 156 - "CanvasPresentation"
Cohesion: 0.09
Nodes (20): CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id, interpolateOptions (+12 more)

### Community 157 - ".backfillMissingThumbnails"
Cohesion: 0.18
Nodes (10): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+2 more)

### Community 158 - "UndoHistory"
Cohesion: 0.12
Nodes (15): Action, Bool, Int, UInt64, Void, UndoBudget, .maxCostBytes, UndoHistory (+7 more)

### Community 159 - "InterpolationRefusal"
Cohesion: 0.15
Nodes (15): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+7 more)

### Community 160 - "CGRect"
Cohesion: 0.21
Nodes (10): CGRect, ClosedRange, NSCoder, String, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView (+2 more)

### Community 161 - "CanvasPresentationLogicTests"
Cohesion: 0.15
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 162 - ".performDrag"
Cohesion: 0.16
Nodes (5): InterpolationWorkflowUITests, Bool, TimeInterval, XCUIElement, TimelineGestureUITests

### Community 163 - "Foundation"
Cohesion: 0.09
Nodes (11): Foundation, os, Notification.Name, CodableColor, .color, Color, .codable, CodableColor (+3 more)

### Community 164 - "StructureSnapshot"
Cohesion: 0.23
Nodes (4): CanvasManager, StructureSnapshot, Int, Layer

### Community 165 - "ViewPreset"
Cohesion: 0.16
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 166 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 167 - "TextRecipeCodableLogicTests"
Cohesion: 0.17
Nodes (5): StaticString, String, T, UInt, TextRecipeCodableLogicTests

### Community 168 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 169 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 171 - "LayerStackListView.Coordinator"
Cohesion: 0.15
Nodes (11): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, ObjectIdentifier, TimeInterval, UIGestureRecognizer (+3 more)

### Community 172 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 173 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 174 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 175 - ".sample"
Cohesion: 0.18
Nodes (13): NSObject, ObjectiveC.runtime, FoundElement, ResolvedTarget, Bool, CGRect, CGSize, Double (+5 more)

### Community 176 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 177 - ".relayout"
Cohesion: 0.23
Nodes (6): Context, UIPinchGestureRecognizer, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 178 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 179 - "TimelineLayoutKey"
Cohesion: 0.29
Nodes (12): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+4 more)

### Community 180 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 182 - "Lasso Fill — Specification"
Cohesion: 0.15
Nodes (12): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 2a. Where a fill lands in the stack: on top of everything already on the layer, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill (+4 more)

### Community 183 - "SelectionOverlayLogicTests"
Cohesion: 0.16
Nodes (6): resolvedLastTouchType(), UITouch, SelectionOverlayLogicTests, Bool, UITouch, S

### Community 184 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 185 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 186 - "Handle"
Cohesion: 0.15
Nodes (13): Handle, bottom, bottomLeft, bottomRight, .heightSign, .isResize, left, right (+5 more)

### Community 187 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 188 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.18
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 189 - "Handoff — 2026-08-22"
Cohesion: 0.20
Nodes (9): A count that does not tie, worth thirty seconds, Handoff — 2026-08-22, Start here — paste this to begin the next session, State, Still true, carried forward, The thing that would have shipped broken, and how it was caught, What landed, What the owner has to decide, once they have looked (+1 more)

### Community 190 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 191 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 192 - ".frames"
Cohesion: 0.20
Nodes (3): CGRect, Range, TimelineRulerClip

### Community 193 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 194 - ".textureBudgetBytes"
Cohesion: 0.47
Nodes (4): CompositorBudget, .textureBudgetBytes, Int, UInt64

### Community 195 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 196 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 197 - "TextRecipe"
Cohesion: 0.15
Nodes (15): Alignment, center, .displayName, .id, justified, left, right, FontDescriptor (+7 more)

### Community 198 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 199 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 200 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 201 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 203 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 205 - "MenuRequest"
Cohesion: 0.50
Nodes (4): MenuRequest, block, gap, loop

### Community 207 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 208 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 209 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 211 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 212 - "TODO"
Cohesion: 0.40
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 213 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 214 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **1054 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+1049 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `CGPoint`, `cels`, `CanvasManager`, `InterpolationGuideLogicTests`, `CanvasManager`, `InterpolationRecipe`, `VectorCanvas`, `LassoFillLogicTests`, `VectorEraserHybridLogicTests`, `Lattice`, `AlphaMask`, `BrushBlendMode`, `Coordinator`, `.solidImage`, `StrokeGeometryLogicTests`, `PerfBaselineTests`, `StrokeCanvasView`, `TextFrame`, `AnimationTimeline`, `ProjectStore`, `UIKit`, `SandwichLogicTests`, `VectorEraserLogicTests`, `.setBakedContent`, `StrokeGeometry`, `ShapeDetector`, `ARAPLogicTests`, `.refreshUndoRedoState`, `ShapeOverlayView`, `.launchIntoEditor`, `BrushEngineLogicTests`, `CanvasManager`, `TextTransformLogicTests`, `CanvasManager`, `TextOverlayView`, `TextBakeCharacterizationTests`, `DeformFactorization`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `LayerStackCell`, `LayerContentVersion`, `FontResolveLogicTests`, `.rows`, `VectorCanvasDataLogicTests`, `ActionRecorder`, `Typography`, `.transparentFormat`, `GuideOverlayView`, `Binding`, `InterpolationEvaluator`, `StrokeSpatialIndex`, `ObjectTransformOverlayView`, `TextTransformOverlayView`, `.apply`, `FloatingPieceOverlayView`, `Brush`, `TimelineRowView`, `VectorSample`, `InterpolationModelLogicTests`, `DrawingView`, `TextHitTestLogicTests`, `SpacingChart`, `VectorTransformUndoLogicTests`, `.image`, `.compositeSize`, `XCUIApplication`, `WindowEventTap`, `.attach`, `BrushStamper`, `PinchMergeGateLogicTests`, `CanvasManager`, `CurveEditor`, `UInt8`, `CodingKeys`, `LayerRowModel`, `CaseIterable`, `OnionSkinLogicTests`, `Coordinator`, `CanvasTransformFreezeUITests`, `.makeUIView`, `TextSettingsPanel`, `SandwichCompositingUITests`, `TimelineLayoutKeyLogicTests`, `RenderRequest`, `.reconcileLayers`, `.lassoFill`, `InterpolationEngineDiagnosticsLogicTests`, `.rasterize`, `InterpolateBar`, `CGContextDabTarget`, `.backfillMissingThumbnails`, `CGRect`, `.performDrag`, `SideToolbar`, `ActionsMenu`, `.sample`, `.relayout`, `TimelineLayoutKey`, `TransformOverlaySupport.swift`, `StrokeStabilizer`, `Handle`, `.frames`, `TextRecipe`, `Kind`, `JSONValue`?**
  _High betweenness centrality (0.289) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `CanvasManager`, `InterpolationGuideLogicTests`, `CanvasManager`, `InterpolationRecipe`, `VectorCanvas`, `LassoFillLogicTests`, `VectorEraserHybridLogicTests`, `Lattice`, `AlphaMask`, `BrushBlendMode`, `Coordinator`, `StrokeGeometryLogicTests`, `PerfBaselineTests`, `String`, `StrokeCanvasView`, `VectorCanvasData`, `TextFrame`, `AnimationTimeline`, `UIKit`, `VectorEraserLogicTests`, `ProjectSaveLogicTests`, `StrokeGeometry`, `ShapeDetector`, `ARAPLogicTests`, `SelectionOverlayView`, `.refreshUndoRedoState`, `ShapeOverlayView`, `BrushEngineLogicTests`, `CanvasManager`, `layers`, `TextTransformLogicTests`, `CanvasManager`, `TextOverlayView`, `TextBakeCharacterizationTests`, `DeformFactorization`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `EyedropperLogicTests`, `SaveDamageGateLogicTests`, `Typography`, `.transparentFormat`, `GuideOverlayView`, `ColorPickerPanel`, `InterpolationEvaluator`, `StrokeSpatialIndex`, `ObjectTransformOverlayView`, `TextTransformOverlayView`, `FloatingPieceOverlayView`, `Brush`, `TimelineRowView`, `VectorSample`, `InterpolationModelLogicTests`, `TextHitTestLogicTests`, `SpacingChart`, `VectorTransformUndoLogicTests`, `FillGestureRestartLogicTests`, `WindowEventTap`, `.rasterize`, `BrushStamper`, `CurveEditor`, `CaseIterable`, `Coordinator`, `.makeUIView`, `CGFloat`, `.reconcileLayers`, `InterpolationEngineDiagnosticsLogicTests`, `.rasterize`, `CGContextDabTarget`, `.backfillMissingThumbnails`, `CGRect`, `TextRecipeCodableLogicTests`, `LayerStackListView.Coordinator`, `.sample`, `TransformOverlaySupport.swift`, `StrokeStabilizer`, `.sampledColor`, `.frames`?**
  _High betweenness centrality (0.140) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `CGPoint`, `cels`, `InterpolationGuideLogicTests`, `OnionSkinLogicTests`, `LassoFillLogicTests`, `.manager`, `VectorEraserHybridLogicTests`, `Lattice`, `ProjectBackupManager`, `AlphaMask`, `ShapeHoldClock`, `TimelineLayoutKeyLogicTests`, `.solidImage`, `StrokeGeometryLogicTests`, `PerfBaselineTests`, `BlockDragCharacterizationTests`, `InterpolationEngineDiagnosticsLogicTests`, `VectorCanvasData`, `UIKit`, `SandwichLogicTests`, `VectorEraserLogicTests`, `ProjectSaveLogicTests`, `.setBakedContent`, `UndoHistory`, `StrokeGestureRecognizer`, `CanvasPresentationLogicTests`, `ARAPLogicTests`, `LayerTreeCharacterizationTests`, `EffectMultiPassLogicTests`, `TextRecipeCodableLogicTests`, `SelectionPersistenceLogicTests`, `BrushEngineLogicTests`, `TextTransformLogicTests`, `RenderTreeCharacterizationTests`, `SelectionOverlayLogicTests`, `PaintUITestCase`, `TextBakeCharacterizationTests`, `InterpolationRenderLogicTests`, `FontResolveLogicTests`, `FillBoundaryLogicTests`, `VectorCanvasDataLogicTests`, `VectorEraserMode`, `CanvasNotice`, `EyedropperLogicTests`, `GalleryOpenState`, `PlaybackBoundsCharacterizationTests`, `SaveDamageGateLogicTests`, `Typography`, `ObjectTransformOverlayView`, `VectorSample`, `InterpolationModelLogicTests`, `TextHitTestLogicTests`, `EffectParityLogicTests`, `VectorTransformUndoLogicTests`, `FillGestureRestartLogicTests`, `VectorPreviewPlanLogicTests`, `PinchMergeGateLogicTests`, `MaskGuardLogicTests`?**
  _High betweenness centrality (0.113) - this node is a cross-community bridge._
- **Are the 80 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 80 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Are the 23 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 23 INFERRED edges - model-reasoned connections that need verification._