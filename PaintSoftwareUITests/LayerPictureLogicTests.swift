import XCTest
import UIKit

/// **`LayerPicture`'s promises** — SCHEDULER_DESIGN.md §3.1, S3b: a picture repaired in place is never
/// read across a write, every revision is a new wrapper, a write touches only its patch's pixels, and a
/// patch drawn in canvas points lands where the whole picture would have put it.
final class LayerPictureLogicTests: XCTestCase {

    private static let size = CGSize(width: 64, height: 48)

    /// A picture of a red square at (8, 8, 16, 16).
    private func picture() throws -> LayerPicture {
        try XCTUnwrap(LayerPicture.draw(size: Self.size) { cg in
            cg.setFillColor(UIColor.red.cgColor)
            cg.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
            return true
        })
    }

    /// The BGRA bytes of `image` at canvas pixel (x, y), read through a copy.
    private func pixel(_ image: UIImage, _ x: Int, _ y: Int) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cg.dataProvider?.data) as Data
        let offset = y * cg.bytesPerRow + x * 4
        return Array(data[offset..<offset + 4])
    }

    /// **Every way the app reads a picture lets go of it.** CoreGraphics reads a layer picture through a
    /// direct-access provider whose byte pointer counts a reader in; a reader that stayed counted would
    /// hold every later write off for good. Drawn into a context, copied out, and dropped: none stays.
    ///
    /// Mutation that reddens it: drop `endRead()` from the provider's `releaseBytePointer`.
    func testReadingAPictureLeavesNoReaderBehind() throws {
        let picture = try picture()
        let image = picture.image
        let sink = try XCTUnwrap(PixelOps.drawImage(size: Self.size) { _ in
            image.draw(at: .zero)
            return true
        })
        XCTAssertEqual(try pixel(sink, 10, 10), [0, 0, 255, 255], "PREMISE: the draw drew the square")
        _ = try pixel(image, 10, 10)
        XCTAssertEqual(picture.readersInFlight, 0, "a finished read is still counted against the next write")
        XCTAssertTrue(picture.exclusively(timeout: 0.05) {}, "a write could not get the picture after reads ended")
    }

    /// **A write waits for the read in flight, and the read sees one picture whole.** A reader holds the
    /// fence (`read`) while a writer asks for the picture: the writer must not get in until the reader is
    /// out, and must get in once it is.
    ///
    /// Mutation that reddens it: drop the `readers > 0` wait in `exclusively`.
    func testAWriteWaitsForTheReaderInFlight() throws {
        let picture = try picture()
        let readerIn = DispatchSemaphore(value: 0), letGo = DispatchSemaphore(value: 0)
        let readerOut = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            picture.read { _ in
                readerIn.signal()
                letGo.wait()
            }
            readerOut.signal()
        }
        readerIn.wait()
        XCTAssertFalse(picture.exclusively(timeout: 0.05) {}, "a write got in while a reader was reading")
        letGo.signal()
        readerOut.wait()
        XCTAssertTrue(picture.exclusively(timeout: 1) {}, "a write could not get in after the reader left")
    }

    /// **A write changes its patch's pixels and no others, and moves the revision only when it says so.**
    /// The wrapper handed out before the write stops being current; the new one is a different object
    /// over the same bytes.
    ///
    /// Mutation that reddens it: an off-by-one row in `write` (the patch lands a row low).
    func testAWriteTouchesItsPatchOnlyAndANewRevisionIsANewWrapper() throws {
        let picture = try picture()
        let before = picture.image
        XCTAssertTrue(LayerPicture.isCurrent(before))
        let rect = try XCTUnwrap(picture.pixelRect(of: CGRect(x: 8, y: 8, width: 8, height: 8)))
        let patch = try XCTUnwrap(PixelPatch(rect: rect, scale: 1))
        XCTAssertTrue(patch.draw { cg in
            cg.setFillColor(UIColor.blue.cgColor)
            cg.fill(CGRect(x: 8, y: 8, width: 8, height: 8))
            return true
        })
        var after: UIImage?
        XCTAssertTrue(picture.exclusively(timeout: 1) {
            picture.write(patch)
            after = picture.revise()
        })
        let image = try XCTUnwrap(after)
        XCTAssertFalse(image === before, "a new revision must be a new wrapper, or an identity check calls it the same picture")
        XCTAssertFalse(LayerPicture.isCurrent(before), "the old wrapper still claims the pixels it was handed")
        XCTAssertTrue(LayerPicture.isCurrent(image))
        XCTAssertEqual(try pixel(image, 8, 8), [255, 0, 0, 255], "the patch's corner is not blue")
        XCTAssertEqual(try pixel(image, 15, 15), [255, 0, 0, 255], "the patch's far corner is not blue")
        XCTAssertEqual(try pixel(image, 16, 16), [0, 0, 255, 255], "the square outside the patch changed")
        XCTAssertEqual(try pixel(image, 8, 16), [0, 0, 255, 255], "the row below the patch changed")
        XCTAssertEqual(try pixel(image, 30, 30), [0, 0, 0, 0], "the paper outside the patch changed")
    }

    /// **A patch drawn in canvas points draws what the whole picture would have**, pixel for pixel: the
    /// same antialiased circle drawn into a patch at an odd offset and into a whole picture agree in every
    /// byte the patch covers. This is what lets a repair walk only its damage.
    ///
    /// Mutation that reddens it: drop the `translateBy(-rect.x, -rect.y)` in `PixelPatch.draw`.
    func testAPatchDrawsExactlyWhatTheWholePictureDraws() throws {
        let circle = CGRect(x: 13.3, y: 9.7, width: 21.4, height: 17.9)
        let whole = try XCTUnwrap(LayerPicture.draw(size: Self.size) { cg in
            cg.setFillColor(UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 0.7).cgColor)
            cg.fillEllipse(in: circle)
            return true
        }).image
        let rect = PixelRect(x: 11, y: 7, width: 27, height: 23)
        let patch = try XCTUnwrap(PixelPatch(rect: rect, scale: 1))
        XCTAssertTrue(patch.draw { cg in
            cg.setFillColor(UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 0.7).cgColor)
            cg.fillEllipse(in: circle)
            return true
        })
        let patchImage = UIImage(cgImage: patch.cgImage)
        var differing = 0
        for y in 0..<rect.height {
            for x in 0..<rect.width where try pixel(patchImage, x, y) != pixel(whole, rect.x + x, rect.y + y) {
                differing += 1
            }
        }
        XCTAssertEqual(differing, 0, "\(differing) pixels of the patch differ from the whole picture's")
    }
}
