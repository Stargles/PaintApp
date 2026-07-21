import Foundation

/// Tracks the current app version for debugging purposes
struct AppVersion {
    /// The current git commit hash (short form)
    static let current = "c8125aa"
    
    /// A human-readable version string
    static var versionString: String {
        return "v\(current)"
    }
}
