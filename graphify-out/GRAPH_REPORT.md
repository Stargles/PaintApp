# Graph Report - PaintApp-tierc  (2026-08-20)

## Corpus Check
- 233 files · ~723,326 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6861 nodes · 20850 edges · 223 communities (205 shown, 18 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2079 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6da92d73`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Brush
- cels
- CGPoint
- LassoFillLogicTests
- Lattice
- .manager
- ProjectBackupManager
- AlphaMask
- CanvasManager
- VectorCanvas
- .setBakedContent
- PointCloudIndex
- Codable
- HistoryActionLabel
- CGFloat
- layers
- PerfBaselineTests
- Coordinator
- ARAPLogicTests
- VectorEraserLogicTests
- EffectLayerLogicTests
- SandwichLogicTests
- .report
- StrokeGestureRecognizer
- CompositorMetalEngine
- CanvasManager
- AnimationTimeline
- StrokeCanvasView
- LayerTreeCharacterizationTests
- .drawLine
- SelectionOverlayView
- .reconcileLayers
- ProjectStore
- UIKit
- BrushEngineLogicTests
- VectorStroke
- VectorCanvasData
- ProjectSaveLogicTests
- .rasterize
- ShapeOverlayView
- Effect
- TextFrame
- EffectMultiPassLogicTests
- PaintUITestCase
- .apply
- CanvasManager
- LayerFolder
- CanvasManager
- OnionSkinLogicTests
- XCTestCase
- .launchIntoEditor
- Fill.metal
- LayerOptionsPanel
- TextBakeCharacterizationTests
- String
- .evaluate
- InterpolationRenderLogicTests
- RenderRequest
- VectorSample
- FontFace
- .withStructureUndo
- View
- ValueLayerLogicTests
- VectorEraserHybridLogicTests
- ObjectTransformOverlayView
- FillBoundaryLogicTests
- VectorCanvasDataLogicTests
- RenderNode
- VectorEraserMode
- TextOverlayView
- agent
- ActionRecorder
- InterpolationRecipe
- Typography
- MaskSource
- InterpolationModelLogicTests
- PlaybackBoundsCharacterizationTests
- Composite.metal
- ProjectManifest
- PaletteColor
- StrokeSpatialIndex
- RasterLayerTexture
- GuideOverlayView
- LayerStackCell
- BlendMode
- CodingKey
- EyedropperLogicTests
- GuideStroke
- Layer Compositing
- .compositeSize
- TimelineRowView
- Known Issues
- CodingKeys
- GalleryOpenState
- WindowEventTap
- TextHitTestLogicTests
- DrawingView
- OnionSkinSettings
- EffectParityLogicTests
- CanvasNotice
- ActivePanel
- InterpolationGuideLogicTests
- Binding
- CodingKeys
- OnionSkinPanel
- Coordinator
- XCUIApplication
- EffectPipelines
- BrushSettingsPanel
- ColorPickerPanel
- VectorPreviewPlanLogicTests
- .rows
- FloatingPieceOverlayView
- .sample
- Compositor.swift
- PinchMergeGateLogicTests
- .refreshUndoRedoState
- FontResolveLogicTests
- Gesture
- read
- .indices
- MaskGuardLogicTests
- CanvasManager
- GradientStopsEditor
- CurveEditor
- ContentView
- SwiftUI
- .image
- InterpolationRefusal
- CGRect
- CanvasTransformFreezeUITests
- SandwichCompositingUITests
- EffectParams
- ShapeHoldClock
- CodingKeys
- Layer
- Coordinator
- TextSettingsPanel
- FillGestureRestartLogicTests
- TimelineLayoutKeyLogicTests
- .backfillMissingThumbnails
- StructureSnapshot
- BlockDragCharacterizationTests
- 1. The decisions
- PerfMonitor
- .arched
- TimedSample
- InterpolateBar
- PaintSoftware - iPad Drawing and Animation App
- TextLayout
- CanvasPresentation
- MemoryBudgetLogicTests
- UndoHistory
- LayerRowModel
- CanvasPresentationLogicTests
- Foundation
- Recording
- .draw
- CanvasSizePickerView
- SideToolbar
- .manager
- MenuInterruptionUITests
- bash
- MotionGroup
- CompositorRole
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- CGContextDabTarget
- CanvasHostView
- .relayout
- Performance
- GuidePath
- TimelineLayoutKey
- CLAUDE.md
- SpacingChart
- StrokeStabilizer
- .savesFired
- SelectPanel
- 4. Future upgrades — the deferred list
- Every dismissible presentation, and whether a stroke under it breaks
- Lasso Fill — Specification
- .sampledColor
- CanvasPresentationModifier
- .attach
- .frames
- Multi-Session Protocol
- BrushBlendMode
- .textureBudgetBytes
- CutOutcome
- Kind
- .row
- Alignment
- Handoff — 2026-08-20
- Corner
- command
- ProjectStore.swift
- JSONValue
- Kind
- InterpolatePanel
- RecordingWriter
- CompositeProbe
- .handleShouldReceive
- Atomic
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- ToolPanelsUITests
- parallel_test.sh
- .waitForDisappearance
- Performance baseline
- TODO
- MenuRequest
- simlock.sh
- TextLayout.swift
- cleanup_session.sh
- screenshot.sh
- Prompt for the next session
- .init
- .render
- presentation-census.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 686 edges
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

## Communities (223 total, 18 thin omitted)

### Community 0 - "Brush"
Cohesion: 0.04
Nodes (29): Brush, BrushDynamics, BrushGrain, Bool, Double, UUID, Capsule, .boundingBox (+21 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 2 - "CGPoint"
Cohesion: 0.05
Nodes (34): CGPoint, .length, Int, Corner, bottomLeft, bottomRight, topLeft, topRight (+26 more)

### Community 3 - "LassoFillLogicTests"
Cohesion: 0.06
Nodes (32): MTLBuffer, MTLCommandBuffer, LassoFillMask, Float, Int, SIMD4, UInt8, FillParams (+24 more)

### Community 4 - "Lattice"
Cohesion: 0.05
Nodes (34): CodingKeys, activeCells, cellSize, cols, originX, originY, rows, vertices (+26 more)

### Community 5 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 6 - "ProjectBackupManager"
Cohesion: 0.06
Nodes (37): DateFormatter, Decodable, Cel, Layer, ManifestSkeleton, ProjectBackup, .id, ProjectBackupManager (+29 more)

### Community 7 - "AlphaMask"
Cohesion: 0.06
Nodes (18): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8, AlphaMask (+10 more)

### Community 8 - "CanvasManager"
Cohesion: 0.04
Nodes (47): Never, Void, CanvasManager, .activeContainerID, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes (+39 more)

### Community 9 - "VectorCanvas"
Cohesion: 0.06
Nodes (48): VectorTextElement, CodableColor, .uiColor, image, kind, DecodeReport, .droppedCount, .isClean (+40 more)

### Community 10 - ".setBakedContent"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 11 - "PointCloudIndex"
Cohesion: 0.08
Nodes (21): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+13 more)

### Community 12 - "Codable"
Cohesion: 0.04
Nodes (66): Codable, CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma (+58 more)

### Community 13 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 14 - "CGFloat"
Cohesion: 0.06
Nodes (29): Accelerate, bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, DeformDataRow (+21 more)

### Community 15 - "layers"
Cohesion: 0.08
Nodes (25): CanvasManager, .activeCelIsInBetween, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationOptions (+17 more)

### Community 16 - "PerfBaselineTests"
Cohesion: 0.11
Nodes (9): PerfBaselineTests, Bool, CanvasManager, CGSize, Double, Int, String, UInt64 (+1 more)

### Community 17 - "Coordinator"
Cohesion: 0.06
Nodes (34): AppliedTool, CanvasView, Coordinator, .canvasContentScale, .isLassoFilling, .sandwichPresentation, OnionSkinKey, SandwichPresentation (+26 more)

### Community 18 - "ARAPLogicTests"
Cohesion: 0.08
Nodes (15): ARAPInterpolation, Interpolator, Options, Bool, Group, MotionGrouping, Options, Bool (+7 more)

### Community 19 - "VectorEraserLogicTests"
Cohesion: 0.09
Nodes (8): VectorEraser, Set, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 20 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 21 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 22 - ".report"
Cohesion: 0.08
Nodes (36): CustomStringConvertible, UUID, UIImage, UInt8, Backdrop, fill, image, none (+28 more)

### Community 23 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 24 - "CompositorMetalEngine"
Cohesion: 0.09
Nodes (33): Admission, admitted, noHeadroom, overBudget, Attempt, image, unavailable, underPressure (+25 more)

### Community 25 - "CanvasManager"
Cohesion: 0.07
Nodes (32): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+24 more)

### Community 26 - "AnimationTimeline"
Cohesion: 0.05
Nodes (44): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+36 more)

### Community 27 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (24): CAShapeLayer, StrokeInput, TimeInterval, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster (+16 more)

### Community 28 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (6): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 29 - ".drawLine"
Cohesion: 0.11
Nodes (11): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement (+3 more)

### Community 30 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 31 - ".reconcileLayers"
Cohesion: 0.06
Nodes (19): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, NSCoder, InterpolationPreviewKey, SandwichKey (+11 more)

### Community 32 - "ProjectStore"
Cohesion: 0.09
Nodes (36): CFAbsoluteTime, BrushLibrary, .customBrushesDirectory, URL, CelContent, DecodedCels, LayerContent, LoadProfile (+28 more)

### Community 33 - "UIKit"
Cohesion: 0.08
Nodes (6): CoreGraphics, Darwin, ThumbnailRenderer, simd, UIKit, XCTest

### Community 34 - "BrushEngineLogicTests"
Cohesion: 0.11
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 35 - "VectorStroke"
Cohesion: 0.07
Nodes (27): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+19 more)

### Community 36 - "VectorCanvasData"
Cohesion: 0.09
Nodes (24): ElementData, fill, image, stroke, text, LossySlot, LossyValue, Outcome (+16 more)

### Community 37 - "ProjectSaveLogicTests"
Cohesion: 0.13
Nodes (11): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString, String (+3 more)

### Community 38 - ".rasterize"
Cohesion: 0.10
Nodes (25): Hashable, IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool (+17 more)

### Community 39 - "ShapeOverlayView"
Cohesion: 0.07
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 40 - "Effect"
Cohesion: 0.09
Nodes (32): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+24 more)

### Community 41 - "TextFrame"
Cohesion: 0.08
Nodes (23): FontDescriptor, Mode, affine, projective, Bool, CGRect, CGSize, CGVector (+15 more)

### Community 42 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 43 - "PaintUITestCase"
Cohesion: 0.10
Nodes (10): HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests, TimelineGestureUITests (+2 more)

### Community 44 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 45 - "CanvasManager"
Cohesion: 0.10
Nodes (21): CanvasManager, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel, CGPath (+13 more)

### Community 46 - "LayerFolder"
Cohesion: 0.08
Nodes (23): CelLocation, BlendMode, Double, UUID, CanvasManager, .activeViewName, Int, String (+15 more)

### Community 47 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 48 - "OnionSkinLogicTests"
Cohesion: 0.10
Nodes (14): CelSpan, .end, tinted, OnionSkinPlanner, OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager (+6 more)

### Community 49 - "XCTestCase"
Cohesion: 0.13
Nodes (9): StaticString, String, UInt, XCTestCase, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String (+1 more)

### Community 50 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, UndoAndLayerHistoryUITests

### Community 51 - "Fill.metal"
Cohesion: 0.17
Nodes (40): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+32 more)

### Community 52 - "LayerOptionsPanel"
Cohesion: 0.12
Nodes (28): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+20 more)

### Community 53 - "TextBakeCharacterizationTests"
Cohesion: 0.17
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 54 - "String"
Cohesion: 0.06
Nodes (39): CaseIterable, Error, BrushShape, custom, .displayName, hardRound, .id, pen (+31 more)

### Community 55 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+13 more)

### Community 56 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (12): StrokeComposite, erase, paint, fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor (+4 more)

### Community 57 - "RenderRequest"
Cohesion: 0.11
Nodes (24): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, RenderResolution, full (+16 more)

### Community 58 - "VectorSample"
Cohesion: 0.12
Nodes (9): VectorSample, .point, VectorStroke, CountingDabTarget, StrokeSampleGateLogicTests, CGBlendMode, UIColor, UInt64 (+1 more)

### Community 59 - "FontFace"
Cohesion: 0.12
Nodes (18): FontFace, .descriptor, .id, FontFamilyGroup, .id, FontLibrary, FontProvider, FontResolution (+10 more)

### Community 60 - ".withStructureUndo"
Cohesion: 0.12
Nodes (15): .interpolationTarget, CanvasManager, Bool, Int, Void, Cel, .endFrame, .isCertainlyBlank (+7 more)

### Community 61 - "View"
Cohesion: 0.10
Nodes (25): View, EffectSettingsMenu, .body, optionsSubMenuHeader(), ClosedRange, CodableColor, Double, String (+17 more)

### Community 62 - "ValueLayerLogicTests"
Cohesion: 0.14
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 63 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 64 - "ObjectTransformOverlayView"
Cohesion: 0.09
Nodes (23): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, FloatingTransform (+15 more)

### Community 65 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 66 - "VectorCanvasDataLogicTests"
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 67 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 68 - "VectorEraserMode"
Cohesion: 0.07
Nodes (24): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+16 more)

### Community 69 - "TextOverlayView"
Cohesion: 0.10
Nodes (16): RenderKey, Bool, CGRect, CGSize, NSCoder, Set, String, UIEvent (+8 more)

### Community 70 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 71 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 72 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 73 - "Typography"
Cohesion: 0.19
Nodes (8): UIFont, ClosedRange, Typography, .clamped, Int, String, UIFont, TextLayoutLogicTests

### Community 74 - "MaskSource"
Cohesion: 0.11
Nodes (16): Kind, folder, layer, MaskSource, folder, .id, layer, Decoder (+8 more)

### Community 75 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 76 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 77 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 78 - "ProjectManifest"
Cohesion: 0.16
Nodes (19): Decoder, ValueFill, CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, BlendMode (+11 more)

### Community 79 - "PaletteColor"
Cohesion: 0.14
Nodes (17): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+9 more)

### Community 80 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 81 - "RasterLayerTexture"
Cohesion: 0.16
Nodes (11): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+3 more)

### Community 82 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 83 - "LayerStackCell"
Cohesion: 0.09
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 84 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 85 - "CodingKey"
Cohesion: 0.07
Nodes (30): CodingKey, CodingKeys, endPoint, kind, rotation, spanStart, spanSweep, startPoint (+22 more)

### Community 86 - "EyedropperLogicTests"
Cohesion: 0.11
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 87 - "GuideStroke"
Cohesion: 0.10
Nodes (19): Identifiable, .guideChips, GuideChip, .id, CodingKeys, boundGroups, id, interval (+11 more)

### Community 88 - "Layer Compositing"
Cohesion: 0.07
Nodes (29): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+21 more)

### Community 89 - ".compositeSize"
Cohesion: 0.16
Nodes (7): .resolutionNoteText, OnionSkinBudget, OnionSkinOpacityRamp, CGSize, Double, Int, Int

### Community 90 - "TimelineRowView"
Cohesion: 0.13
Nodes (17): Kind, cel, gap, Segment, Cel, Int, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 91 - "Known Issues"
Cohesion: 0.07
Nodes (28): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A lasso fill does not paint over line art on a *raster* layer either, for the same-layer case (2026-08-17), A lasso fill does not paint over line art on a *vector* layer (2026-08-17), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), A vector layer's transform is not undoable at all (2026-08-20), Cleanup opportunities (+20 more)

### Community 92 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 93 - "GalleryOpenState"
Cohesion: 0.14
Nodes (13): GalleryOpenState, .isBusy, Bool, UUID, GalleryTileView, .body, Bool, Void (+5 more)

### Community 94 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 95 - "TextHitTestLogicTests"
Cohesion: 0.18
Nodes (6): Bool, CGAffineTransform, CGSize, String, VectorStroke, TextHitTestLogicTests

### Community 96 - "DrawingView"
Cohesion: 0.08
Nodes (20): ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void, DrawingView (+12 more)

### Community 97 - "OnionSkinSettings"
Cohesion: 0.17
Nodes (11): .gradientStops, .opacitySliders, OnionSkinSettings, Side, .id, next, previous, .step (+3 more)

### Community 98 - "EffectParityLogicTests"
Cohesion: 0.20
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 99 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 100 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 102 - "Binding"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, .body, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding (+12 more)

### Community 103 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 104 - "OnionSkinPanel"
Cohesion: 0.11
Nodes (21): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+13 more)

### Community 105 - "Coordinator"
Cohesion: 0.17
Nodes (9): BlockDrag, CelBlockView, Coordinator, Bool, CanvasManager, Coordinator, UIImage, Void (+1 more)

### Community 106 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 107 - "EffectPipelines"
Cohesion: 0.13
Nodes (17): Metal, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue (+9 more)

### Community 108 - "BrushSettingsPanel"
Cohesion: 0.10
Nodes (20): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+12 more)

### Community 109 - "ColorPickerPanel"
Cohesion: 0.13
Nodes (17): ColorPickerPanel, .body, .colorTab, .currentColor, .hexRow, .hueSlider, .palettesTab, .renameAlertBinding (+9 more)

### Community 110 - "VectorPreviewPlanLogicTests"
Cohesion: 0.13
Nodes (11): Bool, String, VectorPreviewPlan, VectorScratchRole, none, overlay, replacement, .traceName (+3 more)

### Community 111 - ".rows"
Cohesion: 0.14
Nodes (13): DispatchWorkItem, IndexPath, .rows, DropTarget, between, onto, LayerStackListView.Coordinator, CGRect (+5 more)

### Community 112 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 113 - ".sample"
Cohesion: 0.18
Nodes (13): NSObject, ObjectiveC.runtime, FoundElement, ResolvedTarget, Bool, CGRect, CGSize, Double (+5 more)

### Community 114 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 115 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 116 - ".refreshUndoRedoState"
Cohesion: 0.13
Nodes (8): UUID, VectorStroke, CanvasManager, .activeEditColor, .isTextInAdjustableState, Bool, Color, String

### Community 117 - "FontResolveLogicTests"
Cohesion: 0.21
Nodes (5): FontResolveLogicTests, StubFontProvider, Bool, String, UIFont

### Community 118 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 119 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 121 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 122 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 123 - "GradientStopsEditor"
Cohesion: 0.13
Nodes (18): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+10 more)

### Community 124 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 125 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 126 - "SwiftUI"
Cohesion: 0.13
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 127 - ".image"
Cohesion: 0.16
Nodes (10): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, Cel, ObjectIdentifier, UIColor (+2 more)

### Community 128 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 129 - "CGRect"
Cohesion: 0.21
Nodes (10): CGRect, ClosedRange, NSCoder, String, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView (+2 more)

### Community 130 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 131 - "SandwichCompositingUITests"
Cohesion: 0.25
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 132 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 133 - "ShapeHoldClock"
Cohesion: 0.19
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 134 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 135 - "Layer"
Cohesion: 0.10
Nodes (17): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+9 more)

### Community 136 - "Coordinator"
Cohesion: 0.22
Nodes (9): Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID, Void (+1 more)

### Community 137 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 138 - "FillGestureRestartLogicTests"
Cohesion: 0.25
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 139 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.27
Nodes (3): CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 140 - ".backfillMissingThumbnails"
Cohesion: 0.18
Nodes (10): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+2 more)

### Community 141 - "StructureSnapshot"
Cohesion: 0.16
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, guideStrokes

### Community 142 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 143 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 144 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 145 - ".arched"
Cohesion: 0.27
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 146 - "TimedSample"
Cohesion: 0.17
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 147 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 148 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.11
Nodes (18): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+10 more)

### Community 149 - "TextLayout"
Cohesion: 0.23
Nodes (11): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGRect (+3 more)

### Community 150 - "CanvasPresentation"
Cohesion: 0.12
Nodes (14): CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id, interpolateOptions (+6 more)

### Community 151 - "MemoryBudgetLogicTests"
Cohesion: 0.18
Nodes (7): UInt64, UndoBudget, .maxCostBytes, MemoryBudgetLogicTests, Int, String, UInt64

### Community 152 - "UndoHistory"
Cohesion: 0.24
Nodes (8): Action, Bool, Int, Void, UndoHistory, .canRedo, .canUndo, .currentCost

### Community 153 - "LayerRowModel"
Cohesion: 0.15
Nodes (13): UIColor, Kind, compositorNode, group, layer, LayerRowModel, .folderID, .isFolder (+5 more)

### Community 154 - "CanvasPresentationLogicTests"
Cohesion: 0.15
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 155 - "Foundation"
Cohesion: 0.12
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 156 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 157 - ".draw"
Cohesion: 0.34
Nodes (7): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 158 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 159 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 161 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 162 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 163 - "MotionGroup"
Cohesion: 0.18
Nodes (11): GroupRegistration, Layer, String, GroupInterpolation, auto, clean, crossFade, MotionGroup (+3 more)

### Community 164 - "CompositorRole"
Cohesion: 0.13
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 165 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 166 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 167 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 168 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 169 - ".relayout"
Cohesion: 0.23
Nodes (6): Context, UIPinchGestureRecognizer, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 170 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 171 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 172 - "TimelineLayoutKey"
Cohesion: 0.29
Nodes (12): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+4 more)

### Community 174 - "SpacingChart"
Cohesion: 0.21
Nodes (4): SpacingChart, .curve, .draggable, Range

### Community 175 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 176 - ".savesFired"
Cohesion: 0.17
Nodes (5): ScenePhaseSaveGate, Bool, ScenePhase, Int, ScenePhase

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

### Community 183 - ".attach"
Cohesion: 0.29
Nodes (3): Context, UIPinchGestureRecognizer, UITableView

### Community 184 - ".frames"
Cohesion: 0.20
Nodes (3): CGRect, Range, TimelineRulerClip

### Community 185 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 186 - "BrushBlendMode"
Cohesion: 0.22
Nodes (9): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+1 more)

### Community 187 - ".textureBudgetBytes"
Cohesion: 0.47
Nodes (4): CompositorBudget, .textureBudgetBytes, Int, UInt64

### Community 188 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 189 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 190 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 191 - "Alignment"
Cohesion: 0.25
Nodes (7): Alignment, center, .displayName, .id, justified, left, right

### Community 192 - "Handoff — 2026-08-20"
Cohesion: 0.29
Nodes (6): Handoff — 2026-08-20, Three things this pass learned the hard way, What is worth doing next, What needs the owner's iPad, What shipped, What the owner owes a ruling on

### Community 193 - "Corner"
Cohesion: 0.29
Nodes (6): Int, Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 194 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 195 - "ProjectStore.swift"
Cohesion: 0.38
Nodes (6): os, CodableColor, .color, Color, .codable, CodableColor

### Community 196 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 197 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 198 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 201 - ".handleShouldReceive"
Cohesion: 0.53
Nodes (4): Bool, ObjectIdentifier, UIGestureRecognizer, UITouch

### Community 202 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 203 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 205 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 206 - ".waitForDisappearance"
Cohesion: 0.40
Nodes (3): Bool, TimeInterval, XCUIElement

### Community 207 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 208 - "TODO"
Cohesion: 0.40
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 209 - "MenuRequest"
Cohesion: 0.50
Nodes (4): MenuRequest, block, gap, loop

### Community 210 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **985 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+980 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **18 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `Brush`, `cels`, `CGPoint`, `LassoFillLogicTests`, `Lattice`, `AlphaMask`, `CanvasManager`, `VectorCanvas`, `.setBakedContent`, `PointCloudIndex`, `layers`, `PerfBaselineTests`, `Coordinator`, `ARAPLogicTests`, `VectorEraserLogicTests`, `EffectLayerLogicTests`, `SandwichLogicTests`, `.report`, `CanvasManager`, `AnimationTimeline`, `StrokeCanvasView`, `.reconcileLayers`, `ProjectStore`, `BrushEngineLogicTests`, `VectorStroke`, `.rasterize`, `ShapeOverlayView`, `PaintUITestCase`, `.apply`, `CanvasManager`, `OnionSkinLogicTests`, `.launchIntoEditor`, `TextBakeCharacterizationTests`, `String`, `.evaluate`, `InterpolationRenderLogicTests`, `RenderRequest`, `VectorSample`, `FontFace`, `VectorEraserHybridLogicTests`, `ObjectTransformOverlayView`, `VectorCanvasDataLogicTests`, `TextOverlayView`, `ActionRecorder`, `InterpolationRecipe`, `Typography`, `InterpolationModelLogicTests`, `StrokeSpatialIndex`, `RasterLayerTexture`, `GuideOverlayView`, `LayerStackCell`, `.compositeSize`, `TimelineRowView`, `WindowEventTap`, `TextHitTestLogicTests`, `DrawingView`, `InterpolationGuideLogicTests`, `Binding`, `Coordinator`, `XCUIApplication`, `BrushSettingsPanel`, `.rows`, `.sample`, `PinchMergeGateLogicTests`, `FontResolveLogicTests`, `.indices`, `CanvasManager`, `GradientStopsEditor`, `CurveEditor`, `.image`, `CGRect`, `CanvasTransformFreezeUITests`, `SandwichCompositingUITests`, `CodingKeys`, `Coordinator`, `TextSettingsPanel`, `TimelineLayoutKeyLogicTests`, `.backfillMissingThumbnails`, `.arched`, `TimedSample`, `InterpolateBar`, `TextLayout`, `LayerRowModel`, `.draw`, `SideToolbar`, `ActionsMenu`, `CGContextDabTarget`, `.relayout`, `GuidePath`, `TimelineLayoutKey`, `SpacingChart`, `StrokeStabilizer`, `.frames`, `Alignment`, `JSONValue`, `Kind`?**
  _High betweenness centrality (0.293) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `Brush`, `CGRect`, `cels`, `LassoFillLogicTests`, `Lattice`, `.manager`, `AlphaMask`, `CanvasManager`, `VectorCanvas`, `.setBakedContent`, `PointCloudIndex`, `.backfillMissingThumbnails`, `FillGestureRestartLogicTests`, `CGFloat`, `layers`, `PerfBaselineTests`, `Coordinator`, `ARAPLogicTests`, `VectorEraserLogicTests`, `TimedSample`, `TextLayout`, `.arched`, `.report`, `CanvasManager`, `AnimationTimeline`, `StrokeCanvasView`, `SelectionOverlayView`, `.manager`, `BrushEngineLogicTests`, `VectorStroke`, `VectorCanvasData`, `ProjectSaveLogicTests`, `.rasterize`, `CGContextDabTarget`, `ShapeOverlayView`, `TextFrame`, `GuidePath`, `CanvasManager`, `StrokeStabilizer`, `.sampledColor`, `TextBakeCharacterizationTests`, `.evaluate`, `.frames`, `InterpolationRenderLogicTests`, `VectorSample`, `.withStructureUndo`, `VectorEraserHybridLogicTests`, `ObjectTransformOverlayView`, `Corner`, `TextOverlayView`, `InterpolationRecipe`, `Typography`, `InterpolationModelLogicTests`, `StrokeSpatialIndex`, `RasterLayerTexture`, `GuideOverlayView`, `EyedropperLogicTests`, `TimelineRowView`, `WindowEventTap`, `TextHitTestLogicTests`, `InterpolationGuideLogicTests`, `Coordinator`, `ColorPickerPanel`, `.rows`, `FloatingPieceOverlayView`, `.sample`, `.refreshUndoRedoState`, `.indices`, `CurveEditor`?**
  _High betweenness centrality (0.148) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `Brush`, `cels`, `CGPoint`, `LassoFillLogicTests`, `Lattice`, `.manager`, `ProjectBackupManager`, `AlphaMask`, `ShapeHoldClock`, `.setBakedContent`, `FillGestureRestartLogicTests`, `PointCloudIndex`, `TimelineLayoutKeyLogicTests`, `BlockDragCharacterizationTests`, `PerfBaselineTests`, `ARAPLogicTests`, `VectorEraserLogicTests`, `EffectLayerLogicTests`, `SandwichLogicTests`, `.report`, `MemoryBudgetLogicTests`, `StrokeGestureRecognizer`, `CanvasPresentationLogicTests`, `LayerTreeCharacterizationTests`, `SelectionOverlayView`, `UIKit`, `BrushEngineLogicTests`, `VectorCanvasData`, `ProjectSaveLogicTests`, `TextFrame`, `EffectMultiPassLogicTests`, `PaintUITestCase`, `OnionSkinLogicTests`, `TextBakeCharacterizationTests`, `InterpolationRenderLogicTests`, `VectorSample`, `ValueLayerLogicTests`, `VectorEraserHybridLogicTests`, `FillBoundaryLogicTests`, `VectorCanvasDataLogicTests`, `VectorEraserMode`, `Typography`, `InterpolationModelLogicTests`, `PlaybackBoundsCharacterizationTests`, `EyedropperLogicTests`, `GalleryOpenState`, `TextHitTestLogicTests`, `EffectParityLogicTests`, `CanvasNotice`, `InterpolationGuideLogicTests`, `VectorPreviewPlanLogicTests`, `PinchMergeGateLogicTests`, `FontResolveLogicTests`, `MaskGuardLogicTests`?**
  _High betweenness centrality (0.109) - this node is a cross-community bridge._
- **Are the 81 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 81 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 23 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 23 INFERRED edges - model-reasoned connections that need verification._