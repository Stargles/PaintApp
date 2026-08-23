import UIKit

/// The live text editor, sitting inside `CanvasView`'s `container` so it shares the canvas's own
/// pan/zoom/rotate transform and the box therefore stays glued to the artwork.
///
/// **The `UITextView` is here for the caret, not for the glyphs.** ADD_TEXT.md §1's "the overlay is
/// the editor" splits the two: the text view supplies the caret, the selection, the keyboard, the
/// system's own edit menu and — for free, because iOS attaches it itself — Scribble; the *pixels*
/// come from `TextLayout.renderBox`, the same drawing code the bake uses. That split is the only
/// thing that makes what the artist sees while typing byte-comparable to what lands when it bakes.
/// A text view drawing its own glyphs would put TextKit's line breaking on screen and CoreText's in
/// the artwork, and the two disagree at the edges.
///
/// So `textView.textColor` is `.clear` throughout. Its *metrics* still matter — the caret has to
/// land between the right two letters — so it is given the same font, kern and paragraph style. A
/// caret a fraction of a point off is invisible; glyphs that jump at commit are not.
///
/// **Nothing in the live path is canvas-sized and nothing in it allocates per frame** (§4 rules 1
/// and 2). The glyph bitmap is the *box*, re-rendered only when the recipe or the box size changes
/// and coalesced to one render per run-loop turn; a box drag assigns a frame and rasterizes nothing.
final class TextOverlayView: UIView, UITextViewDelegate {

    // MARK: - Callbacks

    /// Touch-down on the move band.
    var onDragBegan: (() -> Void)?
    /// A move in progress: the box's new top-left in canvas space.
    var onDragged: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    /// The string as the artist has it now — already coalesced to one call per run-loop turn.
    var onTextChanged: ((String) -> Void)?
    /// First-responder gained or lost. The model keeps this as `textIsFocused`, which is the third
    /// arm of `finalizePendingGesturesForHistoryAction`'s branch.
    var onFocusChanged: ((Bool) -> Void)?

    // MARK: - Chrome, in screen points
    //
    // **A handle is chrome: it belongs to the screen, not to the artwork.** This view is pinned edge
    // to edge to the canvas container, whose transform carries `fitScale * committedScale *
    // liveScale`, so anything expressed in this view's own coordinates is canvas-sized by
    // construction and shrinks as the artist zooms out. Every constant below is a *screen*-point
    // figure divided back out by `canvasScale`, which is `ShapeOverlayView`'s rule and the fix for
    // the "faint blue line, does not have nodes in it" bug `TransformHandleView` still carries.

    /// How far outside the box a touch still counts as "grab the box to move it", in screen points.
    /// Comfortably past the 44 pt guidance is wrong here — the band surrounds a box that may be
    /// small, and too wide a band swallows the taps that should be placing the *next* box.
    private static let moveBandScreenPoints: CGFloat = 22
    private static let outlineScreenWidth: CGFloat = 1
    private static let dashScreenLength: CGFloat = 6

    /// Screen points per canvas point, pushed from the coordinator on every transform change.
    var canvasScale: CGFloat = 1 {
        didSet {
            guard canvasScale != oldValue else { return }
            applyOutlineStyle()
            scheduleGlyphRender()
        }
    }

    private var moveBand: CGFloat { Self.moveBandScreenPoints / max(canvasScale, 0.01) }

    // MARK: - Subviews

    /// The caret, the selection, the keyboard and Scribble. Not the glyphs — see the class comment.
    let textView: UITextView = {
        let view = UITextView()
        view.backgroundColor = .clear
        view.textColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        // Off, deliberately. On an iPad the artist has typed straight quotes into a label and wants
        // straight quotes; smart substitution turns them into curly ones after the fact, which reads
        // as the app changing what was typed.
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.layer.borderWidth = 0
        view.accessibilityIdentifier = "canvas.textEditor"
        return view
    }()

    private let glyphLayer = CALayer()
    private let outlineLayer = CAShapeLayer()

    // MARK: - State

    private(set) var isActive = false
    private var frameModel = TextFrame(origin: .zero, size: .zero)
    private var recipe = TextRecipe()
    /// The style the text view's attributes were last built for, so a keystroke does not rebuild
    /// them and move the caret. See `TextRecipe.styleOnly`.
    private var appliedStyle: TextRecipe?
    /// What the glyph bitmap was rendered for. `nil` forces a render.
    private var renderedKey: RenderKey?
    private var isGlyphRenderScheduled = false
    private var isTextChangeScheduled = false
    /// The canvas-space point under the finger when the move drag began, and where the box's
    /// top-left was then. Both latched at touch-down so a mid-drag pinch cannot move the reference
    /// frame under the gesture — `ShapeOverlayView`'s discipline.
    private var dragTouchStart: CGPoint?
    private var dragOriginStart: CGPoint?

    private struct RenderKey: Equatable {
        let recipe: TextRecipe
        let boxSize: CGSize
        let clip: Bool
        let scale: CGFloat
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isHidden = true
        isUserInteractionEnabled = false

        glyphLayer.anchorPoint = .zero
        glyphLayer.position = .zero
        glyphLayer.magnificationFilter = .linear
        // A warped edge aliases hard without this. Stage 1 never warps, but the flag costs nothing
        // and Stage 5 would otherwise have to remember it.
        glyphLayer.allowsEdgeAntialiasing = true
        layer.addSublayer(glyphLayer)

        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.9).cgColor
        layer.addSublayer(outlineLayer)

        textView.delegate = self
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Driving it

    /// The whole of the view's public surface. Called from `CanvasView.Coordinator.updateTextOverlay`
    /// on every SwiftUI pass, so it must be cheap when nothing changed — which is why every
    /// expensive step below is behind an equality check.
    func update(isActive: Bool, frame frameModel: TextFrame, recipe: TextRecipe, canvasScale: CGFloat) {
        self.canvasScale = canvasScale
        guard isActive else {
            deactivate()
            return
        }
        if !self.isActive {
            self.isActive = true
            isHidden = false
            isUserInteractionEnabled = true
            appliedStyle = nil          // force a rebuild of the text view's attributes
            renderedKey = nil
        }
        self.frameModel = frameModel
        self.recipe = recipe

        applyFrameGeometry()
        applyOutlineStyle()

        if appliedStyle != recipe.styleOnly {
            appliedStyle = recipe.styleOnly
            applyTypingAttributes()
        }
        if textView.text != recipe.string {
            // Only ever true when the *model* changed the string — session start, or an undo that
            // reached past the keyboard's own stack. A keystroke never lands here, because
            // `textViewDidChange` pushed that string to the model in the first place.
            textView.text = recipe.string
            applyTypingAttributes()
        }
        scheduleGlyphRender()
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        isHidden = true
        isUserInteractionEnabled = false
        if textView.isFirstResponder { textView.resignFirstResponder() }
        textView.text = ""
        glyphLayer.contents = nil
        outlineLayer.path = nil
        renderedKey = nil
        appliedStyle = nil
        dragTouchStart = nil
        dragOriginStart = nil
    }

    /// Focuses the caret. The model asks for this on the placement tap, so the keyboard comes up
    /// with the box rather than after a second tap on it.
    @discardableResult
    func focusEditor() -> Bool {
        guard isActive else { return false }
        return textView.becomeFirstResponder()
    }

    /// Drops the keyboard. Installed on `CanvasManager.textFocusResigner`, so the model can do this
    /// without knowing what a first responder is.
    func resignEditor() {
        guard textView.isFirstResponder else { return }
        textView.resignFirstResponder()
    }

    /// Installed on `CanvasManager.textEditUndoHandler`. Returns true when the keyboard's own undo
    /// stack took the action — ADD_TEXT.md §5.1, the owner's decision that undo while you are typing
    /// undoes the typing.
    ///
    /// Returning **false on an empty stack** is what makes "only once you tap away does undo remove
    /// the whole text object" arrive one step early instead of never: undoing past the start of the
    /// typing falls through to the drawing history, whose next step is the text object itself.
    func handleEditUndo(isRedo: Bool) -> Bool {
        guard isActive, textView.isFirstResponder, let manager = textView.undoManager else { return false }
        if isRedo {
            guard manager.canRedo else { return false }
            manager.redo()
        } else {
            guard manager.canUndo else { return false }
            manager.undo()
        }
        // `UITextView` does not reliably call its delegate for an undo, so the model is told here
        // rather than waited on. Without this the string the bake uses is the pre-undo one.
        pushTextToModel()
        return true
    }

    // MARK: - Geometry

    /// Places the glyph bitmap and the caret's text view on the frame's quad.
    ///
    /// **Both are sized to the *layout box* and carried by the frame's own affine map**, rather than
    /// laid out in the frame's bounding rectangle. That is stage 4's whole visual change: a box the
    /// artist has turned shows its type turned, and it shows it through the same matrix
    /// `TextLayout.render` bakes with, so what is on screen is what lands.
    ///
    /// ADD_TEXT.md §1 "Typing in a distorted box happens unwarped" is the rule this obeys: while
    /// `mode == .affine` — every frame stage 4 can make — you edit *in place under the affine
    /// transform*, caret and all. Only `.projective` springs back to flat for typing, and that is
    /// stage 5's.
    ///
    /// A `UIView`'s `transform` is applied about its centre, so the text view is placed by
    /// `bounds`/`center`/`transform` and never by `frame` — assigning `frame` to a transformed view
    /// is undefined, and the caret would land somewhere unrelated to the words. The centre is the
    /// box's own middle carried through the map, which is exactly what cancels the recentring.
    private func applyFrameGeometry() {
        let box = frameModel.boundingBox
        let transform = frameModel.affineTransform
        let boxSize = transform == nil ? box.size : frameModel.size

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.bounds = CGRect(origin: .zero, size: boxSize)
        // `anchorPoint` and `position` are both zero, so the layer-to-superlayer map *is* the
        // transform and local (0,0) lands on the frame's top-left corner.
        glyphLayer.setAffineTransform(transform ?? CGAffineTransform(translationX: box.minX, y: box.minY))
        CATransaction.commit()

        textView.transform = .identity
        textView.bounds = CGRect(origin: .zero, size: boxSize)
        if let transform {
            let middle = CGPoint(x: boxSize.width / 2, y: boxSize.height / 2).applying(transform)
            // The linear part only: the translation is carried by `center`, and applying it twice
            // would put the caret one box-width away from the glyphs.
            textView.transform = CGAffineTransform(a: transform.a, b: transform.b,
                                                   c: transform.c, d: transform.d, tx: 0, ty: 0)
            textView.center = middle
        } else {
            textView.center = CGPoint(x: box.midX, y: box.midY)
        }
    }

    // MARK: - Style

    private func applyTypingAttributes() {
        let font = TextLayout.resolvedFont(for: recipe).font
        let template = TextLayout.attributedString(recipe, font: font)
        var attributes: [NSAttributedString.Key: Any] = template.length > 0
            ? template.attributes(at: 0, effectiveRange: nil)
            : [.font: font]
        // The one attribute deliberately *not* taken from the recipe. The glyphs on screen are the
        // bitmap below this view; the text view draws only the caret and the selection.
        attributes[.foregroundColor] = UIColor.clear
        textView.typingAttributes = attributes
        let selected = textView.selectedRange
        textView.attributedText = NSAttributedString(string: textView.text, attributes: attributes)
        textView.selectedRange = NSRange(location: min(selected.location, textView.text.count),
                                         length: 0)
        textView.textAlignment = TextLayout.nsAlignment(recipe.typography.clamped.alignment)
        // The caret takes the text's own colour, which is the one place the recipe's colour is
        // visible in this view. A clear caret over clear glyphs would leave nothing to aim with.
        textView.tintColor = UIColor(red: CGFloat(recipe.color.red), green: CGFloat(recipe.color.green),
                                     blue: CGFloat(recipe.color.blue), alpha: 1)
    }

    /// A pristine box draws a dashed outline, a sized box a solid one — ADD_TEXT.md §1, and it is
    /// the artist's only signal that the box has stopped growing and started clipping.
    private func applyOutlineStyle() {
        guard isActive else { return }
        outlineLayer.frame = bounds
        // The quad, not the bounding rectangle — stage 4 turns boxes, and an axis-aligned outline
        // around a turned one is a rectangle drawn where the text is not.
        outlineLayer.path = Self.outlinePath(for: frameModel)
        outlineLayer.lineWidth = Self.outlineScreenWidth / max(canvasScale, 0.01)
        if frameModel.autoSize {
            let dash = Self.dashScreenLength / max(canvasScale, 0.01)
            outlineLayer.lineDashPattern = [NSNumber(value: Double(dash)), NSNumber(value: Double(dash))]
        } else {
            outlineLayer.lineDashPattern = nil
        }
    }

    private static func outlinePath(for frame: TextFrame) -> CGPath {
        let corners = frame.corners
        guard corners.count == 4 else { return CGPath(rect: frame.boundingBox, transform: nil) }
        let path = CGMutablePath()
        path.move(to: corners[0])
        path.addLine(to: corners[1])
        path.addLine(to: corners[2])
        path.addLine(to: corners[3])
        path.closeSubpath()
        return path
    }

    // MARK: - Glyphs

    /// Backing pixels per canvas point for the glyph bitmap, capped twice.
    ///
    /// Capped at 3× because past that the artist cannot see the difference and the backing store is
    /// the square of it, and capped again so the store cannot exceed `maximumGlyphTexels` on its
    /// longest side however far they zoom — ADD_TEXT.md §4's rule that nothing in the live path is
    /// canvas-sized only holds if the box's own store is bounded too.
    ///
    /// **The texel cap is applied last and is allowed to take the answer below 1**, which stage 4
    /// changed. It used to be floored at 1, and that floor was invisible only because stage 1's
    /// `autoSize` capped a box at the canvas's right edge. Stage 4 removed that cap — a point-text
    /// box now grows as wide as the string — so a floor of 1 would let a long title mint a bitmap as
    /// many pixels across as it is canvas points. `TextLayout.renderBox` honours a sub-1 scale for
    /// exactly this.
    private var glyphContentsScale: CGFloat {
        let display = max(traitCollection.displayScale, 1)
        let wanted = max(1, min(canvasScale * display, 3 * display))
        let longest = max(glyphBoxSize.width, glyphBoxSize.height, 1)
        return max(TextLayout.minimumRenderScale, min(wanted, Self.maximumGlyphTexels / longest))
    }

    /// The bitmap is the *layout box*, not the frame's bounding rectangle: the rotation is carried
    /// by the layer's transform, so rendering the bounding box would rasterize the box's own
    /// diagonal and then rotate that.
    private var glyphBoxSize: CGSize {
        frameModel.affineTransform == nil ? frameModel.boundingBox.size : frameModel.size
    }

    private static let maximumGlyphTexels: CGFloat = 4096

    /// Coalesces glyph re-renders to one per run-loop turn. A fast typist delivers several
    /// keystrokes per frame and each would otherwise cost a CoreText pass and a bitmap — ADD_TEXT.md
    /// §4 rule 3, which is `scheduleShapePreviewRenderIfNeeded`'s rule with a different subject.
    private func scheduleGlyphRender() {
        guard isActive, !isGlyphRenderScheduled else { return }
        isGlyphRenderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isGlyphRenderScheduled = false
            self.renderGlyphsIfNeeded()
        }
    }

    private func renderGlyphsIfNeeded() {
        guard isActive else { return }
        let key = RenderKey(recipe: recipe, boxSize: glyphBoxSize, clip: !frameModel.autoSize,
                            scale: glyphContentsScale)
        guard key != renderedKey else { return }
        renderedKey = key
        guard let image = TextLayout.renderBox(recipe: key.recipe, boxSize: key.boxSize,
                                               clip: key.clip, scale: key.scale) else {
            glyphLayer.contents = nil
            return
        }
        // No implicit animation: the bitmap is the artwork, and a cross-fade on every keystroke
        // reads as lag.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.contentsScale = key.scale
        glyphLayer.contents = image.cgImage
        CATransaction.commit()
    }

    // MARK: - Hit testing

    /// Claims **only** the box and the move band around it. Everything else falls through to the
    /// canvas underneath, which is what lets a tap somewhere else place the next box — the touch
    /// commits this one on its way past (`beginTextSession` → `beginCanvasEdit`) and places the new
    /// one, instead of being swallowed as a dismiss the artist then has to follow with a second tap.
    /// `ShapeOverlayView` makes itself transparent for the same reason.
    /// **The ownership half of `hitTest`, asked on its own.** `hitTest` answers two questions at
    /// once — *is this touch mine* and *which view of mine is hit* — and only the first is the
    /// arbitration this canvas gets wrong. Split out, it is what `CanvasView.Coordinator.canvasChrome(at:)`
    /// asks to build `CanvasTouchInputs.chrome`, so the five overlays' claims reach the one function
    /// that says who owns a touch instead of each being re-derived by whoever needs to know. The
    /// geometry stays here, untouched.
    ///
    /// The box **and** its move band, which is the whole of what this view claims — the split
    /// between them decides *which* view `hitTest` returns, not whether the touch is ours.
    func claimsTouch(at point: CGPoint) -> Bool {
        guard isActive, !isHidden, isUserInteractionEnabled else { return false }
        return frameModel.contains(point) || frameModel.contains(point, slop: moveBand)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard claimsTouch(at: point) else { return nil }
        // The quad and a collar around it, not the bounding rectangle — the same predicate the
        // display list's re-open query uses (`TextFrame.contains`), so tapping the empty corner of a
        // turned box is tapping the canvas, exactly as it is when the object is committed.
        if frameModel.contains(point) {
            // Inside the box is the text view's: tap to place the caret, and Scribble to write into
            // it. The band is what moves the box.
            //
            // Delegated to the text view's own `hitTest` rather than returned directly. `UITextView`
            // keeps its selection and Scribble recognizers on private subviews, and a hit test that
            // stops at the text view hands those touches to the wrong responder — the caret still
            // places, but drag-to-select and Scribble quietly stop working. Falling back to the text
            // view itself covers the case where it declines its own bounds.
            return textView.hitTest(convert(point, to: textView), with: event) ?? textView
        }
        if frameModel.contains(point, slop: moveBand) { return self }
        return nil
    }

    // MARK: - Moving the box
    //
    // Raw touches rather than a pan recognizer, so the drag bites on the first pixel of movement
    // instead of after a recognizer's ~10 pt of slop — `ShapeOverlayView`'s third discipline, and it
    // matters more here because the thing being dragged is a thin band.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isActive, let touch = touches.first else { return }
        dragTouchStart = touch.location(in: self)
        dragOriginStart = frameModel[.topLeft]
        onDragBegan?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let start = dragTouchStart, let origin = dragOriginStart else { return }
        let now = touch.location(in: self)
        onDragged?(CGPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    private func endDrag() {
        guard dragTouchStart != nil else { return }
        dragTouchStart = nil
        dragOriginStart = nil
        onDragEnded?()
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        // Coalesced for the reason `scheduleGlyphRender` is, and one turn is enough: the model call
        // triggers a SwiftUI pass, which comes back through `update` and schedules the render.
        guard !isTextChangeScheduled else { return }
        isTextChangeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isTextChangeScheduled = false
            self.pushTextToModel()
        }
    }

    private func pushTextToModel() {
        onTextChanged?(textView.text ?? "")
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        onFocusChanged?(true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        // Flushed synchronously rather than through the coalescing turn: focus is leaving, and the
        // very next thing that happens is usually the commit reading `textRecipe.string`.
        isTextChangeScheduled = false
        pushTextToModel()
        onFocusChanged?(false)
    }
}
