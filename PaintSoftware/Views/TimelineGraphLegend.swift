import Combine
import SwiftUI
import UIKit

// **The graph editor's legend — which coloured line is which.** The decisions are `TimelineGraphBand`'s
// (`LegendEntry`, `legend(of:)`, `legendLines(of:)`); this file is the SwiftUI the name column draws it
// with, the object that carries it there from the track, and the one place a curve's `Colour` becomes a
// colour on screen.

extension TimelineGraphBand.Colour {
    /// **The one conversion from a curve's colour to something drawable.** The band's strokes, the
    /// channel list's swatches and the legend's lines all take their colour here, so a curve and the
    /// words that name it cannot be two slightly different colours.
    func uiColor(alpha: CGFloat = 1) -> UIColor {
        UIColor(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: alpha)
    }
}

/// A curve's swatch: filled for an animation, hollow for a curve merely in force — the key dots the band
/// draws, in the list and the legend alike.
struct GraphChannelSwatch: View {
    let colour: TimelineGraphBand.Colour
    let isAnimated: Bool

    var body: some View {
        Group {
            if isAnimated {
                Circle().fill(Color(uiColor: colour.uiColor()))
            } else {
                Circle().strokeBorder(Color(uiColor: colour.uiColor()), lineWidth: 1.5)
            }
        }
        .frame(width: 8, height: 8)
    }
}

/// **What the legend lists, and which band it is the legend of.** Written by the track from the same
/// `Content` it draws the band out of (`TimelineTrackView.Coordinator.relayout`), so the legend is what the
/// band draws by construction, and read by the name column — which therefore observes this and nothing the
/// track's drag writes: it changes when a curve appears, goes, is renamed, changes colour or stops being an
/// animation, and not when a node moves.
@MainActor
final class GraphLegend: ObservableObject {
    struct Listing: Equatable {
        let target: KeyframeTarget?
        let entries: [TimelineGraphBand.LegendEntry]
    }

    @Published private(set) var listing = Listing(target: nil, entries: [])

    /// Called from the track's layout, which runs inside a SwiftUI update — so the write is deferred a
    /// turn, and made only when it changes something. Equal on nearly every call, a node drag included.
    func show(_ content: TimelineGraphBand.Content?) {
        let next = Listing(target: content?.target, entries: TimelineGraphBand.legend(of: content))
        guard next != listing else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.listing != next else { return }
            self.listing = next
        }
    }
}

/// **The legend, in the strip of the name column under the layer's name** — the curves the band beside it
/// draws, each named in the colour it is drawn in.
struct GraphLegendView: View {
    let lines: TimelineGraphBand.LegendLines

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.shown, id: \.parameterID) { entry in
                HStack(spacing: 5) {
                    GraphChannelSwatch(colour: entry.colour, isAnimated: entry.isAnimated)
                    Text(entry.name)
                        .font(.caption2)
                        .foregroundColor(Color(uiColor: entry.colour.uiColor(
                            alpha: entry.isAnimated ? 1 : TimelineGraphBand.flatAlpha)))
                        .lineLimit(1)
                }
                .frame(height: TimelineGraphBand.legendLineHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.name)
                .accessibilityIdentifier("timeline.graphLegend.\(entry.parameterID)")
            }
            if lines.more > 0 {
                Text("+\(lines.more) more")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .frame(height: TimelineGraphBand.legendLineHeight)
                    .accessibilityIdentifier("timeline.graphLegend.more")
            }
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}
