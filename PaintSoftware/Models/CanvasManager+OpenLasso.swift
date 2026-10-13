import CoreGraphics

// MARK: - The open lasso

/// **A freehand lasso the artist has not closed yet** — TODO (184), the owner: *"The user lasso selects,
/// and a node spawns in the place where they first put down their pen. When the node is clicked again
/// it completes the selection, and the user can move on to the next selection which gets booleaned.
/// Thus, if the user taps instead of draws, the select will automatically jump to the new location,
/// forming a polygon like shape. For example if the user taps on the 4 edges of a square, the select
/// forms a square. The previous drawing behaviour should also work."*
///
/// **One polyline in canvas points: the start node first, the open end last.** Everything the pen does in
/// Freehand adds to it — a drawn stroke adds its samples, a tap adds one corner — and the straight edge
/// from the open end to wherever the pen next lands is the polyline's own next segment, so a stroke that
/// joins a lasso needs no rule of its own. A *run* is the points one gesture added, and what Undo takes
/// back one press at a time is a run.
///
/// It is a different thing from `Selection`: nothing is selected until it closes, and the selection
/// already up (which the closed loop will be added to or taken from) stays up under it.
struct OpenLasso: Equatable {
    private(set) var points: [CGPoint]
    /// How many points each run added, oldest first. Their sum is `points.count`.
    private var runLengths: [Int]

    /// Nil for a run with nothing in it.
    init?(startingWith run: [CGPoint]) {
        guard !run.isEmpty else { return nil }
        points = run
        runLengths = [run.count]
    }

    /// The node: where the pen first landed.
    var start: CGPoint { points[0] }
    /// Where the next stroke or tap will be joined on to.
    var end: CGPoint { points[points.count - 1] }

    mutating func append(_ run: [CGPoint]) {
        guard !run.isEmpty else { return }
        points += run
        runLengths.append(run.count)
    }

    /// Takes the last corner or drawn stroke off. False when that was everything, which is the lasso
    /// ending rather than a lasso with nothing in it.
    mutating func removeLastRun() -> Bool {
        guard runLengths.count > 1, let last = runLengths.popLast() else { return false }
        points.removeLast(last)
        return true
    }

    /// Whether `point` is on the start node.
    func isOnStart(_ point: CGPoint, within reach: CGFloat) -> Bool {
        point.distance(to: start) <= reach
    }

    /// Whether a pen lifting or tapping at `point` closes the lasso: it is on the start node, and there
    /// is a shape to close — at least a triangle's worth of points, at least one of them beyond the
    /// node, so a stroke that never left the node it started on is not a loop and two taps on one spot
    /// are not a polygon.
    func closes(at point: CGPoint, within reach: CGFloat) -> Bool {
        guard points.count >= 3, isOnStart(point, within: reach) else { return false }
        return points.contains { !isOnStart($0, within: reach) }
    }

    /// The loop it makes when it closes: the polyline, and the straight edge back from the open end to
    /// the node.
    var closedPath: CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}

extension CanvasManager {

    /// **A stroke lifted in Freehand.** It joins the open lasso — or begins one, its first sample the
    /// node — and if it ended back on the start node the lasso closes on the lift: the selection the
    /// artist has always got from drawing a loop. Lifted anywhere else it stays open for the next
    /// stroke or tap.
    ///
    /// - Parameter nodeReach: how close to the node counts as on it, in canvas points — a screen-point
    ///   figure the overlay has divided by the canvas scale, so the node is as easy to hit zoomed in as
    ///   out.
    func liftLassoStroke(_ run: [CGPoint], nodeReach: CGFloat) {
        var lasso: OpenLasso
        if var open = openLasso {
            open.append(run)
            lasso = open
        } else if let begun = OpenLasso(startingWith: run) {
            lasso = begun
        } else {
            return
        }
        if lasso.closes(at: lasso.end, within: nodeReach) {
            close(lasso)
        } else {
            openLasso = lasso
        }
    }

    /// **A tap in Freehand**: the first one drops the node, a tap on the node of a lasso that has a shape
    /// closes it, and any other tap is a corner with a straight edge from the open end. A tap on the
    /// node of a lasso that has no shape yet does nothing — there is nothing to close and a corner on
    /// the node would be a zero-length edge.
    func tapLasso(at point: CGPoint, nodeReach: CGFloat) {
        guard var lasso = openLasso else {
            openLasso = OpenLasso(startingWith: [point])
            return
        }
        if lasso.closes(at: point, within: nodeReach) {
            close(lasso)
        } else if !lasso.isOnStart(point, within: nodeReach) {
            lasso.append([point])
            openLasso = lasso
        }
    }

    /// Closes the lasso into a loop and hands it to `finishSelection` — the door a rectangle and the
    /// wand arrive by — so it adds to or subtracts from the selection exactly as they do.
    private func close(_ lasso: OpenLasso) {
        openLasso = nil
        finishSelection(path: lasso.closedPath)
    }

    /// **Undo while a lasso is open takes back its last corner or stroke** (TODO (184)), and the lasso
    /// ends with its last run. The history is not touched: nothing an open lasso did is in it.
    func retractOpenLasso() {
        guard var lasso = openLasso else { return }
        openLasso = lasso.removeLastRun() ? lasso : nil
    }

    /// Puts an open lasso down without selecting anything — switching tool or selection mode, tapping
    /// the Select icon, or any edit that takes the canvas for itself.
    func abandonOpenLasso() {
        if openLasso != nil { openLasso = nil }
    }
}
