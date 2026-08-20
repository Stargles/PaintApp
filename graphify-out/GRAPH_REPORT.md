# Graph Report - PaintApp-save  (2026-08-20)

## Corpus Check
- 232 files · ~714,999 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6838 nodes · 20786 edges · 224 communities (210 shown, 14 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2072 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `b7db6782`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- ShapeGeometry
- CanvasManager
- LassoFillLogicTests
- .manager
- AlphaMask
- VectorCanvas
- Lattice
- VectorEraserHybridLogicTests
- CGPoint
- ProjectBackupManager
- .setBakedContent
- Identifiable
- CanvasManager
- HistoryActionLabel
- VectorEraserLogicTests
- Codable
- Coordinator
- AnimationTimeline
- EffectLayerLogicTests
- PerfBaselineTests
- ARAPLogicTests
- PointCloudIndex
- SandwichLogicTests
- StrokeGestureRecognizer
- CodingKeys
- FontResolveLogicTests
- TextFrame
- ProjectSaveLogicTests
- .drawLine
- CanvasManager
- LayerTreeCharacterizationTests
- layers
- CGFloat
- ColorPickerPanel
- StrokeCanvasView
- UIKit
- CompositorMetalEngine
- CanvasManager
- ShapeOverlayView
- PaintUITestCase
- ProjectStore
- Effect
- EffectMultiPassLogicTests
- VectorSample
- .apply
- .rasterize
- BrushEngineLogicTests
- .launchIntoEditor
- CanvasManager
- Fill.metal
- RasterLayerTexture
- View
- RenderTreeCharacterizationTests
- XCTestCase
- TextBakeCharacterizationTests
- .evaluate
- DeformFactorization
- InterpolationRecipe
- ProjectManifest
- LayerContentVersion
- LayerStackCell
- ObjectTransformOverlayView
- InterpolationRenderLogicTests
- .rows
- RenderNode
- FillBoundaryLogicTests
- VectorCanvasDataLogicTests
- TextOverlayView
- agent
- ActionRecorder
- GalleryOpenState
- InterpolationModelLogicTests
- PlaybackBoundsCharacterizationTests
- Composite.metal
- Typography
- Binding
- GuideOverlayView
- StrokeSpatialIndex
- BrushBlendMode
- BlendMode
- .reconcileLayers
- SelectionOverlayView
- EyedropperLogicTests
- TimelineRowView
- VectorCanvasData
- CodingKeys
- WindowEventTap
- ContentView
- Known Issues
- LayerRowModel
- TextHitTestLogicTests
- MaskSource
- CanvasPresentation
- DrawingView
- .compositeSize
- EffectParityLogicTests
- CanvasNotice
- TimedSample
- ActivePanel
- CodingKeys
- OnionSkinPanel
- OnionSkinSettings
- InterpolationGuideLogicTests
- XCUIApplication
- SwiftUI
- EffectPipelines
- .image
- .makeUIView
- Coordinator
- OnionSkinLogicTests
- VectorPreviewPlanLogicTests
- FloatingPieceOverlayView
- Foundation
- .sample
- Compositor.swift
- PinchMergeGateLogicTests
- GuideStroke
- GuideRow
- OnionSkinSource.swift
- Gesture
- Layer Compositing
- read
- BrushStamper
- RenderRequest
- MaskGuardLogicTests
- CanvasManager
- CurveEditor
- Coordinator
- CanvasTransformFreezeUITests
- .measuringPeakMemory
- EffectParams
- CodingKeys
- Kind
- TextSettingsPanel
- FillGestureRestartLogicTests
- .manager
- SandwichCompositingUITests
- TimelineLayoutKeyLogicTests
- .arched
- ShapeHoldClock
- BlockDragCharacterizationTests
- InterpolationEngineDiagnosticsLogicTests
- 1. The decisions
- PerfMonitor
- StructureSnapshot
- SelectionOverlayLogicTests
- InterpolateBar
- PaintSoftware - iPad Drawing and Animation App
- DabTarget
- TextLayout
- .indices
- .backfillMissingThumbnails
- InterpolationRefusal
- CGRect
- CanvasPresentationLogicTests
- Recording
- CanvasSizePickerView
- EraserSettingsPanel
- SideToolbar
- MenuInterruptionUITests
- bash
- CanvasManager
- ViewPreset
- CompositorRole
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- SpacingChart
- UndoHistory
- CanvasHostView
- .relayout
- Performance
- TimelineLayoutKey
- CLAUDE.md
- MotionGroup
- CanvasManager
- .attach
- SelectPanel
- CelBlockView
- 4. Future upgrades — the deferred list
- Every dismissible presentation, and whether a stroke under it breaks
- StrokeStabilizer
- Layer
- Lasso Fill — Specification
- .sampledColor
- .frames
- Multi-Session Protocol
- CutOutcome
- Kind
- .row
- Alignment
- CodingKeys
- .handleShouldReceive
- Handoff — 2026-08-20
- 6. Alpha masks
- command
- JSONValue
- CompositeProbe
- CodingKeys
- LassoFillDiagnostic
- CodingKeys
- Kind
- ValueFill
- ManifestSkeleton
- RecordingWriter
- CodingKeys
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- ToolPanelsUITests
- parallel_test.sh
- CodingKeys
- Performance baseline
- TODO
- CodingKey
- Kind
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- Prompt for the next session
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
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
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

## Communities (224 total, 14 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 1 - "ShapeGeometry"
Cohesion: 0.04
Nodes (30): Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom, left (+22 more)

### Community 2 - "CanvasManager"
Cohesion: 0.04
Nodes (62): Never, Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+54 more)

### Community 3 - "LassoFillLogicTests"
Cohesion: 0.06
Nodes (32): MTLBuffer, MTLCommandBuffer, LassoFillMask, Float, Int, SIMD4, UInt8, FillParams (+24 more)

### Community 4 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 5 - "AlphaMask"
Cohesion: 0.06
Nodes (20): Hashable, CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8 (+12 more)

### Community 6 - "VectorCanvas"
Cohesion: 0.06
Nodes (35): Brush, UUID, VectorTextElement, image, kind, RenderQuality, full, preview (+27 more)

### Community 7 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 8 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (40): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+32 more)

### Community 9 - "CGPoint"
Cohesion: 0.06
Nodes (17): CGPoint, .length, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect (+9 more)

### Community 10 - "ProjectBackupManager"
Cohesion: 0.07
Nodes (28): DateFormatter, Notification.Name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+20 more)

### Community 11 - ".setBakedContent"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 12 - "Identifiable"
Cohesion: 0.03
Nodes (66): CaseIterable, Identifiable, BrushShape, custom, .displayName, hardRound, .id, pen (+58 more)

### Community 13 - "CanvasManager"
Cohesion: 0.06
Nodes (27): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+19 more)

### Community 14 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 15 - "VectorEraserLogicTests"
Cohesion: 0.07
Nodes (11): CGRect, VectorEraser, StaticString, String, UInt, ClosedRange, StaticString, UInt (+3 more)

### Community 16 - "Codable"
Cohesion: 0.05
Nodes (53): Codable, Error, CodableColor, .uiColor, DabLattice, .range, DecodeReport, .droppedCount (+45 more)

### Community 17 - "Coordinator"
Cohesion: 0.06
Nodes (34): Coordinator, .canvasContentScale, .isLassoFilling, .sandwichPresentation, InterpolationPreviewKey, OnionSkinKey, SandwichPresentation, disengaged (+26 more)

### Community 18 - "AnimationTimeline"
Cohesion: 0.04
Nodes (49): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+41 more)

### Community 19 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 20 - "PerfBaselineTests"
Cohesion: 0.12
Nodes (10): CompositorBudget, .textureBudgetBytes, Int, UInt64, PerfBaselineTests, Bool, CanvasManager, CGSize (+2 more)

### Community 21 - "ARAPLogicTests"
Cohesion: 0.08
Nodes (12): ARAPInterpolation, Group, MotionGrouping, Options, Int, Set, ARAPLogicTests, .rigidMotionL (+4 more)

### Community 22 - "PointCloudIndex"
Cohesion: 0.11
Nodes (18): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+10 more)

### Community 23 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 24 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 25 - "CodingKeys"
Cohesion: 0.05
Nodes (45): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+37 more)

### Community 26 - "FontResolveLogicTests"
Cohesion: 0.09
Nodes (23): FontFace, .descriptor, .id, FontFamilyGroup, .id, FontLibrary, FontProvider, FontResolution (+15 more)

### Community 27 - "TextFrame"
Cohesion: 0.07
Nodes (29): Int, Corner, bottomLeft, bottomRight, topLeft, topRight, FontDescriptor, Mode (+21 more)

### Community 28 - "ProjectSaveLogicTests"
Cohesion: 0.11
Nodes (13): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase (+5 more)

### Community 29 - ".drawLine"
Cohesion: 0.11
Nodes (12): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, Bool, CGVector, Double, TimeInterval, UInt8 (+4 more)

### Community 30 - "CanvasManager"
Cohesion: 0.07
Nodes (33): UUID, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform (+25 more)

### Community 31 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (7): Layer, String, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 32 - "layers"
Cohesion: 0.10
Nodes (15): .activeLayerIsVector, .activeCelIsInBetween, Int, CanvasManager, Bool, Int, Void, Cel (+7 more)

### Community 33 - "CGFloat"
Cohesion: 0.07
Nodes (17): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Void, CGFloat (+9 more)

### Community 34 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (34): Palette, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID, Bool, Color (+26 more)

### Community 35 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (27): CAShapeLayer, StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush (+19 more)

### Community 36 - "UIKit"
Cohesion: 0.07
Nodes (7): CoreGraphics, CoreText, Darwin, TextMeasure, simd, UIKit, XCTest

### Community 37 - "CompositorMetalEngine"
Cohesion: 0.10
Nodes (29): Admission, admitted, noHeadroom, overBudget, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+21 more)

### Community 38 - "CanvasManager"
Cohesion: 0.09
Nodes (20): CanvasManager, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel, CGPath (+12 more)

### Community 39 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 40 - "PaintUITestCase"
Cohesion: 0.09
Nodes (13): HistoryNoticeUITests, PaintUITestCase, Int, String, XCUIApplication, InterpolationWorkflowUITests, Bool, TimeInterval (+5 more)

### Community 41 - "ProjectStore"
Cohesion: 0.11
Nodes (33): CFAbsoluteTime, CelContent, DecodedCels, LayerContent, LoadProfile, .millisecondsPerCel, .thumbnailShare, ProjectStore (+25 more)

### Community 42 - "Effect"
Cohesion: 0.09
Nodes (32): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+24 more)

### Community 43 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 44 - "VectorSample"
Cohesion: 0.10
Nodes (12): VectorSample, .point, Sweep, Bool, ClosedRange, Double, CountingDabTarget, StrokeSampleGateLogicTests (+4 more)

### Community 45 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 46 - ".rasterize"
Cohesion: 0.12
Nodes (21): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+13 more)

### Community 47 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 48 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 49 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 50 - "Fill.metal"
Cohesion: 0.17
Nodes (40): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+32 more)

### Community 51 - "RasterLayerTexture"
Cohesion: 0.11
Nodes (14): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+6 more)

### Community 52 - "View"
Cohesion: 0.14
Nodes (29): View, .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex (+21 more)

### Community 53 - "RenderTreeCharacterizationTests"
Cohesion: 0.14
Nodes (7): StaticString, UInt, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 54 - "XCTestCase"
Cohesion: 0.13
Nodes (13): PaletteColor, .color, CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage (+5 more)

### Community 55 - "TextBakeCharacterizationTests"
Cohesion: 0.17
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 56 - ".evaluate"
Cohesion: 0.11
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 57 - "DeformFactorization"
Cohesion: 0.09
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 58 - "InterpolationRecipe"
Cohesion: 0.14
Nodes (15): CelRef, InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference (+7 more)

### Community 59 - "ProjectManifest"
Cohesion: 0.13
Nodes (23): LayerKind, raster, value, vector, K, KeyedDecodingContainer, CelManifest, CodableColor (+15 more)

### Community 60 - "LayerContentVersion"
Cohesion: 0.10
Nodes (23): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderResolution, full, half (+15 more)

### Community 61 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): effectMenuSlug(), LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String (+4 more)

### Community 62 - "ObjectTransformOverlayView"
Cohesion: 0.09
Nodes (23): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, FloatingTransform (+15 more)

### Community 63 - "InterpolationRenderLogicTests"
Cohesion: 0.18
Nodes (9): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int, UIImage, UUID (+1 more)

### Community 64 - ".rows"
Cohesion: 0.11
Nodes (26): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+18 more)

### Community 65 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 66 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 67 - "VectorCanvasDataLogicTests"
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 68 - "TextOverlayView"
Cohesion: 0.10
Nodes (16): RenderKey, Bool, CGRect, CGSize, NSCoder, Set, String, UIEvent (+8 more)

### Community 69 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 70 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 71 - "GalleryOpenState"
Cohesion: 0.11
Nodes (17): GalleryOpenState, .isBusy, Bool, UUID, ProjectVersionsView, RecentlyDeletedView, .body, Void (+9 more)

### Community 72 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 73 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 74 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 75 - "Typography"
Cohesion: 0.20
Nodes (7): UIFont, ClosedRange, Typography, Int, String, UIFont, TextLayoutLogicTests

### Community 76 - "Binding"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 77 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 78 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 79 - "BrushBlendMode"
Cohesion: 0.09
Nodes (17): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+9 more)

### Community 80 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 81 - ".reconcileLayers"
Cohesion: 0.10
Nodes (9): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, SandwichKey, TimeInterval, UIImage (+1 more)

### Community 82 - "SelectionOverlayView"
Cohesion: 0.12
Nodes (16): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, Set, UIColor (+8 more)

### Community 83 - "EyedropperLogicTests"
Cohesion: 0.11
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 84 - "TimelineRowView"
Cohesion: 0.13
Nodes (17): Kind, cel, gap, Segment, Cel, Int, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 85 - "VectorCanvasData"
Cohesion: 0.22
Nodes (6): .elements, VectorCanvasData, String, UUID, VectorStroke, VectorTextPersistenceLogicTests

### Community 86 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 87 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 88 - "ContentView"
Cohesion: 0.09
Nodes (17): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+9 more)

### Community 89 - "Known Issues"
Cohesion: 0.07
Nodes (27): A corrupt raster PNG silently yields a blank cel (2026-08-17), A green backend-parity test does not prove both backends ran (2026-08-15), A lasso fill does not paint over line art on a *raster* layer either, for the same-layer case (2026-08-17), A lasso fill does not paint over line art on a *vector* layer (2026-08-17), A mask sourced from a graded group can be stale (2026-08-15), A stroke begun under a timeline popover stops being delivered, with no terminal callback (2026-08-16), A vector layer's transform is not undoable at all (2026-08-20), Cleanup opportunities (+19 more)

### Community 90 - "LayerRowModel"
Cohesion: 0.12
Nodes (17): DispatchWorkItem, IndexPath, LayerRowModel, .folderID, .isFolder, .maskSource, LayerStackListView.Coordinator, BlendMode (+9 more)

### Community 91 - "TextHitTestLogicTests"
Cohesion: 0.18
Nodes (6): Bool, CGAffineTransform, CGSize, String, VectorStroke, TextHitTestLogicTests

### Community 92 - "MaskSource"
Cohesion: 0.15
Nodes (12): MaskSource, folder, .id, layer, Encoder, UUID, Void, CanvasManager (+4 more)

### Community 93 - "CanvasPresentation"
Cohesion: 0.09
Nodes (20): CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id, interpolateOptions (+12 more)

### Community 94 - "DrawingView"
Cohesion: 0.08
Nodes (20): ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void, DrawingView (+12 more)

### Community 95 - ".compositeSize"
Cohesion: 0.17
Nodes (7): .resolutionNoteText, OnionSkinBudget, OnionSkinOpacityRamp, CGSize, Double, Int, Int

### Community 96 - "EffectParityLogicTests"
Cohesion: 0.20
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 97 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 98 - "TimedSample"
Cohesion: 0.12
Nodes (8): GuidePath, .end, .start, TimeInterval, TimeInterval, TimedSample, .point, TimeInterval

### Community 99 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 100 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 101 - "OnionSkinPanel"
Cohesion: 0.11
Nodes (21): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+13 more)

### Community 102 - "OnionSkinSettings"
Cohesion: 0.19
Nodes (9): .opacitySliders, OnionSkinSettings, Side, .id, next, .step, CodableColor, Double (+1 more)

### Community 104 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 105 - "SwiftUI"
Cohesion: 0.12
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 106 - "EffectPipelines"
Cohesion: 0.13
Nodes (17): Metal, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue (+9 more)

### Community 107 - ".image"
Cohesion: 0.14
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 108 - ".makeUIView"
Cohesion: 0.12
Nodes (9): AppliedTool, CanvasView, Color, Context, Coordinator, Double, LayerTransform, UIColor (+1 more)

### Community 109 - "Coordinator"
Cohesion: 0.17
Nodes (14): .body, Coordinator, DropTarget, between, onto, LayerStackListView, CanvasManager, Coordinator (+6 more)

### Community 110 - "OnionSkinLogicTests"
Cohesion: 0.17
Nodes (5): CelSpan, .end, OnionSkinPlanner, Bool, OnionSkinLogicTests

### Community 111 - "VectorPreviewPlanLogicTests"
Cohesion: 0.13
Nodes (11): Bool, String, VectorPreviewPlan, VectorScratchRole, none, overlay, replacement, .traceName (+3 more)

### Community 112 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 113 - "Foundation"
Cohesion: 0.09
Nodes (10): Foundation, os, CodableColor, .color, Color, .codable, CodableColor, AppVersion (+2 more)

### Community 114 - ".sample"
Cohesion: 0.18
Nodes (13): NSObject, ObjectiveC.runtime, FoundElement, ResolvedTarget, Bool, CGRect, CGSize, Double (+5 more)

### Community 115 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 116 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 117 - "GuideStroke"
Cohesion: 0.13
Nodes (15): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+7 more)

### Community 118 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 119 - "OnionSkinSource.swift"
Cohesion: 0.13
Nodes (9): tinted, OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager, StaticString, UIImage, UInt (+1 more)

### Community 120 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 121 - "Layer Compositing"
Cohesion: 0.09
Nodes (22): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+14 more)

### Community 122 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 123 - "BrushStamper"
Cohesion: 0.17
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 124 - "RenderRequest"
Cohesion: 0.23
Nodes (12): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, Attempt, image (+4 more)

### Community 125 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 126 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 127 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 128 - "Coordinator"
Cohesion: 0.18
Nodes (10): BlockDrag, Coordinator, MenuRequest, block, gap, loop, CanvasManager, Coordinator (+2 more)

### Community 129 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 130 - ".measuringPeakMemory"
Cohesion: 0.16
Nodes (7): Atomic, .value, Double, UInt64, Value, VectorStroke, Void

### Community 131 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 132 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 133 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 134 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 135 - "FillGestureRestartLogicTests"
Cohesion: 0.25
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 136 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 137 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 138 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.27
Nodes (3): CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 139 - ".arched"
Cohesion: 0.25
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 140 - "ShapeHoldClock"
Cohesion: 0.21
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 141 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 142 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 143 - "1. The decisions"
Cohesion: 0.11
Nodes (18): 1. The decisions, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, `ActionsMenu` gains the ability to enter a mode, Add Text, Fonts go through one seam and nothing else (+10 more)

### Community 144 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 145 - "StructureSnapshot"
Cohesion: 0.17
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, guideStrokes

### Community 146 - "SelectionOverlayLogicTests"
Cohesion: 0.16
Nodes (6): resolvedLastTouchType(), UITouch, SelectionOverlayLogicTests, Bool, UITouch, S

### Community 147 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 148 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.11
Nodes (18): Animation, Building and Running, Canvas, Creating a Canvas, Deploying to a physical iPad, Drawing, Features, Fill (+10 more)

### Community 149 - "DabTarget"
Cohesion: 0.20
Nodes (10): AnyObject, CGGradient, Key, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode (+2 more)

### Community 150 - "TextLayout"
Cohesion: 0.23
Nodes (11): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGRect (+3 more)

### Community 152 - ".backfillMissingThumbnails"
Cohesion: 0.21
Nodes (10): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+2 more)

### Community 153 - "InterpolationRefusal"
Cohesion: 0.15
Nodes (12): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+4 more)

### Community 154 - "CGRect"
Cohesion: 0.28
Nodes (8): CGRect, NSCoder, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView, TimelinePlayheadView, TimelineRulerView

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

### Community 161 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 162 - "CanvasManager"
Cohesion: 0.19
Nodes (9): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage (+1 more)

### Community 163 - "ViewPreset"
Cohesion: 0.20
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 164 - "CompositorRole"
Cohesion: 0.13
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 165 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 166 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 167 - "SpacingChart"
Cohesion: 0.19
Nodes (4): SpacingChart, .curve, .draggable, Range

### Community 168 - "UndoHistory"
Cohesion: 0.23
Nodes (7): Action, Bool, Int, Void, UndoHistory, .canRedo, .canUndo

### Community 169 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 170 - ".relayout"
Cohesion: 0.23
Nodes (6): Context, UIPinchGestureRecognizer, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 171 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 172 - "TimelineLayoutKey"
Cohesion: 0.29
Nodes (12): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+4 more)

### Community 174 - "MotionGroup"
Cohesion: 0.23
Nodes (9): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 175 - "CanvasManager"
Cohesion: 0.23
Nodes (6): CanvasManager, .activeEditColor, .isTextInAdjustableState, Bool, Color, String

### Community 176 - ".attach"
Cohesion: 0.23
Nodes (5): Context, UIPinchGestureRecognizer, .gradientStops, previous, UITableView

### Community 177 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 178 - "CelBlockView"
Cohesion: 0.23
Nodes (5): CelBlockView, Bool, ClosedRange, String, UIImage

### Community 179 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 180 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.18
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 181 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 182 - "Layer"
Cohesion: 0.18
Nodes (11): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+3 more)

### Community 183 - "Lasso Fill — Specification"
Cohesion: 0.20
Nodes (10): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill, 8. Open risks (+2 more)

### Community 184 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 185 - ".frames"
Cohesion: 0.20
Nodes (3): CGRect, Range, TimelineRulerClip

### Community 186 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 187 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 188 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 189 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 190 - "Alignment"
Cohesion: 0.25
Nodes (7): Alignment, center, .displayName, .id, justified, left, right

### Community 191 - "CodingKeys"
Cohesion: 0.25
Nodes (8): CodingKeys, groups, guideIDs, localEdits, mode, references, spacing, t

### Community 192 - ".handleShouldReceive"
Cohesion: 0.36
Nodes (4): Bool, ObjectIdentifier, UIGestureRecognizer, UITouch

### Community 193 - "Handoff — 2026-08-20"
Cohesion: 0.29
Nodes (6): Handoff — 2026-08-20, Three things this pass learned the hard way, What is worth doing next, What needs the owner's iPad, What shipped, What the owner owes a ruling on

### Community 194 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 195 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 196 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 198 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 199 - "LassoFillDiagnostic"
Cohesion: 0.38
Nodes (6): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID

### Community 200 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, endPoint, kind, rotation, spanStart, spanSweep, startPoint

### Community 201 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 202 - "ValueFill"
Cohesion: 0.29
Nodes (3): Decoder, Int, ValueFill

### Community 203 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 205 - "CodingKeys"
Cohesion: 0.33
Nodes (6): CodingKeys, id, invert, isEnabled, kind, sources

### Community 206 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 208 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 209 - "CodingKeys"
Cohesion: 0.40
Nodes (5): CodingKeys, displayName, id, mode, tagColor

### Community 210 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 211 - "TODO"
Cohesion: 0.40
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 212 - "CodingKey"
Cohesion: 0.50
Nodes (4): CodingKey, CodingKeys, color, String

### Community 213 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 214 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **984 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+979 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `ShapeGeometry`, `CanvasManager`, `LassoFillLogicTests`, `AlphaMask`, `VectorCanvas`, `Lattice`, `VectorEraserHybridLogicTests`, `CGPoint`, `.setBakedContent`, `Identifiable`, `CanvasManager`, `VectorEraserLogicTests`, `Codable`, `Coordinator`, `AnimationTimeline`, `EffectLayerLogicTests`, `PerfBaselineTests`, `ARAPLogicTests`, `PointCloudIndex`, `SandwichLogicTests`, `FontResolveLogicTests`, `CanvasManager`, `layers`, `StrokeCanvasView`, `CanvasManager`, `ShapeOverlayView`, `PaintUITestCase`, `ProjectStore`, `VectorSample`, `.apply`, `.rasterize`, `BrushEngineLogicTests`, `.launchIntoEditor`, `RasterLayerTexture`, `TextBakeCharacterizationTests`, `.evaluate`, `DeformFactorization`, `InterpolationRecipe`, `LayerContentVersion`, `LayerStackCell`, `ObjectTransformOverlayView`, `InterpolationRenderLogicTests`, `.rows`, `VectorCanvasDataLogicTests`, `TextOverlayView`, `ActionRecorder`, `InterpolationModelLogicTests`, `Typography`, `Binding`, `GuideOverlayView`, `StrokeSpatialIndex`, `BrushBlendMode`, `.reconcileLayers`, `TimelineRowView`, `WindowEventTap`, `LayerRowModel`, `TextHitTestLogicTests`, `DrawingView`, `.compositeSize`, `TimedSample`, `InterpolationGuideLogicTests`, `XCUIApplication`, `.image`, `.makeUIView`, `Coordinator`, `OnionSkinLogicTests`, `.sample`, `PinchMergeGateLogicTests`, `OnionSkinSource.swift`, `BrushStamper`, `RenderRequest`, `CanvasManager`, `CurveEditor`, `Coordinator`, `CanvasTransformFreezeUITests`, `.measuringPeakMemory`, `CodingKeys`, `TextSettingsPanel`, `.manager`, `SandwichCompositingUITests`, `TimelineLayoutKeyLogicTests`, `.arched`, `InterpolationEngineDiagnosticsLogicTests`, `InterpolateBar`, `DabTarget`, `TextLayout`, `.indices`, `.backfillMissingThumbnails`, `CGRect`, `EraserSettingsPanel`, `SideToolbar`, `CanvasManager`, `ActionsMenu`, `SpacingChart`, `.relayout`, `TimelineLayoutKey`, `CelBlockView`, `StrokeStabilizer`, `.frames`, `Alignment`, `JSONValue`, `Kind`?**
  _High betweenness centrality (0.267) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `Coordinator`, `ShapeGeometry`, `CanvasManager`, `cels`, `.manager`, `LassoFillLogicTests`, `VectorCanvas`, `Lattice`, `FillGestureRestartLogicTests`, `.manager`, `AlphaMask`, `.setBakedContent`, `.arched`, `CanvasManager`, `InterpolationEngineDiagnosticsLogicTests`, `VectorEraserLogicTests`, `.measuringPeakMemory`, `Coordinator`, `AnimationTimeline`, `Identifiable`, `PerfBaselineTests`, `ARAPLogicTests`, `PointCloudIndex`, `.indices`, `DabTarget`, `TextLayout`, `.backfillMissingThumbnails`, `TextFrame`, `CGRect`, `ProjectSaveLogicTests`, `CanvasManager`, `layers`, `CGFloat`, `CanvasManager`, `StrokeCanvasView`, `ColorPickerPanel`, `CanvasManager`, `ShapeOverlayView`, `VectorEraserHybridLogicTests`, `VectorSample`, `.rasterize`, `BrushEngineLogicTests`, `CanvasManager`, `CelBlockView`, `RasterLayerTexture`, `StrokeStabilizer`, `TextBakeCharacterizationTests`, `.evaluate`, `DeformFactorization`, `.sampledColor`, `.frames`, `InterpolationRecipe`, `ObjectTransformOverlayView`, `InterpolationRenderLogicTests`, `TextOverlayView`, `InterpolationModelLogicTests`, `Typography`, `GuideOverlayView`, `StrokeSpatialIndex`, `SelectionOverlayView`, `EyedropperLogicTests`, `TimelineRowView`, `VectorCanvasData`, `WindowEventTap`, `LayerRowModel`, `TextHitTestLogicTests`, `TimedSample`, `InterpolationGuideLogicTests`, `.makeUIView`, `FloatingPieceOverlayView`, `.sample`, `BrushStamper`, `CurveEditor`?**
  _High betweenness centrality (0.171) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `cels`, `ShapeGeometry`, `LassoFillLogicTests`, `.manager`, `AlphaMask`, `FillGestureRestartLogicTests`, `Lattice`, `VectorEraserHybridLogicTests`, `ProjectBackupManager`, `.setBakedContent`, `ShapeHoldClock`, `BlockDragCharacterizationTests`, `InterpolationEngineDiagnosticsLogicTests`, `CGPoint`, `TimelineLayoutKeyLogicTests`, `Identifiable`, `SelectionOverlayLogicTests`, `EffectLayerLogicTests`, `PerfBaselineTests`, `ARAPLogicTests`, `VectorEraserLogicTests`, `SandwichLogicTests`, `StrokeGestureRecognizer`, `FontResolveLogicTests`, `CanvasPresentationLogicTests`, `ProjectSaveLogicTests`, `TextFrame`, `LayerTreeCharacterizationTests`, `UIKit`, `PaintUITestCase`, `EffectMultiPassLogicTests`, `VectorSample`, `BrushEngineLogicTests`, `RenderTreeCharacterizationTests`, `TextBakeCharacterizationTests`, `InterpolationRenderLogicTests`, `FillBoundaryLogicTests`, `VectorCanvasDataLogicTests`, `GalleryOpenState`, `InterpolationModelLogicTests`, `PlaybackBoundsCharacterizationTests`, `Typography`, `EyedropperLogicTests`, `VectorCanvasData`, `TextHitTestLogicTests`, `EffectParityLogicTests`, `CanvasNotice`, `InterpolationGuideLogicTests`, `OnionSkinLogicTests`, `VectorPreviewPlanLogicTests`, `PinchMergeGateLogicTests`, `MaskGuardLogicTests`?**
  _High betweenness centrality (0.104) - this node is a cross-community bridge._
- **Are the 81 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 81 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 23 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 23 INFERRED edges - model-reasoned connections that need verification._