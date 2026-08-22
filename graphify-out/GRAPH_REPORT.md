# Graph Report - PaintSoftware  (2026-08-22)

## Corpus Check
- 243 files · ~775,806 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 7257 nodes · 22110 edges · 249 communities (227 shown, 22 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2219 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3f174d1f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PaintUITestCase
- CGPoint
- ProjectBackupManager
- .manager
- TimelineRowView
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
- StrokeGeometry
- VectorEraserLogicTests
- Codable
- .rasterize
- layers
- CanvasManager
- PointCloudIndex
- ViewPreset
- .drawLine
- ParityScenario
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
- View
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
- ARAPLogicTests
- TextOverlayView
- ObjectTransformOverlayView
- Housekeeping pass (8 items from 2026-07-22 feature audit)
- XCUIApplication
- .stampStroke
- Lattice
- AlphaMask
- ProjectStore
- StrokeStabilizer
- VectorEraserHybridLogicTests
- .setBakedContent
- CanvasManager
- .rows
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
- CodingKeys
- DrawingView
- SandwichLogicTests
- CGImage.cropping(to:) retains parent pixel data
- Multi-Session Protocol
- graphify usage protocol
- VectorCanvasDataLogicTests
- TextBakeCharacterizationTests
- .reconcileLayers
- parallel_test.sh
- EffectLayerLogicTests
- InterpolationEngineDiagnosticsLogicTests
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
- EraserSettingsPanel
- CodingKeys
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
- GuideRow
- InterpolateBar
- .launchIntoEditor
- EffectParams
- .draw
- TextHitTestLogicTests
- .backfillMissingThumbnails
- .manager
- CanvasNotice
- SpacingChart
- .resolvedCelIndices
- 4. Future upgrades — the deferred list
- BrushDynamics
- Kind
- command
- LassoFillLogicTests
- CanvasManager
- PinchMergeGateLogicTests
- StrokeSpatialIndex
- StrokeGeometryLogicTests
- .refreshUndoRedoState
- Gesture
- CanvasTransformFreezeUITests
- ShapeHoldClock
- run.sh
- VectorEraserMode
- LayerRowModel
- MetalFillSession
- StructureSnapshot
- CurveEditor
- OnionSkinPanel
- .row
- Recording
- EffectPipelines
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- .dragOnCanvas
- VectorPreviewPlanLogicTests
- 1. The decisions
- SwiftUI
- Int
- JSONValue
- CodingKeys
- .validateProject
- .compositeSize
- Brush
- OnionSkinSettings
- Handle
- Add Text
- Is the brush engine ready for `.ABR` / Procreate brush import?
- MaskGuardLogicTests
- TextRecipe
- CGRect
- simlock.sh
- SandwichCompositingUITests
- .sample
- .attach
- Kind
- FillBoundaryLogicTests
- ActionsMenu
- TextSettingsPanel
- Kind
- UndoHistory
- Performance
- CGSize
- FillGestureRestartLogicTests
- TimelineLayoutKeyLogicTests
- .sampledColor
- Lasso Fill — Specification
- OnionSkinLogicTests
- ObjectTransformFrame
- RecordingWriter
- Atomic
- CanvasPresentationLogicTests
- CGFloat
- DabTarget
- CompositeProbe
- BrushStamper
- CodingKey
- MenuInterruptionUITests
- Coordinator
- .group
- TimelineLayoutKey
- .upright
- Kind
- Every dismissible presentation, and whether a stroke under it breaks
- SelectionPersistenceLogicTests
- .frames
- CutOutcome
- TimedSample
- TODO
- ObjectTransformLogicTests
- Color
- CanvasPresentationModifier
- 1. The decisions
- presentation-census.sh
- Lasso Move — Specification
- Int
- .handleShouldReceive
- CanvasManager
- ValueFill
- CompositorRole
- .relayout
- Handoff — 2026-08-22
- TransformOverlaySupport.swift
- LayerKind
- UIEvent
- ManifestSkeleton
- Edge
- SandwichPresentation
- MenuRequest
- Failure
- BlendMode
- .init
- .encode

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 796 edges
2. `CGFloat` - 569 edges
3. `CanvasManager` - 170 edges
4. `VectorCanvas` - 159 edges
5. `Effect` - 149 edges
6. `layers` - 126 edges
7. `VectorSample` - 125 edges
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

## Communities (249 total, 22 thin omitted)

### Community 0 - "PaintUITestCase"
Cohesion: 0.10
Nodes (13): FillLiveAdjustUITests, HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests (+5 more)

### Community 1 - "CGPoint"
Cohesion: 0.05
Nodes (30): CGPoint, .length, Int, Corner, bottomLeft, bottomRight, topLeft, topRight (+22 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.09
Nodes (26): DateFormatter, Notification.Name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+18 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.13
Nodes (17): Kind, cel, gap, Segment, Cel, Int, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+29 more)

### Community 6 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 7 - "CanvasManager"
Cohesion: 0.03
Nodes (67): Never, Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+59 more)

### Community 8 - "VectorCanvasData"
Cohesion: 0.09
Nodes (22): VectorTextElement, DecodeReport, .droppedCount, .isClean, ElementData, fill, image, stroke (+14 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 10 - "String"
Cohesion: 0.02
Nodes (111): CaseIterable, Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+103 more)

### Community 11 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (25): CAShapeLayer, StrokeInput, TimeInterval, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+17 more)

### Community 13 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 14 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 15 - "TextFrame"
Cohesion: 0.10
Nodes (24): Int, Basis, Corner, bottomLeft, bottomRight, topLeft, topRight, Mode (+16 more)

### Community 16 - "UIKit"
Cohesion: 0.07
Nodes (5): CoreGraphics, Darwin, simd, UIKit, XCTest

### Community 17 - "StrokeGeometry"
Cohesion: 0.11
Nodes (10): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, .clamped (+2 more)

### Community 18 - "VectorEraserLogicTests"
Cohesion: 0.10
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 19 - "Codable"
Cohesion: 0.06
Nodes (35): Codable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+27 more)

### Community 20 - ".rasterize"
Cohesion: 0.12
Nodes (21): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+13 more)

### Community 21 - "layers"
Cohesion: 0.10
Nodes (17): .activeLayerIsVector, .guideRefusal, .interpolationTarget, .linkableGuideStrokes, Int, CanvasManager, Bool, Int (+9 more)

### Community 22 - "CanvasManager"
Cohesion: 0.10
Nodes (19): CanvasManager, .fillEdgeOverlap, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel (+11 more)

### Community 23 - "PointCloudIndex"
Cohesion: 0.13
Nodes (17): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+9 more)

### Community 24 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 25 - ".drawLine"
Cohesion: 0.12
Nodes (10): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, EraserAndPersistenceUITests (+2 more)

### Community 26 - "ParityScenario"
Cohesion: 0.09
Nodes (33): CustomStringConvertible, UIImage, UInt8, Backdrop, fill, image, none, Gesture (+25 more)

### Community 27 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 28 - "PerfBaselineTests"
Cohesion: 0.15
Nodes (4): PerfBaselineTests, Double, String, UInt64

### Community 29 - "Fill.metal"
Cohesion: 0.17
Nodes (41): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+33 more)

### Community 30 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 31 - "RasterLayerTexture"
Cohesion: 0.12
Nodes (17): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+9 more)

### Community 32 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 33 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 34 - "Binding"
Cohesion: 0.10
Nodes (27): Accessory, KeyPath, .isTimelineMenuPresented, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager (+19 more)

### Community 35 - "Coordinator"
Cohesion: 0.06
Nodes (26): CanvasView, Coordinator, .canvasContentScale, .isLassoFilling, .sandwichPresentation, OnionSkinKey, CALayer, CanvasManager (+18 more)

### Community 36 - "FloatingPieceOverlayView"
Cohesion: 0.10
Nodes (19): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+11 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.04
Nodes (49): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+41 more)

### Community 38 - "View"
Cohesion: 0.14
Nodes (29): View, .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex (+21 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.10
Nodes (14): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase (+6 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): effectMenuSlug(), LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String (+4 more)

### Community 41 - "VectorCanvas"
Cohesion: 0.07
Nodes (43): CodableColor, .uiColor, image, DabLattice, .range, kind, Bool, CGAffineTransform (+35 more)

### Community 42 - "XCTestCase"
Cohesion: 0.14
Nodes (11): CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor (+3 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 44 - "TextTransformLogicTests"
Cohesion: 0.10
Nodes (10): TextFrameDrag, Bool, CanvasManager, CGRect, CGSize, Int, StaticString, String (+2 more)

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
Cohesion: 0.23
Nodes (14): CelManifest, FolderManifest, LayerManifest, ProjectManifest, BlendMode, Bool, CodableColor, Date (+6 more)

### Community 50 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 51 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 52 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 53 - "ARAPLogicTests"
Cohesion: 0.12
Nodes (9): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, Int, StaticString, String (+1 more)

### Community 54 - "TextOverlayView"
Cohesion: 0.09
Nodes (18): RenderKey, Bool, CGPath, CGRect, CGSize, NSCoder, Set, String (+10 more)

### Community 55 - "ObjectTransformOverlayView"
Cohesion: 0.11
Nodes (15): ObjectTransformOverlayView, .canvasScale, .drawnChrome, .handleBorderWidth, .handleReach, .handleSize, .outlineWidth, .rotationHandleSize (+7 more)

### Community 56 - "Housekeeping pass (8 items from 2026-07-22 feature audit)"
Cohesion: 0.14
Nodes (15): AppVersion.current stale hardcoded git hash, Color picker discarded hue on gray swatch, deleteCel no-op on layer's last remaining cel, Fill tool off-center fill vertically mirrored (regression), flipCanvas skipped object (photo) layers, FloodFillEngine.fill, ProjectStore.save composites every visible layer for thumbnail, testFillToolBridgesOpenContourGapWhenGapClosingEnabled (XCTSkip) (+7 more)

### Community 57 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 58 - ".stampStroke"
Cohesion: 0.19
Nodes (8): DabRNG, DiscardedDabTarget, Bool, CGBlendMode, ClosedRange, Double, UIColor, UInt64

### Community 59 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 60 - "AlphaMask"
Cohesion: 0.06
Nodes (19): Hashable, CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8 (+11 more)

### Community 61 - "ProjectStore"
Cohesion: 0.08
Nodes (44): CFAbsoluteTime, os, CelContent, CodableColor, .color, Color, .codable, DecodedCel (+36 more)

### Community 62 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 63 - "VectorEraserHybridLogicTests"
Cohesion: 0.12
Nodes (15): UUID, VectorStroke, Gesture, diagonalCut, edgeShave, .label, .samples, squareCut (+7 more)

### Community 64 - ".setBakedContent"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 65 - "CanvasManager"
Cohesion: 0.05
Nodes (40): CanvasManager, .activeCelIsInBetween, .guideChips, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+32 more)

### Community 66 - ".rows"
Cohesion: 0.11
Nodes (26): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+18 more)

### Community 67 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 68 - "GalleryOpenState"
Cohesion: 0.14
Nodes (13): GalleryOpenState, .isBusy, Bool, UUID, GalleryTileView, .body, Bool, Void (+5 more)

### Community 69 - "SaveDamageGateLogicTests"
Cohesion: 0.17
Nodes (9): SaveDamageGateLogicTests, Any, CanvasManager, Data, StaticString, String, UInt, URL (+1 more)

### Community 70 - "PaintSoftware iPad drawing/animation app"
Cohesion: 0.18
Nodes (13): Animation Timeline feature, Brush library feature (shape/hardness/spacing/stabilization/grain), Native-resolution raster/vector drawing engine (no PencilKit), GPU (Metal) colour-based flood fill feature, Gallery / project browser feature, Layers feature (raster/vector/object layers), PaintSoftware iPad drawing/animation app, Project directory structure (Engine/Models/Services/Utilities/Views) (+5 more)

### Community 72 - "PerfBaselineTests.swift"
Cohesion: 0.18
Nodes (11): CelCRUDCharacterizationTests, Shared frame-length clamp relaxed to >=, duplicateCel adjacent-neighbour overlap bug, Autorelease artifact in re-measuring memory (renderToUIImage), BrushStamper.stampStroke, Stroke cost tracks path length, not sample count, PerfBaselineTests.swift, Refactor Stage 0 — baseline + characterization tests (+3 more)

### Community 73 - "LayerTreeCharacterizationTests"
Cohesion: 0.11
Nodes (6): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 74 - ".apply"
Cohesion: 0.27
Nodes (10): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+2 more)

### Community 75 - "ProjectLoadDamage"
Cohesion: 0.13
Nodes (18): LayerDamage, .isEmpty, .itemPhrase, .total, ProjectLoadDamage, .isDamaged, .itemCount, .summary (+10 more)

### Community 76 - "CompositorMetalEngine"
Cohesion: 0.09
Nodes (30): Admission, admitted, noHeadroom, overBudget, Attempt, image, unavailable, underPressure (+22 more)

### Community 77 - "Coordinator"
Cohesion: 0.20
Nodes (11): .body, Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID (+3 more)

### Community 78 - "Foundation"
Cohesion: 0.12
Nodes (4): Foundation, AppVersion, .versionString, String

### Community 79 - "Effect"
Cohesion: 0.08
Nodes (41): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+33 more)

### Community 80 - "CodingKeys"
Cohesion: 0.05
Nodes (42): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+34 more)

### Community 81 - "DrawingView"
Cohesion: 0.05
Nodes (32): ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void, DamagedSaveBanner (+24 more)

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
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 87 - "TextBakeCharacterizationTests"
Cohesion: 0.17
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 88 - ".reconcileLayers"
Cohesion: 0.11
Nodes (9): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, SandwichKey, TimeInterval, UIImage (+1 more)

### Community 89 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 90 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 91 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 92 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 93 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 94 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): StrokeComposite, erase, paint, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int (+3 more)

### Community 95 - "Layer Compositing"
Cohesion: 0.07
Nodes (29): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+21 more)

### Community 109 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 110 - "EraserSettingsPanel"
Cohesion: 0.15
Nodes (13): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+5 more)

### Community 111 - "CodingKeys"
Cohesion: 0.10
Nodes (21): CodingKeys, brush, color, composite, elements, fill, fills, id (+13 more)

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
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 116 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 117 - "RenderNode"
Cohesion: 0.08
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 118 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 119 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 120 - "RenderRequest"
Cohesion: 0.10
Nodes (27): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, RenderResolution, full (+19 more)

### Community 121 - "MaskSource"
Cohesion: 0.14
Nodes (13): MaskSource, folder, .id, layer, Encoder, UUID, Void, body (+5 more)

### Community 122 - "VectorSample"
Cohesion: 0.15
Nodes (7): VectorSample, .point, VectorStroke, CountingDabTarget, StrokeSampleGateLogicTests, UInt64, Tremor

### Community 124 - "TextTransformOverlayView"
Cohesion: 0.12
Nodes (16): Bool, CALayer, CGRect, NSCoder, Set, UIEvent, UITouch, Void (+8 more)

### Community 125 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 126 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 128 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 129 - "VectorTransformUndoLogicTests"
Cohesion: 0.24
Nodes (8): CanvasManager, CGAffineTransform, Int, LayerTransform, StaticString, String, UInt, VectorTransformUndoLogicTests

### Community 130 - "Typography"
Cohesion: 0.12
Nodes (18): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGRect (+10 more)

### Community 131 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 132 - "EyedropperLogicTests"
Cohesion: 0.11
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 133 - ".arched"
Cohesion: 0.25
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 134 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 135 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 136 - ".launchIntoEditor"
Cohesion: 0.18
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 137 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 138 - ".draw"
Cohesion: 0.34
Nodes (7): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 139 - "TextHitTestLogicTests"
Cohesion: 0.17
Nodes (7): TextMeasure, Bool, CGAffineTransform, CGSize, String, VectorStroke, TextHitTestLogicTests

### Community 140 - ".backfillMissingThumbnails"
Cohesion: 0.18
Nodes (9): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+1 more)

### Community 141 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 142 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 143 - "SpacingChart"
Cohesion: 0.19
Nodes (4): SpacingChart, .curve, .draggable, Range

### Community 144 - ".resolvedCelIndices"
Cohesion: 0.14
Nodes (5): CelSpan, .end, OnionSkinPlanner, OnionSkinSource, Bool

### Community 145 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 146 - "BrushDynamics"
Cohesion: 0.14
Nodes (8): BrushDynamics, BrushGrain, Bool, Double, UUID, BrushLibrary, .customBrushesDirectory, URL

### Community 147 - "Kind"
Cohesion: 0.14
Nodes (14): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+6 more)

### Community 148 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 149 - "LassoFillLogicTests"
Cohesion: 0.07
Nodes (18): LassoFillMask, Float, Int, SIMD4, UInt8, mask, LassoFillLogicTests, .loopAroundEverything (+10 more)

### Community 150 - "CanvasManager"
Cohesion: 0.09
Nodes (25): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+17 more)

### Community 151 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 152 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 153 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (6): StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 154 - ".refreshUndoRedoState"
Cohesion: 0.12
Nodes (7): CanvasManager, .activeEditColor, .isTextInAdjustableState, Bool, Color, String, UUID

### Community 155 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 156 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 157 - "ShapeHoldClock"
Cohesion: 0.19
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 159 - "VectorEraserMode"
Cohesion: 0.06
Nodes (27): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+19 more)

### Community 160 - "LayerRowModel"
Cohesion: 0.11
Nodes (20): DispatchWorkItem, IndexPath, DropTarget, between, onto, LayerRowModel, .folderID, .isFolder (+12 more)

### Community 161 - "MetalFillSession"
Cohesion: 0.19
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 162 - "StructureSnapshot"
Cohesion: 0.20
Nodes (4): CanvasManager, StructureSnapshot, Int, Layer

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

### Community 169 - ".dragOnCanvas"
Cohesion: 0.15
Nodes (3): SelectionAndMoveUITests, ToolPanelsUITests, GalleryRecoveryUITests

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
Cohesion: 0.20
Nodes (6): OnionSkinBudget, OnionSkinOpacityRamp, CGSize, Double, Int, Int

### Community 174 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 175 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 176 - ".validateProject"
Cohesion: 0.17
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 177 - ".compositeSize"
Cohesion: 0.13
Nodes (12): NSObjectProtocol, .resolutionNoteText, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel (+4 more)

### Community 178 - "Brush"
Cohesion: 0.15
Nodes (8): Brush, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser, VectorStroke

### Community 179 - "OnionSkinSettings"
Cohesion: 0.15
Nodes (11): .opacitySliders, OnionSkinSettings, Side, .id, next, .step, CodableColor, Double (+3 more)

### Community 180 - "Handle"
Cohesion: 0.15
Nodes (13): Handle, bottom, bottomLeft, bottomRight, .heightSign, .isResize, left, right (+5 more)

### Community 181 - "Add Text"
Cohesion: 0.25
Nodes (5): 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, Add Text

### Community 182 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 183 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 184 - "TextRecipe"
Cohesion: 0.12
Nodes (9): CodableColor, Double, TextRecipe, .styleOnly, StaticString, String, T, UInt (+1 more)

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

### Community 189 - ".attach"
Cohesion: 0.23
Nodes (5): Context, UIPinchGestureRecognizer, .gradientStops, previous, UITableView

### Community 190 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 191 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 192 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 193 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 194 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 195 - "UndoHistory"
Cohesion: 0.12
Nodes (15): Action, Bool, Int, UInt64, Void, UndoBudget, .maxCostBytes, UndoHistory (+7 more)

### Community 196 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 197 - "CGSize"
Cohesion: 0.33
Nodes (5): CompositorBudget, .textureBudgetBytes, Int, UInt64, CGSize

### Community 198 - "FillGestureRestartLogicTests"
Cohesion: 0.22
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 199 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.27
Nodes (3): CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 200 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 201 - "Lasso Fill — Specification"
Cohesion: 0.17
Nodes (11): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 2a. Where a fill lands in the stack: on top of everything already on the layer, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill (+3 more)

### Community 202 - "OnionSkinLogicTests"
Cohesion: 0.23
Nodes (6): OnionSkinSettingsSource, OnionSkinLogicTests, Bool, CanvasManager, UIImage, VectorStroke

### Community 203 - "ObjectTransformFrame"
Cohesion: 0.11
Nodes (14): Handle, bottomLeft, bottomRight, .isCorner, .isDrawn, rotation, topLeft, topRight (+6 more)

### Community 205 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 206 - "CanvasPresentationLogicTests"
Cohesion: 0.15
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 207 - "CGFloat"
Cohesion: 0.06
Nodes (22): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Sample, Void (+14 more)

### Community 208 - "DabTarget"
Cohesion: 0.20
Nodes (10): AnyObject, CGGradient, Key, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode (+2 more)

### Community 210 - "BrushStamper"
Cohesion: 0.17
Nodes (5): BrushStamper, Bool, CanvasManager, Int, UIImage

### Community 211 - "CodingKey"
Cohesion: 0.08
Nodes (24): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+16 more)

### Community 212 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 213 - "Coordinator"
Cohesion: 0.17
Nodes (9): BlockDrag, CelBlockView, Coordinator, Bool, CanvasManager, Coordinator, UIImage, Void (+1 more)

### Community 214 - ".group"
Cohesion: 0.18
Nodes (5): Group, MotionGrouping, Options, Int, Set

### Community 215 - "TimelineLayoutKey"
Cohesion: 0.29
Nodes (12): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+4 more)

### Community 216 - ".upright"
Cohesion: 0.24
Nodes (5): ObjectTransformDrag, .corners, StaticString, String, UInt

### Community 217 - "Kind"
Cohesion: 0.12
Nodes (14): Kind, fill, image, stroke, text, KindProbe, LossySlot, LossyValue (+6 more)

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
Cohesion: 0.12
Nodes (8): GuidePath, .end, .start, TimeInterval, TimeInterval, TimedSample, .point, TimeInterval

### Community 223 - "TODO"
Cohesion: 0.25
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 224 - "ObjectTransformLogicTests"
Cohesion: 0.18
Nodes (5): LiveLayerTransform, CGAffineTransform, ObjectTransformLogicTests, CGSize, VectorStroke

### Community 225 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 226 - "CanvasPresentationModifier"
Cohesion: 0.31
Nodes (6): CanvasPresentationModifier, Bool, CanvasManager, Void, PresentedContent, ViewModifier

### Community 227 - "1. The decisions"
Cohesion: 0.15
Nodes (13): 1. The decisions, A fill is a `CGPath`, and cutting a chunk out of it is two Core Graphics calls, A moved piece carries a **translated** dab lattice; a stationary piece keeps the parent's, An erase punch is a stroke and moves like one, Identity: fresh ids, in-place splice, tags inherited, Interpolation: out of scope, and the guard already exists, Selection is by **centreline**, not by ink — and the alternative is a real feature, not a constant, Text moves whole, if the lasso contains its centre (+5 more)

### Community 229 - "Lasso Move — Specification"
Cohesion: 0.25
Nodes (8): 0. How much of this already exists, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, 6. Open risks, Lasso Move — Specification, Still needs a ruling, and stage 1 can start without any of it

### Community 230 - "Int"
Cohesion: 0.16
Nodes (10): ActiveObjectTransform, InterpolationPreviewKey, Bool, Int, Layer, Set, UIEvent, UIGestureRecognizer (+2 more)

### Community 231 - ".handleShouldReceive"
Cohesion: 0.36
Nodes (4): Bool, ObjectIdentifier, UIGestureRecognizer, UITouch

### Community 232 - "CanvasManager"
Cohesion: 0.18
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage (+2 more)

### Community 233 - "ValueFill"
Cohesion: 0.13
Nodes (13): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+5 more)

### Community 234 - "CompositorRole"
Cohesion: 0.13
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 235 - ".relayout"
Cohesion: 0.23
Nodes (6): Context, UIPinchGestureRecognizer, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 237 - "Handoff — 2026-08-22"
Cohesion: 0.20
Nodes (9): A count that does not tie, worth thirty seconds, Handoff — 2026-08-22, Start here — paste this to begin the next session, State, Still true, carried forward, The thing that would have shipped broken, and how it was caught, What landed, What the owner has to decide, once they have looked (+1 more)

### Community 238 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 239 - "LayerKind"
Cohesion: 0.25
Nodes (6): LayerKind, raster, value, vector, K, KeyedDecodingContainer

### Community 240 - "UIEvent"
Cohesion: 0.50
Nodes (3): Set, UIEvent, UITouch

### Community 241 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 242 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 243 - "SandwichPresentation"
Cohesion: 0.50
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 244 - "MenuRequest"
Cohesion: 0.50
Nodes (4): MenuRequest, block, gap, loop

### Community 245 - "Failure"
Cohesion: 0.67
Nodes (3): Error, Failure, unknownKind

### Community 246 - "BlendMode"
Cohesion: 0.67
Nodes (3): BlendMode, .shaderCode, UInt32

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **1023 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+1018 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **22 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CGFloat` connect `CGFloat` to `PaintUITestCase`, `CGPoint`, `TimelineRowView`, `CanvasManager`, `ShapeOverlayView`, `String`, `cels`, `StrokeCanvasView`, `ActionRecorder`, `BrushEngineLogicTests`, `TextFrame`, `StrokeGeometry`, `VectorEraserLogicTests`, `Codable`, `.rasterize`, `layers`, `CanvasManager`, `PointCloudIndex`, `ParityScenario`, `PerfBaselineTests`, `RasterLayerTexture`, `Binding`, `Coordinator`, `FloatingPieceOverlayView`, `AnimationTimeline`, `LayerStackCell`, `VectorCanvas`, `TextTransformLogicTests`, `FontDescriptor`, `WindowEventTap`, `SideToolbar`, `ARAPLogicTests`, `TextOverlayView`, `ObjectTransformOverlayView`, `XCUIApplication`, `.stampStroke`, `Lattice`, `ProjectStore`, `StrokeStabilizer`, `VectorEraserHybridLogicTests`, `.setBakedContent`, `CanvasManager`, `.rows`, `Coordinator`, `DrawingView`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `TextBakeCharacterizationTests`, `.reconcileLayers`, `EffectLayerLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `EraserSettingsPanel`, `CodingKeys`, `GuideOverlayView`, `DeformFactorization`, `RenderRequest`, `VectorSample`, `InterpolationGuideLogicTests`, `TextTransformOverlayView`, `.indices`, `CanvasManager`, `VectorTransformUndoLogicTests`, `Typography`, `.arched`, `InterpolateBar`, `.launchIntoEditor`, `.draw`, `TextHitTestLogicTests`, `.manager`, `SpacingChart`, `.resolvedCelIndices`, `BrushDynamics`, `LassoFillLogicTests`, `CanvasManager`, `PinchMergeGateLogicTests`, `StrokeSpatialIndex`, `StrokeGeometryLogicTests`, `CanvasTransformFreezeUITests`, `VectorEraserMode`, `LayerRowModel`, `CurveEditor`, `Int`, `JSONValue`, `.compositeSize`, `Brush`, `Handle`, `CGRect`, `SandwichCompositingUITests`, `.sample`, `ActionsMenu`, `TextSettingsPanel`, `TimelineLayoutKeyLogicTests`, `OnionSkinLogicTests`, `ObjectTransformFrame`, `DabTarget`, `BrushStamper`, `Coordinator`, `.group`, `TimelineLayoutKey`, `.upright`, `.frames`, `TimedSample`, `ObjectTransformLogicTests`, `Color`, `Int`, `CanvasManager`, `.relayout`, `.distanceSquared`, `TransformOverlaySupport.swift`?**
  _High betweenness centrality (0.278) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `.manager`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `VectorCanvasData`, `ShapeOverlayView`, `cels`, `StrokeCanvasView`, `BrushEngineLogicTests`, `TextFrame`, `StrokeGeometry`, `VectorEraserLogicTests`, `Codable`, `.rasterize`, `layers`, `CanvasManager`, `PointCloudIndex`, `ParityScenario`, `PerfBaselineTests`, `RasterLayerTexture`, `Coordinator`, `FloatingPieceOverlayView`, `AnimationTimeline`, `ProjectSaveLogicTests`, `VectorCanvas`, `SelectionOverlayView`, `TextTransformLogicTests`, `WindowEventTap`, `ARAPLogicTests`, `TextOverlayView`, `ObjectTransformOverlayView`, `.stampStroke`, `Lattice`, `AlphaMask`, `StrokeStabilizer`, `VectorEraserHybridLogicTests`, `.setBakedContent`, `CanvasManager`, `SaveDamageGateLogicTests`, `TextBakeCharacterizationTests`, `InterpolationEngineDiagnosticsLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `GuideOverlayView`, `DeformFactorization`, `VectorSample`, `InterpolationGuideLogicTests`, `TextTransformOverlayView`, `.indices`, `VectorTransformUndoLogicTests`, `Typography`, `EyedropperLogicTests`, `.arched`, `TextHitTestLogicTests`, `.manager`, `LassoFillLogicTests`, `CanvasManager`, `StrokeSpatialIndex`, `StrokeGeometryLogicTests`, `.refreshUndoRedoState`, `LayerRowModel`, `CurveEditor`, `Brush`, `TextRecipe`, `CGRect`, `.sample`, `FillGestureRestartLogicTests`, `.sampledColor`, `ObjectTransformFrame`, `CGFloat`, `DabTarget`, `BrushStamper`, `Coordinator`, `.group`, `.upright`, `.frames`, `TimedSample`, `ObjectTransformLogicTests`, `Int`, `CanvasManager`, `.distanceSquared`, `TransformOverlaySupport.swift`?**
  _High betweenness centrality (0.140) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `PaintUITestCase`, `CGPoint`, `Typography`, `.manager`, `EyedropperLogicTests`, `VectorTransformUndoLogicTests`, `VectorCanvasData`, `cels`, `TextHitTestLogicTests`, `BrushEngineLogicTests`, `CanvasNotice`, `UIKit`, `VectorEraserLogicTests`, `Codable`, `LassoFillLogicTests`, `PinchMergeGateLogicTests`, `StrokeGeometryLogicTests`, `ParityScenario`, `PerfBaselineTests`, `ShapeHoldClock`, `StrokeGestureRecognizer`, `VectorEraserMode`, `ProjectSaveLogicTests`, `VectorPreviewPlanLogicTests`, `SelectionOverlayView`, `TextTransformLogicTests`, `RenderTreeCharacterizationTests`, `.validateProject`, `FontDescriptor`, `ARAPLogicTests`, `MaskGuardLogicTests`, `TextRecipe`, `Lattice`, `AlphaMask`, `FillBoundaryLogicTests`, `.setBakedContent`, `VectorEraserHybridLogicTests`, `UndoHistory`, `GalleryOpenState`, `SaveDamageGateLogicTests`, `FillGestureRestartLogicTests`, `TimelineLayoutKeyLogicTests`, `LayerTreeCharacterizationTests`, `OnionSkinLogicTests`, `CanvasPresentationLogicTests`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `TextBakeCharacterizationTests`, `EffectLayerLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `EffectMultiPassLogicTests`, `SelectionPersistenceLogicTests`, `InterpolationRenderLogicTests`, `ObjectTransformLogicTests`, `PlaybackBoundsCharacterizationTests`, `EffectParityLogicTests`, `BlockDragCharacterizationTests`, `VectorSample`, `InterpolationGuideLogicTests`?**
  _High betweenness centrality (0.104) - this node is a cross-community bridge._
- **Are the 80 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 80 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 6 INFERRED edges - model-reasoned connections that need verification._