import CoreGraphics
import Foundation

// ADD_TEXT.md §1 "The object stores a recipe, never a result", in code.
//
// Nothing derived is stored here: not glyph positions, not measured bounds, not a warped bitmap,
// not the 3×3 matrix. `TextLayout` computes all of that from these values every time it is asked,
// which is what makes a re-edit survive — retype the string, change the font, change the size, and
// the glyphs re-lay-out into the same box and land in the same place, because the result was never
// baked into anything. It is the derived-recipe discipline VECTOR_INTERPOLATION.md already uses.
//
// **Every type in this file hand-writes `init(from:)`.** Synthesized `Decodable` ignores property
// defaults and throws on a missing key, so a document written by today's build would fail to decode
// the moment a field is added — the reason `VectorStroke` already does this (`VectorLayer.swift:29`).
// There is no `formatVersion` anywhere in this project and this feature does not add one;
// compatibility is per-field `decodeIfPresent` with a default, and `TextRecipeCodableLogicTests`
// pins that a blob missing *every* key still decodes.
//
// Foundation + CoreGraphics only, no UIKit — so it compiles into `PaintSoftwareUITests` alongside
// the rest of the "App sources shared with" group and the layout tests can reach it headlessly.

// MARK: - Which font

/// A font named the way a *document* names one, not the way a running process does.
///
/// **Qualified by pack** (`packID`), so two packs shipping "Inter" cannot collide and a font that
/// has gone missing is diagnosable rather than mysterious. `nil` means the built-in
/// `SystemFontProvider`; `FontLibrary` maps it to `SystemFontProvider.providerID`.
///
/// **The traits are stored rather than parsed back out of `faceName`.** They are what
/// `FontLibrary.resolve`'s middle step matches on: if the exact face is gone but the family is
/// still installed, "the bold one" is a question that can be answered, where "Inter-SemiBold" as a
/// string is not. Parsing weight out of a PostScript name works until it meets a foundry that names
/// its faces differently, which is every third foundry.
struct FontDescriptor: Codable, Equatable, Hashable {
    /// As `UIFont.familyNames` spells it, e.g. "Helvetica Neue" — or `FontDescriptor.systemFamilyName`
    /// for San Francisco, which does not appear in that list at all.
    var familyName: String
    /// The PostScript name of the exact face, e.g. "HelveticaNeue-BoldItalic". `nil` asks for
    /// whatever face the family calls its regular.
    var faceName: String?
    /// Which provider the family belongs to. `nil` is the system.
    var packID: String?
    var isBold: Bool
    var isItalic: Bool

    /// San Francisco's stand-in family name. `UIFont.familyNames` deliberately omits the system
    /// font (its real family is `.AppleSystemUIFont`, a private name that is not stable across OS
    /// versions), so it is surfaced under a distinguished name of our own rather than buried
    /// alphabetically or missing. See `SystemFontProvider.uiFont`.
    static let systemFamilyName = "System"

    static let system = FontDescriptor(familyName: systemFamilyName)

    init(familyName: String = FontDescriptor.systemFamilyName, faceName: String? = nil,
         packID: String? = nil, isBold: Bool = false, isItalic: Bool = false) {
        self.familyName = familyName
        self.faceName = faceName
        self.packID = packID
        self.isBold = isBold
        self.isItalic = isItalic
    }

    private enum CodingKeys: String, CodingKey { case familyName, faceName, packID, isBold, isItalic }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        familyName = try c.decodeIfPresent(String.self, forKey: .familyName) ?? FontDescriptor.systemFamilyName
        faceName = try c.decodeIfPresent(String.self, forKey: .faceName)
        packID = try c.decodeIfPresent(String.self, forKey: .packID)
        isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
    }
}

// MARK: - How it is set

/// Every knob the settings panel exposes that is about *type*, in one defaulted sub-struct.
///
/// Grouped from day one rather than flattened onto `TextRecipe`, which is the generalizable lesson
/// BRUSH_ENGINE_EXTENSIBILITY.md extracts from `Brush`'s `dynamics`/`grain`/`taper`: every flat
/// scalar is a Codable-compatibility question later, and a sub-struct answers it once for the whole
/// group. `outline` and `shadow`, when they arrive, are their own structs beside this one.
struct Typography: Codable, Equatable {

    /// Where each line sits inside the box's width. A segmented `Picker` in the panel
    /// (`EraserSettingsPanel.vectorModePicker`'s shape), because four short mutually-exclusive
    /// options with a current value is exactly what that control is.
    ///
    /// **`.natural` is deliberately absent.** It resolves against the *user interface* language, so
    /// the same document would lay out differently on two iPads — a document property must not
    /// depend on a device setting.
    enum Alignment: String, Codable, CaseIterable, Identifiable {
        case left, center, right, justified

        var id: String { rawValue }

        /// Label for the segmented control. Short enough to fit four across a 300 pt panel.
        var displayName: String {
            switch self {
            case .left: return "Left"
            case .center: return "Center"
            case .right: return "Right"
            case .justified: return "Justify"
            }
        }
    }

    /// Canvas points, not screen points — the box lives in canvas space, so 48 here is 48 canvas
    /// pixels tall whatever the zoom is.
    var pointSize: CGFloat
    /// Extra space after every character, in canvas points. CoreText's `kern`. Negative tightens.
    var tracking: CGFloat
    /// Multiplier on each line's natural height. 1 is the font's own leading.
    var lineHeightMultiple: CGFloat
    /// Extra points between lines *within* a paragraph, on top of `lineHeightMultiple`.
    var lineSpacing: CGFloat
    /// Extra points between paragraphs — i.e. after a line that ends in a newline.
    var paragraphSpacing: CGFloat
    var alignment: Alignment

    init(pointSize: CGFloat = Typography.defaultPointSize, tracking: CGFloat = 0,
         lineHeightMultiple: CGFloat = 1, lineSpacing: CGFloat = 0, paragraphSpacing: CGFloat = 0,
         alignment: Alignment = .left) {
        self.pointSize = pointSize
        self.tracking = tracking
        self.lineHeightMultiple = lineHeightMultiple
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.alignment = alignment
    }

    /// Large enough to read at a typical fit-to-screen zoom on a 2048² canvas, which is where the
    /// artist first meets it. A 17 pt default (the UI body size) is a speck on the artwork.
    static let defaultPointSize: CGFloat = 64

    /// Panel slider bounds, stated here rather than in the view so a test can reach them and so the
    /// clamp and the slider cannot drift apart.
    static let pointSizeRange: ClosedRange<CGFloat> = 8...512
    static let trackingRange: ClosedRange<CGFloat> = -20...40
    static let lineHeightRange: ClosedRange<CGFloat> = 0.5...3
    static let lineSpacingRange: ClosedRange<CGFloat> = -20...80
    static let paragraphSpacingRange: ClosedRange<CGFloat> = 0...200

    private enum CodingKeys: String, CodingKey {
        case pointSize, tracking, lineHeightMultiple, lineSpacing, paragraphSpacing, alignment
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pointSize = try c.decodeIfPresent(CGFloat.self, forKey: .pointSize) ?? Typography.defaultPointSize
        tracking = try c.decodeIfPresent(CGFloat.self, forKey: .tracking) ?? 0
        lineHeightMultiple = try c.decodeIfPresent(CGFloat.self, forKey: .lineHeightMultiple) ?? 1
        lineSpacing = try c.decodeIfPresent(CGFloat.self, forKey: .lineSpacing) ?? 0
        paragraphSpacing = try c.decodeIfPresent(CGFloat.self, forKey: .paragraphSpacing) ?? 0
        alignment = try c.decodeIfPresent(Alignment.self, forKey: .alignment) ?? .left
    }

    /// Every scalar forced back inside its panel range. Applied at decode-adjacent boundaries
    /// rather than in the setters: a hand-edited or future-written document can carry anything, and
    /// a `lineHeightMultiple` of 0 makes CoreText lay every line on top of the last.
    var clamped: Typography {
        var t = self
        t.pointSize = min(max(pointSize, Typography.pointSizeRange.lowerBound), Typography.pointSizeRange.upperBound)
        t.tracking = min(max(tracking, Typography.trackingRange.lowerBound), Typography.trackingRange.upperBound)
        t.lineHeightMultiple = min(max(lineHeightMultiple, Typography.lineHeightRange.lowerBound),
                                   Typography.lineHeightRange.upperBound)
        t.lineSpacing = min(max(lineSpacing, Typography.lineSpacingRange.lowerBound),
                            Typography.lineSpacingRange.upperBound)
        t.paragraphSpacing = min(max(paragraphSpacing, Typography.paragraphSpacingRange.lowerBound),
                                 Typography.paragraphSpacingRange.upperBound)
        return t
    }
}

/// What the text *is*: string, font reference, typography, colour, opacity. Not where it sits —
/// that is `TextFrame`.
///
/// Colour is a `CodableColor` for the reason every other persisted colour in this project is one:
/// `UIColor` does not round-trip through JSON and `Color` is not `Codable` at all.
struct TextRecipe: Codable, Equatable {
    var string: String
    var font: FontDescriptor
    var typography: Typography
    var color: CodableColor
    var opacity: Double

    init(string: String = "", font: FontDescriptor = .system, typography: Typography = Typography(),
         color: CodableColor = TextRecipe.defaultColor, opacity: Double = 1) {
        self.string = string
        self.font = font
        self.typography = typography
        self.color = color
        self.opacity = opacity
    }

    static let defaultColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)

    /// This recipe with its string emptied — the identity of everything *about* the type and
    /// nothing about the words.
    ///
    /// The live overlay compares against it to tell "the artist typed a character" from "the artist
    /// moved a slider": the first must not disturb the caret, the second has to rebuild the whole
    /// attributed string. Without the distinction, every keystroke rewrites the text view's
    /// attributes and the caret jumps to the end of the line.
    var styleOnly: TextRecipe {
        var copy = self
        copy.string = ""
        return copy
    }

    private enum CodingKeys: String, CodingKey { case string, font, typography, color, opacity }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        string = try c.decodeIfPresent(String.self, forKey: .string) ?? ""
        font = try c.decodeIfPresent(FontDescriptor.self, forKey: .font) ?? .system
        typography = try c.decodeIfPresent(Typography.self, forKey: .typography) ?? Typography()
        color = try c.decodeIfPresent(CodableColor.self, forKey: .color) ?? TextRecipe.defaultColor
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
    }
}

// MARK: - Where it sits

/// The domain and the codomain of one map: a local layout box `size`, and the four canvas-space
/// points its corners are sent to.
///
/// **This is not "two transforms."** Collapsing them into a bare quad forces an invented rule for
/// what happens to the quad when the text grows, and "the quad grows along its top and bottom
/// edges" is not a well-defined operation on a projected quad — the whole point of perspective is
/// that those edges are neither parallel nor alike in scale. See ADD_TEXT.md §2.
///
/// **Stage 1 ships `.affine` only, and only its translation.** `corners` is therefore always the
/// box's own rectangle offset to somewhere on the canvas, `mode` is always `.affine`, and the
/// homography that turns the general case into a matrix is Stage 5's. The enum exists now anyway,
/// with both cases, so `.mesh(Lattice)` — Photoshop's Warp Text, which no homography can express —
/// is an additive case later rather than a Codable migration. Nothing in this project builds it.
struct TextFrame: Codable, Equatable {

    /// How `corners` relates to `size`. Two cases from the first commit even though Stage 1 writes
    /// only one, for the reason above.
    enum Mode: String, Codable { case affine, projective }

    /// Index into `corners`, in the order ADD_TEXT.md §1's Heckbert derivation uses: the unit square
    /// `(0,0), (1,0), (1,1), (0,1)`. Named rather than numbered because "corner 2" is the kind of
    /// thing two files come to disagree about.
    enum Corner: Int, CaseIterable { case topLeft = 0, topRight = 1, bottomRight = 2, bottomLeft = 3 }

    /// The layout box, in its own local coordinates with the origin at its top-left. What CoreText
    /// wraps into.
    var size: CGSize
    /// Where the box's four corners land in canvas space, in `Corner` order. Always four entries;
    /// a decoded frame that says otherwise is repaired to an upright box (see `init(from:)`).
    var corners: [CGPoint]
    var mode: Mode
    /// **A stored bit, not an inference.** While true — a fresh box nobody has resized — `size`
    /// tracks the measured layout and adding a character extends the text. The first handle drag
    /// sets it false; from then on `size` is authoritative and text wraps and clips into it. This is
    /// Illustrator's point-text-becomes-area-text moment, and ADD_TEXT.md §5.3 says it feels broken
    /// if it is left implicit: a pristine box draws a dashed outline, a sized box a solid one.
    ///
    /// Stage 1 has no handles, so nothing sets it false yet and every Stage 1 box grows to fit. The
    /// bit is stored now so a Stage 4 box does not have to be told apart from a Stage 1 one by
    /// guesswork.
    var autoSize: Bool

    init(size: CGSize, corners: [CGPoint], mode: Mode = .affine, autoSize: Bool = true) {
        self.size = size
        self.corners = corners.count == 4 ? corners : TextFrame.uprightCorners(origin: .zero, size: size)
        self.mode = mode
        self.autoSize = autoSize
    }

    /// An axis-aligned box with its top-left at `origin` — every box Stage 1 can make.
    init(origin: CGPoint, size: CGSize, autoSize: Bool = true) {
        self.init(size: size, corners: TextFrame.uprightCorners(origin: origin, size: size),
                  mode: .affine, autoSize: autoSize)
    }

    static func uprightCorners(origin: CGPoint, size: CGSize) -> [CGPoint] {
        [CGPoint(x: origin.x, y: origin.y),
         CGPoint(x: origin.x + size.width, y: origin.y),
         CGPoint(x: origin.x + size.width, y: origin.y + size.height),
         CGPoint(x: origin.x, y: origin.y + size.height)]
    }

    subscript(corner: Corner) -> CGPoint { corners[corner.rawValue] }

    /// The canvas-space rectangle the box occupies. Exact while the frame is axis-aligned, which is
    /// every Stage 1 frame; once Stages 4-5 rotate and distort it this becomes the *bounding* box,
    /// which is still what the bake needs as its destination.
    var boundingBox: CGRect {
        let xs = corners.map(\.x), ys = corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// True while `corners` is the box translated and nothing else — no rotation, no scale, no
    /// distort. The whole of Stage 1, and the fast path the bake takes: the glyphs can be drawn
    /// straight into the destination with a translate, no resampling anywhere.
    ///
    /// Compared against an extent-scaled epsilon rather than exactly, because a corner that has
    /// been through a `CGPoint` round-trip in JSON is not bit-identical to the one that went in.
    var isUprightTranslation: Bool {
        guard mode == .affine, corners.count == 4 else { return false }
        let eps = max(1e-6, 1e-6 * max(size.width, size.height))
        let expected = TextFrame.uprightCorners(origin: corners[0], size: size)
        return zip(corners, expected).allSatisfy {
            abs($0.x - $1.x) <= eps && abs($0.y - $1.y) <= eps
        }
    }

    /// The frame moved by a canvas-space delta. Moves `corners` and leaves `size` alone — they are
    /// domain and codomain, and a move is a change of codomain only.
    func moved(by delta: CGVector) -> TextFrame {
        var moved = self
        moved.corners = corners.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
        return moved
    }

    /// The frame re-sized about its top-left corner — what `autoSize` does as the artist types.
    ///
    /// **Stage 4 made this rotation-preserving**, and that was not cosmetic: it used to rebuild
    /// `corners` through `uprightCorners`, so a box the artist had rotated snapped back to
    /// axis-aligned on the very next keystroke. The new corners run along the frame's *own* axes
    /// (`basis`), which is the same statement as before for an upright frame and the right one for a
    /// turned box. A frame too degenerate to have axes falls back to the upright rebuild, because a
    /// collapsed quad has no direction to preserve.
    func resized(to newSize: CGSize) -> TextFrame {
        var resized = self
        resized.size = newSize
        if let basis {
            resized.corners = TextFrame.corners(origin: basis.origin, u: basis.u, v: basis.v,
                                                width: newSize.width, height: newSize.height)
        } else {
            resized.corners = TextFrame.uprightCorners(origin: corners.first ?? .zero, size: newSize)
        }
        return resized
    }

    private enum CodingKeys: String, CodingKey { case size, corners, mode, autoSize }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(CGSize.self, forKey: .size) ?? .zero
        let decoded = try c.decodeIfPresent([CGPoint].self, forKey: .corners)
        // Repaired rather than thrown for the reason ADD_TEXT.md §1 gives for the whole per-field
        // scheme: this file is read by a decoder that already tells a malformed element from an
        // unknown one and logs them differently (`VectorCanvasData.LossySlot`). A frame with three
        // corners is a bug in whatever wrote it; degrading it to an upright box of the right size
        // loses the rotation and keeps the words, which is the better half to keep.
        corners = (decoded?.count == 4 ? decoded! : TextFrame.uprightCorners(origin: .zero, size: size))
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .affine
        autoSize = try c.decodeIfPresent(Bool.self, forKey: .autoSize) ?? true
    }
}

// MARK: - Where it sits, as a map

// ADD_TEXT.md §3 stage 4, "rotate, scale, and handles that are the right size", in code.
//
// **The math lives here rather than in the overlay view, and that is the whole reason it is
// testable.** `ShapeOverlayView`'s own header records why: the corner/edge drag arithmetic used to
// be written out inline in `CanvasView`'s callbacks, "where nothing could unit-test it", and moving
// it onto `ShapeGeometry` is what fixed that. `TextTransformOverlayView` is therefore layers and
// touches and nothing else; every position, every anchor and every new quad comes from below.
//
// Stage 4 writes **rotation and independent-axis scale** and nothing more. The four corners moving
// independently — a real projective warp — is stage 5, and it is what `Engine/Deform/Homography`
// will be for. Everything here consequently assumes the quad is a *parallelogram with perpendicular
// axes*, i.e. a rectangle that has been turned and had its two sides sized: `u` and `v` below are
// unit vectors and the decomposition of a drag onto them is a pair of dot products. A quad that is
// not (only stage 5 can make one, or a hand-edited document) is un-sheared by the first drag rather
// than being refused, which is the honest half to keep — the alternative is a handle that silently
// does nothing.

extension TextFrame {

    /// The frame's own axes in canvas space: where its top-left sits, the unit vectors its local
    /// +x and +y run along, and how far it runs along each.
    ///
    /// This is the affine map written as geometry rather than as a matrix, and it is what every
    /// drag, every handle position and every rotation-preserving resize reads. Nil when the quad has
    /// collapsed far enough that "which way is along the text" has no answer.
    struct Basis: Equatable {
        var origin: CGPoint
        /// Unit vector along the box's local +x (left to right along a line of type).
        var u: CGVector
        /// Unit vector along the box's local +y (down the page).
        var v: CGVector
        /// How far the quad runs along `u` and along `v`. Equal to `size` for every frame this
        /// project writes — `VectorCanvas.mapping(_:throughSimilarity:)`'s text arm scales `size`,
        /// `corners` and the recipe's point size together for exactly this reason — so the two are
        /// stated separately only so a decoded document cannot make one lie about the other.
        ///
        /// **`TextFrameDrag.resized` and `TextFrame.resized(to:)` both depend on that equality**: each
        /// reads `basis.width` as a layout extent and writes it back into `size`. A frame whose
        /// corners had been scaled without its `size` would therefore lose the scale on the first
        /// handle drag or the first auto-size regrow, and nowhere in between would say so.
        var width: CGFloat
        var height: CGFloat
    }

    var basis: Basis? {
        guard corners.count == 4 else { return nil }
        let o = corners[0]
        let ux = corners[1].x - o.x, uy = corners[1].y - o.y
        let vx = corners[3].x - o.x, vy = corners[3].y - o.y
        let w = (ux * ux + uy * uy).squareRoot()
        let h = (vx * vx + vy * vy).squareRoot()
        guard w > TextFrame.degenerateExtent, h > TextFrame.degenerateExtent else { return nil }
        return Basis(origin: o, u: CGVector(dx: ux / w, dy: uy / w),
                     v: CGVector(dx: vx / h, dy: vy / h), width: w, height: h)
    }

    /// The quad's centre — the average of its four corners, which is the centroid for any
    /// parallelogram and therefore the point a rotation turns about.
    var centre: CGPoint {
        guard corners.count == 4 else { return .zero }
        let sx = corners.reduce(CGFloat(0)) { $0 + $1.x }
        let sy = corners.reduce(CGFloat(0)) { $0 + $1.y }
        return CGPoint(x: sx / 4, y: sy / 4)
    }

    /// The angle the box's baseline direction makes with the canvas's +x axis, in radians. Zero for
    /// an upright box.
    var rotation: CGFloat {
        guard let basis else { return 0 }
        return atan2(basis.u.dy, basis.u.dx)
    }

    /// The map from the layout box's own coordinates — origin at its top-left, `size` across — into
    /// canvas space. Nil when the frame is degenerate or its quad is not a parallelogram.
    ///
    /// **This is the affine half of ADD_TEXT.md §1's homography, and it is all stage 4 needs.** The
    /// three places that draw a text object — the raster bake (`TextLayout.render`), the vector
    /// flatten (`VectorCanvas.draw(text:…)`) and the live overlay (`TextOverlayView`) — concatenate
    /// exactly this and then draw the glyphs at `size`, which is why a rotated box draws with no
    /// bitmap and no resampling at all on the two CoreGraphics paths. Stage 5 replaces it with the
    /// full 3×3 for `.projective`; `affine()` there is expected to return this same matrix for every
    /// quad that is a parallelogram, which is every quad stage 4 can make.
    var affineTransform: CGAffineTransform? {
        guard mode == .affine, corners.count == 4,
              size.width > TextFrame.degenerateExtent, size.height > TextFrame.degenerateExtent else { return nil }
        let o = corners[0]
        // The fourth corner is implied by the other three for a parallelogram. A quad that does not
        // satisfy that has no affine map onto it, and saying so is what keeps stage 5's `.projective`
        // an additive case rather than a silent approximation.
        let implied = CGPoint(x: corners[1].x + corners[3].x - o.x, y: corners[1].y + corners[3].y - o.y)
        let extent = max(size.width, size.height)
        let eps = max(1e-6, 1e-6 * extent)
        guard abs(implied.x - corners[2].x) <= eps, abs(implied.y - corners[2].y) <= eps else { return nil }
        let t = CGAffineTransform(a: (corners[1].x - o.x) / size.width,
                                  b: (corners[1].y - o.y) / size.width,
                                  c: (corners[3].x - o.x) / size.height,
                                  d: (corners[3].y - o.y) / size.height,
                                  tx: o.x, ty: o.y)
        // A zero determinant is a box collapsed onto a line; drawing through it produces nothing
        // useful and CoreGraphics will not invert it.
        guard abs(t.a * t.d - t.b * t.c) > 1e-9 else { return nil }
        return t
    }

    /// The frame's four corners as the solver's own type, in the same order.
    var quad: Quad? { Quad(corners) }

    /// **The full 3×3 that `affineTransform` is the special case of** — ADD_TEXT.md §3 stage 5, and
    /// the map every `.projective` frame draws through.
    ///
    /// Computed, never stored, which is §1's whole rule for this object: "not a warped bitmap, not
    /// the 3×3 matrix". Retype the string, change the font, change the point size and the glyphs
    /// re-lay-out into the same box and land in the same perspective, because the perspective was
    /// never baked into anything.
    ///
    /// **It agrees with `affineTransform` on every quad stage 4 can make**, which is the seam that
    /// stage entry left and `HomographyLogicTests.testTheSolversAffineMatchesStageFoursForEveryQuadItCanMake`
    /// measures rather than assumes: 1728 rotated, scaled and translated boxes, no disagreement about
    /// *whether* there is an affine map and at most 1.1e-16 between the two matrices when there is.
    /// The residue is one ULP from the box prescale being a multiply by `1/w` here and a divide by
    /// `w` there, and the two implementations are kept separate on purpose — routing
    /// `affineTransform` through this would make the seam true by construction and the test vacuous.
    var homography: Homography? {
        guard let quad, size.width > TextFrame.degenerateExtent,
              size.height > TextFrame.degenerateExtent else { return nil }
        return Homography(boxSize: size, to: quad)
    }

    /// How much the frame's own map magnifies the box at its densest corner — ADD_TEXT.md §1's
    /// "`contentsScale` comes from the largest per-corner destination scale of `H`".
    ///
    /// **Exactly 1 for every frame stages 1-4 could make**, because a stage-4 quad's extent along
    /// each axis is its `size` along that axis by construction (`TextFrame.Basis` documents that
    /// equality and what depends on it). It exists for the near corner of a foreshortened quad,
    /// which is the one place a warped box genuinely needs more texels than it has points.
    ///
    /// **The `.projective` guard is what makes "exactly" true, and it is not tidiness.**
    /// `maximumCornerScale` is `sqrt(|det J|)`, which on a rotated affine frame is
    /// `sqrt(cos²θ + sin²θ)` — 1 to within an ULP, not 1. `max(1, …)` in the caller clamps the low
    /// side and not the high one, so the ULP survives: **measured, at 131.2° on a 300×120 box it
    /// comes out `1.0000000000000002`**, which carries a `contentsScale` of `2.0000000000000004`
    /// into `UIGraphicsImageRenderer` and rounds the glyph bitmap up to 601 texels where the same
    /// box unrotated takes 600. 34 of 3600 sampled angles land above 1. Asking the *mode* instead of
    /// the arithmetic is cheaper and is the question actually meant: a parallelogram has no
    /// foreshortening to compensate for.
    ///
    /// It lives on the frame rather than in `TextOverlayView`, where it started, for
    /// `TextTransformLogicTests`' sake — stage 4's whole reason for putting the geometry here.
    var warpMagnification: CGFloat {
        guard mode == .projective, let homography else { return 1 }
        return max(1, homography.maximumCornerScale(ofBox: size))
    }

    /// The flat box the artist types into while the frame is warped — ADD_TEXT.md §1 "Typing in a
    /// distorted box happens unwarped" and §5.2, which the owner settled: *"Tap into perspective text
    /// and the box springs back to flat while you type, the perspective version ghosted behind."*
    ///
    /// **Flat, not upright.** The obvious reading of "springs back to flat" is an axis-aligned box,
    /// and that is the wrong one: a title the artist rotated 30° and *then* put into perspective would
    /// snap straight the moment they tapped into it, losing an orientation they can see and did not
    /// ask to change. What is taken out is the *foreshortening* alone —
    /// `Homography.linearised(at:)` at the box's centre keeps the rotation, the scale and the shear
    /// and drops the divide, so the flat box sits where the warped one sat and points the way it
    /// pointed.
    ///
    /// Returns `self` unchanged for an `.affine` frame: there is nothing to unwarp, and stage 4's
    /// behaviour — you edit in place under the affine transform, caret and all — is untouched.
    var flattenedForEditing: TextFrame {
        guard mode == .projective, let homography,
              let flat = homography.linearised(at: CGPoint(x: size.width / 2, y: size.height / 2))
        else { return self }
        var out = self
        out.corners = Quad.rect(CGRect(origin: .zero, size: size)).mapped(by: flat).points
        out.mode = .affine
        return out
    }

    /// Point-in-quad with a slop collar, in the frame's own space.
    ///
    /// `VectorCanvas.frame(_:contains:slop:)` is this — it delegates here — so the display list's
    /// re-open query and the live overlay's hit test cannot come to disagree about what "inside the
    /// text" means. Space-agnostic: `point` and `corners` must simply be in the same space.
    func contains(_ point: CGPoint, slop: CGFloat = 0) -> Bool {
        guard corners.count == 4 else { return false }
        // Winding sign, taken from the whole quad rather than per edge: a degenerate (zero-area) quad
        // has no inside at all, and the per-edge signs of one are noise.
        var area: CGFloat = 0
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            area += a.x * b.y - b.x * a.y
        }
        if abs(area) > 1e-9 {
            let sign: CGFloat = area > 0 ? 1 : -1
            var inside = true
            for i in 0..<4 {
                let a = corners[i], b = corners[(i + 1) % 4]
                let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
                if cross * sign < 0 { inside = false; break }
            }
            if inside { return true }
        }
        guard slop > 0 else { return false }
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            if StrokeGeometry.distanceSquared(from: point, toSegment: a, b) <= slop * slop { return true }
        }
        return false
    }

    /// The four corners of a `width × height` box whose top-left is `origin` and whose axes are `u`
    /// and `v`, in `Corner` order. The one place a quad is built from a basis, so the corner order
    /// cannot drift between the resize, the rotate and the auto-size regrow.
    static func corners(origin: CGPoint, u: CGVector, v: CGVector,
                        width: CGFloat, height: CGFloat) -> [CGPoint] {
        let ux = u.dx * width, uy = u.dy * width
        let vx = v.dx * height, vy = v.dy * height
        return [origin,
                CGPoint(x: origin.x + ux, y: origin.y + uy),
                CGPoint(x: origin.x + ux + vx, y: origin.y + uy + vy),
                CGPoint(x: origin.x + vx, y: origin.y + vy)]
    }

    /// Below this, an extent is not a box. Shared by `basis` and `affineTransform` so "degenerate"
    /// means one thing.
    static let degenerateExtent: CGFloat = 1e-6

    /// The smallest a handle drag may make either axis, in canvas points.
    ///
    /// The same number `TextLayout.minimumBoxWidth` is — that constant is defined as this one — so
    /// the smallest box a drag can make and the smallest box auto-size can make are one figure. A
    /// drag that would take an axis below it, or through the anchor and out the other side, clamps
    /// here rather than mirroring the box: a text object that reads backwards is never what the
    /// artist meant by dragging past the far corner.
    static let minimumExtent: CGFloat = 24

    // MARK: Handles

    /// The nine grips ADD_TEXT.md §3 stage 4 puts on a text box: four corners, four edge midpoints,
    /// and the rotation knob standing off above the top edge.
    ///
    /// Corners size both axes at once; an edge sizes one and freezes the other, which is what makes
    /// the scale genuinely **independent-axis** — for type, "set the wrap width and leave the height
    /// alone" is the common ask, and a corner-only box cannot express it.
    enum Handle: CaseIterable, Equatable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, rotation

        /// True for the eight that size the box. The rotation knob is the exception everywhere.
        var isResize: Bool { self != .rotation }

        /// The quad corner this grip sits *on*, for the four that sit on one — and nil for the four
        /// edge midpoints and the knob, which sit between corners or off the box entirely.
        ///
        /// **This is what makes the four corners "independent" in stage 5's sense**: a distort drag
        /// writes one entry of `corners` and leaves the other three exactly where they were, where a
        /// stage-4 corner drag rebuilds all four from a basis. Only these four can distort; the edge
        /// grips keep sizing an axis and the knob keeps rotating, in both modes.
        var corner: Corner? {
            switch self {
            case .topLeft: return .topLeft
            case .topRight: return .topRight
            case .bottomRight: return .bottomRight
            case .bottomLeft: return .bottomLeft
            case .top, .right, .bottom, .left, .rotation: return nil
            }
        }

        /// How the box's width responds: nil freezes it.
        fileprivate var widthSign: CGFloat? {
            switch self {
            case .topLeft, .bottomLeft, .left: return -1
            case .topRight, .bottomRight, .right: return 1
            case .top, .bottom, .rotation: return nil
            }
        }

        /// How the box's height responds: nil freezes it.
        fileprivate var heightSign: CGFloat? {
            switch self {
            case .topLeft, .topRight, .top: return -1
            case .bottomLeft, .bottomRight, .bottom: return 1
            case .left, .right, .rotation: return nil
            }
        }

        /// Where the drag's anchor sits inside a `width × height` box, in the box's own coordinates.
        /// The anchor is the point diametrically opposite the grip, which is what "the opposite
        /// corner does not move" means once edges are in the set too.
        fileprivate func anchorLocal(width: CGFloat, height: CGFloat) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: width, y: height)
            case .topRight: return CGPoint(x: 0, y: height)
            case .bottomRight: return CGPoint(x: 0, y: 0)
            case .bottomLeft: return CGPoint(x: width, y: 0)
            case .top: return CGPoint(x: width / 2, y: height)
            case .bottom: return CGPoint(x: width / 2, y: 0)
            case .left: return CGPoint(x: width, y: height / 2)
            case .right: return CGPoint(x: 0, y: height / 2)
            case .rotation: return CGPoint(x: width / 2, y: height / 2)
            }
        }
    }

    /// Where every handle sits in canvas space — **the single source of truth both the overlay's
    /// rebuild and its reposition read**, which is `ShapeOverlayView.handleLayout(for:)`'s first
    /// discipline and the reason the two cannot drift apart.
    ///
    /// `rotationOffset` is how far the rotation knob stands off the top edge. It arrives already
    /// divided by `canvasScale`, because it is a *screen*-point figure and this function works in
    /// canvas points — a handle is chrome and belongs to the screen, so the view owns the constant
    /// and the geometry owns the direction.
    ///
    /// Positions come off the quad directly rather than out of `size`, so a frame whose stored size
    /// has drifted from its corners still puts its handles on the corners the artist can see.
    func handleLayout(rotationOffset: CGFloat) -> [(handle: Handle, position: CGPoint)] {
        guard corners.count == 4 else { return [] }
        let c = corners
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let topMid = mid(c[0], c[1])
        var layout: [(handle: Handle, position: CGPoint)] = [
            (.topLeft, c[0]), (.top, topMid), (.topRight, c[1]),
            (.right, mid(c[1], c[2])), (.bottomRight, c[2]),
            (.bottom, mid(c[2], c[3])), (.bottomLeft, c[3]), (.left, mid(c[3], c[0]))
        ]
        // Along the box's own "up", so the knob stays over the top edge at any rotation instead of
        // swinging into the artwork.
        if let basis, rotationOffset != 0 {
            layout.append((.rotation, CGPoint(x: topMid.x - basis.v.dx * rotationOffset,
                                              y: topMid.y - basis.v.dy * rotationOffset)))
        }
        return layout
    }

    /// The handle **nearest** `point` within `reach`, not merely the first whose target contains it.
    ///
    /// `ShapeOverlayView`'s second discipline, and it is more load-bearing here than there: a text
    /// box carries nine grips rather than five, and on a box smaller than the 44 pt target a corner,
    /// its two neighbouring edges and the rotation knob all overlap. First-match would cost such a
    /// box most of its handles outright.
    func handle(nearest point: CGPoint, reach: CGFloat, rotationOffset: CGFloat) -> Handle? {
        var best: (handle: Handle, distance: CGFloat)?
        for entry in handleLayout(rotationOffset: rotationOffset) {
            let distance = hypot(point.x - entry.position.x, point.y - entry.position.y)
            guard distance <= reach else { continue }
            if best == nil || distance < best!.distance { best = (entry.handle, distance) }
        }
        return best?.handle
    }

    /// The canvas point a drag on `handle` must hold still. The rotation knob's is the centre, which
    /// does not move either.
    ///
    /// **A `.projective` frame answers through its homography, not through its basis**, and the two
    /// genuinely differ. `Basis` decomposes onto `u` and `v`, which is the same statement as the
    /// quad only while the quad is a parallelogram; on a warped one it reports the point the box
    /// *would* have had if the perspective were taken out, which is not a point on the quad at all.
    /// The homography answers the question actually asked — where does the box's own opposite edge
    /// sit on the artist's screen — and for an `.affine` frame the two agree to the last bit,
    /// because there `H` **is** the basis written as a matrix.
    func anchor(for handle: Handle) -> CGPoint? {
        if mode == .projective, let homography {
            let local = handle.anchorLocal(width: size.width, height: size.height)
            if let mapped = homography.map(local) { return mapped }
        }
        guard let basis else { return nil }
        let local = handle.anchorLocal(width: basis.width, height: basis.height)
        return CGPoint(x: basis.origin.x + basis.u.dx * local.x + basis.v.dx * local.y,
                       y: basis.origin.y + basis.u.dy * local.x + basis.v.dy * local.y)
    }
}

// MARK: - What a corner grip does

/// Whether dragging a corner sizes the box or distorts it — the segmented control at the bottom of
/// the text panel, and `ADD_TEXT.md` §3 stage 5's "four independent corner handles".
///
/// **Tool state, deliberately kept out of `TextFrame`.** §1's rule is that the object stores what the
/// text is and where it sits, never a mode of working; `TextFrame.mode` is a different question (what
/// kind of map the quad needs) and is *derived* from the corners rather than chosen. Lives here
/// rather than beside `CanvasManager` so `TextFrameDrag` — which is in this file and is what actually
/// reads the decision — does not have to reach up into the app layer for it.
enum TextCornerMode: String, CaseIterable, Identifiable, Codable {
    /// Stage 4: a corner sizes both axes about the opposite corner, and the quad stays a
    /// parallelogram.
    case scale
    /// Stage 5: a corner moves alone and the other three stay put, which is what makes the map
    /// projective and puts type onto a wall.
    case distort

    var id: String { rawValue }

    /// Label for the segmented control. Short enough to sit two-across in a 300 pt panel.
    var displayName: String {
        switch self {
        case .scale: return "Scale"
        case .distort: return "Distort"
        }
    }
}

// MARK: - One drag

/// A handle drag in flight: **the whole starting quad and the anchor, latched at touch-down**.
///
/// ADD_TEXT.md §1 says why the latch rather than a per-frame recomputation, and it is not the
/// obvious reason. Recomputing the anchor from the live frame is stable while the drag stays on one
/// side of it and jumps at the instant it crosses — but the *decisive* case is a mid-drag
/// pinch-zoom: with the reference frame recomputed, the artist's second finger moves the thing the
/// first finger is measuring against, and the box lurches. One latched value removes both, and it is
/// `ShapeOverlayView.activeAnchor`'s argument with one more term.
///
/// **Deliberately no `recordUndo` anywhere in here, and none on lift either.** See
/// `CanvasManager.endTextHandleDrag` for the reasoning; the short version is that a text session
/// already registers exactly one step for everything that happened inside it, and a second step for
/// the drag would be a dead entry the artist has to press through.
struct TextFrameDrag: Equatable {

    /// The frame as it was when the finger went down. Every delta is measured against this and never
    /// against the frame the previous delta produced, so a drag cannot accumulate rounding and cannot
    /// be re-based by anything that happens mid-gesture.
    let start: TextFrame
    let handle: TextFrame.Handle
    /// The canvas point this drag holds still, latched with the quad.
    let anchor: CGPoint

    /// **Stage 5's fork.** False is stage 4 exactly: the eight sizing grips rebuild the whole quad
    /// from a basis and the knob turns it. True is the projective distort — one corner moves, the
    /// other three do not, and the quad stops being a parallelogram.
    ///
    /// A property of the *drag*, latched at touch-down, and never of the `TextFrame`: which grip
    /// gesture the artist has selected is tool state, and the document stores only what the text is
    /// and where it sits (§1, "the object stores a recipe, never a result").
    let isDistort: Bool

    /// Nil only for a distort drag on a quad too warped to have perpendicular axes — which is every
    /// quad a distort has already made, and none of which the sizing paths are reachable from.
    private let basis: TextFrame.Basis?

    init?(frame: TextFrame, handle: TextFrame.Handle, distort: Bool = false) {
        if distort, handle.corner != nil, frame.corners.count == 4,
           frame.size.width > TextFrame.degenerateExtent,
           frame.size.height > TextFrame.degenerateExtent,
           let corner = handle.corner {
            self.start = frame
            self.handle = handle
            self.isDistort = true
            // The diagonally opposite corner — the one point a distort provably does not move,
            // since it writes exactly one entry of `corners`. Taken straight rather than through
            // `anchor(for:)`, which decomposes onto the frame's axes and so assumes the
            // parallelogram a distorted quad is not.
            self.anchor = frame[TextFrame.Corner(rawValue: (corner.rawValue + 2) % 4) ?? .bottomRight]
            self.basis = frame.basis
            return
        }
        guard let basis = frame.basis, let anchor = frame.anchor(for: handle) else { return nil }
        self.start = frame
        self.handle = handle
        self.anchor = anchor
        self.basis = basis
        self.isDistort = false
    }

    /// The frame this drag produces with the finger at `point`.
    ///
    /// Pure, and a function of the *latched* frame alone — driving one delta or sixty produces the
    /// same answer for the same final point, which is the property `TextTransformLogicTests` pins.
    ///
    /// **Falls back to the latched frame when the clamped form refuses.** The live caller is
    /// `CanvasManager.dragTextHandle`, which asks `clampedFrame(draggedTo:)` directly so it can hold
    /// the *last valid* quad rather than the starting one — ADD_TEXT.md §1's clamping rule. This
    /// total form exists so a caller that drives a whole gesture in one call still gets an answer,
    /// and so the two can never mean different things.
    func frame(draggedTo point: CGPoint, minimumExtent: CGFloat = TextFrame.minimumExtent) -> TextFrame {
        clampedFrame(draggedTo: point, minimumExtent: minimumExtent) ?? start
    }

    /// The frame this drag produces, or **nil when the quad it would produce is not one a homography
    /// can be drawn through** — at which point the caller holds whatever it last accepted.
    ///
    /// Nil is only reachable on the two paths that can *make* an invalid quad: the distort, and the
    /// sizing grips and knob on a `.projective` frame. Stage 4's parallelogram arithmetic on an
    /// `.affine` frame always answers, exactly as it did before stage 5 existed.
    func clampedFrame(draggedTo point: CGPoint,
                      minimumExtent: CGFloat = TextFrame.minimumExtent) -> TextFrame? {
        if isDistort { return distortedFrame(draggedTo: point) }
        if start.mode == .projective {
            return warpedFrame(draggedTo: point, minimumExtent: minimumExtent)
        }
        return handle == .rotation ? rotated(towards: point) : resized(towards: point, minimumExtent: minimumExtent)
    }

    /// The frame with this drag's corner moved to `point` and the other three left alone — or **nil
    /// when the quad that would produce is not one a homography can be drawn through**.
    ///
    /// `Homography.isValidQuad` is the whole of the refusal: strictly convex, non-self-intersecting,
    /// above an area floor, solvable, and all four box corners at positive weight. ADD_TEXT.md §1 is
    /// explicit that the resulting handle "will feel like it sticks", and that clamping is the honest
    /// trade: rendering garbage or flipping the box through the horizon are both worse, and the big
    /// editors do the same thing.
    ///
    /// **`autoSize` is cleared, and `mode` is derived rather than asserted.** Clearing the bit is
    /// stage 4's rule for the eight sizing grips applied to a ninth kind of sizing — a box the artist
    /// has shaped by hand is authoritative, and it also keeps `resized(to:)`'s parallelogram
    /// arithmetic from ever meeting a projective quad. Deriving the mode matters more than it looks:
    /// a distort that happens to land back on a parallelogram must go back to `.affine`, or
    /// `affineTransform` would refuse a quad it can express and the artist would lose the native,
    /// unresampled drawing path for a box that no longer needs the warp.
    func distortedFrame(draggedTo point: CGPoint) -> TextFrame? {
        guard isDistort, let corner = handle.corner, var quad = start.quad else { return nil }
        quad[corner.rawValue] = point
        guard Homography.isValidQuad(quad, boxSize: start.size) else { return nil }
        var next = start
        next.corners = quad.points
        next.autoSize = false
        let tolerance = max(1e-6, 1e-6 * max(start.size.width, start.size.height))
        next.mode = quad.isParallelogram(tolerance: tolerance) ? .affine : .projective
        return next
    }

    // MARK: - The eight sizing grips and the knob, on a quad that has perspective

    /// **The same two gestures stage 4 wrote, composed *through* the homography instead of replacing
    /// it** — the eight sizing grips and the rotation knob on a `.projective` frame.
    ///
    /// What this replaces was a silent flatten, and it is worth naming because it looked like
    /// nothing: `resized(towards:)` rebuilds the quad from `basis`, which is the frame's two edge
    /// *directions* and therefore describes a parallelogram. Handed a warped quad it produced the
    /// parallelogram nearest it — the wall of text lay down flat and the far corner jumped — and it
    /// left `mode` saying `.projective` over a quad that no longer was. Nudging the wrap width to
    /// fix a line break destroyed the perspective, with no undo step of its own to get it back.
    ///
    /// **The composition, and why it is the honest behaviour rather than a workaround.** A sizing
    /// grip does not move the quad; it changes the *box* the glyphs are laid out in. So the drag is
    /// carried into box space through `H⁻¹`, resized there with stage 4's own arithmetic — the axis
    /// mask, the anchor opposite the grip, the minimum extent, all of it, with `u` and `v` now the
    /// literal unit axes — and the resulting rectangle carried back out through `H`. The plane the
    /// artist put the text on is untouched: the box grows *along the wall*, foreshortened exactly as
    /// the wall is. That is why the knob is here too, one line down and by a different route: a
    /// rotation is not a box resize, so it turns the whole quad rigidly about its own centre, which
    /// is `R · H` and still a homography with the same perspective row.
    ///
    /// **Nothing is grandfathered.** The grip does not jump under the finger at touch-down, and that
    /// is arithmetic rather than luck: the line `x = w` in box space maps to the line through corners
    /// 1 and 2, so an edge grip's own canvas position inverts to exactly the extent it started from.
    /// And the mode is *derived* on the way out, the same way `distortedFrame` derives it, so a
    /// resize that happens to land back on a parallelogram goes back to `.affine` and gets its native
    /// unresampled drawing path back.
    ///
    /// Nil on a drag that would leave the valid set — a box grown through the vanishing line, most
    /// of all — which is ADD_TEXT.md §1's clamp, reached by the same predicate the distort uses.
    func warpedFrame(draggedTo point: CGPoint,
                     minimumExtent: CGFloat = TextFrame.minimumExtent) -> TextFrame? {
        guard !isDistort, start.mode == .projective, let homography = start.homography else { return nil }
        let candidate = handle == .rotation
            ? turnedInPlane(towards: point)
            : sizedInBoxSpace(towards: point, through: homography, minimumExtent: minimumExtent)
        guard var next = candidate, let quad = next.quad,
              Homography.isValidQuad(quad, boxSize: next.size) else { return nil }
        let tolerance = max(1e-6, 1e-6 * max(next.size.width, next.size.height))
        next.mode = quad.isParallelogram(tolerance: tolerance) ? .affine : .projective
        return next
    }

    /// Stage 4's `resized(towards:)`, done in the box's own coordinates and mapped back out.
    ///
    /// The two are the same function: there `u` and `v` are the frame's axes and the decomposition
    /// is a pair of dot products, here they are `(1,0)` and `(0,1)` and the decomposition is a
    /// subtraction. `handle.widthSign`, `heightSign` and `anchorLocal` are read *unchanged*, which is
    /// the point — the axis mask, the "opposite corner does not move" rule and the clamp at
    /// `minimumExtent` are stage 4's, not a second copy of them.
    private func sizedInBoxSpace(towards point: CGPoint, through homography: Homography,
                                 minimumExtent: CGFloat) -> TextFrame? {
        guard let inverse = homography.inverse, let local = inverse.map(point) else { return nil }
        let held = handle.anchorLocal(width: start.size.width, height: start.size.height)
        let width = handle.widthSign.map { max(minimumExtent, $0 * (local.x - held.x)) } ?? start.size.width
        let height = handle.heightSign.map { max(minimumExtent, $0 * (local.y - held.y)) } ?? start.size.height
        let moved = handle.anchorLocal(width: width, height: height)
        let box = CGRect(x: held.x - moved.x, y: held.y - moved.y, width: width, height: height)
        let mapped = Quad.rect(box).points.compactMap { homography.map($0) }
        guard mapped.count == 4 else { return nil }
        var sized = start
        sized.size = CGSize(width: width, height: height)
        sized.corners = mapped
        sized.autoSize = false
        return sized
    }

    /// The knob on a warped frame: the quad turned **rigidly** about its own centre.
    ///
    /// Rigid rather than rebuilt, which is the whole difference from `rotated(towards:)`. Turning the
    /// four corners is `R · H`, whose third row is `H`'s third row unchanged — so the perspective
    /// survives the rotation exactly, every weight is what it was, and a quad that was valid stays
    /// valid. `size` and `autoSize` do not move, for stage 4's stated reason: turning a box is not
    /// sizing it.
    ///
    /// The angle convention is stage 4's, reused rather than re-derived: the knob stands off the top
    /// edge, so `atan2(finger − centre) + π/2` is where the box's own +x is asked to point, and the
    /// quad is turned by the difference from where it points now. On an `.affine` frame that produces
    /// the same quad `rotated(towards:)` does; on a warped one the knob can sit slightly off the
    /// finger, because a warped quad's edge midpoint is not the image of its box's edge midpoint —
    /// the same half-texel honesty the edge grips already carry, and far less than the ~80 pt jump
    /// this replaced.
    private func turnedInPlane(towards point: CGPoint) -> TextFrame? {
        guard let basis, let quad = start.quad else { return nil }
        let c = start.centre
        let target = atan2(point.y - c.y, point.x - c.x) + .pi / 2
        let delta = target - atan2(basis.u.dy, basis.u.dx)
        let cosD = cos(delta), sinD = sin(delta)
        var turned = start
        turned.corners = quad.points.map { corner in
            let dx = corner.x - c.x, dy = corner.y - c.y
            return CGPoint(x: c.x + dx * cosD - dy * sinD, y: c.y + dx * sinD + dy * cosD)
        }
        return turned
    }

    /// Turns the box about its own centre. Neither `size` nor `autoSize` moves: a rotation is not a
    /// resize, and freezing a pristine box's growth because it was turned would clip the artist's
    /// next keystroke for no reason they could name. See `CanvasManager.dragTextHandle`.
    private func rotated(towards point: CGPoint) -> TextFrame {
        guard let basis else { return start }
        let c = start.centre
        // `+ π/2` because the knob stands off the *top* edge: dragging it straight up from the centre
        // is the box upright, which is angle zero. `ShapeOverlayView.report`'s rotation arm, verbatim.
        let angle = atan2(point.y - c.y, point.x - c.x) + .pi / 2
        let cosA = cos(angle), sinA = sin(angle)
        let u = CGVector(dx: cosA, dy: sinA)
        let v = CGVector(dx: -sinA, dy: cosA)
        let origin = CGPoint(x: c.x - u.dx * basis.width / 2 - v.dx * basis.height / 2,
                             y: c.y - u.dy * basis.width / 2 - v.dy * basis.height / 2)
        var turned = start
        turned.corners = TextFrame.corners(origin: origin, u: u, v: v,
                                           width: basis.width, height: basis.height)
        return turned
    }

    /// Sizes the box along its own axes with the anchor pinned, and **clears `autoSize`**.
    ///
    /// ADD_TEXT.md §1 "Point text grows; a box you sized wraps": this is Illustrator's
    /// point-text-becomes-area-text moment, and the document is explicit that it feels broken left
    /// implicit. From here `size` is authoritative, the text wraps and clips into it, and the
    /// overlay draws a solid outline where a pristine box draws a dashed one.
    private func resized(towards point: CGPoint, minimumExtent: CGFloat) -> TextFrame {
        guard let basis else { return start }
        let d = CGVector(dx: point.x - anchor.x, dy: point.y - anchor.y)
        // Dot products rather than a 2×2 solve because `u ⟂ v` for every quad stage 4 writes; see
        // this file's stage-4 header for what happens to one that is not.
        let alongU = d.dx * basis.u.dx + d.dy * basis.u.dy
        let alongV = d.dx * basis.v.dx + d.dy * basis.v.dy
        let width = handle.widthSign.map { max(minimumExtent, $0 * alongU) } ?? basis.width
        let height = handle.heightSign.map { max(minimumExtent, $0 * alongV) } ?? basis.height

        let local = handle.anchorLocal(width: width, height: height)
        let origin = CGPoint(x: anchor.x - basis.u.dx * local.x - basis.v.dx * local.y,
                             y: anchor.y - basis.u.dy * local.x - basis.v.dy * local.y)
        var sized = start
        sized.size = CGSize(width: width, height: height)
        sized.corners = TextFrame.corners(origin: origin, u: basis.u, v: basis.v,
                                          width: width, height: height)
        sized.autoSize = false
        return sized
    }
}

// MARK: - The element

/// A text object as the document holds it: the recipe, the frame, an identity, and the motion-group
/// tag every other interpolable element carries.
///
/// **The first vector element whose runtime and persisted forms are the same type.** It holds no
/// runtime resource — no texture, no `UIImage` — so it needs none of the `ImageRef` /
/// `<project>/images/` machinery `.image` forces on `ProjectStore`. Stage 3 is what puts it into
/// `VectorElement` and `VectorCanvasData.ElementData`; Stage 1 only ever holds one of these in
/// `CanvasManager`'s draft tier and bakes it to pixels.
struct VectorTextElement: Codable, Equatable, Identifiable {
    var id: UUID
    var recipe: TextRecipe
    var frame: TextFrame
    /// Nil for text nobody has grouped. The tag `VectorStroke` already carries;
    /// VECTOR_INTERPOLATION.md items 11/41 record the wart that it lives on the stroke rather than
    /// on a `VectorElement` accessor, and Stage 6 is where that is promoted.
    var motionGroupID: UUID?

    init(id: UUID = UUID(), recipe: TextRecipe, frame: TextFrame, motionGroupID: UUID? = nil) {
        self.id = id
        self.recipe = recipe
        self.frame = frame
        self.motionGroupID = motionGroupID
    }

    private enum CodingKeys: String, CodingKey { case id, recipe, frame, motionGroupID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        recipe = try c.decodeIfPresent(TextRecipe.self, forKey: .recipe) ?? TextRecipe()
        frame = try c.decodeIfPresent(TextFrame.self, forKey: .frame) ?? TextFrame(origin: .zero, size: .zero)
        motionGroupID = try c.decodeIfPresent(UUID.self, forKey: .motionGroupID)
    }
}
