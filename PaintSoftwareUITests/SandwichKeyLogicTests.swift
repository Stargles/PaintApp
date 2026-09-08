import XCTest
import UIKit

/// **`SandwichKey` is sufficient without `frame`** — TODO (54).
///
/// The owner, 2026-09-07: *"Lets say a frame in the animation is held for a couple cels where nothing
/// changes. The bake and cache seems to re-render each frame even though they are the same."*
///
/// They were right about the cache. `SandwichKey` carried `frame`, so the live canvas rebuilt both
/// half-composites on every playhead step whether or not one pixel of the picture had moved.
/// MEASURED in `BakeWiringUITests.testSteppingThroughAHoldDoesNotRecompositeTheLiveCanvasPerFrame`
/// before the field came out: seven held frames took `rebuilds:` from 5 to 12.
///
/// **This file is the other half of that change and the one that could go wrong quietly.** Dropping a
/// field from a cache key buys work back and risks a stale picture, and a stale picture is invisible
/// to every test that asserts on a stored value. So the assertion here is a **pixel** one, made over
/// pairs of frames:
///
/// > Whenever two frames of a document produce equal keys, the two half-composites they produce are
/// > byte-identical.
///
/// That is the contrapositive of "the key is complete", and it goes red exactly when the code is
/// wrong: a frame-dependent input the key does not carry shows up as two equal keys with two
/// different pictures. It is not a definition — nothing about the arithmetic makes it true, and
/// `testTheKeyIsInsufficientIfAFieldIsRemoved` demonstrates that by removing a *different* field and
/// watching the same sweep fail.
///
/// **Each battery document also has to contain at least one pair that differs**, or the sweep is
/// asserting over an empty set and every implementation passes. That is checked per document, not
/// once at the end.
///
/// `@MainActor` because `sandwichKey` and `makeSandwichRecipe` are — the app target compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and this one does not.
@MainActor
final class SandwichKeyLogicTests: XCTestCase {

    /// Held to CoreGraphics for `SandwichLogicTests`' reason: the claim here is byte-for-byte
    /// identity between two composites of the same content, and the shipped backend's own
    /// documented tolerance is not the subject.
    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)

    private struct Battery {
        let name: String
        let manager: CanvasManager
        let active: Int
        let frames: Int
    }

    /// Documents whose picture varies with the frame, one per mechanism that can make it vary.
    ///
    /// **Enumerated by mechanism rather than by shape**, which is the opposite of
    /// `SandwichLogicTests.battery()` and right for a different question: that file sweeps tree shapes
    /// because it is testing a *cut*, and this one sweeps the ways a frame can reach a pixel because
    /// it is testing whether a key names them. Every one of these is a route by which
    /// `makeSandwichRecipe`'s `frame` argument becomes different bytes.
    private func battery() -> [Battery] {
        var cases: [Battery] = []

        do {
            // The plain one: cel boundaries. Layer 0 holds 0–3 and then a second cel takes 4–7, so
            // there are two distinct pictures and two runs of holds.
            let manager = CanvasFixture.manager(layerCount: 2)
            CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 4), (start: 4, length: 4)])
            CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 8)])
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                          CanvasFixture.solidImage(red, rect: CGRect(x: 4, y: 4, width: 24, height: 24)))
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 4,
                                          CanvasFixture.solidImage(green, rect: CGRect(x: 20, y: 20, width: 24, height: 24)))
            CanvasFixture.setBakedContent(manager, layerIndex: 1, frame: 0,
                                          CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 40, width: 60, height: 12)))
            manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
            cases.append(Battery(name: "two cels, each held for four frames", manager: manager,
                                 active: 0, frames: 8))
        }

        do {
            // A layer that is simply absent for part of the scene — the nil entry in `contents`.
            let manager = CanvasFixture.manager(layerCount: 2)
            CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 8)])
            CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 3, length: 3)])
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                          CanvasFixture.solidImage(red, rect: CGRect(x: 4, y: 4, width: 40, height: 40)))
            CanvasFixture.setBakedContent(manager, layerIndex: 1, frame: 3,
                                          CanvasFixture.solidImage(green, rect: CGRect(x: 12, y: 12, width: 30, height: 30)))
            manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
            cases.append(Battery(name: "a layer whose block covers only the middle of the scene",
                                 manager: manager, active: 0, frames: 8))
        }

        do {
            // KEYFRAMES §4.4: a container pose, which reaches the picture through
            // `LayerContentVersion.pose` and through nothing else in this key — the field
            // `FrameBakeKey` records as the one its "no `default:`" rule could never have caught.
            // Keys at 0 and 3 of an eight-frame scene, so 4–7 are a hold past the last key.
            let manager = CanvasFixture.manager(layerCount: 1)
            CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 8)])
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                          CanvasFixture.solidImage(red, rect: CGRect(x: 2, y: 20, width: 20, height: 20)))
            manager.addValueLayer()
            let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
            let mover = manager.layers.count - 1
            manager.layers[mover].fill = nil
            manager.layers[mover].transform = LayerPose(
                pose: PoseQuad(restingIn: box),
                track: TransformTrack(keys: [
                    .init(frame: 0, pose: PoseQuad(restingIn: box)),
                    .init(frame: 3, pose: PoseQuad(box: box,
                                                   mappedBy: CGAffineTransform(translationX: 20, y: 0)))]))
            CanvasFixture.setCelLayout(manager, layerIndex: mover, [(start: 0, length: 8)])
            cases.append(Battery(name: "a transformation layer keyed at 0 and 3, held to 7",
                                 manager: manager, active: 0, frames: 8))
        }

        do {
            // An animated folder grade, which reaches the picture through the *tree* and through no
            // `LayerContentVersion` at all — RENDER §3.3's reason for putting the resolved tree in
            // the bake key.
            let manager = CanvasFixture.manager(layerCount: 2)
            CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 8)])
            CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 8)])
            CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                          CanvasFixture.solidImage(red, rect: CGRect(x: 4, y: 4, width: 40, height: 40)))
            CanvasFixture.setBakedContent(manager, layerIndex: 1, frame: 0,
                                          CanvasFixture.solidImage(green, rect: CGRect(x: 16, y: 16, width: 30, height: 30)))
            let folder = manager.addFolder(name: "Graded")
            manager.layers[1].parentFolderID = folder
            manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
            if let index = manager.folders.firstIndex(where: { $0.id == folder }) {
                manager.folders[index].effect = .brightnessContrast(.init(brightness: 0, contrast: 0))
                // Keyed to 3 and held to 7, so the grade produces two runs of identical frames and one
                // ramp between them. A *static* grade would make every frame of this document one
                // picture, which the "both operands" guard below rejects — and did, on the first
                // draft of this fixture.
                manager.folders[index].effectTracks["brightnessContrast.brightness"] =
                    AnimationCurve(keys: [AnimationCurve.Key(frame: 0, value: 0),
                                          AnimationCurve.Key(frame: 3, value: 0.6)])
            }
            cases.append(Battery(name: "a folder whose grade is keyed at 0 and 3, held to 7",
                                 manager: manager, active: 0, frames: 8))
        }

        return cases
    }

    /// The two halves `CanvasView.startSandwichRebuild` composites, as bytes.
    private func halves(_ manager: CanvasManager, atFrame frame: Int, active: Int) -> (Data, Data)? {
        guard let recipe = manager.makeSandwichRecipe(atFrame: frame, activeLayerIndex: active),
              let pair = recipe.compositeHalves() else { return nil }
        guard let below = Self.bytes(pair.below), let above = Self.bytes(pair.above) else { return nil }
        return (below, above)
    }

    private static func bytes(_ image: CGImage) -> Data? {
        let width = image.width, height = image.height, bytesPerRow = width * 4
        var buffer = Data(count: height * bytesPerRow)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? buffer : nil
    }

    // MARK: - The claim

    /// **Two frames with one key are two frames with one picture.**
    func testTwoFramesThatShareAKeyCompositeToTheSameBytes() throws {
        for battery in battery() {
            var equalPairs = 0, differingPairs = 0
            for a in 0..<battery.frames {
                let keyA = battery.manager.sandwichKey(atFrame: a, activeLayerIndex: battery.active)
                let pixelsA = try XCTUnwrap(halves(battery.manager, atFrame: a, active: battery.active),
                                            "\(battery.name): frame \(a) has to composite at all")
                for b in (a + 1)..<battery.frames {
                    let keyB = battery.manager.sandwichKey(atFrame: b, activeLayerIndex: battery.active)
                    guard keyA == keyB else { differingPairs += 1; continue }
                    equalPairs += 1
                    let pixelsB = try XCTUnwrap(halves(battery.manager, atFrame: b, active: battery.active))
                    XCTAssertEqual(pixelsA.0, pixelsB.0,
                                   "\(battery.name): frames \(a) and \(b) have one key and two "
                                   + "different `below` halves, so the key is short a field and the "
                                   + "live canvas will show \(a)'s picture at \(b)")
                    XCTAssertEqual(pixelsA.1, pixelsB.1,
                                   "\(battery.name): frames \(a) and \(b) have one key and two "
                                   + "different `above` halves")
                }
            }
            // Both operands, per document. A battery entry with no equal pair asserts nothing, and
            // one with no differing pair is a fixture whose frames are all the same picture — which
            // would make the sweep above true of a key with no fields at all.
            XCTAssertGreaterThan(equalPairs, 0,
                                 "\(battery.name): no two frames share a key, so this document "
                                 + "contributes no assertion")
            XCTAssertGreaterThan(differingPairs, 0,
                                 "\(battery.name): every pair of frames shares a key, so this "
                                 + "document does not vary per frame and proves nothing")
        }
    }

    /// **…and the sweep above is capable of failing**, which is the only thing that makes its silence
    /// worth anything.
    ///
    /// A key deliberately short of `contents` — the field that carries every cel boundary, every
    /// derivation and every container pose — is run through the same pairwise comparison. The
    /// documents in the battery are chosen so that at least one of them then produces two frames with
    /// one key and two pictures, which is exactly the failure the real sweep is watching for.
    ///
    /// **This is not a test of a broken key for its own sake**: it is the mutation test written down,
    /// so that a later change which quietly makes the sweep vacuous — a battery whose documents stop
    /// varying, a comparison that stops comparing — fails here instead of passing everywhere.
    func testTheSweepCatchesAKeyThatIsShortAField() {
        var caught: [String] = []
        for battery in battery() {
            for a in 0..<battery.frames {
                for b in (a + 1)..<battery.frames {
                    let keyA = battery.manager.sandwichKey(atFrame: a, activeLayerIndex: battery.active)
                    let keyB = battery.manager.sandwichKey(atFrame: b, activeLayerIndex: battery.active)
                    // The mutation: compare on everything except `contents`.
                    guard keyA.tree == keyB.tree,
                          keyA.activeLayerIndex == keyB.activeLayerIndex,
                          keyA.renderResolution == keyB.renderResolution,
                          keyA.canvasBackgroundColor == keyB.canvasBackgroundColor,
                          keyA.isCanvasBackgroundVisible == keyB.isCanvasBackgroundVisible
                    else { continue }
                    guard let pixelsA = halves(battery.manager, atFrame: a, active: battery.active),
                          let pixelsB = halves(battery.manager, atFrame: b, active: battery.active)
                    else { continue }
                    if pixelsA.0 != pixelsB.0 || pixelsA.1 != pixelsB.1 {
                        caught.append("\(battery.name): frames \(a) and \(b)")
                    }
                }
            }
        }
        XCTAssertFalse(caught.isEmpty, """
            Dropping `contents` from the comparison has to produce at least one pair of frames that \
            share a key and do not share a picture. It did not, which means the battery no longer \
            varies in a way `contents` is the only field to carry — so \
            `testTwoFramesThatShareAKeyCompositeToTheSameBytes` is passing over documents that could \
            not have failed it.
            """)
    }

    /// **The frame number is the one thing the key does not carry, and this says so as a behaviour
    /// rather than as a field list.**
    ///
    /// A hold is the case the owner reported: a cel spanning several frames, nothing else in the
    /// document varying. Every frame of it has to mint one key — which is what lets
    /// `CanvasView.updateSandwich` skip the rebuild — and the frames either side of the boundary have
    /// to mint two, which is what stops it skipping one it needed.
    func testEveryFrameOfAHoldMintsOneKeyAndTheNextCelMintsAnother() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 5), (start: 5, length: 3)])
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 8)])
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 4, y: 4, width: 30, height: 30)))
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 5,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 24, y: 24, width: 30, height: 30)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1, frame: 0,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 0, width: 64, height: 8)))
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)

        let keys = (0..<8).map { manager.sandwichKey(atFrame: $0, activeLayerIndex: 0) }
        XCTAssertEqual(Set(keys[0..<5].map { $0 == keys[0] }), [true],
                       "Five frames of one cel are one picture and must be one key — a key that "
                       + "moved here is a live composite per frame of every hold in every document")
        XCTAssertEqual(Set(keys[5..<8].map { $0 == keys[5] }), [true],
                       "…and so are the three frames of the cel after it")
        XCTAssertNotEqual(keys[4], keys[5],
                          "The cel boundary must move the key. A key that did not would leave the "
                          + "canvas showing the first cel for the whole scene")
    }
}
