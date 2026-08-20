# Graph Report - PaintSoftware  (2026-08-20)

## Corpus Check
- 229 files · ~683,812 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6677 nodes · 20152 edges · 226 communities (202 shown, 24 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 2023 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `92ddd666`
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
- Outcome
- ShapeOverlayView
- Brush
- cels
- StrokeCanvasView
- ActionRecorder
- BrushEngineLogicTests
- TextFrame
- UIKit
- StrokeGeometryLogicTests
- VectorEraserLogicTests
- .setUpGestures
- .transparentFormat
- layers
- CanvasManager
- .restLattice
- StructureSnapshot
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
- ValueLayerLogicTests
- SelectionOverlayView
- EraserSettingsPanel
- XCTestCase
- ContentView
- PerfMonitor
- FontResolveLogicTests
- LayerManifest
- CanvasSizePickerView
- WindowEventTap
- SideToolbar
- Coordinator
- TextOverlayView
- ObjectTransformOverlayView
- Housekeeping pass (8 items from 2026-07-22 feature audit)
- XCUIApplication
- BrushStamper
- Lattice
- AlphaMask
- SaveSnapshot
- StrokeStabilizer
- CaseIterable
- CompositorParityLogicTests
- CanvasManager
- .rows
- CanvasHostView
- GalleryOpenState
- Layer
- PaintSoftware iPad drawing/animation app
- BrushStamper.DabRNG (seeded splitmix64)
- PerfBaselineTests.swift
- LayerTreeCharacterizationTests
- .apply
- CGFloat
- CompositorMetalEngine
- .attach
- Foundation
- Effect
- CodingKeys
- DrawingView
- SandwichLogicTests
- CGImage.cropping(to:) retains parent pixel data
- Multi-Session Protocol
- graphify usage protocol
- VectorCanvasDataLogicTests
- ProjectStore.swift
- TouchCountRecognizer
- parallel_test.sh
- .setBakedContent
- ARAPLogicTests
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
- InterpolationRecipe
- CodingKey
- Composite.metal
- PlaybackBoundsCharacterizationTests
- GuideOverlayView
- DeformFactorization
- CodingKeys
- RenderNode
- EffectParityLogicTests
- BlockDragCharacterizationTests
- RenderQuality
- MaskSource
- VectorSample
- InterpolationGuideLogicTests
- GuideRow
- agent
- Compositor.swift
- .indices
- CanvasManager
- InterpolationEngineDiagnosticsLogicTests
- Typography
- read
- .solidImage
- .arched
- TimedSample
- InterpolateBar
- .launchIntoEditor
- EffectParams
- RenderRequest
- BackupManagerLogicTests
- CelBlockView
- .manager
- CanvasNotice
- SpacingChart
- OnionSkinSource.swift
- 4. Future upgrades — the deferred list
- TransformOverlaySupport.swift
- Kind
- command
- LassoFillLogicTests
- CanvasManager
- PinchMergeGateLogicTests
- StrokeSpatialIndex
- Coordinator
- CanvasManager
- Gesture
- CanvasTransformFreezeUITests
- ShapeHoldClock
- run.sh
- TextBakeCharacterizationTests
- LayerRowModel
- CanvasPresentation
- Alignment
- CurveEditor
- OnionSkinPanel
- .row
- Recording
- .handleShouldReceive
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- ToolPanelsUITests
- TODO.md
- 1. The decisions
- EffectPipelines
- .compositeSize
- JSONValue
- CodingKeys
- ManifestSkeleton
- .image
- .makeUIView
- OnionSkinSettings
- Corner
- Add Text
- Is the brush engine ready for `.ABR` / Procreate brush import?
- MaskGuardLogicTests
- OnionSkinLogicTests
- CGRect
- simlock.sh
- SandwichCompositingUITests
- .sample
- Kind
- CodingKeys
- FillBoundaryLogicTests
- ActionsMenu
- TextSettingsPanel
- ProjectVersionsView
- UndoHistory
- Performance
- .textureBudgetBytes
- FillGestureRestartLogicTests
- TimelineLayoutKeyLogicTests
- .sampledColor
- Lasso Fill — Specification
- SwiftUI
- VectorScratchRole
- RecordingWriter
- Atomic
- CanvasPresentationLogicTests
- ThumbnailRenderer.swift
- Kind
- TextLayout
- Prompt for the next session
- .encode
- MenuInterruptionUITests
- .relayout
- CanvasManager
- TimelineLayoutKey
- LassoFillDiagnostic
- Kind
- Every dismissible presentation, and whether a stroke under it breaks
- .init
- .frames
- CutOutcome
- Kind
- Handoff — 2026-08-20
- CompositeProbe
- presentation-census.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 663 edges
2. `CGFloat` - 519 edges
3. `CanvasManager` - 157 edges
4. `Effect` - 149 edges
5. `VectorCanvas` - 126 edges
6. `layers` - 121 edges
7. `VectorSample` - 117 edges
8. `Coordinator` - 113 edges
9. `ShapeGeometry` - 109 edges
10. `CanvasManager` - 100 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Stroke-delivery regression: default flip, gate, and recognizer state involved together** — bugs_stroke_delivery_regression, bugs_requirespencilonly, bugs_pencilonlydrawing, bugs_reconcilelayers, bugs_housekeeping_2026_07_26 [EXTRACTED 1.00]

## Communities (226 total, 24 thin omitted)

### Community 0 - "PaintUITestCase"
Cohesion: 0.08
Nodes (14): FillLiveAdjustUITests, HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests (+6 more)

### Community 1 - "CGPoint"
Cohesion: 0.04
Nodes (35): CGPoint, .length, Corner, bottomLeft, bottomRight, topLeft, topRight, Edge (+27 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (20): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+12 more)

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
Cohesion: 0.04
Nodes (60): Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame (+52 more)

### Community 8 - "Outcome"
Cohesion: 0.20
Nodes (8): LossySlot, LossyValue, Outcome, decoded, malformed, unknownKind, Decoder, Value

### Community 9 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 10 - "Brush"
Cohesion: 0.06
Nodes (34): Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+26 more)

### Community 11 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (24): CAShapeLayer, StrokeInput, TimeInterval, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+16 more)

### Community 13 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 14 - "BrushEngineLogicTests"
Cohesion: 0.15
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 15 - "TextFrame"
Cohesion: 0.08
Nodes (25): .descriptor, FontDescriptor, Mode, affine, projective, Bool, CGRect, CGSize (+17 more)

### Community 16 - "UIKit"
Cohesion: 0.07
Nodes (5): CoreGraphics, Darwin, simd, UIKit, XCTest

### Community 17 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (14): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, samples (+6 more)

### Community 18 - "VectorEraserLogicTests"
Cohesion: 0.09
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 19 - ".setUpGestures"
Cohesion: 0.13
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.12
Nodes (20): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+12 more)

### Community 21 - "layers"
Cohesion: 0.09
Nodes (15): .activeLayerIsVector, .activeCelIsInBetween, Int, CanvasManager, Bool, Int, Void, Cel (+7 more)

### Community 22 - "CanvasManager"
Cohesion: 0.09
Nodes (21): CanvasManager, .fillHalfCoverageAlpha, FillGestureContext, FillKey, FillRenderResult, Bool, Cel, CGPath (+13 more)

### Community 23 - ".restLattice"
Cohesion: 0.13
Nodes (8): ARAPInterpolation, Interpolator, Options, Bool, Int, StaticString, String, UInt

### Community 24 - "StructureSnapshot"
Cohesion: 0.11
Nodes (13): CanvasManager, StructureSnapshot, Int, Layer, CanvasManager, .activeViewName, Int, String (+5 more)

### Community 25 - ".drawLine"
Cohesion: 0.12
Nodes (10): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, EraserAndPersistenceUITests (+2 more)

### Community 26 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (46): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+38 more)

### Community 27 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 28 - "PerfBaselineTests"
Cohesion: 0.16
Nodes (6): PerfBaselineTests, CGSize, Double, String, UInt64, VectorStroke

### Community 29 - "Fill.metal"
Cohesion: 0.17
Nodes (40): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+32 more)

### Community 30 - "StrokeGestureRecognizer"
Cohesion: 0.09
Nodes (19): StrokeGiveUp, handedOver, .inkSurvives, interrupted, StrokeInterruption, Bool, StrokeGestureRecognizer, Any (+11 more)

### Community 31 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (14): CGContextDabTarget, RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGContext (+6 more)

### Community 32 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (73): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+65 more)

### Community 33 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, brush, color, eraser, fill, layers, move (+10 more)

### Community 34 - "Binding"
Cohesion: 0.10
Nodes (27): Accessory, KeyPath, .isTimelineMenuPresented, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager (+19 more)

### Community 35 - "Coordinator"
Cohesion: 0.06
Nodes (31): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, Coordinator, .canvasContentScale, .isLassoFilling (+23 more)

### Community 36 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.04
Nodes (50): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+42 more)

### Community 38 - "View"
Cohesion: 0.14
Nodes (29): View, .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex (+21 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.12
Nodes (12): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase, Set, StaticString (+4 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): effectMenuSlug(), LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String (+4 more)

### Community 41 - "VectorCanvas"
Cohesion: 0.05
Nodes (66): AnyObject, Error, DabTarget, CodableColor, .uiColor, image, kind, DabLattice (+58 more)

### Community 42 - "ValueLayerLogicTests"
Cohesion: 0.11
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.07
Nodes (22): resolvedLastTouchType(), UITouch, SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder (+14 more)

### Community 44 - "EraserSettingsPanel"
Cohesion: 0.15
Nodes (13): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+5 more)

### Community 45 - "XCTestCase"
Cohesion: 0.13
Nodes (9): StaticString, String, UInt, XCTestCase, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String (+1 more)

### Community 46 - "ContentView"
Cohesion: 0.09
Nodes (17): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+9 more)

### Community 47 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 48 - "FontResolveLogicTests"
Cohesion: 0.09
Nodes (23): CoreText, FontFace, .id, FontFamilyGroup, .id, FontLibrary, FontProvider, FontResolution (+15 more)

### Community 49 - "LayerManifest"
Cohesion: 0.12
Nodes (24): Decoder, ValueFill, CompositorRole, node, Decoder, Encoder, K, KeyedDecodingContainer (+16 more)

### Community 50 - "CanvasSizePickerView"
Cohesion: 0.15
Nodes (13): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+5 more)

### Community 51 - "WindowEventTap"
Cohesion: 0.17
Nodes (11): AnyClass, Entry, InstallReport, ObjectIdentifier, Set, String, UIEvent, UIGestureRecognizer (+3 more)

### Community 52 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .eyedropperButton, .isEraserMode, .isFillMode, .sliderHeight, Bool, CanvasManager (+5 more)

### Community 53 - "Coordinator"
Cohesion: 0.17
Nodes (14): .body, Coordinator, DropTarget, between, onto, LayerStackListView, CanvasManager, Coordinator (+6 more)

### Community 54 - "TextOverlayView"
Cohesion: 0.10
Nodes (16): RenderKey, Bool, CGRect, CGSize, NSCoder, Set, String, UIEvent (+8 more)

### Community 55 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

### Community 56 - "Housekeeping pass (8 items from 2026-07-22 feature audit)"
Cohesion: 0.14
Nodes (15): AppVersion.current stale hardcoded git hash, Color picker discarded hue on gray swatch, deleteCel no-op on layer's last remaining cel, Fill tool off-center fill vertically mirrored (regression), flipCanvas skipped object (photo) layers, FloodFillEngine.fill, ProjectStore.save composites every visible layer for thumbnail, testFillToolBridgesOpenContourGapWhenGapClosingEnabled (XCTSkip) (+7 more)

### Community 57 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 58 - "BrushStamper"
Cohesion: 0.12
Nodes (9): BrushStamper, DiscardedDabTarget, Sample, Bool, ClosedRange, Bool, CanvasManager, Int (+1 more)

### Community 59 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 60 - "AlphaMask"
Cohesion: 0.07
Nodes (18): Hashable, CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8 (+10 more)

### Community 61 - "SaveSnapshot"
Cohesion: 0.14
Nodes (19): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+11 more)

### Community 62 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 63 - "CaseIterable"
Cohesion: 0.09
Nodes (22): CaseIterable, Colouring, .id, originalColors, .title, Neighbourhood, drawings, frames (+14 more)

### Community 64 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (12): CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int, StaticString, String (+4 more)

### Community 65 - "CanvasManager"
Cohesion: 0.04
Nodes (50): Identifiable, CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationReferenceCanvases (+42 more)

### Community 66 - ".rows"
Cohesion: 0.11
Nodes (26): GradientStop, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+18 more)

### Community 67 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 68 - "GalleryOpenState"
Cohesion: 0.14
Nodes (13): GalleryOpenState, .isBusy, Bool, UUID, GalleryTileView, .body, Bool, Void (+5 more)

### Community 69 - "Layer"
Cohesion: 0.10
Nodes (17): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+9 more)

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

### Community 75 - "CGFloat"
Cohesion: 0.05
Nodes (31): CGGradient, bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Key (+23 more)

### Community 76 - "CompositorMetalEngine"
Cohesion: 0.10
Nodes (29): Admission, admitted, noHeadroom, overBudget, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+21 more)

### Community 77 - ".attach"
Cohesion: 0.23
Nodes (5): Context, UIPinchGestureRecognizer, .gradientStops, previous, UITableView

### Community 78 - "Foundation"
Cohesion: 0.11
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 79 - "Effect"
Cohesion: 0.06
Nodes (52): Codable, Equatable, Kind, folder, layer, Bloom, Blur, BrightnessContrast (+44 more)

### Community 80 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+20 more)

### Community 81 - "DrawingView"
Cohesion: 0.06
Nodes (29): ActionRecorderIndicator, .body, CanvasNoticeBanner, .body, .icon, String, Void, DrawingView (+21 more)

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

### Community 87 - "ProjectStore.swift"
Cohesion: 0.38
Nodes (6): os, CodableColor, .color, Color, .codable, CodableColor

### Community 88 - "TouchCountRecognizer"
Cohesion: 0.20
Nodes (10): Any, Int, Selector, Set, UIEvent, UITouch, Void, TouchCountRecognizer (+2 more)

### Community 89 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 90 - ".setBakedContent"
Cohesion: 0.12
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 91 - "ARAPLogicTests"
Cohesion: 0.07
Nodes (24): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+16 more)

### Community 92 - "EffectMultiPassLogicTests"
Cohesion: 0.11
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

### Community 110 - "InterpolationRecipe"
Cohesion: 0.06
Nodes (33): .interpolationKeyframes, GroupRegistration, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval (+25 more)

### Community 111 - "CodingKey"
Cohesion: 0.04
Nodes (48): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+40 more)

### Community 112 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 113 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 114 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

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

### Community 120 - "RenderQuality"
Cohesion: 0.09
Nodes (27): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderResolution, full, half (+19 more)

### Community 121 - "MaskSource"
Cohesion: 0.16
Nodes (12): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, CanvasManager (+4 more)

### Community 122 - "VectorSample"
Cohesion: 0.18
Nodes (6): VectorSample, .point, CountingDabTarget, StrokeSampleGateLogicTests, UInt64, Tremor

### Community 124 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 125 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 126 - "Compositor.swift"
Cohesion: 0.17
Nodes (20): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+12 more)

### Community 128 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 129 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 130 - "Typography"
Cohesion: 0.19
Nodes (8): UIFont, ClosedRange, Typography, .clamped, Int, String, UIFont, TextLayoutLogicTests

### Community 131 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 132 - ".solidImage"
Cohesion: 0.09
Nodes (11): Eyedropper, Sample, CGSize, Double, Int, UInt8, CGSize, UIColor (+3 more)

### Community 133 - ".arched"
Cohesion: 0.25
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 134 - "TimedSample"
Cohesion: 0.12
Nodes (8): GuidePath, .end, .start, TimeInterval, TimeInterval, TimedSample, .point, TimeInterval

### Community 135 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 136 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, UndoAndLayerHistoryUITests

### Community 137 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 138 - "RenderRequest"
Cohesion: 0.23
Nodes (12): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, Attempt, image (+4 more)

### Community 139 - "BackupManagerLogicTests"
Cohesion: 0.19
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 140 - "CelBlockView"
Cohesion: 0.23
Nodes (5): CelBlockView, Bool, ClosedRange, String, UIImage

### Community 141 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 142 - "CanvasNotice"
Cohesion: 0.09
Nodes (10): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, String, TimeInterval (+2 more)

### Community 143 - "SpacingChart"
Cohesion: 0.17
Nodes (5): SpacingChart, .curve, .draggable, Range, stops

### Community 144 - "OnionSkinSource.swift"
Cohesion: 0.13
Nodes (9): tinted, OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager, StaticString, UIImage, UInt (+1 more)

### Community 145 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 146 - "TransformOverlaySupport.swift"
Cohesion: 0.18
Nodes (10): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+2 more)

### Community 147 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 148 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 149 - "LassoFillLogicTests"
Cohesion: 0.06
Nodes (32): MTLBuffer, MTLCommandBuffer, LassoFillMask, Float, Int, SIMD4, UInt8, FillParams (+24 more)

### Community 150 - "CanvasManager"
Cohesion: 0.06
Nodes (36): CanvasManager, Bool, CGSize, UIImage, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind (+28 more)

### Community 151 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 152 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 153 - "Coordinator"
Cohesion: 0.18
Nodes (10): BlockDrag, Coordinator, MenuRequest, block, gap, loop, CanvasManager, Coordinator (+2 more)

### Community 154 - "CanvasManager"
Cohesion: 0.17
Nodes (10): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage (+2 more)

### Community 155 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 156 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 157 - "ShapeHoldClock"
Cohesion: 0.19
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 159 - "TextBakeCharacterizationTests"
Cohesion: 0.06
Nodes (30): FillMode, .displayName, flood, .id, lasso, Bool, String, Tool (+22 more)

### Community 160 - "LayerRowModel"
Cohesion: 0.12
Nodes (17): DispatchWorkItem, IndexPath, LayerRowModel, .folderID, .isFolder, .maskSource, LayerStackListView.Coordinator, BlendMode (+9 more)

### Community 161 - "CanvasPresentation"
Cohesion: 0.10
Nodes (20): CanvasPresentation, canvasBackgroundColour, effectGradientStopColour, effectOutlineColour, galleryProjectVersions, galleryRecentlyDeleted, .id, interpolateOptions (+12 more)

### Community 162 - "Alignment"
Cohesion: 0.25
Nodes (7): Alignment, center, .displayName, .id, justified, left, right

### Community 163 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 164 - "OnionSkinPanel"
Cohesion: 0.12
Nodes (20): CodableColor, .swiftUIColor, OnionSkinPanel, .body, .caution, .colouringPicker, .countRow, .neighbourhoodPicker (+12 more)

### Community 165 - ".row"
Cohesion: 0.33
Nodes (6): MaskTuningSection, .body, ClosedRange, Float, String, Void

### Community 166 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 167 - ".handleShouldReceive"
Cohesion: 0.36
Nodes (4): Bool, ObjectIdentifier, UIGestureRecognizer, UITouch

### Community 168 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 170 - "TODO.md"
Cohesion: 0.22
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 171 - "1. The decisions"
Cohesion: 0.15
Nodes (13): 1. The decisions, `ActionsMenu` gains the ability to enter a mode, Fonts go through one seam and nothing else, Handles live outside the warped layer, Live warp is Core Animation; the bake is a compute kernel, Persistence: one new case, no sidecar, no version number, Point text grows; a box you sized wraps, The bake trigger is one line (+5 more)

### Community 172 - "EffectPipelines"
Cohesion: 0.17
Nodes (13): Metal, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue (+5 more)

### Community 173 - ".compositeSize"
Cohesion: 0.18
Nodes (5): .resolutionNoteText, OnionSkinBudget, CGSize, Int, Int

### Community 174 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 175 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alignment, autoSize, color, corners, faceName, familyName, font (+17 more)

### Community 176 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 177 - ".image"
Cohesion: 0.15
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 178 - ".makeUIView"
Cohesion: 0.12
Nodes (9): AppliedTool, CanvasView, CanvasManager, Color, Context, Coordinator, Double, LayerTransform (+1 more)

### Community 179 - "OnionSkinSettings"
Cohesion: 0.16
Nodes (11): .opacitySliders, OnionSkinOpacityRamp, OnionSkinSettings, Side, .id, next, .step, CodableColor (+3 more)

### Community 180 - "Corner"
Cohesion: 0.29
Nodes (6): Int, Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 181 - "Add Text"
Cohesion: 0.25
Nodes (5): 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, Add Text

### Community 182 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.14
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 183 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 184 - "OnionSkinLogicTests"
Cohesion: 0.19
Nodes (5): CelSpan, .end, OnionSkinPlanner, Bool, OnionSkinLogicTests

### Community 185 - "CGRect"
Cohesion: 0.28
Nodes (8): CGRect, NSCoder, UILongPressGestureRecognizer, UIView, TimelineDropIndicatorView, TimelineFolderRowView, TimelinePlayheadView, TimelineRulerView

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
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 191 - "FillBoundaryLogicTests"
Cohesion: 0.19
Nodes (6): FillBoundaryLogicTests, Bool, ClosedRange, Float, Int, UInt8

### Community 192 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 193 - "TextSettingsPanel"
Cohesion: 0.16
Nodes (14): CanvasManager, ClosedRange, Double, String, WritableKeyPath, TextSettingsPanel, .alignmentBinding, .alignmentPicker (+6 more)

### Community 194 - "ProjectVersionsView"
Cohesion: 0.38
Nodes (5): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void

### Community 195 - "UndoHistory"
Cohesion: 0.23
Nodes (7): Action, Bool, Int, Void, UndoHistory, .canRedo, .canUndo

### Community 196 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 197 - ".textureBudgetBytes"
Cohesion: 0.47
Nodes (4): CompositorBudget, .textureBudgetBytes, Int, UInt64

### Community 198 - "FillGestureRestartLogicTests"
Cohesion: 0.25
Nodes (7): FillGestureRestartLogicTests, CanvasManager, CGPath, CGRect, Int, TimeInterval, UInt8

### Community 199 - "TimelineLayoutKeyLogicTests"
Cohesion: 0.27
Nodes (3): CanvasManager, Int, TimelineLayoutKeyLogicTests

### Community 200 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 201 - "Lasso Fill — Specification"
Cohesion: 0.20
Nodes (10): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill, 8. Open risks (+2 more)

### Community 202 - "SwiftUI"
Cohesion: 0.11
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 203 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 205 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 206 - "CanvasPresentationLogicTests"
Cohesion: 0.17
Nodes (4): CanvasPresentationLogicTests, Bool, String, URL

### Community 208 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, line, oval, rectangle

### Community 209 - "TextLayout"
Cohesion: 0.22
Nodes (10): NSAttributedString, NSRange, NSTextAlignment, Line, Metrics, Bool, CGContext, CGSize (+2 more)

### Community 212 - "MenuInterruptionUITests"
Cohesion: 0.33
Nodes (5): MenuInterruptionUITests, Int, String, XCUIApplication, XCUIElement

### Community 213 - ".relayout"
Cohesion: 0.23
Nodes (6): Context, UIPinchGestureRecognizer, TimelineScrollView, TimelineTrackView.Coordinator, UIScrollView, UIScrollViewDelegate

### Community 214 - "CanvasManager"
Cohesion: 0.23
Nodes (6): CanvasManager, .activeEditColor, .isTextInAdjustableState, Bool, Color, String

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
Cohesion: 0.20
Nodes (10): BROKEN — a stroke under it dismisses it mid-sequence, nothing clears it first, Counts, Coverage limits of this sweep, Every dismissible presentation, and whether a stroke under it breaks, SAFE, and worth knowing why, SETTLED SAFE (was UNKNOWN) — presents through a path this repo had never verified, The contract, and why it did not hold, The four distinct versions of the problem (+2 more)

### Community 220 - ".frames"
Cohesion: 0.20
Nodes (3): CGRect, Range, TimelineRulerClip

### Community 221 - "CutOutcome"
Cohesion: 0.28
Nodes (7): CutOutcome, cut, missed, unchanged, IntersectionDriver, Set, UUID

### Community 222 - "Kind"
Cohesion: 0.22
Nodes (8): Kind, hiddenLayer, historyRedo, historyUndo, noDrawingSurface, noLayers, nothingEnclosed, nothingToPick

### Community 223 - "Handoff — 2026-08-20"
Cohesion: 0.29
Nodes (6): Handoff — 2026-08-20, Three things this pass learned the hard way, What is worth doing next, What needs the owner's iPad, What shipped, What the owner owes a ruling on

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **939 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+934 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **24 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CGFloat` connect `CGFloat` to `PaintUITestCase`, `CGPoint`, `TimelineRowView`, `CanvasManager`, `ShapeOverlayView`, `Brush`, `cels`, `StrokeCanvasView`, `ActionRecorder`, `BrushEngineLogicTests`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `.transparentFormat`, `layers`, `CanvasManager`, `.restLattice`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `Binding`, `Coordinator`, `AnimationTimeline`, `ProjectSaveLogicTests`, `LayerStackCell`, `VectorCanvas`, `EraserSettingsPanel`, `FontResolveLogicTests`, `WindowEventTap`, `SideToolbar`, `Coordinator`, `TextOverlayView`, `ObjectTransformOverlayView`, `XCUIApplication`, `BrushStamper`, `Lattice`, `StrokeStabilizer`, `CaseIterable`, `CompositorParityLogicTests`, `CanvasManager`, `.rows`, `.apply`, `DrawingView`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `.setBakedContent`, `ARAPLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `InterpolationRecipe`, `GuideOverlayView`, `DeformFactorization`, `RenderQuality`, `VectorSample`, `InterpolationGuideLogicTests`, `.indices`, `CanvasManager`, `InterpolationEngineDiagnosticsLogicTests`, `Typography`, `.arched`, `TimedSample`, `InterpolateBar`, `.launchIntoEditor`, `RenderRequest`, `CelBlockView`, `.manager`, `SpacingChart`, `OnionSkinSource.swift`, `TransformOverlaySupport.swift`, `LassoFillLogicTests`, `CanvasManager`, `PinchMergeGateLogicTests`, `StrokeSpatialIndex`, `Coordinator`, `CanvasManager`, `CanvasTransformFreezeUITests`, `TextBakeCharacterizationTests`, `LayerRowModel`, `Alignment`, `CurveEditor`, `.compositeSize`, `JSONValue`, `.image`, `.makeUIView`, `CGRect`, `SandwichCompositingUITests`, `.sample`, `Kind`, `CodingKeys`, `ActionsMenu`, `TextSettingsPanel`, `TimelineLayoutKeyLogicTests`, `TextLayout`, `.relayout`, `TimelineLayoutKey`, `.frames`?**
  _High betweenness centrality (0.291) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `InterpolationEngineDiagnosticsLogicTests`, `Typography`, `.manager`, `.solidImage`, `ColorPickerPanel`, `TimedSample`, `CanvasManager`, `TimelineRowView`, `ShapeOverlayView`, `Brush`, `.arched`, `StrokeCanvasView`, `CelBlockView`, `BrushEngineLogicTests`, `TextFrame`, `.manager`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `.setUpGestures`, `.transparentFormat`, `layers`, `CanvasManager`, `.restLattice`, `StrokeSpatialIndex`, `CanvasManager`, `CanvasManager`, `Coordinator`, `LassoFillLogicTests`, `PerfBaselineTests`, `VectorEraserHybridLogicTests`, `RasterLayerTexture`, `LayerRowModel`, `TextBakeCharacterizationTests`, `Coordinator`, `CurveEditor`, `AnimationTimeline`, `FloatingPieceOverlayView`, `ProjectSaveLogicTests`, `VectorCanvas`, `SelectionOverlayView`, `.makeUIView`, `WindowEventTap`, `Corner`, `TextOverlayView`, `ObjectTransformOverlayView`, `cels`, `CGRect`, `BrushStamper`, `Lattice`, `.sample`, `AlphaMask`, `StrokeStabilizer`, `CanvasManager`, `FillGestureRestartLogicTests`, `.sampledColor`, `CGFloat`, `TextLayout`, `CanvasManager`, `ARAPLogicTests`, `.frames`, `.evaluate`, `InterpolationRenderLogicTests`, `TransformOverlaySupport.swift`, `InterpolationRecipe`, `GuideOverlayView`, `DeformFactorization`, `VectorSample`, `InterpolationGuideLogicTests`, `.indices`?**
  _High betweenness centrality (0.157) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `PaintUITestCase`, `InterpolationEngineDiagnosticsLogicTests`, `CGPoint`, `.manager`, `.solidImage`, `Typography`, `BackupManagerLogicTests`, `cels`, `BrushEngineLogicTests`, `CanvasNotice`, `UIKit`, `StrokeGeometryLogicTests`, `TextFrame`, `VectorEraserLogicTests`, `LassoFillLogicTests`, `PinchMergeGateLogicTests`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `ShapeHoldClock`, `StrokeGestureRecognizer`, `TextBakeCharacterizationTests`, `ProjectSaveLogicTests`, `ValueLayerLogicTests`, `SelectionOverlayView`, `FontResolveLogicTests`, `MaskGuardLogicTests`, `OnionSkinLogicTests`, `Lattice`, `AlphaMask`, `FillBoundaryLogicTests`, `CompositorParityLogicTests`, `GalleryOpenState`, `FillGestureRestartLogicTests`, `TimelineLayoutKeyLogicTests`, `LayerTreeCharacterizationTests`, `CanvasPresentationLogicTests`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `.setBakedContent`, `ARAPLogicTests`, `EffectMultiPassLogicTests`, `InterpolationRenderLogicTests`, `InterpolationRecipe`, `PlaybackBoundsCharacterizationTests`, `EffectParityLogicTests`, `BlockDragCharacterizationTests`, `VectorSample`, `InterpolationGuideLogicTests`?**
  _High betweenness centrality (0.106) - this node is a cross-community bridge._
- **Are the 77 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 77 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `CanvasManager` (e.g. with `TextFrame` and `TextRecipe`) actually correct?**
  _`CanvasManager` has 5 INFERRED edges - model-reasoned connections that need verification._