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
    /// Only meaningful while `isUprightTranslation`, which is every Stage 1 frame; a rotated or
    /// distorted box re-derives its corners by projecting the new box through its own homography,
    /// and that is Stage 4/5's to write.
    func resized(to newSize: CGSize) -> TextFrame {
        var resized = self
        resized.size = newSize
        resized.corners = TextFrame.uprightCorners(origin: corners.first ?? .zero, size: newSize)
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
