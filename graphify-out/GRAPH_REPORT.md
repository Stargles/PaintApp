# Graph Report - PaintApp-perf9  (2026-08-20)

## Corpus Check
- 230 files · ~703,338 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6800 nodes · 20685 edges · 222 communities (206 shown, 16 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2068 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `c147c04f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- VectorSample
- cels
- CanvasManager
- CGPoint
- CanvasManager
- .manager
- Lattice
- ProjectBackupManager
- InterpolationRecipe
- PointCloudIndex
- VectorCanvas
- CompositorParityLogicTests
- HistoryActionLabel
- Coordinator
- LassoFillLogicTests
- String
- AnimationTimeline
- .setBakedContent
- PerfBaselineTests
- AlphaMask
- VectorEraserLogicTests
- CGFloat
- StrokeCanvasView
- Codable
- SandwichLogicTests
- StrokeGestureRecognizer
- .report
- .drawLine
- ARAPLogicTests
- LayerTreeCharacterizationTests
- SelectionOverlayView
- UIKit
- ShapeOverlayView
- CompositorMetalEngine
- ProjectSaveLogicTests
- PaintUITestCase
- EffectMultiPassLogicTests
- Effect
- .apply
- TextRecipe
- VectorCanvasData
- ValueLayerLogicTests
- BrushEngineLogicTests
- .transparentFormat
- TextFrame
- CanvasManager
- .launchIntoEditor
- XCTestCase
- CanvasManager
- ProjectStore
- Fill.metal
- layers
- CanvasManager
- View
- VectorEraserHybridLogicTests
- .reconcileLayers
- TextBakeCharacterizationTests
- BrushStamper
- .solidImage
- InterpolationRenderLogicTests
- FontFace
- RenderNode
- LayerStackCell
- ObjectTransformOverlayView
- .rows
- FillBoundaryLogicTests
- VectorCanvasDataLogicTests
- VectorEraserMode
- ActionRecorder
- Typography
- TextOverlayView
- PlaybackBoundsCharacterizationTests
- .evaluate
- ProjectManifest
- Binding
- ContentView
- PaletteColor
- GuideOverlayView
- MetalFillSession
- StrokeSampleGateLogicTests
- BlendMode
- CanvasManager
- CodingKey
- TimelineRowView
- CodingKeys
- GalleryOpenState
- WindowEventTap
- Composite.metal
- TextHitTestLogicTests
- MaskSource
- DrawingView
- ColorPickerPanel
- OnionSkinSettings
- EffectParityLogicTests
- Known Issues
- CanvasNotice
- agent
- RasterLayerTexture
- VectorTextPersistenceLogicTests
- ActivePanel
- RenderRequest
- OnionSkinPanel
- Coordinator
- InterpolationGuideLogicTests
- XCUIApplication
- StrokeSpatialIndex
- bash
- TimedSample
- .compositeSize
- FloatingPieceOverlayView
- .sample
- .image
- read
- Compositor.swift
- PinchMergeGateLogicTests
- GuideRow
- FontResolveLogicTests
- Gesture
- SwiftUI
- Foundation
- LayerContentVersion
- Layer Compositing
- MaskGuardLogicTests
- CanvasManager
- CurveEditor
- OnionSkinLogicTests
- LayerRowModel
- Coordinator
- CGRect
- CanvasTransformFreezeUITests
- LayerStackListView.Coordinator
- EffectParams
- .makeRenderRequest
- ShapeHoldClock
- CodingKeys
- Kind
- Layer
- TextSettingsPanel
- FillGestureRestartLogicTests
- .manager
- SandwichCompositingUITests
- TimelineLayoutKeyLogicTests
- .coverage
- .backfillMissingThumbnails
- BlockDragCharacterizationTests
- 1. The decisions
- PerfMonitor
- CanvasPresentation
- EffectPipelines
- InterpolateBar
- InterpolationEngineDiagnosticsLogicTests
- PaintSoftware - iPad Drawing and Animation App
- TextLayout
- .arched
- OnionSkinSource.swift
- CanvasPresentationLogicTests
- Recording
- CanvasSizePickerView
- EraserSettingsPanel
- SideToolbar
- MenuInterruptionUITests
- .indices
- ViewPreset
- CompositorRole
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- CGContextDabTarget
- SpacingChart
- StructureSnapshot
- UndoHistory
- CanvasHostView
- .relayout
- Performance
- TimelineLayoutKey
- CLAUDE.md
- GuidePath
- StrokeStabilizer
- SelectPanel
- 4. Future upgrades — the deferred list
- Every dismissible presentation, and whether a stroke under it breaks
- Lasso Fill — Specification
- .sampledColor
- CanvasPresentationModifier
- .frames
- Multi-Session Protocol
- .textureBudgetBytes
- CutOutcome
- Kind
- TransformMode
- .row
- Handoff — 2026-08-20
- 6. Alpha masks
- command
- JSONValue
- CompositeProbe
- SelectionMode
- RecordingWriter
- .handleShouldReceive
- Double
- Atomic
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- ToolPanelsUITests
- parallel_test.sh
- effectChannels
- .render
- SandwichPresentation
- Performance baseline
- TODO
- FillAxis
- Kind
- MenuRequest
- simlock.sh
- TextLayout.swift
- cleanup_session.sh
- screenshot.sh
- Prompt for the next session
- presentation-census.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 685 edges
2. `CGFloat` - 524 edges
3. `CanvasManager` - 163 edges
4. `VectorCanvas` - 152 edges
5. `Effect` - 149 edges
6. `layers` - 126 edges
7. `VectorSample` - 119 edges
8. `Coordinator` - 115 edges
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

## Communities (222 total, 16 thin omitted)

### Community 0 - "VectorSample"
Cohesion: 0.04
Nodes (30): Brush, VectorSample, .point, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool (+22 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (59): Never, Void, CanvasManager, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex (+51 more)

### Community 3 - "CGPoint"
Cohesion: 0.05
Nodes (34): CGPoint, .length, Int, Corner, bottomLeft, bottomRight, topLeft, topRight (+26 more)

### Community 4 - "CanvasManager"
Cohesion: 0.04
Nodes (52): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+44 more)

### Community 5 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 6 - "Lattice"
Cohesion: 0.05
Nodes (34): CodingKeys, activeCells, cellSize, cols, originX, originY, rows, vertices (+26 more)

### Community 7 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (38): DateFormatter, Decodable, Cel, Layer, ManifestSkeleton, Notification.Name, ProjectBackup, .id (+30 more)

### Community 8 - "InterpolationRecipe"
Cohesion: 0.05
Nodes (43): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+35 more)

### Community 9 - "PointCloudIndex"
Cohesion: 0.07
Nodes (23): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+15 more)

### Community 10 - "VectorCanvas"
Cohesion: 0.06
Nodes (43): ContentProvider, CGSize, UIImage, VectorTextElement, image, kind, Kind, fill (+35 more)

### Community 11 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (12): CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int, StaticString, String (+4 more)

### Community 12 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 13 - "Coordinator"
Cohesion: 0.06
Nodes (31): AppliedTool, CanvasView, Coordinator, .canvasContentScale, .isLassoFilling, .sandwichPresentation, OnionSkinKey, CALayer (+23 more)

### Community 14 - "LassoFillLogicTests"
Cohesion: 0.09
Nodes (16): LassoFillMask, Float, Int, SIMD4, UInt8, mask, LassoFillLogicTests, .loopAroundEverything (+8 more)

### Community 15 - "String"
Cohesion: 0.04
Nodes (55): CaseIterable, Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+47 more)

### Community 16 - "AnimationTimeline"
Cohesion: 0.04
Nodes (50): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+42 more)

### Community 17 - ".setBakedContent"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 18 - "PerfBaselineTests"
Cohesion: 0.12
Nodes (9): PerfBaselineTests, Bool, CanvasManager, CGSize, Double, Int, String, UInt64 (+1 more)

### Community 19 - "AlphaMask"
Cohesion: 0.08
Nodes (11): AlphaMask, .isActive, Bool, Int, MaskParityLogicTests, .side, Bool, CanvasManager (+3 more)

### Community 20 - "VectorEraserLogicTests"
Cohesion: 0.09
Nodes (9): CGRect, VectorEraser, Set, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests (+1 more)

### Community 21 - "CGFloat"
Cohesion: 0.07
Nodes (23): Accelerate, bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, DeformDataRow (+15 more)

### Community 22 - "StrokeCanvasView"
Cohesion: 0.07
Nodes (32): CAShapeLayer, StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush (+24 more)

### Community 23 - "Codable"
Cohesion: 0.05
Nodes (46): Codable, CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma (+38 more)

### Community 24 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 25 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 26 - ".report"
Cohesion: 0.09
Nodes (34): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+26 more)

### Community 27 - ".drawLine"
Cohesion: 0.11
Nodes (12): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, Bool, CGVector, Double, TimeInterval, UInt8 (+4 more)

### Community 28 - "ARAPLogicTests"
Cohesion: 0.08
Nodes (15): ARAPInterpolation, Interpolator, Options, Bool, Matrix2x2, .determinant, .isFinite, .polar (+7 more)

### Community 29 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (6): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 30 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 31 - "UIKit"
Cohesion: 0.08
Nodes (6): CoreGraphics, Darwin, Metal, simd, UIKit, XCTest

### Community 32 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 33 - "CompositorMetalEngine"
Cohesion: 0.11
Nodes (27): Admission, admitted, noHeadroom, overBudget, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+19 more)

### Community 34 - "ProjectSaveLogicTests"
Cohesion: 0.13
Nodes (11): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString, String (+3 more)

### Community 35 - "PaintUITestCase"
Cohesion: 0.09
Nodes (13): HistoryNoticeUITests, PaintUITestCase, Int, String, XCUIApplication, InterpolationWorkflowUITests, Bool, TimeInterval (+5 more)

### Community 36 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 37 - "Effect"
Cohesion: 0.09
Nodes (32): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+24 more)

### Community 38 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 39 - "TextRecipe"
Cohesion: 0.05
Nodes (42): .descriptor, Alignment, center, .displayName, .id, justified, left, right (+34 more)

### Community 40 - "VectorCanvasData"
Cohesion: 0.07
Nodes (35): Error, CodableColor, .uiColor, DecodeReport, .droppedCount, .isClean, ElementData, fill (+27 more)

### Community 41 - "ValueLayerLogicTests"
Cohesion: 0.11
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 42 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 43 - ".transparentFormat"
Cohesion: 0.11
Nodes (21): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+13 more)

### Community 44 - "TextFrame"
Cohesion: 0.08
Nodes (20): Int, Corner, bottomLeft, bottomRight, topLeft, topRight, Mode, affine (+12 more)

### Community 45 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 46 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 47 - "XCTestCase"
Cohesion: 0.13
Nodes (9): StaticString, String, UInt, XCTestCase, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String (+1 more)

### Community 48 - "CanvasManager"
Cohesion: 0.11
Nodes (18): UUID, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform (+10 more)

### Community 49 - "ProjectStore"
Cohesion: 0.13
Nodes (25): CFAbsoluteTime, CelContent, DecodedCels, LayerContent, LoadProfile, .millisecondsPerCel, .thumbnailShare, ProjectStore (+17 more)

### Community 50 - "Fill.metal"
Cohesion: 0.17
Nodes (40): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+32 more)

### Community 51 - "layers"
Cohesion: 0.12
Nodes (19): .activeContainerID, .activeLayerIsVector, .activeLayerKind, .newLayerPlacement, .activeCelIsInBetween, UUID, VectorStroke, LayerTransform (+11 more)

### Community 52 - "CanvasManager"
Cohesion: 0.13
Nodes (16): CanvasManager, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel, CGPath (+8 more)

### Community 53 - "View"
Cohesion: 0.14
Nodes (29): View, .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex (+21 more)

### Community 54 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 55 - ".reconcileLayers"
Cohesion: 0.08
Nodes (16): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, InterpolationPreviewKey, Bool, Int (+8 more)

### Community 56 - "TextBakeCharacterizationTests"
Cohesion: 0.17
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 57 - "BrushStamper"
Cohesion: 0.12
Nodes (14): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+6 more)

### Community 58 - ".solidImage"
Cohesion: 0.09
Nodes (11): Eyedropper, Sample, CGSize, Double, Int, UInt8, CGSize, UIColor (+3 more)

### Community 59 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): StrokeComposite, erase, paint, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int (+3 more)

### Community 60 - "FontFace"
Cohesion: 0.12
Nodes (17): FontFace, .id, FontFamilyGroup, .id, FontLibrary, FontProvider, FontResolution, .substituted (+9 more)

### Community 61 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 62 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): effectMenuSlug(), LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String (+4 more)

### Community 63 - "ObjectTransformOverlayView"
Cohesion: 0.09
Nodes (23): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, FloatingTransform (+15 more)

### Community 64 - ".rows"
Cohesion: 0.11
Nodes (26): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+18 more)

### Community 65 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 66 - "VectorCanvasDataLogicTests"
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 67 - "VectorEraserMode"
Cohesion: 0.07
Nodes (24): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+16 more)

### Community 68 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 69 - "Typography"
Cohesion: 0.19
Nodes (8): UIFont, ClosedRange, Typography, .clamped, Int, String, UIFont, TextLayoutLogicTests

### Community 70 - "TextOverlayView"
Cohesion: 0.11
Nodes (16): RenderKey, Bool, CGRect, CGSize, NSCoder, Set, String, UIEvent (+8 more)

### Community 71 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 72 - ".evaluate"
Cohesion: 0.14
Nodes (19): CGPathElementType, Direction, backward, forward, fromRest, Evaluation, GroupWarp, InterpolationEvaluator (+11 more)

### Community 73 - "ProjectManifest"
Cohesion: 0.16
Nodes (19): Decoder, ValueFill, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, BlendMode (+11 more)

### Community 74 - "Binding"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 75 - "ContentView"
Cohesion: 0.07
Nodes (18): App, AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager (+10 more)

### Community 76 - "PaletteColor"
Cohesion: 0.15
Nodes (17): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+9 more)

### Community 77 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 78 - "MetalFillSession"
Cohesion: 0.19
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 79 - "StrokeSampleGateLogicTests"
Cohesion: 0.15
Nodes (6): CountingDabTarget, StrokeSampleGateLogicTests, CGBlendMode, UIColor, UInt64, Tremor

### Community 80 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 81 - "CanvasManager"
Cohesion: 0.09
Nodes (14): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage (+6 more)

### Community 82 - "CodingKey"
Cohesion: 0.07
Nodes (30): CodingKey, CodingKeys, endPoint, kind, rotation, spanStart, spanSweep, startPoint (+22 more)

### Community 83 - "TimelineRowView"
Cohesion: 0.13
Nodes (17): Kind, cel, gap, Segment, Cel, Int, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 84 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 85 - "GalleryOpenState"
Cohesion: 0.14
Nodes (13): GalleryOpenState, .isBusy, Bool, UUID, GalleryTileView, .body, Bool, Void (+5 more)

### Community 86 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 87 - "Composite.metal"
Cohesion: 0.25
Nodes (26): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+18 more)

### Community 88 - "TextHitTestLogicTests"
Cohesion: 0.18
Nodes (6): Bool, CGAffineTransform, CGSize, String, VectorStroke, TextHitTestLogicTests

### Community 89 - "MaskSource"
Cohesion: 0.13
Nodes (15): Kind, folder, layer, MaskSource, folder, .id, layer, Decoder (+7 more)

### Community 90 - "DrawingView"
Cohesion: 0.08
Nodes (20): ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void, DrawingView (+12 more)

### Community 91 - "ColorPickerPanel"
Cohesion: 0.11
Nodes (20): ColorPickerPanel, .body, .colorTab, .currentColor, .hexRow, .hueSlider, .palettesTab, .renameAlertBinding (+12 more)

### Community 92 - "OnionSkinSettings"
Cohesion: 0.17
Nodes (11): .gradientStops, .opacitySliders, OnionSkinSettings, Side, .id, next, previous, .step (+3 more)

### Community 93 - "EffectParityLogicTests"
Cohesion: 0.20
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 94 - "Known Issues"
Cohesion: 0.08
Nodes (26): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A lasso fill does not paint over line art on a *raster* layer either, for the same-layer case (2026-08-17), A lasso fill does not paint over line art on a *vector* layer (2026-08-17), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), Cleanup opportunities, Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16) (+18 more)

### Community 95 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 96 - "agent"
Cohesion: 0.08
Nodes (25): agent, orchestrator, worker-integration, worker-research, worker-test, worker-ui, model, description (+17 more)

### Community 97 - "RasterLayerTexture"
Cohesion: 0.16
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 98 - "VectorTextPersistenceLogicTests"
Cohesion: 0.22
Nodes (5): .elements, String, UUID, VectorStroke, VectorTextPersistenceLogicTests

### Community 99 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 100 - "RenderRequest"
Cohesion: 0.20
Nodes (14): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, Attempt, image (+6 more)

### Community 101 - "OnionSkinPanel"
Cohesion: 0.11
Nodes (21): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+13 more)

### Community 102 - "Coordinator"
Cohesion: 0.17
Nodes (9): BlockDrag, CelBlockView, Coordinator, Bool, CanvasManager, Coordinator, UIImage, Void (+1 more)

### Community 104 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 105 - "StrokeSpatialIndex"
Cohesion: 0.18
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 106 - "bash"
Cohesion: 0.17
Nodes (24): worker-bugfix, worker-feature, gh *, git *, xcodebuild *, permission, bash, edit (+16 more)

### Community 107 - "TimedSample"
Cohesion: 0.13
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 108 - ".compositeSize"
Cohesion: 0.18
Nodes (5): .resolutionNoteText, OnionSkinBudget, CGSize, Int, Int

### Community 109 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 110 - ".sample"
Cohesion: 0.18
Nodes (13): NSObject, ObjectiveC.runtime, FoundElement, ResolvedTarget, Bool, CGRect, CGSize, Double (+5 more)

### Community 111 - ".image"
Cohesion: 0.15
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 112 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 113 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 114 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 115 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 116 - "FontResolveLogicTests"
Cohesion: 0.21
Nodes (5): FontResolveLogicTests, StubFontProvider, Bool, String, UIFont

### Community 117 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 118 - "SwiftUI"
Cohesion: 0.13
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 119 - "Foundation"
Cohesion: 0.10
Nodes (10): Foundation, os, CodableColor, .color, Color, .codable, CodableColor, AppVersion (+2 more)

### Community 120 - "LayerContentVersion"
Cohesion: 0.13
Nodes (14): Hasher, LayerContentVersion, RenderResolution, full, half, .id, .scale, threeQuarter (+6 more)

### Community 121 - "Layer Compositing"
Cohesion: 0.09
Nodes (22): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+14 more)

### Community 122 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 123 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 124 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 125 - "OnionSkinLogicTests"
Cohesion: 0.19
Nodes (5): CelSpan, .end, OnionSkinPlanner, Bool, OnionSkinLogicTests

### Community 126 - "LayerRowModel"
Cohesion: 0.13
Nodes (13): IndexPath, LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, Context, Double (+5 more)

### Community 127 - "Coordinator"
Cohesion: 0.20
Nodes (10): .body, Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID (+2 more)

### Community 128 - "CGRect"
Cohesion: 0.21
Nodes (10): CGRect, ClosedRange, NSCoder, String, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView (+2 more)

### Community 129 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 130 - "LayerStackListView.Coordinator"
Cohesion: 0.15
Nodes (10): DispatchWorkItem, DropTarget, between, onto, LayerStackListView.Coordinator, CGRect, TimeInterval, UILongPressGestureRecognizer (+2 more)

### Community 131 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 132 - ".makeRenderRequest"
Cohesion: 0.21
Nodes (10): CanvasManager, LayerRenderSource, RenderBackground, SandwichRequests, Bool, CGImage, CGSize, Int (+2 more)

### Community 133 - "ShapeHoldClock"
Cohesion: 0.19
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 134 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 135 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 136 - "Layer"
Cohesion: 0.10
Nodes (17): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+9 more)

### Community 137 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 138 - "FillGestureRestartLogicTests"
Cohesion: 0.25
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 139 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 140 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 141 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.27
Nodes (3): CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 142 - ".coverage"
Cohesion: 0.27
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 143 - ".backfillMissingThumbnails"
Cohesion: 0.18
Nodes (11): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+3 more)

### Community 144 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 145 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 146 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 147 - "CanvasPresentation"
Cohesion: 0.11
Nodes (15): Hashable, CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id (+7 more)

### Community 148 - "EffectPipelines"
Cohesion: 0.19
Nodes (12): MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue, MTLComputeCommandEncoder (+4 more)

### Community 149 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 150 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.30
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 151 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.11
Nodes (18): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+10 more)

### Community 152 - "TextLayout"
Cohesion: 0.23
Nodes (11): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGRect (+3 more)

### Community 153 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 154 - "OnionSkinSource.swift"
Cohesion: 0.18
Nodes (7): OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager, StaticString, UIImage, UInt

### Community 155 - "CanvasPresentationLogicTests"
Cohesion: 0.15
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 156 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 157 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 158 - "EraserSettingsPanel"
Cohesion: 0.15
Nodes (13): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+5 more)

### Community 159 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 160 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 162 - "ViewPreset"
Cohesion: 0.19
Nodes (8): CanvasManager, .activeViewName, Int, String, Bool, String, UUID, ViewPreset

### Community 163 - "CompositorRole"
Cohesion: 0.13
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 164 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 165 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 166 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 167 - "SpacingChart"
Cohesion: 0.19
Nodes (4): SpacingChart, .curve, .draggable, Range

### Community 168 - "StructureSnapshot"
Cohesion: 0.23
Nodes (4): CanvasManager, StructureSnapshot, Int, Layer

### Community 169 - "UndoHistory"
Cohesion: 0.23
Nodes (7): Action, Bool, Int, Void, UndoHistory, .canRedo, .canUndo

### Community 170 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 171 - ".relayout"
Cohesion: 0.23
Nodes (6): Context, UIPinchGestureRecognizer, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 172 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 173 - "TimelineLayoutKey"
Cohesion: 0.29
Nodes (12): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+4 more)

### Community 175 - "GuidePath"
Cohesion: 0.24
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 176 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 177 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 178 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 179 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.18
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 180 - "Lasso Fill — Specification"
Cohesion: 0.20
Nodes (10): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill, 8. Open risks (+2 more)

### Community 181 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 182 - "CanvasPresentationModifier"
Cohesion: 0.31
Nodes (6): CanvasPresentationModifier, Bool, CanvasManager, Void, PresentedContent, ViewModifier

### Community 183 - ".frames"
Cohesion: 0.20
Nodes (3): CGRect, Range, TimelineRulerClip

### Community 184 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 185 - ".textureBudgetBytes"
Cohesion: 0.47
Nodes (4): CompositorBudget, .textureBudgetBytes, Int, UInt64

### Community 186 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 187 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 188 - "TransformMode"
Cohesion: 0.22
Nodes (8): TransformMode, .displayName, distort, freeform, .id, .isImplemented, uniform, warp

### Community 189 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 190 - "Handoff — 2026-08-20"
Cohesion: 0.29
Nodes (6): Handoff — 2026-08-20, Three things this pass learned the hard way, What is worth doing next, What needs the owner's iPad, What shipped, What the owner owes a ruling on

### Community 191 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 192 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 193 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 195 - "SelectionMode"
Cohesion: 0.29
Nodes (7): SelectionMode, automatic, .displayName, .id, lasso, rectangle, .systemImage

### Community 197 - ".handleShouldReceive"
Cohesion: 0.53
Nodes (4): Bool, ObjectIdentifier, UIGestureRecognizer, UITouch

### Community 199 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 200 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 202 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 203 - "effectChannels"
Cohesion: 0.70
Nodes (5): effectChannels(), lutEntry(), uint, noiseValue(), screenValue()

### Community 204 - ".render"
Cohesion: 0.40
Nodes (3): CGSize, UIImage, ThumbnailRenderer

### Community 205 - "SandwichPresentation"
Cohesion: 0.40
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 206 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 207 - "TODO"
Cohesion: 0.40
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 208 - "FillAxis"
Cohesion: 0.50
Nodes (4): FillAxis, edgeOverlap, gapClosing, threshold

### Community 209 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 210 - "MenuRequest"
Cohesion: 0.50
Nodes (4): MenuRequest, block, gap, loop

### Community 211 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **976 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+971 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **16 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `VectorSample`, `cels`, `CanvasManager`, `CGPoint`, `CanvasManager`, `Lattice`, `InterpolationRecipe`, `PointCloudIndex`, `VectorCanvas`, `CompositorParityLogicTests`, `Coordinator`, `LassoFillLogicTests`, `String`, `AnimationTimeline`, `.setBakedContent`, `PerfBaselineTests`, `AlphaMask`, `VectorEraserLogicTests`, `StrokeCanvasView`, `SandwichLogicTests`, `.report`, `ARAPLogicTests`, `ShapeOverlayView`, `PaintUITestCase`, `.apply`, `TextRecipe`, `BrushEngineLogicTests`, `.transparentFormat`, `.launchIntoEditor`, `CanvasManager`, `ProjectStore`, `CanvasManager`, `VectorEraserHybridLogicTests`, `.reconcileLayers`, `TextBakeCharacterizationTests`, `BrushStamper`, `InterpolationRenderLogicTests`, `FontFace`, `LayerStackCell`, `ObjectTransformOverlayView`, `.rows`, `VectorCanvasDataLogicTests`, `ActionRecorder`, `Typography`, `TextOverlayView`, `.evaluate`, `Binding`, `GuideOverlayView`, `StrokeSampleGateLogicTests`, `CanvasManager`, `TimelineRowView`, `WindowEventTap`, `TextHitTestLogicTests`, `DrawingView`, `RasterLayerTexture`, `RenderRequest`, `Coordinator`, `InterpolationGuideLogicTests`, `XCUIApplication`, `StrokeSpatialIndex`, `TimedSample`, `.compositeSize`, `.sample`, `.image`, `PinchMergeGateLogicTests`, `FontResolveLogicTests`, `LayerContentVersion`, `CanvasManager`, `CurveEditor`, `LayerRowModel`, `Coordinator`, `CGRect`, `CanvasTransformFreezeUITests`, `CodingKeys`, `TextSettingsPanel`, `.manager`, `SandwichCompositingUITests`, `TimelineLayoutKeyLogicTests`, `.backfillMissingThumbnails`, `InterpolateBar`, `InterpolationEngineDiagnosticsLogicTests`, `TextLayout`, `.arched`, `OnionSkinSource.swift`, `EraserSettingsPanel`, `SideToolbar`, `.indices`, `ActionsMenu`, `CGContextDabTarget`, `SpacingChart`, `.relayout`, `TimelineLayoutKey`, `GuidePath`, `StrokeStabilizer`, `.frames`, `JSONValue`, `SandwichPresentation`?**
  _High betweenness centrality (0.274) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `VectorSample`, `CGRect`, `CanvasManager`, `LayerStackListView.Coordinator`, `CanvasManager`, `.manager`, `Lattice`, `cels`, `InterpolationRecipe`, `PointCloudIndex`, `VectorCanvas`, `FillGestureRestartLogicTests`, `.manager`, `Coordinator`, `LassoFillLogicTests`, `String`, `.backfillMissingThumbnails`, `AnimationTimeline`, `PerfBaselineTests`, `AlphaMask`, `VectorEraserLogicTests`, `CGFloat`, `StrokeCanvasView`, `InterpolationEngineDiagnosticsLogicTests`, `TextLayout`, `.arched`, `.report`, `ARAPLogicTests`, `SelectionOverlayView`, `ShapeOverlayView`, `.indices`, `ProjectSaveLogicTests`, `CGContextDabTarget`, `BrushEngineLogicTests`, `.transparentFormat`, `TextFrame`, `GuidePath`, `StrokeStabilizer`, `CanvasManager`, `layers`, `CanvasManager`, `.sampledColor`, `VectorEraserHybridLogicTests`, `.frames`, `TextBakeCharacterizationTests`, `BrushStamper`, `.solidImage`, `InterpolationRenderLogicTests`, `ObjectTransformOverlayView`, `Typography`, `TextOverlayView`, `.evaluate`, `GuideOverlayView`, `SandwichPresentation`, `StrokeSampleGateLogicTests`, `CanvasManager`, `TimelineRowView`, `WindowEventTap`, `TextHitTestLogicTests`, `ColorPickerPanel`, `RasterLayerTexture`, `VectorTextPersistenceLogicTests`, `Coordinator`, `InterpolationGuideLogicTests`, `StrokeSpatialIndex`, `TimedSample`, `FloatingPieceOverlayView`, `.sample`, `CurveEditor`?**
  _High betweenness centrality (0.157) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `VectorSample`, `cels`, `CGPoint`, `.manager`, `Lattice`, `ProjectBackupManager`, `InterpolationRecipe`, `ShapeHoldClock`, `FillGestureRestartLogicTests`, `CompositorParityLogicTests`, `TimelineLayoutKeyLogicTests`, `LassoFillLogicTests`, `BlockDragCharacterizationTests`, `.setBakedContent`, `PerfBaselineTests`, `AlphaMask`, `VectorEraserLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `SandwichLogicTests`, `StrokeGestureRecognizer`, `.report`, `CanvasPresentationLogicTests`, `ARAPLogicTests`, `LayerTreeCharacterizationTests`, `SelectionOverlayView`, `UIKit`, `ProjectSaveLogicTests`, `PaintUITestCase`, `EffectMultiPassLogicTests`, `ValueLayerLogicTests`, `BrushEngineLogicTests`, `TextFrame`, `VectorEraserHybridLogicTests`, `TextBakeCharacterizationTests`, `.solidImage`, `InterpolationRenderLogicTests`, `FillBoundaryLogicTests`, `VectorCanvasDataLogicTests`, `VectorEraserMode`, `Typography`, `PlaybackBoundsCharacterizationTests`, `StrokeSampleGateLogicTests`, `GalleryOpenState`, `TextHitTestLogicTests`, `EffectParityLogicTests`, `CanvasNotice`, `VectorTextPersistenceLogicTests`, `InterpolationGuideLogicTests`, `PinchMergeGateLogicTests`, `FontResolveLogicTests`, `MaskGuardLogicTests`, `OnionSkinLogicTests`?**
  _High betweenness centrality (0.111) - this node is a cross-community bridge._
- **Are the 80 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 80 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 23 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 23 INFERRED edges - model-reasoned connections that need verification._