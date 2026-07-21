import SwiftUI
import UIKit

extension Color {
    /// Extracts explicit RGBA components and rebuilds a plain, non-dynamic UIColor, rather than
    /// handing a UIKit API a `UIColor(Color)` conversion resolved through whatever trait collection
    /// happens to be current when this runs (often outside of a SwiftUI body evaluation, so there's no
    /// guarantee it resolves against the same appearance the swatch preview used) — this guarantees the
    /// resulting color always matches exactly what was picked.
    func resolvedUIColor(opacity: Double) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r, green: g, blue: b, alpha: a * CGFloat(opacity))
    }
}
