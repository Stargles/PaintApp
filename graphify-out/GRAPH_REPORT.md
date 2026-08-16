# Graph Report - PaintApp-tlmenus  (2026-08-16)

## Corpus Check
- 177 files · ~478,222 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 5219 nodes · 16118 edges · 180 communities (167 shown, 13 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1719 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ea31aa2e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- CGFloat
- CanvasManager
- .manager
- Lattice
- Coordinator
- CGPoint
- XCTestCase
- CompositorParityLogicTests
- Coordinator
- CanvasManager
- AlphaMask
- Brush
- VectorCanvas
- ARAPLogicTests
- EffectLayerLogicTests
- ParityScenario
- CanvasManager
- Codable
- VectorEraserLogicTests
- PointCloudIndex
- Effect
- ProjectBackupManager
- SandwichLogicTests
- StrokeCanvasView
- PaintUITestCase
- EffectMultiPassLogicTests
- .drawLine
- .apply
- MaskSource
- ShapeOverlayView
- AnimationTimeline
- UIKit
- BrushEngineLogicTests
- LayerManifest
- .transparentFormat
- View
- CanvasManager
- ProjectSaveLogicTests
- PerfBaselineTests
- VectorStroke
- .launchIntoEditor
- VectorSample
- layers
- .evaluate
- InterpolationRenderLogicTests
- ValueLayerLogicTests
- .stampStroke
- .rows
- SaveSnapshot
- WindowEventTap
- RasterLayerTexture
- CanvasNotice
- ActionRecorder
- .encode
- BackupManagerLogicTests
- InterpolationModelLogicTests
- VectorEraserHybridLogicTests
- PlaybackBoundsCharacterizationTests
- StrokeSettingsPanel
- InterpolationRecipe
- CanvasManager
- GuideOverlayView
- BlendMode
- EffectParityLogicTests
- DeformFactorization
- FillParams
- MetalFillEngine
- PaletteColor
- FloatingPieceOverlayView
- CodingKeys
- Composite.metal
- LayerStackCell
- agent
- TimedSample
- .coverage
- ColorPickerPanel
- bash
- GuideStroke
- ActivePanel
- InterpolationGuideLogicTests
- XCUIApplication
- RenderNode
- read
- RenderQuality
- GuideRow
- Gesture
- CodingKey
- Compositor.swift
- VectorEraser
- MaskGuardLogicTests
- CanvasManager
- CurveEditor
- EffectPipelines
- .indices
- InterpolationRefusal
- Coordinator
- ObjectTransformOverlayView
- SelectionOverlayView
- SandwichCompositingUITests
- PerfMonitor
- SwiftUI
- EffectParams
- .setUpGestures
- LayerRowModel
- OnionSkinLogicTests
- .manager
- ContentView
- .arched
- CodingKeys
- BlockDragCharacterizationTests
- InterpolationEngineDiagnosticsLogicTests
- ValueFill
- InterpolateBar
- GalleryView
- Hashable
- LayerStackRow
- CanvasSizePickerView
- CanvasTransformFreezeUITests
- Layer Compositing
- Recording
- ViewPreset
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- Foundation
- MotionGroup
- StructureSnapshot
- UndoHistory
- TouchCountRecognizer
- EraserSettingsPanel
- LayerStackListView.Coordinator
- String
- Kind
- CanvasHostView
- StrokeGestureRecognizer
- Known Issues
- CGContextDabTarget
- SpacingChart
- StrokeStabilizer
- .registerGroups
- .handleReorderDrag
- SelectPanel
- 4. Future upgrades — the deferred list
- ActionsMenu
- .row
- TransformOverlaySupport.swift
- Usage Guide
- PaintSoftware - iPad Drawing and Animation App
- CLAUDE.md
- Multi-Session Protocol
- Next session — the layer-compositing project, after the phase 9 close-out
- MoveTransformBottomBar
- RecordingWriter
- 6. Alpha masks
- command
- JSONValue
- CodingKeys
- Kind
- CanvasView
- ManifestSkeleton
- 4. The render tree
- VectorScratchRole
- Atomic
- ToolPanelsUITests
- parallel_test.sh
- effectChannels
- CodingKeys
- Performance baseline
- CopiedCel
- SandwichPresentation
- .setPinchHighlight
- Kind
- cleanup_session.sh
- screenshot.sh
- .init
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 551 edges
2. `CGFloat` - 424 edges
3. `Effect` - 143 edges
4. `CanvasManager` - 135 edges
5. `VectorCanvas` - 123 edges
6. `layers` - 120 edges
7. `VectorSample` - 100 edges
8. `CanvasManager` - 100 edges
9. `Lattice` - 98 edges
10. `Coordinator` - 97 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `MaskGuardLogicTests` --calls--> `AlphaMask`  [INFERRED]
  PaintSoftwareUITests/MaskGuardLogicTests.swift → PaintSoftware/Models/AlphaMask.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (180 total, 13 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (23): cels, InterpolationReferenceOnionSkinSource, OnionSkinFrame, CanvasManager, CGSize, UIColor, UIImage, InterpolationMotionGroupLogicTests (+15 more)

### Community 1 - "CGFloat"
Cohesion: 0.04
Nodes (35): Void, CGFloat, ClosedFit, ShapeDetector, Bool, CGRect, Int, Corner (+27 more)

### Community 2 - "CanvasManager"
Cohesion: 0.05
Nodes (49): Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame (+41 more)

### Community 3 - ".manager"
Cohesion: 0.07
Nodes (10): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, CGSize, Int, Bool (+2 more)

### Community 4 - "Lattice"
Cohesion: 0.06
Nodes (27): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+19 more)

### Community 5 - "Coordinator"
Cohesion: 0.06
Nodes (46): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+38 more)

### Community 6 - "CGPoint"
Cohesion: 0.07
Nodes (21): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+13 more)

### Community 7 - "XCTestCase"
Cohesion: 0.07
Nodes (15): Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager (+7 more)

### Community 8 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (12): CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int, StaticString, String (+4 more)

### Community 9 - "Coordinator"
Cohesion: 0.06
Nodes (27): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, AppliedTool, Coordinator, .sandwichPresentation (+19 more)

### Community 10 - "CanvasManager"
Cohesion: 0.06
Nodes (28): CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+20 more)

### Community 11 - "AlphaMask"
Cohesion: 0.07
Nodes (15): AlphaMask, .isActive, Bool, Decoder, Int, CGSize, UIColor, UIImage (+7 more)

### Community 12 - "Brush"
Cohesion: 0.04
Nodes (49): CaseIterable, Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+41 more)

### Community 13 - "VectorCanvas"
Cohesion: 0.08
Nodes (30): Identifiable, image, kind, Kind, fill, image, stroke, Bool (+22 more)

### Community 14 - "ARAPLogicTests"
Cohesion: 0.08
Nodes (16): ARAPInterpolation, Interpolator, Options, Bool, Group, MotionGrouping, Options, Int (+8 more)

### Community 15 - "EffectLayerLogicTests"
Cohesion: 0.11
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 16 - "ParityScenario"
Cohesion: 0.09
Nodes (35): CustomStringConvertible, UUID, UIImage, UInt8, Backdrop, fill, image, none (+27 more)

### Community 17 - "CanvasManager"
Cohesion: 0.07
Nodes (30): String, UUID, String, UUID, VectorStroke, CanvasManager, FloatingPiece, .transformedBounds (+22 more)

### Community 18 - "Codable"
Cohesion: 0.05
Nodes (46): Codable, Kind, folder, layer, CodingKeys, amount, angleDegrees, brightness (+38 more)

### Community 19 - "VectorEraserLogicTests"
Cohesion: 0.08
Nodes (9): StaticString, String, UInt, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests (+1 more)

### Community 20 - "PointCloudIndex"
Cohesion: 0.11
Nodes (17): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+9 more)

### Community 21 - "Effect"
Cohesion: 0.08
Nodes (41): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+33 more)

### Community 22 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+13 more)

### Community 23 - "SandwichLogicTests"
Cohesion: 0.11
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 24 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (23): StrokeInput, TimeInterval, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster (+15 more)

### Community 25 - "PaintUITestCase"
Cohesion: 0.10
Nodes (11): PaintUITestCase, Bool, CGVector, Int, String, XCUIApplication, XCUIElement, InterpolationWorkflowUITests (+3 more)

### Community 26 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 27 - ".drawLine"
Cohesion: 0.12
Nodes (9): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, Double, TimeInterval, UInt8, EraserAndPersistenceUITests, ShapeRecoveryUITests (+1 more)

### Community 28 - ".apply"
Cohesion: 0.13
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 29 - "MaskSource"
Cohesion: 0.08
Nodes (28): MaskSource, folder, .id, layer, Encoder, UUID, Bool, Void (+20 more)

### Community 30 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+21 more)

### Community 31 - "AnimationTimeline"
Cohesion: 0.07
Nodes (34): Content, leaf, node, AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel (+26 more)

### Community 32 - "UIKit"
Cohesion: 0.08
Nodes (5): CoreGraphics, Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 33 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 34 - "LayerManifest"
Cohesion: 0.10
Nodes (28): CompositorRole, node, Decoder, Encoder, K, KeyedDecodingContainer, LayerKind, raster (+20 more)

### Community 35 - ".transparentFormat"
Cohesion: 0.12
Nodes (18): IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath, CGRect (+10 more)

### Community 36 - "View"
Cohesion: 0.13
Nodes (31): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+23 more)

### Community 37 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 38 - "ProjectSaveLogicTests"
Cohesion: 0.16
Nodes (10): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+2 more)

### Community 39 - "PerfBaselineTests"
Cohesion: 0.17
Nodes (8): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 40 - "VectorStroke"
Cohesion: 0.10
Nodes (28): CodableColor, .uiColor, DabLattice, .range, ElementData, fill, image, stroke (+20 more)

### Community 41 - ".launchIntoEditor"
Cohesion: 0.17
Nodes (4): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication, UndoAndLayerHistoryUITests

### Community 42 - "VectorSample"
Cohesion: 0.11
Nodes (17): Int64, VectorSample, .point, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool (+9 more)

### Community 43 - "layers"
Cohesion: 0.14
Nodes (14): .activeLayerIsVector, CanvasManager, Bool, CGSize, UIImage, CanvasManager, Bool, Int (+6 more)

### Community 44 - ".evaluate"
Cohesion: 0.12
Nodes (21): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+13 more)

### Community 45 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 46 - "ValueLayerLogicTests"
Cohesion: 0.14
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 47 - ".stampStroke"
Cohesion: 0.10
Nodes (20): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+12 more)

### Community 48 - ".rows"
Cohesion: 0.12
Nodes (26): Gradient, stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all (+18 more)

### Community 49 - "SaveSnapshot"
Cohesion: 0.12
Nodes (24): CelContent, CodableColor, .color, Color, .codable, LayerContent, ProjectStore, .projectsDirectory (+16 more)

### Community 50 - "WindowEventTap"
Cohesion: 0.15
Nodes (18): AnyClass, NSObject, ObjectiveC.runtime, FoundElement, InstallReport, ResolvedTarget, Bool, CGRect (+10 more)

### Community 51 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 52 - "CanvasNotice"
Cohesion: 0.06
Nodes (26): Alignment, Kind, CanvasNotice, .actionTitle, .duration, .message, Kind, hiddenLayer (+18 more)

### Community 53 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 54 - ".encode"
Cohesion: 0.17
Nodes (18): BlendMode, .shaderCode, CompositorMetalEngine, MetalCompositor, ScratchTexturePool, Bool, CGImage, Double (+10 more)

### Community 55 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 56 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 57 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 58 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 59 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 60 - "InterpolationRecipe"
Cohesion: 0.17
Nodes (12): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+4 more)

### Community 61 - "CanvasManager"
Cohesion: 0.11
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 62 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 63 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 64 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 65 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 66 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 67 - "MetalFillEngine"
Cohesion: 0.16
Nodes (17): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+9 more)

### Community 68 - "PaletteColor"
Cohesion: 0.16
Nodes (16): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+8 more)

### Community 69 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 70 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 71 - "Composite.metal"
Cohesion: 0.25
Nodes (26): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+18 more)

### Community 72 - "LayerStackCell"
Cohesion: 0.11
Nodes (9): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, UIView, Void (+1 more)

### Community 73 - "agent"
Cohesion: 0.08
Nodes (25): agent, orchestrator, worker-integration, worker-research, worker-test, worker-ui, model, description (+17 more)

### Community 74 - "TimedSample"
Cohesion: 0.12
Nodes (8): GuidePath, .end, .start, TimeInterval, TimeInterval, TimedSample, .point, TimeInterval

### Community 75 - ".coverage"
Cohesion: 0.16
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 76 - "ColorPickerPanel"
Cohesion: 0.12
Nodes (18): ColorPickerPanel, .body, .colorTab, .currentColor, .hexRow, .hueSlider, .palettesTab, .renameAlertBinding (+10 more)

### Community 77 - "bash"
Cohesion: 0.16
Nodes (24): worker-bugfix, worker-feature, gh *, git *, xcodebuild *, permission, bash, edit (+16 more)

### Community 78 - "GuideStroke"
Cohesion: 0.12
Nodes (15): CodingKeys, boundGroups, id, interval, role, samples, GuideRole, both (+7 more)

### Community 79 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, brush, color, eraser, fill, layers, move (+9 more)

### Community 81 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 82 - "RenderNode"
Cohesion: 0.21
Nodes (16): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, RenderRequest (+8 more)

### Community 83 - "read"
Cohesion: 0.35
Nodes (23): read, applyEffect(), blendOver(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix() (+15 more)

### Community 84 - "RenderQuality"
Cohesion: 0.19
Nodes (14): CanvasManager, LayerRenderSource, RenderBackground, SandwichRequests, Bool, CGImage, CGSize, Int (+6 more)

### Community 85 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 86 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 87 - "CodingKey"
Cohesion: 0.09
Nodes (22): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+14 more)

### Community 88 - "Compositor.swift"
Cohesion: 0.19
Nodes (19): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+11 more)

### Community 89 - "VectorEraser"
Cohesion: 0.16
Nodes (8): CutOutcome, cut, missed, unchanged, IntersectionDriver, Bool, Double, VectorEraser

### Community 90 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 91 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 92 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 93 - "EffectPipelines"
Cohesion: 0.16
Nodes (13): Metal, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool, Int, MTLCommandQueue (+5 more)

### Community 95 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 96 - "Coordinator"
Cohesion: 0.20
Nodes (10): .body, Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID (+2 more)

### Community 97 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (11): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Bool (+3 more)

### Community 98 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 99 - "SandwichCompositingUITests"
Cohesion: 0.25
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 100 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+7 more)

### Community 101 - "SwiftUI"
Cohesion: 0.12
Nodes (9): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, PhotosUI (+1 more)

### Community 102 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 103 - ".setUpGestures"
Cohesion: 0.15
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 104 - "LayerRowModel"
Cohesion: 0.15
Nodes (12): effectMenuSlug(), String, UIColor, LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode (+4 more)

### Community 105 - "OnionSkinLogicTests"
Cohesion: 0.19
Nodes (9): OnionSkinSource, PreviousCelOnionSkinSource, OnionSkinLogicTests, Bool, CanvasManager, StaticString, UIImage, UInt (+1 more)

### Community 106 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 107 - "ContentView"
Cohesion: 0.13
Nodes (13): App, AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager (+5 more)

### Community 108 - ".arched"
Cohesion: 0.25
Nodes (5): GuideSet, .isEmpty, Bool, CGVector, UUID

### Community 109 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 110 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 111 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 112 - "ValueFill"
Cohesion: 0.12
Nodes (14): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+6 more)

### Community 113 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 114 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 115 - "Hashable"
Cohesion: 0.12
Nodes (14): Hashable, Hasher, LayerContentVersion, Cel, ObjectIdentifier, UUID, Tool, eraser (+6 more)

### Community 116 - "LayerStackRow"
Cohesion: 0.12
Nodes (15): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+7 more)

### Community 117 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 118 - "CanvasTransformFreezeUITests"
Cohesion: 0.29
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 119 - "Layer Compositing"
Cohesion: 0.12
Nodes (16): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 5.1 GPU, via Metal, 5.2 The sandwich, 5.3 Performance (+8 more)

### Community 120 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 121 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 122 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 123 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 124 - "Foundation"
Cohesion: 0.13
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 125 - "MotionGroup"
Cohesion: 0.18
Nodes (10): Layer, String, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor (+2 more)

### Community 126 - "StructureSnapshot"
Cohesion: 0.22
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 127 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 128 - "TouchCountRecognizer"
Cohesion: 0.21
Nodes (9): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+1 more)

### Community 129 - "EraserSettingsPanel"
Cohesion: 0.16
Nodes (12): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+4 more)

### Community 130 - "LayerStackListView.Coordinator"
Cohesion: 0.20
Nodes (8): IndexPath, DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizerDelegate, UISwipeActionsConfiguration, UITableViewDelegate

### Community 131 - "String"
Cohesion: 0.29
Nodes (6): Entry, ObjectIdentifier, Set, String, UIGestureRecognizer, UIView

### Community 132 - "Kind"
Cohesion: 0.14
Nodes (14): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+6 more)

### Community 133 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 134 - "StrokeGestureRecognizer"
Cohesion: 0.34
Nodes (7): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, UIGestureRecognizer

### Community 135 - "Known Issues"
Cohesion: 0.15
Nodes (13): A green backend-parity test does not prove both backends ran (2026-08-15), A mask sourced from a graded group can be stale (2026-08-15), Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed (+5 more)

### Community 136 - "CGContextDabTarget"
Cohesion: 0.27
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 137 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 138 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 139 - ".registerGroups"
Cohesion: 0.29
Nodes (3): GroupRegistration, RegistrationElement, RegistrationFrame

### Community 140 - ".handleReorderDrag"
Cohesion: 0.26
Nodes (4): Context, UILongPressGestureRecognizer, UIPinchGestureRecognizer, UITableView

### Community 141 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 142 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 143 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 144 - ".row"
Cohesion: 0.29
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 145 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 146 - "Usage Guide"
Cohesion: 0.22
Nodes (9): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide (+1 more)

### Community 147 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 149 - "Multi-Session Protocol"
Cohesion: 0.25
Nodes (8): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Why the full run costs what it does

### Community 150 - "Next session — the layer-compositing project, after the phase 9 close-out"
Cohesion: 0.25
Nodes (8): Before you run out of context, Machine and delegation discipline, Next session — the layer-compositing project, after the phase 9 close-out, Owner decisions — settled, do not re-ask, Still open, The two hazards this project keeps paying for, What shipped this session, Where verification stands

### Community 151 - "MoveTransformBottomBar"
Cohesion: 0.29
Nodes (6): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void

### Community 153 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 154 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 155 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 156 - "CodingKeys"
Cohesion: 0.29
Nodes (7): CodingKeys, guideIDs, localEdits, mode, references, spacing, t

### Community 157 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 158 - "CanvasView"
Cohesion: 0.29
Nodes (4): CanvasView, CanvasManager, Coordinator, UIViewRepresentable

### Community 159 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 160 - "4. The render tree"
Cohesion: 0.33
Nodes (6): 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes, 4.4 Effects are both a layer and a node, 4.5 Value layers, 4. The render tree

### Community 161 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 162 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 164 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 165 - "effectChannels"
Cohesion: 0.70
Nodes (5): effectChannels(), lutEntry(), uint, noiseValue(), screenValue()

### Community 166 - "CodingKeys"
Cohesion: 0.40
Nodes (5): CodingKeys, kind, mixMode, op, String

### Community 167 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 168 - "CopiedCel"
Cohesion: 0.50
Nodes (3): CopiedCel, Int, UIImage

### Community 169 - "SandwichPresentation"
Cohesion: 0.50
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 171 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

## Knowledge Gaps
- **681 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+676 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `CanvasManager`, `Lattice`, `Coordinator`, `CGPoint`, `CompositorParityLogicTests`, `Coordinator`, `CanvasManager`, `AlphaMask`, `Brush`, `VectorCanvas`, `ARAPLogicTests`, `EffectLayerLogicTests`, `ParityScenario`, `CanvasManager`, `VectorEraserLogicTests`, `PointCloudIndex`, `SandwichLogicTests`, `StrokeCanvasView`, `PaintUITestCase`, `.apply`, `ShapeOverlayView`, `AnimationTimeline`, `BrushEngineLogicTests`, `.transparentFormat`, `ProjectSaveLogicTests`, `PerfBaselineTests`, `VectorStroke`, `.launchIntoEditor`, `VectorSample`, `layers`, `.evaluate`, `InterpolationRenderLogicTests`, `.stampStroke`, `.rows`, `WindowEventTap`, `RasterLayerTexture`, `CanvasNotice`, `ActionRecorder`, `InterpolationModelLogicTests`, `VectorEraserHybridLogicTests`, `StrokeSettingsPanel`, `InterpolationRecipe`, `CanvasManager`, `GuideOverlayView`, `DeformFactorization`, `FloatingPieceOverlayView`, `LayerStackCell`, `TimedSample`, `InterpolationGuideLogicTests`, `XCUIApplication`, `RenderNode`, `VectorEraser`, `CanvasManager`, `CurveEditor`, `.indices`, `Coordinator`, `ObjectTransformOverlayView`, `SandwichCompositingUITests`, `LayerRowModel`, `OnionSkinLogicTests`, `.manager`, `.arched`, `CodingKeys`, `InterpolationEngineDiagnosticsLogicTests`, `InterpolateBar`, `CanvasTransformFreezeUITests`, `SideToolbar`, `EraserSettingsPanel`, `LayerStackListView.Coordinator`, `CGContextDabTarget`, `SpacingChart`, `StrokeStabilizer`, `ActionsMenu`, `TransformOverlaySupport.swift`, `JSONValue`, `Kind`?**
  _High betweenness centrality (0.335) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `CGFloat`, `CanvasManager`, `LayerStackListView.Coordinator`, `Lattice`, `Coordinator`, `.manager`, `CGContextDabTarget`, `Coordinator`, `StrokeStabilizer`, `CanvasManager`, `.registerGroups`, `VectorCanvas`, `ARAPLogicTests`, `AlphaMask`, `ParityScenario`, `CanvasManager`, `TransformOverlaySupport.swift`, `VectorEraserLogicTests`, `PointCloudIndex`, `StrokeCanvasView`, `ShapeOverlayView`, `AnimationTimeline`, `BrushEngineLogicTests`, `.transparentFormat`, `ProjectSaveLogicTests`, `PerfBaselineTests`, `VectorStroke`, `VectorSample`, `layers`, `.evaluate`, `InterpolationRenderLogicTests`, `.stampStroke`, `WindowEventTap`, `RasterLayerTexture`, `InterpolationModelLogicTests`, `VectorEraserHybridLogicTests`, `InterpolationRecipe`, `CanvasManager`, `GuideOverlayView`, `DeformFactorization`, `FloatingPieceOverlayView`, `TimedSample`, `ColorPickerPanel`, `InterpolationGuideLogicTests`, `VectorEraser`, `CurveEditor`, `.indices`, `ObjectTransformOverlayView`, `SelectionOverlayView`, `.setUpGestures`, `.manager`, `.arched`, `InterpolationEngineDiagnosticsLogicTests`, `Foundation`?**
  _High betweenness centrality (0.145) - this node is a cross-community bridge._
- **Why does `task` connect `bash` to `CanvasNotice`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._