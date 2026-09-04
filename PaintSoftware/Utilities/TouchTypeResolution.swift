import UIKit

/// Which touch type a `touchesBegan(_:with:)` set resolves to, for a recognizer that only cares
/// about "was the pencil among these touches" — pencil wins the tie even though `Set<UITouch>`
/// iterates in no defined order, because the fact that matters is "the artist's pen is down", not
/// which member of the set UIKit happened to store first. An artist's off-hand can rest on the
/// glass while the pencil draws, and that resting contact must not flip `lastTouchType` to `.direct`.
///
/// Used by `SelectionOverlayView`'s `TouchTypePanGestureRecognizer`/`TouchTypeTapGestureRecognizer`.
/// `TouchTypePressRecognizer.touchesBegan` in CanvasView.swift applies the identical rule inline;
/// not shared with it because that recognizer predates this pair and touching it is out of scope
/// for the lasso pencil-only-mode fix this exists for.
///
/// Pulled out as its own file, as a function of bare `UITouch.TouchType` values rather than `UITouch`
/// itself, purely so it is unit-testable: nothing outside UIKit can construct a `UITouch`, so a
/// function that needed the touches themselves could only be exercised by a live gesture — the same
/// limitation `StrokePathFitLogicTests` notes for its own domain. Living in its own
/// UIKit-only/CoreGraphics-only file (no `View`, no `App`) is what lets it join the "App sources
/// shared with PaintSoftwareUITests" group in the project file and be tested headlessly, the same
/// arrangement `StrokeGeometry.swift`/`VectorEraser.swift` use — see `BrushEngineLogicTests`'s doc
/// comment for why `@testable import PaintSoftware` doesn't work for a `bundle.ui-testing` product.
///
/// Returns `nil` for an empty set, which callers treat as "leave `lastTouchType` at whatever it
/// already was" — mirroring `TouchTypePressRecognizer`, which also only overwrites on a non-empty set.
func resolvedLastTouchType<S: Sequence>(from types: S) -> UITouch.TouchType? where S.Element == UITouch.TouchType {
    var first: UITouch.TouchType?
    for type in types {
        if first == nil { first = type }
        if type == .pencil { return type }
    }
    return first
}
