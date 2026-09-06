import XCTest
import UIKit

/// **What `TimelineTrackView.Coordinator.relayout`'s un-removable `require(toFail:)` actually costs.**
///
/// `relayout` calls `scrollView.panGestureRecognizer.require(toFail: row.panRecognizer)` once for
/// every row view the pool ever creates, and UIKit has no API to take a failure requirement back.
/// The pool grows with the layer count and shrinks with `rowViews.removeLast().removeFromSuperview()`,
/// so the obvious reading is that the scroll view's pan accumulates a permanent, unbounded set of
/// dependencies on recognizers whose views are gone. Two separate investigations of TODO (39)(c)
/// reached that reading independently and it is **wrong**, which is why it is pinned here rather than
/// left to be re-derived a third time.
///
/// MEASURED on iOS 26.5 (iPad Pro 13-inch M4 simulator, 2026-09-06), by reading the recognizer's
/// private `_failureRequirements` in a throwaway probe: it is an `NSSet` that **deduplicates** (the
/// same pair required three times is one entry) and holds its members **weakly** — required
/// recognizer deallocated, count 1 → 0. `UIGestureRecognizer` does not retain its action target
/// either, so nothing survives a row leaving the pool. A harness that appeared to show the set
/// growing 3, 6, 9, … across add/remove cycles was measuring its own autorelease pool: the same
/// cycles wrapped in `autoreleasepool` hold flat.
///
/// This test is the public-API half of that measurement, and it is the half that matters: **if a
/// future UIKit starts retaining, `relayout` becomes a real leak and a real unbounded set**, and
/// this goes red. It cannot use `_failureRequirements` itself — a test that reads a private ivar
/// stops testing silently the day Apple renames it.
final class TimelineGestureArbitrationLogicTests: XCTestCase {

    /// The exact shape of `relayout`'s pool churn: add a row with a pan, require it, drop the row.
    func testAFailureRequirementDoesNotOutliveTheRowViewItWasMadeFor() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let contentView = UIView(frame: scrollView.bounds)
        scrollView.addSubview(contentView)

        weak var rowAfterwards: UIView?
        weak var rowPanAfterwards: UIPanGestureRecognizer?

        autoreleasepool {
            let row = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 30))
            let rowPan = UIPanGestureRecognizer(target: row, action: nil)
            row.addGestureRecognizer(rowPan)
            contentView.addSubview(row)
            scrollView.panGestureRecognizer.require(toFail: rowPan)
            rowAfterwards = row
            rowPanAfterwards = rowPan

            XCTAssertNotNil(rowAfterwards,
                            "the fixture is wrong if the row is already gone while it is in the pool")
            XCTAssertNotNil(rowPanAfterwards)

            // `relayout`'s shrink, verbatim: `rowViews.removeLast().removeFromSuperview()`.
            row.removeFromSuperview()
        }

        XCTAssertNotNil(scrollView.panGestureRecognizer,
                        "the depender has to outlive the required recognizer for this to mean anything")
        XCTAssertNil(rowPanAfterwards,
                     "the scroll view's pan is still alive and still 'requires' this recognizer to "
                     + "fail, so if the requirement were a strong reference the recognizer would "
                     + "still be here — and `relayout` would accumulate one per row ever created")
        XCTAssertNil(rowAfterwards,
                     "and the row view goes with it: `UIGestureRecognizer` does not retain the "
                     + "target it was created with, so a row that leaves the pool takes its cel "
                     + "views and thumbnails with it")
    }

    /// The same, run the way the pool actually moves: grow to three, shrink to none, ten times over.
    /// A leak of one recognizer per row would be thirty here rather than one.
    func testRepeatedPoolChurnLeavesNothingBehind() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let contentView = UIView(frame: scrollView.bounds)
        scrollView.addSubview(contentView)

        // **Both halves are tracked, and that is not belt-and-braces.** A first draft watched only
        // the row views, and stayed green under a mutation that leaked every *recognizer* — because
        // a `UIPanGestureRecognizer` does not retain the target it was built with, so the rows died
        // anyway. The recognizers are what `_failureRequirements` holds, so they are the operand the
        // accumulation claim is about; the rows are the second, separate fact.
        var liveRecognizers: [() -> Bool] = []
        var liveRows: [() -> Bool] = []
        var peak = 0

        for _ in 0..<10 {
            autoreleasepool {
                var pool: [UIView] = []
                while pool.count < 3 {
                    let row = UIView(frame: .zero)
                    let rowPan = UIPanGestureRecognizer(target: row, action: nil)
                    row.addGestureRecognizer(rowPan)
                    contentView.addSubview(row)
                    scrollView.panGestureRecognizer.require(toFail: rowPan)
                    pool.append(row)
                    weak var weakRow: UIView? = row
                    weak var weakPan: UIPanGestureRecognizer? = rowPan
                    liveRows.append { weakRow != nil }
                    liveRecognizers.append { weakPan != nil }
                }
                peak = max(peak, liveRecognizers.filter { $0() }.count)
                while !pool.isEmpty { pool.removeLast().removeFromSuperview() }
            }
        }

        XCTAssertEqual(peak, 3,
                       "the fixture is wrong if more than one cycle's rows are ever alive at once")
        XCTAssertEqual(liveRecognizers.filter { $0() }.count, 0,
                       "thirty recognizers were required to fail by a scroll pan that is still "
                       + "alive; if any survive, `relayout` accumulates and TODO (39)(c)'s suspect "
                       + "is real")
        XCTAssertEqual(liveRows.filter { $0() }.count, 0,
                       "and thirty row views with them, which would be a leak of every cel view and "
                       + "thumbnail the pool has ever held")
    }
}
