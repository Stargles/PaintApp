import XCTest

/// **When the whole-frame picture of a held grade comes down** — `HeldFrameLanding`, TODO (179).
///
/// Down a frame early is the old grade flashing for a bake's length; up a frame late hides an edit
/// made after the lift. The rule is pure, so each side is pinned here with two keys that differ in
/// one layer's content, the way the canvas's own keys differ before and after a grade is written.
@MainActor
final class HeldFrameLandingLogicTests: XCTestCase {

    /// Two distinct keys of one tiny document — before and after its grade moved.
    private func twoKeys() -> (SandwichKey, SandwichKey) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        let before = manager.sandwichKey(atFrame: 0, activeLayerIndex: 1, holding: [:],
                                         tree: manager.renderTree(atFrame: 0))
        manager.setLayerEffect(layerIndex: 1, to: .brightnessContrast(Effect.BrightnessContrast(brightness: 1.5,
                                                                                               contrast: 1)))
        let after = manager.sandwichKey(atFrame: 0, activeLayerIndex: 1, holding: [:],
                                        tree: manager.renderTree(atFrame: 0))
        return (before, after)
    }

    /// **Up through the hold, and after it until the canvas's own picture of the written key is on
    /// screen** — the bake arriving a pass or several after the lift.
    func testItStaysUpAfterTheLiftUntilThePictureOfTheWrittenKeyIsShown() {
        let (before, after) = twoKeys()
        XCTAssertNotEqual(before, after, "Fixture check: writing the grade moves the key")
        var landing = HeldFrameLanding()
        XCTAssertFalse(landing.isUp)

        landing.update(held: true)
        landing.pass(key: before, pictureIsCurrent: true)
        XCTAssertTrue(landing.isUp, "held: up whatever the canvas shows under it")

        landing.update(held: false)
        XCTAssertTrue(landing.isUp, "the lift alone does not take it down")
        landing.pass(key: after, pictureIsCurrent: false)
        XCTAssertTrue(landing.isUp, "the bake of the written grade has not landed")
        landing.pass(key: after, pictureIsCurrent: false)
        XCTAssertTrue(landing.isUp, "…and still has not")
        landing.pass(key: after, pictureIsCurrent: true)
        XCTAssertFalse(landing.isUp, "it has: down")
    }

    /// **A revert comes down on the first pass**: nothing was written, so the canvas's picture is
    /// already of the key it is on.
    func testARevertComesDownOnTheFirstPass() {
        let (before, _) = twoKeys()
        var landing = HeldFrameLanding()
        landing.update(held: true)
        landing.update(held: false)
        landing.pass(key: before, pictureIsCurrent: true)
        XCTAssertFalse(landing.isUp)
    }

    /// **An edit after the lift takes it down at once** — the held frame shows the written grade, and a
    /// key that moved past that one (an undo, another edit) means it is no longer the truth.
    func testAKeyThatMovesPastTheLandingTakesItDown() {
        let (before, after) = twoKeys()
        var landing = HeldFrameLanding()
        landing.update(held: true)
        landing.update(held: false)
        landing.pass(key: after, pictureIsCurrent: false)
        XCTAssertTrue(landing.isUp)
        landing.pass(key: before, pictureIsCurrent: false)
        XCTAssertFalse(landing.isUp, "the document moved on before the bake landed")
    }

    /// **A canvas the compositor is not drawing** has nothing to wait for — the hosts draw the
    /// document as it is — and **a new hold while landing is a hold**.
    func testADisengagedCanvasLandsAtOnceAndANewHoldWins() {
        let (_, after) = twoKeys()
        var landing = HeldFrameLanding()
        landing.update(held: true)
        landing.update(held: false)
        landing.pass(key: nil, pictureIsCurrent: true)
        XCTAssertFalse(landing.isUp)

        landing.update(held: true)
        landing.update(held: false)
        landing.pass(key: after, pictureIsCurrent: false)
        landing.update(held: true)
        landing.pass(key: after, pictureIsCurrent: true)
        XCTAssertTrue(landing.isUp, "a finger back on a slider is a hold, whatever the canvas shows")
        XCTAssertEqual(landing.phase, .held)
    }
}
