# Graph Report - PaintSoftware  (2026-08-21)

## Corpus Check
- 244 files · ~772,053 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 7236 nodes · 22003 edges · 236 communities (214 shown, 22 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2217 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `09705e81`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PaintUITestCase
- CGFloat
- ProjectBackupManager
- .manager
- Coordinator
- ColorPickerPanel
- bash
- CanvasManager
- VectorCanvasData
- ShapeOverlayView
- String
- cels
- StrokeCanvasView
- ActionRecorder
- BrushEngineLogicTests
- TextFrame
- UIKit
- StrokeGeometryLogicTests
- VectorEraserLogicTests
- InterpolationRecipe
- .rasterize
- layers
- CanvasManager
- ARAPLogicTests
- ViewPreset
- .drawLine
- VectorEraserHybridLogicTests
- CanvasManager
- PerfBaselineTests
- Fill.metal
- StrokeGestureRecognizer
- RasterLayerTexture
- HistoryActionLabel
- ActivePanel
- Binding
- Coordinator
- FloatingPieceOverlayView
- AnimationTimeline
- LayerOptionsPanel
- ProjectSaveLogicTests
- LayerStackCell
- VectorCanvas
- XCTestCase
- SelectionOverlayView
- TextTransformLogicTests
- RenderTreeCharacterizationTests
- ContentView
- PerfMonitor
- FontDescriptor
- ProjectManifest
- CanvasSizePickerView
- WindowEventTap
- SideToolbar
- .makeUIView
- TextOverlayView
- ObjectTransformOverlayView
- Housekeeping pass (8 items from 2026-07-22 feature audit)
- XCUIApplication
- BrushStamper
- CGPoint
- AlphaMask
- ProjectStore
- StrokeStabilizer
- ElementData
- CompositorParityLogicTests
- CanvasManager
- View
- CanvasHostView
- GalleryOpenState
- SaveDamageGateLogicTests
- PaintSoftware iPad drawing/animation app
- BrushStamper.DabRNG (seeded splitmix64)
- PerfBaselineTests.swift
- LayerTreeCharacterizationTests
- .apply
- ProjectLoadDamage
- CompositorMetalEngine
- Coordinator
- Foundation
- Effect
- Codable
- DrawingView
- SandwichLogicTests
- CGImage.cropping(to:) retains parent pixel data
- Multi-Session Protocol
- graphify usage protocol
- VectorCanvasDataLogicTests
- TextBakeCharacterizationTests
- InterpolationRefusal
- parallel_test.sh
- .setBakedContent
- PointCloudIndex
- EffectMultiPassLogicTests
- .evaluate
- InterpolationRenderLogicTests
- Layer Compositing
- cleanup_session.sh
- screenshot.sh
- Switching brush presets resets live size/opacity
- Duplicated canvas-flip geometry (flippedImage/RasterLayerTexture.flipped)
- graphify-guard.sh
- fast_test.sh
- status.sh
- Raster-layer ghost-layer bug (Session 49)
- ShapeDetector unified-scoring rewrite (Session 51)
- ContentView.saveIfNeeded gap (direct project transition)
- Distort/Warp transform modes render identically to Uniform
- Adjust panel / ActionsMenu Cut-Copy-Paste stubs
- BlendMode
- InterpolationModelLogicTests
- CodingKey
- Composite.metal
- PlaybackBoundsCharacterizationTests
- GuideOverlayView
- DeformFactorization
- CodingKeys
- RenderNode
- EffectParityLogicTests
- BlockDragCharacterizationTests
- RenderRequest
- MaskSource
- VectorSample
- InterpolationGuideLogicTests
- TextTransformOverlayView
- agent
- Compositor.swift
- .indices
- CanvasManager
- VectorTransformUndoLogicTests
- Typography
- read
- EyedropperLogicTests
- .arched
- GuideStroke
- InterpolateBar
- .launchIntoEditor
- EffectParams
- .draw
- TextHitTestLogicTests
- .backfillMissingThumbnails
- .manager
- CanvasNotice
- SpacingChart
- OnionSkinLogicTests
- 4. Future upgrades — the deferred list
- TransformOverlaySupport.swift
- Kind
- command
- LassoFillLogicTests
- CanvasManager
- PinchMergeGateLogicTests
- StrokeSpatialIndex
- TimelineRowView
- .refreshUndoRedoState
- Gesture
- CanvasTransformFreezeUITests
- ShapeHoldClock
- run.sh
- VectorEraserMode
- .rows
- CanvasPresentation
- MotionGroup
- CurveEditor
- OnionSkinPanel
- .row
- Recording
- EffectPipelines
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- ToolPanelsUITests
- VectorPreviewPlanLogicTests
- 1. The decisions
- SwiftUI
- Int
- JSONValue
- CodingKeys
- GuidePath
- .compositeSize
- MetalFillSession
- OnionSkinSettings
- .setUpGestures
- Add Text
- Is the brush engine ready for `.ABR` / Procreate brush import?
- MaskGuardLogicTests
- TextRecipeCodableLogicTests
- CGRect
- simlock.sh
- SandwichCompositingUITests
- .sample
- Kind
- CodingKeys
- FillBoundaryLogicTests
- ActionsMenu
- TextSettingsPanel
- LayerRowModel
- UndoHistory
- Performance
- .textureBudgetBytes
- FillGestureRestartLogicTests
- TimelineLayoutKeyLogicTests
- .sampledColor
- Lasso Fill — Specification
- OnionSkinSource.swift
- SelectionOverlayLogicTests
- RecordingWriter
- Atomic
- CanvasPresentationLogicTests
- .perfManager
- CGContextDabTarget
- TextRecipe
- Prompt for the next session
- StructureSnapshot
- MenuInterruptionUITests
- .relayout
- .performDrag
- TimelineLayoutKey
- LassoFillDiagnostic
- Kind
- Every dismissible presentation, and whether a stroke under it breaks
- SelectionPersistenceLogicTests
- .frames
- CutOutcome
- TimedSample
- Handoff — 2026-08-21
- MemoryBudgetLogicTests
- SelectPanel
- CanvasPresentationModifier
- 1. The decisions
- presentation-census.sh
- Lasso Move — Specification
- Attempt
- .handleShouldReceive
- CodingKeys
- ManifestSkeleton
- CopiedCel
- .bytes

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 788 edges
2. `CGFloat` - 563 edges
3. `CanvasManager` - 170 edges
4. `VectorCanvas` - 159 edges
5. `Effect` - 149 edges
6. `layers` - 126 edges
7. `VectorSample` - 124 edges
8. `Coordinator` - 121 edges
9. `ShapeGeometry` - 109 edges
10. `CanvasManager` - 100 edges

## Surprising Connections (you probably didn't know these)
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `PerfBaselineTests` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Stroke-delivery regression: default flip, gate, and recognizer state involved together** — bugs_stroke_delivery_regression, bugs_requirespencilonly, bugs_pencilonlydrawing, bugs_reconcilelayers, bugs_housekeeping_2026_07_26 [EXTRACTED 1.00]

## Communities (236 total, 22 thin omitted)

### Community 0 - "PaintUITestCase"
Cohesion: 0.12
Nodes (10): FillLiveAdjustUITests, HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, SelectionAndMoveUITests (+2 more)

### Community 1 - "CGFloat"
Cohesion: 0.04
Nodes (38): CGFloat, ClosedFit, ShapeDetector, Bool, CGRect, Int, Corner, bottomLeft (+30 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.08
Nodes (28): DateFormatter, Notification.Name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+20 more)

### Community 3 - ".manager"
Cohesion: 0.07
Nodes (9): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool, CanvasManager (+1 more)

### Community 4 - "Coordinator"
Cohesion: 0.14
Nodes (12): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, CanvasManager (+4 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+29 more)

### Community 6 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 7 - "CanvasManager"
Cohesion: 0.04
Nodes (65): Never, Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+57 more)

### Community 8 - "VectorCanvasData"
Cohesion: 0.24
Nodes (6): .elements, VectorCanvasData, String, UUID, VectorStroke, VectorTextPersistenceLogicTests

### Community 9 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 10 - "String"
Cohesion: 0.03
Nodes (73): CaseIterable, Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+65 more)

### Community 11 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (26): CAShapeLayer, StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush (+18 more)

### Community 13 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 14 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 15 - "TextFrame"
Cohesion: 0.07
Nodes (36): Int, Basis, Corner, bottomLeft, bottomRight, topLeft, topRight, Handle (+28 more)

### Community 16 - "UIKit"
Cohesion: 0.07
Nodes (7): CoreGraphics, Darwin, LayerTransform, ThumbnailRenderer, simd, UIKit, XCTest

### Community 17 - "StrokeGeometryLogicTests"
Cohesion: 0.05
Nodes (16): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+8 more)

### Community 18 - "VectorEraserLogicTests"
Cohesion: 0.09
Nodes (8): CGRect, VectorEraser, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 19 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 20 - ".rasterize"
Cohesion: 0.09
Nodes (22): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+14 more)

### Community 21 - "layers"
Cohesion: 0.09
Nodes (16): .activeLayerIsVector, .activeCelIsInBetween, .interpolationTarget, Int, CanvasManager, Bool, Int, Void (+8 more)

### Community 22 - "CanvasManager"
Cohesion: 0.09
Nodes (22): CanvasManager, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel, CGPath (+14 more)

### Community 23 - "ARAPLogicTests"
Cohesion: 0.09
Nodes (12): ARAPInterpolation, Group, MotionGrouping, Options, Int, Set, ARAPLogicTests, .rigidMotionL (+4 more)

### Community 24 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 25 - ".drawLine"
Cohesion: 0.13
Nodes (9): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, EraserAndPersistenceUITests (+1 more)

### Community 26 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (41): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+33 more)

### Community 27 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 28 - "PerfBaselineTests"
Cohesion: 0.12
Nodes (6): PerfBaselineTests, CGSize, Double, String, UInt64, VectorStroke

### Community 29 - "Fill.metal"
Cohesion: 0.17
Nodes (41): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+33 more)

### Community 30 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 31 - "RasterLayerTexture"
Cohesion: 0.15
Nodes (14): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+6 more)

### Community 32 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 33 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 34 - "Binding"
Cohesion: 0.06
Nodes (40): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+32 more)

### Community 35 - "Coordinator"
Cohesion: 0.06
Nodes (32): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, ActiveObjectTransform, Coordinator, .canvasContentScale (+24 more)

### Community 36 - "FloatingPieceOverlayView"
Cohesion: 0.10
Nodes (19): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+11 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.04
Nodes (50): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+42 more)

### Community 38 - "LayerOptionsPanel"
Cohesion: 0.12
Nodes (28): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+20 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.11
Nodes (14): CanvasManager, MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int (+6 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.11
Nodes (9): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, UIView, Void (+1 more)

### Community 41 - "VectorCanvas"
Cohesion: 0.07
Nodes (42): VectorTextElement, CodableColor, .uiColor, kind, StrokeComposite, erase, paint, Bool (+34 more)

### Community 42 - "XCTestCase"
Cohesion: 0.14
Nodes (11): CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor (+3 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.12
Nodes (16): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, Set, UIColor (+8 more)

### Community 44 - "TextTransformLogicTests"
Cohesion: 0.10
Nodes (10): TextFrameDrag, .clamped, Bool, CanvasManager, CGSize, Int, StaticString, String (+2 more)

### Community 45 - "RenderTreeCharacterizationTests"
Cohesion: 0.13
Nodes (8): StaticString, String, UInt, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 46 - "ContentView"
Cohesion: 0.09
Nodes (18): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+10 more)

### Community 47 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 48 - "FontDescriptor"
Cohesion: 0.08
Nodes (25): CoreText, FontFace, .descriptor, .id, FontFamilyGroup, .id, FontLibrary, FontProvider (+17 more)

### Community 49 - "ProjectManifest"
Cohesion: 0.05
Nodes (46): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+38 more)

### Community 50 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 51 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 52 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 53 - ".makeUIView"
Cohesion: 0.16
Nodes (5): CanvasView, Context, Coordinator, UIColor, UIImageView

### Community 54 - "TextOverlayView"
Cohesion: 0.09
Nodes (18): RenderKey, Bool, CGPath, CGRect, CGSize, NSCoder, Set, String (+10 more)

### Community 55 - "ObjectTransformOverlayView"
Cohesion: 0.05
Nodes (42): Handle, bottomLeft, bottomRight, .isCorner, .isDrawn, rotation, topLeft, topRight (+34 more)

### Community 56 - "Housekeeping pass (8 items from 2026-07-22 feature audit)"
Cohesion: 0.14
Nodes (15): AppVersion.current stale hardcoded git hash, Color picker discarded hue on gray swatch, deleteCel no-op on layer's last remaining cel, Fill tool off-center fill vertically mirrored (regression), flipCanvas skipped object (photo) layers, FloodFillEngine.fill, ProjectStore.save composites every visible layer for thumbnail, testFillToolBridgesOpenContourGapWhenGapClosingEnabled (XCTSkip) (+7 more)

### Community 57 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 58 - "BrushStamper"
Cohesion: 0.16
Nodes (12): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+4 more)

### Community 59 - "CGPoint"
Cohesion: 0.06
Nodes (35): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, vertices, DeformedCellIndex (+27 more)

### Community 60 - "AlphaMask"
Cohesion: 0.06
Nodes (19): Hashable, CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8 (+11 more)

### Community 61 - "ProjectStore"
Cohesion: 0.10
Nodes (32): CFAbsoluteTime, CelContent, LayerContent, LoadProfile, .millisecondsPerCel, .thumbnailShare, ProjectStore, .lastSaveProfile (+24 more)

### Community 62 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 63 - "ElementData"
Cohesion: 0.07
Nodes (27): Error, ElementData, fill, image, stroke, text, Failure, unknownKind (+19 more)

### Community 64 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 65 - "CanvasManager"
Cohesion: 0.06
Nodes (27): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationOptions (+19 more)

### Community 66 - "View"
Cohesion: 0.08
Nodes (33): stops, View, CodableColor, .color, Color, .effectColor, EffectCatalog, .all (+25 more)

### Community 67 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 68 - "GalleryOpenState"
Cohesion: 0.11
Nodes (17): GalleryOpenState, .isBusy, Bool, UUID, ProjectVersionsView, RecentlyDeletedView, .body, Void (+9 more)

### Community 69 - "SaveDamageGateLogicTests"
Cohesion: 0.16
Nodes (10): SaveDamageGateLogicTests, Any, CanvasManager, Data, StaticString, String, UInt, URL (+2 more)

### Community 70 - "PaintSoftware iPad drawing/animation app"
Cohesion: 0.18
Nodes (13): Animation Timeline feature, Brush library feature (shape/hardness/spacing/stabilization/grain), Native-resolution raster/vector drawing engine (no PencilKit), GPU (Metal) colour-based flood fill feature, Gallery / project browser feature, Layers feature (raster/vector/object layers), PaintSoftware iPad drawing/animation app, Project directory structure (Engine/Models/Services/Utilities/Views) (+5 more)

### Community 72 - "PerfBaselineTests.swift"
Cohesion: 0.18
Nodes (11): CelCRUDCharacterizationTests, Shared frame-length clamp relaxed to >=, duplicateCel adjacent-neighbour overlap bug, Autorelease artifact in re-measuring memory (renderToUIImage), BrushStamper.stampStroke, Stroke cost tracks path length, not sample count, PerfBaselineTests.swift, Refactor Stage 0 — baseline + characterization tests (+3 more)

### Community 73 - "LayerTreeCharacterizationTests"
Cohesion: 0.10
Nodes (6): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 74 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 75 - "ProjectLoadDamage"
Cohesion: 0.11
Nodes (22): DecodedCel, DecodedCels, Cel, CGSize, LayerDamage, .isEmpty, .itemPhrase, .total (+14 more)

### Community 76 - "CompositorMetalEngine"
Cohesion: 0.11
Nodes (27): Admission, admitted, noHeadroom, overBudget, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+19 more)

### Community 77 - "Coordinator"
Cohesion: 0.14
Nodes (12): DispatchWorkItem, Coordinator, LayerStackListView, CanvasManager, Context, Coordinator, UILongPressGestureRecognizer, UIPinchGestureRecognizer (+4 more)

### Community 78 - "Foundation"
Cohesion: 0.10
Nodes (10): Foundation, os, CodableColor, .color, Color, .codable, CodableColor, AppVersion (+2 more)

### Community 79 - "Effect"
Cohesion: 0.09
Nodes (35): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+27 more)

### Community 80 - "Codable"
Cohesion: 0.06
Nodes (43): Codable, CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma (+35 more)

### Community 81 - "DrawingView"
Cohesion: 0.07
Nodes (23): ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void, DamagedSaveBanner (+15 more)

### Community 82 - "SandwichLogicTests"
Cohesion: 0.09
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 83 - "CGImage.cropping(to:) retains parent pixel data"
Cohesion: 0.50
Nodes (4): CGImage.cropping(to:) retains parent pixel data, PixelOps.copiedSubimage, UIGraphicsImageRendererFormat.preferredRange defaults to extended-range on wide-colour iPad, Stage 5 performance work (dab gradient cache, dirty-rect undo)

### Community 84 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Deploy to iPad (deploy.sh, auto-resign), Multi-Session Protocol, deploy/mac/parallel_test.sh, Remote testing via Tailscale to Mac, Worktree-per-session workflow, Foolproof project backups (Session 34)

### Community 85 - "graphify usage protocol"
Cohesion: 0.67
Nodes (3): graphify-out/GRAPH_REPORT.md, .claude/hooks/graphify-guard.sh, graphify usage protocol

### Community 86 - "VectorCanvasDataLogicTests"
Cohesion: 0.17
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 87 - "TextBakeCharacterizationTests"
Cohesion: 0.17
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 88 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 89 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 90 - ".setBakedContent"
Cohesion: 0.11
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 91 - "PointCloudIndex"
Cohesion: 0.07
Nodes (21): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+13 more)

### Community 92 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 93 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+13 more)

### Community 94 - "InterpolationRenderLogicTests"
Cohesion: 0.18
Nodes (9): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int, UIImage, UUID (+1 more)

### Community 95 - "Layer Compositing"
Cohesion: 0.07
Nodes (29): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+21 more)

### Community 109 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 110 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 111 - "CodingKey"
Cohesion: 0.07
Nodes (30): CodingKey, CodingKeys, endPoint, kind, rotation, spanStart, spanSweep, startPoint (+22 more)

### Community 112 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 113 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 114 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 115 - "DeformFactorization"
Cohesion: 0.11
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 116 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 117 - "RenderNode"
Cohesion: 0.08
Nodes (31): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+23 more)

### Community 118 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 119 - "BlockDragCharacterizationTests"
Cohesion: 0.20
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 120 - "RenderRequest"
Cohesion: 0.10
Nodes (27): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, RenderResolution, full (+19 more)

### Community 121 - "MaskSource"
Cohesion: 0.12
Nodes (16): Kind, folder, layer, MaskSource, folder, .id, layer, Decoder (+8 more)

### Community 122 - "VectorSample"
Cohesion: 0.04
Nodes (29): Brush, BrushDynamics, BrushGrain, Bool, Double, UUID, BrushLibrary, .customBrushesDirectory (+21 more)

### Community 124 - "TextTransformOverlayView"
Cohesion: 0.12
Nodes (16): Bool, CALayer, CGRect, NSCoder, Set, UIEvent, UITouch, Void (+8 more)

### Community 125 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 126 - "Compositor.swift"
Cohesion: 0.13
Nodes (22): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), CompositeProbe, Compositor (+14 more)

### Community 128 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 129 - "VectorTransformUndoLogicTests"
Cohesion: 0.24
Nodes (8): CanvasManager, CGAffineTransform, Int, LayerTransform, StaticString, String, UInt, VectorTransformUndoLogicTests

### Community 130 - "Typography"
Cohesion: 0.15
Nodes (13): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, UIFont, TextLayout, ClosedRange (+5 more)

### Community 131 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 132 - "EyedropperLogicTests"
Cohesion: 0.09
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 133 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 134 - "GuideStroke"
Cohesion: 0.13
Nodes (15): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+7 more)

### Community 135 - "InterpolateBar"
Cohesion: 0.08
Nodes (26): .body, GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton (+18 more)

### Community 136 - ".launchIntoEditor"
Cohesion: 0.16
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, UndoAndLayerHistoryUITests

### Community 137 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 138 - ".draw"
Cohesion: 0.34
Nodes (7): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 139 - "TextHitTestLogicTests"
Cohesion: 0.18
Nodes (7): TextMeasure, Bool, CGAffineTransform, CGSize, String, VectorStroke, TextHitTestLogicTests

### Community 140 - ".backfillMissingThumbnails"
Cohesion: 0.20
Nodes (10): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+2 more)

### Community 141 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 142 - "CanvasNotice"
Cohesion: 0.07
Nodes (18): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, Kind, hiddenLayer (+10 more)

### Community 143 - "SpacingChart"
Cohesion: 0.19
Nodes (4): SpacingChart, .curve, .draggable, Range

### Community 144 - "OnionSkinLogicTests"
Cohesion: 0.21
Nodes (5): CelSpan, .end, OnionSkinPlanner, Bool, OnionSkinLogicTests

### Community 145 - "4. Future upgrades — the deferred list"
Cohesion: 0.15
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 146 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 147 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 148 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 149 - "LassoFillLogicTests"
Cohesion: 0.09
Nodes (16): LassoFillMask, Float, Int, SIMD4, UInt8, mask, LassoFillLogicTests, .loopAroundEverything (+8 more)

### Community 150 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+9 more)

### Community 151 - "PinchMergeGateLogicTests"
Cohesion: 0.19
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 152 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 153 - "TimelineRowView"
Cohesion: 0.12
Nodes (17): MenuRequest, block, gap, loop, Bool, Coordinator, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 154 - ".refreshUndoRedoState"
Cohesion: 0.08
Nodes (16): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage (+8 more)

### Community 155 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 156 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 157 - "ShapeHoldClock"
Cohesion: 0.21
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 159 - "VectorEraserMode"
Cohesion: 0.06
Nodes (27): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+19 more)

### Community 160 - ".rows"
Cohesion: 0.16
Nodes (13): IndexPath, .rows, DropTarget, between, onto, LayerStackListView.Coordinator, Int, Set (+5 more)

### Community 161 - "CanvasPresentation"
Cohesion: 0.12
Nodes (14): CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id, interpolateOptions (+6 more)

### Community 162 - "MotionGroup"
Cohesion: 0.17
Nodes (11): GroupRegistration, Layer, String, GroupInterpolation, auto, clean, crossFade, MotionGroup (+3 more)

### Community 163 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 164 - "OnionSkinPanel"
Cohesion: 0.11
Nodes (21): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+13 more)

### Community 165 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 166 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 167 - "EffectPipelines"
Cohesion: 0.13
Nodes (17): Metal, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue (+9 more)

### Community 168 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 170 - "VectorPreviewPlanLogicTests"
Cohesion: 0.13
Nodes (11): Bool, String, VectorPreviewPlan, VectorScratchRole, none, overlay, replacement, .traceName (+3 more)

### Community 171 - "1. The decisions"
Cohesion: 0.15
Nodes (13): 1. The decisions, `ActionsMenu` gains the ability to enter a mode, Fonts go through one seam and nothing else, Handles live outside the warped layer, Live warp is Core Animation; the bake is a compute kernel, Persistence: one new case, no sidecar, no version number, Point text grows; a box you sized wraps, The bake trigger is one line (+5 more)

### Community 172 - "SwiftUI"
Cohesion: 0.13
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 173 - "Int"
Cohesion: 0.19
Nodes (6): OnionSkinBudget, OnionSkinOpacityRamp, CGSize, Double, Int, Int

### Community 174 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 175 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 176 - "GuidePath"
Cohesion: 0.24
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 177 - ".compositeSize"
Cohesion: 0.12
Nodes (12): NSObjectProtocol, .resolutionNoteText, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel (+4 more)

### Community 178 - "MetalFillSession"
Cohesion: 0.19
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 179 - "OnionSkinSettings"
Cohesion: 0.17
Nodes (11): .gradientStops, .opacitySliders, OnionSkinSettings, Side, .id, next, previous, .step (+3 more)

### Community 180 - ".setUpGestures"
Cohesion: 0.13
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 181 - "Add Text"
Cohesion: 0.15
Nodes (10): 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, Add Text, Done this pass, In flight, Queued (+2 more)

### Community 182 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 183 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 184 - "TextRecipeCodableLogicTests"
Cohesion: 0.15
Nodes (5): StaticString, String, T, UInt, TextRecipeCodableLogicTests

### Community 185 - "CGRect"
Cohesion: 0.21
Nodes (10): CGRect, ClosedRange, NSCoder, String, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView (+2 more)

### Community 186 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

### Community 187 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 188 - ".sample"
Cohesion: 0.18
Nodes (13): NSObject, ObjectiveC.runtime, FoundElement, ResolvedTarget, Bool, CGRect, CGSize, Double (+5 more)

### Community 189 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 190 - "CodingKeys"
Cohesion: 0.09
Nodes (22): CodingKeys, brush, color, composite, elements, fill, fills, id (+14 more)

### Community 191 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 192 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 193 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 194 - "LayerRowModel"
Cohesion: 0.16
Nodes (11): String, UIColor, LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, CGRect (+3 more)

### Community 195 - "UndoHistory"
Cohesion: 0.19
Nodes (9): Action, Bool, Int, Void, UndoBudget, UndoHistory, .canRedo, .canUndo (+1 more)

### Community 196 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 197 - ".textureBudgetBytes"
Cohesion: 0.47
Nodes (4): CompositorBudget, .textureBudgetBytes, Int, UInt64

### Community 198 - "FillGestureRestartLogicTests"
Cohesion: 0.22
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 199 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.25
Nodes (3): CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 200 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 201 - "Lasso Fill — Specification"
Cohesion: 0.17
Nodes (11): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 2a. What "filled over" means, and what the owner ruled on 2026-08-21, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill (+3 more)

### Community 202 - "OnionSkinSource.swift"
Cohesion: 0.17
Nodes (7): OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager, StaticString, UIImage, UInt

### Community 203 - "SelectionOverlayLogicTests"
Cohesion: 0.16
Nodes (6): resolvedLastTouchType(), UITouch, SelectionOverlayLogicTests, Bool, UITouch, S

### Community 205 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 206 - "CanvasPresentationLogicTests"
Cohesion: 0.15
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 207 - ".perfManager"
Cohesion: 0.22
Nodes (4): Bool, CanvasManager, Int, UIImage

### Community 208 - "CGContextDabTarget"
Cohesion: 0.23
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 209 - "TextRecipe"
Cohesion: 0.11
Nodes (19): Bool, CGContext, CGRect, CGSize, UIImage, Alignment, center, .displayName (+11 more)

### Community 211 - "StructureSnapshot"
Cohesion: 0.23
Nodes (4): CanvasManager, StructureSnapshot, Int, Layer

### Community 212 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 213 - ".relayout"
Cohesion: 0.21
Nodes (7): Context, UIPinchGestureRecognizer, Void, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 214 - ".performDrag"
Cohesion: 0.16
Nodes (5): InterpolationWorkflowUITests, Bool, TimeInterval, XCUIElement, TimelineGestureUITests

### Community 215 - "TimelineLayoutKey"
Cohesion: 0.29
Nodes (12): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+4 more)

### Community 216 - "LassoFillDiagnostic"
Cohesion: 0.38
Nodes (6): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID

### Community 217 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 218 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.18
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 220 - ".frames"
Cohesion: 0.20
Nodes (3): CGRect, Range, TimelineRulerClip

### Community 221 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 222 - "TimedSample"
Cohesion: 0.13
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 223 - "Handoff — 2026-08-21"
Cohesion: 0.22
Nodes (6): Five things this pass learned the hard way, Handoff — 2026-08-21, What is worth doing next, What just got re-scoped: PERFORMANCE.md item 14, What shipped, What the owner still owes a ruling on

### Community 224 - "MemoryBudgetLogicTests"
Cohesion: 0.20
Nodes (6): UInt64, .maxCostBytes, MemoryBudgetLogicTests, Int, String, UInt64

### Community 225 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 226 - "CanvasPresentationModifier"
Cohesion: 0.31
Nodes (6): CanvasPresentationModifier, Bool, CanvasManager, Void, PresentedContent, ViewModifier

### Community 227 - "1. The decisions"
Cohesion: 0.15
Nodes (13): 1. The decisions, A fill is a `CGPath`, and cutting a chunk out of it is two Core Graphics calls, A moved piece carries a **translated** dab lattice; a stationary piece keeps the parent's, An erase punch is a stroke and moves like one, Identity: fresh ids, in-place splice, tags inherited, Interpolation: out of scope, and the guard already exists, Selection is by **centreline**, not by ink — and the alternative is a real feature, not a constant, Text moves whole, if the lasso contains its centre (+5 more)

### Community 229 - "Lasso Move — Specification"
Cohesion: 0.25
Nodes (8): 0. How much of this already exists, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, 6. Open risks, Lasso Move — Specification, Still needs a ruling, and stage 1 can start without any of it

### Community 230 - "Attempt"
Cohesion: 0.32
Nodes (6): Attempt, image, unavailable, underPressure, MetalCompositor, CGImage

### Community 231 - ".handleShouldReceive"
Cohesion: 0.36
Nodes (4): Bool, ObjectIdentifier, UIGestureRecognizer, UITouch

### Community 232 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 233 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 234 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **1021 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+1016 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **22 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CGFloat` connect `CGFloat` to `Coordinator`, `CanvasManager`, `ShapeOverlayView`, `String`, `cels`, `StrokeCanvasView`, `ActionRecorder`, `BrushEngineLogicTests`, `TextFrame`, `UIKit`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `InterpolationRecipe`, `.rasterize`, `layers`, `CanvasManager`, `ARAPLogicTests`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `Binding`, `Coordinator`, `FloatingPieceOverlayView`, `AnimationTimeline`, `LayerStackCell`, `VectorCanvas`, `TextTransformLogicTests`, `FontDescriptor`, `WindowEventTap`, `SideToolbar`, `TextOverlayView`, `ObjectTransformOverlayView`, `XCUIApplication`, `BrushStamper`, `CGPoint`, `AlphaMask`, `ProjectStore`, `StrokeStabilizer`, `CompositorParityLogicTests`, `CanvasManager`, `View`, `.apply`, `Coordinator`, `DrawingView`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `TextBakeCharacterizationTests`, `.setBakedContent`, `PointCloudIndex`, `.evaluate`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `GuideOverlayView`, `DeformFactorization`, `RenderRequest`, `VectorSample`, `InterpolationGuideLogicTests`, `TextTransformOverlayView`, `.indices`, `CanvasManager`, `VectorTransformUndoLogicTests`, `Typography`, `.arched`, `InterpolateBar`, `.launchIntoEditor`, `.draw`, `TextHitTestLogicTests`, `.manager`, `SpacingChart`, `TransformOverlaySupport.swift`, `LassoFillLogicTests`, `CanvasManager`, `PinchMergeGateLogicTests`, `StrokeSpatialIndex`, `TimelineRowView`, `.refreshUndoRedoState`, `CanvasTransformFreezeUITests`, `VectorEraserMode`, `.rows`, `CurveEditor`, `Int`, `JSONValue`, `GuidePath`, `.compositeSize`, `CGRect`, `SandwichCompositingUITests`, `.sample`, `Kind`, `CodingKeys`, `ActionsMenu`, `TextSettingsPanel`, `LayerRowModel`, `TimelineLayoutKeyLogicTests`, `OnionSkinSource.swift`, `CGContextDabTarget`, `TextRecipe`, `.relayout`, `.performDrag`, `TimelineLayoutKey`, `.frames`, `TimedSample`?**
  _High betweenness centrality (0.251) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `CGFloat`, `Typography`, `VectorTransformUndoLogicTests`, `EyedropperLogicTests`, `ColorPickerPanel`, `Coordinator`, `CanvasManager`, `.arched`, `ShapeOverlayView`, `String`, `cels`, `StrokeCanvasView`, `.manager`, `BrushEngineLogicTests`, `TextFrame`, `UIKit`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `TransformOverlaySupport.swift`, `.rasterize`, `layers`, `CanvasManager`, `ARAPLogicTests`, `StrokeSpatialIndex`, `CanvasManager`, `.refreshUndoRedoState`, `TimelineRowView`, `InterpolationRecipe`, `LassoFillLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `.rows`, `VectorEraserHybridLogicTests`, `Coordinator`, `CurveEditor`, `AnimationTimeline`, `FloatingPieceOverlayView`, `ProjectSaveLogicTests`, `VectorCanvas`, `VectorCanvasData`, `SelectionOverlayView`, `TextTransformLogicTests`, `GuidePath`, `WindowEventTap`, `.setUpGestures`, `.makeUIView`, `TextOverlayView`, `ObjectTransformOverlayView`, `TextRecipeCodableLogicTests`, `CGRect`, `BrushStamper`, `.sample`, `AlphaMask`, `StrokeStabilizer`, `TextHitTestLogicTests`, `CanvasManager`, `SaveDamageGateLogicTests`, `FillGestureRestartLogicTests`, `.sampledColor`, `.perfManager`, `CGContextDabTarget`, `TextBakeCharacterizationTests`, `PointCloudIndex`, `.frames`, `.evaluate`, `TimedSample`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `GuideOverlayView`, `DeformFactorization`, `VectorSample`, `InterpolationGuideLogicTests`, `TextTransformOverlayView`, `.indices`?**
  _High betweenness centrality (0.162) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `PaintUITestCase`, `CGFloat`, `ProjectBackupManager`, `.manager`, `EyedropperLogicTests`, `Typography`, `VectorTransformUndoLogicTests`, `VectorCanvasData`, `cels`, `TextHitTestLogicTests`, `BrushEngineLogicTests`, `CanvasNotice`, `UIKit`, `OnionSkinLogicTests`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `LassoFillLogicTests`, `ARAPLogicTests`, `PinchMergeGateLogicTests`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `ShapeHoldClock`, `StrokeGestureRecognizer`, `VectorEraserMode`, `ProjectSaveLogicTests`, `VectorPreviewPlanLogicTests`, `TextTransformLogicTests`, `RenderTreeCharacterizationTests`, `FontDescriptor`, `MaskGuardLogicTests`, `ObjectTransformOverlayView`, `TextRecipeCodableLogicTests`, `CGPoint`, `AlphaMask`, `FillBoundaryLogicTests`, `CompositorParityLogicTests`, `GalleryOpenState`, `SaveDamageGateLogicTests`, `FillGestureRestartLogicTests`, `TimelineLayoutKeyLogicTests`, `LayerTreeCharacterizationTests`, `SelectionOverlayLogicTests`, `CanvasPresentationLogicTests`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `TextBakeCharacterizationTests`, `.setBakedContent`, `PointCloudIndex`, `EffectMultiPassLogicTests`, `SelectionPersistenceLogicTests`, `InterpolationRenderLogicTests`, `MemoryBudgetLogicTests`, `InterpolationModelLogicTests`, `PlaybackBoundsCharacterizationTests`, `EffectParityLogicTests`, `BlockDragCharacterizationTests`, `VectorSample`, `InterpolationGuideLogicTests`?**
  _High betweenness centrality (0.095) - this node is a cross-community bridge._
- **Are the 82 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 82 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 6 INFERRED edges - model-reasoned connections that need verification._