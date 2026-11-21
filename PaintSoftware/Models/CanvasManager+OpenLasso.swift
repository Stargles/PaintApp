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
/// **An open lasso acts as a closed one** (LASSO_MOVE.md §5.29, owner 2026-11-17: *"even if the lasso is
/// open, it should still treat it as a closed one. The circle to close it is for if the user wants to
/// make a new selection."*). Every change it makes — a stroke, a corner, an Undo — writes the selection as
/// the lasso's polyline closed by a straight edge from its open end back to the node, added to or taken
/// from the selection that stood when it began (`OpenLassoBase`). So every consumer reads the one
/// `CanvasManager.selection`; none knows a lasso is open. Closing on the node, or anything that takes
/// the canvas for itself, only ends the lasso: the selection is already there, and the step lands.
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

    /// Whether it encloses anything: three points, at least one of them off the node.
    func hasShape(reach: CGFloat) -> Bool {
        points.count >= 3 && points.contains { !isOnStart($0, within: reach) }
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

/// The selection that stood when an open lasso began (`CanvasManager.openLassoBase`). A wrapper so that
/// "a lasso begun over no selection" is not mistaken for "no lasso".
struct OpenLassoBase {
    var selection: Selection?
    /// The start node's reach at the last change, in canvas points: a lasso that never left the node is
    /// not a loop and selects nothing, as it closes on nothing (`OpenLasso.closes`).
    var reach: CGFloat = 0
}

extension CanvasManager {

    /// **A stroke lifted in Freehand.** It joins the open lasso — or begins one, its first sample the
    /// node — and if it ended back on the start node the lasso closes on the lift. Lifted anywhere else
    /// it stays open for the next stroke or tap, and acts as closed all the same.
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
            update(lasso, reach: nodeReach)
            settleOpenLasso()
        } else {
            update(lasso, reach: nodeReach)
        }
    }

    /// **A tap in Freehand**: the first one drops the node, a tap on the node of a lasso that has a shape
    /// closes it, and any other tap is a corner with a straight edge from the open end. A tap on the
    /// node of a lasso that has no shape yet does nothing — there is nothing to close and a corner on
    /// the node would be a zero-length edge.
    func tapLasso(at point: CGPoint, nodeReach: CGFloat) {
        guard var lasso = openLasso else {
            if let begun = OpenLasso(startingWith: [point]) { update(begun, reach: nodeReach) }
            return
        }
        if lasso.closes(at: point, within: nodeReach) {
            settleOpenLasso()
        } else if !lasso.isOnStart(point, within: nodeReach) {
            lasso.append([point])
            update(lasso, reach: nodeReach)
        }
    }

    /// Writes a lasso that changed, and the selection it now acts as.
    private func update(_ lasso: OpenLasso, reach: CGFloat) {
        if openLassoBase == nil { openLassoBase = OpenLassoBase(selection: selection) }
        openLassoBase?.reach = reach
        openLasso = lasso
        syncSelectionToOpenLasso()
    }

    /// **The selection is the lasso's polyline closed** — added to or taken from what stood when the
    /// lasso began, by the rule a closed loop meets a selection (`selectionAfterLoop`). A lasso with
    /// fewer than three points encloses nothing, so the selection is the base. The one place an open
    /// lasso becomes a region.
    private func syncSelectionToOpenLasso() {
        guard let base = openLassoBase else { return }
        guard let lasso = openLasso, lasso.hasShape(reach: base.reach) else {
            selection = base.selection
            return
        }
        guard beginCanvasEdit() else { return }
        switch selectionAfterLoop(lasso.closedPath, onto: base.selection) {
        case .selection(let after): selection = after
        case .ignored, .refusedSubtract: selection = base.selection
        }
    }

    /// **Ends the open lasso and keeps what it selected** — the close on the node, and the landing for a
    /// tool or panel switch, another selection mode, or any edit that takes the canvas for itself. The
    /// selection is already written; this records the one undo step a closed loop leaves (TODO (182)) and
    /// says so when a subtract had nothing to take from.
    func settleOpenLasso() {
        guard let base = openLassoBase else { openLasso = nil; return }
        let hadShape = openLasso?.hasShape(reach: base.reach) ?? false
        openLasso = nil
        openLassoBase = nil
        guard hadShape else { return }
        if base.selection?.isRegion != true && subtractsSelection {
            raise(.nothingToSubtractFrom)
            return
        }
        // A loop too small to enclose anything left the selection as it was: no step.
        if let now = selection, let was = base.selection, now.path === was.path { return }
        recordSelectionStep(from: base.selection, to: selection, label: loopHistoryLabel(onto: base.selection))
    }

    /// Puts the lasso down and the selection back to what stood before it — Deselect's first half.
    func discardOpenLasso() {
        guard let base = openLassoBase else { openLasso = nil; return }
        openLasso = nil
        openLassoBase = nil
        selection = base.selection
    }

    /// **Undo while a lasso is open takes back its last corner or stroke** (TODO (184)), and the lasso
    /// ends with its last run, leaving the selection as it stood before. The history is not touched:
    /// nothing an open lasso did is in it until it settles.
    func retractOpenLasso() {
        guard var lasso = openLasso else { return }
        if lasso.removeLastRun() {
            update(lasso, reach: openLassoBase?.reach ?? 0)
        } else {
            discardOpenLasso()
        }
    }
}
