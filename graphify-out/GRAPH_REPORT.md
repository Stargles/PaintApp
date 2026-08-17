# Graph Report - PaintApp-docs  (2026-08-16)

## Corpus Check
- 179 files · ~489,624 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 5285 nodes · 16325 edges · 165 communities (153 shown, 12 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 1733 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `020da583`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- ShapeGeometry
- CanvasManager
- .manager
- CGPoint
- Coordinator
- AlphaMask
- CompositorParityLogicTests
- cels
- CanvasManager
- VectorCanvas
- EffectLayerLogicTests
- UIKit
- Lattice
- AnimationTimeline
- PointCloudIndex
- StrokeCanvasView
- ColorPickerPanel
- EffectMultiPassLogicTests
- .report
- SandwichLogicTests
- ARAPLogicTests
- StrokeGeometryLogicTests
- PaintUITestCase
- RasterLayerTexture
- .drawLine
- CodingKeys
- VectorEraserLogicTests
- .setUpGestures
- .solidImage
- ShapeOverlayView
- CanvasManager
- .transparentFormat
- BackupManagerLogicTests
- View
- CanvasManager
- BrushEngineLogicTests
- VectorSample
- layers
- ProjectSaveLogicTests
- LayerTreeCharacterizationTests
- PerfBaselineTests
- CanvasNotice
- BrushStamper
- ProjectBackupManager
- Brush
- .launchIntoEditor
- InterpolationRenderLogicTests
- Coordinator
- VectorEraserHybridLogicTests
- CGFloat
- LayerRowModel
- CanvasManager
- ResolvedMask
- CodingKeys
- .evaluate
- LayerStackCell
- WindowEventTap
- Coordinator
- agent
- ActionRecorder
- PlaybackBoundsCharacterizationTests
- Composite.metal
- InterpolationRecipe
- StrokeSettingsPanel
- StrokeGestureRecognizer
- Codable
- GuideOverlayView
- .rows
- BlendMode
- EffectParityLogicTests
- FillParams
- StrokeSpatialIndex
- .encode
- SaveSnapshot
- OnionSkinLogicTests
- .apply
- StrokeSampleGateLogicTests
- CGContextDabTarget
- TouchCountRecognizer
- InterpolationEngineDiagnosticsLogicTests
- MaskSource
- .attach
- CodingKeys
- .rasterize
- SwiftUI
- ObjectTransformOverlayView
- Effect
- 4. The render tree
- ActionsMenu
- VectorScratchRole
- .encode
- SandwichPresentation
- GuideStroke
- ActivePanel
- XCUIApplication
- LayerStackListView.Coordinator
- FloatingPieceOverlayView
- RenderRequest
- MaskGuardLogicTests
- GuideRow
- Gesture
- read
- Compositor.swift
- CanvasManager
- CurveEditor
- ContentView
- .init
- SelectionOverlayView
- BlockDragCharacterizationTests
- SandwichCompositingUITests
- PerfMonitor
- EffectParams
- Kind
- InterpolationGuideLogicTests
- CodingKey
- RenderNode
- Layer
- ProjectSummary
- Layer Compositing
- InterpolateBar
- CanvasSizePickerView
- CanvasTransformFreezeUITests
- Recording
- SideToolbar
- Is the brush engine ready for `.ABR` / Procreate brush import?
- bash
- UndoHistory
- String
- CanvasHostView
- Known Issues
- GuidePath
- SpacingChart
- StructureSnapshot
- StrokeStabilizer
- CanvasManager
- SelectPanel
- 4. Future upgrades — the deferred list
- Foundation
- .group
- .row
- Multi-Session Protocol
- TransformOverlaySupport.swift
- Usage Guide
- PaintSoftware - iPad Drawing and Animation App
- CLAUDE.md
- RecordingWriter
- 6. Alpha masks
- command
- JSONValue
- Kind
- ManifestSkeleton
- Atomic
- ToolPanelsUITests
- parallel_test.sh
- Performance baseline
- Kind
- simlock.sh
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 557 edges
2. `CGFloat` - 435 edges
3. `Effect` - 143 edges
4. `CanvasManager` - 139 edges
5. `VectorCanvas` - 123 edges
6. `layers` - 118 edges
7. `VectorSample` - 110 edges
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

## Communities (165 total, 12 thin omitted)

### Community 0 - "ShapeGeometry"
Cohesion: 0.04
Nodes (34): ClosedFit, ShapeDetector, Bool, CGRect, Int, Corner, bottomLeft, bottomRight (+26 more)

### Community 1 - "CanvasManager"
Cohesion: 0.04
Nodes (63): Void, CanvasManager, .activeContainerID, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame (+55 more)

### Community 2 - ".manager"
Cohesion: 0.07
Nodes (9): CanvasFixture, CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int, Bool, CanvasManager (+1 more)

### Community 3 - "CGPoint"
Cohesion: 0.12
Nodes (8): CGPoint, .length, LatticeLogicTests, Int, StaticString, String, UInt, .samples

### Community 4 - "Coordinator"
Cohesion: 0.06
Nodes (46): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, MenuRequest, block (+38 more)

### Community 5 - "AlphaMask"
Cohesion: 0.08
Nodes (11): AlphaMask, .isActive, Bool, Int, MaskParityLogicTests, .side, Bool, CanvasManager (+3 more)

### Community 6 - "CompositorParityLogicTests"
Cohesion: 0.08
Nodes (12): CompositorParityLogicTests, BlendMode, Bool, CanvasManager, CGImage, Int, StaticString, String (+4 more)

### Community 7 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 8 - "CanvasManager"
Cohesion: 0.05
Nodes (41): CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+33 more)

### Community 9 - "VectorCanvas"
Cohesion: 0.06
Nodes (54): Identifiable, CodableColor, .uiColor, kind, DabLattice, .range, ElementData, fill (+46 more)

### Community 10 - "EffectLayerLogicTests"
Cohesion: 0.10
Nodes (10): EffectLayerLogicTests, .side, CanvasManager, CGImage, Int, String, UIColor, UIImage (+2 more)

### Community 11 - "UIKit"
Cohesion: 0.08
Nodes (5): CoreGraphics, Darwin, ThumbnailRenderer, UIKit, XCTest

### Community 12 - "Lattice"
Cohesion: 0.10
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 13 - "AnimationTimeline"
Cohesion: 0.05
Nodes (49): FolderKind, compositorNode, group, LayerStackRow, .depth, folder, .folderID, .folderKind (+41 more)

### Community 14 - "PointCloudIndex"
Cohesion: 0.10
Nodes (17): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+9 more)

### Community 15 - "StrokeCanvasView"
Cohesion: 0.10
Nodes (23): StrokeInput, TimeInterval, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing, .raster (+15 more)

### Community 16 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (38): Int, Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette (+30 more)

### Community 17 - "EffectMultiPassLogicTests"
Cohesion: 0.13
Nodes (6): EffectMultiPassLogicTests, Double, Int, SIMD4, String, UInt8

### Community 18 - ".report"
Cohesion: 0.10
Nodes (32): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+24 more)

### Community 19 - "SandwichLogicTests"
Cohesion: 0.11
Nodes (7): Battery, SandwichLogicTests, BlendMode, CanvasManager, CGImage, Int, String

### Community 20 - "ARAPLogicTests"
Cohesion: 0.13
Nodes (9): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, Int, StaticString, String (+1 more)

### Community 21 - "StrokeGeometryLogicTests"
Cohesion: 0.06
Nodes (14): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, StrokeGeometryLogicTests (+6 more)

### Community 22 - "PaintUITestCase"
Cohesion: 0.11
Nodes (10): PaintUITestCase, Bool, Int, String, XCUIApplication, InterpolationWorkflowUITests, TimelineGestureUITests, UndoAndLayerHistoryUITests (+2 more)

### Community 23 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (12): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+4 more)

### Community 24 - ".drawLine"
Cohesion: 0.12
Nodes (11): FillContainmentUITests, FillLiveAdjustUITests, FillUndoRedoUITests, CGVector, Double, TimeInterval, UInt8, XCUIElement (+3 more)

### Community 25 - "CodingKeys"
Cohesion: 0.05
Nodes (45): CodingKeys, amount, angleDegrees, brightness, color, contrast, gamma, hueDegrees (+37 more)

### Community 26 - "VectorEraserLogicTests"
Cohesion: 0.13
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 27 - ".setUpGestures"
Cohesion: 0.10
Nodes (13): .sandwichPresentation, CGSize, Set, UIEvent, UIPanGestureRecognizer, UIPinchGestureRecognizer, UITouch, UIView (+5 more)

### Community 28 - ".solidImage"
Cohesion: 0.09
Nodes (13): CGImage, CGRect, CGSize, UIColor, UIImage, UInt8, CanvasManager, CGImage (+5 more)

### Community 29 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind, axisBottom (+21 more)

### Community 30 - "CanvasManager"
Cohesion: 0.06
Nodes (39): CanvasManager, Bool, CGSize, UIImage, String, UUID, Void, CanvasManager (+31 more)

### Community 31 - ".transparentFormat"
Cohesion: 0.13
Nodes (18): IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath, CGRect (+10 more)

### Community 32 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 33 - "View"
Cohesion: 0.12
Nodes (32): .layerPanelRail, blendModeRow(), effectSettingsRow(), FolderOptionsPanel, .body, .folder, .folderIndex, LayerOptionsPanel (+24 more)

### Community 34 - "CanvasManager"
Cohesion: 0.13
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 35 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 36 - "VectorSample"
Cohesion: 0.12
Nodes (14): VectorSample, .point, CutOutcome, cut, missed, unchanged, IntersectionDriver, Sweep (+6 more)

### Community 37 - "layers"
Cohesion: 0.13
Nodes (14): .activeLayerIsVector, .activeCelIsInBetween, CanvasManager, Bool, Int, Cel, .endFrame, Int (+6 more)

### Community 38 - "ProjectSaveLogicTests"
Cohesion: 0.15
Nodes (10): ProjectSaveLogicTests, Bool, CanvasManager, Cel, Set, StaticString, String, UInt (+2 more)

### Community 39 - "LayerTreeCharacterizationTests"
Cohesion: 0.06
Nodes (15): Layer, StaticString, String, UInt, UUID, XCTestCase, LayerTreeCharacterizationTests, CanvasManager (+7 more)

### Community 40 - "PerfBaselineTests"
Cohesion: 0.16
Nodes (9): PerfBaselineTests, Bool, CanvasManager, Double, Int, String, UIImage, UInt64 (+1 more)

### Community 41 - "CanvasNotice"
Cohesion: 0.06
Nodes (26): Alignment, Kind, CanvasNotice, .actionTitle, .duration, .message, Kind, hiddenLayer (+18 more)

### Community 42 - "BrushStamper"
Cohesion: 0.14
Nodes (14): AnyObject, BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange (+6 more)

### Community 43 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory, .projectsDirectory (+13 more)

### Community 44 - "Brush"
Cohesion: 0.05
Nodes (41): CaseIterable, Brush, BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply (+33 more)

### Community 45 - ".launchIntoEditor"
Cohesion: 0.18
Nodes (3): BlendModesAndCompositorUITests, LayerPanelUITests, XCUIApplication

### Community 46 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 47 - "Coordinator"
Cohesion: 0.20
Nodes (10): Coordinator, LayerStackListView, CanvasManager, Coordinator, Int, Set, UUID, Void (+2 more)

### Community 48 - "VectorEraserHybridLogicTests"
Cohesion: 0.12
Nodes (16): StrokeComposite, erase, paint, Gesture, diagonalCut, edgeShave, .label, .samples (+8 more)

### Community 49 - "CGFloat"
Cohesion: 0.05
Nodes (28): Accelerate, bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, DeformDataRow (+20 more)

### Community 50 - "LayerRowModel"
Cohesion: 0.15
Nodes (11): UIColor, LayerRowModel, .folderID, .isFolder, .maskSource, BlendMode, Bool, Double (+3 more)

### Community 51 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 52 - "ResolvedMask"
Cohesion: 0.29
Nodes (7): CacheKey, MaskCache, MaskResolver, ResolvedMask, CGImage, Int, UInt8

### Community 53 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 54 - ".evaluate"
Cohesion: 0.11
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 55 - "LayerStackCell"
Cohesion: 0.10
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 56 - "WindowEventTap"
Cohesion: 0.15
Nodes (18): AnyClass, NSObject, ObjectiveC.runtime, FoundElement, InstallReport, ResolvedTarget, Bool, CGRect (+10 more)

### Community 57 - "Coordinator"
Cohesion: 0.06
Nodes (28): LayerHostView, .maskedContentViews, Bool, CALayer, CGImage, AppliedTool, CanvasView, Coordinator (+20 more)

### Community 58 - "agent"
Cohesion: 0.06
Nodes (33): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+25 more)

### Community 59 - "ActionRecorder"
Cohesion: 0.16
Nodes (12): ActionRecorder, .directory, .now, CFTimeInterval, CGSize, Double, ObjectIdentifier, String (+4 more)

### Community 60 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 61 - "Composite.metal"
Cohesion: 0.21
Nodes (32): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+24 more)

### Community 62 - "InterpolationRecipe"
Cohesion: 0.07
Nodes (22): CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve (+14 more)

### Community 63 - "StrokeSettingsPanel"
Cohesion: 0.10
Nodes (26): Accessory, KeyPath, BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem (+18 more)

### Community 64 - "StrokeGestureRecognizer"
Cohesion: 0.34
Nodes (7): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, UIGestureRecognizer

### Community 65 - "Codable"
Cohesion: 0.10
Nodes (31): Codable, Decoder, ValueFill, CompositorRole, node, Decoder, Encoder, K (+23 more)

### Community 66 - "GuideOverlayView"
Cohesion: 0.13
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGRect (+8 more)

### Community 67 - ".rows"
Cohesion: 0.12
Nodes (27): Gradient, stops, CodableColor, .color, Color, .effectColor, EffectCatalog, .all (+19 more)

### Community 68 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 69 - "EffectParityLogicTests"
Cohesion: 0.20
Nodes (4): EffectParityLogicTests, Int, String, UInt8

### Community 70 - "FillParams"
Cohesion: 0.18
Nodes (29): device, float2, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor (+21 more)

### Community 71 - "StrokeSpatialIndex"
Cohesion: 0.13
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 72 - ".encode"
Cohesion: 0.06
Nodes (48): Metal, MTLBuffer, MTLCommandBuffer, MTLLibrary, MTLTextureUsage, BlendMode, .shaderCode, CompositorMetalEngine (+40 more)

### Community 73 - "SaveSnapshot"
Cohesion: 0.15
Nodes (17): CelContent, LayerContent, ProjectStore, .projectsDirectory, SaveSnapshot, BlendMode, Bool, CanvasManager (+9 more)

### Community 74 - "OnionSkinLogicTests"
Cohesion: 0.13
Nodes (14): OnionSkinFrame, OnionSkinSource, PreviousCelOnionSkinSource, CanvasManager, CGSize, UIColor, UIImage, OnionSkinLogicTests (+6 more)

### Community 75 - ".apply"
Cohesion: 0.12
Nodes (20): EffectParams, EffectReference, CGImage, Float, Int, SIMD4, UInt32, UInt8 (+12 more)

### Community 76 - "StrokeSampleGateLogicTests"
Cohesion: 0.17
Nodes (4): CountingDabTarget, StrokeSampleGateLogicTests, UInt64, Tremor

### Community 77 - "CGContextDabTarget"
Cohesion: 0.27
Nodes (7): CGGradient, CGContextDabTarget, DabGradientCache, Key, CGBlendMode, CGContext, UIColor

### Community 78 - "TouchCountRecognizer"
Cohesion: 0.21
Nodes (9): Any, Int, Set, UIEvent, UITouch, Void, TouchCountRecognizer, .activeCount (+1 more)

### Community 79 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.30
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 80 - "MaskSource"
Cohesion: 0.07
Nodes (30): Kind, folder, layer, MaskSource, folder, .id, layer, Decoder (+22 more)

### Community 81 - ".attach"
Cohesion: 0.23
Nodes (5): IndexPath, Context, UIPinchGestureRecognizer, UISwipeActionsConfiguration, UITableView

### Community 82 - "CodingKeys"
Cohesion: 0.06
Nodes (36): GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder, UUID (+28 more)

### Community 84 - "SwiftUI"
Cohesion: 0.08
Nodes (15): Combine, .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager, MoveTransformBottomBar (+7 more)

### Community 85 - "ObjectTransformOverlayView"
Cohesion: 0.17
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

### Community 86 - "Effect"
Cohesion: 0.09
Nodes (32): Equatable, Bloom, Blur, BrightnessContrast, ChromaticAberration, value, Curves, Effect (+24 more)

### Community 87 - "4. The render tree"
Cohesion: 0.33
Nodes (6): 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes, 4.4 Effects are both a layer and a node, 4.5 Value layers, 4. The render tree

### Community 88 - "ActionsMenu"
Cohesion: 0.10
Nodes (21): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+13 more)

### Community 89 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 91 - "SandwichPresentation"
Cohesion: 0.50
Nodes (4): SandwichPresentation, disengaged, midStroke, rest

### Community 92 - "GuideStroke"
Cohesion: 0.11
Nodes (18): Hashable, CelLocation, CodingKeys, boundGroups, id, interval, role, samples (+10 more)

### Community 93 - "ActivePanel"
Cohesion: 0.13
Nodes (17): ActivePanel, actions, brush, color, eraser, fill, layers, move (+9 more)

### Community 95 - "XCUIApplication"
Cohesion: 0.23
Nodes (9): CuttingModesUITests, Mode1UITests, ModePickerUITests, Int, String, XCUIApplication, XCUIElement, VectorEraserTestSupport (+1 more)

### Community 96 - "LayerStackListView.Coordinator"
Cohesion: 0.16
Nodes (10): DispatchWorkItem, DropTarget, between, onto, LayerStackListView.Coordinator, CGRect, TimeInterval, UILongPressGestureRecognizer (+2 more)

### Community 97 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 98 - "RenderRequest"
Cohesion: 0.14
Nodes (20): Hasher, CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, SandwichRequests, Bool (+12 more)

### Community 99 - "MaskGuardLogicTests"
Cohesion: 0.15
Nodes (8): .antialiasHalfWidth, .threshold, Float, MaskGuardLogicTests, ClosedRange, Float, Int, String

### Community 100 - "GuideRow"
Cohesion: 0.12
Nodes (16): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+8 more)

### Community 101 - "Gesture"
Cohesion: 0.13
Nodes (14): build_gestures(), element_expression(), emit_gesture(), emit_state_comments(), Gesture, main(), normalized_expression(), parse() (+6 more)

### Community 102 - "read"
Cohesion: 0.37
Nodes (22): read, applyEffect(), bloomCombine(), bloomThreshold(), blur1D(), chromaticAberration(), compositeEffectMix(), compositeFill() (+14 more)

### Community 103 - "Compositor.swift"
Cohesion: 0.19
Nodes (19): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+11 more)

### Community 104 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 105 - "CurveEditor"
Cohesion: 0.21
Nodes (11): CurvePoint, MonotoneCubic, CurveEditor, .body, .curvePath, .dragGesture, .grid, .handles (+3 more)

### Community 106 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 109 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 110 - "BlockDragCharacterizationTests"
Cohesion: 0.23
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 111 - "SandwichCompositingUITests"
Cohesion: 0.26
Nodes (9): SandwichCompositingUITests, .crossing, Bool, CGVector, Int, String, TimeInterval, UInt8 (+1 more)

### Community 112 - "PerfMonitor"
Cohesion: 0.14
Nodes (15): CADisplayLink, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount, PerfMonitor (+7 more)

### Community 113 - "EffectParams"
Cohesion: 0.10
Nodes (20): EffectParams, amount, brightness, colorB, colorG, colorR, contrast, hueTurns (+12 more)

### Community 114 - "Kind"
Cohesion: 0.10
Nodes (20): Kind, bloom, blur, brightnessContrast, chromaticAberration, curves, gradientMap, hsvShift (+12 more)

### Community 115 - "InterpolationGuideLogicTests"
Cohesion: 0.10
Nodes (11): GuideSet, .isEmpty, Bool, TimedSample, .point, InterpolationGuideLogicTests, CanvasManager, Cel (+3 more)

### Community 116 - "CodingKey"
Cohesion: 0.06
Nodes (34): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+26 more)

### Community 117 - "RenderNode"
Cohesion: 0.20
Nodes (15): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, RenderNode (+7 more)

### Community 118 - "Layer"
Cohesion: 0.17
Nodes (11): Layer, .hasNoDrawingSurface, .isFillReference, .layerEffect, .valueFill, BlendMode, Bool, Cel (+3 more)

### Community 120 - "ProjectSummary"
Cohesion: 0.15
Nodes (13): ProjectSummary, Date, ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body (+5 more)

### Community 121 - "Layer Compositing"
Cohesion: 0.12
Nodes (16): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 5.1 GPU, via Metal, 5.2 The sandwich, 5.3 Performance (+8 more)

### Community 123 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 126 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 127 - "CanvasTransformFreezeUITests"
Cohesion: 0.29
Nodes (6): CanvasTransformFreezeUITests, Int, String, XCUIApplication, XCUIElement, XCUICoordinate

### Community 128 - "Recording"
Cohesion: 0.17
Nodes (12): Recording, .id, .name, .sizeText, Date, Int, ActionRecorderSection, .body (+4 more)

### Community 129 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 130 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.13
Nodes (14): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled (+6 more)

### Community 131 - "bash"
Cohesion: 0.36
Nodes (15): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+7 more)

### Community 133 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 134 - "String"
Cohesion: 0.29
Nodes (6): Entry, ObjectIdentifier, Set, String, UIGestureRecognizer, UIView

### Community 135 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 137 - "Known Issues"
Cohesion: 0.14
Nodes (14): A green backend-parity test does not prove both backends ran (2026-08-15), A mask sourced from a graded group can be stale (2026-08-15), An interrupted stroke stubs, and no terminal callback runs (2026-08-16), Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues (+6 more)

### Community 138 - "GuidePath"
Cohesion: 0.25
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 139 - "SpacingChart"
Cohesion: 0.15
Nodes (5): GuideHandles, SpacingChart, .curve, .draggable, Int

### Community 140 - "StructureSnapshot"
Cohesion: 0.18
Nodes (6): CanvasManager, StructureSnapshot, Int, Layer, String, guideStrokes

### Community 141 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 142 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 143 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 144 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 145 - "Foundation"
Cohesion: 0.08
Nodes (15): Foundation, Tool, eraser, fill, pen, pencil, Notification.Name, CodableColor (+7 more)

### Community 146 - ".group"
Cohesion: 0.17
Nodes (7): Group, MotionGrouping, Options, Bool, Int, Set, groups

### Community 147 - ".row"
Cohesion: 0.29
Nodes (7): MaskTuningSection, .body, Binding, ClosedRange, Float, String, Void

### Community 148 - "Multi-Session Protocol"
Cohesion: 0.22
Nodes (9): Action recorder — get the bug off the owner's iPad instead of guessing at a simulator, Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change, Two branches can mint the same pbxproj object id, and git will merge them happily (+1 more)

### Community 150 - "TransformOverlaySupport.swift"
Cohesion: 0.18
Nodes (10): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+2 more)

### Community 151 - "Usage Guide"
Cohesion: 0.22
Nodes (9): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide (+1 more)

### Community 152 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 157 - "6. Alpha masks"
Cohesion: 0.29
Nodes (7): 6.1 Render-time, never baked — including raster, 6.2 Model, 6.3 Binary, with a threshold, 6.4 Live feedback while drawing, 6.5 UI, 6.6 Lifecycle, 6. Alpha masks

### Community 158 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 159 - "JSONValue"
Cohesion: 0.29
Nodes (7): JSONValue, bool, int, null, num, str, Bool

### Community 163 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 164 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 167 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 169 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 170 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 172 - "Kind"
Cohesion: 0.50
Nodes (4): Kind, compositorNode, group, layer

### Community 173 - "simlock.sh"
Cohesion: 0.83
Nodes (3): reap_stale(), release(), simlock.sh script

## Knowledge Gaps
- **679 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `.now` (+674 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **12 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `ShapeGeometry`, `CanvasManager`, `SideToolbar`, `CGPoint`, `Coordinator`, `AlphaMask`, `CompositorParityLogicTests`, `cels`, `CanvasManager`, `VectorCanvas`, `GuidePath`, `SpacingChart`, `Lattice`, `AnimationTimeline`, `PointCloudIndex`, `StrokeCanvasView`, `CanvasManager`, `StrokeStabilizer`, `.group`, `EffectLayerLogicTests`, `ARAPLogicTests`, `StrokeGeometryLogicTests`, `TransformOverlaySupport.swift`, `RasterLayerTexture`, `PaintUITestCase`, `.report`, `VectorEraserLogicTests`, `.setUpGestures`, `SandwichLogicTests`, `ShapeOverlayView`, `CanvasManager`, `JSONValue`, `.transparentFormat`, `BrushEngineLogicTests`, `VectorSample`, `Kind`, `ProjectSaveLogicTests`, `PerfBaselineTests`, `CanvasNotice`, `BrushStamper`, `Brush`, `.launchIntoEditor`, `InterpolationRenderLogicTests`, `Coordinator`, `VectorEraserHybridLogicTests`, `LayerRowModel`, `CanvasManager`, `CodingKeys`, `.evaluate`, `LayerStackCell`, `WindowEventTap`, `Coordinator`, `ActionRecorder`, `InterpolationRecipe`, `StrokeSettingsPanel`, `GuideOverlayView`, `.rows`, `StrokeSpatialIndex`, `OnionSkinLogicTests`, `.apply`, `StrokeSampleGateLogicTests`, `CGContextDabTarget`, `InterpolationEngineDiagnosticsLogicTests`, `.attach`, `ObjectTransformOverlayView`, `ActionsMenu`, `GuideStroke`, `.soleGuide`, `XCUIApplication`, `CanvasManager`, `CurveEditor`, `SandwichCompositingUITests`, `InterpolationGuideLogicTests`, `RenderNode`, `InterpolateBar`, `CanvasTransformFreezeUITests`?**
  _High betweenness centrality (0.306) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `ShapeGeometry`, `CanvasManager`, `Coordinator`, `AlphaMask`, `cels`, `CanvasManager`, `VectorCanvas`, `GuidePath`, `SpacingChart`, `Lattice`, `StrokeStabilizer`, `PointCloudIndex`, `StrokeCanvasView`, `CanvasManager`, `AnimationTimeline`, `.group`, `ColorPickerPanel`, `ARAPLogicTests`, `StrokeGeometryLogicTests`, `TransformOverlaySupport.swift`, `RasterLayerTexture`, `.report`, `VectorEraserLogicTests`, `.setUpGestures`, `ShapeOverlayView`, `CanvasManager`, `.transparentFormat`, `BrushEngineLogicTests`, `VectorSample`, `layers`, `ProjectSaveLogicTests`, `PerfBaselineTests`, `BrushStamper`, `Brush`, `InterpolationRenderLogicTests`, `VectorEraserHybridLogicTests`, `CGFloat`, `CanvasManager`, `.evaluate`, `WindowEventTap`, `Coordinator`, `InterpolationRecipe`, `GuideOverlayView`, `StrokeSpatialIndex`, `StrokeSampleGateLogicTests`, `CGContextDabTarget`, `InterpolationEngineDiagnosticsLogicTests`, `.rasterize`, `ObjectTransformOverlayView`, `GuideStroke`, `.soleGuide`, `LayerStackListView.Coordinator`, `FloatingPieceOverlayView`, `CurveEditor`, `SelectionOverlayView`, `InterpolationGuideLogicTests`?**
  _High betweenness centrality (0.156) - this node is a cross-community bridge._
- **Why does `task` connect `ContentView` to `CanvasNotice`, `bash`?**
  _High betweenness centrality (0.075) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 14 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `CanvasManager` (e.g. with `FillKey` and `UndoHistory`) actually correct?**
  _`CanvasManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._