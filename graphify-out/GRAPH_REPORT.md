# Graph Report - PaintApp-vec-undo  (2026-08-21)

## Corpus Check
- 234 files · ~727,370 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6893 nodes · 20974 edges · 210 communities (192 shown, 18 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2084 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9a62f50b`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- CGFloat
- CanvasManager
- cels
- CanvasManager
- LassoFillLogicTests
- Lattice
- .manager
- InterpolationGuideLogicTests
- ProjectBackupManager
- String
- PerfBaselineTests
- CGPoint
- VectorEraserHybridLogicTests
- ARAPLogicTests
- VectorCanvas
- VectorSample
- PointCloudIndex
- CompositorParityLogicTests
- HistoryActionLabel
- Coordinator
- VectorEraserLogicTests
- InterpolationRecipe
- Brush
- AlphaMask
- AnimationTimeline
- .setBakedContent
- .launchIntoEditor
- ColorPickerPanel
- StrokeCanvasView
- StrokeGestureRecognizer
- PaintUITestCase
- SandwichLogicTests
- CompositorMetalEngine
- CodingKeys
- ProjectSaveLogicTests
- LayerTreeCharacterizationTests
- ProjectStore
- SelectionOverlayView
- UIKit
- ShapeOverlayView
- .rasterize
- Effect
- EffectMultiPassLogicTests
- Binding
- .apply
- .drawLine
- CanvasManager
- Codable
- TextFrame
- XCTestCase
- CanvasManager
- BrushEngineLogicTests
- CanvasManager
- RasterLayerTexture
- Fill.metal
- RenderRequest
- View
- RenderTreeCharacterizationTests
- TextBakeCharacterizationTests
- .evaluate
- .solidImage
- FontFace
- LayerStackCell
- layers
- InterpolationRenderLogicTests
- FillBoundaryLogicTests
- VectorCanvasDataLogicTests
- CodingKey
- RenderNode
- VectorEraserMode
- TextOverlayView
- agent
- ActionRecorder
- Typography
- UndoHistory
- GuideOverlayView
- PlaybackBoundsCharacterizationTests
- LayerRowModel
- Composite.metal
- BlendMode
- StrokeSpatialIndex
- MaskSource
- .compositeSize
- CurveEditor
- TimelineRowView
- FloatingPieceOverlayView
- CodingKeys
- .rows
- GalleryOpenState
- OnionSkinSettings
- ContentView
- Known Issues
- TextHitTestLogicTests
- CanvasPresentation
- EffectParityLogicTests
- CanvasNotice
- VectorTransformUndoLogicTests
- VectorCanvasData
- GuideStroke
- OnionSkinPanel
- ActivePanel
- EffectPipelines
- SpacingChart
- CodingKeys
- Coordinator
- XCUIApplication
- WindowEventTap
- DrawingView
- VectorPreviewPlanLogicTests
- Compositor.swift
- PinchMergeGateLogicTests
- .makeUIView
- .setUpGestures
- GuideRow
- OnionSkinSource.swift
- Int
- FontResolveLogicTests
- Gesture
- Layer Compositing
- read
- MaskGuardLogicTests
- CanvasManager
- ObjectTransformOverlayView
- CGRect
- CanvasTransformFreezeUITests
- SwiftUI
- EffectParams
- CodingKeys
- Kind
- Layer
- LayerStackListView.Coordinator
- OnionSkinLogicTests
- TextSettingsPanel
- FillGestureRestartLogicTests
- TextRecipeCodableLogicTests
- TimelineLayoutKeyLogicTests
- Recording
- .coverage
- ShapeHoldClock
- BlockDragCharacterizationTests
- 1. The decisions
- PerfMonitor
- Foundation
- InterpolateBar
- PaintSoftware - iPad Drawing and Animation App
- DeformFactorization
- TextLayout
- .backfillMissingThumbnails
- CanvasPresentationLogicTests
- .draw
- CanvasSizePickerView
- SideToolbar
- MenuInterruptionUITests
- bash
- .refreshUndoRedoState
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView
- .sample
- StructureSnapshot
- CanvasHostView
- .relayout
- Performance
- TimelineLayoutKey
- CLAUDE.md
- String
- StrokeStabilizer
- CanvasManager
- SelectPanel
- 4. Future upgrades — the deferred list
- Every dismissible presentation, and whether a stroke under it breaks
- Lasso Fill — Specification
- .sampledColor
- .frames
- Multi-Session Protocol
- CutOutcome
- Kind
- .row
- TransformOverlaySupport.swift
- Handoff — 2026-08-20
- 6. Alpha masks
- command
- ProjectStore.swift
- JSONValue
- CompositeProbe
- Kind
- RecordingWriter
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- ToolPanelsUITests
- parallel_test.sh
- SandwichPresentation
- Performance baseline
- TODO
- Kind
- MenuRequest
- simlock.sh
- TextLayout.swift
- cleanup_session.sh
- screenshot.sh
- Prompt for the next session
- .render
- HistoryNoticeUITests
- .bytes
- presentation-census.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- ThumbnailRenderer.swift

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 700 edges
2. `CGFloat` - 525 edges
3. `CanvasManager` - 168 edges
4. `VectorCanvas` - 154 edges
5. `Effect` - 149 edges
6. `layers` - 126 edges
7. `VectorSample` - 120 edges
8. `Coordinator` - 115 edges
9. `ShapeGeometry` - 109 edges
10. `CanvasManager` - 100 edges

## Surprising Connections (you probably didn't know these)
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `PerfBaselineTests` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (210 total, 18 thin omitted)

### Community 0 - "CGFloat"
Cohesion: 0.04
Nodes (37): CGFloat, ClosedFit, ShapeDetector, Bool, CGRect, Int, Corner, bottomLeft (+29 more)

### Community 1 - "CanvasManager"
Cohesion: 0.03
Nodes (74): Never, Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+66 more)

### Community 2 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 3 - "CanvasManager"
Cohesion: 0.04
Nodes (54): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+46 more)

### Community 4 - "LassoFillLogicTests"
Cohesion: 0.06
Nodes (32): MTLBuffer, MTLCommandBuffer, LassoFillMask, Float, Int, SIMD4, UInt8, FillParams (+24 more)

### Community 5 - "Lattice"
Cohesion: 0.06
Nodes (34): CodingKeys, activeCells, cellSize, cols, originX, originY, rows, vertices (+26 more)

### Community 6 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 7 - "InterpolationGuideLogicTests"
Cohesion: 0.07
Nodes (13): GuideHandles, GuideSet, .isEmpty, Bool, Int, TimedSample, .point, InterpolationGuideLogicTests (+5 more)

### Community 8 - "ProjectBackupManager"
Cohesion: 0.07
Nodes (37): DateFormatter, Decodable, Cel, Layer, ManifestSkeleton, ProjectBackup, .id, ProjectBackupManager (+29 more)

### Community 9 - "String"
Cohesion: 0.03
Nodes (86): CaseIterable, Error, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+78 more)

### Community 10 - "PerfBaselineTests"
Cohesion: 0.08
Nodes (18): CompositorBudget, .textureBudgetBytes, Int, UInt64, Atomic, .value, PerfBaselineTests, Bool (+10 more)

### Community 11 - "CGPoint"
Cohesion: 0.06
Nodes (21): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+13 more)

### Community 12 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (41): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+33 more)

### Community 13 - "ARAPLogicTests"
Cohesion: 0.06
Nodes (20): ARAPInterpolation, Interpolator, Options, Bool, Matrix2x2, .determinant, .isFinite, .polar (+12 more)

### Community 14 - "VectorCanvas"
Cohesion: 0.07
Nodes (46): Identifiable, VectorTextElement, CodableColor, .uiColor, image, kind, Kind, fill (+38 more)

### Community 15 - "VectorSample"
Cohesion: 0.05
Nodes (31): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+23 more)

### Community 16 - "PointCloudIndex"
Cohesion: 0.08
Nodes (21): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+13 more)

### Community 17 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (12): CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int, StaticString, String (+4 more)

### Community 18 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 19 - "Coordinator"
Cohesion: 0.06
Nodes (28): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, Coordinator, .canvasContentScale, .isLassoFilling (+20 more)

### Community 20 - "VectorEraserLogicTests"
Cohesion: 0.07
Nodes (9): StaticString, String, UInt, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests (+1 more)

### Community 21 - "InterpolationRecipe"
Cohesion: 0.07
Nodes (22): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+14 more)

### Community 22 - "Brush"
Cohesion: 0.08
Nodes (18): Brush, BrushDynamics, BrushGrain, Bool, Double, UUID, Sweep, Bool (+10 more)

### Community 23 - "AlphaMask"
Cohesion: 0.08
Nodes (11): AlphaMask, .isActive, Bool, Int, MaskParityLogicTests, .side, Bool, CanvasManager (+3 more)

### Community 24 - "AnimationTimeline"
Cohesion: 0.04
Nodes (50): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+42 more)

### Community 25 - ".setBakedContent"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 26 - ".launchIntoEditor"
Cohesion: 0.12
Nodes (12): BlendModesAndCompositorUITests, LayerPanelUITests, SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String (+4 more)

### Community 27 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (38): Hashable, Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+30 more)

### Community 28 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (27): CAShapeLayer, StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush (+19 more)

### Community 29 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 30 - "PaintUITestCase"
Cohesion: 0.08
Nodes (15): FillLiveAdjustUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests, Bool (+7 more)

### Community 31 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 32 - "CompositorMetalEngine"
Cohesion: 0.09
Nodes (33): Admission, admitted, noHeadroom, overBudget, Attempt, image, unavailable, underPressure (+25 more)

### Community 33 - "CodingKeys"
Cohesion: 0.05
Nodes (44): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+36 more)

### Community 34 - "ProjectSaveLogicTests"
Cohesion: 0.11
Nodes (13): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase (+5 more)

### Community 35 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (7): Layer, UInt, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 36 - "ProjectStore"
Cohesion: 0.09
Nodes (36): CFAbsoluteTime, BrushLibrary, .customBrushesDirectory, URL, CelContent, DecodedCels, LayerContent, LoadProfile (+28 more)

### Community 37 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 38 - "UIKit"
Cohesion: 0.08
Nodes (5): CoreGraphics, Darwin, simd, UIKit, XCTest

### Community 39 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 40 - ".rasterize"
Cohesion: 0.10
Nodes (25): FloatingPiece, .transformedBounds, CGRect, CGSize, IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache (+17 more)

### Community 41 - "Effect"
Cohesion: 0.08
Nodes (33): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+25 more)

### Community 42 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 43 - "Binding"
Cohesion: 0.07
Nodes (39): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+31 more)

### Community 44 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 45 - ".drawLine"
Cohesion: 0.13
Nodes (9): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, EraserAndPersistenceUITests (+1 more)

### Community 46 - "CanvasManager"
Cohesion: 0.08
Nodes (22): UUID, CanvasManager, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform, Selection (+14 more)

### Community 47 - "Codable"
Cohesion: 0.10
Nodes (29): Codable, Kind, folder, layer, Decoder, ValueFill, CompositorRole, node (+21 more)

### Community 48 - "TextFrame"
Cohesion: 0.07
Nodes (31): Int, Alignment, center, .displayName, .id, justified, left, right (+23 more)

### Community 49 - "XCTestCase"
Cohesion: 0.10
Nodes (11): CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor (+3 more)

### Community 50 - "CanvasManager"
Cohesion: 0.11
Nodes (20): CanvasManager, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel, CGPath (+12 more)

### Community 51 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 52 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 53 - "RasterLayerTexture"
Cohesion: 0.10
Nodes (21): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses (+13 more)

### Community 54 - "Fill.metal"
Cohesion: 0.17
Nodes (40): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+32 more)

### Community 55 - "RenderRequest"
Cohesion: 0.10
Nodes (27): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, RenderResolution, full (+19 more)

### Community 56 - "View"
Cohesion: 0.14
Nodes (29): View, .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex (+21 more)

### Community 57 - "RenderTreeCharacterizationTests"
Cohesion: 0.14
Nodes (7): StaticString, String, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 58 - "TextBakeCharacterizationTests"
Cohesion: 0.17
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 59 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+13 more)

### Community 60 - ".solidImage"
Cohesion: 0.08
Nodes (11): Eyedropper, Sample, CGSize, Double, Int, UInt8, CGSize, UIColor (+3 more)

### Community 61 - "FontFace"
Cohesion: 0.12
Nodes (18): FontFace, .descriptor, .id, FontFamilyGroup, .id, FontLibrary, FontProvider, FontResolution (+10 more)

### Community 62 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+4 more)

### Community 63 - "layers"
Cohesion: 0.15
Nodes (12): .activeLayerIsVector, CanvasManager, Bool, Int, Cel, .endFrame, .isCertainlyBlank, Bool (+4 more)

### Community 64 - "InterpolationRenderLogicTests"
Cohesion: 0.18
Nodes (9): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int, UIImage, UUID (+1 more)

### Community 65 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 66 - "VectorCanvasDataLogicTests"
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 67 - "CodingKey"
Cohesion: 0.06
Nodes (35): CodingKey, CodingKeys, endPoint, kind, rotation, spanStart, spanSweep, startPoint (+27 more)

### Community 68 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 69 - "VectorEraserMode"
Cohesion: 0.07
Nodes (24): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+16 more)

### Community 70 - "TextOverlayView"
Cohesion: 0.10
Nodes (16): RenderKey, Bool, CGRect, CGSize, NSCoder, Set, String, UIEvent (+8 more)

### Community 71 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 72 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 73 - "Typography"
Cohesion: 0.19
Nodes (8): UIFont, ClosedRange, Typography, .clamped, Int, String, UIFont, TextLayoutLogicTests

### Community 74 - "UndoHistory"
Cohesion: 0.12
Nodes (15): Action, Bool, Int, UInt64, Void, UndoBudget, .maxCostBytes, UndoHistory (+7 more)

### Community 75 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 76 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 77 - "LayerRowModel"
Cohesion: 0.15
Nodes (17): DispatchWorkItem, Coordinator, LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, CanvasManager (+9 more)

### Community 78 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 79 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 80 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 81 - "MaskSource"
Cohesion: 0.12
Nodes (13): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, Void (+5 more)

### Community 82 - ".compositeSize"
Cohesion: 0.11
Nodes (12): NSObjectProtocol, .resolutionNoteText, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel (+4 more)

### Community 83 - "CurveEditor"
Cohesion: 0.13
Nodes (18): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+10 more)

### Community 84 - "TimelineRowView"
Cohesion: 0.13
Nodes (17): Kind, cel, gap, Segment, Cel, Int, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 85 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (13): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+5 more)

### Community 86 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 87 - ".rows"
Cohesion: 0.15
Nodes (19): CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections(), effectMenuSlug() (+11 more)

### Community 88 - "GalleryOpenState"
Cohesion: 0.14
Nodes (13): GalleryOpenState, .isBusy, Bool, UUID, GalleryTileView, .body, Bool, Void (+5 more)

### Community 89 - "OnionSkinSettings"
Cohesion: 0.16
Nodes (12): .gradientStops, .opacitySliders, OnionSkinSettings, Side, .id, next, previous, .step (+4 more)

### Community 90 - "ContentView"
Cohesion: 0.09
Nodes (17): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+9 more)

### Community 91 - "Known Issues"
Cohesion: 0.07
Nodes (27): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A lasso fill does not paint over line art on a *raster* layer either, for the same-layer case (2026-08-17), A lasso fill does not paint over line art on a *vector* layer (2026-08-17), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), Cleanup opportunities, Drawing on a vector layer at 4K was capped at ~19 fps by the live stroke preview — FIXED 2026-08-20 (+19 more)

### Community 92 - "TextHitTestLogicTests"
Cohesion: 0.18
Nodes (6): Bool, CGAffineTransform, CGSize, String, VectorStroke, TextHitTestLogicTests

### Community 93 - "CanvasPresentation"
Cohesion: 0.09
Nodes (20): CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id, interpolateOptions (+12 more)

### Community 94 - "EffectParityLogicTests"
Cohesion: 0.20
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 95 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 96 - "VectorTransformUndoLogicTests"
Cohesion: 0.24
Nodes (8): CanvasManager, CGAffineTransform, Int, LayerTransform, StaticString, String, UInt, VectorTransformUndoLogicTests

### Community 97 - "VectorCanvasData"
Cohesion: 0.24
Nodes (6): .elements, VectorCanvasData, String, UUID, VectorStroke, VectorTextPersistenceLogicTests

### Community 98 - "GuideStroke"
Cohesion: 0.11
Nodes (16): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+8 more)

### Community 99 - "OnionSkinPanel"
Cohesion: 0.11
Nodes (21): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+13 more)

### Community 100 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 101 - "EffectPipelines"
Cohesion: 0.12
Nodes (17): Metal, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue (+9 more)

### Community 102 - "SpacingChart"
Cohesion: 0.11
Nodes (10): GuidePath, .end, .start, SpacingChart, .curve, .draggable, CGVector, Range (+2 more)

### Community 103 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 104 - "Coordinator"
Cohesion: 0.17
Nodes (9): BlockDrag, CelBlockView, Coordinator, Bool, CanvasManager, Coordinator, UIImage, Void (+1 more)

### Community 105 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 106 - "WindowEventTap"
Cohesion: 0.19
Nodes (9): AnyClass, NSObject, FoundElement, InstallReport, CGRect, UIEvent, WindowEventTap, UIAccessibilityTraits (+1 more)

### Community 107 - "DrawingView"
Cohesion: 0.09
Nodes (18): CanvasNoticeBanner, .body, .icon, String, Void, DrawingView, .body, .panelAlignment (+10 more)

### Community 108 - "VectorPreviewPlanLogicTests"
Cohesion: 0.13
Nodes (11): Bool, String, VectorPreviewPlan, VectorScratchRole, none, overlay, replacement, .traceName (+3 more)

### Community 109 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 110 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 111 - ".makeUIView"
Cohesion: 0.12
Nodes (9): AppliedTool, CanvasView, CanvasManager, Color, Context, Coordinator, Double, LayerTransform (+1 more)

### Community 112 - ".setUpGestures"
Cohesion: 0.13
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 113 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 114 - "OnionSkinSource.swift"
Cohesion: 0.13
Nodes (9): tinted, OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager, StaticString, UIImage, UInt (+1 more)

### Community 115 - "Int"
Cohesion: 0.21
Nodes (6): OnionSkinBudget, OnionSkinOpacityRamp, CGSize, Double, Int, Int

### Community 116 - "FontResolveLogicTests"
Cohesion: 0.21
Nodes (5): FontResolveLogicTests, StubFontProvider, Bool, String, UIFont

### Community 117 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 118 - "Layer Compositing"
Cohesion: 0.09
Nodes (22): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+14 more)

### Community 119 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 120 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 121 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 122 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

### Community 123 - "CGRect"
Cohesion: 0.21
Nodes (10): CGRect, ClosedRange, NSCoder, String, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView (+2 more)

### Community 124 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 125 - "SwiftUI"
Cohesion: 0.14
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 126 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 127 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 128 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 129 - "Layer"
Cohesion: 0.10
Nodes (17): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+9 more)

### Community 130 - "LayerStackListView.Coordinator"
Cohesion: 0.15
Nodes (11): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, ObjectIdentifier, TimeInterval, UIGestureRecognizer (+3 more)

### Community 131 - "OnionSkinLogicTests"
Cohesion: 0.22
Nodes (4): CelSpan, .end, OnionSkinPlanner, OnionSkinLogicTests

### Community 132 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 133 - "FillGestureRestartLogicTests"
Cohesion: 0.25
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 134 - "TextRecipeCodableLogicTests"
Cohesion: 0.17
Nodes (5): StaticString, String, T, UInt, TextRecipeCodableLogicTests

### Community 135 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.27
Nodes (3): CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 136 - "Recording"
Cohesion: 0.13
Nodes (14): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderIndicator, .body (+6 more)

### Community 137 - ".coverage"
Cohesion: 0.27
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 138 - "ShapeHoldClock"
Cohesion: 0.21
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 139 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 140 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 141 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 142 - "Foundation"
Cohesion: 0.11
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 143 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 144 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.11
Nodes (18): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+10 more)

### Community 145 - "DeformFactorization"
Cohesion: 0.22
Nodes (9): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Double, Int, Int32, SparseMatrix_Double (+1 more)

### Community 146 - "TextLayout"
Cohesion: 0.23
Nodes (11): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGRect (+3 more)

### Community 147 - ".backfillMissingThumbnails"
Cohesion: 0.20
Nodes (10): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+2 more)

### Community 148 - "CanvasPresentationLogicTests"
Cohesion: 0.15
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 149 - ".draw"
Cohesion: 0.34
Nodes (7): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 150 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 151 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 152 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 153 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 155 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 156 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 157 - "LayerStackListView"
Cohesion: 0.16
Nodes (9): IndexPath, .body, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView (+1 more)

### Community 158 - ".sample"
Cohesion: 0.27
Nodes (9): ObjectiveC.runtime, ResolvedTarget, Bool, CGSize, Double, Int, UITouch, TouchSample (+1 more)

### Community 159 - "StructureSnapshot"
Cohesion: 0.23
Nodes (4): CanvasManager, StructureSnapshot, Int, Layer

### Community 160 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 161 - ".relayout"
Cohesion: 0.23
Nodes (6): Context, UIPinchGestureRecognizer, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 162 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 163 - "TimelineLayoutKey"
Cohesion: 0.29
Nodes (12): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+4 more)

### Community 165 - "String"
Cohesion: 0.32
Nodes (6): Entry, ObjectIdentifier, Set, String, UIGestureRecognizer, UIView

### Community 166 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 167 - "CanvasManager"
Cohesion: 0.23
Nodes (6): CanvasManager, .activeEditColor, .isTextInAdjustableState, Bool, Color, String

### Community 168 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 169 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 170 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.18
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 171 - "Lasso Fill — Specification"
Cohesion: 0.20
Nodes (10): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill, 8. Open risks (+2 more)

### Community 172 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 173 - ".frames"
Cohesion: 0.20
Nodes (3): CGRect, Range, TimelineRulerClip

### Community 174 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 175 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 176 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 177 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 178 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 179 - "Handoff — 2026-08-20"
Cohesion: 0.25
Nodes (7): Five things this pass learned the hard way, Handoff — 2026-08-20, The numbers worth knowing, What is worth doing next, What needs the owner's iPad, What shipped, What the owner owes a ruling on

### Community 180 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 181 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 182 - "ProjectStore.swift"
Cohesion: 0.38
Nodes (6): os, CodableColor, .color, Color, .codable, CodableColor

### Community 183 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 185 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 187 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 189 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 190 - "SandwichPresentation"
Cohesion: 0.40
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 191 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 192 - "TODO"
Cohesion: 0.40
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 193 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 194 - "MenuRequest"
Cohesion: 0.50
Nodes (4): MenuRequest, block, gap, loop

### Community 195 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **985 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+980 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **18 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `CanvasManager`, `cels`, `CanvasManager`, `LassoFillLogicTests`, `Lattice`, `InterpolationGuideLogicTests`, `String`, `PerfBaselineTests`, `CGPoint`, `VectorEraserHybridLogicTests`, `ARAPLogicTests`, `VectorCanvas`, `VectorSample`, `PointCloudIndex`, `CompositorParityLogicTests`, `Coordinator`, `VectorEraserLogicTests`, `InterpolationRecipe`, `Brush`, `AlphaMask`, `AnimationTimeline`, `.setBakedContent`, `.launchIntoEditor`, `StrokeCanvasView`, `PaintUITestCase`, `SandwichLogicTests`, `ProjectStore`, `ShapeOverlayView`, `.rasterize`, `Binding`, `.apply`, `CanvasManager`, `TextFrame`, `CanvasManager`, `BrushEngineLogicTests`, `RasterLayerTexture`, `RenderRequest`, `TextBakeCharacterizationTests`, `.evaluate`, `FontFace`, `LayerStackCell`, `layers`, `InterpolationRenderLogicTests`, `VectorCanvasDataLogicTests`, `TextOverlayView`, `ActionRecorder`, `Typography`, `GuideOverlayView`, `LayerRowModel`, `StrokeSpatialIndex`, `.compositeSize`, `CurveEditor`, `TimelineRowView`, `FloatingPieceOverlayView`, `TextHitTestLogicTests`, `VectorTransformUndoLogicTests`, `GuideStroke`, `SpacingChart`, `Coordinator`, `XCUIApplication`, `WindowEventTap`, `DrawingView`, `PinchMergeGateLogicTests`, `.makeUIView`, `OnionSkinSource.swift`, `Int`, `FontResolveLogicTests`, `CanvasManager`, `ObjectTransformOverlayView`, `CGRect`, `CanvasTransformFreezeUITests`, `CodingKeys`, `TextSettingsPanel`, `TimelineLayoutKeyLogicTests`, `InterpolateBar`, `DeformFactorization`, `TextLayout`, `.draw`, `SideToolbar`, `ActionsMenu`, `LayerStackListView`, `.sample`, `.relayout`, `TimelineLayoutKey`, `StrokeStabilizer`, `.frames`, `TransformOverlaySupport.swift`, `JSONValue`, `Kind`, `SandwichPresentation`?**
  _High betweenness centrality (0.273) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `CGFloat`, `CanvasManager`, `LayerStackListView.Coordinator`, `CanvasManager`, `cels`, `Lattice`, `.manager`, `InterpolationGuideLogicTests`, `FillGestureRestartLogicTests`, `LassoFillLogicTests`, `PerfBaselineTests`, `TextRecipeCodableLogicTests`, `VectorEraserHybridLogicTests`, `ARAPLogicTests`, `VectorCanvas`, `VectorSample`, `PointCloudIndex`, `DeformFactorization`, `TextLayout`, `Coordinator`, `VectorEraserLogicTests`, `InterpolationRecipe`, `Brush`, `AlphaMask`, `AnimationTimeline`, `.refreshUndoRedoState`, `ColorPickerPanel`, `StrokeCanvasView`, `.sample`, `ProjectSaveLogicTests`, `SelectionOverlayView`, `StrokeStabilizer`, `CanvasManager`, `.rasterize`, `ShapeOverlayView`, `.sampledColor`, `.frames`, `CanvasManager`, `String`, `TextFrame`, `CanvasManager`, `TransformOverlaySupport.swift`, `BrushEngineLogicTests`, `RasterLayerTexture`, `TextBakeCharacterizationTests`, `.evaluate`, `.solidImage`, `SandwichPresentation`, `layers`, `InterpolationRenderLogicTests`, `TextOverlayView`, `Typography`, `GuideOverlayView`, `StrokeSpatialIndex`, `CurveEditor`, `TimelineRowView`, `FloatingPieceOverlayView`, `TextHitTestLogicTests`, `VectorTransformUndoLogicTests`, `VectorCanvasData`, `GuideStroke`, `SpacingChart`, `Coordinator`, `WindowEventTap`, `.makeUIView`, `.setUpGestures`, `ObjectTransformOverlayView`, `CGRect`?**
  _High betweenness centrality (0.175) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `CGFloat`, `cels`, `OnionSkinLogicTests`, `LassoFillLogicTests`, `FillGestureRestartLogicTests`, `.manager`, `InterpolationGuideLogicTests`, `ProjectBackupManager`, `Lattice`, `PerfBaselineTests`, `BlockDragCharacterizationTests`, `VectorEraserHybridLogicTests`, `ARAPLogicTests`, `ShapeHoldClock`, `CGPoint`, `PointCloudIndex`, `CompositorParityLogicTests`, `VectorSample`, `CanvasPresentationLogicTests`, `InterpolationRecipe`, `VectorEraserLogicTests`, `AlphaMask`, `.setBakedContent`, `StrokeGestureRecognizer`, `PaintUITestCase`, `SandwichLogicTests`, `ProjectSaveLogicTests`, `LayerTreeCharacterizationTests`, `TextRecipeCodableLogicTests`, `SelectionOverlayView`, `UIKit`, `TimelineLayoutKeyLogicTests`, `EffectMultiPassLogicTests`, `BrushEngineLogicTests`, `RenderTreeCharacterizationTests`, `TextBakeCharacterizationTests`, `.solidImage`, `InterpolationRenderLogicTests`, `FillBoundaryLogicTests`, `VectorCanvasDataLogicTests`, `VectorEraserMode`, `Typography`, `UndoHistory`, `PlaybackBoundsCharacterizationTests`, `GalleryOpenState`, `TextHitTestLogicTests`, `EffectParityLogicTests`, `CanvasNotice`, `VectorTransformUndoLogicTests`, `VectorCanvasData`, `VectorPreviewPlanLogicTests`, `PinchMergeGateLogicTests`, `FontResolveLogicTests`, `MaskGuardLogicTests`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Are the 81 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 81 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 23 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 23 INFERRED edges - model-reasoned connections that need verification._