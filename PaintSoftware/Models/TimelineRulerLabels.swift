import CoreGraphics
import Foundation

/// **What the timeline's ruler writes along its top edge, at the zoom the artist has pinched to** —
/// TODO (122): *"When the timeline is zoomed out it should display seconds instead of frames."*
///
/// **Two vocabularies, and the zoom decides between them by one test: does every frame's number fit
/// in its own column?** Zoomed in, the ruler labels each frame (`1`, `2`, `3`…, the way the frame
/// readout counts), because at that zoom the artist is placing drawings on frames and a frame is the
/// unit that matters. Zoomed out until the numbers would run into each other, it labels *time*
/// instead — `1s`, `2s`… from the document's frame rate — because at that zoom the artist is
/// surveying the scene's length and a whole second is the unit that reads at a glance. Thinning the
/// frame numbers (every 5th, every 10th) was the other answer and is not taken: a ruler of `5 10 15`
/// is still frames, and the owner asked for seconds.
///
/// **The threshold is a relationship, not a number.** What decides is the widest label the window
/// holds against the column it must fit in (`minimumPitch(forCharacters:)`), so a long scene — whose
/// frame numbers are five digits wide — switches earlier than a short one, and neither can ever show
/// two numbers on top of each other. It is stated in points for the reason `TimelineKeyMarkers`'
/// collapse threshold is: what collides is pixels.
///
/// **In seconds the labels thin themselves to what fits.** A label sits on a second boundary (frame
/// index `n × fps`, which is where second `n` begins — frame `i` is shown at time `i / fps`) and the
/// stride between labelled seconds is the smallest of 1, 2, 5, 10, 15, 30, 60… that leaves each its
/// own room. The frames between two labelled seconds are not labelled at all, and the ruler's
/// gridlines — one per frame, at every zoom — are the ticks between.
///
/// **Why this is a type and not arithmetic inside the ruler view**, for the standing reason:
/// `Views/TimelineRulerStrip.swift` is not compiled into `PaintSoftwareUITests`, so a decision made
/// there is decided where no fast-tier test can see it. The view keeps the font and the
/// `NSString.draw`.
enum TimelineRulerLabels {

    // MARK: - How big a label is

    /// The ruler's font size. The view reads it so the width model below is about the glyphs it
    /// actually draws.
    static let fontSize: CGFloat = 9
    /// How far a label sits right of its column's leading edge.
    static let labelInset: CGFloat = 2
    /// One glyph's advance at `fontSize`. The system font's digits are tabular and a hair under 0.6 em;
    /// the colon and the `s` of a time label are narrower, so a label is never wider than this says.
    static let glyphWidth: CGFloat = 5.5
    /// The smallest daylight between one label's end and the next one's start.
    static let labelGap: CGFloat = 4

    /// **The column a label of `characters` characters needs to itself** — the inset it starts at, its
    /// glyphs, and the gap before the next. A label and its neighbour closer than this collide.
    static func minimumPitch(forCharacters characters: Int) -> CGFloat {
        labelInset + CGFloat(characters) * glyphWidth + labelGap
    }

    // MARK: - The plan

    enum Unit: String, Equatable {
        case frames
        case seconds
    }

    /// How the ruler is labelled at one zoom: in which unit, and how many frames lie between two
    /// labelled ticks.
    struct Plan: Equatable {
        let unit: Unit
        /// 1 for frame numbers; the labelled seconds' stride times `framesPerSecond` for seconds.
        let framesBetweenLabels: Int
        fileprivate let framesPerSecond: Int

        /// The label of the tick at `frame` (a 0-based frame index), or nil when no label sits there.
        func label(atFrame frame: Int) -> String? {
            guard frame >= 0, frame % framesBetweenLabels == 0 else { return nil }
            switch unit {
            case .frames:  return "\(frame + 1)"
            case .seconds: return TimelineRulerLabels.secondsText(frame / framesPerSecond)
            }
        }

        /// The frames in `frames` that carry a label, ascending.
        func labelledFrames(in frames: Range<Int>) -> [Int] {
            guard !frames.isEmpty else { return [] }
            let first = max(frames.lowerBound, 0)
            let aligned = (first + framesBetweenLabels - 1) / framesBetweenLabels * framesBetweenLabels
            guard aligned < frames.upperBound else { return [] }
            return Array(stride(from: aligned, to: frames.upperBound, by: framesBetweenLabels))
        }
    }

    /// **The labelling for a window ending at frame `lastFrame`.** The window's last frame is the one
    /// with the widest label, so it is the one the fit is judged on.
    ///
    /// - Parameters:
    ///   - pixelsPerFrame: the zoom — the width of one frame's column.
    ///   - framesPerSecond: the document's frame rate. Floored at 1 rather than trusted: it is a
    ///     divisor.
    ///   - lastFrame: the highest 0-based frame index the window shows.
    static func plan(pixelsPerFrame: CGFloat, framesPerSecond: Int, lastFrame: Int) -> Plan {
        let fps = max(framesPerSecond, 1)
        let widestFrameLabel = String(max(lastFrame, 0) + 1).count
        if pixelsPerFrame >= minimumPitch(forCharacters: widestFrameLabel) {
            return Plan(unit: .frames, framesBetweenLabels: 1, framesPerSecond: fps)
        }
        let widestSecondsLabel = secondsText(max(lastFrame, 0) / fps).count
        let needed = minimumPitch(forCharacters: widestSecondsLabel)
        let seconds = secondsStrides.first { CGFloat($0 * fps) * pixelsPerFrame >= needed }
            ?? secondsStrides[secondsStrides.count - 1]
        return Plan(unit: .seconds, framesBetweenLabels: seconds * fps, framesPerSecond: fps)
    }

    /// The seconds between two labelled ticks, smallest first: the numbers a person counts in.
    static let secondsStrides = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]

    /// **`5s`, then `1:05`, then `1:00:05`** — seconds spelled as the number of them until a minute is
    /// worth saying, then as a clock. The suffix is dropped once the colon makes the unit plain.
    static func secondsText(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        if total < 60 { return "\(total)s" }
        let minutes = total / 60 % 60
        let remainder = total % 60
        let hours = total / 3600
        let pad: (Int) -> String = { $0 < 10 ? "0\($0)" : "\($0)" }
        if hours == 0 { return "\(minutes):\(pad(remainder))" }
        return "\(hours):\(pad(minutes)):\(pad(remainder))"
    }

    // MARK: - What a test can see

    /// The ruler's accessibility value: the unit, a colon, then every label in `frames` in order and
    /// comma-separated — `"seconds:0s,1s,2s"`, `"frames:1,2,3"`. What the artist reads off the ruler,
    /// as text, so a UI test can ask which vocabulary is on screen and not only that something is.
    static func encode(_ plan: Plan, frames: Range<Int>) -> String {
        let labels = plan.labelledFrames(in: frames).compactMap { plan.label(atFrame: $0) }
        return "\(plan.unit.rawValue):" + labels.joined(separator: ",")
    }
}
