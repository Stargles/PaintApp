# Graph Report - PaintSoftware  (2026-08-18)

## Corpus Check
- 207 files · ~608,909 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 6058 nodes · 18315 edges · 212 communities (192 shown, 20 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 1913 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `cf062208`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PaintUITestCase
- CGPoint
- ProjectBackupManager
- .manager
- Coordinator
- ColorPickerPanel
- bash
- CanvasManager
- String
- ShapeOverlayView
- BrushBlendMode
- cels
- StrokeCanvasView
- ActionRecorder
- BrushEngineLogicTests
- TransformMode
- UIKit
- Brush
- VectorEraserLogicTests
- Coordinator
- .transparentFormat
- .withStructureUndo
- CanvasManager
- MetalFillEngine
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
- .reconcileLayers
- FloatingPieceOverlayView
- AnimationTimeline
- View
- ProjectSaveLogicTests
- LayerStackCell
- VectorCanvas
- XCTestCase
- SelectionOverlayView
- EraserSettingsPanel
- RenderTreeCharacterizationTests
- ContentView
- PerfMonitor
- ValueFill
- LayerManifest
- CanvasSizePickerView
- WindowEventTap
- SideToolbar
- Coordinator
- .rasterize
- ObjectTransformOverlayView
- Housekeeping pass (8 items from 2026-07-22 feature audit)
- XCUIApplication
- CGFloat
- Lattice
- AlphaMask
- SaveSnapshot
- StrokeStabilizer
- CaseIterable
- CompositorParityLogicTests
- layers
- .rows
- CanvasHostView
- GalleryView
- SelectPanel
- PaintSoftware iPad drawing/animation app
- BrushStamper.DabRNG (seeded splitmix64)
- PerfBaselineTests.swift
- LayerTreeCharacterizationTests
- .apply
- BrushStamper
- CompositorMetalEngine
- .attach
- .registerGroups
- Effect
- Codable
- DrawingView
- SandwichLogicTests
- CGImage.cropping(to:) retains parent pixel data
- Multi-Session Protocol
- graphify usage protocol
- VectorCanvasDataLogicTests
- SwiftUI
- CompositorRole
- parallel_test.sh
- EffectLayerLogicTests
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
- GuideRow
- agent
- Compositor.swift
- .indices
- CanvasManager
- InterpolationEngineDiagnosticsLogicTests
- MotionGroup
- read
- EyedropperLogicTests
- .arched
- TimedSample
- InterpolateBar
- .launchIntoEditor
- EffectParams
- .draw
- BackupManagerLogicTests
- ResolvedMask
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
- LayerKind
- InterpolationRecipe
- CanvasManager
- Gesture
- CanvasTransformFreezeUITests
- ShapeHoldClock
- run.sh
- VectorEraserMode
- LayerRowModel
- LayerFolder
- StructureSnapshot
- CurveEditor
- OnionSkinPanel
- .row
- Recording
- VectorScratchRole
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- ToolPanelsUITests
- TODO.md
- 1. The decisions
- EffectPipelines
- .compositeSize
- JSONValue
- .encode
- ManifestSkeleton
- .image
- .makeUIView
- OnionSkinSettings
- GuideStroke
- Add Text
- Is the brush engine ready for `.ABR` / Procreate brush import?
- MaskGuardLogicTests
- OnionSkinLogicTests
- InterpolationRefusal
- simlock.sh
- SandwichCompositingUITests
- .sample
- .handleShouldReceive
- CodingKeys
- FillBoundaryLogicTests
- ActionsMenu
- InterpolationPreviewKey
- CGContextDabTarget
- UndoHistory
- Performance
- .textureBudgetBytes
- Handoff — 2026-08-18
- .addImageToActiveVectorLayer
- .sampledColor
- Lasso Fill — Specification
- CodingKeys
- Kind
- RecordingWriter
- Atomic
- MergeLossKind
- .render
- CopiedCel
- Kind
- Prompt for the next session
- SandwichPresentation

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 615 edges
2. `CGFloat` - 479 edges
3. `Effect` - 149 edges
4. `CanvasManager` - 144 edges
5. `VectorCanvas` - 124 edges
6. `layers` - 119 edges
7. `VectorSample` - 116 edges
8. `ShapeGeometry` - 109 edges
9. `Coordinator` - 108 edges
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
- `.body` --calls--> `ContentView`  [INFERRED]
  PaintSoftware/PaintApp.swift → PaintSoftware/ContentView.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Stroke-delivery regression: default flip, gate, and recognizer state involved together** — bugs_stroke_delivery_regression, bugs_requirespencilonly, bugs_pencilonlydrawing, bugs_reconcilelayers, bugs_housekeeping_2026_07_26 [EXTRACTED 1.00]

## Communities (212 total, 20 thin omitted)

### Community 0 - "PaintUITestCase"
Cohesion: 0.09
Nodes (14): HistoryNoticeUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests, Bool (+6 more)

### Community 1 - "CGPoint"
Cohesion: 0.05
Nodes (34): CGPoint, .length, Int, Corner, bottomLeft, bottomRight, topLeft, topRight (+26 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+13 more)

### Community 3 - ".manager"
Cohesion: 0.07
Nodes (10): CanvasFixture, CanvasManager, CGSize, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool (+2 more)

### Community 4 - "Coordinator"
Cohesion: 0.06
Nodes (48): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+40 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Hashable, Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex (+29 more)

### Community 6 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 7 - "CanvasManager"
Cohesion: 0.05
Nodes (34): Void, CanvasManager, .activeContainerID, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+26 more)

### Community 8 - "String"
Cohesion: 0.06
Nodes (48): Error, Identifiable, CodableColor, .uiColor, DabLattice, .range, DecodeReport, .droppedCount (+40 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.06
Nodes (36): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+28 more)

### Community 10 - "BrushBlendMode"
Cohesion: 0.08
Nodes (23): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+15 more)

### Community 11 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (25): StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+17 more)

### Community 13 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 14 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 15 - "TransformMode"
Cohesion: 0.22
Nodes (8): TransformMode, .displayName, distort, freeform, .id, .isImplemented, uniform, warp

### Community 16 - "UIKit"
Cohesion: 0.05
Nodes (11): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, AppVersion, .versionString, String (+3 more)

### Community 17 - "Brush"
Cohesion: 0.05
Nodes (20): Brush, Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange (+12 more)

### Community 18 - "VectorEraserLogicTests"
Cohesion: 0.08
Nodes (16): CutOutcome, cut, missed, unchanged, IntersectionDriver, Sweep, Bool, CGRect (+8 more)

### Community 19 - "Coordinator"
Cohesion: 0.10
Nodes (18): Coordinator, .canvasContentScale, .isLassoFilling, .sandwichPresentation, CALayer, CanvasManager, CGSize, Date (+10 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.17
Nodes (14): IntPoint, PixelOps, .rasterizeCacheBytes, Bool, CGPath, CGRect, CGSize, Color (+6 more)

### Community 21 - ".withStructureUndo"
Cohesion: 0.14
Nodes (12): .interpolationTarget, CanvasManager, Bool, Int, Void, Cel, .endFrame, .isCertainlyBlank (+4 more)

### Community 22 - "CanvasManager"
Cohesion: 0.12
Nodes (16): CanvasManager, FillKey, Bool, Cel, CGPath, Float, Int, Layer (+8 more)

### Community 23 - "MetalFillEngine"
Cohesion: 0.18
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 24 - "ViewPreset"
Cohesion: 0.16
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 25 - ".drawLine"
Cohesion: 0.11
Nodes (11): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement (+3 more)

### Community 26 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (42): CustomStringConvertible, UIImage, UInt8, Backdrop, fill, image, none, Gesture (+34 more)

### Community 27 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 28 - "PerfBaselineTests"
Cohesion: 0.13
Nodes (9): PerfBaselineTests, Bool, CanvasManager, CGSize, Double, Int, String, UInt64 (+1 more)

### Community 29 - "Fill.metal"
Cohesion: 0.18
Nodes (33): device, float2, colourDistance(), computeWalls(), distanceToCanvasEdge(), edgeBridge(), edgeDilate(), FillParams (+25 more)

### Community 30 - "StrokeGestureRecognizer"
Cohesion: 0.10
Nodes (20): StrokeGestureRecognizer, Any, Bool, Int, Selector, Set, UIEvent, UITouch (+12 more)

### Community 31 - "RasterLayerTexture"
Cohesion: 0.21
Nodes (10): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+2 more)

### Community 32 - "HistoryActionLabel"
Cohesion: 0.03
Nodes (72): HistoryActionLabel, addEffectLayer, addFolder, addFrame, addGuide, addLayer, addMotionGroup, addNode (+64 more)

### Community 33 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, brush, color, eraser, fill, move, none (+9 more)

### Community 34 - "Binding"
Cohesion: 0.09
Nodes (29): Accessory, KeyPath, .isTimelineMenuPresented, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager (+21 more)

### Community 35 - ".reconcileLayers"
Cohesion: 0.11
Nodes (8): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, SandwichKey, TimeInterval, UIImage

### Community 36 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (13): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+5 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.05
Nodes (43): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+35 more)

### Community 38 - "View"
Cohesion: 0.14
Nodes (29): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+21 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.12
Nodes (12): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Int, ScenePhase, Set, StaticString (+4 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.10
Nodes (11): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+3 more)

### Community 41 - "VectorCanvas"
Cohesion: 0.07
Nodes (36): ContentProvider, UUID, CGSize, UIImage, image, kind, Kind, fill (+28 more)

### Community 42 - "XCTestCase"
Cohesion: 0.14
Nodes (11): CGImage, CGRect, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor (+3 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.08
Nodes (21): resolvedLastTouchType(), UITouch, SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder (+13 more)

### Community 44 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (16): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+8 more)

### Community 45 - "RenderTreeCharacterizationTests"
Cohesion: 0.14
Nodes (7): StaticString, String, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 46 - "ContentView"
Cohesion: 0.14
Nodes (11): AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager, MainActor (+3 more)

### Community 47 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 48 - "ValueFill"
Cohesion: 0.13
Nodes (13): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+5 more)

### Community 49 - "LayerManifest"
Cohesion: 0.24
Nodes (15): CelManifest, CodableColor, FolderManifest, LayerManifest, ProjectManifest, BlendMode, Bool, CodableColor (+7 more)

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
Cohesion: 0.16
Nodes (14): .body, Coordinator, DropTarget, between, onto, LayerStackListView, CanvasManager, Coordinator (+6 more)

### Community 54 - ".rasterize"
Cohesion: 0.17
Nodes (7): RasterizeCache, .bytesResident, RasterizeKey, Cel, ObjectIdentifier, UUID, CGSize

### Community 55 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

### Community 56 - "Housekeeping pass (8 items from 2026-07-22 feature audit)"
Cohesion: 0.14
Nodes (15): AppVersion.current stale hardcoded git hash, Color picker discarded hue on gray swatch, deleteCel no-op on layer's last remaining cel, Fill tool off-center fill vertically mirrored (regression), flipCanvas skipped object (photo) layers, FloodFillEngine.fill, ProjectStore.save composites every visible layer for thumbnail, testFillToolBridgesOpenContourGapWhenGapClosingEnabled (XCTSkip) (+7 more)

### Community 57 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 58 - "CGFloat"
Cohesion: 0.11
Nodes (13): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, ClosedFit (+5 more)

### Community 59 - "Lattice"
Cohesion: 0.06
Nodes (34): CodingKeys, activeCells, cellSize, cols, originX, originY, rows, vertices (+26 more)

### Community 60 - "AlphaMask"
Cohesion: 0.08
Nodes (12): AlphaMask, .isActive, Bool, Decoder, Int, MaskParityLogicTests, .side, Bool (+4 more)

### Community 61 - "SaveSnapshot"
Cohesion: 0.12
Nodes (22): BrushLibrary, .customBrushesDirectory, URL, CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary (+14 more)

### Community 62 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 63 - "CaseIterable"
Cohesion: 0.06
Nodes (35): CaseIterable, Kind, line, oval, rectangle, SelectionMode, automatic, .displayName (+27 more)

### Community 64 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (13): UIColor, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int, StaticString (+5 more)

### Community 65 - "layers"
Cohesion: 0.07
Nodes (27): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+19 more)

### Community 66 - ".rows"
Cohesion: 0.11
Nodes (27): stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all, effectMenuSections() (+19 more)

### Community 67 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 68 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 69 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

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

### Community 75 - "BrushStamper"
Cohesion: 0.12
Nodes (14): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+6 more)

### Community 76 - "CompositorMetalEngine"
Cohesion: 0.12
Nodes (23): Admission, admitted, noHeadroom, overBudget, CompositorMetalEngine, .uploadCacheCounts, Entry, Key (+15 more)

### Community 77 - ".attach"
Cohesion: 0.23
Nodes (5): Context, UIPinchGestureRecognizer, .gradientStops, previous, UITableView

### Community 78 - ".registerGroups"
Cohesion: 0.26
Nodes (3): GroupRegistration, RegistrationElement, RegistrationFrame

### Community 79 - "Effect"
Cohesion: 0.09
Nodes (32): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+24 more)

### Community 80 - "Codable"
Cohesion: 0.05
Nodes (49): Codable, Kind, folder, layer, CodingKeys, amount, angleDegrees, brightness (+41 more)

### Community 81 - "DrawingView"
Cohesion: 0.06
Nodes (26): Alignment, App, task, PaintApp, .body, ActionRecorderIndicator, .body, CanvasNoticeBanner (+18 more)

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

### Community 87 - "SwiftUI"
Cohesion: 0.07
Nodes (17): Combine, os, CodableColor, .color, Color, .codable, CodableColor, ScenePhaseSaveGate (+9 more)

### Community 88 - "CompositorRole"
Cohesion: 0.13
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 89 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 90 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (11): UIImage, EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor (+3 more)

### Community 91 - "ARAPLogicTests"
Cohesion: 0.06
Nodes (30): ARAPInterpolation, ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex (+22 more)

### Community 92 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 93 - ".evaluate"
Cohesion: 0.14
Nodes (19): CGPathElementType, Direction, backward, forward, fromRest, Evaluation, GroupWarp, InterpolationEvaluator (+11 more)

### Community 94 - "InterpolationRenderLogicTests"
Cohesion: 0.20
Nodes (8): ID, InterpolationRenderLogicTests, CGSize, CodableColor, Int, UIImage, UUID, VectorStroke

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
Cohesion: 0.09
Nodes (22): CodingKey, CodingKeys, endPoint, kind, rotation, spanStart, spanSweep, startPoint (+14 more)

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
Nodes (32): Arity, fixed, variadic, Array, .containsAGrade, .effectIntermediateTextures, .gpuLeafThreshold, .leafLayerIndices (+24 more)

### Community 118 - "EffectParityLogicTests"
Cohesion: 0.20
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 119 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 120 - "RenderRequest"
Cohesion: 0.11
Nodes (24): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, RenderResolution, full (+16 more)

### Community 121 - "MaskSource"
Cohesion: 0.15
Nodes (11): MaskSource, folder, .id, layer, Encoder, UUID, CanvasManager, .renderLeafOrder (+3 more)

### Community 122 - "VectorSample"
Cohesion: 0.08
Nodes (18): Int64, VectorSample, .point, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool (+10 more)

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
Cohesion: 0.25
Nodes (4): rest, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 130 - "MotionGroup"
Cohesion: 0.23
Nodes (9): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 131 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 132 - "EyedropperLogicTests"
Cohesion: 0.09
Nodes (8): Eyedropper, Sample, CGSize, Double, Int, UInt8, EyedropperLogicTests, UInt8

### Community 133 - ".arched"
Cohesion: 0.25
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 134 - "TimedSample"
Cohesion: 0.12
Nodes (8): GuidePath, .end, .start, TimeInterval, TimeInterval, TimedSample, .point, TimeInterval

### Community 135 - "InterpolateBar"
Cohesion: 0.14
Nodes (15): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+7 more)

### Community 136 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 137 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 138 - ".draw"
Cohesion: 0.32
Nodes (7): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 139 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 140 - "ResolvedMask"
Cohesion: 0.15
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 141 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 142 - "CanvasNotice"
Cohesion: 0.07
Nodes (17): Kind, CanvasNotice, .actionTitle, .code, .duration, .message, Kind, hiddenLayer (+9 more)

### Community 143 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 144 - "OnionSkinSource.swift"
Cohesion: 0.13
Nodes (9): tinted, OnionSkinSettingsSource, OnionSkinSource, Bool, CanvasManager, StaticString, UIImage, UInt (+1 more)

### Community 145 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
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
Cohesion: 0.16
Nodes (14): LassoFillMask, CGPath, Float, Int, SIMD4, UInt8, mask, LassoFillLogicTests (+6 more)

### Community 150 - "CanvasManager"
Cohesion: 0.11
Nodes (19): UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move (+11 more)

### Community 151 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 152 - "LayerKind"
Cohesion: 0.25
Nodes (6): LayerKind, raster, value, vector, K, KeyedDecodingContainer

### Community 153 - "InterpolationRecipe"
Cohesion: 0.19
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 154 - "CanvasManager"
Cohesion: 0.09
Nodes (14): CanvasManager, Bool, CGSize, UIImage, CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale (+6 more)

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

### Community 160 - "LayerRowModel"
Cohesion: 0.13
Nodes (16): DispatchWorkItem, IndexPath, LayerRowModel, .folderID, .isFolder, .maskSource, LayerStackListView.Coordinator, BlendMode (+8 more)

### Community 161 - "LayerFolder"
Cohesion: 0.13
Nodes (14): CelLocation, BlendMode, Double, UUID, LayerFolder, .compositorOp, .isCompositorNode, .maxInputCount (+6 more)

### Community 162 - "StructureSnapshot"
Cohesion: 0.22
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

### Community 167 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 168 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 170 - "TODO.md"
Cohesion: 0.28
Nodes (5): Done this pass, In flight, Queued, The canvas size that actually matters, TODO

### Community 171 - "1. The decisions"
Cohesion: 0.15
Nodes (13): 1. The decisions, `ActionsMenu` gains the ability to enter a mode, Fonts go through one seam and nothing else, Handles live outside the warped layer, Live warp is Core Animation; the bake is a compute kernel, Persistence: one new case, no sidecar, no version number, Point text grows; a box you sized wraps, The bake trigger is one line (+5 more)

### Community 172 - "EffectPipelines"
Cohesion: 0.10
Nodes (21): Metal, MTLLibrary, MTLTextureUsage, Attempt, image, unavailable, underPressure, BlendMode (+13 more)

### Community 173 - ".compositeSize"
Cohesion: 0.18
Nodes (6): OnionSkinBudget, OnionSkinOpacityRamp, CGSize, Double, Int, Int

### Community 174 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 176 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 177 - ".image"
Cohesion: 0.14
Nodes (11): NSObjectProtocol, Key, OnionSkinFrame, OnionSkinRasterCache, .residentBytes, CanvasManager, Cel, ObjectIdentifier (+3 more)

### Community 178 - ".makeUIView"
Cohesion: 0.12
Nodes (9): CanvasView, OnionSkinKey, CGImage, Context, Coordinator, LayerTransform, ObjectIdentifier, UIColor (+1 more)

### Community 179 - "OnionSkinSettings"
Cohesion: 0.19
Nodes (9): .opacitySliders, OnionSkinSettings, Side, .id, next, .step, CodableColor, Double (+1 more)

### Community 180 - "GuideStroke"
Cohesion: 0.13
Nodes (15): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+7 more)

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

### Community 185 - "InterpolationRefusal"
Cohesion: 0.15
Nodes (15): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+7 more)

### Community 186 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

### Community 187 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 188 - ".sample"
Cohesion: 0.18
Nodes (13): NSObject, ObjectiveC.runtime, FoundElement, ResolvedTarget, Bool, CGRect, CGSize, Double (+5 more)

### Community 189 - ".handleShouldReceive"
Cohesion: 0.36
Nodes (4): Bool, ObjectIdentifier, UIGestureRecognizer, UITouch

### Community 190 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 191 - "FillBoundaryLogicTests"
Cohesion: 0.32
Nodes (5): FillBoundaryLogicTests, Bool, Float, Int, UInt8

### Community 192 - "ActionsMenu"
Cohesion: 0.18
Nodes (13): ActionsMenu, .addTextRow, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, .textUnavailableReason (+5 more)

### Community 193 - "InterpolationPreviewKey"
Cohesion: 0.18
Nodes (9): InterpolationPreviewKey, Bool, Int, Layer, Set, UIEvent, UIGestureRecognizer, UITouch (+1 more)

### Community 194 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 195 - "UndoHistory"
Cohesion: 0.23
Nodes (7): Action, Bool, Int, Void, UndoHistory, .canRedo, .canUndo

### Community 196 - "Performance"
Cohesion: 0.14
Nodes (14): 1. The recalibration, and what it promotes, 2. What the artist actually feels, 3. The programme, 4. The onion-skin device re-run (2026-08-18), 5. What not to do, 6. Open questions, Answered, Performance (+6 more)

### Community 197 - ".textureBudgetBytes"
Cohesion: 0.36
Nodes (5): CompositorBudget, .textureBudgetBytes, CGSize, Int, UInt64

### Community 198 - "Handoff — 2026-08-18"
Cohesion: 0.20
Nodes (10): Handoff — 2026-08-18, Onion skin: what the device settled, Open: `tmp/lasso` — the live owner bug, Process, this pass, Still queued, The one thing to read first, The oval unification merged after this was first written, The two owner answers that did more than any analysis (+2 more)

### Community 199 - ".addImageToActiveVectorLayer"
Cohesion: 0.27
Nodes (3): Bool, LayerTransform, UIImage

### Community 200 - ".sampledColor"
Cohesion: 0.36
Nodes (3): CanvasManager, Bool, Color

### Community 201 - "Lasso Fill — Specification"
Cohesion: 0.22
Nodes (9): 1. The algorithm, in standard terms, 2. Is the owner's proposal right?, 3. The rule, for an artist, 4. Edge cases, decided, 5. What shipped applications do, and where this diverges, 6. Pixel-level specification, 7. When there is nothing to fill, 8. Open risks (+1 more)

### Community 202 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, guideIDs, localEdits, mode, references, spacing, t

### Community 203 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 205 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 206 - "MergeLossKind"
Cohesion: 0.40
Nodes (5): MergeLossKind, blendMode, .confirmationMessage, valueLayerContent, PendingMergeConfirmation

### Community 207 - ".render"
Cohesion: 0.40
Nodes (3): CGSize, UIImage, ThumbnailRenderer

### Community 208 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 209 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 211 - "SandwichPresentation"
Cohesion: 0.67
Nodes (3): SandwichPresentation, disengaged, midStroke

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **863 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+858 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **20 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CGFloat` connect `CGFloat` to `PaintUITestCase`, `CGPoint`, `Coordinator`, `CanvasManager`, `String`, `ShapeOverlayView`, `BrushBlendMode`, `cels`, `StrokeCanvasView`, `ActionRecorder`, `BrushEngineLogicTests`, `UIKit`, `Brush`, `VectorEraserLogicTests`, `Coordinator`, `.transparentFormat`, `CanvasManager`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `Binding`, `.reconcileLayers`, `FloatingPieceOverlayView`, `AnimationTimeline`, `ProjectSaveLogicTests`, `LayerStackCell`, `VectorCanvas`, `EraserSettingsPanel`, `WindowEventTap`, `SideToolbar`, `Coordinator`, `ObjectTransformOverlayView`, `XCUIApplication`, `Lattice`, `AlphaMask`, `StrokeStabilizer`, `CaseIterable`, `CompositorParityLogicTests`, `layers`, `.rows`, `.apply`, `BrushStamper`, `.registerGroups`, `DrawingView`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `EffectLayerLogicTests`, `ARAPLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `GuideOverlayView`, `DeformFactorization`, `RenderRequest`, `VectorSample`, `InterpolationGuideLogicTests`, `.indices`, `CanvasManager`, `InterpolationEngineDiagnosticsLogicTests`, `.arched`, `TimedSample`, `.launchIntoEditor`, `.draw`, `.manager`, `SpacingChart`, `OnionSkinSource.swift`, `TransformOverlaySupport.swift`, `LassoFillLogicTests`, `CanvasManager`, `PinchMergeGateLogicTests`, `InterpolationRecipe`, `CanvasManager`, `CanvasTransformFreezeUITests`, `VectorEraserMode`, `LayerRowModel`, `CurveEditor`, `.compositeSize`, `JSONValue`, `.image`, `.makeUIView`, `SandwichCompositingUITests`, `.sample`, `CodingKeys`, `ActionsMenu`, `InterpolationPreviewKey`, `CGContextDabTarget`, `Kind`?**
  _High betweenness centrality (0.309) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `InterpolationEngineDiagnosticsLogicTests`, `EyedropperLogicTests`, `ColorPickerPanel`, `TimedSample`, `Coordinator`, `String`, `ShapeOverlayView`, `BrushBlendMode`, `.arched`, `StrokeCanvasView`, `.manager`, `BrushEngineLogicTests`, `cels`, `UIKit`, `Brush`, `VectorEraserLogicTests`, `Coordinator`, `.transparentFormat`, `.withStructureUndo`, `CanvasManager`, `CanvasManager`, `TransformOverlaySupport.swift`, `LassoFillLogicTests`, `CanvasManager`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `LayerRowModel`, `CurveEditor`, `FloatingPieceOverlayView`, `AnimationTimeline`, `ProjectSaveLogicTests`, `VectorCanvas`, `SelectionOverlayView`, `.makeUIView`, `WindowEventTap`, `.rasterize`, `ObjectTransformOverlayView`, `CGFloat`, `Lattice`, `.sample`, `AlphaMask`, `StrokeStabilizer`, `CaseIterable`, `layers`, `CGContextDabTarget`, `.addImageToActiveVectorLayer`, `.sampledColor`, `BrushStamper`, `.registerGroups`, `ARAPLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `GuideOverlayView`, `DeformFactorization`, `VectorSample`, `InterpolationGuideLogicTests`, `.indices`?**
  _High betweenness centrality (0.152) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `PaintUITestCase`, `InterpolationEngineDiagnosticsLogicTests`, `CGPoint`, `.manager`, `EyedropperLogicTests`, `BackupManagerLogicTests`, `cels`, `BrushEngineLogicTests`, `CanvasNotice`, `UIKit`, `Brush`, `VectorEraserLogicTests`, `LassoFillLogicTests`, `PinchMergeGateLogicTests`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `ShapeHoldClock`, `VectorEraserMode`, `ProjectSaveLogicTests`, `SelectionOverlayView`, `RenderTreeCharacterizationTests`, `MaskGuardLogicTests`, `OnionSkinLogicTests`, `Lattice`, `AlphaMask`, `FillBoundaryLogicTests`, `CompositorParityLogicTests`, `LayerTreeCharacterizationTests`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `EffectLayerLogicTests`, `ARAPLogicTests`, `EffectMultiPassLogicTests`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `PlaybackBoundsCharacterizationTests`, `EffectParityLogicTests`, `BlockDragCharacterizationTests`, `VectorSample`, `InterpolationGuideLogicTests`?**
  _High betweenness centrality (0.102) - this node is a cross-community bridge._
- **Are the 69 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 69 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.rasterize()`) actually correct?**
  _`CGFloat` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 3 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 3 INFERRED edges - model-reasoned connections that need verification._