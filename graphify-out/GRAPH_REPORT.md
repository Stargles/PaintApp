# Graph Report - laptop-tailscale-connection-78ec13  (2026-08-10)

## Corpus Check
- 149 files · ~281,998 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3723 nodes · 11388 edges · 137 communities (127 shown, 10 thin omitted)
- Extraction: 88% EXTRACTED · 12% INFERRED · 0% AMBIGUOUS · INFERRED: 1360 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `108c424a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cels
- .launchIntoEditor
- VectorEraserHybridLogicTests
- Coordinator
- layers
- VectorCanvas
- PerfBaselineTests
- StrokeCanvasView
- bash
- ProjectBackupManager
- CGPoint
- ColorPickerPanel
- CanvasManager
- CanvasManager
- .setCelLayout
- VectorSample
- PointCloudIndex
- VectorEraserLogicTests
- Lattice
- BrushEngineLogicTests
- .transparentFormat
- AnimationTimeline
- ViewPreset
- BrushBlendMode
- CanvasManager
- RasterLayerTexture
- InterpolationRenderLogicTests
- SaveSnapshot
- StrokeGeometryLogicTests
- InterpolationModelLogicTests
- VectorImageElement
- UIKit
- ARAPLogicTests
- Coordinator
- .group
- .activeCelIndex
- ShapeGeometry
- PlaybackBoundsCharacterizationTests
- DeformFactorization
- Codable
- StrokeSpatialIndex
- StrokeGeometry
- GuideOverlayView
- LayerTreeCharacterizationTests
- MetalFillEngine
- CanvasManager
- BackupManagerLogicTests
- FillParams
- FloatingPieceOverlayView
- InterpolationRecipe
- TouchCountRecognizer
- .makeUIView
- Layer Compositing
- CodingKeys
- ActivePanel
- .manager
- LayerStackCell
- InterpolationGuideLogicTests
- StrokeSettingsPanel
- ShapeOverlayView
- View
- VectorStroke
- CanvasManager
- LayerOptionsPanel
- StructureSnapshot
- BlockDragCharacterizationTests
- .indices
- CanvasManager
- .load
- SelectionOverlayView
- GuideStroke
- LayerRowModel
- .manager
- ContentView
- CodingKeys
- InterpolationRefusal
- Color
- EraserSettingsPanel
- InterpolationEngineDiagnosticsLogicTests
- PerfMonitor
- .stampStroke
- CodingKeys
- InterpolateBar
- DrawingView
- .arched
- CGFloat
- TimedSample
- CanvasSizePickerView
- SwiftUI
- Identifiable
- SideToolbar
- UndoHistory
- ObjectTransformOverlayView
- UIView
- Foundation
- CanvasHostView
- XCTestCase
- GuidePath
- SpacingChart
- InterpolationPreviewKey
- Coordinator
- .registerGroups
- LayerStackRow
- SelectPanel
- 4. Future upgrades — the deferred list
- DabTarget
- ActionsMenu
- Is the brush engine ready for `.ABR` / Procreate brush import?
- LayerStackListView.Coordinator
- StrokeStabilizer
- SelectionMode
- PaintSoftware - iPad Drawing and Animation App
- BrushSettingsPanel
- Layer
- VectorScratchRole
- Usage Guide
- CutOutcome
- Kind
- InterpolatePanel
- .attach
- CLAUDE.md
- Known Issues
- Atomic
- ProjectStore.swift
- GalleryView
- What needs to change
- Multi-Session Protocol
- parallel_test.sh
- Performance baseline
- .setPinchHighlight
- cleanup_session.sh
- screenshot.sh
- graphify-guard.sh
- run.sh
- fast_test.sh
- status.sh

## God Nodes (most connected - your core abstractions)
1. `CGPoint` - 533 edges
2. `CGFloat` - 405 edges
3. `VectorCanvas` - 122 edges
4. `layers` - 106 edges
5. `CanvasManager` - 100 edges
6. `CanvasManager` - 99 edges
7. `Lattice` - 98 edges
8. `VectorSample` - 98 edges
9. `InterpolationGuideLogicTests` - 90 edges
10. `Coordinator` - 79 edges

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

## Communities (137 total, 10 thin omitted)

### Community 0 - "cels"
Cohesion: 0.06
Nodes (18): cels, InterpolationReferenceOnionSkinSource, InterpolationMotionGroupLogicTests, .twoBodiesAtRest, .twoBodiesMoved, CanvasManager, Cel, CodableColor (+10 more)

### Community 1 - ".launchIntoEditor"
Cohesion: 0.06
Nodes (21): FillUITests, LayerUITests, PaintUITestCase, Bool, CGVector, Double, Int, String (+13 more)

### Community 2 - "VectorEraserHybridLogicTests"
Cohesion: 0.06
Nodes (49): CustomStringConvertible, UUID, UIImage, UInt8, Backdrop, fill, image, none (+41 more)

### Community 3 - "Coordinator"
Cohesion: 0.06
Nodes (42): BlockDrag, CelBlockView, Coordinator, Kind, cel, gap, Segment, Bool (+34 more)

### Community 4 - "layers"
Cohesion: 0.09
Nodes (19): CanvasManager, .activeCelIsInBetween, .guideRefusal, .hasAnonymousWholeFrameGroup, .interpolationCommitOptions, .interpolationContentProvider, .interpolationKeyframes, .interpolationReferenceCanvases (+11 more)

### Community 5 - "VectorCanvas"
Cohesion: 0.10
Nodes (19): kind, Bool, CGAffineTransform, CGPath, CGRect, CGSize, VectorCanvas, .elements (+11 more)

### Community 6 - "PerfBaselineTests"
Cohesion: 0.20
Nodes (7): PerfBaselineTests, CanvasManager, Double, Int, String, UInt64, VectorStroke

### Community 7 - "StrokeCanvasView"
Cohesion: 0.09
Nodes (25): StrokeInput, TimeInterval, UITouch, UIView, NSCoder, StrokeCanvasView, .brush, .isNoScratchRole (+17 more)

### Community 8 - "bash"
Cohesion: 0.06
Nodes (56): agent, orchestrator, worker-bugfix, worker-feature, worker-integration, worker-research, worker-test, worker-ui (+48 more)

### Community 9 - "ProjectBackupManager"
Cohesion: 0.11
Nodes (22): DateFormatter, name, ProjectBackup, .id, ProjectBackupManager, .backupsRootDirectory, .currentAppSignature, .documentsDirectory (+14 more)

### Community 10 - "CGPoint"
Cohesion: 0.13
Nodes (7): CGPoint, .length, LatticeLogicTests, Int, StaticString, String, UInt

### Community 11 - "ColorPickerPanel"
Cohesion: 0.07
Nodes (37): Palette, PaletteColor, .color, PaletteStore, .palettes, .selectedIndex, .selectedPalette, .selectedPaletteID (+29 more)

### Community 12 - "CanvasManager"
Cohesion: 0.05
Nodes (40): CanvasManager, .activeLayerIsVector, .activeLayerKind, .availableBrushes, .availableEraserBrushes, .contentEndFrame, .currentFrame, .currentLayerIndex (+32 more)

### Community 13 - "CanvasManager"
Cohesion: 0.09
Nodes (26): Void, CanvasManager, FloatingPiece, .transformedBounds, FloatingPieceKind, duplicate, move, FloatingTransform (+18 more)

### Community 14 - ".setCelLayout"
Cohesion: 0.12
Nodes (4): Int, CelCRUDCharacterizationTests, CanvasManager, Int

### Community 15 - "VectorSample"
Cohesion: 0.17
Nodes (10): Brush, VectorSample, .point, Sweep, Bool, CGRect, ClosedRange, Double (+2 more)

### Community 16 - "PointCloudIndex"
Cohesion: 0.12
Nodes (15): ARAPRegistration, Constraint, Matching, bidirectional, sourceToTarget, Options, PointCloudIndex, .isEmpty (+7 more)

### Community 17 - "VectorEraserLogicTests"
Cohesion: 0.11
Nodes (6): ClosedRange, StaticString, UInt, VectorStroke, VectorEraserLogicTests, .horizontalRun

### Community 18 - "Lattice"
Cohesion: 0.09
Nodes (22): vertices, DeformedCellIndex, Hit, Lattice, .cellCount, .currentBounds, .restBounds, .restConfiguration (+14 more)

### Community 19 - "BrushEngineLogicTests"
Cohesion: 0.14
Nodes (12): BrushEngineLogicTests, Any, CodableColor, Data, Double, Int, String, T (+4 more)

### Community 20 - ".transparentFormat"
Cohesion: 0.11
Nodes (20): IntPoint, PixelOps, Bool, Cel, CGPath, CGRect, CGSize, Color (+12 more)

### Community 21 - "AnimationTimeline"
Cohesion: 0.07
Nodes (32): Content, Gesture, AnimationTimeline, .blockMenu, .collapsedBar, .contentHeight, .dragHandle, .frameLabel (+24 more)

### Community 22 - "ViewPreset"
Cohesion: 0.18
Nodes (9): CanvasManager, .activeViewName, Int, String, viewPresets, Bool, String, UUID (+1 more)

### Community 23 - "BrushBlendMode"
Cohesion: 0.08
Nodes (23): BrushBlendMode, .cgBlendMode, darken, .id, lighten, multiply, normal, screen (+15 more)

### Community 24 - "CanvasManager"
Cohesion: 0.12
Nodes (15): CanvasManager, FillKey, Bool, Cel, Float, Int, Layer, SIMD4 (+7 more)

### Community 25 - "RasterLayerTexture"
Cohesion: 0.13
Nodes (13): RasterLayerTexture, .dabGradientCacheHits, .dabGradientCacheMisses, .hasContent, .strokeDirtyRect, Bool, CGRect, CGSize (+5 more)

### Community 26 - "InterpolationRenderLogicTests"
Cohesion: 0.08
Nodes (30): CGPathElementType, Direction, backward, forward, fromRest, Evaluation, GroupWarp, InterpolationEvaluator (+22 more)

### Community 27 - "SaveSnapshot"
Cohesion: 0.15
Nodes (18): BrushLibrary, .customBrushesDirectory, URL, CelContent, LayerContent, ProjectStore, .projectsDirectory, ProjectSummary (+10 more)

### Community 28 - "StrokeGeometryLogicTests"
Cohesion: 0.09
Nodes (7): Intersection, StrokeGeometryLogicTests, .fixedBrush, .ramp, StaticString, String, UInt

### Community 29 - "InterpolationModelLogicTests"
Cohesion: 0.10
Nodes (10): InterpolationModelLogicTests, CanvasManager, Data, Set, String, T, URL, UUID (+2 more)

### Community 30 - "VectorImageElement"
Cohesion: 0.18
Nodes (10): ContentProvider, CGSize, UIImage, RenderQuality, full, preview, CGContext, LayerTransform (+2 more)

### Community 31 - "UIKit"
Cohesion: 0.09
Nodes (6): CoreGraphics, Darwin, LayerTransform, ThumbnailRenderer, UIKit, XCTest

### Community 32 - "ARAPLogicTests"
Cohesion: 0.12
Nodes (10): ARAPInterpolation, Interpolator, Options, Bool, ARAPLogicTests, .rigidMotionL, Int, StaticString (+2 more)

### Community 33 - "Coordinator"
Cohesion: 0.11
Nodes (17): AppliedTool, Coordinator, CanvasManager, CGSize, Color, Date, Double, NSLayoutConstraint (+9 more)

### Community 34 - ".group"
Cohesion: 0.18
Nodes (7): Group, MotionGrouping, Options, Bool, Int, Set, groups

### Community 35 - ".activeCelIndex"
Cohesion: 0.13
Nodes (12): .interpolationTarget, CanvasManager, Bool, Int, Cel, .endFrame, Int, UIImage (+4 more)

### Community 36 - "ShapeGeometry"
Cohesion: 0.05
Nodes (33): CaseIterable, Int, Corner, bottomLeft, bottomRight, topLeft, topRight, Edge (+25 more)

### Community 37 - "PlaybackBoundsCharacterizationTests"
Cohesion: 0.13
Nodes (4): PlaybackBoundsCharacterizationTests, Bool, CanvasManager, Int

### Community 38 - "DeformFactorization"
Cohesion: 0.11
Nodes (14): Accelerate, DeformDataRow, DeformEdgeTerm, DeformFactorization, Matrix2x2, .determinant, .isFinite, .polar (+6 more)

### Community 39 - "Codable"
Cohesion: 0.14
Nodes (28): Codable, LayerKind, compositing, raster, vector, CelManifest, CodableColor, FolderManifest (+20 more)

### Community 40 - "StrokeSpatialIndex"
Cohesion: 0.14
Nodes (12): Int64, SegmentRef, StrokeSpatialIndex, .count, .isEmpty, Bool, CGRect, Int (+4 more)

### Community 41 - "StrokeGeometry"
Cohesion: 0.14
Nodes (8): Capsule, .boundingBox, StrokeGeometry, Bool, CGRect, ClosedRange, Int, SplitRun

### Community 42 - "GuideOverlayView"
Cohesion: 0.12
Nodes (16): Editing, handles, none, spacing, Grip, Guide, GuideOverlayView, CGPath (+8 more)

### Community 43 - "LayerTreeCharacterizationTests"
Cohesion: 0.17
Nodes (10): CanvasFixture, CanvasManager, Layer, StaticString, String, UInt, UUID, LayerTreeCharacterizationTests (+2 more)

### Community 44 - "MetalFillEngine"
Cohesion: 0.15
Nodes (18): Metal, MTLBuffer, MTLCommandBuffer, MTLCommandQueue, MTLComputeCommandEncoder, MTLComputePipelineState, MTLDevice, FillParams (+10 more)

### Community 45 - "CanvasManager"
Cohesion: 0.18
Nodes (13): CanvasManager, .layerStackRows, StackAnchor, bottom, folder, layer, Bool, ClosedRange (+5 more)

### Community 46 - "BackupManagerLogicTests"
Cohesion: 0.16
Nodes (7): UUID, BackupManagerLogicTests, Int, String, UInt8, URL, UUID

### Community 47 - "FillParams"
Cohesion: 0.18
Nodes (28): constant, device, float4, kernel, colourDistance(), computeWalls(), edgeDilate(), FillParams (+20 more)

### Community 48 - "FloatingPieceOverlayView"
Cohesion: 0.13
Nodes (15): FloatingTransform, FloatingPieceOverlayView, Bool, CGRect, CGSize, Int, NSCoder, UIPanGestureRecognizer (+7 more)

### Community 49 - "InterpolationRecipe"
Cohesion: 0.17
Nodes (13): Equatable, CelRef, InterpolationRecipe, .isWellFormed, .referencedCels, InterpolationReference, LocalEdit, MotionGroupBinding (+5 more)

### Community 50 - "TouchCountRecognizer"
Cohesion: 0.12
Nodes (16): StrokeGestureRecognizer, Bool, Set, UIEvent, UITouch, Void, Any, Int (+8 more)

### Community 51 - ".makeUIView"
Cohesion: 0.15
Nodes (6): LayerHostView, CanvasView, Context, Coordinator, LayerTransform, UIImageView

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
Cohesion: 0.12
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

### Community 61 - "VectorStroke"
Cohesion: 0.08
Nodes (36): CodableColor, .uiColor, DabLattice, .range, ElementData, fill, image, stroke (+28 more)

### Community 62 - "CanvasManager"
Cohesion: 0.18
Nodes (11): CanvasManager, CelDropRequest, CelDropVerdict, allowed, needsRasterization, rejected, Bool, Cel (+3 more)

### Community 63 - "LayerOptionsPanel"
Cohesion: 0.15
Nodes (18): .layerPanelRail, LayerOptionsPanel, .body, .layerIndex, .mergeTargetIndex, LayerPanel, .backgroundRow, .body (+10 more)

### Community 64 - "StructureSnapshot"
Cohesion: 0.16
Nodes (6): CanvasManager, StructureSnapshot, Int, Layer, String, guideStrokes

### Community 65 - "BlockDragCharacterizationTests"
Cohesion: 0.22
Nodes (4): BlockDragCharacterizationTests, Bool, CanvasManager, Int

### Community 67 - "CanvasManager"
Cohesion: 0.12
Nodes (11): CanvasManager, .activeShape, .activeShapePreviewImage, .isActiveShapePreviewStale, .resolvedShape, .shapeStampSpacing, Bool, String (+3 more)

### Community 68 - ".load"
Cohesion: 0.15
Nodes (15): Decodable, Cel, Layer, ManifestSkeleton, Cel, Layer, CanvasManager, MainActor (+7 more)

### Community 69 - "SelectionOverlayView"
Cohesion: 0.17
Nodes (10): SelectionOverlayView, .isCapturingGestures, Bool, CGPath, CGRect, NSCoder, UIColor, UIPanGestureRecognizer (+2 more)

### Community 70 - "GuideStroke"
Cohesion: 0.17
Nodes (10): Hashable, GuideRole, both, timing, trajectory, GuideStroke, KeyframeInterval, Bool (+2 more)

### Community 71 - "LayerRowModel"
Cohesion: 0.27
Nodes (8): LayerRowModel, .folderID, Double, Int, Set, String, UIImage, UUID

### Community 72 - ".manager"
Cohesion: 0.21
Nodes (3): CanvasManager, Cel, VectorStroke

### Community 73 - "ContentView"
Cohesion: 0.12
Nodes (14): App, task, AppScreen, editor, gallery, sizePicker, ContentView, .body (+6 more)

### Community 74 - "CodingKeys"
Cohesion: 0.10
Nodes (20): CodingKeys, brush, color, composite, elements, fill, fills, id (+12 more)

### Community 75 - "InterpolationRefusal"
Cohesion: 0.16
Nodes (14): InterpolationRefusal, alreadyInterpolated, interpolationNotEvaluable, .message, noInterpolationToGuide, notAVectorLayer, notEnoughReferences, nothingToCommit (+6 more)

### Community 76 - "Color"
Cohesion: 0.16
Nodes (10): Color, .hexString, .hsbaComponents, .rgbaComponents, Double, String, UIColor, ColorMath (+2 more)

### Community 77 - "EraserSettingsPanel"
Cohesion: 0.12
Nodes (15): .panelView, CheckerboardPattern, .body, EraserSettingsPanel, .body, .preview, .vectorModePicker, CanvasManager (+7 more)

### Community 78 - "InterpolationEngineDiagnosticsLogicTests"
Cohesion: 0.27
Nodes (3): InterpolationEngineDiagnosticsLogicTests, Registration, Int

### Community 79 - "PerfMonitor"
Cohesion: 0.15
Nodes (14): CADisplayLink, CFTimeInterval, ObservableObject, PerfHUDOverlay, .body, .hudBody, .toggleButton, .totalCelCount (+6 more)

### Community 80 - ".stampStroke"
Cohesion: 0.15
Nodes (11): BrushStamper, DabRNG, DiscardedDabTarget, Sample, Bool, CGBlendMode, ClosedRange, Double (+3 more)

### Community 81 - "CodingKeys"
Cohesion: 0.11
Nodes (18): CodingKeys, backgroundColor, canvasHeight, canvasPadding, canvasWidth, customBrushes, fps, id (+10 more)

### Community 82 - "InterpolateBar"
Cohesion: 0.13
Nodes (16): .body, InterpolateBar, .activeRecipe, .commandRow, .commands, .commitButton, .referenceButton, .referenceSummary (+8 more)

### Community 83 - "DrawingView"
Cohesion: 0.12
Nodes (14): Alignment, DrawingView, .body, .panelAlignment, Bool, CanvasManager, UUID, Void (+6 more)

### Community 84 - ".arched"
Cohesion: 0.29
Nodes (4): GuideSet, .isEmpty, Bool, UUID

### Community 85 - "CGFloat"
Cohesion: 0.14
Nodes (11): bendRatio(), cellSize(), coverage(), cShape(), polyline(), Int, CGFloat, ClosedFit (+3 more)

### Community 86 - "TimedSample"
Cohesion: 0.18
Nodes (4): TimeInterval, TimedSample, .point, TimeInterval

### Community 87 - "CanvasSizePickerView"
Cohesion: 0.14
Nodes (14): CanvasSizePickerView, .body, .height, .isValid, .width, Field, height, width (+6 more)

### Community 88 - "SwiftUI"
Cohesion: 0.18
Nodes (4): Combine, PhotosUI, QuartzCore, SwiftUI

### Community 89 - "Identifiable"
Cohesion: 0.13
Nodes (16): Identifiable, .guideChips, .motionGroupChips, GuideChip, .id, MotionGroupChip, .id, Layer (+8 more)

### Community 90 - "SideToolbar"
Cohesion: 0.17
Nodes (13): SideToolbar, .body, .isEraserMode, .isFillMode, .sliderHeight, Binding, Bool, CanvasManager (+5 more)

### Community 91 - "UndoHistory"
Cohesion: 0.21
Nodes (8): Action, Bool, Int, String, Void, UndoHistory, .canRedo, .canUndo

### Community 92 - "ObjectTransformOverlayView"
Cohesion: 0.28
Nodes (7): ObjectTransformOverlayView, CGRect, CGSize, LayerTransform, NSCoder, UIPanGestureRecognizer, Void

### Community 93 - "UIView"
Cohesion: 0.16
Nodes (11): FloatingTransform, .effectiveScaleX, .effectiveScaleY, LayerTransform, .effectiveScaleX, .effectiveScaleY, OverlayTransformProjecting, Bool (+3 more)

### Community 94 - "Foundation"
Cohesion: 0.10
Nodes (10): Foundation, Tool, eraser, fill, pen, pencil, Notification.Name, AppVersion (+2 more)

### Community 95 - "CanvasHostView"
Cohesion: 0.15
Nodes (9): CanvasHostView, .accessibilityValue, .canBecomeFirstResponder, .keyCommands, Bool, CanvasManager, String, Void (+1 more)

### Community 96 - "XCTestCase"
Cohesion: 0.22
Nodes (7): OnionSkinSource, PreviousCelOnionSkinSource, XCTestCase, OnionSkinLogicTests, Bool, UIImage, VectorStroke

### Community 97 - "GuidePath"
Cohesion: 0.22
Nodes (5): GuidePath, .end, .start, CGVector, TimeInterval

### Community 98 - "SpacingChart"
Cohesion: 0.21
Nodes (3): SpacingChart, .curve, .draggable

### Community 99 - "InterpolationPreviewKey"
Cohesion: 0.17
Nodes (8): InterpolationPreviewKey, Bool, Int, Layer, Set, UIGestureRecognizer, UIImage, UUID

### Community 100 - "Coordinator"
Cohesion: 0.22
Nodes (9): NSObject, Coordinator, LayerStackListView, CanvasManager, Coordinator, UIView, Void, UITableViewDiffableDataSource (+1 more)

### Community 101 - ".registerGroups"
Cohesion: 0.21
Nodes (5): GroupRegistration, RegistrationElement, RegistrationFrame, Cel, Int

### Community 102 - "LayerStackRow"
Cohesion: 0.17
Nodes (11): LayerStackRow, .depth, folder, .folderID, .id, .isFolder, layer, .layerIndex (+3 more)

### Community 103 - "SelectPanel"
Cohesion: 0.20
Nodes (9): SelectPanel, .body, .divider, .hasSelection, .switchIndicator, Bool, CanvasManager, String (+1 more)

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
Cohesion: 0.21
Nodes (8): IndexPath, DropTarget, between, onto, LayerStackListView.Coordinator, UIGestureRecognizerDelegate, UISwipeActionsConfiguration, UITableViewDelegate

### Community 109 - "StrokeStabilizer"
Cohesion: 0.32
Nodes (3): StrokeStabilizer, .stabilization, Double

### Community 110 - "SelectionMode"
Cohesion: 0.15
Nodes (11): CanvasManager, Bool, CGSize, UIImage, SelectionMode, automatic, .displayName, .id (+3 more)

### Community 111 - "PaintSoftware - iPad Drawing and Animation App"
Cohesion: 0.22
Nodes (9): Building and Running, Deploying to a physical iPad, Features, Known limitations / open work, License, PaintSoftware - iPad Drawing and Animation App, Project Structure, Requirements (+1 more)

### Community 112 - "BrushSettingsPanel"
Cohesion: 0.32
Nodes (7): BrushSettingsPanel, .body, .importCustomBrushRow, .preview, CanvasManager, PhotosPickerItem, String

### Community 113 - "Layer"
Cohesion: 0.25
Nodes (7): Layer, Bool, Cel, Double, String, UIImage, UUID

### Community 114 - "VectorScratchRole"
Cohesion: 0.33
Nodes (6): String, VectorScratchRole, none, overlay, replacement, .traceName

### Community 115 - "Usage Guide"
Cohesion: 0.25
Nodes (8): Animation, Canvas, Creating a Canvas, Drawing, Fill, Layers, Select & Move, Usage Guide

### Community 116 - "CutOutcome"
Cohesion: 0.29
Nodes (5): CutOutcome, cut, missed, unchanged, IntersectionDriver

### Community 117 - "Kind"
Cohesion: 0.29
Nodes (6): Kind, easeIn, easeInOut, easeOut, linear, sampled

### Community 118 - "InterpolatePanel"
Cohesion: 0.29
Nodes (6): .interpolateButton, InterpolatePanel, .body, .groupOverlayOption, .options, CanvasManager

### Community 119 - ".attach"
Cohesion: 0.26
Nodes (4): Context, UILongPressGestureRecognizer, UIPinchGestureRecognizer, UITableView

### Community 121 - "Known Issues"
Cohesion: 0.33
Nodes (6): Cleanup opportunities, Duplicate is a silent no-op against an adjacent neighbour (2026-07-28), Fill tool: the gap-closing UI test is still skipped (2026-07-21), Known Issues, Missing / stubbed, as designed, Switching brush presets resets live size/opacity (2026-07-22)

### Community 122 - "Atomic"
Cohesion: 0.47
Nodes (4): Atomic, .value, Void, Value

### Community 124 - "ProjectStore.swift"
Cohesion: 0.47
Nodes (5): CodableColor, .color, Color, .codable, CodableColor

### Community 125 - "GalleryView"
Cohesion: 0.15
Nodes (11): ProjectVersionsView, RecentlyDeletedView, .body, Void, GalleryTileView, .body, Void, GalleryView (+3 more)

### Community 126 - "What needs to change"
Cohesion: 0.40
Nodes (5): `Brush` will need grouping before it needs fields, `BrushShape` and `customTextureFileName` should become one thing, The blocker: `DabTarget` is circle-only, Two smaller notes, What needs to change

### Community 127 - "Multi-Session Protocol"
Cohesion: 0.40
Nodes (5): Build and test, Deploy to iPad, Docs, graphify, Multi-Session Protocol

### Community 128 - "parallel_test.sh"
Cohesion: 0.70
Nodes (4): claim_sim(), log(), release_sim(), parallel_test.sh script

### Community 130 - "Performance baseline"
Cohesion: 0.40
Nodes (4): Known remaining costs, Performance baseline, Traps — read before measuring anything, Where it stands

## Knowledge Gaps
- **482 isolated node(s):** `graphify-guard.sh script`, `gallery`, `sizePicker`, `editor`, `softRound` (+477 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CGFloat` connect `CGFloat` to `cels`, `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `Coordinator`, `layers`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `CGPoint`, `CanvasManager`, `CanvasManager`, `VectorSample`, `PointCloudIndex`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `BrushBlendMode`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `StrokeGeometryLogicTests`, `InterpolationModelLogicTests`, `VectorImageElement`, `UIKit`, `ARAPLogicTests`, `Coordinator`, `.group`, `ShapeGeometry`, `DeformFactorization`, `StrokeSpatialIndex`, `StrokeGeometry`, `GuideOverlayView`, `FloatingPieceOverlayView`, `InterpolationRecipe`, `.makeUIView`, `LayerStackCell`, `InterpolationGuideLogicTests`, `StrokeSettingsPanel`, `ShapeOverlayView`, `VectorStroke`, `CanvasManager`, `.indices`, `CanvasManager`, `.load`, `.manager`, `CodingKeys`, `Color`, `EraserSettingsPanel`, `InterpolationEngineDiagnosticsLogicTests`, `.stampStroke`, `InterpolateBar`, `DrawingView`, `.arched`, `TimedSample`, `SideToolbar`, `UIView`, `XCTestCase`, `GuidePath`, `SpacingChart`, `InterpolationPreviewKey`, `Coordinator`, `DabTarget`, `ActionsMenu`, `LayerStackListView.Coordinator`, `StrokeStabilizer`, `SelectionMode`, `Kind`?**
  _High betweenness centrality (0.325) - this node is a cross-community bridge._
- **Why does `CGPoint` connect `CGPoint` to `cels`, `VectorEraserHybridLogicTests`, `Coordinator`, `layers`, `VectorCanvas`, `PerfBaselineTests`, `StrokeCanvasView`, `ColorPickerPanel`, `CanvasManager`, `CanvasManager`, `VectorSample`, `PointCloudIndex`, `VectorEraserLogicTests`, `Lattice`, `BrushEngineLogicTests`, `.transparentFormat`, `AnimationTimeline`, `BrushBlendMode`, `CanvasManager`, `RasterLayerTexture`, `InterpolationRenderLogicTests`, `StrokeGeometryLogicTests`, `VectorImageElement`, `UIKit`, `ARAPLogicTests`, `Coordinator`, `.group`, `.activeCelIndex`, `ShapeGeometry`, `DeformFactorization`, `StrokeSpatialIndex`, `StrokeGeometry`, `GuideOverlayView`, `FloatingPieceOverlayView`, `InterpolationRecipe`, `.makeUIView`, `InterpolationGuideLogicTests`, `ShapeOverlayView`, `StructureSnapshot`, `.indices`, `CanvasManager`, `.load`, `SelectionOverlayView`, `.manager`, `InterpolationEngineDiagnosticsLogicTests`, `.stampStroke`, `.arched`, `CGFloat`, `TimedSample`, `ObjectTransformOverlayView`, `UIView`, `Foundation`, `GuidePath`, `.registerGroups`, `DabTarget`, `LayerStackListView.Coordinator`, `StrokeStabilizer`, `SelectionMode`?**
  _High betweenness centrality (0.210) - this node is a cross-community bridge._
- **Why does `XCTestCase` connect `XCTestCase` to `cels`, `.launchIntoEditor`, `VectorEraserHybridLogicTests`, `PerfBaselineTests`, `CGPoint`, `.setCelLayout`, `VectorEraserLogicTests`, `BrushEngineLogicTests`, `InterpolationRenderLogicTests`, `StrokeGeometryLogicTests`, `InterpolationModelLogicTests`, `UIKit`, `ARAPLogicTests`, `ShapeGeometry`, `PlaybackBoundsCharacterizationTests`, `LayerTreeCharacterizationTests`, `BackupManagerLogicTests`, `.manager`, `InterpolationGuideLogicTests`, `BlockDragCharacterizationTests`, `.load`, `InterpolationEngineDiagnosticsLogicTests`?**
  _High betweenness centrality (0.090) - this node is a cross-community bridge._
- **Are the 54 inferred relationships involving `CGPoint` (e.g. with `.init()` and `.finish()`) actually correct?**
  _`CGPoint` has 54 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `CGFloat` (e.g. with `.celInsertionIndex()` and `.load()`) actually correct?**
  _`CGFloat` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `VectorCanvas` (e.g. with `.composite()` and `.testEvictionKeepsTheCelsNearestTheCurrentFrameAndDropsTheRest()`) actually correct?**
  _`VectorCanvas` has 11 INFERRED edges - model-reasoned connections that need verification._
- **Are the 105 inferred relationships involving `layers` (e.g. with `.celDropVerdict()` and `.celInsertionIndex()`) actually correct?**
  _`layers` has 105 INFERRED edges - model-reasoned connections that need verification._