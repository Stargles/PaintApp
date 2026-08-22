# Graph Report - PaintSoftware  (2026-08-22)

## Corpus Check
- 245 files · ~793,095 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 7372 nodes · 22456 edges · 242 communities (220 shown, 22 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2274 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `fdd2badc`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PaintUITestCase
- ShapeGeometry
- ProjectBackupManager
- .manager
- TimelineRowView
- PaletteColor
- bash
- CanvasManager
- VectorCanvasData
- ShapeOverlayView
- String
- cels
- StrokeCanvasView
- ActionRecorder
- BrushEngineLogicTests
- TextRecipe
- UIKit
- CGPoint
- Brush
- InterpolationRecipe
- .transparentFormat
- layers
- CanvasManager
- PointCloudIndex
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
- View
- ProjectSaveLogicTests
- LayerStackCell
- VectorCanvas
- XCTestCase
- SelectionOverlayView
- TextFrame
- RenderTreeCharacterizationTests
- ContentView
- PerfMonitor
- FontFace
- ProjectManifest
- CanvasSizePickerView
- WindowEventTap
- SideToolbar
- ARAPLogicTests
- TextOverlayView
- ObjectTransformOverlayView
- Housekeeping pass (8 items from 2026-07-22 feature audit)
- XCUIApplication
- BrushStamper
- Lattice
- AlphaMask
- ProjectStore
- StrokeStabilizer
- SizePreviewRequest
- .solidImage
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
- LayerRowModel
- Foundation
- Codable
- GradientStopsEditor
- DrawingView
- SandwichLogicTests
- CGImage.cropping(to:) retains parent pixel data
- Multi-Session Protocol
- graphify usage protocol
- VectorCanvasDataLogicTests
- TextBakeCharacterizationTests
- LassoFillLogicTests
- parallel_test.sh
- .setBakedContent
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
- BrushSettingsPanel
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
- FontResolveLogicTests
- CanvasManager
- VectorTransformUndoLogicTests
- Typography
- read
- EyedropperLogicTests
- TextLayout
- GuideRow
- InterpolateBar
- .launchIntoEditor
- EffectParams
- .draw
- TextHitTestLogicTests
- .backfillMissingThumbnails
- .makeUIView
- CanvasNotice
- ColorPickerPanel
- OnionSkinLogicTests
- 4. Future upgrades — the deferred list
- BrushBlendMode
- Kind
- command
- CGRect
- CanvasManager
- PinchMergeGateLogicTests
- StrokeSpatialIndex
- CanvasPresentation
- .refreshUndoRedoState
- Gesture
- CanvasTransformFreezeUITests
- ShapeHoldClock
- run.sh
- VectorEraserMode
- LayerStackListView.Coordinator
- MetalFillSession
- StructureSnapshot
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
- .compositeSize
- JSONValue
- CodingKeys
- .rasterize
- .image
- .performDrag
- OnionSkinSettings
- .lassoFill
- Add Text
- Is the brush engine ready for `.ABR` / Procreate brush import?
- MaskGuardLogicTests
- TextRecipeCodableLogicTests
- CGRect
- simlock.sh
- ResolvedMask
- .sample
- SelectPanel
- Kind
- FillBoundaryLogicTests
- ActionsMenu
- TextSettingsPanel
- Kind
- UndoHistory
- Performance
- .textureBudgetBytes
- FillGestureRestartLogicTests
- TimelineLayoutKeyLogicTests
- .sampledColor
- Lasso Fill — Specification
- OnionSkinSource.swift
- .rasterize
- RecordingWriter
- Atomic
- CanvasPresentationLogicTests
- CGFloat
- CGContextDabTarget
- CompositeProbe
- RenderQuality
- CodingKey
- MenuInterruptionUITests
- Coordinator
- .group
- TimelineLayoutKey
- CodingKeys
- ProjectStore.swift
- Every dismissible presentation, and whether a stroke under it breaks
- SelectionPersistenceLogicTests
- .frames
- CutOutcome
- CodingKeys
- TODO
- InterpolatePanel
- CopiedCel
- CanvasPresentationModifier
- 1. The decisions
- presentation-census.sh
- Lasso Move — Specification
- .setUpGestures
- CanvasManager
- ValueFill
- CompositorRole
- .relayout
- Handoff — 2026-08-22
- TransformOverlaySupport.swift
- LayerKind
- ManifestSkeleton
- MenuRequest
- Effect
- .encode

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 812 edges
2. `CGFloat` - 598 edges
3. `CanvasManager` - 173 edges
4. `VectorCanvas` - 159 edges
5. `Effect` - 149 edges
6. `layers` - 126 edges
7. `VectorSample` - 125 edges
8. `Coordinator` - 121 edges
9. `ShapeGeometry` - 120 edges
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

## Hyperedges (group relationships)
- **Stroke-delivery regression: default flip, gate, and recognizer state involved together** — bugs_stroke_delivery_regression, bugs_requirespencilonly, bugs_pencilonlydrawing, bugs_reconcilelayers, bugs_housekeeping_2026_07_26 [EXTRACTED 1.00]

## Communities (242 total, 22 thin omitted)

### Community 0 - "PaintUITestCase"
Cohesion: 0.12
Nodes (9): HistoryNoticeUITests, PaintUITestCase, Int, String, XCUIApplication, SelectionAndMoveUITests, GalleryRecoveryUITests, ShapeRecoveryUITests (+1 more)

### Community 1 - "ShapeGeometry"
Cohesion: 0.04
Nodes (32): coverage(), Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom (+24 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.08
Nodes (27): DateFormatter, Notification.Name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+19 more)

### Community 3 - ".manager"
Cohesion: 0.07
Nodes (10): CanvasFixture, CanvasManager, CGSize, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool (+2 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.13
Nodes (17): Kind, cel, gap, Segment, Cel, Int, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 5 - "PaletteColor"
Cohesion: 0.15
Nodes (17): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+9 more)

### Community 6 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 7 - "CanvasManager"
Cohesion: 0.04
Nodes (62): Never, Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+54 more)

### Community 8 - "VectorCanvasData"
Cohesion: 0.09
Nodes (25): ElementData, fill, image, stroke, text, KindProbe, LossySlot, LossyValue (+17 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (39): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+31 more)

### Community 10 - "String"
Cohesion: 0.04
Nodes (56): CaseIterable, Error, Kind, line, oval, rectangle, CodableColor, .uiColor (+48 more)

### Community 11 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (26): CAShapeLayer, StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush (+18 more)

### Community 13 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 14 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 15 - "TextRecipe"
Cohesion: 0.13
Nodes (16): Alignment, center, .displayName, .id, justified, left, right, FontDescriptor (+8 more)

### Community 16 - "UIKit"
Cohesion: 0.07
Nodes (6): CoreGraphics, Darwin, TextMeasure, simd, UIKit, XCTest

### Community 17 - "CGPoint"
Cohesion: 0.06
Nodes (15): CGPoint, .length, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect (+7 more)

### Community 18 - "Brush"
Cohesion: 0.06
Nodes (17): Brush, Sweep, Bool, CGRect, ClosedRange, Double, VectorEraser, .fixedBrush (+9 more)

### Community 19 - "InterpolationRecipe"
Cohesion: 0.04
Nodes (46): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+38 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.11
Nodes (21): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+13 more)

### Community 21 - "layers"
Cohesion: 0.09
Nodes (17): .activeLayerIsVector, .activeCelIsInBetween, .guideRefusal, .interpolationTarget, Int, CanvasManager, Bool, Int (+9 more)

### Community 22 - "CanvasManager"
Cohesion: 0.09
Nodes (23): CanvasManager, .fillEdgeOverlap, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel (+15 more)

### Community 23 - "PointCloudIndex"
Cohesion: 0.14
Nodes (14): ARAPRegistration, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty, Result (+6 more)

### Community 24 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 25 - ".drawLine"
Cohesion: 0.12
Nodes (10): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, Bool, CGVector, Double, TimeInterval, UInt8 (+2 more)

### Community 26 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (39): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+31 more)

### Community 27 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 28 - "PerfBaselineTests"
Cohesion: 0.11
Nodes (9): PerfBaselineTests, Bool, CanvasManager, CGSize, Double, Int, String, UInt64 (+1 more)

### Community 29 - "Fill.metal"
Cohesion: 0.17
Nodes (41): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+33 more)

### Community 30 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 31 - "RasterLayerTexture"
Cohesion: 0.11
Nodes (16): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+8 more)

### Community 32 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 33 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 34 - "Binding"
Cohesion: 0.14
Nodes (20): Accessory, KeyPath, .body, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding (+12 more)

### Community 35 - "Coordinator"
Cohesion: 0.06
Nodes (32): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, ActiveObjectTransform, Coordinator, .canvasContentScale (+24 more)

### Community 36 - "FloatingPieceOverlayView"
Cohesion: 0.10
Nodes (19): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+11 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.05
Nodes (44): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+36 more)

### Community 38 - "View"
Cohesion: 0.14
Nodes (29): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+21 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.10
Nodes (14): MainActor, Void, ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase (+6 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): effectMenuSlug(), LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String (+4 more)

### Community 41 - "VectorCanvas"
Cohesion: 0.07
Nodes (40): Identifiable, VectorTextElement, image, DabLattice, .range, Kind, fill, image (+32 more)

### Community 42 - "XCTestCase"
Cohesion: 0.11
Nodes (11): CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor (+3 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 44 - "TextFrame"
Cohesion: 0.05
Nodes (44): Int, Basis, Corner, bottomLeft, bottomRight, topLeft, topRight, Handle (+36 more)

### Community 45 - "RenderTreeCharacterizationTests"
Cohesion: 0.14
Nodes (7): StaticString, String, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 46 - "ContentView"
Cohesion: 0.09
Nodes (18): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+10 more)

### Community 47 - "PerfMonitor"
Cohesion: 0.16
Nodes (13): CADisplayLink, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor, .isRunning (+5 more)

### Community 48 - "FontFace"
Cohesion: 0.12
Nodes (16): FontFace, .descriptor, .id, FontFamilyGroup, .id, FontResolution, .substituted, FontSubstitution (+8 more)

### Community 49 - "ProjectManifest"
Cohesion: 0.25
Nodes (14): CelManifest, FolderManifest, LayerManifest, ProjectManifest, BlendMode, Bool, CodableColor, Date (+6 more)

### Community 50 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 51 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 52 - "SideToolbar"
Cohesion: 0.16
Nodes (14): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+6 more)

### Community 53 - "ARAPLogicTests"
Cohesion: 0.15
Nodes (6): ARAPInterpolation, ARAPLogicTests, Int, StaticString, String, UInt

### Community 54 - "TextOverlayView"
Cohesion: 0.10
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
Cohesion: 0.17
Nodes (12): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Bool, CGBlendMode, ClosedRange, Double (+4 more)

### Community 59 - "Lattice"
Cohesion: 0.07
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 60 - "AlphaMask"
Cohesion: 0.08
Nodes (11): AlphaMask, .isActive, Bool, Int, MaskParityLogicTests, .side, Bool, CanvasManager (+3 more)

### Community 61 - "ProjectStore"
Cohesion: 0.09
Nodes (38): CFAbsoluteTime, CelContent, DecodedCel, DecodedCels, LayerContent, LoadProfile, .millisecondsPerCel, .thumbnailShare (+30 more)

### Community 62 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 63 - "SizePreviewRequest"
Cohesion: 0.05
Nodes (38): Anchor, ObservableObject, .sizePreview, .uploadableLeafCount, CanvasDisplayScale, SizePreviewGeometry, .isClipped, .stampDiameter (+30 more)

### Community 64 - ".solidImage"
Cohesion: 0.08
Nodes (13): UIColor, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int, StaticString (+5 more)

### Community 65 - "CanvasManager"
Cohesion: 0.04
Nodes (48): CanvasManager, .guideChips, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .linkableGuideStrokes (+40 more)

### Community 66 - ".rows"
Cohesion: 0.16
Nodes (19): CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections(), EffectSettingsMenu (+11 more)

### Community 67 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 68 - "GalleryOpenState"
Cohesion: 0.10
Nodes (18): GalleryOpenState, .isBusy, Bool, UUID, ProjectVersionsView, .body, RecentlyDeletedView, .body (+10 more)

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
Nodes (7): Layer, UInt, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 74 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 75 - "ProjectLoadDamage"
Cohesion: 0.13
Nodes (18): LayerDamage, .isEmpty, .itemPhrase, .total, ProjectLoadDamage, .isDamaged, .itemCount, .summary (+10 more)

### Community 76 - "CompositorMetalEngine"
Cohesion: 0.09
Nodes (33): Admission, admitted, noHeadroom, overBudget, Attempt, image, unavailable, underPressure (+25 more)

### Community 77 - "LayerRowModel"
Cohesion: 0.11
Nodes (22): IndexPath, Coordinator, LayerRowModel, .folderID, .isFolder, .maskSource, LayerStackListView, BlendMode (+14 more)

### Community 78 - "Foundation"
Cohesion: 0.12
Nodes (4): Foundation, AppVersion, .versionString, String

### Community 79 - "Codable"
Cohesion: 0.05
Nodes (45): Codable, CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma (+37 more)

### Community 80 - "GradientStopsEditor"
Cohesion: 0.15
Nodes (14): stops, value, levels, .lookupTable, GradientStop, CodableColor, UInt8, GradientStopsEditor (+6 more)

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
Cohesion: 0.16
Nodes (11): Any, Data, Double, Int, String, T, UIColor, UIImage (+3 more)

### Community 87 - "TextBakeCharacterizationTests"
Cohesion: 0.17
Nodes (6): CanvasManager, CGRect, Int, String, UInt8, TextBakeCharacterizationTests

### Community 88 - "LassoFillLogicTests"
Cohesion: 0.14
Nodes (7): LassoFillLogicTests, Bool, CGPath, ClosedRange, Int, UInt64, UInt8

### Community 89 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 90 - ".setBakedContent"
Cohesion: 0.10
Nodes (11): UIImage, EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor (+3 more)

### Community 91 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.30
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 92 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 93 - ".evaluate"
Cohesion: 0.13
Nodes (19): CGPathElementType, Direction, backward, forward, fromRest, Evaluation, GroupWarp, InterpolationEvaluator (+11 more)

### Community 94 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (12): StrokeComposite, erase, paint, fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor (+4 more)

### Community 95 - "Layer Compositing"
Cohesion: 0.07
Nodes (29): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+21 more)

### Community 109 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 110 - "BrushSettingsPanel"
Cohesion: 0.10
Nodes (20): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+12 more)

### Community 111 - "CodingKeys"
Cohesion: 0.10
Nodes (21): CodingKeys, brush, color, composite, elements, fill, fills, id (+13 more)

### Community 112 - "Composite.metal"
Cohesion: 0.21
Nodes (31): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+23 more)

### Community 113 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 114 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 115 - "DeformFactorization"
Cohesion: 0.09
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
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 120 - "RenderRequest"
Cohesion: 0.11
Nodes (24): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, RenderResolution, full (+16 more)

### Community 121 - "MaskSource"
Cohesion: 0.11
Nodes (17): Kind, folder, layer, MaskSource, folder, .id, layer, Decoder (+9 more)

### Community 122 - "VectorSample"
Cohesion: 0.15
Nodes (8): VectorSample, .point, CountingDabTarget, StrokeSampleGateLogicTests, CGBlendMode, UIColor, UInt64, Tremor

### Community 123 - "InterpolationGuideLogicTests"
Cohesion: 0.05
Nodes (24): GuideHandles, GuidePath, .end, .start, GuideSet, .isEmpty, SpacingChart, .curve (+16 more)

### Community 124 - "TextTransformOverlayView"
Cohesion: 0.11
Nodes (16): Bool, CALayer, CGRect, NSCoder, Set, UIEvent, UITouch, Void (+8 more)

### Community 125 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 126 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 127 - "FontResolveLogicTests"
Cohesion: 0.16
Nodes (8): CoreText, FontLibrary, FontProvider, FontResolveLogicTests, StubFontProvider, Bool, String, UIFont

### Community 128 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 129 - "VectorTransformUndoLogicTests"
Cohesion: 0.24
Nodes (8): CanvasManager, CGAffineTransform, Int, LayerTransform, StaticString, String, UInt, VectorTransformUndoLogicTests

### Community 130 - "Typography"
Cohesion: 0.18
Nodes (8): UIFont, ClosedRange, Typography, .clamped, Int, String, UIFont, TextLayoutLogicTests

### Community 131 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 132 - "EyedropperLogicTests"
Cohesion: 0.09
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 133 - "TextLayout"
Cohesion: 0.14
Nodes (13): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGRect (+5 more)

### Community 134 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 135 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 136 - ".launchIntoEditor"
Cohesion: 0.12
Nodes (12): BlendModesAndCompositorUITests, LayerPanelUITests, SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String (+4 more)

### Community 137 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 138 - ".draw"
Cohesion: 0.32
Nodes (7): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 139 - "TextHitTestLogicTests"
Cohesion: 0.18
Nodes (6): Bool, CGAffineTransform, CGSize, String, VectorStroke, TextHitTestLogicTests

### Community 140 - ".backfillMissingThumbnails"
Cohesion: 0.19
Nodes (9): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+1 more)

### Community 141 - ".makeUIView"
Cohesion: 0.11
Nodes (10): AppliedTool, CanvasView, CanvasManager, Color, Context, Coordinator, Double, UIColor (+2 more)

### Community 142 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 143 - "ColorPickerPanel"
Cohesion: 0.14
Nodes (17): ColorPickerPanel, .body, .colorTab, .currentColor, .hexRow, .hueSlider, .palettesTab, .renameAlertBinding (+9 more)

### Community 144 - "OnionSkinLogicTests"
Cohesion: 0.21
Nodes (5): CelSpan, .end, OnionSkinPlanner, Bool, OnionSkinLogicTests

### Community 145 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 146 - "BrushBlendMode"
Cohesion: 0.07
Nodes (26): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+18 more)

### Community 147 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 148 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 149 - "CGRect"
Cohesion: 0.16
Nodes (5): .loopAroundEverything, CanvasManager, CGRect, TimeInterval, UIImage

### Community 150 - "CanvasManager"
Cohesion: 0.09
Nodes (25): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+17 more)

### Community 151 - "PinchMergeGateLogicTests"
Cohesion: 0.14
Nodes (7): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests, Bool, Int

### Community 152 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 153 - "CanvasPresentation"
Cohesion: 0.09
Nodes (19): Hashable, CelLocation, CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted (+11 more)

### Community 154 - ".refreshUndoRedoState"
Cohesion: 0.11
Nodes (8): UUID, VectorStroke, CanvasManager, .isTextInAdjustableState, Bool, Color, Int, UUID

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
Cohesion: 0.07
Nodes (24): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+16 more)

### Community 160 - "LayerStackListView.Coordinator"
Cohesion: 0.11
Nodes (14): DispatchWorkItem, DropTarget, between, onto, LayerStackListView.Coordinator, Bool, CGRect, ObjectIdentifier (+6 more)

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
Cohesion: 0.10
Nodes (22): .onionSkinButton, CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow (+14 more)

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
Cohesion: 0.12
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 173 - ".compositeSize"
Cohesion: 0.20
Nodes (6): OnionSkinBudget, OnionSkinOpacityRamp, CGSize, Double, Int, Int

### Community 174 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 175 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 176 - ".rasterize"
Cohesion: 0.18
Nodes (6): LassoFillMask, Float, Int, SIMD4, UInt8, mask

### Community 177 - ".image"
Cohesion: 0.14
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 178 - ".performDrag"
Cohesion: 0.13
Nodes (6): InterpolationWorkflowUITests, Bool, TimeInterval, XCUIElement, TimelineGestureUITests, UndoAndLayerHistoryUITests

### Community 179 - "OnionSkinSettings"
Cohesion: 0.14
Nodes (13): .gradientStops, .opacitySliders, OnionSkinSettings, Side, .id, next, previous, .step (+5 more)

### Community 181 - "Add Text"
Cohesion: 0.25
Nodes (5): 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, Add Text

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

### Community 187 - "ResolvedMask"
Cohesion: 0.27
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 188 - ".sample"
Cohesion: 0.18
Nodes (13): NSObject, ObjectiveC.runtime, FoundElement, ResolvedTarget, Bool, CGRect, CGSize, Double (+5 more)

### Community 189 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

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

### Community 197 - ".textureBudgetBytes"
Cohesion: 0.47
Nodes (4): CompositorBudget, .textureBudgetBytes, Int, UInt64

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
Cohesion: 0.15
Nodes (12): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 2a. Where a fill lands in the stack: on top of everything already on the layer, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill (+4 more)

### Community 202 - "OnionSkinSource.swift"
Cohesion: 0.14
Nodes (7): tinted, OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager, UIImage, VectorStroke

### Community 205 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 206 - "CanvasPresentationLogicTests"
Cohesion: 0.15
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 207 - "CGFloat"
Cohesion: 0.05
Nodes (19): bendRatio(), cellSize(), cShape(), polyline(), Int, Sample, Void, Constraint (+11 more)

### Community 208 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 210 - "RenderQuality"
Cohesion: 0.31
Nodes (6): ContentProvider, CGSize, UIImage, RenderQuality, full, preview

### Community 211 - "CodingKey"
Cohesion: 0.09
Nodes (22): CodingKey, CodingKeys, endPoint, kind, rotation, spanStart, spanSweep, startPoint (+14 more)

### Community 212 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 213 - "Coordinator"
Cohesion: 0.17
Nodes (9): BlockDrag, CelBlockView, Coordinator, Bool, CanvasManager, Coordinator, UIImage, Void (+1 more)

### Community 214 - ".group"
Cohesion: 0.17
Nodes (6): Group, MotionGrouping, Options, Bool, Int, Set

### Community 215 - "TimelineLayoutKey"
Cohesion: 0.29
Nodes (12): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+4 more)

### Community 216 - "CodingKeys"
Cohesion: 0.25
Nodes (8): CodingKeys, groups, guideIDs, localEdits, mode, references, spacing, t

### Community 217 - "ProjectStore.swift"
Cohesion: 0.38
Nodes (6): os, CodableColor, .color, Color, .codable, CodableColor

### Community 218 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.18
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 220 - ".frames"
Cohesion: 0.20
Nodes (3): CGRect, Range, TimelineRulerClip

### Community 221 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 222 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, activeCells, cellSize, cols, originX, originY, rows

### Community 223 - "TODO"
Cohesion: 0.25
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 224 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 225 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 226 - "CanvasPresentationModifier"
Cohesion: 0.31
Nodes (7): CanvasPresentationModifier, Bool, CanvasManager, Void, View, PresentedContent, ViewModifier

### Community 227 - "1. The decisions"
Cohesion: 0.15
Nodes (13): 1. The decisions, A fill is a `CGPath`, and cutting a chunk out of it is two Core Graphics calls, A moved piece carries a **translated** dab lattice; a stationary piece keeps the parent's, An erase punch is a stroke and moves like one, Identity: fresh ids, in-place splice, tags inherited, Interpolation: out of scope, and the guard already exists, Selection is by **centreline**, not by ink — and the alternative is a real feature, not a constant, Text moves whole, if the lasso contains its centre (+5 more)

### Community 229 - "Lasso Move — Specification"
Cohesion: 0.25
Nodes (8): 0. How much of this already exists, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, 6. Open risks, Lasso Move — Specification, Still needs a ruling, and stage 1 can start without any of it

### Community 230 - ".setUpGestures"
Cohesion: 0.13
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 232 - "CanvasManager"
Cohesion: 0.21
Nodes (8): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage

### Community 233 - "ValueFill"
Cohesion: 0.13
Nodes (13): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+5 more)

### Community 234 - "CompositorRole"
Cohesion: 0.14
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 235 - ".relayout"
Cohesion: 0.23
Nodes (6): Context, UIPinchGestureRecognizer, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 237 - "Handoff — 2026-08-22"
Cohesion: 0.22
Nodes (8): Handoff — 2026-08-22, Start here — paste this to begin the next session, State, Still true, carried forward, Three findings worth more than the fixes, Traps this pass hit, for the next one, What landed, What the owner has to decide, once they have looked

### Community 238 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 239 - "LayerKind"
Cohesion: 0.25
Nodes (6): LayerKind, raster, value, vector, K, KeyedDecodingContainer

### Community 241 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 244 - "MenuRequest"
Cohesion: 0.50
Nodes (4): MenuRequest, block, gap, loop

### Community 245 - "Effect"
Cohesion: 0.11
Nodes (27): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, Curves, Effect, .displayName (+19 more)

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **1037 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+1032 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **22 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CGFloat` connect `CGFloat` to `ShapeGeometry`, `TimelineRowView`, `CanvasManager`, `ShapeOverlayView`, `String`, `cels`, `StrokeCanvasView`, `ActionRecorder`, `BrushEngineLogicTests`, `TextRecipe`, `CGPoint`, `Brush`, `InterpolationRecipe`, `.transparentFormat`, `layers`, `CanvasManager`, `PointCloudIndex`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `Binding`, `Coordinator`, `FloatingPieceOverlayView`, `AnimationTimeline`, `LayerStackCell`, `VectorCanvas`, `TextFrame`, `FontFace`, `WindowEventTap`, `SideToolbar`, `ARAPLogicTests`, `TextOverlayView`, `ObjectTransformOverlayView`, `XCUIApplication`, `BrushStamper`, `Lattice`, `AlphaMask`, `ProjectStore`, `StrokeStabilizer`, `SizePreviewRequest`, `.solidImage`, `CanvasManager`, `.apply`, `LayerRowModel`, `GradientStopsEditor`, `DrawingView`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `TextBakeCharacterizationTests`, `LassoFillLogicTests`, `.setBakedContent`, `InterpolationEngineDiagnosticsLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `BrushSettingsPanel`, `CodingKeys`, `GuideOverlayView`, `DeformFactorization`, `RenderRequest`, `VectorSample`, `InterpolationGuideLogicTests`, `TextTransformOverlayView`, `FontResolveLogicTests`, `CanvasManager`, `VectorTransformUndoLogicTests`, `Typography`, `TextLayout`, `InterpolateBar`, `.launchIntoEditor`, `.draw`, `TextHitTestLogicTests`, `.backfillMissingThumbnails`, `.makeUIView`, `BrushBlendMode`, `CanvasManager`, `PinchMergeGateLogicTests`, `StrokeSpatialIndex`, `CanvasTransformFreezeUITests`, `CurveEditor`, `.compositeSize`, `JSONValue`, `.rasterize`, `.image`, `.performDrag`, `CGRect`, `.sample`, `ActionsMenu`, `TextSettingsPanel`, `TimelineLayoutKeyLogicTests`, `OnionSkinSource.swift`, `CGContextDabTarget`, `RenderQuality`, `Coordinator`, `.group`, `TimelineLayoutKey`, `.frames`, `CanvasManager`, `.relayout`, `TransformOverlaySupport.swift`?**
  _High betweenness centrality (0.268) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `ShapeGeometry`, `Typography`, `VectorTransformUndoLogicTests`, `EyedropperLogicTests`, `TextLayout`, `TimelineRowView`, `CanvasManager`, `VectorCanvasData`, `ShapeOverlayView`, `String`, `cels`, `StrokeCanvasView`, `.backfillMissingThumbnails`, `BrushEngineLogicTests`, `.makeUIView`, `ColorPickerPanel`, `TextHitTestLogicTests`, `Brush`, `InterpolationRecipe`, `.transparentFormat`, `layers`, `CanvasManager`, `PointCloudIndex`, `StrokeSpatialIndex`, `CanvasManager`, `.refreshUndoRedoState`, `CGRect`, `PerfBaselineTests`, `VectorEraserHybridLogicTests`, `RasterLayerTexture`, `LayerStackListView.Coordinator`, `Coordinator`, `CurveEditor`, `AnimationTimeline`, `FloatingPieceOverlayView`, `ProjectSaveLogicTests`, `VectorCanvas`, `SelectionOverlayView`, `TextFrame`, `.rasterize`, `WindowEventTap`, `ARAPLogicTests`, `TextOverlayView`, `ObjectTransformOverlayView`, `TextRecipeCodableLogicTests`, `CGRect`, `BrushStamper`, `Lattice`, `.sample`, `AlphaMask`, `StrokeStabilizer`, `SizePreviewRequest`, `CanvasManager`, `SaveDamageGateLogicTests`, `FillGestureRestartLogicTests`, `.sampledColor`, `.rasterize`, `CGFloat`, `CGContextDabTarget`, `RenderQuality`, `Coordinator`, `.group`, `TextBakeCharacterizationTests`, `InterpolationEngineDiagnosticsLogicTests`, `.frames`, `.evaluate`, `InterpolationRenderLogicTests`, `.setUpGestures`, `CanvasManager`, `TransformOverlaySupport.swift`, `GuideOverlayView`, `DeformFactorization`, `VectorSample`, `InterpolationGuideLogicTests`, `TextTransformOverlayView`?**
  _High betweenness centrality (0.158) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `PaintUITestCase`, `ShapeGeometry`, `ProjectBackupManager`, `.manager`, `EyedropperLogicTests`, `Typography`, `VectorTransformUndoLogicTests`, `VectorCanvasData`, `cels`, `TextHitTestLogicTests`, `BrushEngineLogicTests`, `CanvasNotice`, `UIKit`, `OnionSkinLogicTests`, `CGPoint`, `InterpolationRecipe`, `Brush`, `PinchMergeGateLogicTests`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `ShapeHoldClock`, `StrokeGestureRecognizer`, `VectorEraserMode`, `ProjectSaveLogicTests`, `VectorPreviewPlanLogicTests`, `SelectionOverlayView`, `TextFrame`, `RenderTreeCharacterizationTests`, `ARAPLogicTests`, `MaskGuardLogicTests`, `ObjectTransformOverlayView`, `TextRecipeCodableLogicTests`, `Lattice`, `AlphaMask`, `FillBoundaryLogicTests`, `.solidImage`, `UndoHistory`, `GalleryOpenState`, `SaveDamageGateLogicTests`, `FillGestureRestartLogicTests`, `TimelineLayoutKeyLogicTests`, `LayerTreeCharacterizationTests`, `CanvasPresentationLogicTests`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `TextBakeCharacterizationTests`, `LassoFillLogicTests`, `.setBakedContent`, `InterpolationEngineDiagnosticsLogicTests`, `EffectMultiPassLogicTests`, `SelectionPersistenceLogicTests`, `InterpolationRenderLogicTests`, `PlaybackBoundsCharacterizationTests`, `EffectParityLogicTests`, `BlockDragCharacterizationTests`, `VectorSample`, `InterpolationGuideLogicTests`, `FontResolveLogicTests`?**
  _High betweenness centrality (0.107) - this node is a cross-community bridge._
- **Are the 80 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 80 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 8 INFERRED edges - model-reasoned connections that need verification._