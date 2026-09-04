import XCTest
import UIKit
import CoreGraphics

/// **A vector cel's render, made incremental for the case the artist is actually in.**
///
/// PERFORMANCE.md §11 measured the problem on the owner's own iPad: committing one stroke to a cel
/// re-stamps *every dab the cel holds*, at 3.16 µs a dab, so their current 190-stroke density is
/// already ~142 ms behind the pen and a thousand strokes is 0.74 s. `VectorCanvas.Damage` is what
/// each mutation now says about itself.
///
/// **This is the seam alone, and nothing rides on it yet.** `Damage` is computed and stored and the
/// render still walks the list whole, so the fast tier passing here says the declarations are
/// correct *and* that adding them changed no behaviour — which is the half of this change that
/// would be expensive to retrofit, because it means revisiting every mutation site with knowledge of
/// what each one does.
final class IncrementalAppendLogicTests: XCTestCase {

    // MARK: - The scene
    //
    // Small (128×96) on purpose: these are logic-tier tests run constantly, and the byte comparison
    // is over every pixel. The behaviours under test are all about *order*, not about area.

    private static let canvasSize = CGSize(width: 128, height: 96)

    private static func brush(_ blend: BrushBlendMode = .normal) -> Brush {
        Brush(name: "Append", shape: .softRound, size: 6, spacingFraction: 0.3, blendMode: blend)
    }

    /// A short deterministic arc, placed so that strokes overlap each other — overlap is what makes
    /// a blend mode and an eraser visible at all, so a fixture of disjoint marks would pass every
    /// isolation test by accident.
    private static func stroke(_ index: Int, blend: BrushBlendMode = .normal,
                               composite: StrokeComposite = .paint) -> VectorStroke {
        let x = 16 + CGFloat((index * 13) % 84)
        let y = 20 + CGFloat((index * 29) % 52)
        let samples = (0..<6).map { step -> VectorSample in
            let t = CGFloat(step) / 5
            return VectorSample(x: x + t * 26, y: y + sin(t * .pi) * 14,
                                pressure: 0.4 + 0.6 * t)
        }
        return VectorStroke(brush: brush(blend),
                            color: CodableColor(red: Double((index % 3)) / 3,
                                                green: 0.2, blue: 0.7, alpha: 1),
                            size: 6, opacity: 0.9, samples: samples,
                            composite: composite,
                            seed: UInt64(index &+ 1))
    }

    private static func fill() -> VectorFillElement {
        VectorFillElement(path: CGPath(rect: CGRect(x: 8, y: 60, width: 60, height: 24),
                                       transform: nil),
                          color: CodableColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1),
                          opacity: 0.7)
    }

    private static func canvas(_ n: Int, blend: BrushBlendMode = .normal) -> VectorCanvas {
        VectorCanvas(size: canvasSize, elements: (0..<n).map { .stroke(stroke($0, blend: blend)) })
    }

    // MARK: - (1) What each mutation site declares

    /// **Every mutation site, and what it now says about itself.** The seam is `lastDamage`, read
    /// without rendering anything, so this pins the declarations rather than their consequences —
    /// which is what makes it useful when one of them is later changed by someone who has not read
    /// `appendPreservesTheWalk`.
    ///
    /// **The fixture is mutated cumulatively rather than rebuilt per row**, which CLAUDE.md's
    /// "green assertion" section is specifically about: a table that constructs a fresh canvas per
    /// row would be comparing something other than the effect of the row.
    func testWhatEveryMutationSiteDeclares() {
        let canvas = Self.canvas(3)
        XCTAssertEqual(canvas.lastDamage, .everything, "a canvas nobody has edited assumes nothing")

        canvas.addStroke(Self.stroke(3))
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "addStroke")

        canvas.addStroke(canvasSpaceStroke: Self.stroke(4))
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "addStroke(canvasSpaceStroke:)")

        canvas.addFill(Self.fill())
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "addFill — LASSO_FILL.md §2a appends")

        canvas.addFill(canvasSpacePath: CGPath(rect: CGRect(x: 2, y: 2, width: 9, height: 9),
                                               transform: nil),
                       color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1))
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "addFill(canvasSpacePath:)")

        var recipe = TextRecipe(string: "hi")
        recipe.typography.pointSize = 10
        let text = VectorTextElement(id: UUID(), recipe: recipe,
                                     frame: TextFrame(origin: CGPoint(x: 10, y: 70),
                                                      size: CGSize(width: 30, height: 12)))
        canvas.upsertText(text)
        XCTAssertEqual(canvas.lastDamage, .appended(count: 1), "a brand-new text object appends")

        var retyped = text
        retyped.recipe.string = "hello"
        canvas.upsertText(retyped)
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "re-editing text replaces it at its own z-position, which is not an append")

        // An image goes *below* the first stroke, so on this cel it is a middle insert.
        let photo = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                                             size: CGSize(width: 8, height: 8))
        canvas.addImage(VectorImageElement(image: photo,
                                           transform: LayerTransform(position: CGPoint(x: 40, y: 40),
                                                                     scale: 1, rotation: 0)))
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "an image inserted under the line art is not an append")

        canvas.removeText(id: text.id)
        XCTAssertEqual(canvas.lastDamage, .everything, "removeText")

        canvas.suppressedElementIDs = [canvas.elements[0].id]
        XCTAssertEqual(canvas.lastDamage, .everything, "suppression hides an element in the middle")
        canvas.suppressedElementIDs = []

        canvas.setTransform(CGAffineTransform(translationX: 3, y: 4))
        XCTAssertEqual(canvas.lastDamage, .everything,
                       "a layer transform resamples the whole picture; there is nothing to append to")
        canvas.setTransform(.identity)

        canvas.bumpVersion()
        XCTAssertEqual(canvas.lastDamage, .everything, "bumpVersion is undo's seam and knows nothing")
    }

    /// **An image imported onto a cel with no line art on it *is* an append**, and the declaration
    /// is derived from where the element landed rather than argued from the kind order — so this row
    /// and the `.everything` row above are the same call site answering two different lists.
    func testAnImageOntoAnEmptyCelIsAnAppendAndOntoLineArtIsNot() {
        let photo = CanvasFixture.solidImage(.green, rect: CGRect(x: 0, y: 0, width: 8, height: 8),
                                             size: CGSize(width: 8, height: 8))
        func element() -> VectorImageElement {
            VectorImageElement(image: photo,
                               transform: LayerTransform(position: CGPoint(x: 40, y: 40),
                                                         scale: 1, rotation: 0))
        }

        let blank = VectorCanvas(size: Self.canvasSize, elements: [])
        blank.addImage(element())
        XCTAssertEqual(blank.lastDamage, .appended(count: 1))
        blank.addImage(element())
        XCTAssertEqual(blank.lastDamage, .appended(count: 1), "a second image goes above the first")

        let inked = Self.canvas(2)
        inked.addImage(element())
        XCTAssertEqual(inked.lastDamage, .everything)
    }

    /// **The eraser's two halves declare differently, and that is the whole reason `eraseHybrid`
    /// returns a `Damage`.** A soft-brush punch appends one `.erase` element; a hard-brush clean cut
    /// deletes and splits strokes in the middle of the list first.
    func testTheEraserDeclaresAnAppendOnlyWhenItMerelyPunches() {
        let soft = Self.canvas(4)
        let path = (0..<6).map { VectorSample(x: 12 + CGFloat($0) * 18, y: 44, pressure: 0.5) }
        // Opacity below 1 forbids the clean cut (`VectorEraser.supportsCleanCut`), so this gesture
        // can only punch.
        XCTAssertTrue(soft.erase(alongPath: path, brush: Self.brush(), size: 12, opacity: 0.5,
                                 mode: .erase))
        XCTAssertEqual(soft.lastDamage, .appended(count: 1),
                       "a punch is one `.erase` element on the end of the list")

        let cut = Self.canvas(4)
        XCTAssertTrue(cut.erase(alongPath: path, brush: Self.brush(), size: 40, opacity: 1,
                                mode: .cutPoints))
        XCTAssertEqual(cut.lastDamage, .everything,
                       "Mode 2 replaces strokes with the pieces it cut them into")
    }
}
