# Graph Report - laptop-tailscale-connection-78ec13  (2026-08-13)

## Corpus Check
- 159 files · ~326,240 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 4107 nodes · 12545 edges · 159 communities (143 shown, 16 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1466 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `389876b4`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- .launchIntoEditor
- VectorEraserHybridLogicTests
- Coordinator
- CanvasManager
- VectorCanvas
- PerfBaselineTests
- StrokeCanvasView
- bash
- ProjectBackupManager
- StrokeGeometryLogicTests
- ColorPickerPanel
- CanvasManager
- CanvasManager
- .setCelLayout
- CompositorParityLogicTests
- ARAPRegistration
- VectorEraserLogicTests
- Lattice
- BrushEngineLogicTests
- .transparentFormat
- AnimationTimeline
- ViewPreset
- .solidImage
- CanvasManager
- RasterLayerTexture
- InterpolationRenderLogicTests
- SaveSnapshot
- PointCloudIndex
- InterpolationModelLogicTests
- InterpolationRecipe
- UIKit
- ARAPLogicTests
- .setUpGestures
- LatticeLogicTests
- layers
- CGPoint
- PlaybackBoundsCharacterizationTests
- BrushShape
- Codable
- StrokeSpatialIndex
- CGFloat
- GuideOverlayView
- LayerTreeCharacterizationTests
- .encode
- CanvasManager
- BackupManagerLogicTests
- FillParams
- FloatingPieceOverlayView
- BrushBlendMode
- TouchCountRecognizer
- Coordinator
- Layer Compositing
- CodingKeys
- ActivePanel
- .manager
- LayerStackCell
- InterpolationGuideLogicTests
- StrokeSettingsPanel
- ShapeOverlayView
- View
- .encode
- CanvasManager
- LayerOptionsPanel
- StructureSnapshot
- BlockDragCharacterizationTests
- .indices
- CanvasManager
- .load
- SelectionOverlayView
- .makeUIView
- Foundation
- .manager
- ContentView
- RenderTreeCharacterizationTests
- CodingKeys
- Color
- BrushSettingsPanel
- BlendMode
- PerfMonitor
- .stampStroke
- CodingKeys
- InterpolateBar
- SelectPanel
- .arched
- DeformFactorization
- TimedSample
- CanvasSizePickerView
- .rgbaPixels
- MotionGroup
- SideToolbar
- UndoHistory
- ObjectTransformOverlayView
- TransformOverlaySupport.swift
- DrawingView
- CanvasHostView
- XCTestCase
- Equatable
- SpacingChart
- LayerStackRow
- InterpolationEngineDiagnosticsLogicTests
- SandwichLogicTests
- VectorEraserMode
- RenderNode
- 4. Future upgrades — the deferred list
- DabTarget
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView.Coordinator
- StrokeStabilizer
- .setCanvasPadding
- PaintSoftware - iPad Drawing and Animation App
- LayerStackListView
- Layer
- SwiftUI
- Usage Guide
- CutOutcome
- agent
- .withInterpolationUndo
- LayerRowModel
- CLAUDE.md
- Known Issues
- Atomic
- ManifestSkeleton
- EraserSettingsPanel
- ProjectVersionsView
- What needs to change
- Multi-Session Protocol
- parallel_test.sh
- Composite.metal
- Performance baseline
- InterpolatePanel
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh
- MoveTransformBottomBar
- Kind
- GuidePath
- nextprompt.md
- .clearRasterizeCache
- .attach
- VectorScratchRole
- Gesture
- Corner
- Edge
- command
- compositeOver
- worker-feature
- worker-research
- .setPinchHighlight
- .placedImage
- orchestrator
- worker-bugfix
- ThumbnailRenderer.swift
- worker-test

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 535 edges
2. `CGFloat` - 409 edges
3. `VectorCanvas` - 122 edges
4. `layers` - 110 edges
5. `CanvasManager` - 103 edges
6. `CanvasManager` - 100 edges
7. `VectorSample` - 99 edges
8. `Lattice` - 98 edges
9. `Coordinator` - 91 edges
10. `InterpolationGuideLogicTests` - 90 edges

## Surprising Connections (you probably didn't know these)
- `PerfBaselineTests` --calls--> `Brush`  [INFERRED]
  PaintSoftwareUITests/PerfBaselineTests.swift → PaintSoftware/Engine/Brush.swift
- `.fixedBrush` --calls--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Brush.swift
- `StrokeGeometryLogicTests` --calls--> `CGPoint`  [INFERRED]
  PaintSoftwareUITests/StrokeGeometryLogicTests.swift → PaintSoftware/Engine/Deform/MotionGrouping.swift
- `InterpolationRenderLogicTests` --calls--> `CelRef`  [INFERRED]
  PaintSoftwareUITests/InterpolationRenderLogicTests.swift → PaintSoftware/Models/InterpolationRecipe.swift
- `ParityScenario` --references--> `Brush`  [EXTRACTED]
  PaintSoftwareUITests/RasterVectorParityLogicTests.swift → PaintSoftware/Engine/Brush.swift

## Import Cycles
- None detected.

## Communities (159 total, 16 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (20): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+12 more)

### Community 1 - ".launchIntoEditor"
Cohesion: 0.05
Nodes (30): FillUITests, LayerUITests, .crossing, Bool, CGVector, Int, String, TimeInterval (+22 more)

### Community 2 - "VectorEraserHybridLogicTests"
Cohesion: 0.07
Nodes (41): CustomStringConvertible, UUID, Backdrop, fill, image, none, ParityPixel, .description (+33 more)

### Community 3 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 4 - "CanvasManager"
Cohesion: 0.07
Nodes (29): Identifiable, CanvasManager, .activeCelIsInBetween, .guideChips, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider (+21 more)

### Community 5 - "VectorCanvas"
Cohesion: 0.06
Nodes (57): CodableColor, .uiColor, image, kind, DabLattice, .range, ElementData, fill (+49 more)

### Community 6 - "PerfBaselineTests"
Cohesion: 0.19
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 7 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (25): StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+17 more)

### Community 8 - "bash"
Cohesion: 0.38
Nodes (16): gh *, git *, xcodebuild *, permission, bash, edit, glob, grep (+8 more)

### Community 9 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 10 - "StrokeGeometryLogicTests"
Cohesion: 0.08
Nodes (7): Intersection, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 11 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 12 - "CanvasManager"
Cohesion: 0.05
Nodes (44): CanvasManager, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex, .effectiveLoopRange (+36 more)

### Community 13 - "CanvasManager"
Cohesion: 0.07
Nodes (35): String, UUID, Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate (+27 more)

### Community 14 - ".setCelLayout"
Cohesion: 0.12
Nodes (4): Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 15 - "CompositorParityLogicTests"
Cohesion: 0.14
Nodes (7): CompositorParityLogicTests, Bool, CanvasManager, Int, StaticString, String, UInt

### Community 16 - "ARAPRegistration"
Cohesion: 0.12
Nodes (14): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, Result, Similarity (+6 more)

### Community 17 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (7): VectorEraser, ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 18 - "Lattice"
Cohesion: 0.08
Nodes (23): Interpolator, vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds (+15 more)

### Community 19 - "BrushEngineLogicTests"
Cohesion: 0.21
Nodes (8): BrushEngineLogicTests, Any, CodableColor, Data, Double, String, T, VectorStroke

### Community 20 - ".transparentFormat"
Cohesion: 0.10
Nodes (23): IntPoint, PixelOps, RasterizeCache, RasterizeKey, Bool, Cel, CGPath, CGRect (+15 more)

### Community 21 - "AnimationTimeline"
Cohesion: 0.07
Nodes (31): Gesture, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight, .dragHandle, .frameLabel, .gapMenu (+23 more)

### Community 22 - "ViewPreset"
Cohesion: 0.16
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 23 - ".solidImage"
Cohesion: 0.11
Nodes (13): CGImage, CGRect, CGSize, StaticString, String, UIColor, UIImage, UInt (+5 more)

### Community 24 - "CanvasManager"
Cohesion: 0.10
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 26 - "InterpolationRenderLogicTests"
Cohesion: 0.06
Nodes (46): CGPathElementType, ContentProvider, Direction, backward, forward, fromRest, Evaluation, GroupWarp (+38 more)

### Community 27 - "SaveSnapshot"
Cohesion: 0.08
Nodes (31): CelContent, CodableColor, .color, Color, .codable, LayerContent, ProjectStore, .projectsDirectory (+23 more)

### Community 28 - "PointCloudIndex"
Cohesion: 0.16
Nodes (9): PointCloudIndex, .isEmpty, Group, MotionGrouping, Options, Bool, Int, Set (+1 more)

### Community 29 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 30 - "InterpolationRecipe"
Cohesion: 0.17
Nodes (11): InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding, SpacingCurve, Bool (+3 more)

### Community 31 - "UIKit"
Cohesion: 0.08
Nodes (5): CoreGraphics, Darwin, LayerTransform, UIKit, XCTest

### Community 32 - "ARAPLogicTests"
Cohesion: 0.14
Nodes (8): ARAPInterpolation, Options, Bool, ARAPLogicTests, .rigidMotionL, StaticString, String, UInt

### Community 33 - ".setUpGestures"
Cohesion: 0.15
Nodes (8): CGSize, UILongPressGestureRecognizer, UIPanGestureRecognizer, UIPinchGestureRecognizer, UIView, Void, Recognizer, UIRotationGestureRecognizer

### Community 34 - "LatticeLogicTests"
Cohesion: 0.14
Nodes (5): LatticeLogicTests, Int, StaticString, String, UInt

### Community 35 - "layers"
Cohesion: 0.14
Nodes (11): .activeLayerIsVector, CanvasManager, Bool, Int, Void, Cel, .endFrame, Int (+3 more)

### Community 36 - "CGPoint"
Cohesion: 0.06
Nodes (31): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGPoint, .length (+23 more)

### Community 37 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 38 - "BrushShape"
Cohesion: 0.13
Nodes (14): CaseIterable, BrushShape, custom, .displayName, hardRound, .id, pen, pencil (+6 more)

### Community 39 - "Codable"
Cohesion: 0.22
Nodes (21): Codable, LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest (+13 more)

### Community 40 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 41 - "CGFloat"
Cohesion: 0.09
Nodes (17): Brush, CGFloat, VectorSample, Capsule, .boundingBox, StrokeGeometry, Bool, CGRect (+9 more)

### Community 42 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 43 - "LayerTreeCharacterizationTests"
Cohesion: 0.19
Nodes (7): CanvasFixture, CanvasManager, Layer, UUID, LayerTreeCharacterizationTests, CanvasManager, String

### Community 44 - ".encode"
Cohesion: 0.08
Nodes (35): Metal, MTLBuffer, MTLCommandBuffer, MTLTexture, BlendMode, .shaderCode, CompositorMetalEngine, MetalCompositor (+27 more)

### Community 45 - "CanvasManager"
Cohesion: 0.14
Nodes (17): CanvasManager, .layerStackRows, ContainerEntry, folder, layer, StackAnchor, bottom, folder (+9 more)

### Community 46 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 47 - "FillParams"
Cohesion: 0.18
Nodes (28): device, colourDistance(), computeWalls(), edgeDilate(), FillParams, edgeOverlap, fillColor, gapRadius (+20 more)

### Community 48 - "FloatingPieceOverlayView"
Cohesion: 0.18
Nodes (10): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+2 more)

### Community 49 - "BrushBlendMode"
Cohesion: 0.09
Nodes (17): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+9 more)

### Community 50 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 51 - "Coordinator"
Cohesion: 0.08
Nodes (25): LayerHostView, Bool, Coordinator, .sandwichPresentation, InterpolationPreviewKey, LayerContentVersion, SandwichKey, SandwichPresentation (+17 more)

### Community 52 - "Layer Compositing"
Cohesion: 0.07
Nodes (28): 10. Still open, 11. Build order, 1. Why these are one project, 2. What is *not* changing, 3. Settled decisions, 4.1 Structure, 4.2 Isolated groups, 4.3 Compositor nodes (+20 more)

### Community 53 - "CodingKeys"
Cohesion: 0.08
Nodes (26): CodingKey, CodingKeys, activeCells, cellSize, cols, originX, originY, rows (+18 more)

### Community 54 - "ActivePanel"
Cohesion: 0.13
Nodes (18): ActivePanel, actions, adjust, brush, color, eraser, fill, layers (+10 more)

### Community 55 - ".manager"
Cohesion: 0.16
Nodes (3): Bool, CanvasManager, ViewPresetCharacterizationTests

### Community 56 - "LayerStackCell"
Cohesion: 0.11
Nodes (10): LayerStackCell, Bool, Double, Int, NSCoder, NSLayoutConstraint, String, UIView (+2 more)

### Community 58 - "StrokeSettingsPanel"
Cohesion: 0.15
Nodes (19): Accessory, KeyPath, StrokeSettingsPanel, .body, .brush, .grainDepthBinding, .opacityBinding, .presetPicker (+11 more)

### Community 59 - "ShapeOverlayView"
Cohesion: 0.08
Nodes (29): CALayer, CornerHandle, EdgeHandle, EndpointHandle, end, start, HandleInfo, HandleKind (+21 more)

### Community 60 - "View"
Cohesion: 0.13
Nodes (17): GuideRow, .averagingNote, .body, .guideButton, .hasASpacingChart, .hasRecipe, .spacingButton, Bool (+9 more)

### Community 62 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 63 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (23): .layerPanelRail, blendModeRow(), FolderOptionsPanel, .body, .folderIndex, LayerOptionsPanel, .body, .layerIndex (+15 more)

### Community 64 - "StructureSnapshot"
Cohesion: 0.18
Nodes (5): CanvasManager, StructureSnapshot, Int, Layer, String

### Community 65 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 67 - "CanvasManager"
Cohesion: 0.16
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 68 - ".load"
Cohesion: 0.22
Nodes (8): ProjectSaveLogicTests, Bool, CanvasManager, Cel, StaticString, String, UInt, URL

### Community 69 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 70 - ".makeUIView"
Cohesion: 0.12
Nodes (10): AppliedTool, CanvasView, Color, Context, Coordinator, Double, LayerTransform, .body (+2 more)

### Community 71 - "Foundation"
Cohesion: 0.14
Nodes (5): Foundation, Notification.Name, AppVersion, .versionString, String

### Community 72 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 73 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 74 - "RenderTreeCharacterizationTests"
Cohesion: 0.22
Nodes (3): RenderTreeCharacterizationTests, CanvasManager, String

### Community 75 - "CodingKeys"
Cohesion: 0.11
Nodes (19): CodingKeys, brush, color, composite, elements, fill, fills, id (+11 more)

### Community 76 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 77 - "BrushSettingsPanel"
Cohesion: 0.13
Nodes (15): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String, .panelView (+7 more)

### Community 78 - "BlendMode"
Cohesion: 0.11
Nodes (18): BlendMode, add, colorBurn, colorDodge, darken, difference, .displayName, hardLight (+10 more)

### Community 79 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 80 - ".stampStroke"
Cohesion: 0.14
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 81 - "CodingKeys"
Cohesion: 0.08
Nodes (21): CodingKeys, backgroundColor, blendMode, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps (+13 more)

### Community 82 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 83 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

### Community 84 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 85 - "DeformFactorization"
Cohesion: 0.12
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 86 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 87 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 89 - "MotionGroup"
Cohesion: 0.19
Nodes (10): Layer, GroupInterpolation, auto, clean, crossFade, MotionGroup, CodableColor, Decoder (+2 more)

### Community 90 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 91 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 92 - "ObjectTransformOverlayView"
Cohesion: 0.13
Nodes (16): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void, Kind (+8 more)

### Community 93 - "TransformOverlaySupport.swift"
Cohesion: 0.28
Nodes (7): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting

### Community 94 - "DrawingView"
Cohesion: 0.25
Nodes (7): Alignment, DrawingView, .panelAlignment, Bool, CanvasManager, UUID, Void

### Community 95 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 96 - "XCTestCase"
Cohesion: 0.22
Nodes (7): OnionSkinSource, PreviousCelOnionSkinSource, XCTestCase, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 97 - "Equatable"
Cohesion: 0.17
Nodes (12): Equatable, Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval (+4 more)

### Community 98 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 99 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 100 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.23
Nodes (4): rest, InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 101 - "SandwichLogicTests"
Cohesion: 0.13
Nodes (6): Battery, SandwichLogicTests, CanvasManager, CGImage, Int, String

### Community 102 - "VectorEraserMode"
Cohesion: 0.14
Nodes (13): Bool, Tool, eraser, fill, pen, pencil, VectorEraserMode, cutPoints (+5 more)

### Community 103 - "RenderNode"
Cohesion: 0.07
Nodes (36): BlendMode, .coreGraphicsBlendMode, Compositor, CompositorBackend, coreGraphics, metal, CoreGraphicsCompositor, CGBlendMode (+28 more)

### Community 104 - "4. Future upgrades — the deferred list"
Cohesion: 0.17
Nodes (12): 1. What it does, 2. Architecture, 3. Settled decisions and hard-won facts, 4. Future upgrades — the deferred list, 5. Open judgement calls for the product owner, Explicitly deferred — do not build without being asked, Model and correctness gaps, Performance (+4 more)

### Community 105 - "DabTarget"
Cohesion: 0.22
Nodes (9): AnyObject, CGGradient, CGContextDabTarget, DabGradientCache, DabTarget, Key, CGBlendMode, CGContext (+1 more)

### Community 106 - "ActionsMenu"
Cohesion: 0.25
Nodes (9): ActionsMenu, .body, .content, .paddingControl, .pencilOnlyToggle, CanvasManager, Double, PhotosPickerItem (+1 more)

### Community 107 - "Is the brush engine ready for `.ABR` / Procreate brush import?"
Cohesion: 0.20
Nodes (9): 1. One stamper serves every tier, 2. The replayability contract, 3. Imported-asset lifetime is already solved, 4. The eraser degrades gracefully by construction, Is the brush engine ready for `.ABR` / Procreate brush import?, Order, if it is ever scheduled, Verdict, What I would not do (+1 more)

### Community 108 - "LayerStackListView.Coordinator"
Cohesion: 0.29
Nodes (6): DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizerDelegate, UITableViewDelegate

### Community 109 - "StrokeStabilizer"
Cohesion: 0.36
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 110 - ".setCanvasPadding"
Cohesion: 0.33
Nodes (4): CanvasManager, Bool, CGSize, UIImage

### Community 111 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 112 - "LayerStackListView"
Cohesion: 0.18
Nodes (8): IndexPath, .body, LayerStackListView, Context, Coordinator, Void, UISwipeActionsConfiguration, UITableView

### Community 113 - "Layer"
Cohesion: 0.22
Nodes (8): Layer, BlendMode, Bool, Cel, Double, String, UIImage, UUID

### Community 114 - "SwiftUI"
Cohesion: 0.18
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 115 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 116 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 117 - "agent"
Cohesion: 0.14
Nodes (13): agent, worker-integration, worker-ui, model, plugin, $schema, description, mode (+5 more)

### Community 118 - ".withInterpolationUndo"
Cohesion: 0.11
Nodes (16): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+8 more)

### Community 119 - "LayerRowModel"
Cohesion: 0.18
Nodes (14): NSObject, Coordinator, LayerRowModel, .folderID, BlendMode, CanvasManager, Double, Int (+6 more)

### Community 121 - "Known Issues"
Cohesion: 0.33
Nodes (6): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 122 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 123 - "ManifestSkeleton"
Cohesion: 0.47
Nodes (6): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer

### Community 124 - "EraserSettingsPanel"
Cohesion: 0.29
Nodes (7): CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager

### Community 125 - "ProjectVersionsView"
Cohesion: 0.47
Nodes (4): ProjectVersionsView, RecentlyDeletedView, .body, Void

### Community 126 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 127 - "Multi-Session Protocol"
Cohesion: 0.33
Nodes (6): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol, Triaging a failed XCUITest — do this before suspecting your change

### Community 128 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 129 - "Composite.metal"
Cohesion: 0.42
Nodes (11): float3, blendChannels(), blendColorBurn(), blendColorDodge(), blendHardLight(), blendMultiply(), blendOver(), blendScreen() (+3 more)

### Community 130 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

### Community 131 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 138 - "MoveTransformBottomBar"
Cohesion: 0.29
Nodes (6): MoveTransformBottomBar, .body, .divider, CanvasManager, String, Void

### Community 140 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 141 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 142 - "nextprompt.md"
Cohesion: 0.25
Nodes (7): Carried forward to a later phase, with the answer already worked out, Constraints, Gotchas the wiring session was handed, which the draft should already reflect — verify it does, State, The scope decision, taken by the product owner on 2026-08-12, What 5b-1 built and verified (commit `9925d51`), What is left

### Community 145 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 146 - "Gesture"
Cohesion: 0.33
Nodes (6): Gesture, diagonalCut, edgeShave, .label, .samples, squareCut

### Community 147 - "Corner"
Cohesion: 0.40
Nodes (5): Corner, bottomLeft, bottomRight, topLeft, topRight

### Community 148 - "Edge"
Cohesion: 0.40
Nodes (5): Edge, bottom, left, right, top

### Community 149 - "command"
Cohesion: 0.29
Nodes (7): command, deploy, resign, description, template, description, template

### Community 150 - "compositeOver"
Cohesion: 0.48
Nodes (7): compositeFill(), compositeOver(), constant, kernel, uint2, texture2d, write

### Community 151 - "worker-feature"
Cohesion: 0.50
Nodes (4): worker-feature, description, mode, model

### Community 152 - "worker-research"
Cohesion: 0.50
Nodes (4): worker-research, description, mode, model

### Community 155 - "orchestrator"
Cohesion: 0.50
Nodes (4): orchestrator, description, mode, model

### Community 156 - "worker-bugfix"
Cohesion: 0.50
Nodes (4): worker-bugfix, description, mode, model

### Community 158 - "worker-test"
Cohesion: 0.50
Nodes (4): worker-test, description, mode, model

## Knowledge Gaps
- **523 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+518 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **16 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `Coordinator`, `CanvasManager`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `CanvasManager`, `GuidePath`, `Kind`, `CanvasManager`, `ARAPRegistration`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `CompositorParityLogicTests`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `.placedImage`, `PointCloudIndex`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `UIKit`, `ARAPLogicTests`, `.setUpGestures`, `LatticeLogicTests`, `CGPoint`, `BrushShape`, `StrokeSpatialIndex`, `GuideOverlayView`, `BrushBlendMode`, `Coordinator`, `LayerStackCell`, `InterpolationGuideLogicTests`, `StrokeSettingsPanel`, `ShapeOverlayView`, `CanvasManager`, `.indices`, `CanvasManager`, `.load`, `.makeUIView`, `.manager`, `CodingKeys`, `Color`, `.stampStroke`, `InterpolateBar`, `.arched`, `DeformFactorization`, `TimedSample`, `.rgbaPixels`, `SideToolbar`, `ObjectTransformOverlayView`, `TransformOverlaySupport.swift`, `DrawingView`, `XCTestCase`, `SpacingChart`, `InterpolationEngineDiagnosticsLogicTests`, `SandwichLogicTests`, `RenderNode`, `DabTarget`, `ActionsMenu`, `StrokeStabilizer`, `.setCanvasPadding`, `LayerStackListView`, `LayerRowModel`, `EraserSettingsPanel`?**
  _High betweenness centrality (0.348) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `VectorEraserHybridLogicTests`, `Coordinator`, `CanvasManager`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `StrokeGeometryLogicTests`, `ColorPickerPanel`, `CanvasManager`, `GuidePath`, `CanvasManager`, `.clearRasterizeCache`, `ARAPRegistration`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `Gesture`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `.placedImage`, `PointCloudIndex`, `InterpolationModelLogicTests`, `InterpolationRecipe`, `UIKit`, `ARAPLogicTests`, `.setUpGestures`, `LatticeLogicTests`, `layers`, `BrushShape`, `StrokeSpatialIndex`, `CGFloat`, `GuideOverlayView`, `FloatingPieceOverlayView`, `Coordinator`, `InterpolationGuideLogicTests`, `ShapeOverlayView`, `.indices`, `CanvasManager`, `.load`, `SelectionOverlayView`, `.makeUIView`, `.manager`, `.stampStroke`, `CodingKeys`, `.arched`, `DeformFactorization`, `TimedSample`, `.rgbaPixels`, `ObjectTransformOverlayView`, `TransformOverlaySupport.swift`, `InterpolationEngineDiagnosticsLogicTests`, `DabTarget`, `LayerStackListView.Coordinator`, `StrokeStabilizer`, `.setCanvasPadding`?**
  _High betweenness centrality (0.225) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `cels`, `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `StrokeGeometryLogicTests`, `.setCelLayout`, `CompositorParityLogicTests`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `.solidImage`, `InterpolationRenderLogicTests`, `InterpolationModelLogicTests`, `UIKit`, `ARAPLogicTests`, `LatticeLogicTests`, `CGPoint`, `PlaybackBoundsCharacterizationTests`, `LayerTreeCharacterizationTests`, `BackupManagerLogicTests`, `.manager`, `InterpolationGuideLogicTests`, `BlockDragCharacterizationTests`, `.load`, `RenderTreeCharacterizationTests`, `InterpolationEngineDiagnosticsLogicTests`, `SandwichLogicTests`?**
  _High betweenness centrality (0.076) - this node is a cross-community bridge._
- **Are the 56 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 56 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `CGFloat` (e.g. with `.draw()` and `.celInsertionIndex()`) actually correct?**
  _`CGFloat` has 13 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 109 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 109 INFERRED edges - model-reasoned connections that need verification._