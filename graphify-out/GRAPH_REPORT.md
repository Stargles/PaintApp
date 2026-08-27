# Graph Report - PaintSoftware  (2026-08-27)

## Corpus Check
- 257 files · ~892,994 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 7897 nodes · 24386 edges · 246 communities (226 shown, 20 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2404 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ef645069`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PaintUITestCase
- ShapeGeometry
- ProjectBackupManager
- .manager
- TimelineRowView
- ColorPickerPanel
- bash
- CanvasManager
- Homography
- ShapeOverlayView
- String
- cels
- StrokeCanvasView
- ActionRecorder
- BrushEngineLogicTests
- TextTransformLogicTests
- UIKit
- StrokeGeometryLogicTests
- VectorEraserLogicTests
- LassoMoveLogicTests
- .transparentFormat
- .withStructureUndo
- CanvasManager
- PointCloudIndex
- LayerFolder
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
- .rgbaBytes
- SelectionOverlayView
- EffectPipelines
- XCTestCase
- ContentView
- PerfMonitor
- Handle
- ProjectManifest
- CanvasSizePickerView
- WindowEventTap
- SideToolbar
- ARAPLogicTests
- TextOverlayView
- ObjectTransformOverlayView
- Housekeeping pass (8 items from 2026-07-22 feature audit)
- XCUIApplication
- RenderRequest
- CGPoint
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
- Coordinator
- Foundation
- Codable
- Hashable
- DrawingView
- SandwichLogicTests
- CGImage.cropping(to:) retains parent pixel data
- Multi-Session Protocol
- graphify usage protocol
- VectorCanvasDataLogicTests
- TextBakeCharacterizationTests
- LassoFillLogicTests
- parallel_test.sh
- EffectLayerLogicTests
- OnionSkinSource.swift
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
- FontDescriptor
- .upright
- Composite.metal
- PlaybackBoundsCharacterizationTests
- GuideOverlayView
- ObjectTransformLogicTests
- CodingKeys
- RenderNode
- Effect
- BlockDragCharacterizationTests
- ParityScenario
- MaskSource
- VectorSample
- InterpolationGuideLogicTests
- TextTransformOverlayView
- agent
- Compositor.swift
- FontResolveLogicTests
- CanvasManager
- InterpolationRecipe
- Typography
- read
- EyedropperLogicTests
- InterpolationModelLogicTests
- GuideRow
- InterpolateBar
- .launchIntoEditor
- EffectParams
- Admission
- TextHitTestLogicTests
- CanvasManager
- XCUIApplication
- CanvasNotice
- Atomic
- OnionSkinLogicTests
- 4. Future upgrades — the deferred list
- Brush
- Kind
- TextRecipe
- .init
- CanvasManager
- PinchMergeGateLogicTests
- StrokeSpatialIndex
- CanvasPresentationModifier
- .refreshUndoRedoState
- Gesture
- CanvasTransformFreezeUITests
- ShapeHoldClock
- run.sh
- VectorEraserMode
- LayerStackListView.Coordinator
- SandwichCompositingUITests
- StructureSnapshot
- CurveEditor
- OnionSkinPanel
- .row
- Recording
- CGFloat
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- VectorTransformUndoLogicTests
- VectorPreviewPlanLogicTests
- 1. The decisions
- .setUpGestures
- .compositeSize
- JSONValue
- CodingKeys
- BrushStamper
- .image
- MetalFillSession
- OnionSkinSettings
- Handle
- Add Text
- Is the brush engine ready for `.ABR` / Procreate brush import?
- MaskGuardLogicTests
- TextFrame
- CGRect
- simlock.sh
- CanvasTouchOwnerLogicTests
- .sample
- SelectPanel
- Kind
- FillBoundaryLogicTests
- ActionsMenu
- TextSettingsPanel
- LayerRowModel
- UndoHistory
- Performance
- SelectionPersistenceLogicTests
- CGRect
- TimelineLayoutKeyLogicTests
- CanvasTouchInputs
- Lasso Fill — Specification
- SpacingChart
- .rasterize
- RecordingWriter
- samples
- CanvasPresentationLogicTests
- DeformFactorization
- CGContextDabTarget
- .previewed
- CanvasTouchOwner
- CodingKeys
- MenuInterruptionUITests
- Coordinator
- SwiftUI
- TimelineLayoutKey
- VectorCanvasData
- InterpolationEngineDiagnosticsLogicTests
- Every dismissible presentation, and whether a stroke under it breaks
- LayerStackListView
- .lassoFill
- CutOutcome
- LayerStackRow
- TODO
- .textureBudgetBytes
- ObjectTransformFrame
- CanvasManager
- 1. The decisions
- presentation-census.sh
- Lasso Move — Specification
- ToolLogicTests
- MetalWarpEngine
- CanvasActiveLayer
- WarpParams
- ManifestSkeleton
- .relayout
- .sampledColor
- Handoff — 2026-08-27 (session 69)
- 1. What will actually hurt, ranked
- CanvasTouchChrome
- Kind
- Int
- SandwichPresentation
- Kind
- MenuRequest
- Equatable

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 931 edges
2. `CGFloat` - 660 edges
3. `VectorCanvas` - 212 edges
4. `CanvasManager` - 176 edges
5. `Effect` - 149 edges
6. `VectorSample` - 147 edges
7. `Coordinator` - 130 edges
8. `ShapeGeometry` - 121 edges
9. `CanvasManager` - 100 edges
10. `Lattice` - 98 edges

## Surprising Connections (you probably didn't know these)
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `.sourceScale` --calls--> `CGFloat`  [EXTRACTED]
  PaintSoftwareUITests/WarpAgreementCharacterizationTests.swift → PaintSoftware/Engine/Deform/Lattice.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `.quads` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/WarpAgreementCharacterizationTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Stroke-delivery regression: default flip, gate, and recognizer state involved together** — bugs_stroke_delivery_regression, bugs_requirespencilonly, bugs_pencilonlydrawing, bugs_reconcilelayers, bugs_housekeeping_2026_07_26 [EXTRACTED 1.00]

## Communities (246 total, 20 thin omitted)

### Community 0 - "PaintUITestCase"
Cohesion: 0.08
Nodes (14): FillLiveAdjustUITests, HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests (+6 more)

### Community 1 - "ShapeGeometry"
Cohesion: 0.04
Nodes (32): coverage(), Corner, bottomLeft, bottomRight, topLeft, topRight, Edge, bottom (+24 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.07
Nodes (29): DateFormatter, Notification.Name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+21 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 4 - "TimelineRowView"
Cohesion: 0.13
Nodes (17): Kind, cel, gap, Segment, Cel, Int, UIGestureRecognizer, UIPanGestureRecognizer (+9 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (36): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+28 more)

### Community 6 - "bash"
Cohesion: 0.14
Nodes (27): worker-feature, worker-integration, worker-ui, gh *, git *, xcodebuild *, permission, bash (+19 more)

### Community 7 - "CanvasManager"
Cohesion: 0.04
Nodes (52): Never, Void, CanvasManager, .activeContainerID, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes (+44 more)

### Community 8 - "Homography"
Cohesion: 0.05
Nodes (41): CATransform3D, Homography, .catransform3D, .determinant, .inverse, Bool, CGAffineTransform, CGRect (+33 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.05
Nodes (45): CornerHandle, EdgeHandle, Bool, EndpointHandle, end, start, HandleInfo, HandleKind (+37 more)

### Community 10 - "String"
Cohesion: 0.04
Nodes (59): CaseIterable, Error, Identifiable, Kind, line, oval, rectangle, DecodeReport (+51 more)

### Community 11 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (28): CAShapeLayer, StrokeInput, TimeInterval, NSCoder, StrokeCanvasView, .brush, .hasVectorFloat, .isNoScratchRole (+20 more)

### Community 13 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 14 - "BrushEngineLogicTests"
Cohesion: 0.12
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 15 - "TextTransformLogicTests"
Cohesion: 0.08
Nodes (11): CGSize, TextFrameDrag, Bool, CanvasManager, CGRect, CGSize, Int, StaticString (+3 more)

### Community 16 - "UIKit"
Cohesion: 0.06
Nodes (7): CoreGraphics, CoreText, Darwin, Metal, simd, UIKit, XCTest

### Community 17 - "StrokeGeometryLogicTests"
Cohesion: 0.05
Nodes (17): MembershipRun, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange (+9 more)

### Community 18 - "VectorEraserLogicTests"
Cohesion: 0.09
Nodes (7): VectorEraser, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 19 - "LassoMoveLogicTests"
Cohesion: 0.17
Nodes (10): .elements, LassoMoveLogicTests, Bool, CanvasManager, CGImage, CGPath, CGRect, CodableColor (+2 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.08
Nodes (28): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+20 more)

### Community 21 - ".withStructureUndo"
Cohesion: 0.11
Nodes (16): .interpolationTarget, LayerTransform, CanvasManager, Bool, Int, Void, Cel, .endFrame (+8 more)

### Community 22 - "CanvasManager"
Cohesion: 0.10
Nodes (22): CanvasManager, .fillEdgeOverlap, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel (+14 more)

### Community 23 - "PointCloudIndex"
Cohesion: 0.10
Nodes (18): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+10 more)

### Community 24 - "LayerFolder"
Cohesion: 0.08
Nodes (22): BlendMode, Double, UUID, CanvasManager, .activeViewName, Int, String, LayerFolder (+14 more)

### Community 25 - ".drawLine"
Cohesion: 0.15
Nodes (8): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, ShapeRecoveryUITests

### Community 26 - "VectorEraserHybridLogicTests"
Cohesion: 0.10
Nodes (21): ParityReport, .diagnostic, .isExact, RasterVectorParity, Bool, Int, UIImage, VectorStroke (+13 more)

### Community 27 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 28 - "PerfBaselineTests"
Cohesion: 0.10
Nodes (10): CutPreviewProbe, PerfBaselineTests, Bool, CanvasManager, CGSize, Double, Int, String (+2 more)

### Community 29 - "Fill.metal"
Cohesion: 0.18
Nodes (40): device, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams, edgeInset (+32 more)

### Community 30 - "StrokeGestureRecognizer"
Cohesion: 0.06
Nodes (29): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+21 more)

### Community 31 - "RasterLayerTexture"
Cohesion: 0.12
Nodes (14): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+6 more)

### Community 32 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (74): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+66 more)

### Community 33 - "ActivePanel"
Cohesion: 0.11
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 34 - "Binding"
Cohesion: 0.07
Nodes (39): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+31 more)

### Community 35 - "Coordinator"
Cohesion: 0.05
Nodes (40): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, ActiveObjectTransform, AppliedTool, CanvasView (+32 more)

### Community 36 - "FloatingPieceOverlayView"
Cohesion: 0.09
Nodes (22): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+14 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.06
Nodes (34): AnimationTimeline, .collapsedBar, .contentHeight, .frameLabel, .interpolateButton, .isCollapsed, .isTimelineMenuPresented, .layerNameColumn (+26 more)

### Community 38 - "View"
Cohesion: 0.13
Nodes (30): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+22 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.09
Nodes (17): MainActor, Void, ProjectSaveLogicTests, Any, Bool, CanvasManager, Cel, CGSize (+9 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.11
Nodes (9): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, UIView, Void (+1 more)

### Community 41 - "VectorCanvas"
Cohesion: 0.06
Nodes (49): CGPathFillRule, CodableColor, .uiColor, image, CutPreviewEdit, DabLattice, .range, kind (+41 more)

### Community 42 - ".rgbaBytes"
Cohesion: 0.11
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.06
Nodes (28): LassoFillDiagnostic, CGPath, Double, TimeInterval, UIImage, UUID, resolvedLastTouchType(), UITouch (+20 more)

### Community 44 - "EffectPipelines"
Cohesion: 0.14
Nodes (16): MTLLibrary, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState (+8 more)

### Community 45 - "XCTestCase"
Cohesion: 0.13
Nodes (9): StaticString, String, UInt, XCTestCase, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String (+1 more)

### Community 46 - "ContentView"
Cohesion: 0.09
Nodes (18): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+10 more)

### Community 47 - "PerfMonitor"
Cohesion: 0.11
Nodes (16): CADisplayLink, ObservableObject, .sizePreview, CanvasDisplayScale, PerfHUDOverlay, .body, .hudBody, .toggleButton (+8 more)

### Community 48 - "Handle"
Cohesion: 0.14
Nodes (10): Handle, body, bottomLeft, bottomRight, .isCorner, .isDrawn, rotation, topLeft (+2 more)

### Community 49 - "ProjectManifest"
Cohesion: 0.08
Nodes (33): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+25 more)

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
Cohesion: 0.09
Nodes (12): ARAPInterpolation, Group, MotionGrouping, Options, Int, Set, ARAPLogicTests, .rigidMotionL (+4 more)

### Community 54 - "TextOverlayView"
Cohesion: 0.08
Nodes (22): RenderKey, Bool, CGPath, CGRect, CGSize, Float, NSCoder, Set (+14 more)

### Community 55 - "ObjectTransformOverlayView"
Cohesion: 0.09
Nodes (18): ObjectTransformOverlayView, .canvasScale, .drawnChrome, .handleBorderWidth, .handleReach, .handleSize, .outlineWidth, .rotationHandleSize (+10 more)

### Community 56 - "Housekeeping pass (8 items from 2026-07-22 feature audit)"
Cohesion: 0.14
Nodes (15): AppVersion.current stale hardcoded git hash, Color picker discarded hue on gray swatch, deleteCel no-op on layer's last remaining cel, Fill tool off-center fill vertically mirrored (regression), flipCanvas skipped object (photo) layers, FloodFillEngine.fill, ProjectStore.save composites every visible layer for thumbnail, testFillToolBridgesOpenContourGapWhenGapClosingEnabled (XCTSkip) (+7 more)

### Community 57 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 58 - "RenderRequest"
Cohesion: 0.09
Nodes (31): Hasher, CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, CanvasManager (+23 more)

### Community 59 - "CGPoint"
Cohesion: 0.06
Nodes (30): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+22 more)

### Community 60 - "AlphaMask"
Cohesion: 0.07
Nodes (18): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8, AlphaMask (+10 more)

### Community 61 - "ProjectStore"
Cohesion: 0.09
Nodes (38): CFAbsoluteTime, CelContent, DecodedCel, DecodedCels, LayerContent, LoadProfile, .millisecondsPerCel, .thumbnailShare (+30 more)

### Community 62 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 63 - "SizePreviewRequest"
Cohesion: 0.06
Nodes (35): Anchor, .uploadableLeafCount, SizePreviewGeometry, .isClipped, .stampDiameter, .windowSide, SizePreviewRequest, SizePreviewSide (+27 more)

### Community 64 - ".solidImage"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 65 - "CanvasManager"
Cohesion: 0.04
Nodes (51): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+43 more)

### Community 66 - ".rows"
Cohesion: 0.12
Nodes (27): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+19 more)

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
Cohesion: 0.13
Nodes (18): LayerDamage, .isEmpty, .itemPhrase, .total, ProjectLoadDamage, .isDamaged, .itemCount, .summary (+10 more)

### Community 76 - "CompositorMetalEngine"
Cohesion: 0.10
Nodes (29): Attempt, image, unavailable, underPressure, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+21 more)

### Community 77 - "Coordinator"
Cohesion: 0.18
Nodes (11): DispatchWorkItem, Coordinator, CanvasManager, Int, Set, UILongPressGestureRecognizer, UIPinchGestureRecognizer, UUID (+3 more)

### Community 78 - "Foundation"
Cohesion: 0.09
Nodes (10): Foundation, os, CodableColor, .color, Color, .codable, CodableColor, AppVersion (+2 more)

### Community 79 - "Codable"
Cohesion: 0.05
Nodes (50): Codable, Kind, folder, layer, CodingKeys, amount, angleDegrees, brightness (+42 more)

### Community 80 - "Hashable"
Cohesion: 0.06
Nodes (29): Hashable, CelLocation, CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted (+21 more)

### Community 81 - "DrawingView"
Cohesion: 0.06
Nodes (27): ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void, DamagedSaveBanner (+19 more)

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

### Community 90 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 91 - "OnionSkinSource.swift"
Cohesion: 0.13
Nodes (9): tinted, OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager, StaticString, UIImage, UInt (+1 more)

### Community 92 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 93 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 94 - "InterpolationRenderLogicTests"
Cohesion: 0.18
Nodes (9): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int, UIImage, UUID (+1 more)

### Community 95 - "Layer Compositing"
Cohesion: 0.07
Nodes (29): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+21 more)

### Community 109 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 110 - "FontDescriptor"
Cohesion: 0.09
Nodes (23): .descriptor, Alignment, center, .displayName, .id, justified, left, right (+15 more)

### Community 111 - ".upright"
Cohesion: 0.24
Nodes (6): ObjectTransformDrag, .corners, LayerTransform, StaticString, String, UInt

### Community 112 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 113 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 114 - "GuideOverlayView"
Cohesion: 0.13
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 115 - "ObjectTransformLogicTests"
Cohesion: 0.18
Nodes (4): CGAffineTransform, ObjectTransformLogicTests, CGSize, VectorStroke

### Community 116 - "CodingKeys"
Cohesion: 0.07
Nodes (29): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+21 more)

### Community 117 - "RenderNode"
Cohesion: 0.08
Nodes (31): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+23 more)

### Community 118 - "Effect"
Cohesion: 0.09
Nodes (13): Effect, .displayName, .kind, .kindCode, .passes, .reshapesCoverage, .weights, Encoder (+5 more)

### Community 119 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 120 - "ParityScenario"
Cohesion: 0.10
Nodes (26): CustomStringConvertible, UIImage, UInt8, Backdrop, fill, image, none, Gesture (+18 more)

### Community 121 - "MaskSource"
Cohesion: 0.13
Nodes (13): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, Void (+5 more)

### Community 122 - "VectorSample"
Cohesion: 0.13
Nodes (9): VectorSample, .point, StaticString, String, UInt, CountingDabTarget, StrokeSampleGateLogicTests, UInt64 (+1 more)

### Community 123 - "InterpolationGuideLogicTests"
Cohesion: 0.07
Nodes (12): GuideHandles, GuideSet, .isEmpty, Bool, TimedSample, .point, InterpolationGuideLogicTests, CanvasManager (+4 more)

### Community 124 - "TextTransformOverlayView"
Cohesion: 0.12
Nodes (16): Bool, CALayer, CGRect, NSCoder, Set, UIEvent, UITouch, Void (+8 more)

### Community 125 - "agent"
Cohesion: 0.07
Nodes (28): agent, orchestrator, worker-bugfix, worker-research, worker-test, command, deploy, resign (+20 more)

### Community 126 - "Compositor.swift"
Cohesion: 0.13
Nodes (22): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), CompositeProbe, Compositor (+14 more)

### Community 127 - "FontResolveLogicTests"
Cohesion: 0.08
Nodes (23): FontFace, .id, FontFamilyGroup, .id, FontLibrary, FontProvider, FontResolution, .substituted (+15 more)

### Community 128 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 129 - "InterpolationRecipe"
Cohesion: 0.09
Nodes (23): Set, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+15 more)

### Community 130 - "Typography"
Cohesion: 0.15
Nodes (10): ClosedRange, Typography, CGRect, CGSize, ClosedRange, Int, String, UIFont (+2 more)

### Community 131 - "read"
Cohesion: 0.34
Nodes (25): float2, read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+17 more)

### Community 132 - "EyedropperLogicTests"
Cohesion: 0.11
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 133 - "InterpolationModelLogicTests"
Cohesion: 0.09
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 134 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 135 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 136 - ".launchIntoEditor"
Cohesion: 0.16
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, UndoAndLayerHistoryUITests

### Community 137 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 138 - "Admission"
Cohesion: 0.50
Nodes (4): Admission, admitted, noHeadroom, overBudget

### Community 139 - "TextHitTestLogicTests"
Cohesion: 0.17
Nodes (7): TextMeasure, Bool, CGAffineTransform, CGSize, String, VectorStroke, TextHitTestLogicTests

### Community 140 - "CanvasManager"
Cohesion: 0.19
Nodes (9): CanvasManager, Entry, Bool, Cel, CGSize, UIImage, UUID, ThumbnailBatch (+1 more)

### Community 141 - "XCUIApplication"
Cohesion: 0.12
Nodes (9): EraserAndPersistenceUITests, SelectionAndMoveUITests, Double, Int, StaticString, UInt, XCUIApplication, XCUIElement (+1 more)

### Community 142 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 143 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 144 - "OnionSkinLogicTests"
Cohesion: 0.19
Nodes (5): CelSpan, .end, OnionSkinPlanner, Bool, OnionSkinLogicTests

### Community 145 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 146 - "Brush"
Cohesion: 0.07
Nodes (27): Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+19 more)

### Community 147 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 148 - "TextRecipe"
Cohesion: 0.16
Nodes (16): CTFrame, CTFramesetter, NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool (+8 more)

### Community 150 - "CanvasManager"
Cohesion: 0.08
Nodes (28): CanvasManager, .canResetFloating, .isAnyPieceFloating, .mirrorUnavailableReason, FixedAngleRotation, FloatingPiece, .transformedBounds, FloatingPieceKind (+20 more)

### Community 151 - "PinchMergeGateLogicTests"
Cohesion: 0.14
Nodes (7): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests, Bool, Int

### Community 152 - "StrokeSpatialIndex"
Cohesion: 0.18
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 153 - "CanvasPresentationModifier"
Cohesion: 0.31
Nodes (7): CanvasPresentationModifier, Bool, CanvasManager, Void, View, PresentedContent, ViewModifier

### Community 154 - ".refreshUndoRedoState"
Cohesion: 0.09
Nodes (16): CanvasManager, Bool, CGAffineTransform, CGRect, CGSize, Int, LayerTransform, Set (+8 more)

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
Cohesion: 0.09
Nodes (22): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+14 more)

### Community 160 - "LayerStackListView.Coordinator"
Cohesion: 0.14
Nodes (11): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, ObjectIdentifier, TimeInterval, UIGestureRecognizer (+3 more)

### Community 161 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 162 - "StructureSnapshot"
Cohesion: 0.23
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

### Community 167 - "CGFloat"
Cohesion: 0.05
Nodes (20): bendRatio(), cellSize(), cShape(), polyline(), Int, Void, CGFloat, ClosedFit (+12 more)

### Community 168 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 169 - "VectorTransformUndoLogicTests"
Cohesion: 0.24
Nodes (8): CanvasManager, CGAffineTransform, Int, LayerTransform, StaticString, String, UInt, VectorTransformUndoLogicTests

### Community 170 - "VectorPreviewPlanLogicTests"
Cohesion: 0.13
Nodes (11): Bool, String, VectorPreviewPlan, VectorScratchRole, none, overlay, replacement, .traceName (+3 more)

### Community 171 - "1. The decisions"
Cohesion: 0.15
Nodes (13): 1. The decisions, `ActionsMenu` gains the ability to enter a mode, Fonts go through one seam and nothing else, Handles live outside the warped layer, Live warp is Core Animation; the bake is a compute kernel, Persistence: one new case, no sidecar, no version number, Point text grows; a box you sized wraps, The bake trigger is one line (+5 more)

### Community 172 - ".setUpGestures"
Cohesion: 0.11
Nodes (13): .isLassoFilling, Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITapGestureRecognizer, UITouch, UIView (+5 more)

### Community 173 - ".compositeSize"
Cohesion: 0.19
Nodes (5): .resolutionNoteText, OnionSkinBudget, CGSize, Double, Int

### Community 174 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 175 - "CodingKeys"
Cohesion: 0.08
Nodes (24): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+16 more)

### Community 176 - "BrushStamper"
Cohesion: 0.13
Nodes (15): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+7 more)

### Community 177 - ".image"
Cohesion: 0.14
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 178 - "MetalFillSession"
Cohesion: 0.19
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 179 - "OnionSkinSettings"
Cohesion: 0.19
Nodes (9): .opacitySliders, OnionSkinSettings, Side, .id, next, .step, CodableColor, Double (+1 more)

### Community 180 - "Handle"
Cohesion: 0.09
Nodes (21): Int, frame, Corner, bottomLeft, bottomRight, topLeft, topRight, Handle (+13 more)

### Community 181 - "Add Text"
Cohesion: 0.25
Nodes (5): 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, Add Text

### Community 182 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 183 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 184 - "TextFrame"
Cohesion: 0.09
Nodes (18): Basis, CGAffineTransform, CGRect, CGVector, TextFrame, .affineTransform, .basis, .boundingBox (+10 more)

### Community 185 - "CGRect"
Cohesion: 0.17
Nodes (12): CGRect, ClosedRange, NSCoder, String, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView (+4 more)

### Community 186 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

### Community 187 - "CanvasTouchOwnerLogicTests"
Cohesion: 0.17
Nodes (3): CanvasTouchOwnerLogicTests, String, Void

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
Cohesion: 0.15
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 194 - "LayerRowModel"
Cohesion: 0.14
Nodes (12): effectMenuSlug(), String, UIColor, LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode (+4 more)

### Community 195 - "UndoHistory"
Cohesion: 0.12
Nodes (15): Action, Bool, Int, UInt64, Void, UndoBudget, .maxCostBytes, UndoHistory (+7 more)

### Community 196 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 198 - "CGRect"
Cohesion: 0.16
Nodes (5): .loopAroundEverything, CanvasManager, CGRect, TimeInterval, UIImage

### Community 199 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.17
Nodes (5): CGRect, Range, CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 200 - "CanvasTouchInputs"
Cohesion: 0.09
Nodes (19): CanvasTouchInputs, .activeHostIsInteractive, .activeHostReceivesTouches, .catchAllIsEnabled, .catchAllRaisesNotice, .eyedropperPressIsEnabled, .fillPressIsEnabled, .floatingOverlayIsInteractive (+11 more)

### Community 201 - "Lasso Fill — Specification"
Cohesion: 0.15
Nodes (12): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 2a. Where a fill lands in the stack: on top of everything already on the layer, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill (+4 more)

### Community 202 - "SpacingChart"
Cohesion: 0.12
Nodes (10): GuidePath, .end, .start, SpacingChart, .curve, .draggable, CGVector, Int (+2 more)

### Community 203 - ".rasterize"
Cohesion: 0.18
Nodes (6): LassoFillMask, Float, Int, SIMD4, UInt8, mask

### Community 205 - "samples"
Cohesion: 0.19
Nodes (6): Sweep, Bool, CGRect, ClosedRange, Double, samples

### Community 206 - "CanvasPresentationLogicTests"
Cohesion: 0.17
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 207 - "DeformFactorization"
Cohesion: 0.10
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 208 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 209 - ".previewed"
Cohesion: 0.36
Nodes (5): Double, Int, UIImage, VectorStroke, VectorCutPreviewLogicTests

### Community 210 - "CanvasTouchOwner"
Cohesion: 0.11
Nodes (18): CanvasTouchOwner, activeLayerStroke, catchAllNotice, eyedropper, fillPress, floatingPiece, guideOverlay, lassoFill (+10 more)

### Community 211 - "CodingKeys"
Cohesion: 0.03
Nodes (64): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+56 more)

### Community 212 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 213 - "Coordinator"
Cohesion: 0.22
Nodes (6): BlockDrag, CelBlockView, Coordinator, Bool, CanvasManager, UIImage

### Community 214 - "SwiftUI"
Cohesion: 0.15
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 215 - "TimelineLayoutKey"
Cohesion: 0.24
Nodes (13): CelKey, DragKey, FolderKey, Bool, CanvasManager, ClosedRange, Int, ObjectIdentifier (+5 more)

### Community 216 - "VectorCanvasData"
Cohesion: 0.10
Nodes (18): VectorTextElement, ElementData, fill, image, stroke, text, Encoder, VectorCanvasData (+10 more)

### Community 217 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 218 - "Every dismissible presentation, and whether a stroke under it breaks"
Cohesion: 0.18
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 219 - "LayerStackListView"
Cohesion: 0.16
Nodes (9): IndexPath, .body, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView (+1 more)

### Community 221 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 222 - "LayerStackRow"
Cohesion: 0.12
Nodes (15): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+7 more)

### Community 223 - "TODO"
Cohesion: 0.20
Nodes (8): Done this pass, In flight, Queued, Queued, The canvas size that actually matters, The owner's seven device reports, 2026-08-26, TODO, Verified on the device

### Community 224 - ".textureBudgetBytes"
Cohesion: 0.47
Nodes (4): CompositorBudget, .textureBudgetBytes, Int, UInt64

### Community 225 - "ObjectTransformFrame"
Cohesion: 0.20
Nodes (7): Handle, LiveLayerTransform, ObjectTransformFrame, .centre, .isEmpty, CGSize, Set

### Community 226 - "CanvasManager"
Cohesion: 0.16
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage (+2 more)

### Community 227 - "1. The decisions"
Cohesion: 0.15
Nodes (13): 1. The decisions, A fill is a `CGPath`, and cutting a chunk out of it is two Core Graphics calls, A moved piece carries a **translated** dab lattice; a stationary piece keeps the parent's, An erase punch is a stroke and moves like one, Identity: fresh ids, in-place splice, tags inherited, Interpolation: out of scope, and the guard already exists, Selection is by **centreline**, not by ink — and the alternative is a real feature, not a constant, Text moves whole, if the lasso contains its centre (+5 more)

### Community 229 - "Lasso Move — Specification"
Cohesion: 0.18
Nodes (9): 0. What shipped, and where it lives, 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, 6. Open risks, Lasso Move — Specification, Still needs a ruling (+1 more)

### Community 230 - "ToolLogicTests"
Cohesion: 0.17
Nodes (3): Bool, Tool, ToolLogicTests

### Community 231 - "MetalWarpEngine"
Cohesion: 0.22
Nodes (8): MetalWarpEngine, Int, MTLCommandQueue, MTLComputePipelineState, MTLDevice, MTLTexture, MTLTextureUsage, UInt8

### Community 232 - "CanvasActiveLayer"
Cohesion: 0.20
Nodes (9): CanvasActiveLayer, .exists, .hasNoDrawingSurface, noDrawingSurface, none, raster, vector, Bool (+1 more)

### Community 233 - "WarpParams"
Cohesion: 0.20
Nodes (10): WarpParams, m0, m1, m2, m3, m4, m5, m6 (+2 more)

### Community 234 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 235 - ".relayout"
Cohesion: 0.21
Nodes (7): Context, Coordinator, UIPinchGestureRecognizer, Void, TimelineScrollView, TimelineTrackView, UIScrollView

### Community 236 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 237 - "Handoff — 2026-08-27 (session 69)"
Cohesion: 0.25
Nodes (7): Carried, deliberately not done, Handoff — 2026-08-27 (session 69), Start here — paste this to begin the next session, State, Still open, blocked on the owner's iPad, Still true, carried forward, What landed

### Community 238 - "1. What will actually hurt, ranked"
Cohesion: 0.22
Nodes (9): 1. Nothing answers "who owns this canvas touch" — and this is where the bugs are, 1. What will actually hurt, ranked, 2. What a frame looks like is memoized in eleven hand-written keys, 2. What is genuinely good — do not disturb, 3. A save that fails tells nobody, and one nil PNG fails the whole document, 3. What is not worth doing, 4. One persisted property means four hand-kept structs, and the initializer defaults hide the miss, 4. The owner's question, answered (+1 more)

### Community 239 - "CanvasTouchChrome"
Cohesion: 0.25
Nodes (8): CanvasTouchChrome, guideGrip, none, .owner, shapeHandleOrOutline, textBoxOrBand, textHandle, transformBoxOrHandle

### Community 240 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 242 - "SandwichPresentation"
Cohesion: 0.50
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 243 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 244 - "MenuRequest"
Cohesion: 0.50
Nodes (4): MenuRequest, block, gap, loop

### Community 245 - "Equatable"
Cohesion: 0.16
Nodes (23): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, .lookupTable (+15 more)

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **1128 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+1123 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **20 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CGFloat` connect `CGFloat` to `PaintUITestCase`, `ShapeGeometry`, `TimelineRowView`, `CanvasManager`, `Homography`, `ShapeOverlayView`, `String`, `cels`, `StrokeCanvasView`, `ActionRecorder`, `BrushEngineLogicTests`, `TextTransformLogicTests`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `LassoMoveLogicTests`, `.transparentFormat`, `CanvasManager`, `PointCloudIndex`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `Binding`, `Coordinator`, `FloatingPieceOverlayView`, `AnimationTimeline`, `ProjectSaveLogicTests`, `LayerStackCell`, `VectorCanvas`, `PerfMonitor`, `Handle`, `WindowEventTap`, `SideToolbar`, `ARAPLogicTests`, `TextOverlayView`, `ObjectTransformOverlayView`, `XCUIApplication`, `RenderRequest`, `CGPoint`, `AlphaMask`, `ProjectStore`, `StrokeStabilizer`, `SizePreviewRequest`, `.solidImage`, `CanvasManager`, `.rows`, `.apply`, `Coordinator`, `DrawingView`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `TextBakeCharacterizationTests`, `LassoFillLogicTests`, `EffectLayerLogicTests`, `OnionSkinSource.swift`, `.evaluate`, `InterpolationRenderLogicTests`, `FontDescriptor`, `.upright`, `GuideOverlayView`, `ObjectTransformLogicTests`, `ParityScenario`, `VectorSample`, `InterpolationGuideLogicTests`, `TextTransformOverlayView`, `FontResolveLogicTests`, `CanvasManager`, `InterpolationRecipe`, `Typography`, `InterpolationModelLogicTests`, `InterpolateBar`, `.launchIntoEditor`, `TextHitTestLogicTests`, `CanvasManager`, `Brush`, `TextRecipe`, `CanvasManager`, `PinchMergeGateLogicTests`, `StrokeSpatialIndex`, `CanvasTransformFreezeUITests`, `SandwichCompositingUITests`, `CurveEditor`, `VectorTransformUndoLogicTests`, `.compositeSize`, `JSONValue`, `BrushStamper`, `.image`, `Handle`, `TextFrame`, `CGRect`, `.sample`, `ActionsMenu`, `TextSettingsPanel`, `LayerRowModel`, `TimelineLayoutKeyLogicTests`, `SpacingChart`, `.rasterize`, `samples`, `DeformFactorization`, `CGContextDabTarget`, `.previewed`, `CodingKeys`, `Coordinator`, `TimelineLayoutKey`, `InterpolationEngineDiagnosticsLogicTests`, `LayerStackListView`, `ObjectTransformFrame`, `CanvasManager`, `.relayout`, `Kind`?**
  _High betweenness centrality (0.270) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `ShapeGeometry`, `.manager`, `TimelineRowView`, `ColorPickerPanel`, `CanvasManager`, `Homography`, `ShapeOverlayView`, `cels`, `StrokeCanvasView`, `BrushEngineLogicTests`, `TextTransformLogicTests`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `LassoMoveLogicTests`, `.transparentFormat`, `.withStructureUndo`, `CanvasManager`, `PointCloudIndex`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `Coordinator`, `FloatingPieceOverlayView`, `AnimationTimeline`, `ProjectSaveLogicTests`, `VectorCanvas`, `SelectionOverlayView`, `Handle`, `WindowEventTap`, `ARAPLogicTests`, `TextOverlayView`, `ObjectTransformOverlayView`, `AlphaMask`, `StrokeStabilizer`, `SizePreviewRequest`, `.solidImage`, `CanvasManager`, `SaveDamageGateLogicTests`, `Foundation`, `TextBakeCharacterizationTests`, `.evaluate`, `InterpolationRenderLogicTests`, `FontDescriptor`, `.upright`, `GuideOverlayView`, `ObjectTransformLogicTests`, `ParityScenario`, `VectorSample`, `InterpolationGuideLogicTests`, `TextTransformOverlayView`, `InterpolationRecipe`, `Typography`, `EyedropperLogicTests`, `InterpolationModelLogicTests`, `TextHitTestLogicTests`, `CanvasManager`, `Brush`, `TextRecipe`, `CanvasManager`, `StrokeSpatialIndex`, `.refreshUndoRedoState`, `LayerStackListView.Coordinator`, `CurveEditor`, `CGFloat`, `VectorTransformUndoLogicTests`, `.setUpGestures`, `BrushStamper`, `Handle`, `TextFrame`, `CGRect`, `.sample`, `CGRect`, `SpacingChart`, `.rasterize`, `samples`, `DeformFactorization`, `CGContextDabTarget`, `Coordinator`, `VectorCanvasData`, `InterpolationEngineDiagnosticsLogicTests`, `ObjectTransformFrame`, `CanvasManager`, `.sampledColor`?**
  _High betweenness centrality (0.184) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `PaintUITestCase`, `ShapeGeometry`, `ProjectBackupManager`, `.manager`, `EyedropperLogicTests`, `InterpolationModelLogicTests`, `Typography`, `Homography`, `cels`, `TextHitTestLogicTests`, `BrushEngineLogicTests`, `CanvasNotice`, `UIKit`, `OnionSkinLogicTests`, `StrokeGeometryLogicTests`, `LassoMoveLogicTests`, `.transparentFormat`, `TextTransformLogicTests`, `VectorEraserLogicTests`, `PinchMergeGateLogicTests`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `ShapeHoldClock`, `StrokeGestureRecognizer`, `ProjectSaveLogicTests`, `VectorTransformUndoLogicTests`, `.rgbaBytes`, `SelectionOverlayView`, `VectorPreviewPlanLogicTests`, `ARAPLogicTests`, `MaskGuardLogicTests`, `TextFrame`, `CanvasTouchOwnerLogicTests`, `CGPoint`, `AlphaMask`, `FillBoundaryLogicTests`, `.solidImage`, `UndoHistory`, `GalleryOpenState`, `SaveDamageGateLogicTests`, `SelectionPersistenceLogicTests`, `TimelineLayoutKeyLogicTests`, `LayerTreeCharacterizationTests`, `CanvasPresentationLogicTests`, `.previewed`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `TextBakeCharacterizationTests`, `LassoFillLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `EffectLayerLogicTests`, `VectorCanvasData`, `EffectMultiPassLogicTests`, `InterpolationRenderLogicTests`, `ToolLogicTests`, `PlaybackBoundsCharacterizationTests`, `ObjectTransformLogicTests`, `Effect`, `BlockDragCharacterizationTests`, `ParityScenario`, `VectorSample`, `InterpolationGuideLogicTests`, `FontResolveLogicTests`?**
  _High betweenness centrality (0.112) - this node is a cross-community bridge._
- **Are the 88 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 88 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 35 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 35 INFERRED edges - model-reasoned connections that need verification._