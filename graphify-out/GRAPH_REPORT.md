# Graph Report - PaintApp-layerux  (2026-08-15)

## Corpus Check
- 178 files · ~476,765 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 5220 nodes · 16119 edges · 181 communities (166 shown, 15 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1720 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `fd802d55`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- Lattice
- ShapeGeometry
- Coordinator
- CompositorParityLogicTests
- XCTestCase
- .manager
- layers
- CanvasManager
- VectorCanvas
- AlphaMask
- Coordinator
- EffectLayerLogicTests
- ParityScenario
- ColorPickerPanel
- Codable
- UIKit
- AnimationTimeline
- EffectMultiPassLogicTests
- .drawLine
- ProjectBackupManager
- CGFloat
- SandwichLogicTests
- Effect
- MetalFillEngine
- StrokeCanvasView
- PointCloudIndex
- VectorEraserLogicTests
- SaveSnapshot
- PaintUITestCase
- ShapeOverlayView
- .apply
- ValueLayerLogicTests
- BrushEngineLogicTests
- StrokeGeometryLogicTests
- CanvasManager
- View
- InterpolationRenderLogicTests
- CanvasManager
- ProjectSaveLogicTests
- .launchIntoEditor
- PerfBaselineTests
- .transparentFormat
- StrokeSettingsPanel
- BrushBlendMode
- ARAPLogicTests
- .rows
- String
- WindowEventTap
- .evaluate
- CGPoint
- VectorEraserHybridLogicTests
- RasterLayerTexture
- LayerManifest
- DeformFactorization
- DrawingView
- agent
- ActionRecorder
- .encode
- BackupManagerLogicTests
- InterpolationModelLogicTests
- Composite.metal
- InterpolationRecipe
- PlaybackBoundsCharacterizationTests
- ValueFill
- .group
- StrokeGeometry
- BlendMode
- .withStructureUndo
- RenderRequest
- StrokeSpatialIndex
- LayerStackCell
- EffectParityLogicTests
- SwiftUI
- FillParams
- CanvasManager
- MaskSource
- GuideOverlayView
- FloatingPieceOverlayView
- .activeCelIndex
- CodingKeys
- RenderNode
- OnionSkinLogicTests
- GuideStroke
- .stampStroke
- CanvasManager
- ActivePanel
- InterpolationGuideLogicTests
- XCUIApplication
- TransformMode
- GuideRow
- Gesture
- read
- Compositor.swift
- MaskGuardLogicTests
- CanvasManager
- CurveEditor
- ActionsMenu
- ContentView
- .indices
- InterpolationRefusal
- ObjectTransformOverlayView
- SelectionOverlayView
- CanvasNotice
- EffectParams
- .setUpGestures
- BlockDragCharacterizationTests
- .manager
- SandwichCompositingUITests
- .makeUIView
- PerfMonitor
- .coverage
- ViewPreset
- InterpolateBar
- .arched
- TimedSample
- VectorEraserMode
- CanvasSizePickerView
- LayerRowModel
- CanvasTransformFreezeUITests
- DabTarget
- Layer Compositing
- Recording
- .draw
- .registerGroups
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- bash
- CompositorRole
- UndoHistory
- TouchCountRecognizer
- Coordinator
- LayerStackListView
- Cel
- Kind
- CanvasHostView
- StrokeGestureRecognizer
- Known Issues
- String
- GuidePath
- SpacingChart
- MotionGroup
- StructureSnapshot
- StrokeStabilizer
- 4. Future upgrades — the deferred list
- LayerStackListView.Coordinator
- .rasterize
- .handleReorderDrag
- .row
- TransformOverlaySupport.swift
- Usage Guide
- PaintSoftware - iPad Drawing and Animation App
- CLAUDE.md
- Multi-Session Protocol
- Next session — the layer-compositing project, after the phase 9 close-out
- .setCanvasPadding
- 6. Alpha masks
- command
- JSONValue
- CutOutcome
- Kind
- ManifestSkeleton
- RecordingWriter
- 4. The render tree
- VectorScratchRole
- Atomic
- ToolPanelsUITests
- parallel_test.sh
- DabLattice
- Performance baseline
- SandwichPresentation
- .setPinchHighlight
- cleanup_session.sh
- screenshot.sh
- .init
- .bytes
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

## Communities (181 total, 15 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 1 - "Lattice"
Cohesion: 0.05
Nodes (35): CodingKeys, activeCells, cellSize, cols, originX, originY, rows, vertices (+27 more)

### Community 2 - "ShapeGeometry"
Cohesion: 0.05
Nodes (32): ClosedFit, ShapeDetector, Bool, CGRect, Int, Corner, bottomLeft, bottomRight (+24 more)

### Community 3 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 4 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (15): CGSize, UIColor, UIImage, CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage (+7 more)

### Community 5 - "XCTestCase"
Cohesion: 0.07
Nodes (15): Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager (+7 more)

### Community 6 - ".manager"
Cohesion: 0.07
Nodes (9): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool, CanvasManager (+1 more)

### Community 7 - "layers"
Cohesion: 0.07
Nodes (30): Identifiable, CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider (+22 more)

### Community 8 - "CanvasManager"
Cohesion: 0.05
Nodes (35): Void, CanvasManager, .activeContainerID, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame (+27 more)

### Community 9 - "VectorCanvas"
Cohesion: 0.08
Nodes (38): CodableColor, .uiColor, image, kind, Kind, fill, image, stroke (+30 more)

### Community 10 - "AlphaMask"
Cohesion: 0.08
Nodes (11): AlphaMask, .isActive, Bool, Int, MaskParityLogicTests, .side, Bool, CanvasManager (+3 more)

### Community 11 - "Coordinator"
Cohesion: 0.07
Nodes (22): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, NSCoder, Coordinator, .sandwichPresentation (+14 more)

### Community 12 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 13 - "ParityScenario"
Cohesion: 0.09
Nodes (34): CustomStringConvertible, UUID, Backdrop, fill, image, none, Gesture, diagonalCut (+26 more)

### Community 14 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (38): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+30 more)

### Community 15 - "Codable"
Cohesion: 0.05
Nodes (46): Codable, Kind, folder, layer, CodingKeys, amount, angleDegrees, brightness (+38 more)

### Community 16 - "UIKit"
Cohesion: 0.06
Nodes (11): CoreGraphics, Darwin, Foundation, LayerTransform, Notification.Name, AppVersion, .versionString, String (+3 more)

### Community 17 - "AnimationTimeline"
Cohesion: 0.05
Nodes (46): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+38 more)

### Community 18 - "EffectMultiPassLogicTests"
Cohesion: 0.11
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 19 - ".drawLine"
Cohesion: 0.12
Nodes (11): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement (+3 more)

### Community 20 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+13 more)

### Community 21 - "CGFloat"
Cohesion: 0.15
Nodes (12): Brush, CGFloat, VectorSample, Sweep, Bool, CGRect, ClosedRange, Double (+4 more)

### Community 22 - "SandwichLogicTests"
Cohesion: 0.11
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 23 - "Effect"
Cohesion: 0.10
Nodes (41): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+33 more)

### Community 24 - "MetalFillEngine"
Cohesion: 0.08
Nodes (30): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, EffectPipelines, MetalEffectEngine, Bool (+22 more)

### Community 25 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (22): StrokeInput, TimeInterval, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster, .vectorCanvas (+14 more)

### Community 26 - "PointCloudIndex"
Cohesion: 0.14
Nodes (16): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+8 more)

### Community 27 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 28 - "SaveSnapshot"
Cohesion: 0.08
Nodes (30): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+22 more)

### Community 29 - "PaintUITestCase"
Cohesion: 0.11
Nodes (10): PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests, TimelineGestureUITests, UndoAndLayerHistoryUITests (+2 more)

### Community 30 - "ShapeOverlayView"
Cohesion: 0.07
Nodes (30): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+22 more)

### Community 31 - ".apply"
Cohesion: 0.13
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 32 - "ValueLayerLogicTests"
Cohesion: 0.11
Nodes (10): CGImage, CGRect, UInt8, CanvasManager, CGImage, Int, UIColor, UIImage (+2 more)

### Community 33 - "BrushEngineLogicTests"
Cohesion: 0.15
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 34 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (7): Intersection, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 35 - "CanvasManager"
Cohesion: 0.11
Nodes (19): String, UUID, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move (+11 more)

### Community 36 - "View"
Cohesion: 0.13
Nodes (31): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+23 more)

### Community 37 - "InterpolationRenderLogicTests"
Cohesion: 0.14
Nodes (14): StrokeComposite, erase, paint, fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor (+6 more)

### Community 38 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 39 - "ProjectSaveLogicTests"
Cohesion: 0.16
Nodes (10): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+2 more)

### Community 40 - ".launchIntoEditor"
Cohesion: 0.18
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 41 - "PerfBaselineTests"
Cohesion: 0.17
Nodes (8): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 42 - ".transparentFormat"
Cohesion: 0.13
Nodes (18): IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath, CGRect (+10 more)

### Community 43 - "StrokeSettingsPanel"
Cohesion: 0.08
Nodes (33): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+25 more)

### Community 44 - "BrushBlendMode"
Cohesion: 0.07
Nodes (26): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+18 more)

### Community 45 - "ARAPLogicTests"
Cohesion: 0.13
Nodes (7): ARAPInterpolation, ARAPLogicTests, .rigidMotionL, Int, StaticString, String, UInt

### Community 46 - ".rows"
Cohesion: 0.12
Nodes (27): Gradient, stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all (+19 more)

### Community 47 - "String"
Cohesion: 0.08
Nodes (31): CodingKeys, brush, color, composite, elements, fill, fills, id (+23 more)

### Community 48 - "WindowEventTap"
Cohesion: 0.15
Nodes (18): AnyClass, NSObject, ObjectiveC.runtime, FoundElement, InstallReport, ResolvedTarget, Bool, CGRect (+10 more)

### Community 49 - ".evaluate"
Cohesion: 0.12
Nodes (20): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, InterpolationEvaluator (+12 more)

### Community 50 - "CGPoint"
Cohesion: 0.14
Nodes (12): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+4 more)

### Community 51 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 52 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 53 - "LayerManifest"
Cohesion: 0.14
Nodes (22): LayerKind, raster, value, vector, K, KeyedDecodingContainer, CelManifest, CodableColor (+14 more)

### Community 54 - "DeformFactorization"
Cohesion: 0.11
Nodes (17): Accelerate, Interpolator, Options, Bool, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2 (+9 more)

### Community 55 - "DrawingView"
Cohesion: 0.07
Nodes (25): Alignment, ActionRecorderIndicator, .body, DrawingView, .body, .panelAlignment, Bool, CanvasManager (+17 more)

### Community 56 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 57 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 58 - ".encode"
Cohesion: 0.17
Nodes (18): BlendMode, .shaderCode, CompositorMetalEngine, MetalCompositor, ScratchTexturePool, Bool, CGImage, Double (+10 more)

### Community 59 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 60 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 61 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 62 - "InterpolationRecipe"
Cohesion: 0.16
Nodes (11): InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve, Bool (+3 more)

### Community 63 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 64 - "ValueFill"
Cohesion: 0.07
Nodes (28): CodingKey, CodingKeys, id, invert, isEnabled, kind, sources, CodingKeys (+20 more)

### Community 65 - ".group"
Cohesion: 0.12
Nodes (14): Group, MotionGrouping, Options, Bool, Int, Set, CodingKeys, groups (+6 more)

### Community 66 - "StrokeGeometry"
Cohesion: 0.15
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 67 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 68 - ".withStructureUndo"
Cohesion: 0.14
Nodes (13): BlendMode, UUID, Void, LayerFolder, .compositorOp, .isCompositorNode, .maxInputCount, BlendMode (+5 more)

### Community 69 - "RenderRequest"
Cohesion: 0.14
Nodes (20): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, SandwichRequests, Bool (+12 more)

### Community 70 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 71 - "LayerStackCell"
Cohesion: 0.10
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 72 - "EffectParityLogicTests"
Cohesion: 0.16
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 73 - "SwiftUI"
Cohesion: 0.09
Nodes (15): Combine, CodableColor, .color, Color, .codable, CodableColor, .interpolateButton, InterpolatePanel (+7 more)

### Community 74 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 75 - "CanvasManager"
Cohesion: 0.12
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 76 - "MaskSource"
Cohesion: 0.13
Nodes (13): MaskSource, folder, .id, layer, Decoder, Encoder, UUID, Void (+5 more)

### Community 77 - "GuideOverlayView"
Cohesion: 0.14
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 78 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (13): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+5 more)

### Community 79 - ".activeCelIndex"
Cohesion: 0.17
Nodes (7): .interpolationTarget, CanvasManager, Bool, Int, CopiedCel, Int, UIImage

### Community 80 - "CodingKeys"
Cohesion: 0.07
Nodes (28): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, compositorRole (+20 more)

### Community 81 - "RenderNode"
Cohesion: 0.10
Nodes (25): Arity, fixed, variadic, Array, .leafLayerIndices, .needsCompositorOnCanvas, CompositorOp, .arity (+17 more)

### Community 82 - "OnionSkinLogicTests"
Cohesion: 0.13
Nodes (14): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGSize, UIColor, UIImage, OnionSkinLogicTests (+6 more)

### Community 83 - "GuideStroke"
Cohesion: 0.12
Nodes (17): Hashable, CodingKeys, boundGroups, id, interval, role, samples, GuideRole (+9 more)

### Community 84 - ".stampStroke"
Cohesion: 0.15
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 85 - "CanvasManager"
Cohesion: 0.12
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 86 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 88 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 89 - "TransformMode"
Cohesion: 0.09
Nodes (20): CaseIterable, Kind, line, oval, rectangle, SelectionMode, automatic, .displayName (+12 more)

### Community 90 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 91 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 92 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 93 - "Compositor.swift"
Cohesion: 0.19
Nodes (19): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+11 more)

### Community 94 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 95 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 96 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 97 - "ActionsMenu"
Cohesion: 0.12
Nodes (17): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+9 more)

### Community 98 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 100 - "InterpolationRefusal"
Cohesion: 0.14
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 101 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

### Community 102 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 103 - "CanvasNotice"
Cohesion: 0.11
Nodes (16): Kind, CanvasNotice, .actionTitle, .duration, .message, Kind, hiddenLayer, noDrawingSurface (+8 more)

### Community 104 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 105 - ".setUpGestures"
Cohesion: 0.15
Nodes (11): Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView, Void, TouchTypePressRecognizer (+3 more)

### Community 106 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 107 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 108 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 109 - ".makeUIView"
Cohesion: 0.14
Nodes (6): CanvasView, CanvasManager, Context, Coordinator, LayerTransform, UIImageView

### Community 110 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+6 more)

### Community 111 - ".coverage"
Cohesion: 0.29
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 112 - "ViewPreset"
Cohesion: 0.16
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 113 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 114 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 115 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 116 - "VectorEraserMode"
Cohesion: 0.12
Nodes (16): Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode, cutPoints (+8 more)

### Community 117 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 118 - "LayerRowModel"
Cohesion: 0.15
Nodes (13): UIColor, Kind, compositorNode, group, layer, LayerRowModel, .folderID, .isFolder (+5 more)

### Community 119 - "CanvasTransformFreezeUITests"
Cohesion: 0.29
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 120 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 121 - "Layer Compositing"
Cohesion: 0.12
Nodes (16): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 5.1 GPU, via Metal, 5.2 The sandwich, 5.3 Performance (+8 more)

### Community 122 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 123 - ".draw"
Cohesion: 0.34
Nodes (8): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, UIGraphicsImageRendererContext

### Community 124 - ".registerGroups"
Cohesion: 0.24
Nodes (3): GroupRegistration, RegistrationElement, RegistrationFrame

### Community 125 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 126 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 127 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 128 - "CompositorRole"
Cohesion: 0.13
Nodes (11): CodingKeys, kind, mixMode, op, CompositorRole, node, Decoder, Encoder (+3 more)

### Community 129 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 130 - "TouchCountRecognizer"
Cohesion: 0.21
Nodes (9): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+1 more)

### Community 131 - "Coordinator"
Cohesion: 0.30
Nodes (6): Coordinator, CanvasManager, Int, Set, UUID, UITableViewDiffableDataSource

### Community 132 - "LayerStackListView"
Cohesion: 0.16
Nodes (9): IndexPath, .body, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView (+1 more)

### Community 133 - "Cel"
Cohesion: 0.27
Nodes (8): CGSize, Layer, String, Cel, .endFrame, Int, UIImage, UUID

### Community 134 - "Kind"
Cohesion: 0.14
Nodes (14): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+6 more)

### Community 135 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 136 - "StrokeGestureRecognizer"
Cohesion: 0.34
Nodes (7): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, UIGestureRecognizer

### Community 137 - "Known Issues"
Cohesion: 0.15
Nodes (13): A green backend-parity test does not prove both backends ran (2026-08-15), A mask sourced from a graded group can be stale (2026-08-15), Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed (+5 more)

### Community 138 - "String"
Cohesion: 0.31
Nodes (6): Entry, ObjectIdentifier, Set, String, UIGestureRecognizer, UIView

### Community 139 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 140 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 141 - "MotionGroup"
Cohesion: 0.21
Nodes (9): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+1 more)

### Community 142 - "StructureSnapshot"
Cohesion: 0.26
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 143 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 144 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 145 - "LayerStackListView.Coordinator"
Cohesion: 0.27
Nodes (6): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 147 - ".handleReorderDrag"
Cohesion: 0.27
Nodes (3): CGRect, UILongPressGestureRecognizer, UIPinchGestureRecognizer

### Community 148 - ".row"
Cohesion: 0.29
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 149 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 150 - "Usage Guide"
Cohesion: 0.22
Nodes (9): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide (+1 more)

### Community 151 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 153 - "Multi-Session Protocol"
Cohesion: 0.25
Nodes (8): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Why the full run costs what it does

### Community 154 - "Next session — the layer-compositing project, after the phase 9 close-out"
Cohesion: 0.25
Nodes (8): Before you run out of context, Machine and delegation discipline, Next session — the layer-compositing project, after the phase 9 close-out, Owner decisions — settled, do not re-ask, Still open, The two hazards this project keeps paying for, What shipped this session, Where verification stands

### Community 155 - ".setCanvasPadding"
Cohesion: 0.36
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 156 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 157 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 158 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 159 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 160 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 161 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 163 - "4. The render tree"
Cohesion: 0.33
Nodes (6): 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes, 4.4 Effects are both a layer and a node, 4.5 Value layers, 4. The render tree

### Community 164 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 165 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 167 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 168 - "DabLattice"
Cohesion: 0.60
Nodes (3): DabLattice, .range, ClosedRange

### Community 169 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 170 - "SandwichPresentation"
Cohesion: 0.50
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

## Knowledge Gaps
- **680 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+675 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `Lattice`, `ShapeGeometry`, `Coordinator`, `CompositorParityLogicTests`, `layers`, `CanvasManager`, `VectorCanvas`, `AlphaMask`, `Coordinator`, `EffectLayerLogicTests`, `ParityScenario`, `UIKit`, `AnimationTimeline`, `SandwichLogicTests`, `StrokeCanvasView`, `PointCloudIndex`, `VectorEraserLogicTests`, `PaintUITestCase`, `ShapeOverlayView`, `.apply`, `BrushEngineLogicTests`, `StrokeGeometryLogicTests`, `CanvasManager`, `InterpolationRenderLogicTests`, `ProjectSaveLogicTests`, `.launchIntoEditor`, `PerfBaselineTests`, `.transparentFormat`, `StrokeSettingsPanel`, `BrushBlendMode`, `ARAPLogicTests`, `.rows`, `String`, `WindowEventTap`, `.evaluate`, `CGPoint`, `VectorEraserHybridLogicTests`, `RasterLayerTexture`, `DeformFactorization`, `DrawingView`, `ActionRecorder`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `.group`, `StrokeGeometry`, `StrokeSpatialIndex`, `LayerStackCell`, `CanvasManager`, `GuideOverlayView`, `FloatingPieceOverlayView`, `OnionSkinLogicTests`, `.stampStroke`, `CanvasManager`, `InterpolationGuideLogicTests`, `XCUIApplication`, `TransformMode`, `CanvasManager`, `CurveEditor`, `ActionsMenu`, `.indices`, `ObjectTransformOverlayView`, `.manager`, `SandwichCompositingUITests`, `InterpolateBar`, `.arched`, `TimedSample`, `VectorEraserMode`, `LayerRowModel`, `CanvasTransformFreezeUITests`, `DabTarget`, `.draw`, `.registerGroups`, `SideToolbar`, `Coordinator`, `LayerStackListView`, `GuidePath`, `SpacingChart`, `StrokeStabilizer`, `TransformOverlaySupport.swift`, `.setCanvasPadding`, `JSONValue`, `Kind`, `DabLattice`?**
  _High betweenness centrality (0.340) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `Lattice`, `ShapeGeometry`, `Coordinator`, `layers`, `CanvasManager`, `VectorCanvas`, `AlphaMask`, `GuidePath`, `Coordinator`, `ParityScenario`, `ColorPickerPanel`, `StrokeStabilizer`, `UIKit`, `AnimationTimeline`, `LayerStackListView.Coordinator`, `.rasterize`, `CGFloat`, `TransformOverlaySupport.swift`, `StrokeCanvasView`, `PointCloudIndex`, `VectorEraserLogicTests`, `.setCanvasPadding`, `ShapeOverlayView`, `BrushEngineLogicTests`, `StrokeGeometryLogicTests`, `CanvasManager`, `InterpolationRenderLogicTests`, `ProjectSaveLogicTests`, `PerfBaselineTests`, `.transparentFormat`, `BrushBlendMode`, `ARAPLogicTests`, `WindowEventTap`, `.evaluate`, `VectorEraserHybridLogicTests`, `RasterLayerTexture`, `DeformFactorization`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `.group`, `StrokeGeometry`, `StrokeSpatialIndex`, `CanvasManager`, `GuideOverlayView`, `FloatingPieceOverlayView`, `.activeCelIndex`, `.stampStroke`, `CanvasManager`, `InterpolationGuideLogicTests`, `TransformMode`, `CurveEditor`, `.indices`, `ObjectTransformOverlayView`, `SelectionOverlayView`, `.setUpGestures`, `.manager`, `.makeUIView`, `.arched`, `TimedSample`, `DabTarget`, `.registerGroups`?**
  _High betweenness centrality (0.149) - this node is a cross-community bridge._
- **Why does `task` connect `ContentView` to `DrawingView`, `bash`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._