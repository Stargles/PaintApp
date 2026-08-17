# Graph Report - PaintSoftware  (2026-08-17)

## Corpus Check
- 197 files · ~549,863 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 5583 nodes · 17120 edges · 187 communities (167 shown, 20 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1801 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `350c9a31`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PaintUITestCase
- ShapeGeometry
- ProjectBackupManager
- .manager
- Coordinator
- ColorPickerPanel
- bash
- CanvasManager
- VectorElement
- ShapeOverlayView
- Identifiable
- cels
- StrokeCanvasView
- ActionRecorder
- BrushEngineLogicTests
- CanvasManager
- UIKit
- CGPoint
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
- StrokeGestureRecognizer
- RasterLayerTexture
- StrokeSpatialIndex
- ActivePanel
- StrokeSettingsPanel
- Coordinator
- FloatingPieceOverlayView
- AnimationTimeline
- View
- ProjectSaveLogicTests
- LayerStackCell
- TransformOverlaySupport.swift
- XCTestCase
- SelectionOverlayView
- EraserSettingsPanel
- RenderTreeCharacterizationTests
- ContentView
- PerfMonitor
- Layer
- Codable
- CanvasSizePickerView
- WindowEventTap
- SideToolbar
- LayerRowModel
- Kind
- ObjectTransformOverlayView
- Housekeeping pass (8 items from 2026-07-22 feature audit)
- XCUIApplication
- UndoHistory
- Lattice
- AlphaMask
- SaveSnapshot
- StrokeStabilizer
- BrushStamper
- CompositorParityLogicTests
- CanvasManager
- .rows
- CanvasHostView
- ProjectSummary
- SelectPanel
- PaintSoftware iPad drawing/animation app
- BrushStamper.DabRNG (seeded splitmix64)
- PerfBaselineTests.swift
- LayerTreeCharacterizationTests
- .apply
- CGFloat
- CompositorMetalEngine
- InterpolationRecipe
- PointCloudIndex
- Effect
- CodingKeys
- CanvasNotice
- SandwichLogicTests
- CGImage.cropping(to:) retains parent pixel data
- Multi-Session Protocol
- graphify usage protocol
- VectorCanvasDataLogicTests
- SwiftUI
- MaskGuardLogicTests
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
- CodingKeys
- Composite.metal
- PlaybackBoundsCharacterizationTests
- GuideOverlayView
- DeformFactorization
- .group
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
- CGContextDabTarget
- read
- GuidePath
- .arched
- TimedSample
- InterpolateBar
- .launchIntoEditor
- EffectParams
- RenderRequest
- BackupManagerLogicTests
- .coverage
- .manager
- Is the brush engine ready for `.ABR` / Procreate brush import?
- SpacingChart
- OnionSkinLogicTests
- Vector Interpolation
- .init
- Kind
- command
- CutOutcome
- Kind
- PinchMergeGateLogicTests
- GuideStroke
- .makeUIView
- CanvasManager
- Gesture
- CanvasTransformFreezeUITests
- ShapeHoldClock
- run.sh
- Hashable
- LayerStackListView.Coordinator
- SelectionMode
- StructureSnapshot
- CurveEditor
- ActionsMenu
- .row
- MotionGroup
- VectorScratchRole
- ToolPanelsUITests
- Atomic
- TODO
- 1. The decisions
- .testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold
- .noteTransition
- JSONValue
- RecordingWriter
- ManifestSkeleton
- Handoff — 2026-08-16
- StrokeSampleGate
- .testLassoIgnoresAFingerWhilePencilOnlyModeIsOn
- 4. Future upgrades — the deferred list
- Add Text
- What is already right, and must not be lost
- What needs to change
- SandwichPresentation
- CopiedCel
- simlock.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 573 edges
2. `CGFloat` - 454 edges
3. `Effect` - 149 edges
4. `CanvasManager` - 141 edges
5. `VectorCanvas` - 124 edges
6. `layers` - 118 edges
7. `VectorSample` - 115 edges
8. `CanvasManager` - 100 edges
9. `Coordinator` - 100 edges
10. `Lattice` - 98 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
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

## Communities (187 total, 20 thin omitted)

### Community 0 - "PaintUITestCase"
Cohesion: 0.11
Nodes (9): FillLiveAdjustUITests, PaintUITestCase, Bool, Int, XCUIApplication, InterpolationWorkflowUITests, TimelineGestureUITests, SelectionAndMoveUITests (+1 more)

### Community 1 - "ShapeGeometry"
Cohesion: 0.05
Nodes (31): ClosedFit, ShapeDetector, Bool, CGRect, Int, Corner, bottomLeft, bottomRight (+23 more)

### Community 2 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+14 more)

### Community 3 - ".manager"
Cohesion: 0.06
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 4 - "Coordinator"
Cohesion: 0.06
Nodes (46): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+38 more)

### Community 5 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (38): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+30 more)

### Community 6 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 7 - "CanvasManager"
Cohesion: 0.04
Nodes (52): Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame (+44 more)

### Community 8 - "VectorElement"
Cohesion: 0.04
Nodes (80): Error, CodableColor, .uiColor, CodingKeys, brush, color, composite, elements (+72 more)

### Community 9 - "ShapeOverlayView"
Cohesion: 0.07
Nodes (35): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+27 more)

### Community 10 - "Identifiable"
Cohesion: 0.04
Nodes (46): CaseIterable, Identifiable, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+38 more)

### Community 11 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 12 - "StrokeCanvasView"
Cohesion: 0.11
Nodes (22): StrokeInput, TimeInterval, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas (+14 more)

### Community 13 - "ActionRecorder"
Cohesion: 0.10
Nodes (23): ActionRecorder, .directory, .now, Recording, .id, .name, .sizeText, CFTimeInterval (+15 more)

### Community 14 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 15 - "CanvasManager"
Cohesion: 0.09
Nodes (25): CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform, .affineTransform (+17 more)

### Community 16 - "UIKit"
Cohesion: 0.05
Nodes (11): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, AppVersion, .versionString, String (+3 more)

### Community 17 - "CGPoint"
Cohesion: 0.07
Nodes (16): CGPoint, .length, .center, .point, Capsule, .boundingBox, Intersection, StrokeGeometry (+8 more)

### Community 18 - "VectorEraserLogicTests"
Cohesion: 0.09
Nodes (9): StaticString, String, UInt, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests (+1 more)

### Community 19 - ".setUpGestures"
Cohesion: 0.12
Nodes (11): CGSize, Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, Void, TouchTypePressRecognizer (+3 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.12
Nodes (20): IntPoint, PixelOps, .rasterizeCacheBytes, RasterizeCache, .bytesResident, RasterizeKey, Bool, Cel (+12 more)

### Community 21 - "layers"
Cohesion: 0.12
Nodes (16): .activeLayerIsVector, .activeCelIsInBetween, .guideRefusal, .interpolationTarget, .linkableGuideStrokes, LayerTransform, UIImage, CanvasManager (+8 more)

### Community 22 - "CanvasManager"
Cohesion: 0.09
Nodes (17): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+9 more)

### Community 23 - "MetalFillEngine"
Cohesion: 0.08
Nodes (30): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool (+22 more)

### Community 24 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 25 - ".drawLine"
Cohesion: 0.12
Nodes (10): FillContainmentUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement, EraserAndPersistenceUITests (+2 more)

### Community 26 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (41): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+33 more)

### Community 27 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 28 - "PerfBaselineTests"
Cohesion: 0.14
Nodes (8): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 29 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 30 - "StrokeGestureRecognizer"
Cohesion: 0.10
Nodes (20): StrokeGestureRecognizer, Any, Bool, Int, Selector, Set, UIEvent, UITouch (+12 more)

### Community 31 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 32 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 33 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, brush, color, eraser, fill, layers, move (+9 more)

### Community 34 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 35 - "Coordinator"
Cohesion: 0.08
Nodes (22): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, NSCoder, Coordinator, .canvasContentScale (+14 more)

### Community 36 - "FloatingPieceOverlayView"
Cohesion: 0.14
Nodes (13): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+5 more)

### Community 37 - "AnimationTimeline"
Cohesion: 0.05
Nodes (46): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+38 more)

### Community 38 - "View"
Cohesion: 0.12
Nodes (32): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+24 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.16
Nodes (10): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+2 more)

### Community 40 - "LayerStackCell"
Cohesion: 0.09
Nodes (12): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIColor (+4 more)

### Community 41 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 42 - "XCTestCase"
Cohesion: 0.10
Nodes (12): CGImage, CGRect, String, UInt8, XCTestCase, CanvasManager, CGImage, Int (+4 more)

### Community 43 - "SelectionOverlayView"
Cohesion: 0.08
Nodes (21): resolvedLastTouchType(), UITouch, SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder (+13 more)

### Community 44 - "EraserSettingsPanel"
Cohesion: 0.16
Nodes (12): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+4 more)

### Community 45 - "RenderTreeCharacterizationTests"
Cohesion: 0.14
Nodes (7): StaticString, UInt, RenderTreeCharacterizationTests, BlendMode, CanvasManager, String, UUID

### Community 46 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 47 - "PerfMonitor"
Cohesion: 0.13
Nodes (15): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+7 more)

### Community 48 - "Layer"
Cohesion: 0.10
Nodes (17): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+9 more)

### Community 49 - "Codable"
Cohesion: 0.11
Nodes (28): Codable, Kind, folder, layer, Decoder, ValueFill, CompositorRole, node (+20 more)

### Community 50 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 51 - "WindowEventTap"
Cohesion: 0.14
Nodes (19): AnyClass, NSObject, ObjectiveC.runtime, FoundElement, InstallReport, ResolvedTarget, Bool, CGRect (+11 more)

### Community 52 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 53 - "LayerRowModel"
Cohesion: 0.11
Nodes (23): DispatchWorkItem, Coordinator, LayerRowModel, .folderID, .isFolder, .maskSource, LayerStackListView, BlendMode (+15 more)

### Community 54 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 55 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

### Community 56 - "Housekeeping pass (8 items from 2026-07-22 feature audit)"
Cohesion: 0.14
Nodes (15): AppVersion.current stale hardcoded git hash, Color picker discarded hue on gray swatch, deleteCel no-op on layer's last remaining cel, Fill tool off-center fill vertically mirrored (regression), flipCanvas skipped object (photo) layers, FloodFillEngine.fill, ProjectStore.save composites every visible layer for thumbnail, testFillToolBridgesOpenContourGapWhenGapClosingEnabled (XCTSkip) (+7 more)

### Community 57 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 58 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 59 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 60 - "AlphaMask"
Cohesion: 0.08
Nodes (14): AlphaMask, .isActive, Bool, Int, CGSize, UIColor, UIImage, MaskParityLogicTests (+6 more)

### Community 61 - "SaveSnapshot"
Cohesion: 0.15
Nodes (17): CelContent, LayerContent, ProjectStore, .projectsDirectory, SaveSnapshot, BlendMode, Bool, CanvasManager (+9 more)

### Community 62 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 63 - "BrushStamper"
Cohesion: 0.15
Nodes (13): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+5 more)

### Community 64 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (12): CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int, StaticString, String (+4 more)

### Community 65 - "CanvasManager"
Cohesion: 0.05
Nodes (39): CanvasManager, .guideChips, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases, .motionGroupChips (+31 more)

### Community 66 - ".rows"
Cohesion: 0.12
Nodes (27): Gradient, stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all (+19 more)

### Community 67 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 68 - "ProjectSummary"
Cohesion: 0.11
Nodes (19): os, CodableColor, .color, Color, .codable, ProjectSummary, CodableColor, Date (+11 more)

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
Nodes (6): Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String, UUID

### Community 74 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 75 - "CGFloat"
Cohesion: 0.08
Nodes (26): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, Brush, CGFloat (+18 more)

### Community 76 - "CompositorMetalEngine"
Cohesion: 0.10
Nodes (27): Admission, admitted, noHeadroom, overBudget, BlendMode, .shaderCode, CompositorMetalEngine, .uploadCacheCounts (+19 more)

### Community 77 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 78 - "PointCloudIndex"
Cohesion: 0.11
Nodes (18): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+10 more)

### Community 79 - "Effect"
Cohesion: 0.10
Nodes (40): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, Curves, Effect, .displayName (+32 more)

### Community 80 - "CodingKeys"
Cohesion: 0.05
Nodes (43): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+35 more)

### Community 81 - "CanvasNotice"
Cohesion: 0.07
Nodes (26): Alignment, Kind, CanvasNotice, .actionTitle, .duration, .message, Kind, hiddenLayer (+18 more)

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
Cohesion: 0.08
Nodes (15): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, MoveTransformBottomBar (+7 more)

### Community 88 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 89 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 90 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 91 - "ARAPLogicTests"
Cohesion: 0.11
Nodes (10): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, .rigidMotionL, Int, StaticString (+2 more)

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

### Community 110 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 111 - "CodingKeys"
Cohesion: 0.04
Nodes (57): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+49 more)

### Community 112 - "Composite.metal"
Cohesion: 0.21
Nodes (31): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+23 more)

### Community 113 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 114 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 115 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 116 - ".group"
Cohesion: 0.17
Nodes (7): Group, MotionGrouping, Options, Bool, Int, Set, groups

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
Cohesion: 0.12
Nodes (21): CanvasManager, LayerRenderSource, RenderBackground, RenderResolution, full, half, .id, .scale (+13 more)

### Community 121 - "MaskSource"
Cohesion: 0.12
Nodes (13): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, Bool (+5 more)

### Community 122 - "VectorSample"
Cohesion: 0.16
Nodes (7): VectorSample, CountingDabTarget, StrokeSampleGateLogicTests, CGBlendMode, UIColor, UInt64, Tremor

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
Cohesion: 0.30
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 130 - "CGContextDabTarget"
Cohesion: 0.24
Nodes (8): CGGradient, Key, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 131 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 132 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 133 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 134 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 135 - "InterpolateBar"
Cohesion: 0.14
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 136 - ".launchIntoEditor"
Cohesion: 0.12
Nodes (14): BlendModesAndCompositorUITests, LayerPanelUITests, SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String (+6 more)

### Community 137 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 138 - "RenderRequest"
Cohesion: 0.23
Nodes (12): CoreGraphicsCompositor, CGImage, CGRect, Double, UIImage, UInt8, Attempt, image (+4 more)

### Community 139 - "BackupManagerLogicTests"
Cohesion: 0.18
Nodes (6): BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 140 - ".coverage"
Cohesion: 0.18
Nodes (12): Hasher, CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8 (+4 more)

### Community 141 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 142 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.29
Nodes (4): Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do

### Community 143 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 144 - "OnionSkinLogicTests"
Cohesion: 0.12
Nodes (14): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGSize, UIColor, UIImage, OnionSkinLogicTests (+6 more)

### Community 145 - "Vector Interpolation"
Cohesion: 0.33
Nodes (6): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 5. Open judgement calls for the product owner, Vector Interpolation, What the papers say

### Community 147 - "Kind"
Cohesion: 0.14
Nodes (14): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+6 more)

### Community 148 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 149 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 150 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 151 - "PinchMergeGateLogicTests"
Cohesion: 0.21
Nodes (5): PinchMergeGate, RowLayout, Bool, Int, PinchMergeGateLogicTests

### Community 152 - "GuideStroke"
Cohesion: 0.13
Nodes (15): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+7 more)

### Community 153 - ".makeUIView"
Cohesion: 0.11
Nodes (10): AppliedTool, CanvasView, CanvasManager, Color, Context, Coordinator, Double, LayerTransform (+2 more)

### Community 154 - "CanvasManager"
Cohesion: 0.15
Nodes (12): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+4 more)

### Community 155 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 156 - "CanvasTransformFreezeUITests"
Cohesion: 0.26
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 157 - "ShapeHoldClock"
Cohesion: 0.19
Nodes (9): ShapeHoldClock, .isHoldComplete, .stillDuration, Bool, TimeInterval, ShapeHoldClockLogicTests, Bool, Int (+1 more)

### Community 159 - "Hashable"
Cohesion: 0.25
Nodes (7): Hashable, CelLocation, Tool, eraser, fill, pen, pencil

### Community 160 - "LayerStackListView.Coordinator"
Cohesion: 0.13
Nodes (13): IndexPath, DropTarget, between, onto, LayerStackListView.Coordinator, Bool, ObjectIdentifier, TimeInterval (+5 more)

### Community 161 - "SelectionMode"
Cohesion: 0.14
Nodes (11): CanvasManager, Bool, CGSize, UIImage, SelectionMode, automatic, .displayName, .id (+3 more)

### Community 162 - "StructureSnapshot"
Cohesion: 0.19
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 163 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 164 - "ActionsMenu"
Cohesion: 0.23
Nodes (10): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, .renderResolutionControl, CanvasManager, Double (+2 more)

### Community 165 - ".row"
Cohesion: 0.29
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 166 - "MotionGroup"
Cohesion: 0.17
Nodes (13): CodingKeys, displayName, id, mode, tagColor, GroupInterpolation, auto, clean (+5 more)

### Community 167 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 169 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Value, Void

### Community 170 - "TODO"
Cohesion: 0.33
Nodes (4): Done this pass, In flight, Queued, TODO

### Community 171 - "1. The decisions"
Cohesion: 0.15
Nodes (13): 1. The decisions, `ActionsMenu` gains the ability to enter a mode, Fonts go through one seam and nothing else, Handles live outside the warped layer, Live warp is Core Animation; the bake is a compute kernel, Persistence: one new case, no sidecar, no version number, Point text grows; a box you sized wraps, The bake trigger is one line (+5 more)

### Community 172 - ".testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold"
Cohesion: 0.33
Nodes (6): CompositorBudget, .textureBudgetBytes, CGSize, Int, UInt64, CGSize

### Community 173 - ".noteTransition"
Cohesion: 0.29
Nodes (5): Entry, ObjectIdentifier, Set, UIGestureRecognizer, UIView

### Community 174 - "JSONValue"
Cohesion: 0.25
Nodes (8): JSONValue, bool, int, null, num, str, Bool, Int

### Community 176 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 177 - "Handoff — 2026-08-16"
Cohesion: 0.33
Nodes (6): Blocked on the owner, Branch state, Handoff — 2026-08-16, Process, learned expensively here, The one genuinely new capability: you can test on the owner's iPad, The two open bugs, with what is already known

### Community 179 - ".testLassoIgnoresAFingerWhilePencilOnlyModeIsOn"
Cohesion: 0.47
Nodes (3): SelectionPencilOnlyUITests, Bool, XCUIApplication

### Community 180 - "4. Future upgrades — the deferred list"
Cohesion: 0.33
Nodes (6): 4. Future upgrades — the deferred list, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance, The big one — engine upgrade candidates, UI and workflow

### Community 181 - "Add Text"
Cohesion: 0.40
Nodes (5): 2. Why the rejected alternatives were rejected, 3. Staged delivery, 4. Performance rules, 5. Behaviour, decided, Add Text

### Community 182 - "What is already right, and must not be lost"
Cohesion: 0.40
Nodes (5): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, What is already right, and must not be lost

### Community 183 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 184 - "SandwichPresentation"
Cohesion: 0.40
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 185 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 186 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Ambiguous Edges - Review These
- `Stroke-delivery regression (pencil-only-drawing default)` → `Fill tool off-center fill vertically mirrored (regression)`  [AMBIGUOUS]
  BUGS.md · relation: conceptually_related_to

## Knowledge Gaps
- **722 isolated node(s):** `In flight`, `Queued`, `Done this pass`, `graphify-guard.sh script`, `gallery` (+717 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **20 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Stroke-delivery regression (pencil-only-drawing default)` and `Fill tool off-center fill vertically mirrored (regression)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `CGFloat` connect `CGFloat` to `PaintUITestCase`, `ShapeGeometry`, `Coordinator`, `CanvasManager`, `VectorElement`, `ShapeOverlayView`, `Identifiable`, `cels`, `StrokeCanvasView`, `ActionRecorder`, `BrushEngineLogicTests`, `CanvasManager`, `UIKit`, `CGPoint`, `VectorEraserLogicTests`, `.setUpGestures`, `.transparentFormat`, `CanvasManager`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `StrokeSpatialIndex`, `StrokeSettingsPanel`, `Coordinator`, `FloatingPieceOverlayView`, `AnimationTimeline`, `ProjectSaveLogicTests`, `LayerStackCell`, `TransformOverlaySupport.swift`, `EraserSettingsPanel`, `WindowEventTap`, `SideToolbar`, `LayerRowModel`, `ObjectTransformOverlayView`, `XCUIApplication`, `Lattice`, `AlphaMask`, `StrokeStabilizer`, `BrushStamper`, `CompositorParityLogicTests`, `CanvasManager`, `.rows`, `.apply`, `InterpolationRecipe`, `PointCloudIndex`, `CanvasNotice`, `SandwichLogicTests`, `VectorCanvasDataLogicTests`, `EffectLayerLogicTests`, `ARAPLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `GuideOverlayView`, `DeformFactorization`, `.group`, `RenderQuality`, `VectorSample`, `InterpolationGuideLogicTests`, `.indices`, `CanvasManager`, `InterpolationEngineDiagnosticsLogicTests`, `CGContextDabTarget`, `GuidePath`, `.arched`, `TimedSample`, `InterpolateBar`, `.launchIntoEditor`, `RenderRequest`, `.manager`, `SpacingChart`, `OnionSkinLogicTests`, `Kind`, `PinchMergeGateLogicTests`, `.makeUIView`, `CanvasManager`, `CanvasTransformFreezeUITests`, `LayerStackListView.Coordinator`, `SelectionMode`, `CurveEditor`, `ActionsMenu`, `JSONValue`, `StrokeSampleGate`, `SandwichPresentation`?**
  _High betweenness centrality (0.311) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `ShapeGeometry`, `CGContextDabTarget`, `.manager`, `GuidePath`, `ColorPickerPanel`, `TimedSample`, `Coordinator`, `VectorElement`, `ShapeOverlayView`, `Identifiable`, `InterpolationEngineDiagnosticsLogicTests`, `StrokeCanvasView`, `.arched`, `BrushEngineLogicTests`, `CanvasManager`, `UIKit`, `.manager`, `VectorEraserLogicTests`, `.setUpGestures`, `.transparentFormat`, `layers`, `CanvasManager`, `.makeUIView`, `CanvasManager`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `RasterLayerTexture`, `StrokeSpatialIndex`, `SelectionMode`, `LayerStackListView.Coordinator`, `Coordinator`, `CurveEditor`, `AnimationTimeline`, `FloatingPieceOverlayView`, `ProjectSaveLogicTests`, `TransformOverlaySupport.swift`, `SelectionOverlayView`, `StrokeSampleGate`, `WindowEventTap`, `ObjectTransformOverlayView`, `SandwichPresentation`, `cels`, `Lattice`, `AlphaMask`, `StrokeStabilizer`, `BrushStamper`, `CanvasManager`, `CGFloat`, `InterpolationRecipe`, `PointCloudIndex`, `ARAPLogicTests`, `.evaluate`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `GuideOverlayView`, `DeformFactorization`, `.group`, `VectorSample`, `InterpolationGuideLogicTests`, `.indices`?**
  _High betweenness centrality (0.153) - this node is a cross-community bridge._
- **Why does `.body` connect `CanvasNotice` to `ActivePanel`, `AnimationTimeline`, `SelectPanel`, `CanvasManager`, `ContentView`, `PerfMonitor`, `SideToolbar`, `SwiftUI`, `.makeUIView`?**
  _High betweenness centrality (0.078) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._