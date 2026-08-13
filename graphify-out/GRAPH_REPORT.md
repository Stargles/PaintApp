# Graph Report - phase7-tier2  (2026-08-13)

## Corpus Check
- 161 files · ~342,345 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4269 nodes · 13095 edges · 163 communities (152 shown, 11 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1508 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `993b0461`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- .launchIntoEditor
- cels
- Coordinator
- CanvasManager
- Coordinator
- CanvasManager
- VectorCanvas
- CompositorParityLogicTests
- ParityScenario
- ProjectBackupManager
- .encode
- ColorPickerPanel
- .setCelLayout
- String
- CanvasManager
- Lattice
- PointCloudIndex
- StrokeGeometryLogicTests
- StrokeCanvasView
- VectorEraserLogicTests
- BrushEngineLogicTests
- CGPoint
- InterpolationRecipe
- CGFloat
- CanvasManager
- UIKit
- InterpolationRenderLogicTests
- SandwichLogicTests
- PerfBaselineTests
- .evaluate
- Brush
- CanvasManager
- ARAPLogicTests
- InterpolationEngineDiagnosticsLogicTests
- AnimationTimeline
- RasterLayerTexture
- VectorEraserHybridLogicTests
- StructureSnapshot
- ProjectManifest
- .load
- InterpolationModelLogicTests
- layers
- GuideOverlayView
- PlaybackBoundsCharacterizationTests
- StrokeSettingsPanel
- ShapeGeometry
- StrokeGeometry
- VectorSample
- LayerTreeCharacterizationTests
- FillParams
- Layer Compositing
- SaveSnapshot
- TouchCountRecognizer
- DeformFactorization
- FloatingPieceOverlayView
- RenderTreeCharacterizationTests
- ShapeDetectorLogicTests
- LayerOptionsPanel
- .stampStroke
- MaskParityLogicTests
- BackupManagerLogicTests
- LayerStackCell
- ActivePanel
- BlendMode
- .analyse
- .transparentFormat
- InterpolationGuideLogicTests
- RenderNode
- View
- ShapeOverlayView
- .manager
- CanvasManager
- MetalFillEngine
- ContentView
- Equatable
- LayerRowModel
- .indices
- InterpolationRefusal
- CodingKeys
- .solidImage
- ObjectTransformOverlayView
- SelectionOverlayView
- CanvasManager
- .manager
- Foundation
- Color
- ActionsMenu
- EraserSettingsPanel
- BlockDragCharacterizationTests
- PerfMonitor
- .draw
- InterpolateBar
- ProjectVersionsView
- DrawingView
- .arched
- RenderRequest
- ShapeDetector
- TimedSample
- .setUpGestures
- CanvasSizePickerView
- bash
- SideToolbar
- SwiftUI
- UndoHistory
- .stampCircle
- LayerStackListView
- agent
- CanvasHostView
- GuidePath
- SpacingChart
- XCTestCase
- Composite.metal
- StrokeStabilizer
- .withInterpolationUndo
- LayerStackRow
- SelectPanel
- 4. Future upgrades — the deferred list
- .coverage
- Is the brush engine ready for `.ABR` / Procreate brush import?
- ViewPreset
- Matrix2x2
- LayerStackListView.Coordinator
- You are the Orchestrator for the rest of the layer-compositing project
- Layer
- BrushBlendMode
- TransformOverlaySupport.swift
- PaintSoftware - iPad Drawing and Animation App
- .refreshUndoRedoState
- Usage Guide
- command
- compositeOver
- CutOutcome
- InterpolatePanel
- VectorEraserMode
- CLAUDE.md
- Known Issues
- Multi-Session Protocol
- ManifestSkeleton
- CodingKeys
- ProjectStore.swift
- VectorScratchRole
- Atomic
- What needs to change
- parallel_test.sh
- Compositor.swift
- .menuButton
- Edge
- Performance baseline
- BrushSettingsPanel
- SelectionMode
- CaseIterable
- Deterministic
- worker-test
- worker-ui
- cleanup_session.sh
- screenshot.sh
- SandwichPresentation
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- .bytes

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 536 edges
2. `CGFloat` - 409 edges
3. `VectorCanvas` - 123 edges
4. `layers` - 114 edges
5. `CanvasManager` - 105 edges
6. `CanvasManager` - 100 edges
7. `VectorSample` - 99 edges
8. `Lattice` - 98 edges
9. `Coordinator` - 90 edges
10. `InterpolationGuideLogicTests` - 90 edges

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

## Communities (163 total, 11 thin omitted)

### Community 0 - ".launchIntoEditor"
Cohesion: 0.05
Nodes (30): FillUITests, LayerUITests, .crossing, Bool, CGVector, Int, String, TimeInterval (+22 more)

### Community 1 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 2 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 3 - "CanvasManager"
Cohesion: 0.05
Nodes (44): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+36 more)

### Community 4 - "Coordinator"
Cohesion: 0.06
Nodes (28): LayerHostView, Bool, NSCoder, AppliedTool, CanvasView, Coordinator, .sandwichPresentation, InterpolationPreviewKey (+20 more)

### Community 5 - "CanvasManager"
Cohesion: 0.06
Nodes (29): Identifiable, CanvasManager, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes (+21 more)

### Community 6 - "VectorCanvas"
Cohesion: 0.09
Nodes (28): image, kind, Kind, fill, image, stroke, Bool, CGAffineTransform (+20 more)

### Community 7 - "CompositorParityLogicTests"
Cohesion: 0.12
Nodes (9): CompositorParityLogicTests, Bool, CanvasManager, CGImage, Int, StaticString, String, UIImage (+1 more)

### Community 8 - "ParityScenario"
Cohesion: 0.09
Nodes (33): CustomStringConvertible, Backdrop, fill, image, none, Gesture, diagonalCut, edgeShave (+25 more)

### Community 9 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (21): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+13 more)

### Community 10 - ".encode"
Cohesion: 0.13
Nodes (20): Metal, MTLTexture, BlendMode, .shaderCode, CompositorMetalEngine, MetalCompositor, ScratchTexturePool, Bool (+12 more)

### Community 11 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 12 - ".setCelLayout"
Cohesion: 0.11
Nodes (5): CanvasManager, Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 13 - "String"
Cohesion: 0.05
Nodes (50): UUID, CodableColor, .uiColor, CodingKeys, brush, color, composite, elements (+42 more)

### Community 14 - "CanvasManager"
Cohesion: 0.08
Nodes (28): String, UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+20 more)

### Community 15 - "Lattice"
Cohesion: 0.09
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 16 - "PointCloudIndex"
Cohesion: 0.12
Nodes (15): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+7 more)

### Community 17 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (7): Intersection, samples, StrokeGeometryLogicTests, .ramp, StaticString, String, UInt

### Community 18 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (24): StrokeInput, TimeInterval, UITouch, UIView, StrokeCanvasView, .brush, .isNoScratchRole, .pencilOnlyDrawing (+16 more)

### Community 19 - "VectorEraserLogicTests"
Cohesion: 0.15
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 20 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 21 - "CGPoint"
Cohesion: 0.15
Nodes (7): CGPoint, .length, LatticeLogicTests, Int, StaticString, String, UInt

### Community 22 - "InterpolationRecipe"
Cohesion: 0.11
Nodes (21): Codable, InterpolationMode, generate, reproject, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference (+13 more)

### Community 23 - "CGFloat"
Cohesion: 0.11
Nodes (13): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, Sweep (+5 more)

### Community 24 - "CanvasManager"
Cohesion: 0.11
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "UIKit"
Cohesion: 0.07
Nodes (6): CoreGraphics, Darwin, LayerTransform, ThumbnailRenderer, UIKit, XCTest

### Community 26 - "InterpolationRenderLogicTests"
Cohesion: 0.16
Nodes (11): fill, ID, InterpolationRenderLogicTests, CGSize, CodableColor, Double, Int, UIImage (+3 more)

### Community 27 - "SandwichLogicTests"
Cohesion: 0.13
Nodes (6): Battery, SandwichLogicTests, CanvasManager, CGImage, Int, String

### Community 28 - "PerfBaselineTests"
Cohesion: 0.18
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 29 - ".evaluate"
Cohesion: 0.12
Nodes (22): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+14 more)

### Community 30 - "Brush"
Cohesion: 0.08
Nodes (19): Brush, BrushDynamics, BrushGrain, BrushShape, custom, .displayName, hardRound, .id (+11 more)

### Community 31 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 32 - "ARAPLogicTests"
Cohesion: 0.08
Nodes (11): ARAPInterpolation, Interpolator, Options, Bool, groups, ARAPLogicTests, .rigidMotionL, Int (+3 more)

### Community 33 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.25
Nodes (4): rest, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 34 - "AnimationTimeline"
Cohesion: 0.08
Nodes (25): Gesture, AnimationTimeline, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .isCollapsed, .layerNameColumn (+17 more)

### Community 35 - "RasterLayerTexture"
Cohesion: 0.14
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 36 - "VectorEraserHybridLogicTests"
Cohesion: 0.14
Nodes (13): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut, Bool, Double (+5 more)

### Community 37 - "StructureSnapshot"
Cohesion: 0.19
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 38 - "ProjectManifest"
Cohesion: 0.20
Nodes (20): LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest, LayerManifest (+12 more)

### Community 39 - ".load"
Cohesion: 0.22
Nodes (8): ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString, String, UInt, URL

### Community 40 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 41 - "layers"
Cohesion: 0.15
Nodes (12): .activeLayerIsVector, .activeCelIsInBetween, CanvasManager, Bool, Int, Void, Cel, .endFrame (+4 more)

### Community 42 - "GuideOverlayView"
Cohesion: 0.12
Nodes (17): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+9 more)

### Community 43 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 44 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 45 - "ShapeGeometry"
Cohesion: 0.09
Nodes (19): Corner, bottomLeft, bottomRight, topLeft, topRight, FollowFrame, ShapeGeometry, .boundingRect (+11 more)

### Community 46 - "StrokeGeometry"
Cohesion: 0.15
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 47 - "VectorSample"
Cohesion: 0.19
Nodes (12): Int64, VectorSample, .point, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool (+4 more)

### Community 48 - "LayerTreeCharacterizationTests"
Cohesion: 0.19
Nodes (8): Layer, StaticString, String, UInt, UUID, LayerTreeCharacterizationTests, CanvasManager, String

### Community 49 - "FillParams"
Cohesion: 0.18
Nodes (28): device, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor, gapRadius (+20 more)

### Community 50 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 51 - "SaveSnapshot"
Cohesion: 0.10
Nodes (26): CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary, SaveSnapshot, BlendMode, Bool (+18 more)

### Community 52 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 53 - "DeformFactorization"
Cohesion: 0.23
Nodes (9): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Double, Int, Int32, SparseMatrix_Double (+1 more)

### Community 54 - "FloatingPieceOverlayView"
Cohesion: 0.16
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 55 - "RenderTreeCharacterizationTests"
Cohesion: 0.22
Nodes (3): RenderTreeCharacterizationTests, CanvasManager, String

### Community 56 - "ShapeDetectorLogicTests"
Cohesion: 0.16
Nodes (3): ShapeDetectorLogicTests, CGRect, Int

### Community 57 - "LayerOptionsPanel"
Cohesion: 0.14
Nodes (24): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex (+16 more)

### Community 58 - ".stampStroke"
Cohesion: 0.16
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 59 - "MaskParityLogicTests"
Cohesion: 0.12
Nodes (10): AlphaMask, .isActive, Bool, Float, MaskParityLogicTests, .side, Bool, CanvasManager (+2 more)

### Community 60 - "BackupManagerLogicTests"
Cohesion: 0.15
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 61 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 62 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 63 - "BlendMode"
Cohesion: 0.06
Nodes (31): BlendMode, add, clipToBelow, color, colorBurn, colorDodge, .compositedMode, darken (+23 more)

### Community 64 - ".analyse"
Cohesion: 0.29
Nodes (6): Group, MotionGrouping, Options, Bool, Int, Set

### Community 65 - ".transparentFormat"
Cohesion: 0.10
Nodes (23): IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath, CGRect (+15 more)

### Community 67 - "RenderNode"
Cohesion: 0.07
Nodes (31): Kind, folder, layer, MaskSource, folder, .id, layer, Decoder (+23 more)

### Community 68 - "View"
Cohesion: 0.14
Nodes (17): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+9 more)

### Community 69 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 70 - ".manager"
Cohesion: 0.12
Nodes (4): CGSize, Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 71 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 72 - "MetalFillEngine"
Cohesion: 0.18
Nodes (16): MTLBuffer, MTLCommandBuffer, FillParams, MetalFillEngine, .pipelines, MetalFillSession, Bool, Float (+8 more)

### Community 73 - "ContentView"
Cohesion: 0.13
Nodes (13): App, AppScreen, editor, gallery, sizePicker, ContentView, .body, CanvasManager (+5 more)

### Community 74 - "Equatable"
Cohesion: 0.18
Nodes (12): Equatable, Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval (+4 more)

### Community 75 - "LayerRowModel"
Cohesion: 0.16
Nodes (15): NSObject, Coordinator, LayerRowModel, .folderID, BlendMode, Double, Int, Set (+7 more)

### Community 77 - "InterpolationRefusal"
Cohesion: 0.16
Nodes (11): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+3 more)

### Community 78 - "CodingKeys"
Cohesion: 0.09
Nodes (22): CodingKeys, alphaMask, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, customBrushes (+14 more)

### Community 79 - ".solidImage"
Cohesion: 0.16
Nodes (9): CanvasFixture, CGImage, CGRect, CGSize, UIColor, UIImage, UInt8, BlendMode (+1 more)

### Community 80 - "ObjectTransformOverlayView"
Cohesion: 0.18
Nodes (12): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+4 more)

### Community 81 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 82 - "CanvasManager"
Cohesion: 0.21
Nodes (8): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, UIImage

### Community 83 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 84 - "Foundation"
Cohesion: 0.10
Nodes (10): Foundation, Tool, eraser, fill, pen, pencil, Notification.Name, AppVersion (+2 more)

### Community 85 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 86 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 87 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 88 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 89 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 90 - ".draw"
Cohesion: 0.28
Nodes (9): CoreGraphicsCompositor, CGImage, CGRect, Double, Int, UIImage, UInt8, CGImage (+1 more)

### Community 91 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 92 - "ProjectVersionsView"
Cohesion: 0.38
Nodes (5): ProjectVersionsView, .body, RecentlyDeletedView, .body, Void

### Community 93 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 94 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 95 - "RenderRequest"
Cohesion: 0.16
Nodes (18): CanvasManager, LayerContentVersion, LayerRenderSource, RenderBackground, RenderRequest, SandwichRequests, Bool, Cel (+10 more)

### Community 96 - "ShapeDetector"
Cohesion: 0.19
Nodes (5): ClosedFit, ShapeDetector, Bool, CGRect, Int

### Community 97 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 98 - ".setUpGestures"
Cohesion: 0.14
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 99 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 100 - "bash"
Cohesion: 0.31
Nodes (17): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+9 more)

### Community 101 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 102 - "SwiftUI"
Cohesion: 0.15
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 103 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 104 - ".stampCircle"
Cohesion: 0.21
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 105 - "LayerStackListView"
Cohesion: 0.18
Nodes (8): IndexPath, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView, UIViewRepresentable

### Community 106 - "agent"
Cohesion: 0.08
Nodes (25): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, model, description (+17 more)

### Community 107 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 108 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 109 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 110 - "XCTestCase"
Cohesion: 0.22
Nodes (7): OnionSkinSource, PreviousCelOnionSkinSource, XCTestCase, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 111 - "Composite.metal"
Cohesion: 0.28
Nodes (24): float3, blendChannels(), blendColor(), blendColorBurn(), blendColorDodge(), blendDarkerColor(), blendDivide(), blendExclusion() (+16 more)

### Community 112 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 113 - ".withInterpolationUndo"
Cohesion: 0.14
Nodes (11): Layer, String, Void, GroupInterpolation, auto, clean, crossFade, MotionGroup (+3 more)

### Community 114 - "LayerStackRow"
Cohesion: 0.14
Nodes (12): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+4 more)

### Community 115 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 116 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 117 - ".coverage"
Cohesion: 0.23
Nodes (6): CacheKey, MaskCache, MaskResolver, ResolvedMask, Int, UInt8

### Community 118 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 119 - "ViewPreset"
Cohesion: 0.19
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 120 - "Matrix2x2"
Cohesion: 0.24
Nodes (5): Matrix2x2, .determinant, .isFinite, .polar, Bool

### Community 121 - "LayerStackListView.Coordinator"
Cohesion: 0.21
Nodes (8): DropTarget, between, onto, LayerStackListView.Coordinator, Bool, UIGestureRecognizer, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 122 - "You are the Orchestrator for the rest of the layer-compositing project"
Cohesion: 0.22
Nodes (8): At each phase boundary, Cut deliberately, with the answer already worked out, Gotchas that each cost a cycle — put these in every worker prompt, Read this first, because the last session got it wrong, State, What is left, What phase 5b just built, and the two places phase 6 collides with it, You are the Orchestrator for the rest of the layer-compositing project

### Community 123 - "Layer"
Cohesion: 0.22
Nodes (8): Layer, BlendMode, Bool, Cel, Double, String, UIImage, UUID

### Community 124 - "BrushBlendMode"
Cohesion: 0.22
Nodes (9): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+1 more)

### Community 125 - "TransformOverlaySupport.swift"
Cohesion: 0.18
Nodes (10): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+2 more)

### Community 126 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 127 - ".refreshUndoRedoState"
Cohesion: 0.16
Nodes (7): CanvasManager, Bool, CGSize, UIImage, String, UUID, VectorStroke

### Community 128 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 129 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 130 - "compositeOver"
Cohesion: 0.31
Nodes (11): blendOver(), compositeFill(), compositeMask(), compositeOver(), constant, float4, kernel, uint (+3 more)

### Community 131 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 132 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 133 - "VectorEraserMode"
Cohesion: 0.25
Nodes (8): Bool, VectorEraserMode, cutPoints, cutToIntersection, .displayName, erase, .id, .isStabilized

### Community 135 - "Known Issues"
Cohesion: 0.29
Nodes (7): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), `duplicateLayer` drops `blendMode`, and now `alphaMask` too (2026-08-13), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 136 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 137 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 138 - "CodingKeys"
Cohesion: 0.06
Nodes (32): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+24 more)

### Community 139 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 140 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 141 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 142 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 143 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 144 - "Compositor.swift"
Cohesion: 0.19
Nodes (19): BlendMode, .coreGraphicsBlendMode, .isNonSeparable, clipColor(), colorBurnChannel(), colorDodgeChannel(), Compositor, CompositorBackend (+11 more)

### Community 145 - ".menuButton"
Cohesion: 0.32
Nodes (6): .blockMenu, .gapMenu, .loopMenu, ButtonRole, String, Void

### Community 146 - "Edge"
Cohesion: 0.25
Nodes (5): Edge, bottom, left, right, top

### Community 147 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 148 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 149 - "SelectionMode"
Cohesion: 0.29
Nodes (7): SelectionMode, automatic, .displayName, .id, lasso, rectangle, .systemImage

### Community 150 - "CaseIterable"
Cohesion: 0.33
Nodes (5): CaseIterable, Kind, line, oval, rectangle

### Community 152 - "worker-test"
Cohesion: 0.50
Nodes (4): worker-test, description, mode, model

### Community 153 - "worker-ui"
Cohesion: 0.50
Nodes (4): worker-ui, description, mode, model

### Community 156 - "SandwichPresentation"
Cohesion: 0.67
Nodes (3): SandwichPresentation, disengaged, midStroke

## Knowledge Gaps
- **551 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+546 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `.launchIntoEditor`, `cels`, `Coordinator`, `CanvasManager`, `Coordinator`, `CanvasManager`, `VectorCanvas`, `CompositorParityLogicTests`, `ParityScenario`, `String`, `CanvasManager`, `Lattice`, `PointCloudIndex`, `StrokeGeometryLogicTests`, `StrokeCanvasView`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `CGPoint`, `CaseIterable`, `InterpolationRecipe`, `CanvasManager`, `UIKit`, `InterpolationRenderLogicTests`, `SandwichLogicTests`, `PerfBaselineTests`, `.evaluate`, `Brush`, `Deterministic`, `ARAPLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `AnimationTimeline`, `RasterLayerTexture`, `VectorEraserHybridLogicTests`, `.load`, `InterpolationModelLogicTests`, `GuideOverlayView`, `StrokeSettingsPanel`, `ShapeGeometry`, `StrokeGeometry`, `VectorSample`, `DeformFactorization`, `FloatingPieceOverlayView`, `ShapeDetectorLogicTests`, `.stampStroke`, `LayerStackCell`, `.analyse`, `.transparentFormat`, `InterpolationGuideLogicTests`, `ShapeOverlayView`, `CanvasManager`, `LayerRowModel`, `.indices`, `ObjectTransformOverlayView`, `CanvasManager`, `.manager`, `Color`, `ActionsMenu`, `EraserSettingsPanel`, `.draw`, `InterpolateBar`, `DrawingView`, `.arched`, `ShapeDetector`, `TimedSample`, `.setUpGestures`, `SideToolbar`, `.stampCircle`, `LayerStackListView`, `GuidePath`, `SpacingChart`, `XCTestCase`, `StrokeStabilizer`, `Matrix2x2`, `TransformOverlaySupport.swift`, `.refreshUndoRedoState`?**
  _High betweenness centrality (0.331) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `Coordinator`, `CanvasManager`, `Coordinator`, `CanvasManager`, `VectorCanvas`, `ParityScenario`, `ColorPickerPanel`, `CanvasManager`, `Lattice`, `PointCloudIndex`, `StrokeGeometryLogicTests`, `Edge`, `StrokeCanvasView`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `CaseIterable`, `CGFloat`, `CanvasManager`, `UIKit`, `InterpolationRecipe`, `InterpolationRenderLogicTests`, `PerfBaselineTests`, `.evaluate`, `Brush`, `ARAPLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `AnimationTimeline`, `RasterLayerTexture`, `VectorEraserHybridLogicTests`, `.load`, `InterpolationModelLogicTests`, `layers`, `GuideOverlayView`, `ShapeGeometry`, `StrokeGeometry`, `VectorSample`, `DeformFactorization`, `FloatingPieceOverlayView`, `ShapeDetectorLogicTests`, `.stampStroke`, `MaskParityLogicTests`, `.analyse`, `.transparentFormat`, `InterpolationGuideLogicTests`, `ShapeOverlayView`, `.manager`, `.indices`, `ObjectTransformOverlayView`, `SelectionOverlayView`, `CanvasManager`, `.manager`, `.arched`, `ShapeDetector`, `TimedSample`, `.setUpGestures`, `.stampCircle`, `GuidePath`, `StrokeStabilizer`, `Matrix2x2`, `LayerStackListView.Coordinator`, `TransformOverlaySupport.swift`, `.refreshUndoRedoState`?**
  _High betweenness centrality (0.189) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `.launchIntoEditor`, `cels`, `CompositorParityLogicTests`, `ParityScenario`, `.setCelLayout`, `StrokeGeometryLogicTests`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `CGPoint`, `UIKit`, `InterpolationRenderLogicTests`, `SandwichLogicTests`, `PerfBaselineTests`, `ARAPLogicTests`, `InterpolationEngineDiagnosticsLogicTests`, `VectorEraserHybridLogicTests`, `.load`, `InterpolationModelLogicTests`, `PlaybackBoundsCharacterizationTests`, `LayerTreeCharacterizationTests`, `RenderTreeCharacterizationTests`, `ShapeDetectorLogicTests`, `MaskParityLogicTests`, `BackupManagerLogicTests`, `InterpolationGuideLogicTests`, `.manager`, `BlockDragCharacterizationTests`?**
  _High betweenness centrality (0.079) - this node is a cross-community bridge._
- **Are the 57 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 57 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 13 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 113 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 113 INFERRED edges - model-reasoned connections that need verification._