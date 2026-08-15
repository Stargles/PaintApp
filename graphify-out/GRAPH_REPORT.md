# Graph Report - PaintSoftware  (2026-08-15)

## Corpus Check
- 171 files · ~433,971 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4962 nodes · 15325 edges · 173 communities (153 shown, 20 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1648 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ee2bebdb`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PaintUITestCase
- CGPoint
- ProjectBackupManager
- .manager
- Coordinator
- PaletteColor
- bash
- CanvasManager
- VectorCanvas
- ShapeOverlayView
- Brush
- cels
- StrokeCanvasView
- CodingKeys
- BrushEngineLogicTests
- CanvasManager
- UIKit
- StrokeGeometryLogicTests
- VectorEraserLogicTests
- .setUpGestures
- .transparentFormat
- layers
- CanvasManager
- MetalFillEngine
- ViewPreset
- .drawLine
- VectorEraserHybridLogicTests
- CanvasManager
- PerfBaselineTests
- FillParams
- TouchCountRecognizer
- RasterLayerTexture
- StrokeSpatialIndex
- ActivePanel
- StrokeSettingsPanel
- Coordinator
- FloatingPieceOverlayView
- AnimationTimeline
- LayerOptionsPanel
- ProjectSaveLogicTests
- LayerStackCell
- TransformOverlaySupport.swift
- XCTestCase
- SelectionOverlayView
- EraserSettingsPanel
- ColorPickerPanel
- ContentView
- PerfMonitor
- CodingKeys
- ProjectManifest
- CanvasSizePickerView
- LayerStackListView
- SideToolbar
- Coordinator
- LayerRowModel
- ObjectTransformOverlayView
- Housekeeping pass (8 items from 2026-07-22 feature audit)
- XCUIApplication
- UndoHistory
- Lattice
- AlphaMask
- SaveSnapshot
- StrokeStabilizer
- VectorSample
- CompositorParityLogicTests
- CanvasManager
- LayerStackRow
- CanvasHostView
- GalleryView
- SelectPanel
- PaintSoftware iPad drawing/animation app
- BrushStamper.DabRNG (seeded splitmix64)
- PerfBaselineTests.swift
- LayerTreeCharacterizationTests
- .apply
- InterpolationRecipe
- StrokeGeometry
- InterpolationModelLogicTests
- PointCloudIndex
- Effect
- CodingKeys
- DrawingView
- SandwichLogicTests
- CGImage.cropping(to:) retains parent pixel data
- Multi-Session Protocol
- graphify usage protocol
- Tool
- SwiftUI
- MaskGuardLogicTests
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
- .encode
- CodingKey
- Composite.metal
- PlaybackBoundsCharacterizationTests
- GuideOverlayView
- CGFloat
- BackupManagerLogicTests
- RenderNode
- EffectParityLogicTests
- .group
- RenderQuality
- MaskSource
- GuideStroke
- InterpolationGuideLogicTests
- View
- agent
- Compositor.swift
- .indices
- CanvasManager
- InterpolationEngineDiagnosticsLogicTests
- BlockDragCharacterizationTests
- read
- InterpolationRefusal
- .arched
- TimedSample
- InterpolateBar
- .launchIntoEditor
- EffectParams
- RenderRequest
- StructureSnapshot
- String
- .manager
- Is the brush engine ready for `.ABR` / Procreate brush import?
- SpacingChart
- OnionSkinLogicTests
- 4. Future upgrades — the deferred list
- LatticeLogicTests
- Kind
- command
- CutOutcome
- Kind
- ManifestSkeleton
- Color
- SandwichCompositingUITests
- CanvasManager
- ValueFill
- .encode
- ResolvedMask
- run.sh
- Foundation
- LayerStackListView.Coordinator
- CompositorRole
- StrokeGestureRecognizer
- GuidePath
- ActionsMenu
- .row
- Deterministic
- CodingKeys
- ToolPanelsUITests
- Corner
- Edge
- .render
- SandwichPresentation

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 539 edges
2. `CGFloat` - 412 edges
3. `Effect` - 124 edges
4. `VectorCanvas` - 123 edges
5. `CanvasManager` - 123 edges
6. `layers` - 117 edges
7. `VectorSample` - 100 edges
8. `CanvasManager` - 100 edges
9. `Lattice` - 98 edges
10. `Coordinator` - 95 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Stroke-delivery regression: default flip, gate, and recognizer state involved together** — bugs_stroke_delivery_regression, bugs_requirespencilonly, bugs_pencilonlydrawing, bugs_reconcilelayers, bugs_housekeeping_2026_07_26 [EXTRACTED 1.00]

## Communities (173 total, 20 thin omitted)

### Community 0 - "PaintUITestCase"
Cohesion: 0.10
Nodes (11): FillLiveAdjustUITests, PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests, TimelineGestureUITests (+3 more)

### Community 1 - "CGPoint"
Cohesion: 0.07
Nodes (24): CGPoint, .length, ClosedFit, ShapeDetector, Bool, CGRect, Int, FollowFrame (+16 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 3 - ".manager"
Cohesion: 0.07
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 4 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 5 - "PaletteColor"
Cohesion: 0.16
Nodes (17): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+9 more)

### Community 6 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 7 - "CanvasManager"
Cohesion: 0.05
Nodes (43): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+35 more)

### Community 8 - "VectorCanvas"
Cohesion: 0.06
Nodes (58): Codable, Identifiable, CodableColor, .uiColor, image, kind, DabLattice, .range (+50 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+21 more)

### Community 10 - "Brush"
Cohesion: 0.06
Nodes (27): Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+19 more)

### Community 11 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (31): StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+23 more)

### Community 13 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 14 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 15 - "CanvasManager"
Cohesion: 0.08
Nodes (27): String, UUID, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move (+19 more)

### Community 16 - "UIKit"
Cohesion: 0.09
Nodes (4): CoreGraphics, Darwin, UIKit, XCTest

### Community 17 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (7): Intersection, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 18 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (7): VectorEraser, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 19 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 20 - ".transparentFormat"
Cohesion: 0.12
Nodes (20): Hashable, CelLocation, IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel (+12 more)

### Community 21 - "layers"
Cohesion: 0.14
Nodes (11): .activeLayerIsVector, .activeCelIsInBetween, CanvasManager, Bool, Int, Cel, .endFrame, Int (+3 more)

### Community 22 - "CanvasManager"
Cohesion: 0.11
Nodes (16): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+8 more)

### Community 23 - "MetalFillEngine"
Cohesion: 0.07
Nodes (34): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, BlendMode, .shaderCode, MetalCompositor (+26 more)

### Community 24 - "ViewPreset"
Cohesion: 0.20
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 25 - ".drawLine"
Cohesion: 0.12
Nodes (10): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, EraserAndPersistenceUITests (+2 more)

### Community 26 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (49): CustomStringConvertible, UUID, UIImage, UInt8, Backdrop, fill, image, none (+41 more)

### Community 27 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 28 - "PerfBaselineTests"
Cohesion: 0.08
Nodes (23): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+15 more)

### Community 29 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 30 - "TouchCountRecognizer"
Cohesion: 0.21
Nodes (9): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+1 more)

### Community 31 - "RasterLayerTexture"
Cohesion: 0.10
Nodes (22): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, RasterLayerTexture, .dabGradientCacheHits (+14 more)

### Community 32 - "StrokeSpatialIndex"
Cohesion: 0.17
Nodes (10): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+2 more)

### Community 33 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 34 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 35 - "Coordinator"
Cohesion: 0.06
Nodes (31): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, AppliedTool, CanvasView, Coordinator (+23 more)

### Community 36 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.08
Nodes (30): Gesture, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight, .frameLabel, .gapMenu, .isCollapsed (+22 more)

### Community 38 - "LayerOptionsPanel"
Cohesion: 0.12
Nodes (29): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel, .body (+21 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.16
Nodes (10): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+2 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.09
Nodes (11): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+3 more)

### Community 41 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 42 - "XCTestCase"
Cohesion: 0.15
Nodes (10): CGImage, UInt8, XCTestCase, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 44 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 45 - "ColorPickerPanel"
Cohesion: 0.11
Nodes (20): ColorPickerPanel, .colorTab, .currentColor, .hexRow, .hueSlider, .palettesTab, .renameAlertBinding, .svSquare (+12 more)

### Community 46 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 47 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 48 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+17 more)

### Community 49 - "ProjectManifest"
Cohesion: 0.15
Nodes (21): role, LayerKind, compositing, raster, value, vector, CelManifest, FolderManifest (+13 more)

### Community 50 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 51 - "LayerStackListView"
Cohesion: 0.18
Nodes (8): IndexPath, .body, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView

### Community 52 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 53 - "Coordinator"
Cohesion: 0.26
Nodes (8): NSObject, Coordinator, CanvasManager, Int, Set, UIView, UUID, UITableViewDiffableDataSource

### Community 54 - "LayerRowModel"
Cohesion: 0.14
Nodes (15): Kind, compositorNode, group, layer, LayerRowModel, .folderID, .isFolder, .maskSource (+7 more)

### Community 55 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 56 - "Housekeeping pass (8 items from 2026-07-22 feature audit)"
Cohesion: 0.14
Nodes (15): AppVersion.current stale hardcoded git hash, Color picker discarded hue on gray swatch, deleteCel no-op on layer's last remaining cel, Fill tool off-center fill vertically mirrored (regression), flipCanvas skipped object (photo) layers, FloodFillEngine.fill, ProjectStore.save composites every visible layer for thumbnail, testFillToolBridgesOpenContourGapWhenGapClosingEnabled (XCTSkip) (+7 more)

### Community 57 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 58 - "UndoHistory"
Cohesion: 0.23
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 59 - "Lattice"
Cohesion: 0.05
Nodes (40): Accelerate, Interpolator, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite (+32 more)

### Community 60 - "AlphaMask"
Cohesion: 0.07
Nodes (12): AlphaMask, .isActive, Bool, Decoder, Int, MaskParityLogicTests, .side, Bool (+4 more)

### Community 61 - "SaveSnapshot"
Cohesion: 0.12
Nodes (24): CelContent, CodableColor, .color, Color, .codable, LayerContent, ProjectStore, .projectsDirectory (+16 more)

### Community 62 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 63 - "VectorSample"
Cohesion: 0.20
Nodes (8): VectorSample, .point, Sweep, Bool, CGRect, ClosedRange, Double, samples

### Community 64 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (16): CGRect, CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager (+8 more)

### Community 65 - "CanvasManager"
Cohesion: 0.06
Nodes (29): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationOptions (+21 more)

### Community 66 - "LayerStackRow"
Cohesion: 0.12
Nodes (15): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+7 more)

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
Cohesion: 0.07
Nodes (14): Layer, StaticString, String, UInt, UUID, LayerTreeCharacterizationTests, CanvasManager, String (+6 more)

### Community 74 - ".apply"
Cohesion: 0.29
Nodes (10): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+2 more)

### Community 75 - "InterpolationRecipe"
Cohesion: 0.13
Nodes (16): Set, CelRef, InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed, .referencedCels (+8 more)

### Community 76 - "StrokeGeometry"
Cohesion: 0.15
Nodes (9): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, .dragHandle (+1 more)

### Community 77 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 78 - "PointCloudIndex"
Cohesion: 0.10
Nodes (20): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+12 more)

### Community 79 - "Effect"
Cohesion: 0.10
Nodes (35): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+27 more)

### Community 80 - "CodingKeys"
Cohesion: 0.05
Nodes (44): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+36 more)

### Community 81 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 82 - "SandwichLogicTests"
Cohesion: 0.11
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

### Community 86 - "Tool"
Cohesion: 0.33
Nodes (5): Tool, eraser, fill, pen, pencil

### Community 87 - "SwiftUI"
Cohesion: 0.10
Nodes (9): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, PhotosUI (+1 more)

### Community 88 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 89 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 90 - ".setBakedContent"
Cohesion: 0.14
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 91 - "ARAPLogicTests"
Cohesion: 0.16
Nodes (5): ARAPInterpolation, Options, Bool, ARAPLogicTests, Int

### Community 92 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 93 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+13 more)

### Community 94 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 95 - "Layer Compositing"
Cohesion: 0.05
Nodes (37): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+29 more)

### Community 109 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 110 - ".encode"
Cohesion: 0.22
Nodes (14): CompositorMetalEngine, ScratchTexturePool, Bool, CGImage, Double, Float, Int, MTLCommandQueue (+6 more)

### Community 111 - "CodingKey"
Cohesion: 0.12
Nodes (17): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+9 more)

### Community 112 - "Composite.metal"
Cohesion: 0.21
Nodes (31): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+23 more)

### Community 113 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 114 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 115 - "CGFloat"
Cohesion: 0.14
Nodes (10): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Void, CGFloat (+2 more)

### Community 116 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 117 - "RenderNode"
Cohesion: 0.10
Nodes (25): Arity, fixed, variadic, Array, .leafLayerIndices, .needsCompositorOnCanvas, CompositorOp, .arity (+17 more)

### Community 118 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 119 - ".group"
Cohesion: 0.18
Nodes (7): Group, MotionGrouping, Options, Bool, Int, Set, groups

### Community 120 - "RenderQuality"
Cohesion: 0.14
Nodes (18): CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, SandwichRequests, Bool, Cel, CGImage (+10 more)

### Community 121 - "MaskSource"
Cohesion: 0.14
Nodes (13): MaskSource, folder, .id, layer, Encoder, UUID, Bool, Void (+5 more)

### Community 122 - "GuideStroke"
Cohesion: 0.13
Nodes (14): CodingKeys, boundGroups, id, interval, samples, GuideRole, both, timing (+6 more)

### Community 124 - "View"
Cohesion: 0.14
Nodes (17): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+9 more)

### Community 125 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 126 - "Compositor.swift"
Cohesion: 0.19
Nodes (19): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+11 more)

### Community 128 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 129 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.25
Nodes (4): rest, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 130 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 131 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 132 - "InterpolationRefusal"
Cohesion: 0.18
Nodes (11): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+3 more)

### Community 133 - ".arched"
Cohesion: 0.27
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 134 - "TimedSample"
Cohesion: 0.17
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 135 - "InterpolateBar"
Cohesion: 0.14
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 136 - ".launchIntoEditor"
Cohesion: 0.18
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 137 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 138 - "RenderRequest"
Cohesion: 0.32
Nodes (9): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, RenderRequest (+1 more)

### Community 139 - "StructureSnapshot"
Cohesion: 0.27
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 140 - "String"
Cohesion: 0.06
Nodes (38): CaseIterable, Kind, line, oval, rectangle, Kind, folder, layer (+30 more)

### Community 142 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 143 - "SpacingChart"
Cohesion: 0.19
Nodes (4): SpacingChart, .curve, .draggable, stops

### Community 144 - "OnionSkinLogicTests"
Cohesion: 0.12
Nodes (14): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGSize, UIColor, UIImage, OnionSkinLogicTests (+6 more)

### Community 145 - "4. Future upgrades — the deferred list"
Cohesion: 0.15
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 146 - "LatticeLogicTests"
Cohesion: 0.15
Nodes (5): LatticeLogicTests, Int, StaticString, String, UInt

### Community 147 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 148 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 149 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 150 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 151 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 152 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 153 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 154 - "CanvasManager"
Cohesion: 0.09
Nodes (15): CanvasManager, Bool, CGSize, UIImage, CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale (+7 more)

### Community 155 - "ValueFill"
Cohesion: 0.12
Nodes (14): Layer, .compositingEffect, .hasNoDrawingSurface, .isFillReference, .valueFill, BlendMode, Bool, Cel (+6 more)

### Community 157 - "ResolvedMask"
Cohesion: 0.15
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 159 - "Foundation"
Cohesion: 0.12
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 160 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (7): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 161 - "CompositorRole"
Cohesion: 0.13
Nodes (11): K, KeyedDecodingContainer, CodingKeys, kind, mixMode, op, CompositorRole, node (+3 more)

### Community 162 - "StrokeGestureRecognizer"
Cohesion: 0.27
Nodes (7): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, UIGestureRecognizer

### Community 163 - "GuidePath"
Cohesion: 0.27
Nodes (3): GuidePath, CGVector, TimeInterval

### Community 164 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 165 - ".row"
Cohesion: 0.29
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 167 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, guideIDs, localEdits, mode, references, spacing, t

### Community 169 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 170 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 171 - ".render"
Cohesion: 0.40
Nodes (3): CGSize, UIImage, ThumbnailRenderer

### Community 172 - "SandwichPresentation"
Cohesion: 0.67
Nodes (3): SandwichPresentation, disengaged, midStroke

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **642 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+637 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **20 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CGFloat` connect `CGFloat` to `CanvasManager`, `CGPoint`, `InterpolationEngineDiagnosticsLogicTests`, `PaintUITestCase`, `Coordinator`, `.arched`, `TimedSample`, `CanvasManager`, `VectorCanvas`, `InterpolateBar`, `Brush`, `RenderRequest`, `StrokeCanvasView`, `CodingKeys`, `ShapeOverlayView`, `SpacingChart`, `CanvasManager`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `.setUpGestures`, `.transparentFormat`, `OnionSkinLogicTests`, `CanvasManager`, `Kind`, `Color`, `LatticeLogicTests`, `VectorEraserHybridLogicTests`, `CanvasManager`, `PerfBaselineTests`, `SandwichCompositingUITests`, `RasterLayerTexture`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `GuidePath`, `ActionsMenu`, `AnimationTimeline`, `Coordinator`, `ProjectSaveLogicTests`, `LayerStackCell`, `TransformOverlaySupport.swift`, `Deterministic`, `EraserSettingsPanel`, `.launchIntoEditor`, `LayerStackListView`, `SideToolbar`, `Coordinator`, `ObjectTransformOverlayView`, `cels`, `XCUIApplication`, `Lattice`, `AlphaMask`, `StrokeStabilizer`, `VectorSample`, `CompositorParityLogicTests`, `CanvasManager`, `BrushEngineLogicTests`, `InterpolationRecipe`, `StrokeGeometry`, `InterpolationModelLogicTests`, `PointCloudIndex`, `DrawingView`, `SandwichLogicTests`, `.setBakedContent`, `ARAPLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `GuideOverlayView`, `.group`, `InterpolationGuideLogicTests`, `.indices`?**
  _High betweenness centrality (0.263) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `InterpolationEngineDiagnosticsLogicTests`, `.manager`, `Coordinator`, `.arched`, `TimedSample`, `CanvasManager`, `VectorCanvas`, `ShapeOverlayView`, `Brush`, `cels`, `StrokeCanvasView`, `.manager`, `BrushEngineLogicTests`, `CanvasManager`, `StrokeGeometryLogicTests`, `LatticeLogicTests`, `VectorEraserLogicTests`, `.transparentFormat`, `layers`, `CanvasManager`, `.setUpGestures`, `CanvasManager`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `StrokeSpatialIndex`, `Foundation`, `LayerStackListView.Coordinator`, `GuidePath`, `Coordinator`, `AnimationTimeline`, `FloatingPieceOverlayView`, `ProjectSaveLogicTests`, `TransformOverlaySupport.swift`, `SelectionOverlayView`, `ColorPickerPanel`, `ObjectTransformOverlayView`, `Lattice`, `AlphaMask`, `StrokeStabilizer`, `VectorSample`, `CanvasManager`, `InterpolationRecipe`, `StrokeGeometry`, `InterpolationModelLogicTests`, `PointCloudIndex`, `ARAPLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `GuideOverlayView`, `CGFloat`, `.group`, `InterpolationGuideLogicTests`, `.indices`?**
  _High betweenness centrality (0.153) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `PaintUITestCase`, `InterpolationEngineDiagnosticsLogicTests`, `BlockDragCharacterizationTests`, `.manager`, `CGPoint`, `cels`, `BrushEngineLogicTests`, `UIKit`, `OnionSkinLogicTests`, `LatticeLogicTests`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `ProjectSaveLogicTests`, `AlphaMask`, `CompositorParityLogicTests`, `LayerTreeCharacterizationTests`, `InterpolationModelLogicTests`, `SandwichLogicTests`, `MaskGuardLogicTests`, `.setBakedContent`, `ARAPLogicTests`, `EffectMultiPassLogicTests`, `InterpolationRenderLogicTests`, `PlaybackBoundsCharacterizationTests`, `BackupManagerLogicTests`, `EffectParityLogicTests`, `InterpolationGuideLogicTests`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._