# Graph Report - PaintSoftware  (2026-08-15)

## Corpus Check
- 169 files · ~410,134 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4798 nodes · 14741 edges · 159 communities (140 shown, 19 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1598 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `1338749e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- CGPoint
- ProjectBackupManager
- .manager
- Coordinator
- ColorPickerPanel
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
- Coordinator
- .transparentFormat
- layers
- CanvasManager
- MetalFillEngine
- ViewPreset
- .stampStroke
- VectorEraserHybridLogicTests
- CanvasManager
- PerfBaselineTests
- FillParams
- TouchCountRecognizer
- RasterLayerTexture
- StrokeSpatialIndex
- ActivePanel
- StrokeSettingsPanel
- LayerHostView
- FloatingPieceOverlayView
- AnimationTimeline
- View
- .load
- LayerStackCell
- TransformOverlaySupport.swift
- SelectionMode
- SelectionOverlayView
- BrushSettingsPanel
- CGContextDabTarget
- ContentView
- PerfMonitor
- CodingKeys
- Codable
- CanvasSizePickerView
- .attach
- SideToolbar
- Coordinator
- LayerRowModel
- ObjectTransformOverlayView
- Housekeeping pass (8 items from 2026-07-22 feature audit)
- CompositorRole
- UndoHistory
- Lattice
- AlphaMask
- SaveSnapshot
- StrokeStabilizer
- CGFloat
- CompositorParityLogicTests
- CanvasManager
- LayerStackRow
- CanvasHostView
- GalleryView
- SelectPanel
- PaintSoftware iPad drawing/animation app
- BrushStamper.DabRNG (seeded splitmix64)
- PerfBaselineTests.swift
- XCTestCase
- .apply
- ActionsMenu
- Layer
- InterpolationRecipe
- PointCloudIndex
- Effect
- CodingKeys
- DrawingView
- SandwichLogicTests
- CGImage.cropping(to:) retains parent pixel data
- Multi-Session Protocol
- graphify usage protocol
- Hashable
- SwiftUI
- Atomic
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
- .encode
- CodingKeys
- Composite.metal
- PlaybackBoundsCharacterizationTests
- GuideOverlayView
- DeformFactorization
- BackupManagerLogicTests
- RenderNode
- EffectParityLogicTests
- .group
- RenderRequest
- MaskSource
- GuideStroke
- InterpolationGuideLogicTests
- GuideRow
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
- BrushStamper
- EffectParams
- .draw
- StructureSnapshot
- MotionGroup
- .manager
- Is the brush engine ready for `.ABR` / Procreate brush import?
- SpacingChart
- OnionSkinLogicTests
- 4. Future upgrades — the deferred list
- GuidePath
- Kind
- command
- CutOutcome
- Kind
- ManifestSkeleton
- Corner
- Edge
- .render
- Kind
- .encode
- .init
- run.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 539 edges
2. `CGFloat` - 412 edges
3. `CanvasManager` - 125 edges
4. `VectorCanvas` - 123 edges
5. `layers` - 117 edges
6. `Effect` - 105 edges
7. `CanvasManager` - 100 edges
8. `VectorSample` - 99 edges
9. `Lattice` - 98 edges
10. `Coordinator` - 95 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Stroke-delivery regression: default flip, gate, and recognizer state involved together** — bugs_stroke_delivery_regression, bugs_requirespencilonly, bugs_pencilonlydrawing, bugs_reconcilelayers, bugs_housekeeping_2026_07_26 [EXTRACTED 1.00]

## Communities (159 total, 19 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.05
Nodes (30): FillUITests, LayerUITests, .crossing, Bool, CGVector, Int, String, TimeInterval (+22 more)

### Community 1 - "CGPoint"
Cohesion: 0.06
Nodes (31): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+23 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 3 - ".manager"
Cohesion: 0.07
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 4 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 6 - "bash"
Cohesion: 0.13
Nodes (28): worker-feature, worker-integration, worker-research, gh *, git *, xcodebuild *, permission, bash (+20 more)

### Community 7 - "CanvasManager"
Cohesion: 0.05
Nodes (44): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .effectiveLoopRange, .hasLoopBoundary, .isFillInAdjustableState (+36 more)

### Community 8 - "VectorCanvas"
Cohesion: 0.06
Nodes (54): Identifiable, CodableColor, .uiColor, image, kind, DabLattice, .range, ElementData (+46 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+21 more)

### Community 10 - "Brush"
Cohesion: 0.06
Nodes (37): Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal (+29 more)

### Community 11 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.08
Nodes (29): StrokeInput, TimeInterval, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster (+21 more)

### Community 13 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 14 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 15 - "CanvasManager"
Cohesion: 0.09
Nodes (27): .currentFrame, .currentLayerIndex, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move (+19 more)

### Community 16 - "UIKit"
Cohesion: 0.05
Nodes (10): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, AppVersion, .versionString, String (+2 more)

### Community 17 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (14): Capsule, .boundingBox, Intersection, StrokeGeometry, Bool, CGRect, ClosedRange, Int (+6 more)

### Community 18 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 19 - "Coordinator"
Cohesion: 0.07
Nodes (26): AppliedTool, CanvasView, Coordinator, .sandwichPresentation, SandwichPresentation, disengaged, midStroke, CanvasManager (+18 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.10
Nodes (23): IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath, CGRect (+15 more)

### Community 21 - "layers"
Cohesion: 0.17
Nodes (13): .activeLayerIsVector, CanvasManager, Bool, Int, Cel, .endFrame, Int, UIImage (+5 more)

### Community 22 - "CanvasManager"
Cohesion: 0.09
Nodes (17): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+9 more)

### Community 23 - "MetalFillEngine"
Cohesion: 0.08
Nodes (30): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool (+22 more)

### Community 24 - "ViewPreset"
Cohesion: 0.19
Nodes (8): CanvasManager, .activeViewName, Int, String, Bool, String, UUID, ViewPreset

### Community 25 - ".stampStroke"
Cohesion: 0.08
Nodes (22): AnyObject, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+14 more)

### Community 26 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (49): CustomStringConvertible, UUID, UIImage, UInt8, Backdrop, fill, image, none (+41 more)

### Community 27 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 28 - "PerfBaselineTests"
Cohesion: 0.20
Nodes (7): PerfBaselineTests, Bool, Double, Int, String, UInt64, VectorStroke

### Community 29 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 30 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 31 - "RasterLayerTexture"
Cohesion: 0.19
Nodes (10): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+2 more)

### Community 32 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 33 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 34 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker (+18 more)

### Community 35 - "LayerHostView"
Cohesion: 0.08
Nodes (15): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, InterpolationPreviewKey, SandwichKey, Bool (+7 more)

### Community 36 - "FloatingPieceOverlayView"
Cohesion: 0.10
Nodes (19): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+11 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.07
Nodes (31): Gesture, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .gapMenu (+23 more)

### Community 38 - "View"
Cohesion: 0.10
Nodes (35): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel, .body (+27 more)

### Community 39 - ".load"
Cohesion: 0.17
Nodes (9): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+1 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.09
Nodes (11): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+3 more)

### Community 41 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 42 - "SelectionMode"
Cohesion: 0.14
Nodes (11): CanvasManager, Bool, CGSize, UIImage, SelectionMode, automatic, .displayName, .id (+3 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 44 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 45 - "CGContextDabTarget"
Cohesion: 0.25
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 46 - "ContentView"
Cohesion: 0.13
Nodes (13): App, AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager (+5 more)

### Community 47 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+7 more)

### Community 48 - "CodingKeys"
Cohesion: 0.08
Nodes (25): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+17 more)

### Community 49 - "Codable"
Cohesion: 0.17
Nodes (24): Codable, Kind, folder, layer, LayerKind, compositing, raster, vector (+16 more)

### Community 50 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 51 - ".attach"
Cohesion: 0.29
Nodes (4): Context, UILongPressGestureRecognizer, UIPinchGestureRecognizer, UITableView

### Community 52 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 53 - "Coordinator"
Cohesion: 0.15
Nodes (15): NSObject, Coordinator, DropTarget, between, onto, LayerStackListView, CanvasManager, Coordinator (+7 more)

### Community 54 - "LayerRowModel"
Cohesion: 0.12
Nodes (15): IndexPath, LayerRowModel, .folderID, .isFolder, .maskSource, LayerStackListView.Coordinator, BlendMode, Bool (+7 more)

### Community 55 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 56 - "Housekeeping pass (8 items from 2026-07-22 feature audit)"
Cohesion: 0.14
Nodes (15): AppVersion.current stale hardcoded git hash, Color picker discarded hue on gray swatch, deleteCel no-op on layer's last remaining cel, Fill tool off-center fill vertically mirrored (regression), flipCanvas skipped object (photo) layers, FloodFillEngine.fill, ProjectStore.save composites every visible layer for thumbnail, testFillToolBridgesOpenContourGapWhenGapClosingEnabled (XCTSkip) (+7 more)

### Community 57 - "CompositorRole"
Cohesion: 0.20
Nodes (7): CompositorRole, node, slot, Decoder, Encoder, Int, UUID

### Community 58 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 59 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 60 - "AlphaMask"
Cohesion: 0.05
Nodes (22): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8, AlphaMask (+14 more)

### Community 61 - "SaveSnapshot"
Cohesion: 0.12
Nodes (22): BrushLibrary, .customBrushesDirectory, URL, CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary (+14 more)

### Community 62 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 63 - "CGFloat"
Cohesion: 0.14
Nodes (10): Void, CGFloat, VectorSample, Sweep, Bool, CGRect, ClosedRange, Double (+2 more)

### Community 64 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (14): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+6 more)

### Community 65 - "CanvasManager"
Cohesion: 0.06
Nodes (28): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+20 more)

### Community 66 - "LayerStackRow"
Cohesion: 0.12
Nodes (16): FolderKind, compositorNode, group, inputSlot, LayerStackRow, .depth, folder, .folderID (+8 more)

### Community 67 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 68 - "GalleryView"
Cohesion: 0.14
Nodes (12): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void (+4 more)

### Community 69 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 70 - "PaintSoftware iPad drawing/animation app"
Cohesion: 0.18
Nodes (13): Animation Timeline feature, Brush library feature (shape/hardness/spacing/stabilization/grain), Native-resolution raster/vector drawing engine (no PencilKit), GPU (Metal) colour-based flood fill feature, Gallery / project browser feature, Layers feature (raster/vector/object layers), PaintSoftware iPad drawing/animation app, Project directory structure (Engine/Models/Services/Utilities/Views) (+5 more)

### Community 72 - "PerfBaselineTests.swift"
Cohesion: 0.18
Nodes (11): CelCRUDCharacterizationTests, Shared frame-length clamp relaxed to >=, duplicateCel adjacent-neighbour overlap bug, Autorelease artifact in re-measuring memory (renderToUIImage), BrushStamper.stampStroke, Stroke cost tracks path length, not sample count, PerfBaselineTests.swift, Refactor Stage 0 — baseline + characterization tests (+3 more)

### Community 73 - "XCTestCase"
Cohesion: 0.08
Nodes (13): Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager (+5 more)

### Community 74 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 75 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 76 - "Layer"
Cohesion: 0.18
Nodes (10): Layer, .compositingEffect, .isFillReference, BlendMode, Bool, Cel, Double, String (+2 more)

### Community 77 - "InterpolationRecipe"
Cohesion: 0.07
Nodes (21): InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve, Bool (+13 more)

### Community 78 - "PointCloudIndex"
Cohesion: 0.10
Nodes (19): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+11 more)

### Community 79 - "Effect"
Cohesion: 0.08
Nodes (39): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+31 more)

### Community 80 - "CodingKeys"
Cohesion: 0.06
Nodes (38): CodingKeys, amount, angleDegrees, brightness, contrast, gamma, hueDegrees, inputBlack (+30 more)

### Community 81 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 82 - "SandwichLogicTests"
Cohesion: 0.11
Nodes (8): leaf, Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 83 - "CGImage.cropping(to:) retains parent pixel data"
Cohesion: 0.50
Nodes (4): CGImage.cropping(to:) retains parent pixel data, PixelOps.copiedSubimage, UIGraphicsImageRendererFormat.preferredRange defaults to extended-range on wide-colour iPad, Stage 5 performance work (dab gradient cache, dirty-rect undo)

### Community 84 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Deploy to iPad (deploy.sh, auto-resign), Multi-Session Protocol, deploy/mac/parallel_test.sh, Remote testing via Tailscale to Mac, Worktree-per-session workflow, Foolproof project backups (Session 34)

### Community 85 - "graphify usage protocol"
Cohesion: 0.67
Nodes (3): graphify-out/GRAPH_REPORT.md, .claude/hooks/graphify-guard.sh, graphify usage protocol

### Community 86 - "Hashable"
Cohesion: 0.25
Nodes (7): Hashable, CelLocation, Tool, eraser, fill, pen, pencil

### Community 87 - "SwiftUI"
Cohesion: 0.09
Nodes (14): Combine, CodableColor, .color, Color, .codable, CodableColor, .interpolateButton, InterpolatePanel (+6 more)

### Community 88 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 89 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 90 - "EffectLayerLogicTests"
Cohesion: 0.14
Nodes (13): CGImage, CGRect, UInt8, EffectLayerLogicTests, .side, CanvasManager, CGImage, Int (+5 more)

### Community 91 - "ARAPLogicTests"
Cohesion: 0.12
Nodes (10): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, .rigidMotionL, Int, StaticString (+2 more)

### Community 92 - "EffectMultiPassLogicTests"
Cohesion: 0.15
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 93 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 94 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 95 - "Layer Compositing"
Cohesion: 0.05
Nodes (36): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+28 more)

### Community 109 - "BlendMode"
Cohesion: 0.05
Nodes (36): CaseIterable, Kind, line, oval, rectangle, BlendMode, add, clipToBelow (+28 more)

### Community 110 - ".encode"
Cohesion: 0.17
Nodes (18): BlendMode, .shaderCode, CompositorMetalEngine, MetalCompositor, ScratchTexturePool, Bool, CGImage, Double (+10 more)

### Community 111 - "CodingKeys"
Cohesion: 0.06
Nodes (33): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+25 more)

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

### Community 116 - "BackupManagerLogicTests"
Cohesion: 0.18
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 117 - "RenderNode"
Cohesion: 0.10
Nodes (24): Arity, fixed, variadic, Array, .leafLayerIndices, .needsCompositorOnCanvas, CompositorOp, .arity (+16 more)

### Community 118 - "EffectParityLogicTests"
Cohesion: 0.18
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 119 - ".group"
Cohesion: 0.17
Nodes (7): Group, MotionGrouping, Options, Bool, Int, Set, groups

### Community 120 - "RenderRequest"
Cohesion: 0.16
Nodes (18): CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, SandwichRequests, Bool, Cel (+10 more)

### Community 121 - "MaskSource"
Cohesion: 0.15
Nodes (11): MaskSource, folder, .id, layer, Encoder, UUID, CanvasManager, .renderLeafOrder (+3 more)

### Community 122 - "GuideStroke"
Cohesion: 0.13
Nodes (16): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+8 more)

### Community 124 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 125 - "agent"
Cohesion: 0.09
Nodes (21): agent, orchestrator, worker-bugfix, worker-test, worker-ui, model, description, mode (+13 more)

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
Cohesion: 0.39
Nodes (19): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+11 more)

### Community 132 - "InterpolationRefusal"
Cohesion: 0.16
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 133 - ".arched"
Cohesion: 0.27
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 134 - "TimedSample"
Cohesion: 0.17
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 135 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 136 - "BrushStamper"
Cohesion: 0.24
Nodes (3): BrushStamper, CanvasManager, UIImage

### Community 137 - "EffectParams"
Cohesion: 0.12
Nodes (17): EffectParams, amount, brightness, contrast, hueTurns, intensity, isMonochrome, levels (+9 more)

### Community 138 - ".draw"
Cohesion: 0.32
Nodes (8): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 139 - "StructureSnapshot"
Cohesion: 0.19
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 140 - "MotionGroup"
Cohesion: 0.17
Nodes (11): GroupRegistration, Layer, String, GroupInterpolation, auto, clean, crossFade, MotionGroup (+3 more)

### Community 142 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 143 - "SpacingChart"
Cohesion: 0.19
Nodes (4): SpacingChart, .curve, .draggable, stops

### Community 144 - "OnionSkinLogicTests"
Cohesion: 0.24
Nodes (6): OnionSkinSource, PreviousCelOnionSkinSource, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 145 - "4. Future upgrades — the deferred list"
Cohesion: 0.15
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 146 - "GuidePath"
Cohesion: 0.27
Nodes (3): GuidePath, CGVector, TimeInterval

### Community 147 - "Kind"
Cohesion: 0.18
Nodes (11): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+3 more)

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

### Community 152 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 153 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 154 - ".render"
Cohesion: 0.40
Nodes (3): CGSize, UIImage, ThumbnailRenderer

### Community 155 - "Kind"
Cohesion: 0.40
Nodes (5): Kind, compositorNode, group, inputSlot, layer

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **637 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+632 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **19 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CGFloat` connect `CGFloat` to `CanvasManager`, `CGPoint`, `InterpolationEngineDiagnosticsLogicTests`, `.launchIntoEditor`, `Coordinator`, `.arched`, `TimedSample`, `CanvasManager`, `VectorCanvas`, `InterpolateBar`, `Brush`, `.draw`, `StrokeCanvasView`, `CodingKeys`, `BrushEngineLogicTests`, `SpacingChart`, `UIKit`, `StrokeGeometryLogicTests`, `GuidePath`, `VectorEraserLogicTests`, `CanvasManager`, `.transparentFormat`, `CanvasManager`, `Kind`, `Coordinator`, `.stampStroke`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `LayerHostView`, `FloatingPieceOverlayView`, `AnimationTimeline`, `.load`, `LayerStackCell`, `TransformOverlaySupport.swift`, `SelectionMode`, `CGContextDabTarget`, `ShapeOverlayView`, `BrushStamper`, `SideToolbar`, `Coordinator`, `LayerRowModel`, `cels`, `Lattice`, `AlphaMask`, `StrokeStabilizer`, `CompositorParityLogicTests`, `CanvasManager`, `.apply`, `ActionsMenu`, `InterpolationRecipe`, `PointCloudIndex`, `DrawingView`, `SandwichLogicTests`, `OnionSkinLogicTests`, `EffectLayerLogicTests`, `ARAPLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `BlendMode`, `GuideOverlayView`, `DeformFactorization`, `.group`, `InterpolationGuideLogicTests`, `.indices`?**
  _High betweenness centrality (0.304) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `InterpolationEngineDiagnosticsLogicTests`, `.manager`, `Coordinator`, `ColorPickerPanel`, `TimedSample`, `CanvasManager`, `VectorCanvas`, `ShapeOverlayView`, `Brush`, `.arched`, `StrokeCanvasView`, `.manager`, `BrushEngineLogicTests`, `CanvasManager`, `UIKit`, `StrokeGeometryLogicTests`, `GuidePath`, `VectorEraserLogicTests`, `.transparentFormat`, `layers`, `CanvasManager`, `Coordinator`, `.stampStroke`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `StrokeSpatialIndex`, `FloatingPieceOverlayView`, `AnimationTimeline`, `.load`, `TransformOverlaySupport.swift`, `SelectionMode`, `SelectionOverlayView`, `CGContextDabTarget`, `BrushStamper`, `LayerRowModel`, `ObjectTransformOverlayView`, `cels`, `Lattice`, `AlphaMask`, `StrokeStabilizer`, `CGFloat`, `CanvasManager`, `InterpolationRecipe`, `PointCloudIndex`, `ARAPLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `BlendMode`, `GuideOverlayView`, `DeformFactorization`, `.group`, `InterpolationGuideLogicTests`, `.indices`?**
  _High betweenness centrality (0.193) - this node is a cross-community bridge._
- **Why does `CanvasManager` connect `CanvasManager` to `CGPoint`, `TimedSample`, `Brush`, `StructureSnapshot`, `MotionGroup`, `SpacingChart`, `CanvasManager`, `layers`, `CanvasManager`, `MetalFillEngine`, `ViewPreset`, `RasterLayerTexture`, `SelectionMode`, `PerfMonitor`, `Codable`, `UndoHistory`, `CGFloat`, `InterpolationRecipe`, `Hashable`, `SwiftUI`, `MaskSource`, `GuideStroke`?**
  _High betweenness centrality (0.111) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._